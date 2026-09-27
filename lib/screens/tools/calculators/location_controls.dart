// LocationControls: the inputs-and-readouts half of the "Where Am I?" tool.
//
// Takes the shared LocationController. The phone layout shows every card;
// the presenter layout shows a compact panel beside the stage with rarely
// used settings behind disclosures. No part draws the floor; LocationStage
// owns that.
//
// Control types follow GL-003 §8.14: the three-way method choice is an
// AppToggle, the AP count is an AppSelect, blocked paths are filter chips.
// The one status hue is the "impossible" note on the stage, a computed flag
// (§8.13 rule 6); an error size is a measurement, not a verdict.
//
// ILLUSTRATIVE VALUES (spec 33) are labeled on screen: the shadowing sigma,
// the power each AP radiates, and the blocked-path bias. The timing error is
// labeled with its source, a vendor developer document (1 to 2 m).
//
// ACRONYMS (Keith's standing rule): FTM and RTT are spelled out the first
// time each surface shows them.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/location_engine.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';
import '../labeled_field.dart';
import 'location_controller.dart';
import 'location_parts.dart';
import 'location_stage.dart' show locMethodShort;

class LocationControls extends StatelessWidget {
  const LocationControls({super.key, required this.controller});

  final LocationController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final LocationController c = controller;
        if (PresenterMode.isActive(context)) return _PresenterPanel(c);
        final List<Widget> cards = <Widget>[
          LocCard(child: _MethodFields(c)),
          _ReadoutsCard(c),
          _SignalCard(c),
          _TimingCard(c),
          _LessonCard(c),
          _FloorCard(c),
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

  final LocationController c;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LocCard(child: _MethodFields(c, compact: true)),
        const SizedBox(height: AppSpacing.xs),
        _SignalCard(c, compact: true),
        const SizedBox(height: AppSpacing.xs),
        _TimingCard(c, compact: true),
        PresenterDisclosure(
          title: 'Distances per AP',
          children: <Widget>[_ReadoutsCard(c)],
        ),
        PresenterDisclosure(
          title: 'Worked example and the speed of light',
          children: <Widget>[
            _WorkedExample(c),
            const SizedBox(height: AppSpacing.xs),
            _LightSpeed(c),
          ],
        ),
        PresenterDisclosure(
          title: 'The floor: APs and device position',
          children: <Widget>[_FloorCard(c)],
        ),
      ],
    );
  }
}

// ── Method ──────────────────────────────────────────────────────────────────

class _MethodFields extends StatelessWidget {
  const _MethodFields(this.c, {this.compact = false});

  final LocationController c;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Widget toggle = AppToggle<LocView>(
      value: c.view,
      semanticLabel: 'Ranging method',
      expand: true,
      items: <AppToggleItem<LocView>>[
        for (final LocView v in LocView.values) (v, v.label),
      ],
      onChanged: (LocView v) => c.view = v,
    );
    final Widget resample = LocOutlineButton(
      icon: Icons.refresh_rounded,
      label: 'Re-sample',
      semanticLabel: 'Measure every distance again with new random draws',
      onPressed: c.resample,
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          toggle,
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Expanded(child: resample),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: _LessonButton(c, compact: true)),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const LocSectionLabel(
          'Method: signal strength, or fine timing measurement (FTM) of the '
          'round trip',
        ),
        const SizedBox(height: AppSpacing.xxs),
        toggle,
        const SizedBox(height: AppSpacing.xs),
        resample,
        const SizedBox(height: AppSpacing.xxs),
        const LocNote(
          'Drag the device on the floor. Each AP\'s circle is the distance '
          'the method estimated; the position is the point that best fits '
          'all the circles. Re-sample draws new measurement errors.',
        ),
      ],
    );
  }
}

// ── Readouts ────────────────────────────────────────────────────────────────

class _ReadoutsCard extends StatelessWidget {
  const _ReadoutsCard(this.c);

  final LocationController c;

