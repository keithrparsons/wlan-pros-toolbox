// PredictMeasureControls: the inputs-and-readouts half of Predict, Then
// Measure.
//
// Takes the shared PredictMeasureController. The phone layout shows every
// card; the presenter layout shows a compact panel beside the stage with the
// rarely used settings behind disclosures. No part draws the map;
// PredictMeasureStage owns that.
//
// Control types follow GL-003 §8.14: two- and three-option choices are
// AppToggles (tap action, scenario), the wall list is an AppSelect. No
// status hues: a difference in dB is a measurement, not a verdict (§8.13
// rule 6).
//
// ACRONYMS (Keith's standing rule): IDW is spelled out the first time a
// surface shows it; AP, dBm and RSSI are the standing exceptions.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/predict_measure_engine.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../units/length_format.dart';
import '../labeled_field.dart';
import 'heat_map_builder_parts.dart';
import 'predict_measure_controller.dart';

class PredictMeasureControls extends StatelessWidget {
  const PredictMeasureControls({super.key, required this.controller});

  final PredictMeasureController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final PredictMeasureController c = controller;
        if (PresenterMode.isActive(context)) return _PresenterPanel(c);
        final List<Widget> cards = <Widget>[
          HmCard(child: _WalkFields(c)),
          _ReadoutsCard(c),
          HmCard(child: _ModelButtons(c)),
          HmCard(child: _WallFields(c)),
          HmCard(child: _WallTable(c)),
          HmCard(child: _ApFields(c)),
          HmCard(child: _ScenarioFields(c)),
          HmCard(child: _InstructorFields(c)),
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

  final PredictMeasureController c;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        HmCard(child: _ScenarioFields(c, compact: true)),
        const SizedBox(height: AppSpacing.xs),
        HmCard(child: _WalkFields(c, compact: true)),
        const SizedBox(height: AppSpacing.xs),
        HmCard(child: _ModelButtons(c)),
        PresenterDisclosure(
          title: 'Wall losses: the design',
          children: <Widget>[
            HmCard(child: _WallFields(c, compact: true)),
            const SizedBox(height: AppSpacing.xs),
            HmCard(child: _WallTable(c)),
          ],
        ),
        PresenterDisclosure(
          title: 'AP position',
          children: <Widget>[HmCard(child: _ApFields(c))],
        ),
        PresenterDisclosure(
          title: 'Instructor: the hidden truth',
          children: <Widget>[HmCard(child: _InstructorFields(c))],
        ),
      ],
    );
  }
}

// ── The walk ────────────────────────────────────────────────────────────────

class _WalkFields extends StatelessWidget {
  const _WalkFields(this.c, {this.compact = false});

