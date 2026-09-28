// PredictMeasureStage: the pictures half of Predict, Then Measure.
//
// The floor seen from above with its walls (design loss, tested or untested,
// true loss after the reveal), the AP on a stick, the student's walk and one
// of four maps (Predicted, Measured, Difference, Truth after the reveal),
// the legend and the predict-then-reveal prompt. Takes the shared
// PredictMeasureController and nothing else, so a phone layout can stack it
// with PredictMeasureControls and a presenter layout can put the two side by
// side.
//
// A tap or drag on the floor draws the walk or moves the AP, per the tap
// setting; both go through the controller. The walk buttons and the AP
// sliders in PredictMeasureControls do the same for keyboard users.
//
// PRESENTER (spec 00): inside a PresenterLayout the map fills the stage
// height with no scroll, and a strip over it carries the readouts the lesson
// is about. Painters read PresenterMode.scaleOf.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/heat_map_builder_engine.dart';
import '../../../services/wifi_lab/predict_measure_engine.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_coverage_ramp.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/presenter/presenter.dart';
import 'heat_map_builder_painters.dart';
import 'heat_map_builder_parts.dart';
import 'predict_measure_controller.dart';
import 'predict_measure_painters.dart';

class PredictMeasureStage extends StatefulWidget {
  const PredictMeasureStage({super.key, required this.controller});

  final PredictMeasureController controller;

  @override
  State<PredictMeasureStage> createState() => _PredictMeasureStageState();
}

class _PredictMeasureStageState extends State<PredictMeasureStage> {
  // Repaint key for the map painter; bumped on every controller change.
  int _revision = 0;

  PredictMeasureController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_bump);
  }

  @override
  void didUpdateWidget(PredictMeasureStage old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_bump);
      widget.controller.addListener(_bump);
    }
  }

  @override
  void dispose() {
    c.removeListener(_bump);
    super.dispose();
  }

  void _bump() => _revision++;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (BuildContext context, _) {
        final bool present = PresenterMode.isActive(context);
        final Widget map = _MapCard(
          controller: c,
          revision: _revision,
          fill: present,
        );
        if (present) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _NowStrip(controller: c),
              const SizedBox(height: AppSpacing.xs),
              _LessonBanner(controller: c),
              const SizedBox(height: AppSpacing.xs),
              Expanded(child: map),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _LessonBanner(controller: c),
            const SizedBox(height: AppSpacing.sm),
            map,
          ],
        );
      },
    );
  }
}

// ── Now strip (presenter) ───────────────────────────────────────────────────

class _NowStrip extends StatelessWidget {
  const _NowStrip({required this.controller});

  final PredictMeasureController controller;

  @override
  Widget build(BuildContext context) {
    final PredictMeasureController c = controller;
    final PmMaps m = c.maps;
    return HmCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 2,
            child: _Tile(
              label: 'Walls tested',
              value: '${c.testedCount} of ${c.walls.length}',
              headline: true,
            ),
          ),
          Expanded(
            flex: 2,
            child: _Tile(
              label: 'Largest difference',
              value: m.largestDiffDb == null
                  ? 'no data'
                  : fmtSignedDb(m.largestDiffDb!),
              headline: true,
            ),
          ),
          Expanded(
            flex: 2,
            child: _Tile(
              label:
                  'Differs by over ${kPmDiffThresholdDb.toStringAsFixed(0)} dB',
              value: '${fmtPct(m.diffOverShare)} of floor',
            ),
          ),
          Expanded(
            flex: 3,
            child: _Tile(
              label:
                  'Below ${kPmDesignTargetDbm.toStringAsFixed(0)} dBm '
                  '(illustrative)',
              value:
                  'design ${fmtPct(m.predictedBelowTarget)}'
                  '${c.revealed ? ', truth ${fmtPct(m.truthBelowTarget)}' : ''}',
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    this.headline = false,
  });

  final String label;
  final String value;
  final bool headline;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final TextStyle base = mono.outputMedium.copyWith(
      color: headline ? colors.textAccent : colors.textPrimary,
    );
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              maxLines: 2,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: colors.textSecondary),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: headline ? sc.headlineStyle(base) : base,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Lesson banner: predict, then reveal ─────────────────────────────────────

/// The walls where the building differs from the design by more than 0.5 dB.
List<int> _wrongWalls(PredictMeasureController c) => <int>[
  for (int i = 0; i < c.walls.length; i++)
    if ((c.walls[i].trueLossDb - c.walls[i].predictedLossDb).abs() > 0.5) i,
];

