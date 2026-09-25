// FsplStage: the plot half of the Wi-Fi Lab FSPL Simulator.
//
// The stage is the chart and everything that belongs to reading it: the view
// and distance-range toggles, the plot, its legend, and the cursor (drag or
// tap on the plot; a slider under it for keyboard and screen-reader users).
// It takes an FsplSimModel and knows nothing about the controls, so a screen
// can place it above the controls (phone), beside them (desktop) or full
// screen beside them (a future presenter layout).
//
// THEME: context.colors only (dark §8 / light §8.20). Curves lime, told apart
// by stroke and marker shape (GL-003 §8.15, no categorical palette).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/fspl_math.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_toggle.dart';
import 'fspl_simulator_chart.dart';
import 'fspl_simulator_model.dart';
import 'fspl_simulator_panels.dart';

class FsplStage extends StatelessWidget {
  const FsplStage({super.key, required this.model, required this.chartHeight});

  final FsplSimModel model;

  /// Height of the plot itself. The toggles, legend and cursor slider add to
  /// it. A presenter layout passes whatever the projector leaves.
  final double chartHeight;

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
    final List<FsplSeries> series = model.series();
    final ({double min, double max, double step}) yr = model.yRange(series);
    final List<FsplRefLine> refs = model.refLines();
    final FsplMeasuredMark? mark = model.measuredMark();
    final List<WifiBand> bands = model.bands;

    return FsplCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              AppToggle<FsplView>(
                semanticLabel: 'Chart shows',
                value: model.view,
                items: const <AppToggleItem<FsplView>>[
                  (FsplView.received, 'Received'),
                  (FsplView.pathLoss, 'Path loss'),
                ],
                onChanged: model.setView,
              ),
              AppToggle<FsplRange>(
                semanticLabel: 'Distance axis',
                value: model.range,
                items: <AppToggleItem<FsplRange>>[
                  for (final FsplRange r in FsplRange.values) (r, r.label),
                ],
                onChanged: model.setRange,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            model.view == FsplView.received
                ? 'Received power (dBm) vs distance, log scale'
                : 'Free-space path loss (dB) vs distance, log scale',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          SizedBox(
            height: chartHeight,
            child: Semantics(
              label: _semantics(),
              excludeSemantics: true,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: ColoredBox(
                  color: colors.surface2,
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints c) {
                      final Size size = Size(c.maxWidth, c.maxHeight);
                      final FsplChartGeometry g = FsplChartGeometry(
                        size: size,
                        maxDistanceM: model.range.maxM,
                        yMin: yr.min,
                        yMax: yr.max,
                      );
                      void moveTo(Offset local) {
                        if (bands.isEmpty) return;
                        model.setCursor(g.distanceAt(local.dx));
                      }

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (TapDownDetails d) =>
                            moveTo(d.localPosition),
                        onHorizontalDragStart: (DragStartDetails d) =>
                            moveTo(d.localPosition),
                        onHorizontalDragUpdate: (DragUpdateDetails d) =>
                            moveTo(d.localPosition),
                        child: CustomPaint(
                          size: size,
                          painter: FsplChartPainter(
                            maxDistanceM: model.range.maxM,
                            yMin: yr.min,
                            yMax: yr.max,
                            yStep: yr.step,
                            series: series,
                            refLines: refs,
                            cursorDistanceM: model.cursorM,
                            cursorLabel: FsplFormat.dist(model.cursorM),
                            measured: mark,
                            style: _chartStyle(context),
                            revision: model.revision,
                            emptyMessage: bands.isEmpty
                                ? 'Turn on a band to draw its curve.'
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _legend(
            context,
            showRefs: refs.isNotEmpty && bands.isNotEmpty,
            showMeasured: mark != null,
          ),
          const SizedBox(height: AppSpacing.xxs),
          _cursorSlider(context),
        ],
      ),
    );
  }

  String _semantics() {
    final String what = model.view == FsplView.received
        ? 'Received power in dBm'
        : 'Free-space path loss in dB';
    if (model.bands.isEmpty) {
      return '$what against distance. No band is on; turn one on to draw '
          'its curve.';
    }
    final String at = model.bands
        .map(
          (WifiBand b) =>
              '${b.label} ${FsplFormat.n(model.y(model.pathLoss(b, model.cursorM)))} '
              '${model.unit}',
        )
        .join(', ');
    return '$what against distance, 1 m to ${model.range.label}, log scale. '
        'Cursor at ${FsplFormat.dist(model.cursorM)}: $at.';
  }

  FsplChartStyle _chartStyle(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return FsplChartStyle(
      curve: colors.textAccent,
      model: colors.textTertiary,
      grid: colors.border,
      axis: colors.borderStrong,
      refLine: colors.textSecondary,
      cursor: colors.textPrimary,
      measured: colors.textPrimary,
      surface: colors.surface2,
      axisLabel: mono.inlineCode.copyWith(
        fontSize: AppTextSize.caption,
        color: colors.textTertiary,
      ),
      refLabel: text.labelSmall!.copyWith(color: colors.textSecondary),
      cursorLabel: mono.inlineCode.copyWith(
        fontSize: AppTextSize.caption,
        color: colors.surface2,
        fontWeight: FontWeight.w500,
      ),
      emptyLabel: text.bodyMedium!.copyWith(color: colors.textSecondary),
    );
  }

  Widget _cursorSlider(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final double maxLg = FsplMath.log10(model.range.maxM);
    return Row(
      children: <Widget>[
        ExcludeSemantics(
          child: Text(
            'Cursor',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ),
        Expanded(
          child: Slider(
            value: FsplMath.log10(model.cursorM).clamp(0.0, maxLg),
            min: 0,
            max: maxLg,
            divisions: (maxLg * 50).round(),
            onChanged: model.bands.isEmpty
                ? null
                : (double v) => model.setCursor(math.pow(10, v).toDouble()),
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            label: FsplFormat.dist(model.cursorM),
            semanticFormatterCallback: (double v) =>
                'Cursor distance ${FsplFormat.dist(math.pow(10, v).toDouble())}',
          ),
        ),
      ],
    );
  }

  Widget _legend(
    BuildContext context, {
    required bool showRefs,
    required bool showMeasured,
  }) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    Widget item(Widget swatch, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(width: 28, height: 14, child: swatch),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: text.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
    return ExcludeSemantics(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          for (final WifiBand b in model.bands)
            item(FsplBandSample(band: b), '${b.label} ch ${model.channel(b)}'),
          if (model.indoor && model.bands.isNotEmpty)
            item(
              FsplBandSample(band: model.bands.first, model: true),
              'Indoor model, n = ${FsplFormat.n(model.exponent)}',
            ),
          if (showRefs)
            item(
              CustomPaint(
                painter: FsplStrokeSamplePainter(
                  stroke: CurveStroke.dashed,
                  marker: null,
                  color: colors.textSecondary,
                  surface: colors.surface1,
                  model: true,
                ),
              ),
              'Design target',
            ),
          if (showMeasured)
            item(
              Center(
                child: Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(
                    width: 9,
                    height: 9,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              'Measured',
            ),
        ],
      ),
    );
  }
}
