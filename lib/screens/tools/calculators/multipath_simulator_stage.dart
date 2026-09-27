// MultipathStage: the pictures half of the Multipath Simulator.
//
// Scene (one wall / standing wave), phasor diagram, power-vs-position plot,
// and the many-path histogram, each with its legend. Takes the shared
// MultipathController and nothing else, so a phone layout can stack it with
// MultipathControls and a presenter layout can put the two side by side.
// Dragging the scene or the plot moves the receiver through the controller;
// the sliders in MultipathControls do the same thing for keyboard users.
//
// PRESENTER (lib/widgets/presenter/): inside a PresenterLayout the pictures
// fill the stage with no scroll. Two-path scenes put the scene beside the
// arrows, with the received level in headline type over the arrows, and the
// power plot under both. Many paths puts the plot beside the arrows and the
// histogram beside the two-antenna fade figures. Strokes, markers and
// painted labels follow PresenterMode.scaleOf.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/multipath_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';
import 'multipath_simulator_controller.dart';
import 'multipath_simulator_painters.dart';
import 'multipath_simulator_parts.dart';

typedef _C = MultipathController;

class MultipathStage extends StatelessWidget {
  const MultipathStage({super.key, required this.controller});

  final MultipathController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final MultipathPaintStyle style = _paintStyle(context);
        final bool many = controller.isManyPaths;
        if (PresenterMode.isActive(context)) {
          return _presenter(context, style, many);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (!many) ...<Widget>[
              _SceneCard(controller: controller, style: style),
              const SizedBox(height: AppSpacing.sm),
            ],
            _PhasorCard(controller: controller, style: style),
            const SizedBox(height: AppSpacing.sm),
            _PlotCard(controller: controller, style: style),
            if (many) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              _HistogramCard(controller: controller, style: style),
            ],
          ],
        );
      },
    );
  }

  /// Presenter: every picture in a bounded box, no scroll.
  Widget _presenter(
    BuildContext context,
    MultipathPaintStyle style,
    bool many,
  ) {
    final MultipathController c = controller;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double side = (box.maxWidth * 0.36).clamp(300.0, 480.0);
        Widget row(Widget main, Widget aside) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: main),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(width: side, child: aside),
          ],
        );
        final Widget phasors = _PhasorCard(
          controller: c,
          style: style,
          presenter: true,
        );
        if (!many) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                flex: 11,
                child: row(
                  _SceneCard(controller: c, style: style, presenter: true),
                  phasors,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                flex: 9,
                child: _PlotCard(controller: c, style: style, presenter: true),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              flex: 11,
              child: row(
                _PlotCard(controller: c, style: style, presenter: true),
                phasors,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              flex: 9,
              child: row(
                _HistogramCard(controller: c, style: style, presenter: true),
                _FadeCard(controller: c),
              ),
            ),
          ],
        );
      },
    );
  }

  static MultipathPaintStyle _paintStyle(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    // Painted text does not see MediaQuery's text scale; the presenter scale
    // reaches it here (1.0 outside presenter mode).
    final PresenterScale scale = PresenterMode.scaleOf(context);
    return MultipathPaintStyle(
      scale: scale,
      accent: colors.textAccent,
      primary: colors.textPrimary,
      secondary: colors.textSecondary,
      tertiary: colors.textTertiary,
      grid: colors.border,
      axis: colors.borderStrong,
      wall: colors.borderStrong,
      labelStyle: mono.inlineCode.copyWith(
        fontSize: scale.paintFont(AppTextSize.caption - 2),
        color: colors.textSecondary,
      ),
      units: UnitSystemScope.systemOf(context),
    );
  }
}

/// In presenter mode [child] takes the rest of its card's height.
Widget _fill(bool presenter, Widget child) =>
    presenter ? Expanded(child: child) : child;

/// Presenter stage, many paths: how often each antenna, and both at once,
/// sit more than 10 dB down. "Both at once" is the lesson, in headline type.
class _FadeCard extends StatelessWidget {
  const _FadeCard({required this.controller});