String _wallList(
  PredictMeasureController c,
  List<int> ids, {
  bool truth = false,
}) => ids
    .map((int i) {
      final PmWall w = c.walls[i];
      final PmWallTest? t = c.survey.tests[i];
      final String name =
          '${PredictMeasureController.wallName(i)} '
          '(${w.material.label.toLowerCase()})';
      if (truth) {
        return '$name: design ${fmtM(w.predictedLossDb)} dB, really '
            '${fmtM(w.trueLossDb)} dB';
      }
      return '$name: design ${fmtM(w.predictedLossDb)} dB, tested '
          '${t!.estimateDb.toStringAsFixed(1)} dB';
    })
    .join('; ');

/// The prompt for the current state.
String pmLessonText(PredictMeasureController c) {
  final int n = c.walls.length;
  if (!c.revealed) {
    if (!c.hasWalk) {
      return 'Predict: the design shows green everywhere. What would you '
          'check before signing it off? Every wall loss in it is a claim. '
          'Draw a walk with the AP on a stick where the design puts the AP, '
          'then compare the Predicted and Measured maps.';
    }
    final List<int> disagree = <int>[
      for (final PmWallTest t in c.survey.tests.values)
        if ((t.estimateDb - c.walls[t.wallIndex].predictedLossDb).abs() > 1)
          t.wallIndex,
    ]..sort();
    return 'Your walk tested ${c.testedCount} of $n walls. '
        '${disagree.isEmpty ? 'None of them disagrees with the design by more than 1 dB. ' : 'Disagreeing with the design: ${_wallList(c, disagree)}. '}'
        '${c.untestedCount == 0 ? 'Every wall has samples on both sides.' : 'The other ${c.untestedCount} are still claims: no sample pair straddles them. Reveal the truth when you have decided.'}';
  }
  final List<int> wrong = _wrongWalls(c);
  if (wrong.isEmpty) {
    return 'Reveal: the design now matches the building on every wall. '
        '${fmtPct(c.maps.predictedBelowTarget)} of the floor is below the '
        '${kPmDesignTargetDbm.toStringAsFixed(0)} dBm design target '
        '(illustrative). If that is too much, the AP may need to move, or '
        'the design may need another AP.';
  }
  final List<int> missed = <int>[
    for (final int i in wrong)
      if (!c.survey.isTested(i)) i,
  ];
  return 'Reveal: the building differs from the design on ${wrong.length} '
      '${wrong.length == 1 ? 'wall' : 'walls'}: ${_wallList(c, wrong, truth: true)}. '
      '${missed.isEmpty ? 'Your walk tested every one of them; Update model fixes the design. ' : 'Your walk missed ${missed.map(PredictMeasureController.wallName).join(', ')}. '}'
      'You only learn a wall\'s loss by measuring on both sides of it.';
}

class _LessonBanner extends StatelessWidget {
  const _LessonBanner({required this.controller});

