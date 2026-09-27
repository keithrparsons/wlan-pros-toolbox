// RateVsRangeStage: the picture half of the Wi-Fi Classroom Rate vs Range tool.
//
// The top-down ring view and everything that belongs to reading it: the
// caption, the rings with the draggable client, a distance slider for
// keyboard and screen-reader users, the MCS legend (every ring, always
// labeled), and the beacon-airtime bar. It takes a RateVsRangeModel and knows
// nothing about the controls, so a screen can place it above the controls
// (phone), beside them (desktop) or full screen (the presenter layout).
//
// PRESENTER (lib/widgets/presenter/): inside a PresenterLayout the ring view
// fills the stage's height, and what the client reads stands beside it: its
// MCS and rate in headline type, received power, SNR, and whether it can
// still hear beacons, over the beacon-airtime bar. Strokes, markers and
// painted labels follow PresenterMode.scaleOf.
//
// THEME: context.colors (dark §8 / light §8.20) plus RvrPalette, one hue per
// MCS ring under GL-003 §8.15.2. Every ring is also labeled.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/fspl_math.dart';
import '../../../services/wifi_lab/rate_vs_range_math.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'rate_vs_range_model.dart';
import 'rate_vs_range_painter.dart';
import 'rate_vs_range_parts.dart';

class RateVsRangeStage extends StatelessWidget {
  const RateVsRangeStage({
    super.key,
    required this.model,
    required this.stageHeight,
  });

  final RateVsRangeModel model;

  /// Height of the ring view itself. The caption, slider, legend and bar add
  /// to it. Ignored in presenter mode, where the rings fill the stage.
  final double stageHeight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final List<RvrRing> rings = model.rings;
    final RvrClientReading client = model.client;
    final bool presenter = PresenterMode.isActive(context);