  final MultipathController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final FadeStats f = controller.fade;
    return MpCard(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: box.maxWidth,
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const MpSectionLabel('Two antennas: time below -10 dB'),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Both at once',
                    style: text.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  Text(
                    _C.pct(f.fractionBoth),
                    style: scale
                        .headlineStyle(mono.outputLarge)
                        .copyWith(color: colors.textAccent),
                  ),
                  MpRow(label: 'Antenna A', value: _C.pct(f.fractionA)),
                  MpRow(label: 'Antenna B', value: _C.pct(f.fractionB)),
                  const MpRow(label: 'Rayleigh, one', value: '9.5%'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A plot surface: surface-2, rounded, labelled for screen readers, with an
/// optional drag-to-move handler that gets the local x and the size.
class _PlotSurface extends StatelessWidget {
  const _PlotSurface({
    this.height,
    required this.semantic,
    required this.painter,
    this.onDrag,
    this.verticalPadding = 0,
  });

  /// Null fills the parent's bounded height (the presenter stage).
  final double? height;
  final String semantic;
  final CustomPainter Function(Size size) painter;
  final void Function(double dx, Size size)? onDrag;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Semantics(
      label: semantic,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(
          height: height,
          color: colors.surface2,
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final Size size = Size(c.maxWidth, c.maxHeight);
              final Widget paint = CustomPaint(
                size: size,
                painter: painter(size),
              );
              final void Function(double, Size)? drag = onDrag;
              if (drag == null) return paint;
              return MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (TapDownDetails e) =>
                      drag(e.localPosition.dx, size),
                  onHorizontalDragUpdate: (DragUpdateDetails e) =>
                      drag(e.localPosition.dx, size),
                  child: paint,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Scene (modes 1 and 2) ───────────────────────────────────────────────────

class _SceneCard extends StatelessWidget {
  const _SceneCard({
    required this.controller,
    required this.style,
    this.presenter = false,
  });

  final MultipathController controller;
  final MultipathPaintStyle style;

  /// Fill a bounded box: the picture takes the height.
  final bool presenter;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final MultipathController c = controller;
    final bool one = c.mode == MultipathMode.oneWall;
    final List<double> nulls = one ? const <double>[] : c.nulls;
    final String semantic = one
        ? 'Scene seen from above: a wall along the top, the access point on '
              'the left, and the receiver ${_C.len(c.trackOffset, UnitSystemScope.systemOf(context), 0)} along a '
              '${_C.dist(1, UnitSystemScope.systemOf(context))} track. The '
              'direct ray goes straight across; the reflected '
              'ray bounces off the wall.'
        : 'Scene: a wall on the left, the receiver '
              '${_C.len(c.wallDistance, UnitSystemScope.systemOf(context))} in front of it, and the signal '
              'arriving from an access point '
              '${_C.dist(10, UnitSystemScope.systemOf(context))} away. '
              '${nulls.length} '
              'nulls are marked along the floor.';
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MpSectionLabel(one ? 'Seen from above' : 'Walking toward the wall'),
          const SizedBox(height: AppSpacing.xs),
          _fill(
            presenter,
            _PlotSurface(
              height: presenter ? null : 170,
              semantic: semantic,
              painter: (Size size) => one
                  ? TwoRayScenePainter(
                      scene: MultipathController.twoRay,
                      t: c.trackOffset,
                      style: style,
                    )
                  : StandingWaveScenePainter(
                      range: MultipathController.standing.range,
                      distance: c.wallDistance,
                      nulls: nulls,
                      style: style,
                    ),
              onDrag: (double dx, Size size) {
                if (one) {
                  c.trackOffset = TwoRayScenePainter.trackOffsetAt(
                    dx,
                    MultipathController.twoRay,
                    size,
                  );
                } else {
                  c.wallDistance = StandingWaveScenePainter.distanceAt(
                    dx,
                    MultipathController.standing.range,
                    size,
                  );
                }
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          MpLegend(
            items: <MpLegendItem>[
              MpLegendItem.line(
                color: colors.textSecondary,
                width: 2,
                label: 'Direct',
              ),
              MpLegendItem.line(
                color: colors.textSecondary,
                width: 2,
                dashed: true,
                label: 'Reflected',
              ),
              MpLegendItem(
                swatch: Container(
                  width: 10,
                  height: 14,
                  color: colors.textAccent,
                ),
                label: 'Receiver (drag it)',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Phasors ─────────────────────────────────────────────────────────────────

class _PhasorCard extends StatelessWidget {
  const _PhasorCard({
    required this.controller,
    required this.style,
    this.presenter = false,
  });

  final MultipathController controller;
  final MultipathPaintStyle style;

  /// Fill a bounded box, with the received level in headline type over the
  /// arrows (the number the lesson is about).
  final bool presenter;

  Widget _headline(BuildContext context, bool many, double db) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            many
                ? 'Antenna A, against the average'
                : 'Received, against the direct copy alone',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _C.db(db),
              style: PresenterMode.scaleOf(context)
                  .headlineStyle(mono.outputLarge)
                  .copyWith(color: colors.textAccent),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final MultipathController c = controller;
    final bool many = c.isManyPaths;
    final List<Complex> ph = c.phasors;
    final double db = c.receivedDb;
    final String semantic = many
        ? '${ph.length} arrows, one per reflected copy, drawn head to tail. '
              'Their sum is ${_C.db(db)} against the average.'
        : 'Two arrows head to tail: the direct copy pointing right, and the '
              'reflected copy at ${_C.deg(ph[1])} with length '
              '${ph[1].abs.toStringAsFixed(2)}. Their sum is ${_C.db(db)} '
              'against the direct copy alone.';
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MpSectionLabel('The copies add as arrows'),
          if (presenter) _headline(context, many, db),
          const SizedBox(height: AppSpacing.xs),
          _fill(
            presenter,
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: presenter ? 1e4 : 360),
                child: AspectRatio(
                  aspectRatio: 1.3,
                  child: Semantics(
                    label: semantic,
                    excludeSemantics: true,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      child: ColoredBox(
                        color: colors.surface2,
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: PhasorPainter(
                            phasors: ph,
                            style: style,
                            showUnitCircle: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          MpLegend(
            items: <MpLegendItem>[
              if (many)
                MpLegendItem.line(
                  color: colors.textSecondary,
                  width: 1.5,
                  label: 'One copy each',
                )
              else ...<MpLegendItem>[
                MpLegendItem.line(
                  color: colors.textSecondary,
                  width: 2,
                  label: 'Direct',
                ),
                MpLegendItem.line(
                  color: colors.textSecondary,
                  width: 2,
                  dashed: true,
                  label: 'Reflected',
                ),
              ],
              MpLegendItem.line(
                color: colors.textAccent,
                width: 3,
                label: 'Sum',
              ),
              MpLegendItem.line(
                color: colors.borderStrong,
                width: 1,
                dashed: true,
                label: many ? 'Average strength' : 'Direct alone',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Power vs position ───────────────────────────────────────────────────────

class _PlotCard extends StatelessWidget {
  const _PlotCard({
    required this.controller,
    required this.style,
    this.presenter = false,
  });

  final MultipathController controller;
  final MultipathPaintStyle style;

  /// Fill a bounded box: the plot takes the height.
  final bool presenter;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final MultipathController c = controller;
    final List<double> a = c.traceA;
    final List<double>? b = c.traceB;
    final UnitSystem u = c.units;
    final LengthFormat f = LengthFormat(u);
    final String title = switch (c.mode) {
      MultipathMode.oneWall =>
        'Power along the ${f.dist(MultipathController.twoRay.trackLength)} '
            'track',
      MultipathMode.standingWave => 'Power vs distance to the wall',
      MultipathMode.manyPaths =>
        'Power along ${f.dist(2)}, against the average',
    };
    // The plot works in cm; imperial shows inches with round ticks.
    final double toShown = u.isMetric ? 1 : 1 / 2.54;
    final double shownMax = c.plotRangeCm * toShown;
    final List<double>? ticks = u.isMetric
        ? null
        : NiceTicks.between(0, shownMax, target: 3);
    final String semantic = c.isManyPaths
        ? 'Plot of received power along ${f.dist(2)} for antenna A, solid, and '
              'antenna B, dashed. Antenna A is below -10 dB '
              '${_C.pct(c.fade.fractionA)} of the way.'
        : 'Plot of received power against position. The receiver is at '
              '${_C.len(c.positionCm / 100, u)}, where the power is '
              '${_C.db(c.receivedDb)}.';
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MpSectionLabel(title),
          const SizedBox(height: AppSpacing.xs),
          _fill(
            presenter,
            _PlotSurface(
              height: presenter ? null : 200,
              verticalPadding: AppSpacing.xxs,
              semantic: semantic,
              painter: (Size size) => PowerPlotPainter(
                traceA: a,
                traceB: b,
                xMax: shownMax,
                xUnitLabel: f.smallUnit,
                xTicks: ticks,
                marker: c.positionCm * toShown,
                style: style,
                revision: c.plotRevision,
              ),
              onDrag: (double dx, Size size) => c.setPositionCm(
                PowerPlotPainter.positionAt(dx, shownMax, size) / toShown,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          MpLegend(
            items: <MpLegendItem>[
              MpLegendItem.line(
                color: colors.textAccent,
                width: 2,
                label: b == null ? 'Received' : 'Antenna A',
              ),
              if (b != null)
                MpLegendItem.line(
                  color: colors.textSecondary,
                  width: 2,
                  dashed: true,
                  label: 'Antenna B',
                ),
              MpLegendItem.line(
                color: colors.borderStrong,
                width: 1,
                dashed: true,
                label: '-10 dB',
              ),
              MpLegendItem(
                swatch: Container(
                  width: 2,
                  height: 12,
                  color: colors.textPrimary,
                ),
                label: 'Receiver',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Histogram (mode 3) ──────────────────────────────────────────────────────

class _HistogramCard extends StatelessWidget {
  const _HistogramCard({
    required this.controller,
    required this.style,
    this.presenter = false,
  });

  final MultipathController controller;
  final MultipathPaintStyle style;

  /// Fill a bounded box; the long note is phone-only.
  final bool presenter;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final MultipathController c = controller;
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MpSectionLabel('How often each power level shows up'),
          const SizedBox(height: AppSpacing.xs),
          _fill(
            presenter,
            _PlotSurface(
              height: presenter ? null : 170,
              verticalPadding: AppSpacing.xxs,
              semantic:
                  'Histogram of antenna A power along '
                  '${_C.dist(2, UnitSystemScope.systemOf(context))} in 2.5 dB '
                  'bins, with '
                  'the Rayleigh prediction drawn over it. Measured below -10 dB: '
                  '${_C.pct(c.fade.fractionA)}; Rayleigh predicts 9.5%.',
              painter: (Size size) => HistogramPainter(
                histogram: c.histogram,
                style: style,
                revision: c.plotRevision,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          MpLegend(
            items: <MpLegendItem>[
              MpLegendItem(
                swatch: Container(
                  width: 10,
                  height: 10,
                  color: colors.textAccent,
                ),
                label: 'Antenna A, measured',
              ),
              MpLegendItem.line(
                color: colors.textPrimary,
                width: 2,
                label: 'Rayleigh prediction',
              ),
            ],
          ),
          if (!presenter) const SizedBox(height: AppSpacing.xs),
          if (!presenter)
            MpNote(
              icon: Icons.info_outline,
              message:
                  'The end bars also hold everything past -30 and +10 dB. A '
                  '${_C.dist(2, UnitSystemScope.systemOf(context))} '
                  'track holds only a few dozen fades, so the bars wander '
                  'around the curve; try New layout, more reflectors, or a '
                  'higher band.',
            ),
        ],
      ),
    );
  }
}
