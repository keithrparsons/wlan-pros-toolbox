// HeatMapBuilderStage: the pictures half of the Heat Map Builder.
//
// The floor seen from above with its APs, walls, sample dots and the map
// (heat map, truth or error map), the legend, the cell inspector, the lesson
// prompt and, once run, the spacing experiment plot. Takes the shared
// HeatMapBuilderController and nothing else, so a phone layout can stack it
// with HeatMapBuilderControls and a presenter layout can put the two side by
// side.
//
// A tap on the floor adds a sample or inspects a cell, per the tap setting;
// both go through the controller. The grid, walk and lesson buttons and the
// inspector sliders in HeatMapBuilderControls do the same for keyboard users.
//
// PRESENTER (spec 00): inside a PresenterLayout the map fills the stage
// height with no scroll, and a strip over it carries the numbers the lesson
// is about: samples, root mean square error, the largest error and how much
// of the floor is white. Painters read PresenterMode.scaleOf.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/heat_map_builder_engine.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_coverage_ramp.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter.dart';
import 'heat_map_builder_controller.dart';
import 'heat_map_builder_painters.dart';
import 'heat_map_builder_parts.dart';

class HeatMapBuilderStage extends StatefulWidget {
  const HeatMapBuilderStage({super.key, required this.controller});

  final HeatMapBuilderController controller;

  @override
  State<HeatMapBuilderStage> createState() => _HeatMapBuilderStageState();
}

class _HeatMapBuilderStageState extends State<HeatMapBuilderStage> {
  // Repaint key for the map painter; bumped on every controller change.
  int _revision = 0;

  HeatMapBuilderController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_bump);
  }

  @override
  void didUpdateWidget(HeatMapBuilderStage old) {
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
        final bool experiment = c.experiment != null;
        final Widget mapCard = _MapCard(
          controller: c,
          revision: _revision,
          fill: present,
        );
        if (present) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _NowStrip(controller: c),
              if (c.lesson != HmLessonStep.off) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                _LessonBanner(controller: c),
              ],
              const SizedBox(height: AppSpacing.xs),
              // The experiment sits beside the map, so both keep the full
              // stage height (a floor plan is wide, a plot needs height).
              Expanded(
                child: experiment
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(flex: 3, child: mapCard),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            flex: 2,
                            child: _ExperimentCard(controller: c, fill: true),
                          ),
                        ],
                      )
                    : mapCard,
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (c.lesson != HmLessonStep.off) ...<Widget>[
              _LessonBanner(controller: c),
              const SizedBox(height: AppSpacing.sm),
            ],
            mapCard,
            if (experiment) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              _ExperimentCard(controller: c),
            ],
          ],
        );
      },
    );
  }
}

// ── Now strip (presenter) ───────────────────────────────────────────────────

class _NowStrip extends StatelessWidget {
  const _NowStrip({required this.controller});

  final HeatMapBuilderController controller;

