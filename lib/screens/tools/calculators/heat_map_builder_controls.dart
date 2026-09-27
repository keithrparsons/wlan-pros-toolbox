// HeatMapBuilderControls: the inputs-and-readouts half of the Heat Map
// Builder.
//
// Takes the shared HeatMapBuilderController and a set of parts to show. The
// phone layout puts samples and readouts right under the stage and the
// method, noise, lesson, worked example and floor cards after them; the
// presenter layout shows a compact panel beside the stage. No part draws the
// map or the spacing plot; HeatMapBuilderStage owns those. The worked example
// carries its own small diagram because it is a readout of the method.
//
// Control types follow GL-003 §8.14: two- and three-option choices are
// AppToggles (tap action, method, averaging domain, extrapolation), the AP
// count is an AppSelect. No status hues: an error size is a measurement, not
// a verdict (§8.13 rule 6).
//
// ACRONYMS (Keith's standing rule): IDW, RMSE and mW are spelled out the
// first time each surface shows them.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/heat_map_builder_engine.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter.dart';
import '../labeled_field.dart';
import 'heat_map_builder_controller.dart';
import 'heat_map_builder_painters.dart';
import 'heat_map_builder_parts.dart';

/// The groups HeatMapBuilderControls can show.
enum HmControlPart {
  /// Tap action, grid, walk, spacing, undo, clear, the inspector.
  samples,

  /// Samples, RMSE, largest error, no-data share.
  readouts,

  /// Method, power, averaging domain, guess range, extrapolation.
  method,

  /// Noise sigma, averaging count, take again.
  noise,

  /// Predict then reveal, the hidden wall, the spacing experiment.
  lesson,

  /// The three-sample worked example.
  workedExample,

  /// AP count and path-loss exponent.
  floor,
}

class HeatMapBuilderControls extends StatelessWidget {
  const HeatMapBuilderControls({
    super.key,
    required this.controller,
    this.parts = const <HmControlPart>{
      HmControlPart.samples,
      HmControlPart.readouts,
      HmControlPart.method,
      HmControlPart.noise,
      HmControlPart.lesson,
      HmControlPart.workedExample,
      HmControlPart.floor,
    },
  });

  final HeatMapBuilderController controller;
  final Set<HmControlPart> parts;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final HeatMapBuilderController c = controller;
        if (PresenterMode.isActive(context)) return _PresenterPanel(c);
        final List<Widget> cards = <Widget>[
          if (parts.contains(HmControlPart.samples)) _SamplesCard(c),
          if (parts.contains(HmControlPart.readouts)) _ReadoutsCard(c),
          if (parts.contains(HmControlPart.method))
            HmCard(child: _MethodFields(c, first: true)),
          if (parts.contains(HmControlPart.noise)) _NoiseCard(c),
          if (parts.contains(HmControlPart.lesson)) _LessonCard(c),
          if (parts.contains(HmControlPart.workedExample))
            _WorkedExampleCard(c),
          if (parts.contains(HmControlPart.floor)) _FloorCard(c),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < cards.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              cards[i],
            ],
          ],
        );
      },
    );
  }
}

// ── Presenter panel ─────────────────────────────────────────────────────────

class _PresenterPanel extends StatelessWidget {
  const _PresenterPanel(this.c);

  final HeatMapBuilderController c;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        HmCard(child: _SampleButtons(c, compact: true)),
        const SizedBox(height: AppSpacing.xs),
        HmCard(child: _MethodFields(c, first: true, compact: true)),
        const SizedBox(height: AppSpacing.xs),
        HmCard(child: _LessonButtons(c)),
        PresenterDisclosure(
          title: 'Worked example: three samples',
          children: <Widget>[_WorkedExampleCard(c)],
        ),
        PresenterDisclosure(
          title: 'Noise, the floor, and inspecting by keyboard',
          children: <Widget>[
            _NoiseCard(c, compact: true),
            const SizedBox(height: AppSpacing.xs),
            _FloorCard(c),
            const SizedBox(height: AppSpacing.xs),
            HmCard(child: _InspectorFields(c)),
          ],
        ),
      ],
    );
  }
}

// ── Samples ─────────────────────────────────────────────────────────────────

