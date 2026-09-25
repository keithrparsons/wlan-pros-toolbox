// MultipathStage: the pictures half of the Multipath Simulator.
//
// Scene (one wall / standing wave), phasor diagram, power-vs-position plot,
// and the many-path histogram, each with its legend. Takes the shared
// MultipathController and nothing else, so a phone layout can stack it with
// MultipathControls and a presenter layout can put the two side by side.
// Dragging the scene or the plot moves the receiver through the controller;
// the sliders in MultipathControls do the same thing for keyboard users.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/multipath_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
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

  static MultipathPaintStyle _paintStyle(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return MultipathPaintStyle(
      accent: colors.textAccent,
      primary: colors.textPrimary,
      secondary: colors.textSecondary,
      tertiary: colors.textTertiary,
      grid: colors.border,
      axis: colors.borderStrong,
      wall: colors.borderStrong,
      labelStyle: mono.inlineCode.copyWith(
        fontSize: AppTextSize.caption - 2,
        color: colors.textSecondary,
      ),
    );
  }
}

/// A plot surface: surface-2, rounded, labelled for screen readers, with an
/// optional drag-to-move handler that gets the local x and the size.
class _PlotSurface extends StatelessWidget {
  const _PlotSurface({
    required this.height,
    required this.semantic,
    required this.painter,
    this.onDrag,
    this.verticalPadding = 0,
  });

  final double height;
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
  const _SceneCard({required this.controller, required this.style});

  final MultipathController controller;
  final MultipathPaintStyle style;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final MultipathController c = controller;
    final bool one = c.mode == MultipathMode.oneWall;
    final List<double> nulls = one ? const <double>[] : c.nulls;
    final String semantic = one
        ? 'Scene seen from above: a wall along the top, the access point on '
              'the left, and the receiver ${_C.cm(c.trackOffset, 0)} along a '
              '1 m track. The direct ray goes straight across; the reflected '
              'ray bounces off the wall.'
        : 'Scene: a wall on the left, the receiver '
              '${_C.cm(c.wallDistance)} in front of it, and the signal '
              'arriving from an access point 10 m away. ${nulls.length} '
              'nulls are marked along the floor.';
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MpSectionLabel(one ? 'Seen from above' : 'Walking toward the wall'),
          const SizedBox(height: AppSpacing.xs),
          _PlotSurface(
            height: 170,
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
  const _PhasorCard({required this.controller, required this.style});

  final MultipathController controller;
  final MultipathPaintStyle style;

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
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
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
  const _PlotCard({required this.controller, required this.style});

  final MultipathController controller;
  final MultipathPaintStyle style;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final MultipathController c = controller;
    final List<double> a = c.traceA;
    final List<double>? b = c.traceB;
    final String title = switch (c.mode) {
      MultipathMode.oneWall => 'Power along the 1 m track',
      MultipathMode.standingWave => 'Power vs distance to the wall',
      MultipathMode.manyPaths => 'Power along 2 m, against the average',
    };
    final String semantic = c.isManyPaths
        ? 'Plot of received power along 2 m for antenna A, solid, and '
              'antenna B, dashed. Antenna A is below -10 dB '
              '${_C.pct(c.fade.fractionA)} of the way.'
        : 'Plot of received power against position. The receiver is at '
              '${c.positionCm.toStringAsFixed(1)} cm, where the power is '
              '${_C.db(c.receivedDb)}.';
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MpSectionLabel(title),
          const SizedBox(height: AppSpacing.xs),
          _PlotSurface(
            height: 200,
            verticalPadding: AppSpacing.xxs,
            semantic: semantic,
            painter: (Size size) => PowerPlotPainter(
              traceA: a,
              traceB: b,
              xMax: c.plotRangeCm,
              xUnitLabel: 'cm',
              marker: c.positionCm,
              style: style,
              revision: c.plotRevision,
            ),
            onDrag: (double dx, Size size) => c.setPositionCm(
              PowerPlotPainter.positionAt(dx, c.plotRangeCm, size),
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
  const _HistogramCard({required this.controller, required this.style});

  final MultipathController controller;
  final MultipathPaintStyle style;

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
          _PlotSurface(
            height: 170,
            verticalPadding: AppSpacing.xxs,
            semantic:
                'Histogram of antenna A power along 2 m in 2.5 dB bins, with '
                'the Rayleigh prediction drawn over it. Measured below -10 dB: '
                '${_C.pct(c.fade.fractionA)}; Rayleigh predicts 9.5%.',
            painter: (Size size) => HistogramPainter(
              histogram: c.histogram,
              style: style,
              revision: c.plotRevision,
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
          const SizedBox(height: AppSpacing.xs),
          const MpNote(
            icon: Icons.info_outline,
            message:
                'The end bars also hold everything past -30 and +10 dB. A 2 m '
                'track holds only a few dozen fades, so the bars wander '
                'around the curve; try New layout, more reflectors, or a '
                'higher band.',
          ),
        ],
      ),
    );
  }
}
