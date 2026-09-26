// UplinkDownlinkStage: the picture half of the Wi-Fi Classroom Uplink vs
// Downlink tool.
//
// The top-down floor and everything that belongs to reading it: the caption,
// the two rings with the asymmetry zone and the draggable client, a distance
// slider for keyboard and screen-reader users, and the legend. It takes an
// UplinkDownlinkController and knows nothing about the controls, so a screen
// can place it above the controls (phone), beside them (desktop) or full
// screen (the presenter layout).
//
// PRESENTER (lib/widgets/presenter/): the floor fills the stage's height, and
// both directions' numbers stand beside it in headline type, over the
// predict-then-reveal card, so the instructor can ask the question and show
// the answer without touching the controls. Strokes, markers and painted
// labels follow PresenterMode.scaleOf.
//
// THEME: context.colors (dark §8 / light §8.20), direction hues from
// UdPalette (§8.15.2), the zone in the accent. Every line is labeled.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/fspl_math.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'uplink_downlink_controller.dart';
import 'uplink_downlink_painter.dart';
import 'uplink_downlink_parts.dart';
import 'uplink_downlink_readouts.dart';

class UplinkDownlinkStage extends StatelessWidget {
  const UplinkDownlinkStage({
    super.key,
    required this.controller,
    required this.stageHeight,
  });

  final UplinkDownlinkController controller;

  /// Height of the floor view itself. The caption, slider and legend add to
  /// it. Ignored in presenter mode, where the floor fills the stage.
  final double stageHeight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final UdConfig c = controller.config;
    final bool presenter = PresenterMode.isActive(context);