class _SamplesCard extends StatelessWidget {
  const _SamplesCard(this.c);

  final HeatMapBuilderController c;

  @override
  Widget build(BuildContext context) {
    return HmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const HmSectionLabel('Samples'),
          const SizedBox(height: AppSpacing.xs),
          _SampleButtons(c),
          if (c.tapAction == HmTapAction.inspect) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _InspectorFields(c),
          ],
        ],
      ),
    );
  }
}

class _SampleButtons extends StatelessWidget {
  const _SampleButtons(this.c, {this.compact = false});

  final HeatMapBuilderController c;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final String count =
        '${c.points.length} ${c.points.length == 1 ? 'sample' : 'samples'}'
        '${c.hasSamples ? ' (${c.layout.label.toLowerCase()})' : ''}';
    final Widget undo = IconButton(
      onPressed: c.hasSamples ? c.undoSample : null,
      tooltip: 'Remove the last sample',
      icon: const Icon(Icons.undo_rounded),
      color: context.colors.textAccent,
    );
    final Widget clear = IconButton(
      onPressed: c.hasSamples || c.lesson != HmLessonStep.off
          ? c.clearSamples
          : null,
      tooltip: 'Clear every sample',
      icon: const Icon(Icons.delete_sweep_outlined),
      color: context.colors.textAccent,
    );
    final Widget grid = HmOutlineButton(
      icon: Icons.grid_on_rounded,
      label: 'Grid',
      semanticLabel:
          'Place a grid of samples every '
          '${c.lf.distSpoken(c.spacingM, decimals: 0)}',
      onPressed: c.useGrid,
    );
    final Widget walk = HmOutlineButton(
      icon: Icons.directions_walk_rounded,
      label: compact ? 'Walk' : 'Corridor walk',
      semanticLabel:
          'Walk the corridor with a sample every '
          '${c.lf.distSpoken(c.spacingM, decimals: 0)}',
      onPressed: c.useWalk,
    );
    final Widget spacing = HmSlider(
      label: compact ? 'Spacing' : 'Grid and walk spacing',
      valueText: c.whole(c.spacingM),
      // Whole metres, or whole feet.
      value: c.lf.distValue(c.spacingM),
      min: (c.lf.distValue(kHmMinSpacingM) - 1e-9).ceilToDouble(),
      max: (c.lf.distValue(kHmMaxSpacingM) + 1e-9).floorToDouble(),
      divisions:
          ((c.lf.distValue(kHmMaxSpacingM) + 1e-9).floorToDouble() -
                  (c.lf.distValue(kHmMinSpacingM) - 1e-9).ceilToDouble())
              .round(),
      onChanged: (double v) => c.spacingM = c.lf.distToMetres(v),
      semanticValue: (double v) =>
          '${v.toStringAsFixed(0)} ${c.lf.distUnitSpoken}',
    );
    final Widget tap = AppToggle<HmTapAction>(
      value: c.tapAction,
      label: compact ? null : 'A tap on the floor will',
      semanticLabel: 'What a tap on the floor does',
      expand: true,
      items: <AppToggleItem<HmTapAction>>[
        for (final HmTapAction a in HmTapAction.values) (a, a.label),
      ],
      onChanged: (HmTapAction a) => c.tapAction = a,
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          tap,
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Expanded(child: grid),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: walk),
              undo,
              clear,
            ],
          ),
          spacing,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        tap,
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: <Widget>[
            Expanded(child: grid),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: walk),
          ],
        ),
        spacing,
        Row(
          children: <Widget>[
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  c.atSampleLimit
                      ? '$count. The floor is full ($kHmMaxSamples).'
                      : count,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ),
            undo,
            clear,
          ],
        ),
        if (!c.hasSamples)
          const HmNote(
            'No samples yet, so the whole floor is white: no data. Tap the '
            'floor to add a sample, or place a grid or a corridor walk.',
          ),
      ],
    );
  }
}

/// Keyboard equivalent of tapping a cell: move the inspected cell.
class _InspectorFields extends StatelessWidget {
  const _InspectorFields(this.c);

  final HeatMapBuilderController c;

