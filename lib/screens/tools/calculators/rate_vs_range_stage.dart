// RateVsRangeStage: the picture half of the Wi-Fi Lab Rate vs Range tool.
//
// The top-down ring view and everything that belongs to reading it: the
// caption, the rings with the draggable client, a distance slider for
// keyboard and screen-reader users, the MCS legend (every ring, always
// labeled), and the beacon-airtime bar. It takes a RateVsRangeModel and knows
// nothing about the controls, so a screen can place it above the controls
// (phone), beside them (desktop) or full screen (a future presenter layout).
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
  /// to it. A presenter layout passes whatever the projector leaves.
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

    return RvrCard(
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
          SizedBox(
            height: stageHeight,
            child: Semantics(
              label: _semantics(rings, client),
              excludeSemantics: true,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: ColoredBox(
                  color: colors.surface2,
                  child: _rings(context, rings, client),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          _distanceSlider(context),
          const SizedBox(height: AppSpacing.xxs),
          _legend(context, rings),
          const SizedBox(height: AppSpacing.sm),
          _beaconBar(context),
        ],
      ),
    );
  }

  String _semantics(List<RvrRing> rings, RvrClientReading c) {
    final String radii = rings
        .map((RvrRing r) => 'MCS ${r.mcs} ${RvrFormat.dist(r.radiusM)}')
        .join(', ');
    final String at = c.mcs == null
        ? 'below MCS 0'
        : 'MCS ${c.mcs}, ${RvrFormat.rate(c.rateMbps)}';
    return 'Coverage rings around the AP at ${model.widthMHz} MHz: $radii. '
        'Cell edge at ${model.basicRate.label} basic rate '
        '${RvrFormat.dist(model.cellEdgeM)}. Client at '
        '${RvrFormat.dist(c.distanceM)}: ${RvrFormat.n(c.receivedDbm)} dBm, '
        '$at.';
  }

  RvrStageStyle _style(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return RvrStageStyle(
      surface: colors.surface2,
      grid: colors.textTertiary,
      edge: colors.textPrimary,
      client: colors.textPrimary,
      clientRim: colors.surface2,
      ap: colors.textPrimary,
      gridLabel: mono.inlineCode.copyWith(
        fontSize: AppTextSize.caption,
        color: colors.textTertiary,
      ),
      ringLabel: mono.inlineCode.copyWith(
        fontSize: AppTextSize.caption,
        color: colors.textPrimary,
        fontWeight: FontWeight.w500,
      ),
      edgeLabel: text.labelSmall!.copyWith(color: colors.textPrimary),
      clientLabel: text.labelSmall!.copyWith(
        color: colors.textPrimary,
        fontWeight: FontWeight.w600,
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
            label: RvrFormat.dist(model.clientDistanceM),
            semanticFormatterCallback: (double v) =>
                'Client distance ${RvrFormat.dist(math.pow(10, v).toDouble())}',
          ),
        ),
        ExcludeSemantics(
          child: SizedBox(
            width: 72,
            child: Text(
              RvrFormat.dist(model.clientDistanceM),
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
                  '${RvrFormat.dist(r.radiusM)}',
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
                  height: 12,
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
          '${RvrFormat.dist(model.cellEdgeM)}'
          '${model.basicRate == RvrBasicRate.mbps6 ? '' : ' (6 Mbps: ${RvrFormat.dist(model.cellEdge6M)})'}.',
          style: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}