    final Widget view = Semantics(
      label: _semantics(c),
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: ColoredBox(color: colors.surface2, child: _floor(context, c)),
      ),
    );
    final Widget card = UdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Top-down view, ${c.band.label}, ${c.widthMHz} MHz. Each ring is '
            'where one end can still decode the other at the lowest '
            'modulation and coding scheme (MCS 0). Drag the client dot.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (presenter)
            Expanded(child: view)
          else
            SizedBox(height: stageHeight, child: view),
          const SizedBox(height: AppSpacing.xxs),
          _distanceSlider(context, c),
          const SizedBox(height: AppSpacing.xxs),
          _legend(context, c),
        ],
      ),
    );
    if (!presenter) return card;

    // Presenter: the floor takes the height; both directions and the
    // prediction stand beside it.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double side = (box.maxWidth * 0.40).clamp(340.0, 520.0);
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
                      UplinkDownlinkReadouts(
                        controller: controller,
                        compact: true,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      UplinkDownlinkPredict(controller: controller),
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

  String _semantics(UdConfig c) {
    final UdDirection dl = c.downlink;
    final UdDirection ul = c.uplink;
    return 'Top-down view. The client can decode the AP out to '
        '${UdFormat.dist(c.downlinkRingM)}; the AP can decode the client out '
        'to ${UdFormat.dist(c.uplinkRingM)}. Client at '
        '${UdFormat.dist(c.clientDistanceM)}: downlink, AP to client, '
        '${UdFormat.dbm(dl.rssiDbm)}, ${UdFormat.mcs(dl.mcs)}; uplink, client '
        'to AP, ${UdFormat.dbm(ul.rssiDbm)}, ${UdFormat.mcs(ul.mcs)}.';
  }

  UdStageStyle _style(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    // Painted text does not see MediaQuery's text scale; the presenter scale
    // reaches it here (1.0 outside presenter mode).
    final PresenterScale scale = PresenterMode.scaleOf(context);
    TextStyle up(TextStyle t) =>
        t.copyWith(fontSize: scale.paintFont(t.fontSize ?? AppTextSize.body));
    return UdStageStyle(
      scale: scale,
      surface: colors.surface2,
      grid: colors.textTertiary,
      ink: colors.textPrimary,
      down: UdPalette.of(UdDir.downlink, colors),
      up: UdPalette.of(UdDir.uplink, colors),
      zone: colors.primary,
      gridLabel: up(
        mono.inlineCode.copyWith(
          fontSize: AppTextSize.caption,
          color: colors.textTertiary,
        ),
      ),
      label: up(
        text.labelSmall!.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _floor(BuildContext context, UdConfig c) {
    final double range = controller.viewRangeM;
    final UdDirection dl = c.downlink;
    final UdDirection ul = c.uplink;
    final bool downBigger = c.downlinkRingM >= c.uplinkRingM;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final Size size = Size(box.maxWidth, box.maxHeight);
        final RvrStageGeometry g = RvrStageGeometry(size: size, rangeM: range);
        void place(Offset local) {
          final ({double distanceM, double angle}) p = g.polarAt(local);
          controller.setClientPolar(p.distanceM, p.angle);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (TapDownDetails d) => place(d.localPosition),
          // Vertical and horizontal drag recognizers, not pan: pan needs
          // twice the touch slop, so a page scroll would win on a phone.
          onVerticalDragStart: (DragStartDetails d) => place(d.localPosition),
          onVerticalDragUpdate: (DragUpdateDetails d) => place(d.localPosition),
          onHorizontalDragStart: (DragStartDetails d) => place(d.localPosition),
          onHorizontalDragUpdate: (DragUpdateDetails d) =>
              place(d.localPosition),
          child: CustomPaint(
            size: size,
            painter: UdStagePainter(
              rangeM: range,
              downRingM: c.downlinkRingM,
              upRingM: c.uplinkRingM,
              clientDistanceM: c.clientDistanceM,
              clientAngle: controller.clientAngle,
              downLabel:
                  'Downlink ${UdFormat.dbm(dl.rssiDbm)}, '
                  '${UdFormat.mcs(dl.mcs)}',
              upLabel:
                  'Uplink ${UdFormat.dbm(ul.rssiDbm)}, '
                  '${UdFormat.mcs(ul.mcs)}',
              downRingLabel: 'Client decodes AP',
              upRingLabel: 'AP decodes client',
              zoneLabel: c.zoneMiddleM == null
                  ? null
                  : downBigger
                  ? 'Only the client decodes'
                  : 'Only the AP decodes',
              zoneAlpha: kUdZoneAlpha,
              style: _style(context),
              revision: controller.revision,
            ),
          ),
        );
      },
    );
  }

  Widget _distanceSlider(BuildContext context, UdConfig c) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final double maxLog = FsplMath.log10(controller.viewRangeM);
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
            value: FsplMath.log10(c.clientDistanceM).clamp(0, maxLog),
            min: 0,
            max: maxLog,
            divisions: 200,
            onChanged: (double v) =>
                controller.setClientDistance(math.pow(10, v).toDouble()),
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            label: UdFormat.dist(c.clientDistanceM),
            semanticFormatterCallback: (double v) =>
                'Client distance ${UdFormat.dist(math.pow(10, v).toDouble())}',
          ),
        ),
        ExcludeSemantics(
          child: SizedBox(
            width: 72 * PresenterMode.scaleOf(context).text,
            child: Text(
              UdFormat.dist(c.clientDistanceM),
              textAlign: TextAlign.right,
              style: mono.inlineCode.copyWith(color: colors.textPrimary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _legend(BuildContext context, UdConfig c) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    TextStyle? st() => text.bodySmall?.copyWith(color: colors.textSecondary);
    Widget row(Widget swatch, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        swatch,
        const SizedBox(width: AppSpacing.xxs),
        Flexible(child: Text(label, style: st())),
      ],
    );
    return ExcludeSemantics(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          row(
            const UdLineSwatch(dir: UdDir.downlink),
            'Solid: downlink, AP to client. Client decodes AP to '
            '${UdFormat.dist(c.downlinkRingM)}',
          ),
          row(
            const UdLineSwatch(dir: UdDir.uplink),
            'Dashed: uplink, client to AP. AP decodes client to '
            '${UdFormat.dist(c.uplinkRingM)}',
          ),
          row(
            const UdZoneSwatch(),
            'Asymmetry zone, ${UdFormat.dist(c.asymmetryZoneM)} wide',
          ),
        ],
      ),
    );
  }
}