  @override
  Widget build(BuildContext context) {
    final HmPoint? q = c.inspectedCell;
    final HmFloor f = c.floor;
    final HmPoint at = q ?? (x: f.widthM / 2, y: f.depthM / 2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        HmSlider(
          label: 'Inspected cell, across',
          // Cell centres; the slider stays on the 0.5 m cell grid, the
          // reading is in the unit on screen.
          valueText: q == null
              ? 'none'
              : c.lf.dist(at.x, decimals: 2, keepZeros: true),
          value: at.x,
          min: kHmCellM / 2,
          max: f.widthM - kHmCellM / 2,
          divisions: (f.widthM / kHmCellM).round() - 1,
          onChanged: (double v) => c.inspect((x: v, y: at.y)),
          semanticValue: (double v) =>
              '${c.lf.distValue(v).toStringAsFixed(2)} ${c.lf.distUnitSpoken}',
        ),
        HmSlider(
          label: 'Inspected cell, down',
          // Cell centres; the slider stays on the 0.5 m cell grid, the
          // reading is in the unit on screen.
          valueText: q == null
              ? 'none'
              : c.lf.dist(at.y, decimals: 2, keepZeros: true),
          value: at.y,
          min: kHmCellM / 2,
          max: f.depthM - kHmCellM / 2,
          divisions: (f.depthM / kHmCellM).round() - 1,
          onChanged: (double v) => c.inspect((x: at.x, y: v)),
          semanticValue: (double v) =>
              '${c.lf.distValue(v).toStringAsFixed(2)} ${c.lf.distUnitSpoken}',
        ),
      ],
    );
  }
}

// ── Readouts ────────────────────────────────────────────────────────────────

class _ReadoutsCard extends StatelessWidget {
  const _ReadoutsCard(this.c);

  final HeatMapBuilderController c;

  @override
  Widget build(BuildContext context) {
    final HmMap m = c.map;
    return HmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const HmSectionLabel('How good is this map?'),
          const SizedBox(height: AppSpacing.xxs),
          HmRow(label: 'Samples', value: '${c.points.length}'),
          HmRow(
            label: 'Root mean square error (RMSE)',
            value: m.rmseDb == null
                ? 'no data'
                : '${m.rmseDb!.toStringAsFixed(1)} dB',
            emphasize: m.rmseDb != null,
          ),
          HmRow(
            label: 'Largest error',
            value: m.maxErrorDb == null
                ? 'no data'
                : '${fmtSignedDb(m.maxErrorDb!)} at '
                      '${c.lf.distValue(m.maxErrorCell!.x).toStringAsFixed(1)}, '
                      '${c.lf.dist(m.maxErrorCell!.y, decimals: 1, keepZeros: true)}',
          ),
          HmRow(
            label: 'Floor with no data (white)',
            value: '${(m.noDataShare * 100).toStringAsFixed(0)}%',
          ),
          const SizedBox(height: AppSpacing.xxs),
          const HmNote(
            'RMSE is the typical size of the map\'s error, in dB, over the '
            'cells that have data. Error is estimate minus truth: plus means '
            'the map promises more signal than is really there.',
          ),
        ],
      ),
    );
  }
}

// ── Method ──────────────────────────────────────────────────────────────────

class _MethodFields extends StatelessWidget {
  const _MethodFields(this.c, {this.first = false, this.compact = false});

  final HeatMapBuilderController c;

