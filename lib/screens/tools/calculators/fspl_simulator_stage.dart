// FsplStage: the plot half of the Wi-Fi Lab FSPL Simulator.
//
// The stage is the chart and everything that belongs to reading it: the view
// and distance-range toggles, the plot, its legend, and the cursor (drag or
// tap on the plot; a slider under it for keyboard and screen-reader users).
// It takes an FsplSimModel and knows nothing about the controls, so a screen
// can place it above the controls (phone), beside them (desktop) or full
// screen beside them (the presenter layout).
//
// PRESENTER (lib/widgets/presenter/): inside a PresenterLayout the plot
// fills the stage's height and the numbers the lesson is about stand beside
// it: received power per band at the cursor, in headline type, over the Why
// bars (spreading vs aperture). Strokes, markers and painted labels follow
// PresenterMode.scaleOf.
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
import '../../../widgets/presenter/presenter_mode.dart';
import 'fspl_simulator_chart.dart';
import 'fspl_simulator_model.dart';
import 'fspl_simulator_panels.dart';

class FsplStage extends StatelessWidget {
  const FsplStage({super.key, required this.model, required this.chartHeight});

  final FsplSimModel model;

  /// Height of the plot itself. The toggles, legend and cursor slider add to
  /// it. Ignored in presenter mode, where the plot fills the stage.
  final double chartHeight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final List<FsplSeries> series = model.series();
    final ({double min, double max, double step}) yr = model.yRange(series);
    final List<FsplRefLine> refs = model.refLines();
    final FsplMeasuredMark? mark = model.measuredMark();
    final List<WifiBand> bands = model.bands;
    final bool presenter = PresenterMode.isActive(context);

    final Widget chart = _chart(context, series, yr, refs, mark, bands);
    final Widget card = FsplCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _toggles(),
          const SizedBox(height: AppSpacing.xs),
          _caption(context),
          const SizedBox(height: AppSpacing.xxs),
          if (presenter)
            Expanded(child: chart)
          else
            SizedBox(height: chartHeight, child: chart),
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
    if (!presenter) return card;

    // Presenter: the cursor numbers across the top, the plot filling the
    // height under them, and the Why bars beside the plot.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double side = (box.maxWidth * 0.3).clamp(280.0, 420.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            FsplCursorHeadline(model: model),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: card),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: side,
                    // The bars shrink as one piece rather than clip when the
                    // window is short.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: side,
                        child: FsplWhyPanel(model: model, compact: true),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _toggles() {
    return Wrap(
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
    );
  }

  Widget _caption(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      model.view == FsplView.received
          ? 'Received power (dBm) vs distance, log scale'
          : 'Free-space path loss (dB) vs distance, log scale',
      style: text.bodySmall?.copyWith(color: colors.textTertiary),
    );
  }

  Widget _chart(
    BuildContext context,
    List<FsplSeries> series,
    ({double min, double max, double step}) yr,
    List<FsplRefLine> refs,
    FsplMeasuredMark? mark,
    List<WifiBand> bands,
  ) {
    final AppColorScheme colors = context.colors;
    final FsplChartStyle style = _chartStyle(context);
    return Semantics(
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
                padScale: style.scale.text,
              );
              void moveTo(Offset local) {
                if (bands.isEmpty) return;
                model.setCursor(g.distanceAt(local.dx));
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (TapDownDetails d) => moveTo(d.localPosition),
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
                    style: style,
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
    // Painted text does not see MediaQuery's text scale; the presenter scale
    // reaches it here (1.0 outside presenter mode).
    final PresenterScale scale = PresenterMode.scaleOf(context);
    TextStyle up(TextStyle t) =>
        t.copyWith(fontSize: scale.paintFont(t.fontSize ?? AppTextSize.body));
    return FsplChartStyle(
      scale: scale,
      curve: colors.textAccent,
      model: colors.textTertiary,
      grid: colors.border,
      axis: colors.borderStrong,
      refLine: colors.textSecondary,
      cursor: colors.textPrimary,
      measured: colors.textPrimary,
      surface: colors.surface2,
      axisLabel: up(
        mono.inlineCode.copyWith(
          fontSize: AppTextSize.caption,
          color: colors.textTertiary,
        ),
      ),
      refLabel: up(text.labelSmall!.copyWith(color: colors.textSecondary)),
      cursorLabel: up(
        mono.inlineCode.copyWith(
          fontSize: AppTextSize.caption,
          color: colors.surface2,
          fontWeight: FontWeight.w500,
        ),
      ),
      emptyLabel: up(text.bodyMedium!.copyWith(color: colors.textSecondary)),
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
    final double k = PresenterMode.scaleOf(context).marker;
    Widget item(Widget swatch, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(width: 28 * k, height: 14 * k, child: swatch),
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
                  scale: k,
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
                    width: 9 * k,
                    height: 9 * k,
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
