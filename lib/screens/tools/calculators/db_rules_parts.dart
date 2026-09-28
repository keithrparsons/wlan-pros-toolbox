// Shared small widgets for the Wi-Fi Classroom tool Decibels in Your Head,
// the Rules of 3 and 10 (db-rules): card, section label, readout row, and
// the predict-then-reveal card. Used by the stage and the controls, so
// neither imports the other.
//
// COLOR: context.colors only. ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'db_rules_controller.dart';

class DrCard extends StatelessWidget {
  const DrCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }
}

class DrSectionLabel extends StatelessWidget {
  const DrSectionLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Semantics(
      header: true,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.textSecondary,
          letterSpacing: 0.4,
          fontWeight: colors.isLight ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}

/// A label and a mono value on one line, wrapping to two when narrow.
class DrReadout extends StatelessWidget {
  const DrReadout(this.label, this.value, {super.key, this.headline = false});
  final String label;
  final String value;

  /// The one number the lesson is about: larger, and the accent ink.
  final bool headline;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: AppSpacing.xs,
        children: <Widget>[
          Text(
            label,
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          Text(
            value,
            style: (headline ? mono.outputMedium : mono.inlineCode).copyWith(
              color: headline ? colors.textAccent : colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Predict, then reveal: "Is -67 dBm a little or a lot stronger than -70?"
class DbRulesPredict extends StatelessWidget {
  const DbRulesPredict({super.key, required this.controller});
  final DbRulesController controller;

  static const String question =
      'Is -67 dBm a little or a lot stronger than -70 dBm?';

  static const String answer =
      'A lot: about twice the power. -67 dBm is 3 dB above -70 dBm, and '
      '+3 dB is 1.995 times the milliwatts, so about double: 199.5 '
      'picowatts against 100.';

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
    final bool presenter = PresenterMode.isActive(context);
    final bool open = controller.revealed;
    TextStyle body() => text.bodyMedium!.copyWith(color: colors.textPrimary);

    return DrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const DrSectionLabel('Predict, then reveal'),
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
            Semantics(liveRegion: true, child: Text(answer, style: body())),
            if (!presenter) ...<Widget>[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'On the dB ruler the step looks small. On the linear bar it '
                'is the difference between 10% and 20% of the length.',
                style: body(),
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: controller.dbm == DbRules.predictDbm
                    ? null
                    : controller.showPrediction,
                icon: const Icon(Icons.compare_arrows),
                label: Text(
                  'Show -67 dBm against -70 dBm${presenter ? ' (Space)' : ''}',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