  final PredictMeasureController c;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final String count =
        '${c.sampleCount} ${c.sampleCount == 1 ? 'sample' : 'samples'} on '
        '${c.legs.length} ${c.legs.length == 1 ? 'leg' : 'legs'}';
    final Widget tap = AppToggle<PmTapAction>(
      value: c.tapAction,
      label: compact ? null : 'A tap or drag on the floor will',
      semanticLabel: 'What a tap or drag on the floor does',
      expand: true,
      items: <AppToggleItem<PmTapAction>>[
        for (final PmTapAction a in PmTapAction.values) (a, a.label),
      ],
      onChanged: (PmTapAction a) => c.tapAction = a,
    );
    final Widget oneSide = HmOutlineButton(
      icon: Icons.east_rounded,
      label: compact ? 'One side' : 'One side only',
      semanticLabel: 'Walk the corridor, staying on one side of every wall',
      onPressed: c.useOneSideWalk,
    );
    final Widget both = HmOutlineButton(
      icon: Icons.swap_vert_rounded,
      label: compact ? 'Both sides' : 'Both sides of every wall',
      semanticLabel: 'Walk a short leg across every wall',
      onPressed: c.useBothSidesWalk,
    );
    final Widget undo = IconButton(
      onPressed: c.hasWalk ? c.undoLeg : null,
      tooltip: 'Remove the last leg of the walk',
      icon: const Icon(Icons.undo_rounded),
      color: colors.textAccent,
    );
    final Widget clear = IconButton(
      onPressed: c.hasWalk ? c.clearWalk : null,
      tooltip: 'Clear the walk',
      icon: const Icon(Icons.delete_sweep_outlined),
      color: colors.textAccent,
    );
    final Widget noise = HmSlider(
      label: compact
          ? 'Noise (illustrative)'
          : 'Noise on each sample (illustrative)',
      valueText: '${c.sigmaDb.toStringAsFixed(1)} dB',
      value: c.sigmaDb,
      min: 0,
      max: kPmMaxSigmaDb,
      divisions: (kPmMaxSigmaDb * 2).round(),
      onChanged: (double v) => c.sigmaDb = v,
      semanticValue: (double v) => '${v.toStringAsFixed(1)} dB',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!compact) ...<Widget>[
          const HmSectionLabel('The walk: AP on a stick survey'),
          const SizedBox(height: AppSpacing.xs),
        ],
        tap,
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: <Widget>[
            Expanded(child: oneSide),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: both),
            if (compact) ...<Widget>[undo, clear],
          ],
        ),
        if (!compact)
          Row(
            children: <Widget>[
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    c.walkFull
                        ? '$count. The walk is full ($kPmMaxSamples samples).'
                        : count,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
              undo,
              clear,
            ],
          ),
        noise,
        if (!compact && !c.hasWalk)
          const HmNote(
            'No walk yet, so the Measured and Difference maps are white: no '
            'data. Drag on the floor to walk (each drag is one leg; a tap '
            'continues the last leg), or pick a walk above. A sample is '
            'taken every meter.',
          ),
      ],
    );
  }
}

// ── Readouts ────────────────────────────────────────────────────────────────

class _ReadoutsCard extends StatelessWidget {
  const _ReadoutsCard(this.c);

  final PredictMeasureController c;

  @override
  Widget build(BuildContext context) {
    final PmMaps m = c.maps;
    final String target = kPmDesignTargetDbm.toStringAsFixed(0);
    return HmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const HmSectionLabel('Predicted vs measured'),
          const SizedBox(height: AppSpacing.xxs),
          HmRow(
            label: 'Walls tested',
            value: '${c.testedCount} of ${c.walls.length}',
            emphasize: true,
          ),
          HmRow(label: 'Walls untested', value: '${c.untestedCount}'),
          HmRow(
            label: 'Largest difference (measured minus predicted)',
            value: m.largestDiffDb == null
                ? 'no data'
                : '${fmtSignedDb(m.largestDiffDb!)} at '
                      '${c.coord(m.largestDiffAt!.x)}, '
                      '${c.len(m.largestDiffAt!.y)}',
          ),
          HmRow(
            label:
                'Floor where they differ by more than '
                '${kPmDiffThresholdDb.toStringAsFixed(0)} dB',
            value: m.diffOverShareOfMeasured == null
                ? '${fmtPct(m.diffOverShare)} (no data)'
                : '${fmtPct(m.diffOverShare)} '
                      '(${fmtPct(m.diffOverShareOfMeasured!)} of the '
                      'measured area)',
          ),
          HmRow(
            label: 'Floor the walk measured',
            value: fmtPct(m.measuredShare),
          ),
          HmRow(
            label: 'Below the $target dBm design target (illustrative)',
            value:
                'design ${fmtPct(m.predictedBelowTarget)}'
                '${m.measuredBelowTarget == null ? '' : ', measured ${fmtPct(m.measuredBelowTarget!)} of the measured area'}'
                '${c.revealed ? ', truth ${fmtPct(m.truthBelowTarget)}' : ''}',
          ),
          const SizedBox(height: AppSpacing.xxs),
          const HmNote(
            'The Difference map compares each sample with what the design '
            'predicted at that exact spot, then spreads those differences '
            'with inverse distance weighting (IDW), the method Heat Map '
            'Builder uses. Minus means the building is weaker than the '
            'design.',
          ),
        ],
      ),
    );
  }
}

// ── Update and reveal ───────────────────────────────────────────────────────

class _ModelButtons extends StatelessWidget {
  const _ModelButtons(this.c);