  @override
  Widget build(BuildContext context) {
    final List<LocMethod> methods = c.view.methods;
    final List<LocApReading> drawn = c.run.drawn;
    return LocCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LocSectionLabel('Distance to each AP: estimate (error)'),
          const SizedBox(height: AppSpacing.xxs),
          for (int i = 0; i < drawn.length; i++)
            LocRow(
              label:
                  'AP ${i + 1}, true ${fmtM(drawn[i].trueDistanceM, UnitSystemScope.systemOf(context))}'
                  '${c.isBlocked(i) && methods.contains(LocMethod.ftm) ? ', blocked' : ''}',
              value: <String>[
                for (final LocMethod m in methods)
                  '${methods.length > 1 ? (m == LocMethod.signal ? 'Signal ' : 'Timing ') : ''}'
                      '${fmtM(drawn[i].distanceFor(m), UnitSystemScope.systemOf(context))} '
                      '(${fmtSignedM(drawn[i].errorFor(m), UnitSystemScope.systemOf(context))})',
              ].join('\n'),
            ),
          const SizedBox(height: AppSpacing.xxs),
          for (final LocMethod m in methods) ...<Widget>[
            LocRow(
              label: '${locMethodShort(m)}: position error',
              value: c.run.result(m).positionErrorM == null
                  ? 'no fix'
                  : fmtM(
                      c.run.result(m).positionErrorM!,
                      UnitSystemScope.systemOf(context),
                    ),
              emphasize: true,
            ),
            LocRow(
              label: '${locMethodShort(m)}: spread radius, $kLocTrials repeats',
              value: fmtM(
                c.run.result(m).spreadRadiusM,
                UnitSystemScope.systemOf(context),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxs),
          const LocNote(
            'Error is estimate minus truth: plus reads long. The spread '
            'radius is the root mean square distance of 50 repeated '
            'estimates from their average.',
          ),
        ],
      ),
    );
  }
}

// ── Signal strength ─────────────────────────────────────────────────────────

class _SignalCard extends StatelessWidget {
  const _SignalCard(this.c, {this.compact = false});

  final LocationController c;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final LocSettings s = c.settings;
    final Widget n = LocSlider(
      label: compact ? 'Path-loss exponent n' : 'Path-loss exponent (n)',
      valueText: s.exponent.toStringAsFixed(1),
      value: s.exponent,
      min: kLocMinExponent,
      max: kLocMaxExponent,
      divisions: 20,
      onChanged: (double v) => c.exponent = v,
      semanticValue: (double v) => 'n ${v.toStringAsFixed(1)}',
    );
    final Widget sigma = LocSlider(
      label: 'Shadowing sigma (illustrative)',
      valueText: '${s.sigmaDb.toStringAsFixed(1)} dB',
      value: s.sigmaDb,
      min: 0,
      max: kLocMaxSigmaDb,
      divisions: (kLocMaxSigmaDb * 2).round(),
      onChanged: (double v) => c.sigmaDb = v,
      semanticValue: (double v) => '${v.toStringAsFixed(1)} dB',
    );
    final Widget factor = LocRow(
      label: compact
          ? 'Distance factor, 10^(sigma / 10n)'
          : 'One-sigma distance factor, 10^(sigma / 10n)',
      value: 'x${c.errorFactor.toStringAsFixed(3)}',
      emphasize: true,
    );
    if (compact) {
      return LocCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const LocSectionLabel('Signal strength'),
            Row(
              children: <Widget>[
                Expanded(child: n),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: sigma),
              ],
            ),
            factor,
          ],
        ),
      );
    }
    return LocCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LocSectionLabel('Signal strength'),
          const SizedBox(height: AppSpacing.xxs),
          n,
          sigma,
          const LocNote(
            'Shadowing is the few dB that walls, furniture and people add or '
            'take away at one spot. The device cannot know it, so it reads '
            'straight into the distance.',
          ),
          const SizedBox(height: AppSpacing.xs),
          factor,
          const SizedBox(height: AppSpacing.xs),
          _WorkedExample(c),
          LocRow(
            label: 'Each AP radiates (illustrative)',
            value: '${kLocApPowerDbm.toStringAsFixed(0)} dBm on 5 GHz',
          ),
        ],
      ),
    );
  }
}

class _WorkedExample extends StatelessWidget {
  const _WorkedExample(this.c);

  final LocationController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final LocSettings s = c.settings;
    final UnitSystem u = UnitSystemScope.systemOf(context);
    final String ten = LengthFormat(u).dist(locWorkedDistanceM(u), decimals: 0);
    final (double lo, double hi) = locOneSigmaRange(
      locWorkedDistanceM(u),
      s.sigmaDb,
      s.exponent,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LocSectionLabel('Worked example: a device $ten away'),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          '10^(${s.sigmaDb.toStringAsFixed(1)} / (10 x '
          '${s.exponent.toStringAsFixed(1)})) = '
          'x${c.errorFactor.toStringAsFixed(3)}',
          style: mono.inlineCode.copyWith(color: colors.textPrimary),
        ),
        LocRow(label: 'One sigma short: $ten / factor', value: fmtM(lo, u)),
        LocRow(label: 'One sigma long: $ten x factor', value: fmtM(hi, u)),
        LocNote(
          'The same dB error costs more ${u.isMetric ? 'meters' : 'feet'} '
          'the farther away the AP is: '
          'the error is a factor, not a fixed distance.',
        ),
      ],
    );
  }
}

