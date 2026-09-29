// MultipathControls: the inputs-and-readouts half of the Multipath Simulator.
//
// Takes the shared MultipathController and a set of parts to show, so the
// phone layout can put setup and inputs above MultipathStage and the readouts
// below it, while a presenter layout shows every part in one column beside
// the stage. No part draws a plot; MultipathStage owns those.
//
// Control types follow GL-003 §8.14: scene, band and reflector range are
// three-option AppToggles; the four-option wall material is an AppSelect.
// The only status hue is the guard-interval verdict (§8.13 rule 6): a copy
// that arrives after 0.8 us is tinted statusWarning with an icon and the
// words "past GI"; copies within it stay neutral (§8.15.1).
//
// PRESENTER: inside a PresenterLayout the panel shows setup and inputs
// without their explanatory prose, folds the delay list into a
// PresenterDisclosure, and leaves the received level and the fade figures
// to the stage. The Antennas and Combine toggles move to the stage's plot
// header there.
//
// DIVERSITY (2026-09-29, spec 41): Many paths adds an Antennas toggle (2 or
// 4) and a Combine toggle (A only / Selection / MRC), a combined row in the
// received readout, and a "Diversity gain at 1%" card with the textbook
// Rayleigh figures beside what this track shows.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/multipath_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../../../units/unit_system.dart';
import '../labeled_field.dart';
import 'multipath_simulator_controller.dart';
import 'multipath_simulator_parts.dart';

typedef _C = MultipathController;

/// The groups MultipathControls can show.
enum MultipathControlPart {
  /// Scene and band.
  setup,

  /// Wall material and receiver position, or reflectors and antennas.
  inputs,

  /// Received power, diversity, delays and the explainer.
  readouts,
}

/// Delay rows shown before "Show all paths".
const int kMultipathShortPathList = 5;

class MultipathControls extends StatelessWidget {
  const MultipathControls({
    super.key,
    required this.controller,
    this.parts = const <MultipathControlPart>{
      MultipathControlPart.setup,
      MultipathControlPart.inputs,
      MultipathControlPart.readouts,
    },
  });