  /// True where this is the first place the surface names IDW.
  final bool first;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final HmSettings s = c.settings;
    final bool idw = s.method == HmMethod.idw;
    final String extrapNote = switch (s.extrapolation) {
      HmExtrapolation.off =>
        'Beyond the guess range the map stays white: no data.',
      HmExtrapolation.flatIdw =>
        'Beyond the guess range IDW keeps filling. It can never go below its '
            'weakest sample, so it goes flat while the real signal keeps '
            'falling.',
      HmExtrapolation.pathLoss =>
        'Beyond the guess range a log-distance model fitted to each AP\'s '
            'samples fills in. It follows distance but cannot see a wall no '
            'one measured across.',
    };
    // The toggle is bare; the heading above it (which can wrap) is where
    // IDW is spelled out.
    final Widget method = AppToggle<HmMethod>(
      value: s.method,
      semanticLabel: 'Interpolation method',
      expand: true,
      items: <AppToggleItem<HmMethod>>[
        for (final HmMethod m in HmMethod.values) (m, m.label),
      ],
      onChanged: (HmMethod m) => c.method = m,
    );
    final Widget power = HmSlider(
      label: idw || compact
          ? 'Power (p)'
          : 'Power (p): not used by nearest neighbor',
      valueText: fmtPower(s.power),
      value: s.power,
      min: kHmMinPower,
      max: kHmMaxPower,
      divisions: ((kHmMaxPower - kHmMinPower) * 2).round(),
      onChanged: idw ? (double v) => c.power = v : null,
      semanticValue: (double v) => 'power ${fmtPower(v)}',
    );
    final Widget range = HmSlider(
      label: 'Guess range',
      valueText: c.whole(s.guessRangeM),
      // Whole metres, or whole feet.
      value: c.lf.distValue(s.guessRangeM),
      min: (c.lf.distValue(kHmMinGuessRangeM) - 1e-9).ceilToDouble(),
      max: (c.lf.distValue(kHmMaxGuessRangeM) + 1e-9).floorToDouble(),
      divisions:
          ((c.lf.distValue(kHmMaxGuessRangeM) + 1e-9).floorToDouble() -
                  (c.lf.distValue(kHmMinGuessRangeM) - 1e-9).ceilToDouble())
              .round(),
      onChanged: (double v) => c.guessRangeM = c.lf.distToMetres(v),
      semanticValue: (double v) =>
          '${v.toStringAsFixed(0)} ${c.lf.distUnitSpoken}',
    );
    final Widget domain = AppToggle<HmDomain>(
      value: s.domain,
      label: compact ? null : 'Average the samples in',
      semanticLabel: 'Average the samples in',
      expand: true,
      items: const <AppToggleItem<HmDomain>>[
        (HmDomain.db, 'dB'),
        (HmDomain.mw, 'Milliwatts (mW)'),
      ],
      onChanged: (HmDomain d) => c.domain = d,
    );
    final Widget extrap = AppToggle<HmExtrapolation>(
      value: s.extrapolation,
      label: 'Beyond the guess range',
      semanticLabel: 'Extrapolation beyond the guess range',
      expand: true,
      items: <AppToggleItem<HmExtrapolation>>[
        for (final HmExtrapolation x in HmExtrapolation.values) (x, x.label),
      ],
      onChanged: (HmExtrapolation x) => c.extrapolation = x,
    );
    if (compact) {
      final TextStyle? label = Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(color: context.colors.textSecondary);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (first) ...<Widget>[
            const HmSectionLabel(
              'Method: inverse distance weighting (IDW) or nearest neighbor',
            ),
            const SizedBox(height: AppSpacing.xxs),
          ],
          method,
          Row(
            children: <Widget>[
              Expanded(child: power),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: range),
            ],
          ),
          Row(
            children: <Widget>[
              Text('Average in', style: label),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: domain),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          extrap,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        HmSectionLabel(
          first
              ? 'Method: inverse distance weighting (IDW) or nearest neighbor'
              : 'Method',
        ),
        const SizedBox(height: AppSpacing.xxs),
        method,
        power,
        domain,
        const SizedBox(height: AppSpacing.xxs),
        const HmNote(
          'Which domain survey products use is not published. Averaging '
          'in milliwatts leans toward the strongest sample.',
        ),
        const SizedBox(height: AppSpacing.xs),
        range,
        const HmNote(
          'How far the map may guess from a sample, also called the '
          'accuracy distance or interpolation distance.',
        ),
        const SizedBox(height: AppSpacing.xs),
        extrap,
        const SizedBox(height: AppSpacing.xxs),
        HmNote(extrapNote),
      ],
    );
  }
}

// ── Noise ───────────────────────────────────────────────────────────────────

class _NoiseCard extends StatelessWidget {
  const _NoiseCard(this.c, {this.compact = false});

  final HeatMapBuilderController c;