// ── Timing ──────────────────────────────────────────────────────────────────

class _TimingCard extends StatelessWidget {
  const _TimingCard(this.c, {this.compact = false});

  final LocationController c;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final LocSettings s = c.settings;
    final AppColorScheme colors = context.colors;
    final Widget error = LocSlider(
      label: compact
          ? 'Error (vendor-documented ${locVendorRange(c.units)})'
          : 'Timing error, one standard deviation (vendor-documented '
                '${locVendorRange(c.units)})',
      valueText: fmtM(s.ftmErrorM, UnitSystemScope.systemOf(context)),
      value: s.ftmErrorM,
      min: kLocMinFtmErrorM,
      max: kLocMaxFtmErrorM,
      divisions: ((kLocMaxFtmErrorM - kLocMinFtmErrorM) * 10).round(),
      onChanged: (double v) => c.ftmErrorM = v,
      semanticValue: (double v) => fmtM(v, c.units),
    );
    final Widget bias = LocSlider(
      label: compact
          ? 'Blocked extra (illustrative)'
          : 'Blocked-path extra distance (illustrative)',
      valueText: fmtM(s.blockedBiasM, UnitSystemScope.systemOf(context)),
      value: s.blockedBiasM,
      min: 0,
      max: kLocMaxBlockedBiasM,
      divisions: (kLocMaxBlockedBiasM * 2).round(),
      onChanged: (double v) => c.blockedBiasM = v,
      semanticValue: (double v) => fmtM(v, c.units),
    );
    final Widget chips = Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xxs,
      children: <Widget>[
        for (int i = 0; i < c.apCount; i++)
          FilterChip(
            label: Text('AP ${i + 1}'),
            tooltip: c.isBlocked(i)
                ? 'Clear AP ${i + 1}\'s direct path'
                : 'Block AP ${i + 1}\'s direct path',
            selected: c.isBlocked(i),
            onSelected: (_) => c.toggleBlocked(i),
            selectedColor: colors.primary.withValues(alpha: 0.2),
            checkmarkColor: colors.textAccent,
            side: BorderSide(color: colors.borderStrong),
          ),
      ],
    );
    final TextStyle? chipsLabel = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: colors.textSecondary);
    if (compact) {
      final Widget compactChips = Wrap(
        spacing: AppSpacing.xxs,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          for (int i = 0; i < c.apCount; i++)
            Semantics(
              label: 'AP ${i + 1} direct path blocked',
              child: FilterChip(
                label: Text('${i + 1}'),
                tooltip: c.isBlocked(i)
                    ? 'Clear AP ${i + 1}\'s direct path'
                    : 'Block AP ${i + 1}\'s direct path',
                selected: c.isBlocked(i),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => c.toggleBlocked(i),
                selectedColor: colors.primary.withValues(alpha: 0.2),
                side: BorderSide(
                  color: c.isBlocked(i) ? colors.primary : colors.borderStrong,
                ),
              ),
            ),
        ],
      );
      return LocCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const LocSectionLabel('Fine timing measurement (FTM)'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: error),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: bias),
              ],
            ),
            Row(
              children: <Widget>[
                Text('Blocked AP', style: chipsLabel),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: compactChips),
              ],
            ),
          ],
        ),
      );
    }
    return LocCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LocSectionLabel('Round-trip timing (FTM, from 802.11mc)'),
          const SizedBox(height: AppSpacing.xxs),
          error,
          LocNote(
            'The ${locVendorRange(c.units)} figure comes from a vendor '
            'developer document, not a measurement here.',
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('Direct path blocked', style: chipsLabel),
          const SizedBox(height: AppSpacing.xxs),
          chips,
          bias,
          const LocNote(
            'With the direct path blocked, the first signal to arrive is a '
            'reflection. It travelled farther, so that AP\'s distance reads '
            'long and its circle is drawn dashed.',
          ),
          const SizedBox(height: AppSpacing.xs),
          _LightSpeed(c),
        ],
      ),
    );
  }
}

class _LightSpeed extends StatelessWidget {
  const _LightSpeed(this.c);

  final LocationController c;

