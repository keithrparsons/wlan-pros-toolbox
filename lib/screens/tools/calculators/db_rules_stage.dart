// DbRulesStage: the picture half of the Wi-Fi Classroom tool Decibels in
// Your Head, the Rules of 3 and 10 (db-rules).
//
// The linear milliwatt bar over the dB ruler (DbRulesPainter), a legend, the
// readouts (signal, reference, difference as a ratio, the rules path beside
// the exact ratio) and the predict-then-reveal card. It takes a
// DbRulesController and knows nothing about the controls.
//
// PRESENTER: the picture fills the stage's height; the readouts and the
// prediction stand beside it. Strokes, markers and painted labels follow
// PresenterMode.scaleOf.
//
// THEME: context.colors only. ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'db_rules_controller.dart';
import 'db_rules_painter.dart';
import 'db_rules_parts.dart';

/// Words for the stage's screen-reader summary.
String dbRulesStageSemantics(DbRulesController k) =>
    'Linear power bar and dB ruler. Signal ${DbFormat.dbm(k.dbm)}, '
    '${(DbRules.barShare(k.dbm) * 100).toStringAsFixed(1)} percent of the bar. '
    'Reference ${DbFormat.dbm(DbRules.referenceDbm)}, 10 percent of the bar. '
    'Difference ${DbFormat.dbDiff(k.diffDb)}, '
    '${DbRules.powerWords(k.diffDb)}.';

class DbRulesStage extends StatelessWidget {
  const DbRulesStage({
    super.key,
    required this.controller,
    required this.stageHeight,
  });

  final DbRulesController controller;

  /// Height of the picture. Ignored in presenter mode, where it fills.
  final double stageHeight;

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
    final PresenterScale s = PresenterMode.scaleOf(context);
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);

    final Widget picture = Semantics(
      label: dbRulesStageSemantics(controller),
      excludeSemantics: true,
      child: CustomPaint(
        size: Size.infinite,
        painter: DbRulesPainter(
          dbm: controller.dbm,
          ink: colors.textPrimary,
          neutral: colors.textTertiary,
          secondary: colors.textSecondary,
          accent: colors.primary,
          track: colors.disabledFill,
          surface: colors.surface1,
          stroke: s.stroke,
          marker: s.marker,
          fontScale: s.text,
          labelStyle: text.bodySmall ?? const TextStyle(),
        ),
      ),
    );

    final Widget card = DrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Top: power on a linear scale, milliwatts, full length at -60 '
            'dBm. Bottom: the same levels in dBm (decibels relative to one '
            'milliwatt), the scale the slider uses. A line joins each whole '
            'dB on the ruler to its power on the bar.',
            style: small(),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (presenter)
            Expanded(child: picture)
          else
            SizedBox(height: stageHeight, child: picture),
          const SizedBox(height: AppSpacing.xs),
          _legend(context),
        ],
      ),
    );

    final Widget readouts = DrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: _readouts(context),
      ),
    );

    if (!presenter) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          card,
          const SizedBox(height: AppSpacing.sm),
          readouts,
          const SizedBox(height: AppSpacing.sm),
          DbRulesPredict(controller: controller),
        ],
      );
    }

    // Presenter: the picture takes the full stage width (the linear bar is
    // the lesson, so it gets the room); the readouts and the prediction sit
    // side by side under it and shrink as one piece rather than clip.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: card),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: box.maxHeight * 0.46),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: box.maxWidth,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: readouts),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: DbRulesPredict(controller: controller)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _readouts(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final DbRulesController k = controller;
    return <Widget>[
      const DrSectionLabel('What the step is worth'),
      const SizedBox(height: AppSpacing.xxs),
      DrReadout('Signal ${DbFormat.dbm(k.dbm)}', DbFormat.pw(k.pw)),
      DrReadout(
        'Reference ${DbFormat.dbm(DbRules.referenceDbm)}',
        DbFormat.pw(k.referencePw),
      ),
      const SizedBox(height: AppSpacing.xxs),
      DrReadout(
        'Difference ${DbFormat.dbDiff(k.diffDb)}',
        DbRules.powerWords(k.diffDb),
        headline: true,
      ),
      const SizedBox(height: AppSpacing.xxs),
      DrReadout('Rules of 3 and 10', k.pathWords),
      if (k.path.steps.isNotEmpty) DrReadout('Exact', DbFormat.ratio(k.ratio)),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        'pW is picowatts, trillionths of a watt: 100 pW is 0.0000001 mW.',
        style: text.bodySmall?.copyWith(color: colors.textTertiary),
      ),
    ];
  }

  Widget _legend(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle? t = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colors.textSecondary);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      children: <Widget>[
        Text('Thick line with a dot: the signal', style: t),
        Text('Dashed line: the -70 dBm reference, 10% of the bar', style: t),
        Text('Thin lines: every remaining whole dB', style: t),
      ],
    );
  }
}