  final PredictMeasureController c;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: HmFilledButton(
            icon: Icons.published_with_changes_rounded,
            label: 'Update model',
            onPressed: c.canUpdateModel ? c.updateModel : null,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: HmOutlineButton(
            icon: c.revealed
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            label: c.revealed ? 'Hide the truth' : 'Reveal the truth',
            semanticLabel: c.revealed
                ? 'Hide the true wall losses'
                : 'Reveal the true wall losses',
            onPressed: c.toggleReveal,
          ),
        ),
      ],
    );
  }
}

// ── Wall losses ─────────────────────────────────────────────────────────────

class _WallFields extends StatelessWidget {
  const _WallFields(this.c, {this.compact = false});

  final PredictMeasureController c;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final PmWall w = c.selected;
    final int i = c.selectedWall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!compact) ...<Widget>[
          const HmSectionLabel('Wall losses in the design (illustrative)'),
          const SizedBox(height: AppSpacing.xs),
        ],
        LabeledField(
          label: 'Wall',
          semanticLabel: 'Wall to edit',
          field: AppSelect<int>(
            value: i,
            semanticLabel: 'Wall to edit',
            items: <AppSelectItem<int>>[
              for (int j = 0; j < c.walls.length; j++)
                (
                  j,
                  '${PredictMeasureController.wallName(j)}, '
                      '${c.walls[j].material.label.toLowerCase()}',
                ),
            ],
            onChanged: (int j) => c.selectedWall = j,
          ),
        ),
        HmSlider(
          label: '${PredictMeasureController.wallName(i)} design loss',
          valueText: fmtDb(w.predictedLossDb),
          value: w.predictedLossDb,
          min: kPmMinLossDb,
          max: kPmMaxLossDb,
          divisions: ((kPmMaxLossDb - kPmMinLossDb) * 2).round(),
          onChanged: (double v) => c.predictedLossDb = v,
          semanticValue: (double v) => '${v.toStringAsFixed(1)} dB',
        ),
        HmOutlineButton(
          icon: Icons.restart_alt_rounded,
          label:
              '${w.material.label} default, '
              '${fmtM(w.material.defaultLossDb)} dB',
          semanticLabel:
              'Set ${PredictMeasureController.wallName(i)} to the '
              '${w.material.label.toLowerCase()} default, '
              '${fmtM(w.material.defaultLossDb)} dB, illustrative',
          onPressed: w.predictedLossDb == w.material.defaultLossDb
              ? null
              : c.useMaterialDefault,
        ),
        if (!compact) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          HmNote(
            'Material defaults are illustrative, not measured: '
            '${PmMaterial.values.map((PmMaterial m) => '${m.label.toLowerCase()} ${fmtM(m.defaultLossDb)} dB').join(', ')}. '
            'Real walls of one material vary widely.',
          ),
        ],
      ],
    );
  }
}

/// Every wall: design, what the walk found, and the truth after the reveal.
class _WallTable extends StatelessWidget {
  const _WallTable(this.c);

  final PredictMeasureController c;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const HmSectionLabel('Every wall'),
        const SizedBox(height: AppSpacing.xxs),
        for (int i = 0; i < c.walls.length; i++)
          HmRow(
            label:
                '${PredictMeasureController.wallName(i)} '
                '${c.walls[i].material.label.toLowerCase()}',
            value: _line(i),
            emphasize: c.survey.isTested(i),
          ),
      ],
    );
  }

  String _line(int i) {
    final PmWall w = c.walls[i];
    final PmWallTest? t = c.survey.tests[i];
    return 'design ${fmtM(w.predictedLossDb)}'
        '${c.updatedWalls.contains(i) ? ' (updated)' : ''}, '
        '${t == null ? 'untested' : 'tested ${t.estimateDb.toStringAsFixed(1)}'}'
        '${c.revealed ? ', true ${fmtM(w.trueLossDb)}' : ''} dB';
  }
}

// ── The AP ──────────────────────────────────────────────────────────────────

class _ApFields extends StatelessWidget {
  const _ApFields(this.c);

  final PredictMeasureController c;

