// Readouts and the predict-then-reveal card for the Wi-Fi Classroom Body Loss
// tool.
//
// BodyLossReadouts: received level and MCS, the loss from the holder, the
// loss from the crowd, and the difference between the empty and the occupied
// building (spec 34). `compact` is the presenter-stage form: the numbers and
// one line each, no footnotes.
//
// BodyLossPredict: "You surveyed the auditorium empty on Saturday. What
// happens Monday at 9 a.m.?" (spec 34), with the answer hidden until Reveal
// (or P in presenter mode).
//
// Both take the controller and know nothing about the stage or the controls.
// No status hues: a level or an MCS is a description, not a verdict
// (GL-003 §8.13 rule 6). ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'body_loss_controller.dart';
import 'body_loss_parts.dart';

/// One sentence on the holder's loss.
String blHolderSentence(BlConfig c) {
  final String off = BlFormat.deg(c.offAxisDeg);
  if (c.holderShare <= 0.001) {
    return 'The holder faces $off away from the AP, so the body is not on '
        'the line: no holder loss.';
  }
  if (c.holderShare >= 0.999) {
    return 'The holder\'s back is to the AP, so the whole body sits on the '
        'line: the full ${BlFormat.db(c.fullHolderLossAt(c.band))} at '
        '${c.band.label}.';
  }
  return 'The holder faces $off away from the AP, so the body is partly on '
      'the line: ${(c.holderShare * 100).round()}% of the '
      '${BlFormat.db(c.fullHolderLossAt(c.band))} full value.';
}

/// One sentence on the crowd's loss.
String blCrowdSentence(BlConfig c) {
  if (!c.occupied) {
    return 'The building is empty, so the crowd costs nothing. Filled, '
        '${BlFormat.people(c.crossingCount)} would stand on the line.';
  }
  if (c.crowdSize == 0) return 'No one else is in the room.';
  if (c.crossingCount == 0) {
    return 'Nobody stands on the line to the AP, so the crowd costs nothing '
        'here. Drag a person onto the line.';
  }
  return '${BlFormat.people(c.crossingCount)} on the line x '
      '${BlFormat.db(c.perPersonAtBandDb)} each at ${c.band.label} = '
      '${BlFormat.db(c.crowdLossDb)}.';
}

class BodyLossReadouts extends StatelessWidget {
  const BodyLossReadouts({
    super.key,
    required this.controller,
    this.compact = false,
  });

  final BodyLossController controller;