  @override
  Widget build(BuildContext context) {
    final double d0 = c.run.drawn.first.trueDistanceM;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LocSectionLabel(
          'Why timing gives ${c.units.isMetric ? 'meters' : 'feet'}',
        ),
        LocRow(
          label: 'Light travels, per nanosecond',
          value: c.units.isMetric
              ? '${(kLocMetersPerNs * 100).toStringAsFixed(0)} cm'
              : LengthFormat(c.units).small(kLocMetersPerNs, decimals: 1),
        ),
        LocRow(
          label: '1 ns of round-trip time (RTT) is',
          value:
              '${c.units.isMetric ? '${(locDistanceFromRoundTripNs(1) * 100).toStringAsFixed(0)} cm' : LengthFormat(c.units).small(locDistanceFromRoundTripNs(1), decimals: 1)} '
              'of distance',
        ),
        LocRow(
          label:
              'RTT to AP 1 now (${fmtM(d0, UnitSystemScope.systemOf(context))})',
          value: '${locRoundTripNs(d0).toStringAsFixed(1)} ns',
        ),
        const LocNote(
          'Distance = speed of light x RTT / 2: the frame goes out and the '
          'reply comes back.',
        ),
      ],
    );
  }
}

// ── Lesson ──────────────────────────────────────────────────────────────────

class _LessonCard extends StatelessWidget {
  const _LessonCard(this.c);

  final LocationController c;

  @override
  Widget build(BuildContext context) {
    return LocCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LocSectionLabel('Predict, then reveal'),
          const SizedBox(height: AppSpacing.xxs),
          const LocNote(
            'Your phone sees an AP at -70 dBm. How far away is it?',
          ),
          const SizedBox(height: AppSpacing.xs),
          _LessonButton(c),
        ],
      ),
    );
  }
}

class _LessonButton extends StatelessWidget {
  const _LessonButton(this.c, {this.compact = false});

  final LocationController c;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final String label = switch (c.lesson) {
      LocLessonStep.off => compact ? 'Ask: -70 dBm' : 'Ask: -70 dBm, how far?',
      LocLessonStep.predict => compact ? 'Reveal' : 'Reveal the answer',
      LocLessonStep.revealed => compact ? 'End question' : 'End the question',
    };
    return LocFilledButton(
      icon: c.lesson == LocLessonStep.revealed
          ? Icons.check_rounded
          : Icons.visibility_outlined,
      label: label,
      onPressed: c.nextReveal,
    );
  }
}

// ── Floor ───────────────────────────────────────────────────────────────────

class _FloorCard extends StatelessWidget {
  const _FloorCard(this.c);

  final LocationController c;

  @override
  Widget build(BuildContext context) {
    final LocPoint d = c.device;
    return LocCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LocSectionLabel('The floor'),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'APs',
            semanticLabel: 'Number of APs',
            field: AppSelect<int>(
              value: c.apCount,
              semanticLabel: 'Number of APs',
              items: <AppSelectItem<int>>[
                for (int n = kLocMinAps; n <= kLocMaxAps; n++) (n, '$n APs'),
              ],
              onChanged: (int n) => c.apCount = n,
            ),
          ),
          LocSlider(
            label: 'Device position, across',
            valueText: fmtM(d.x, c.units),
            // 0.5 m steps, or whole feet.
            value: LengthFormat(c.units).distValue(d.x),
            min: 0,
            max: c.units.isMetric
                ? kLocFloorWidthM
                : LengthUnits.metresToFeet(kLocFloorWidthM).floorToDouble(),
            divisions: c.units.isMetric
                ? (kLocFloorWidthM * 2).round()
                : LengthUnits.metresToFeet(kLocFloorWidthM).floor(),
            onChanged: (double v) =>
                c.device = (x: LengthFormat(c.units).distToMetres(v), y: d.y),
            semanticValue: (double v) => fmtM(v, c.units),
          ),
          LocSlider(
            label: 'Device position, down',
            valueText: fmtM(d.y, c.units),
            // 0.5 m steps, or whole feet.
            value: LengthFormat(c.units).distValue(d.y),
            min: 0,
            max: c.units.isMetric
                ? kLocFloorDepthM
                : LengthUnits.metresToFeet(kLocFloorDepthM).floorToDouble(),
            divisions: c.units.isMetric
                ? (kLocFloorDepthM * 2).round()
                : LengthUnits.metresToFeet(kLocFloorDepthM).floor(),
            onChanged: (double v) =>
                c.device = (x: d.x, y: LengthFormat(c.units).distToMetres(v)),
            semanticValue: (double v) => fmtM(v, c.units),
          ),
          LocRow(
            label: 'Floor',
            value:
                '${LengthFormat(c.units).dist(kLocFloorWidthM, decimals: 0)} x '
                '${LengthFormat(c.units).dist(kLocFloorDepthM, decimals: 0)}',
          ),
        ],
      ),
    );
  }
}