  /// Presenter fold: the explanatory note is dropped.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final HmNoise n = c.noise;
    return HmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const HmSectionLabel('Measurement noise (illustrative)'),
          HmSlider(
            label: 'Noise on one reading, sigma',
            valueText: '${n.sigmaDb.toStringAsFixed(1)} dB',
            value: n.sigmaDb,
            min: 0,
            max: kHmMaxSigmaDb,
            divisions: (kHmMaxSigmaDb * 2).round(),
            onChanged: (double v) => c.sigmaDb = v,
            semanticValue: (double v) => '${v.toStringAsFixed(1)} dB',
          ),
          HmSlider(
            label: 'Readings averaged per point',
            valueText: '${n.averaging}',
            value: n.averaging.toDouble(),
            min: 1,
            max: kHmMaxAveraging.toDouble(),
            divisions: kHmMaxAveraging - 1,
            onChanged: (double v) => c.averaging = v.round(),
            semanticValue: (double v) => '${v.round()} readings',
          ),
          HmRow(
            label: 'Noise left after averaging',
            value: '${n.effectiveSigmaDb.toStringAsFixed(1)} dB',
          ),
          const SizedBox(height: AppSpacing.xxs),
          HmOutlineButton(
            icon: Icons.refresh_rounded,
            label: 'Take the samples again',
            semanticLabel: 'Take every sample again with new noise',
            onPressed: n.sigmaDb > 0 && c.hasSamples ? c.rerun : null,
          ),
          if (!compact) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            const HmNote(
              'Each reading wanders around the true level (fading). '
              'Averaging N readings shrinks that by the square root of N.',
            ),
          ],
        ],
      ),
    );
  }
}

// ── Lesson, wall, experiment ────────────────────────────────────────────────

class _LessonCard extends StatelessWidget {
  const _LessonCard(this.c);

  final HeatMapBuilderController c;

  @override
  Widget build(BuildContext context) {
    return HmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const HmSectionLabel('Predict, then reveal'),
          const SizedBox(height: AppSpacing.xxs),
          const HmNote(
            'Three dots can paint the whole floor green. Should they? Start '
            'with three samples, then reveal a wider guess range, then the '
            'hidden wall.',
          ),
          const SizedBox(height: AppSpacing.xs),
          _LessonButtons(c),
        ],
      ),
    );
  }
}

class _LessonButtons extends StatelessWidget {
  const _LessonButtons(this.c);

  final HeatMapBuilderController c;