  final PredictMeasureController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool present = PresenterMode.isActive(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border(left: BorderSide(color: colors.primary, width: 4)),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Text(
          pmLessonText(controller),
          style: (present ? text.bodyMedium : text.bodyLarge)?.copyWith(
            color: colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ── The map ─────────────────────────────────────────────────────────────────

class _MapCard extends StatefulWidget {
  const _MapCard({
    required this.controller,
    required this.revision,
    this.fill = false,
  });

  final PredictMeasureController controller;
  final int revision;

  /// Presenter: fill a bounded box; the teaching prose is dropped.
  final bool fill;

  @override
  State<_MapCard> createState() => _MapCardState();
}

class _MapCardState extends State<_MapCard> {
  Size _size = Size.zero;

  PredictMeasureController get c => widget.controller;

  HmPoint _toFloor(Offset o) =>
      HmFloorMapping(_size, c.model.widthM, c.model.depthM).toFloor(o);

  String _semantic() {
    final PmMaps m = c.maps;
    final StringBuffer b = StringBuffer(
      'Floor, ${c.coord(c.model.widthM)} by ${c.coord(c.model.depthM)} '
      '${c.lf.distUnitSpoken}, '
      'seen from above, showing the ${c.view.label.toLowerCase()} map. '
      'AP on a stick at ${c.coord(c.ap.x)}, ${c.coord(c.ap.y)} '
      '${c.lf.distUnitSpoken}. '
      '${c.walls.length} walls, ${c.testedCount} tested. '
      '${c.sampleCount} samples on the walk. ',
    );
    if (c.view == PmMapView.measured || c.view == PmMapView.difference) {
      b.write(
        '${fmtPct(1 - m.measuredShare)} of the floor is white, no data. ',
      );
    }
    b.write(
      c.tapAction == PmTapAction.walk
          ? 'Tap or drag to draw the walk.'
          : 'Tap or drag to move the AP.',
    );
    return b.toString();
  }

  void _panStart(DragStartDetails d) {
    final HmPoint p = _toFloor(d.localPosition);
    if (c.tapAction == PmTapAction.ap) {
      c.moveAp(p);
    } else {
      c.startLeg(p);
    }
  }

  void _panUpdate(DragUpdateDetails d) {
    final HmPoint p = _toFloor(d.localPosition);
    if (c.tapAction == PmTapAction.ap) {
      c.moveAp(p);
    } else {
      c.extendLeg(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool fill = widget.fill;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final Widget plan = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints bc) {
        _size = Size(bc.maxWidth, bc.maxHeight);
        return MouseRegion(
          cursor: SystemMouseCursors.precise,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (TapUpDetails d) => c.tapFloor(_toFloor(d.localPosition)),
            onPanStart: _panStart,
            onPanUpdate: _panUpdate,
            onPanEnd: (_) => c.endLeg(),
            onPanCancel: c.endLeg,
            child: CustomPaint(
              size: _size,
              painter: PmMapPainter(
                sc: sc,
                font:
                    Theme.of(context).textTheme.labelSmall ?? const TextStyle(),
                data: PmMapPaintData(
                  model: c.model,
                  maps: c.maps,
                  survey: c.survey,
                  legs: c.legs,
                  view: c.view,
                  revealed: c.revealed,
                  selectedWall: c.selectedWall,
                  updatedWalls: c.updatedWalls,
                  revision: widget.revision,
                ),
              ),
            ),
          ),
        );
      },
    );
    final Widget floor = Semantics(
      label: _semantic(),
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: fill
            ? plan
            : AspectRatio(
                aspectRatio: c.model.widthM / c.model.depthM + 0.04,
                child: plan,
              ),
      ),
    );
    return HmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: HmSectionLabel(
                  'Floor, seen from above (${c.len(c.model.widthM)} x '
                  '${c.len(c.model.depthM)}, ${c.preset.label.toLowerCase()}, '
                  'illustrative)',
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              // A Select inside a Row needs a bounded width; wide enough
              // for "Difference" at presenter scale.
              SizedBox(
                width: 180,
                child: AppSelect<PmMapView>(
                  value: c.view,
                  semanticLabel: 'Map',
                  items: <AppSelectItem<PmMapView>>[
                    for (final PmMapView v in c.availableViews) (v, v.label),
                  ],
                  onChanged: (PmMapView v) => c.view = v,
                ),
              ),
            ],
          ),
          if (!fill) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Only the lime dots on the walk are measurements. The '
              'Predicted map is the design; every wall loss in it is a '
              'claim until a walk crosses the wall.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          if (fill) Expanded(child: floor) else floor,
          const SizedBox(height: AppSpacing.xs),
          _Legend(view: c.view),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.view});

  final PmMapView view;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextStyle small = mono.inlineCode.copyWith(
      color: colors.textSecondary,
      fontSize: AppTextSize.caption - 1,
    );
    final bool diff = view == PmMapView.difference;
    final bool noData = diff || view == PmMapView.measured;
    final List<double> edges = diff ? kHmErrorEdgesDb : kHmSignalEdgesDbm;
    String stopLabel(int i) {
      if (i == 0) return '<${edges.first.toStringAsFixed(0)}';
      final String v = edges[i - 1].toStringAsFixed(0);
      return i == edges.length ? '$v+' : v;
    }

    final String title = switch (view) {
      PmMapView.predicted => 'Predicted signal (the design), dBm',
      PmMapView.measured => 'Measured signal (the walk, interpolated), dBm',
      PmMapView.difference =>
        'Difference, dB (size of measured minus predicted)',
      PmMapView.truth => 'True signal (the building), dBm',
    };
    return Semantics(
      label:
          '$title. Darkest ${stopLabel(0)}, palest ${stopLabel(edges.length)}. '
          '${noData ? 'White with a hatch: no data.' : ''}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: small),
          const SizedBox(height: AppSpacing.xxs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (int i = 0; i <= edges.length; i++)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          width: 34,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppCoverageRamp.stops[i],
                            border: Border.all(color: colors.borderStrong),
                          ),
                        ),
                        Text(stopLabel(i), style: small),
                      ],
                    ),
                ],
              ),
              if (noData)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      width: 22,
                      height: 14,
                      child: CustomPaint(painter: _NoDataSwatchPainter()),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text('No data', style: small),
                  ],
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.borderStrong),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text('Sample on the walk', style: small),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoDataSwatchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = kHmNoDataColor);
    canvas.save();
    canvas.clipRect(r);
    final Paint hatch = Paint()
      ..color = kHmNoDataHatch
      ..strokeWidth = 1;
    for (double x = -size.height; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        hatch,
      );
    }
    canvas.restore();
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = kHmNoDataHatch,
    );
  }

  @override
  bool shouldRepaint(_NoDataSwatchPainter old) => false;
}
