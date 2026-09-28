// Controls and explainer for the Wi-Fi Classroom tool Decibels in Your Head,
// the Rules of 3 and 10 (db-rules).
//
// DbRulesControls: the one dB slider (the signal level, -80 to -60 dBm, in
// whole dB), step buttons for the two rules (3 dB and 10 dB either way), and
// Reset. DbRulesExplainer: the rules, the formulas, and the two tools that do
// the conversion as calculators. Neither knows about the stage.
//
// PRESENTER: the explanatory prose drops and each label carries its key.
//
// THEME: context.colors only. ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'db_rules_controller.dart';
import 'db_rules_parts.dart';

class DbRulesControls extends StatelessWidget {
  const DbRulesControls({super.key, required this.controller});
  final DbRulesController controller;

  /// The step buttons: dB change and its label.
  static const List<(int, String)> steps = <(int, String)>[
    (-10, '-10 dB'),
    (-3, '-3 dB'),
    (3, '+3 dB'),
    (10, '+10 dB'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _children(context),
      ),
    );
  }

  List<Widget> _children(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final DbRulesController k = controller;
    final bool prose = !PresenterMode.isActive(context);
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);

    String keyFor(int db) => prose
        ? ''
        : switch (db) {
            -10 => ' (Page Down)',
            -3 => ' (Left)',
            3 => ' (Right)',
            10 => ' (Page Up)',
            _ => '',
          };

    return <Widget>[
      const DrSectionLabel('The one control'),
      const SizedBox(height: AppSpacing.xs),
      ExcludeSemantics(
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                prose ? 'Signal level' : 'Signal level (Up, Down)',
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
            Text(
              DbFormat.dbm(k.dbm),
              style: mono.inlineCode.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
      Slider(
        value: k.dbm.toDouble(),
        min: DbRules.minDbm.toDouble(),
        max: DbRules.maxDbm.toDouble(),
        divisions: DbRules.maxDbm - DbRules.minDbm,
        onChanged: k.setDbm,
        activeColor: colors.primary,
        inactiveColor: colors.disabledFill,
        label: DbFormat.dbm(k.dbm),
        semanticFormatterCallback: (double v) =>
            'Signal level ${v.round()} dBm, '
            '${DbFormat.dbDiff(v.round() - DbRules.referenceDbm)} from the '
            'reference',
      ),
      if (prose)
        Text(
          'The reference stays at ${DbFormat.dbm(DbRules.referenceDbm)}. Move '
          'the signal and watch the bar: every 3 dB up doubles it, every 10 dB '
          'up makes it ten times longer.',
          style: small(),
        ),
      const SizedBox(height: AppSpacing.sm),
      const DrSectionLabel('Step by a rule'),
      const SizedBox(height: AppSpacing.xxs),
      Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: <Widget>[
          for (final (int db, String label) in steps)
            OutlinedButton(
              onPressed:
                  (k.dbm + db) >= DbRules.minDbm &&
                      (k.dbm + db) <= DbRules.maxDbm
                  ? () => k.nudge(db)
                  : null,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, AppSpacing.minTouchTarget),
              ),
              child: Text('$label${keyFor(db)}'),
            ),
        ],
      ),
      if (prose)
        Text(
          'A step that would leave the -80 to -60 dBm range is turned off.',
          style: small(),
        ),
      SizedBox(height: prose ? AppSpacing.md : AppSpacing.sm),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: k.reset,
          icon: const Icon(Icons.restart_alt),
          label: Text(prose ? 'Reset' : 'Reset (R)'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, AppSpacing.minTouchTarget),
          ),
        ),
      ),
    ];
  }
}

// ── Explainer ─────────────────────────────────────────────────────────────

class DbRulesExplainer extends StatelessWidget {
  const DbRulesExplainer({super.key});

  static const List<String> lessons = <String>[
    '1. A decibel (dB) is a ratio. It says how many times stronger or weaker '
        'one power is than another.',
    '2. The rule of 3: +3 dB doubles the power and -3 dB halves it. The '
        'exact factor is 1.995, so say "about double".',
    '3. The rule of 10: +10 dB is exactly ten times the power and -10 dB a '
        'tenth. +20 dB is a hundred times.',
    '4. Any whole number of dB is a sum of tens and threes, so the two rules '
        'reach every step: +1 dB is +10 -3 -3 -3, ten times then halved three '
        'times, about 1.25 times.',
  ];

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    TextStyle body() => text.bodyMedium!.copyWith(color: colors.textPrimary);
    TextStyle formula() =>
        mono.inlineCode.copyWith(color: colors.textSecondary);
    return DrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const DrSectionLabel('The rules of 3 and 10'),
          const SizedBox(height: AppSpacing.xs),
          for (final String l in lessons) ...<Widget>[
            Text(l, style: body()),
            const SizedBox(height: AppSpacing.xs),
          ],
          Text('mW = 10^(dBm / 10)', style: formula()),
          Text('Power ratio = 10^(dB difference / 10)', style: formula()),
          Text('10^(3 / 10) = 1.995', style: formula()),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'For any level or difference, not just the ones on this slider, '
            'use the dBm / Watt Converter; the dB Reference lists the common '
            'ratios in a table.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          Wrap(
            spacing: AppSpacing.xs,
            children: <Widget>[
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRouter.dbmWatt),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open dBm / Watt Converter'),
              ),
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRouter.dbReference),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open dB Reference'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