  @override
  Widget build(BuildContext context) {
    final String next = switch (c.lesson) {
      HmLessonStep.off => 'Start: three dots',
      HmLessonStep.predict => 'Reveal: widen the guess range',
      HmLessonStep.widened => 'Reveal: the hidden wall',
      HmLessonStep.wallRevealed => 'End the lesson',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        HmFilledButton(
          icon: c.lesson == HmLessonStep.wallRevealed
              ? Icons.check_rounded
              : Icons.visibility_outlined,
          label: next,
          onPressed: c.nextReveal,
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: <Widget>[
            Expanded(
              flex: 2,
              child: HmOutlineButton(
                icon: c.wallRevealed
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                label: c.wallRevealed ? 'Hide wall' : 'Reveal wall',
                semanticLabel: c.wallRevealed
                    ? 'Hide the hidden wall again'
                    : 'Reveal the hidden wall',
                onPressed: () => c.wallRevealed = !c.wallRevealed,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              flex: 3,
              child: HmOutlineButton(
                icon: Icons.show_chart_rounded,
                label: 'Spacing experiment',
                semanticLabel:
                    'Run the spacing experiment: grids at '
                    '${c.experimentSpacingsShown.take(5).map((double v) => v.toStringAsFixed(0)).join(', ')} and '
                    '${c.experimentSpacingsShown.last.toStringAsFixed(0)} '
                    '${c.lf.distUnitSpoken}',
                onPressed: c.runExperiment,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Worked example ──────────────────────────────────────────────────────────

class _WorkedExampleCard extends StatelessWidget {
  const _WorkedExampleCard(this.c);

  final HeatMapBuilderController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final HmSettings s = c.settings;
    final bool nearest = s.method == HmMethod.nearest;
    // Imperial shows 5, 10 and 15 ft: the same 1 : 2 : 3 ratios as 2, 4 and
    // 6 m, so the shares and the result are the same; the raw weights are
    // computed from the distances on screen so the arithmetic checks.
    final List<double> ds = c.units.isMetric
        ? HmWorkedExample.distancesM
        : const <double>[5, 10, 15];
    final List<double> w = idwWeights(ds, s.power);
    final double sw = w.fold(0, (double a, double b) => a + b);
    final List<double> shares = nearest
        ? const <double>[1, 0, 0]
        : <double>[for (final double x in w) x / sw];
    final double result = HmWorkedExample.result(
      s.power,
      s.domain,
      nearest: nearest,
    );
    final String how = nearest
        ? 'nearest neighbor'
        : 'power ${fmtPower(s.power)}, averaged in '
              '${s.domain == HmDomain.db ? 'dB' : 'milliwatts'}';
    return HmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const HmSectionLabel('Worked example: one cell, three samples'),
          const SizedBox(height: AppSpacing.xxs),
          Semantics(
            label:
                'A cell ${ds[0].toStringAsFixed(0)}, ${ds[1].toStringAsFixed(0)} '
                'and ${ds[2].toStringAsFixed(0)} ${c.lf.distUnitSpoken} from '
                'samples of minus 55, minus 65 '
                'and minus 70 dBm. Line thickness shows each weight.',
            excludeSemantics: true,
            child: SizedBox(
              height: 120,
              child: CustomPaint(
                painter: HmWorkedExamplePainter(
                  shares: shares,
                  line: colors.textAccent,
                  cell: colors.textPrimary,
                  sample: colors.textAccent,
                  label: colors.textSecondary,
                  sc: sc,
                  font: mono.inlineCode,
                  distancesShown: ds,
                  unitLabel: c.lf.distUnit,
                ),
              ),
            ),
          ),
          for (int i = 0; i < 3; i++)
            HmRow(
              label:
                  '${HmWorkedExample.valuesDbm[i].toStringAsFixed(0)} dBm at '
                  '${ds[i].toStringAsFixed(0)} ${c.lf.distUnit}',
              value: nearest
                  ? (i == 0 ? 'weight 1 (nearest)' : 'weight 0')
                  : 'weight ${_fmtWeight(w[i])} '
                        '(${(shares[i] * 100).toStringAsFixed(0)}%)',
            ),
          HmRow(
            label: 'Cell estimate ($how)',
            value: fmtDbm(result),
            emphasize: true,
          ),
          Text(
            nearest
                ? 'Nearest neighbor copies the closest sample.'
                : 'z = sum(w x z) / sum(w), with w = 1 / d^p',
            style: mono.inlineCode.copyWith(
              color: colors.textTertiary,
              fontSize: AppTextSize.caption,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtWeight(double w) =>
      w >= 0.1 ? w.toStringAsFixed(3) : w.toStringAsFixed(4);
}

// ── Floor ───────────────────────────────────────────────────────────────────

class _FloorCard extends StatelessWidget {
  const _FloorCard(this.c);

  final HeatMapBuilderController c;

  @override
  Widget build(BuildContext context) {
    final HmFloor f = c.floor;
    return HmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const HmSectionLabel('The floor (the truth the samples read)'),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'APs',
            semanticLabel: 'Number of APs',
            field: AppSelect<int>(
              value: c.apCount,
              semanticLabel: 'Number of APs',
              items: <AppSelectItem<int>>[
                for (int n = kHmMinAps; n <= kHmMaxAps; n++)
                  (n, n == 1 ? '1 AP' : '$n APs'),
              ],
              onChanged: (int n) => c.apCount = n,
            ),
          ),
          HmSlider(
            label: 'Path-loss exponent (n)',
            valueText: f.pathLossExponent.toStringAsFixed(1),
            value: f.pathLossExponent,
            min: 2,
            max: 4,
            divisions: 20,
            onChanged: (double v) => c.pathLossExponent = v,
            semanticValue: (double v) => 'n ${v.toStringAsFixed(1)}',
          ),
          HmRow(
            label: 'Each AP radiates',
            value: '${f.eirpDbm.toStringAsFixed(0)} dBm on 5 GHz',
          ),
          HmRow(
            label: 'Walls',
            value:
                '${f.walls.where((HmWall w) => !w.hidden).length} drawn, '
                '${f.walls.where((HmWall w) => w.hidden).length} hidden',
          ),
        ],
      ),
    );
  }
}