  final MultipathController controller;
  final Set<MultipathControlPart> parts;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final MultipathController c = controller;
        final bool presenter = PresenterMode.isActive(context);
        final List<Widget> cards = presenter
            ? <Widget>[
                _SetupCard(c),
                if (c.isManyPaths) _ReflectorsCard(c) else _WallCard(c),
                PresenterDisclosure(
                  title: c.isManyPaths
                      ? 'How late each copy arrives'
                      : 'How late the reflected copy arrives',
                  children: <Widget>[_DelayCard(c)],
                ),
              ]
            : <Widget>[
                if (parts.contains(MultipathControlPart.setup)) _SetupCard(c),
                if (parts.contains(MultipathControlPart.inputs)) ...<Widget>[
                  if (c.isManyPaths) _ReflectorsCard(c) else _WallCard(c),
                ],
                if (parts.contains(MultipathControlPart.readouts)) ...<Widget>[
                  _ReceivedCard(c),
                  if (c.isManyPaths) ...<Widget>[
                    _DiversityCard(c),
                    _GainCard(c),
                  ],
                  _DelayCard(c),
                  _ExplainerCard(c),
                ],
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

// ── Setup ───────────────────────────────────────────────────────────────────

class _SetupCard extends StatelessWidget {
  const _SetupCard(this.c);

  final MultipathController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Three options, but the labels wrap as segments at phone width,
          // so GL-003 §8.14 routes this to the Select.
          LabeledField(
            label: 'Scene',
            semanticLabel: 'Scene',
            field: AppSelect<MultipathMode>(
              value: c.mode,
              semanticLabel: 'Scene',
              items: <AppSelectItem<MultipathMode>>[
                for (final MultipathMode m in MultipathMode.values)
                  (m, m.menuLabel),
              ],
              onChanged: (MultipathMode m) => c.mode = m,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<MultipathBand>(
            label: 'Band',
            value: c.band,
            expand: true,
            items: <AppToggleItem<MultipathBand>>[
              for (final MultipathBand b in MultipathBand.values) (b, b.label),
            ],
            onChanged: (MultipathBand b) => c.band = b,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Wavelength λ = ${_C.len(c.band.wavelength, UnitSystemScope.systemOf(context), 2)}, so λ/2 = '
            '${_C.len(c.band.wavelength / 2, UnitSystemScope.systemOf(context), 2)}.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ── Modes 1 and 2: wall and receiver ────────────────────────────────────────

class _WallCard extends StatelessWidget {
  const _WallCard(this.c);

  final MultipathController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final double g = c.gammaMagnitude;
    final double ripple = StandingWaveScene.rippleDb(g);
    final bool one = c.mode == MultipathMode.oneWall;
    final double pos = one ? c.trackOffset : c.wallDistance;
    final String gammaText = g == 0
        ? 'No reflection: the direct path alone.'
        : 'The wall sends back '
              '${(g * g * 100).toStringAsFixed(g < 0.2 ? 1 : 0)}% of the power '
              'that hits it, flipped in phase (180 deg). '
              '${ripple.isFinite ? 'In front of it the signal swings by up to ${ripple.toStringAsFixed(1)} dB.' : 'In front of it the two copies can cancel completely.'}';
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LabeledField(
            label: 'Wall material',
            semanticLabel: 'Wall material',
            field: AppSelect<WallMaterial>(
              value: c.material,
              semanticLabel: 'Wall material',
              items: <AppSelectItem<WallMaterial>>[
                for (final WallMaterial m in WallMaterial.values)
                  (
                    m,
                    m.gammaMagnitude == null
                        ? m.label
                        : '${m.label} (|Γ| '
                              '${m.gammaMagnitude!.toStringAsFixed(2)})',
                  ),
              ],
              onChanged: (WallMaterial m) => c.material = m,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          MpSliderHeader(
            label: 'Reflection strength |Γ|',
            value: g.toStringAsFixed(2),
          ),
          Slider(
            value: g,
            divisions: 100,
            onChanged: (double v) => c.gammaMagnitude = v,
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            label: g.toStringAsFixed(2),
            semanticFormatterCallback: (double v) =>
                'Reflection strength ${v.toStringAsFixed(2)}',
          ),
          if (!PresenterMode.isActive(context))
            Text(
              gammaText,
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          const SizedBox(height: AppSpacing.md),
          MpSliderHeader(
            label: one ? 'Receiver position' : 'Distance to the wall',
            value: _C.len(pos, UnitSystemScope.systemOf(context)),
          ),
          Slider(
            value: pos,
            max: one
                ? MultipathController.twoRay.trackLength
                : MultipathController.standing.range,
            divisions: one ? 1000 : 800,
            onChanged: (double v) {
              if (one) {
                c.trackOffset = v;
              } else {
                c.wallDistance = v;
              }
            },
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            label: _C.len(pos, UnitSystemScope.systemOf(context)),
            semanticFormatterCallback: (double v) => one
                ? 'Receiver position ${_C.len(v, UnitSystemScope.systemOf(context))}'
                : 'Distance to the wall ${_C.len(v, UnitSystemScope.systemOf(context))}',
          ),
          if (!PresenterMode.isActive(context))
            MpNote(
              icon: Icons.swipe,
              message:
                  'Drag the receiver in the picture or on the plot, or use this '
                  'slider. Arrow keys move it '
                  '${UnitSystemScope.systemOf(context).isMetric ? (one ? '1 mm' : '0.5 mm') : (one ? '0.04 in' : '0.02 in')} at a time.',
            ),
        ],
      ),
    );
  }
}

// ── Mode 3: reflectors and antennas ─────────────────────────────────────────

class _ReflectorsCard extends StatelessWidget {
  const _ReflectorsCard(this.c);

  final MultipathController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MpSliderHeader(label: 'Reflectors', value: '${c.reflectorCount}'),
          Slider(
            value: c.reflectorCount.toDouble(),
            min: 2,
            max: 30,
            divisions: 28,
            onChanged: (double v) => c.reflectorCount = v.round(),
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            label: '${c.reflectorCount}',
            semanticFormatterCallback: (double v) => '${v.round()} reflectors',
          ),
          AppToggle<ScatterEnvironment>(
            label: 'Reflectors up to',
            value: c.environment,
            expand: true,
            items: <AppToggleItem<ScatterEnvironment>>[
              for (final ScatterEnvironment e in ScatterEnvironment.values)
                (e, _C.dist(e.maxRadius, UnitSystemScope.systemOf(context))),
            ],
            onChanged: (ScatterEnvironment e) => c.environment = e,
          ),
          if (!PresenterMode.isActive(context)) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '${c.environment.label}. The direct path is blocked, so every '
              'copy is a reflection, each with equal power and a random '
              'phase.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Layout ${c.layout}',
                  style: text.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ),
              Semantics(
                button: true,
                label: 'New layout: place the reflectors somewhere else',
                excludeSemantics: true,
                child: OutlinedButton.icon(
                  onPressed: c.newLayout,
                  icon: Icon(Icons.shuffle_rounded, color: colors.textAccent),
                  label: Text(
                    'New layout',
                    style: text.labelLarge?.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.textAccent,
                    side: BorderSide(color: colors.borderStrong, width: 1.5),
                    minimumSize: const Size(0, AppSpacing.minTouchTarget),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          MpSliderHeader(
            label: 'Antenna A position',
            value: _C.len(c.antennaX, UnitSystemScope.systemOf(context)),
          ),
          Slider(
            value: c.antennaX,
            max: 2,
            divisions: 2000,
            onChanged: (double v) => c.antennaX = v,
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            label: _C.len(c.antennaX, UnitSystemScope.systemOf(context)),
            semanticFormatterCallback: (double v) =>
                'Antenna A position ${_C.len(v, UnitSystemScope.systemOf(context))}',
          ),
          MpSliderHeader(
            label: c.antennaCount == 2
                ? 'Antenna B offset (λ)'
                : 'Antenna spacing (λ)',
            value:
                '${c.offsetLambda.toStringAsFixed(2)} = '
                '${_C.len(c.offsetMeters, UnitSystemScope.systemOf(context))}',
          ),
          Slider(
            value: c.offsetLambda,
            divisions: 20,
            onChanged: (double v) => c.offsetLambda = v,
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            label: '${c.offsetLambda.toStringAsFixed(2)} λ',
            semanticFormatterCallback: (double v) =>
                'Antenna B offset ${v.toStringAsFixed(2)} wavelengths',
          ),
          // In Presenter both diversity toggles sit on the stage, in the
          // plot's header.
          if (!PresenterMode.isActive(context)) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            AntennaCountToggle(controller: c, label: 'Antennas'),
            const SizedBox(height: AppSpacing.sm),
            CombineToggle(controller: c, label: 'Combine'),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              switch (c.combine) {
                CombineMethod.aOnly => 'Antenna A on its own, as a radio '
                    'with one antenna hears it.',
                CombineMethod.selection => 'The receiver uses whichever '
                    'antenna is stronger at each spot.',
                CombineMethod.mrc => 'The receiver adds every antenna, '
                    'each aligned in phase and weighted by its strength.',
              },
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Readouts ────────────────────────────────────────────────────────────────

class _ReceivedCard extends StatelessWidget {
  const _ReceivedCard(this.c);

  final MultipathController c;

  @override
  Widget build(BuildContext context) {
    final bool many = c.isManyPaths;
    final double db = c.receivedDb;
    final List<Widget> rows = <Widget>[
      MpRow(
        label: many ? 'Antenna A' : 'Received',
        value: _C.db(db),
        emphasize: true,
      ),
    ];
    if (many) {
      rows.add(
        MpRow(
          label: 'Antenna B',
          value: _C.db(
            c.scene.normalizedPowerDb(c.antennaX + c.offsetMeters, c.band),
          ),
        ),
      );
      if (c.isCombining) {
        rows[0] = MpRow(label: 'Antenna A', value: _C.db(db));
        rows.add(
          MpRow(
            label: 'Combined (${c.combine.label})',
            value: _C.db(c.combinedDb),
            emphasize: true,
          ),
        );
      }
    } else {
      final List<Complex> ph = c.phasors;
      final List<double> trace = c.traceA;
      rows
        ..add(
          MpRow(
            label: 'Reflected arrow',
            value: '${ph[1].abs.toStringAsFixed(2)} long at ${_C.deg(ph[1])}',
          ),
        )
        ..add(
          MpRow(
            label: 'Sum arrow',
            value: '${MultipathMath.sum(ph).abs.toStringAsFixed(2)} long',
          ),
        );
      if (c.mode == MultipathMode.oneWall) {
        double lo = trace.first, hi = trace.first;
        for (final double v in trace) {
          if (v < lo) lo = v;
          if (v > hi) hi = v;
        }
        rows.add(
          MpRow(
            label: 'Along the track',
            value: '${_C.db(lo)} to ${_C.db(hi)}',
          ),
        );
      } else {
        final List<double> nulls = c.nulls;
        final double half = c.band.wavelength / 2;
        if (nulls.length >= 2) {
          rows.add(
            MpRow(
              label: 'Dips measured',
              value:
                  'every '
                  '${_C.len((nulls.last - nulls.first) / (nulls.length - 1), UnitSystemScope.systemOf(context), 2)}',
            ),
          );
        }
        rows.add(
          MpRow(
            label: 'Half wavelength',
            value: _C.len(half, UnitSystemScope.systemOf(context), 2),
          ),
        );
        double lo = trace[1];
        for (final double v in trace.skip(1)) {
          if (v < lo) lo = v;
        }
        rows.add(MpRow(label: 'Deepest dip', value: _C.db(lo)));
      }
    }
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MpSectionLabel(
            many
                ? 'At the receiver, against the average'
                : 'At the receiver, against the direct copy alone',
          ),
          const SizedBox(height: AppSpacing.xxs),
          ...rows,
        ],
      ),
    );
  }
}

class _DiversityCard extends StatelessWidget {
  const _DiversityCard(this.c);

  final MultipathController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final FadeStats f = c.fade;
    final bool two = c.antennaCount == 2;
    final bool combining = c.isCombining;
    final bool mrc = combining && c.combine == CombineMethod.mrc;
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MpSectionLabel(
            '${two ? 'Two' : 'Four'} antennas: how often below -10 dB',
          ),
          const SizedBox(height: AppSpacing.xxs),
          MpRow(label: 'Antenna A', value: _C.pct(f.fractionA)),
          MpRow(label: 'Antenna B', value: _C.pct(f.fractionB)),
          MpRow(
            label: two ? 'Both at once' : 'All four at once',
            value: _C.pct(c.allFadedFraction),
            emphasize: !mrc,
          ),
          if (mrc)
            MpRow(
              label: 'Combined (MRC)',
              value: _C.pct(c.combinedFadeFraction),
              emphasize: true,
            ),
          const MpRow(label: 'Rayleigh, one', value: '9.5%'),
          if (combining)
            MpRow(
              label: 'Rayleigh, ${c.combine.label}',
              value: _C.pctFine(c.rayleighFadeFraction(c.combine)),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'A receiver that picks the stronger antenna is faded only when '
            '${two ? 'both are' : 'all four are'}. At 0 λ the antennas are '
            'the same antenna. Near 0.5 λ apart they rarely fade together; '
            'if they faded independently, ${two ? 'both' : 'all four'} at '
            'once would be about ${_C.pctFine(c.rayleighFadeFraction(CombineMethod.selection))}. '
            'MRC does better still, because two weak antennas added together '
            'can clear -10 dB when neither does alone.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Diversity gain at 1%: the textbook Rayleigh figure for each method with
/// this many antennas, and what this track shows for the chosen one.
class _GainCard extends StatelessWidget {
  const _GainCard(this.c);

  final MultipathController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final int n = c.antennaCount;
    final double? track = c.trackGainDb;
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MpSectionLabel('Diversity gain at 1%, $n antennas'),
          const SizedBox(height: AppSpacing.xxs),
          MpRow(
            label: 'Selection',
            value: _C.gain(c.rayleighGainDb(CombineMethod.selection)),
            emphasize: c.combine == CombineMethod.selection,
          ),
          MpRow(
            label: 'MRC',
            value: _C.gain(c.rayleighGainDb(CombineMethod.mrc)),
            emphasize: c.combine == CombineMethod.mrc,
          ),
          if (track != null)
            MpRow(
              label: 'On this track',
              value: _C.gain(track),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Selection and MRC are the textbook (Rayleigh) figures. One '
            'antenna on its own is more than 20 dB below its average 1% of '
            'the time. The gain is how much of that the combined signal '
            'wins back. MRC adds the antennas\' power, so its trace '
            'averages ${n == 2 ? 'about 3 dB' : 'about 6 dB'} above one '
            'antenna. A ${_C.dist(2, UnitSystemScope.systemOf(context))} '
            'track holds only a few deep fades, so this track\'s figure '
            'wanders; New layout shows a different one.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _DelayCard extends StatelessWidget {
  const _DelayCard(this.c);

  final MultipathController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool many = c.isManyPaths;
    final List<MultipathDelayRow> all = c.delayRows;
    final List<MultipathDelayRow> rows = many && !c.showAllPaths
        ? all.take(kMultipathShortPathList).toList()
        : all;
    final int late = c.latePaths;
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MpSectionLabel(
            many
                ? 'How late each copy arrives (latest first)'
                : 'How late the reflected copy arrives',
          ),
          const SizedBox(height: AppSpacing.xxs),
          for (final MultipathDelayRow r in rows) _DelayRow(r),
          if (many && all.length > kMultipathShortPathList)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: c.toggleShowAllPaths,
                style: TextButton.styleFrom(
                  foregroundColor: colors.textAccent,
                  minimumSize: const Size(0, AppSpacing.minTouchTarget),
                ),
                child: Text(
                  c.showAllPaths
                      ? 'Show the latest $kMultipathShortPathList'
                      : 'Show all ${all.length} paths',
                ),
              ),
            ),
          if (many)
            MpRow(
              label: 'Past 0.8 µs',
              value: '$late of ${all.length}',
              valueColor: late > 0 ? colors.statusWarning : null,
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'A copy that travels '
            '${_C.dist(240, UnitSystemScope.systemOf(context))} further '
            'arrives 0.8 µs late, the '
            'length of the guard interval that protects each OFDM symbol. '
            'Later than that, it spills into the next symbol.'
            '${many && c.environment != ScatterEnvironment.outdoors ? ' Try ${_C.dist(ScatterEnvironment.outdoors.maxRadius, UnitSystemScope.systemOf(context))} reflectors.' : ''}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _DelayRow extends StatelessWidget {
  const _DelayRow(this.row);

  final MultipathDelayRow row;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final double ns = MultipathMath.delayNs(row.extraMeters);
    final bool past = MultipathMath.exceedsGuardInterval(ns);
    return Semantics(
      label:
          '${row.name}: ${_C.path(row.extraMeters, UnitSystemScope.systemOf(context))} longer, ${_C.ns(ns)} late, '
          '${past ? 'past the guard interval' : 'within the guard interval'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 80,
              child: Text(
                row.name,
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
            Expanded(
              child: Text(
                '+${_C.path(row.extraMeters, UnitSystemScope.systemOf(context))}  ${_C.ns(ns)}',
                style: mono.inlineCode.copyWith(color: colors.textPrimary),
              ),
            ),
            if (past) ...<Widget>[
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: colors.statusWarning,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'past GI',
                style: text.bodySmall?.copyWith(color: colors.statusWarning),
              ),
            ] else
              Text(
                'within GI',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
          ],
        ),
      ),
    );
  }
}

class _ExplainerCard extends StatelessWidget {
  const _ExplainerCard(this.c);

  final MultipathController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle? body = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary);
    final List<String> paras = switch (c.mode) {
      MultipathMode.oneWall => <String>[
        'The receiver hears the direct copy plus one that bounced off the '
            'wall. The bounced copy travels further, so it arrives later and '
            'with a different phase. Each copy is an arrow; what the receiver '
            'gets is their sum.',
        'Pointing the same way, the arrows add. Pointing opposite ways, they '
            'cancel. Move the receiver a few centimeters and the reflected '
            'arrow swings around, which is why RSSI jumps when you move a '
            'phone a hand width.',
      ],
      MultipathMode.standingWave => <String>[
        'The wave coming in and the wave coming back off the wall overlap. '
            'Every half wavelength you step closer, the reflected copy loses '
            'one full turn against the direct one, so the dips repeat every '
            'λ/2: ${UnitSystemScope.systemOf(context).isMetric ? '6.2 cm at 2.4 GHz, 2.7 cm at 5.5 GHz, 2.3 cm at 6.5 GHz' : '2.42 in at 2.4 GHz, 1.07 in at 5.5 GHz, 0.91 in at 6.5 GHz'}.',
        'Metal sends almost everything back, so the dips go to nothing. A '
            'weaker reflector gives shallower dips: thick concrete swings '
            'about 7 dB.',
      ],
      MultipathMode.manyPaths => <String>[
        'With many copies from many directions, the arrows point every which '
            'way and their sum wanders at random. The power follows the '
            'Rayleigh pattern: about 9.5% of spots sit more than 10 dB below '
            'the average, and a few are far deeper.',
        'That is why one RSSI sample means little, and why a second antenna '
            'helps: half a wavelength away, it rarely sits in a dip at the '
            'same spot.',
        'Combine shows what the receiver does with the antennas. Selection '
            'keeps the stronger one; MRC (maximal ratio combining) adds them '
            'all, lined up in phase. Both fill in the dips, and MRC fills '
            'them further.',
      ],
    };
    return MpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MpSectionLabel('What you are seeing'),
          const SizedBox(height: AppSpacing.xs),
          for (int i = 0; i < paras.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSpacing.xs),
            Text(paras[i], style: body),
          ],
        ],
      ),
    );
  }
}