  @override
  Widget build(BuildContext context) {
    final PmModel m = c.model;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const HmSectionLabel('AP on a stick: where the design puts the AP'),
        HmSlider(
          label: 'AP across',
          valueText: c.len(c.ap.x),
          // 0.5 m steps, or whole feet (the controller snaps either way).
          value: c.ap.x,
          min: 0.5,
          max: m.widthM - 0.5,
          divisions: c.units.isMetric
              ? ((m.widthM - 1) * 2).round()
              : (LengthUnits.metresToFeet(m.widthM - 1)).round(),
          onChanged: (double v) => c.apX = v,
          semanticValue: (double v) => '${c.coord(v)} ${c.lf.distUnitSpoken}',
        ),
        HmSlider(
          label: 'AP down',
          valueText: c.len(c.ap.y),
          // 0.5 m steps, or whole feet (the controller snaps either way).
          value: c.ap.y,
          min: 0.5,
          max: m.depthM - 0.5,
          divisions: c.units.isMetric
              ? ((m.depthM - 1) * 2).round()
              : (LengthUnits.metresToFeet(m.depthM - 1)).round(),
          onChanged: (double v) => c.apY = v,
          semanticValue: (double v) => '${c.coord(v)} ${c.lf.distUnitSpoken}',
        ),
        HmNote(
          'The AP radiates ${fmtM(m.eirpDbm)} dBm effective isotropic '
          'radiated power (EIRP) on a 5 GHz channel, path-loss exponent '
          '${m.pathLossExponent.toStringAsFixed(1)}; both illustrative. '
          'Moving the AP walks the same path again from the new spot.',
        ),
      ],
    );
  }
}

// ── Scenario ────────────────────────────────────────────────────────────────

class _ScenarioFields extends StatelessWidget {
  const _ScenarioFields(this.c, {this.compact = false});

  final PredictMeasureController c;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Widget preset = AppToggle<PmPreset>(
      value: c.preset,
      label: compact ? null : 'Scenario (illustrative)',
      semanticLabel: 'Scenario, illustrative',
      expand: true,
      items: <AppToggleItem<PmPreset>>[
        for (final PmPreset p in PmPreset.values) (p, p.label),
      ],
      onChanged: (PmPreset p) => c.preset = p,
    );
    final Widget reset = HmOutlineButton(
      icon: Icons.restart_alt_rounded,
      label: compact ? 'Reset' : 'Reset scenario',
      semanticLabel:
          'Reset the scenario: the design, the AP, the walk and the reveal',
      onPressed: c.reset,
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          preset,
          const SizedBox(height: AppSpacing.xs),
          reset,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        preset,
        const SizedBox(height: AppSpacing.xs),
        reset,
        const SizedBox(height: AppSpacing.xxs),
        const HmNote(
          'Reset keeps the building\'s hidden truth. A new scenario loads '
          'its own floor, design and hidden truth.',
        ),
      ],
    );
  }
}

// ── Instructor ──────────────────────────────────────────────────────────────

class _InstructorFields extends StatelessWidget {
  const _InstructorFields(this.c);

  final PredictMeasureController c;

  @override
  Widget build(BuildContext context) {
    final PmWall w = c.selected;
    final int i = c.selectedWall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const HmSectionLabel('Instructor: the hidden truth (illustrative)'),
        const SizedBox(height: AppSpacing.xxs),
        HmNote(
          'By default two walls are much worse than the design and one is '
          'better, picked by seed ${c.seed}. Setting the truth here shows '
          'it to anyone watching.',
        ),
        HmSlider(
          label: '${PredictMeasureController.wallName(i)} true loss',
          valueText: fmtDb(w.trueLossDb),
          value: w.trueLossDb,
          min: kPmMinLossDb,
          max: kPmMaxLossDb,
          divisions: ((kPmMaxLossDb - kPmMinLossDb) * 2).round(),
          onChanged: (double v) => c.trueLossDb = v,
          semanticValue: (double v) => '${v.toStringAsFixed(1)} dB',
        ),
        HmOutlineButton(
          icon: Icons.casino_outlined,
          label: 'New hidden truth',
          semanticLabel: 'Pick a new hidden truth with the next seed',
          onPressed: c.newHiddenTruth,
        ),
      ],
    );
  }
}