    final Widget view = Semantics(
      label: _semantics(rings, client),
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: ColoredBox(
          color: colors.surface2,
          child: _rings(context, rings, client),
        ),
      ),
    );
    final Widget card = RvrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Top-down view, ${model.band.label}, ${model.widthMHz} MHz, '
            '${model.streams} ${model.streams == 1 ? 'stream' : 'streams'}. '
            'Drag the client dot.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (presenter)
            Expanded(child: view)
          else
            SizedBox(height: stageHeight, child: view),
          const SizedBox(height: AppSpacing.xxs),
          _distanceSlider(context),
          const SizedBox(height: AppSpacing.xxs),
          _legend(context, rings),
          if (!presenter) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _beaconBar(context),
          ],
        ],
      ),
    );
    if (!presenter) return card;

    // Presenter: the rings take the height; what the client reads and the
    // beacon bar stand beside them.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double side = (box.maxWidth * 0.36).clamp(300.0, 480.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: card),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: side,
              // Shrinks as one piece rather than clip in a short window.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: side,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _clientHeadline(context, client),
                      const SizedBox(height: AppSpacing.sm),
                      RvrCard(child: _beaconBar(context)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Presenter stage: the client's MCS and rate in headline type, with the
  /// numbers that decide it.
  Widget _clientHeadline(BuildContext context, RvrClientReading c) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final String Function(double, [int]) n = RvrFormat.n;

    Widget value(String label, String v) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: text.labelSmall?.copyWith(color: colors.textTertiary),
        ),
        Text(v, style: mono.inlineCode.copyWith(color: colors.textPrimary)),
      ],
    );

    return RvrCard(
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            RvrSectionLabel('Client at ${model.dist(c.distanceM)}'),
            const SizedBox(height: AppSpacing.xxs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                c.mcs == null ? 'Below MCS 0' : 'MCS ${c.mcs}',
                style: scale
                    .headlineStyle(mono.outputLarge)
                    .copyWith(color: colors.textAccent),
              ),
            ),
            if (c.mcs != null)
              Text(
                RvrFormat.rate(c.rateMbps),
                style: mono.outputMedium.copyWith(color: colors.textAccent),
              ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                value('Received', '${n(c.receivedDbm)} dBm'),
                value('SNR', '${n(c.snrDb)} dB'),
                value('Noise floor', '${n(c.noiseFloorDbm)} dBm'),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              c.insideCell
                  ? 'Inside the cell: hears ${model.basicRate.label} '
                        'beacons.'
                  : 'Outside the cell: too weak for '
                        '${model.basicRate.label} beacons.',
              style: text.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  String _semantics(List<RvrRing> rings, RvrClientReading c) {
    final String radii = rings
        .map((RvrRing r) => 'MCS ${r.mcs} ${model.dist(r.radiusM)}')
        .join(', ');
    final String at = c.mcs == null
        ? 'below MCS 0'
        : 'MCS ${c.mcs}, ${RvrFormat.rate(c.rateMbps)}';
    return 'Coverage rings around the AP at ${model.widthMHz} MHz: $radii. '
        'Cell edge at ${model.basicRate.label} basic rate '
        '${model.dist(model.cellEdgeM)}. Client at '
        '${model.dist(c.distanceM)}: ${RvrFormat.n(c.receivedDbm)} dBm, '
        '$at.';
  }

  RvrStageStyle _style(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    // Painted text does not see MediaQuery's text scale; the presenter scale
    // reaches it here (1.0 outside presenter mode).
    final PresenterScale scale = PresenterMode.scaleOf(context);
    TextStyle up(TextStyle t) =>
        t.copyWith(fontSize: scale.paintFont(t.fontSize ?? AppTextSize.body));
    return RvrStageStyle(
      scale: scale,
      surface: colors.surface2,
      grid: colors.textTertiary,
      edge: colors.textPrimary,
      client: colors.textPrimary,
      clientRim: colors.surface2,
      ap: colors.textPrimary,
      gridLabel: up(
        mono.inlineCode.copyWith(
          fontSize: AppTextSize.caption,
          color: colors.textTertiary,
        ),
      ),
      ringLabel: up(
        mono.inlineCode.copyWith(
          fontSize: AppTextSize.caption,
          color: colors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      edgeLabel: up(text.labelSmall!.copyWith(color: colors.textPrimary)),
      clientLabel: up(
        text.labelSmall!.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _rings(BuildContext context, List<RvrRing> rings, RvrClientReading c) {
    final AppColorScheme colors = context.colors;
    final double range = model.viewRangeM;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final Size size = Size(box.maxWidth, box.maxHeight);
        final RvrStageGeometry g = RvrStageGeometry(size: size, rangeM: range);
        void place(Offset local) {
          final ({double distanceM, double angle}) p = g.polarAt(local);
          model.setClientPolar(p.distanceM, p.angle);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (TapDownDetails d) => place(d.localPosition),
          // Vertical and horizontal drag recognizers, not pan: pan needs
          // twice the touch slop, so on a phone the page's vertical scroll
          // would win every mostly-vertical drag and the dot would not move.
          onVerticalDragStart: (DragStartDetails d) => place(d.localPosition),
          onVerticalDragUpdate: (DragUpdateDetails d) => place(d.localPosition),
          onHorizontalDragStart: (DragStartDetails d) => place(d.localPosition),
          onHorizontalDragUpdate: (DragUpdateDetails d) =>
              place(d.localPosition),
          child: CustomPaint(
            size: size,
            painter: RvrStagePainter(
              units: model.units,
              rangeM: range,
              rings: <RvrPaintRing>[
                for (final RvrRing r in rings)
                  RvrPaintRing(
                    mcs: r.mcs,
                    radiusM: r.radiusM,
                    color: RvrPalette.of(r.mcs, colors),
                  ),
              ],
              cellEdgeM: model.cellEdgeM,
              cellEdgeLabel: 'Cell edge, ${model.basicRate.label} beacons',
              clientDistanceM: c.distanceM,
              clientAngle: model.clientAngle,
              clientLabel: c.mcs == null
                  ? 'Below MCS 0'
                  : 'MCS ${c.mcs}, ${RvrFormat.rate(c.rateMbps)}',
              highlightMcs: c.mcs,
              style: _style(context),
              revision: model.revision,
            ),
          ),
        );
      },
    );
  }

  Widget _distanceSlider(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final double maxLog = FsplMath.log10(model.viewRangeM);
    return Row(
      children: <Widget>[
        ExcludeSemantics(
          child: Text(
            'Client',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ),
        Expanded(
          child: Slider(
            value: FsplMath.log10(model.clientDistanceM).clamp(0, maxLog),
            min: 0,
            max: maxLog,
            divisions: 200,
            onChanged: (double v) =>
                model.setClientDistance(math.pow(10, v).toDouble()),
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            label: model.dist(model.clientDistanceM),
            semanticFormatterCallback: (double v) =>
                'Client distance ${model.dist(math.pow(10, v).toDouble())}',
          ),
        ),
        ExcludeSemantics(
          child: SizedBox(
            width: 72 * PresenterMode.scaleOf(context).text,
            child: Text(
              model.dist(model.clientDistanceM),
              textAlign: TextAlign.right,
              style: mono.inlineCode.copyWith(color: colors.textPrimary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _legend(BuildContext context, List<RvrRing> rings) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final int? at = model.client.mcs;
    return ExcludeSemantics(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          for (final RvrRing r in rings)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                RvrSwatch(mcs: r.mcs),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  'MCS ${r.mcs}: ${RvrFormat.rate(r.rateMbps)}, '
                  '${model.dist(r.radiusM)}',
                  style: text.bodySmall?.copyWith(
                    color: r.mcs == at
                        ? colors.textPrimary
                        : colors.textSecondary,
                    fontWeight: r.mcs == at ? FontWeight.w600 : null,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _beaconBar(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final double now = model.beaconPercent;
    final double at6 = model.beaconPercentAt6;
    final double frac = at6 <= 0 ? 0 : (now / at6).clamp(0.0, 1.0);
    final String label =
        'Beacons use ${RvrFormat.pct(now)} of airtime: ${model.ssids} '
        '${model.ssids == 1 ? 'SSID' : 'SSIDs'} at ${model.basicRate.label}. '
        'The whole bar is the same beacons at 6 Mbps, '
        '${RvrFormat.pct(at6)}.';
    final String rateNote = model.basicRate.isSourcedDirectly
        ? 'same floor as MCS 0'
        : 'MCS-equivalent floor (MCS ${model.basicRate.equivalentMcs})';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          label: label,
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                label,
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xxs),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: SizedBox(
                  height: 12 * PresenterMode.scaleOf(context).marker,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surface2,
                          border: Border.all(color: colors.borderStrong),
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                        ),
                      ),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: frac,
                        child: ColoredBox(
                          color: RvrPalette.of(
                            model.basicRate.equivalentMcs,
                            colors,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Minimum basic rate ${model.basicRate.label}, $rateNote: cell '
          'edge ${RvrFormat.n(model.cellEdgeDbm, 0)} dBm at '
          '${model.dist(model.cellEdgeM)}'
          '${model.basicRate == RvrBasicRate.mbps6 ? '' : ' (6 Mbps: ${model.dist(model.cellEdge6M)})'}.',
          style: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}
