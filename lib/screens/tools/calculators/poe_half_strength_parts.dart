// Shared small widgets for the Wi-Fi Classroom tool "PoE: Why the New AP
// Runs at Half Strength": card, section label, note row, a label/value row
// and a mono figure row. Used by the stage, the readouts and the controls,
// so none imports another.
//
// THEME: context.colors only. No status hues: a reduced AP is described in
// words, not painted red (GL-003 §8.13 rule 6). ASCII copy, no em dashes
// (GL-004).

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import 'calc_parts.dart';

typedef PhCard = CalcCard;

typedef PhSectionLabel = CalcSectionLabel;

typedef PhNote = CalcNote;

/// A label over its answer, the answer in the body style. Merged into one
/// semantics node so a screen reader reads "label: answer".
class PhFact extends StatelessWidget {
  const PhFact({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              label,
              style: text.labelMedium?.copyWith(color: colors.textSecondary),
            ),
            Text(
              value,
              style: text.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// A mono figure beside its label: "Guesses tried  12".
class PhFigure extends StatelessWidget {
  const PhFigure({super.key, required this.label, required this.value});
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
        Flexible(
          flex: 2,
          child: Text(
            value,
            style: mono.outputMedium.copyWith(color: colors.textAccent),
          ),
        ),
      ],
    );
  }
}