  @override
  Widget build(BuildContext context) {
    final HeatMapBuilderController c = controller;
    final HmMap m = c.map;
    return HmCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: _Tile(label: 'Samples', value: '${c.points.length}'),
          ),
          Expanded(
            flex: 2,
            child: _Tile(
              label: 'Root mean square error (RMSE)',
              value: m.rmseDb == null
                  ? 'no data'
                  : '${m.rmseDb!.toStringAsFixed(1)} dB',
              headline: true,
            ),
          ),
          Expanded(
            flex: 2,
            child: _Tile(
              label: 'Largest error',
              value: m.maxErrorDb == null
                  ? 'no data'
                  : fmtSignedDb(m.maxErrorDb!),
              headline: true,
            ),
          ),
          Expanded(
            flex: 2,
            child: _Tile(
              label: 'No data (white)',
              value: '${(m.noDataShare * 100).toStringAsFixed(0)}%',
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
            Text(
              value,
              maxLines: 1,
              style: headline ? sc.headlineStyle(base) : base,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Lesson banner ───────────────────────────────────────────────────────────

/// The lesson's words for [step] on [c]'s current map.
String hmLessonText(HeatMapBuilderController c) {
  switch (c.lesson) {
    case HmLessonStep.off:
      return '';
    case HmLessonStep.predict:
      return 'Predict: three dots can paint the whole floor green. Should '
          'they? Only the dots are measurements; with a '
          '${c.whole(c.settings.guessRangeM)} guess range the '
          'rest of the floor is white, because it has no data.';
    case HmLessonStep.widened:
      return 'Reveal 1: the guess range is now '
          '${c.whole(c.settings.guessRangeM)} and flat inverse '
          'distance weighting fills the rest. Three dots paint the whole '
          'floor, and every cell but the three is a guess.';
    case HmLessonStep.wallRevealed:
      final double? worst = c.map.maxErrorDb;
      return 'Reveal 2: the hidden 12 dB wall. The error map shows where the '
          'painted floor is wrong${worst == null ? '' : ', by up to ${fmtSignedDb(worst)}'}. '
          'White, no data, was the truthful answer.';
  }
}

class _LessonBanner extends StatelessWidget {
  const _LessonBanner({required this.controller});

  final HeatMapBuilderController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
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
          hmLessonText(controller),
          style: text.bodyLarge?.copyWith(color: colors.textPrimary),
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

  final HeatMapBuilderController controller;
  final int revision;

  /// Presenter: fill a bounded box; the teaching prose is dropped.
  final bool fill;

  @override
  State<_MapCard> createState() => _MapCardState();
}

class _MapCardState extends State<_MapCard> {
  Size _size = Size.zero;

  HeatMapBuilderController get c => widget.controller;

  HmPaintView get _paintView => switch (c.view) {
    HmView.estimate => HmPaintView.estimate,
    HmView.truth => HmPaintView.truth,
    HmView.error => HmPaintView.error,
  };

  String _semantic() {
    final HmMap m = c.map;
    final StringBuffer b = StringBuffer(
      'Floor, ${c.lf.distNumber(c.floor.widthM, decimals: 0)} by '
      '${c.lf.distNumber(c.floor.depthM, decimals: 0)} '
      '${c.lf.distUnitSpoken}, seen from above, showing the '
      '${c.view.label.toLowerCase()}. ${c.apCount} '
      '${c.apCount == 1 ? 'AP' : 'APs'}. ${c.points.length} samples. ',
    );
    if (c.view != HmView.truth) {
      b.write(
        '${(m.noDataShare * 100).toStringAsFixed(0)} percent of the floor '
        'is white, no data. ',
      );
    }
    if (m.rmseDb != null) {
      b.write(
        'Root mean square error ${m.rmseDb!.toStringAsFixed(1)} dB, '
        'largest error ${fmtSignedDb(m.maxErrorDb!)}. ',
      );
    }
    if (c.wallRevealed) b.write('The hidden 12 dB wall is shown dashed. ');
    b.write(
      c.tapAction == HmTapAction.add
          ? 'Tap to add a sample.'
          : 'Tap to inspect a cell.',
    );
    return b.toString();
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
            onTapUp: (TapUpDetails d) {
              final HmFloorMapping m = HmFloorMapping(
                _size,
                c.floor.widthM,
                c.floor.depthM,
              );
              c.tapFloor(m.toFloor(d.localPosition));
            },
            child: CustomPaint(
              size: _size,
              painter: HmMapPainter(
                sc: sc,
                font:
                    Theme.of(context).textTheme.labelSmall ?? const TextStyle(),
                data: HmMapPaintData(
                  floor: c.floor,
                  map: c.map,
                  samples: c.samples,
                  view: _paintView,
                  wallRevealed: c.wallRevealed,
                  inspectedCell: c.inspectedCell,
                  inspection: c.inspection,
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
            : AspectRatio(aspectRatio: 40 / 25 + 0.04, child: plan),
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
                  'Floor, seen from above (${c.whole(c.floor.widthM)} x '
                  '${c.whole(c.floor.depthM)})',
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AppToggle<HmView>(
                value: c.view,
                semanticLabel: 'Map view',
                items: <AppToggleItem<HmView>>[
                  for (final HmView v in HmView.values) (v, v.label),
                ],
                onChanged: (HmView v) => c.view = v,
              ),
            ],
          ),
          if (!fill) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Only the lime dots are measurements. Every other cell is a '
              'guess. White means no data, not no coverage.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          if (fill) Expanded(child: floor) else floor,
          const SizedBox(height: AppSpacing.xs),
          _Legend(view: c.view),
          if (c.inspectedCell != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            _InspectorLine(controller: c),
          ],
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.view});

  final HmView view;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextStyle small = mono.inlineCode.copyWith(
      color: colors.textSecondary,
      fontSize: AppTextSize.caption - 1,
    );
    final bool error = view == HmView.error;
    final List<double> edges = error ? kHmErrorEdgesDb : kHmSignalEdgesDbm;
    String stopLabel(int i) {
      if (i == 0) {
        return error
            ? '<${edges.first.toStringAsFixed(0)}'
            : '<${edges.first.toStringAsFixed(0)}';
      }
      final String v = edges[i - 1].toStringAsFixed(0);
      return i == edges.length ? '$v+' : v;
    }

    final String title = error
        ? 'Error, dB (size of estimate minus truth)'
        : 'Signal of the strongest AP, dBm';
    return Semantics(
      label:
          '$title. Darkest ${stopLabel(0)}, palest ${stopLabel(edges.length)}. '
          '${view == HmView.truth ? '' : 'White with a hatch: no data.'}',
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
              if (view != HmView.truth)
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
                  Text('Sample', style: small),
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

class _InspectorLine extends StatelessWidget {
  const _InspectorLine({required this.controller});

  final HeatMapBuilderController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final HeatMapBuilderController c = controller;
    final HmPoint q = c.inspectedCell!;
    final HmCellEstimate e = c.inspection!;
    final double truth = c.inspectedTruthDbm!;
    final String how = switch (e.fill) {
      HmFill.interpolated =>
        c.settings.method == HmMethod.nearest
            ? 'nearest sample'
            : '${e.contributions.length} samples, weighted',
      HmFill.flat => 'flat fill from ${e.contributions.length} samples',
      HmFill.model => 'path-loss fill',
      HmFill.none => 'no data',
    };
    final String value = e.dbm == null
        ? 'no data (truth ${fmtDbm(truth)})'
        : '${fmtDbm(e.dbm!)} ($how); truth ${fmtDbm(truth)}; error '
              '${fmtSignedDb(e.dbm! - truth)}';
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            'Cell at ${c.lf.distValue(q.x).toStringAsFixed(2)}, '
            '${c.lf.dist(q.y, decimals: 2, keepZeros: true)}: '
            '$value',
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
        ),
        IconButton(
          onPressed: () => c.inspect(null),
          tooltip: 'Stop inspecting this cell',
          icon: const Icon(Icons.close_rounded),
          color: colors.textSecondary,
        ),
      ],
    );
  }
}

// ── Spacing experiment ──────────────────────────────────────────────────────

class _ExperimentCard extends StatelessWidget {
  const _ExperimentCard({required this.controller, this.fill = false});

  final HeatMapBuilderController controller;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final List<HmSpacingSeries> series = controller.experiment!;
    final List<Color> hues = <Color>[
      colors.textAccent,
      colors.textPrimary,
      colors.textSecondary,
    ];
    final String summary = <String>[
      for (final HmSpacingSeries s in series)
        '${s.label}: ${s.rmseDb.map((double v) => v.toStringAsFixed(1)).join(', ')} dB',
    ].join('. ');
    final Widget plot = Semantics(
      label:
          'Root mean square error against grid spacing '
          '${controller.experimentSpacingsShown.map((double v) => v.toStringAsFixed(0)).join(', ')} ${controller.lf.distUnit}. '
          '$summary.',
      excludeSemantics: true,
      child: CustomPaint(
        painter: HmSpacingPainter(
          series: series,
          spacingsShown: controller.experimentSpacingsShown,
          axisMax: controller.units.isMetric ? 10 : 30,
          unit: controller.lf.distUnit,
          style: HmSpacingPlotStyle(
            sc: sc,
            series: hues,
            axis: colors.borderStrong,
            grid: colors.border,
            label: colors.textSecondary,
            font: mono.inlineCode,
          ),
        ),
      ),
    );
    final Widget legend = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      children: <Widget>[
        for (int i = 0; i < series.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 34,
                height: 14,
                child: CustomPaint(
                  painter: HmSeriesKeyPainter(index: i, color: hues[i]),
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                series[i].label,
                style: mono.inlineCode.copyWith(
                  color: colors.textSecondary,
                  fontSize: AppTextSize.caption - 1,
                ),
              ),
            ],
          ),
      ],
    );
    return HmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: HmSectionLabel(
                  'Spacing experiment: root mean square error (RMSE) by grid '
                  'spacing',
                ),
              ),
              IconButton(
                onPressed: controller.closeExperiment,
                tooltip: 'Close the spacing experiment',
                icon: const Icon(Icons.close_rounded),
                color: colors.textSecondary,
              ),
            ],
          ),
          if (fill)
            Expanded(child: plot)
          else
            SizedBox(height: 180, child: plot),
          const SizedBox(height: AppSpacing.xxs),
          legend,
          if (!fill && series.length == 1) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            const HmNote(
              'Set the noise above 0 dB and run it again to see where noise '
              'on single readings stops closer samples from helping, and what '
              'averaging buys back.',
            ),
          ],
        ],
      ),
    );
  }
}