  /// The presenter-stage form: numbers and one line each.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final BlConfig c = controller.config;
    TextStyle body() => text.bodyMedium!.copyWith(color: colors.textPrimary);
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);

    return BlCard(
      child: Semantics(
        container: true,
        liveRegion: compact,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BlSectionLabel(
              'Device ${BlFormat.dist(c.distanceM)} from the AP, '
              '${c.occupied ? 'occupied' : 'empty'}',
            ),
            const SizedBox(height: AppSpacing.xxs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      BlFormat.dbm(c.receivedDbm),
                      style: scale
                          .headlineStyle(mono.outputLarge)
                          .copyWith(color: colors.textPrimary),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  c.mcs == null ? 'Below MCS 0' : 'MCS ${c.mcs}',
                  style: mono.outputMedium.copyWith(color: colors.textAccent),
                ),
              ],
            ),
            Text(
              compact
                  ? 'Received level and MCS'
                  : 'Received level, and the MCS (modulation and coding '
                        'scheme, the data-rate step) it supports at 20 MHz',
              style: small(),
            ),
            const SizedBox(height: AppSpacing.xs),
            _Figure(
              label: 'Loss from the holder',
              value: BlFormat.db(c.holderLossAppliedDb),
            ),
            Text(
              compact
                  ? '${BlFormat.deg(c.offAxisDeg)} away from facing the AP'
                  : blHolderSentence(c),
              style: compact ? small() : body(),
            ),
            const SizedBox(height: AppSpacing.xs),
            _Figure(
              label: 'Loss from the crowd',
              value: BlFormat.db(c.crowdLossDb),
            ),
            Text(
              compact
                  ? (c.occupied
                        ? '${BlFormat.people(c.crossingCount)} on the line'
                        : 'Empty building')
                  : blCrowdSentence(c),
              style: compact ? small() : body(),
            ),
            const SizedBox(height: AppSpacing.xs),
            _Figure(
              label: 'Empty vs occupied',
              value: BlFormat.db(c.emptyVsOccupiedDb),
            ),
            Text(
              'Empty ${BlFormat.dbm(c.emptyDbm)}, ${BlFormat.mcs(c.mcsEmpty)}; '
              'occupied ${BlFormat.dbm(c.occupiedDbm)}, '
              '${BlFormat.mcs(c.mcsOccupied)}',
              style: compact ? small() : body(),
            ),
            if (!compact) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              BlSectionLabel(BlLabels.bandTrend),
              const SizedBox(height: AppSpacing.xxs),
              for (final WifiBand b in WifiBand.values)
                Text(
                  '${b.label}: ${BlFormat.db(c.fullHolderLossAt(b))} with the '
                  'back to the AP (x${BlFormat.n(c.multiplierFor(b), 2)})',
                  style: mono.inlineCode.copyWith(
                    color: b == c.band
                        ? colors.textPrimary
                        : colors.textSecondary,
                    fontWeight: b == c.band ? FontWeight.w700 : null,
                  ),
                ),
              const SizedBox(height: AppSpacing.xs),
              const BlNote(
                Icons.info_outline,
                'Every body loss here is an illustrative setting, not a '
                'measurement. No measured body-loss figure stands behind '
                'these defaults: set them to match what you measure.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Flexible(
          child: Text(
            '$label  ',
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
        ),
        Text(
          value,
          style: mono.outputMedium.copyWith(color: colors.textAccent),
        ),
      ],
    );
  }
}

// ── Predict, then reveal ──────────────────────────────────────────────────

/// The answer, from the scene as it stands.
String blPredictAnswer(BlConfig c) {
  if (c.crowdSize == 0 || c.crossingCount == 0) {
    return 'Here, nothing changes: nobody stands on the line between this '
        'device and the AP. Add people or drag one onto the line, and ask '
        'again.';
  }
  return 'The level drops ${BlFormat.db(c.emptyVsOccupiedDb)}: from '
      '${BlFormat.dbm(c.emptyDbm)} (${BlFormat.mcs(c.mcsEmpty)}) in the empty '
      'room to ${BlFormat.dbm(c.occupiedDbm)} '
      '(${BlFormat.mcs(c.mcsOccupied)}) with people in their seats. '
      '${BlFormat.people(c.crossingCount)} now stand on the line to the AP, '
      'each costing ${BlFormat.db(c.perPersonAtBandDb)} here (illustrative).';
}

class BodyLossPredict extends StatelessWidget {
  const BodyLossPredict({super.key, required this.controller});
  final BodyLossController controller;

  static const String question =
      'You surveyed the auditorium empty on Saturday. What happens Monday at '
      '9 a.m.?';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final BlConfig c = controller.config;
    final bool presenter = PresenterMode.isActive(context);
    final bool open = controller.revealed;
    TextStyle body() => text.bodyMedium!.copyWith(color: colors.textPrimary);

    return BlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const BlSectionLabel('Predict, then reveal'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            question,
            style: text.titleMedium?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: controller.toggleReveal,
              icon: Icon(open ? Icons.visibility_off : Icons.visibility),
              label: Text(
                '${open ? 'Hide the answer' : 'Reveal the answer'}'
                '${presenter ? ' (P)' : ''}',
              ),
            ),
          ),
          if (open) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Semantics(
              liveRegion: true,
              child: Text(blPredictAnswer(c), style: body()),
            ),
            if (!presenter) ...<Widget>[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Every person between the device and the AP is mostly water. '
                'A survey of the empty building reads better than the '
                'building in use, so leave margin for the crowd.',
                style: body(),
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: controller.toggleOccupied,
                icon: Icon(
                  c.occupied
                      ? Icons.person_off_outlined
                      : Icons.groups_outlined,
                ),
                label: Text(
                  c.occupied ? 'Show Saturday, empty' : 'Show Monday, occupied',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
