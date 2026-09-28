// Wpa2PasswordStage: the picture half of the Wi-Fi Classroom tool "Why a
// Long Wi-Fi Password Matters More on WPA2" (wpa2-password).
//
// The drawing (WpStagePainter), its caption and legend, and, in presenter
// mode, the readouts and the prediction beside it. It takes the controller
// and knows nothing about the controls, so a screen can place it above the
// controls (phone), beside them (desktop) or full screen (presenter).
//
// Wpa2PasswordReadouts: the number of possible passwords (plain arithmetic)
// and four facts about the chosen security: where each guess is checked,
// what sets the pace, whether the AP sees the guessing, and what happens to
// recorded traffic if the password is learned later. NO TIMES (brief
// section 5, anti-pattern 2).
//
// Wpa2PasswordPredict: the Wi-Fi Alliance's own example (5,000 possible
// passwords), with the answer hidden until Reveal (or P in presenter mode).
//
// THEME: context.colors only. ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'wpa2_password_controller.dart';
import 'wpa2_password_painter.dart';
import 'wpa2_password_parts.dart';

/// The whole drawing in words, for a screen reader.
String wpStageSemantics(WpConfig c, int guesses, int apFailed) {
  final String where = switch (c.security) {
    WpSecurity.wpa2 =>
      "A phone associates with your AP. The attacker's computer holds a "
          'recording of one association and checks guesses against it on '
          'its own, limited only by that computer.',
    WpSecurity.wpa3 =>
      "A phone associates with your AP using SAE. A recording lets the "
          "attacker's computer check no guess, so each guess goes to the AP "
          'as one live exchange.',
    WpSecurity.transition =>
      'A WPA3 phone and an older WPA2-only laptop share one network and one '
          "password. The attacker's computer holds a recording of the "
          "laptop's WPA2 association and checks guesses against it on its "
          'own, limited only by that computer.',
  };
  return '$where Guesses tried: $guesses. Failed attempts the AP logged: '
      '$apFailed.';
}

class Wpa2PasswordStage extends StatelessWidget {
  const Wpa2PasswordStage({
    super.key,
    required this.controller,
    required this.stageHeight,
  });

  final Wpa2PasswordController controller;

  /// Height of the drawing itself. Ignored in presenter mode, where the
  /// drawing fills the stage.
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
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final bool presenter = PresenterMode.isActive(context);
    final WpConfig c = controller.config;

    final Widget drawing = Semantics(
      label: wpStageSemantics(
        c,
        controller.guesses,
        controller.apFailedAttempts,
      ),
      liveRegion: presenter,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: ColoredBox(
          color: colors.surface2,
          child: CustomPaint(
            size: Size.infinite,
            painter: WpStagePainter(
              security: c.security,
              guesses: controller.guesses,
              apFailed: controller.apFailedAttempts,
              phase: controller.phase,
              scale: scale,
              palette: WpPalette(
                ink: colors.textPrimary,
                muted: colors.textSecondary,
                faint: colors.textTertiary,
                accent: colors.textAccent,
                box: colors.surface2,
                boxBorder: colors.borderStrong,
                fontFamily: text.bodySmall?.fontFamily,
              ),
            ),
          ),
        ),
      ),
    );

    final Widget card = WpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '${c.security.label}. The highlighted path shows where each '
            'password guess is checked.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (presenter)
            Expanded(child: drawing)
          else
            SizedBox(height: stageHeight, child: drawing),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Solid line: over the air. Dashed line: a recording. Highlighted '
            'line with the moving dot: where a guess is checked. The pace on '
            'screen is slowed for the eye; it is not a speed.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
    if (!presenter) return card;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double side = (box.maxWidth * 0.42).clamp(320.0, 520.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: card),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: side,
              // Shrinks as one piece rather than clip in a short window.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: side,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Wpa2PasswordReadouts(
                        controller: controller,
                        compact: true,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wpa2PasswordPredict(controller: controller),
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
}

// ── Readouts ─────────────────────────────────────────────────────────────

class Wpa2PasswordReadouts extends StatelessWidget {
  const Wpa2PasswordReadouts({
    super.key,
    required this.controller,
    this.compact = false,
  });

  final Wpa2PasswordController controller;

  /// The presenter-stage form: no footnotes.
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
    final WpConfig c = controller.config;
    final BigInt n = c.possiblePasswords;
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);

    return WpCard(
      child: Semantics(
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            WpSectionLabel(
              'A password of ${c.length} characters, ${c.charset.phrase}',
            ),
            const SizedBox(height: AppSpacing.xxs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                WpFormat.count(n),
                style: scale
                    .headlineStyle(mono.outputLarge)
                    .copyWith(color: colors.textPrimary),
              ),
            ),
            Text(
              'possible passwords (${c.charset.size} to the power '
              '${c.length}, a ${WpFormat.digits(n)}-digit number). Each extra '
              'character multiplies this by ${c.perExtraCharacter}.',
              style: small(),
            ),
            WpFact(
              label: 'Where each guess is checked',
              value: c.guessPlace.label,
            ),
            if (!compact)
              WpFact(label: 'What sets the pace', value: c.paceLabel),
            WpFact(
              label: 'Does the AP see the guessing?',
              value: c.apSeesGuesses
                  ? 'Yes: every wrong guess is a failed authentication it '
                        'can notice and limit'
                  : 'No: nothing reaches the AP',
            ),
            if (!compact)
              WpFact(
                label: 'Recorded traffic, if the password is learned later',
                value: c.recordedTraffic,
              ),
            const SizedBox(height: AppSpacing.xs),
            Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  WpFigure(
                    label: 'Guesses tried',
                    value: WpFormat.integer(controller.guesses),
                  ),
                  WpFigure(
                    label: 'Failed attempts the AP logged',
                    value: WpFormat.integer(controller.apFailedAttempts),
                  ),
                ],
              ),
            ),
            if (!compact) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              const WpNote(
                Icons.info_outline,
                'The count assumes the password was picked at random from '
                'these characters. A word, a name or a pattern is on every '
                'guess list and falls long before the count runs out.',
              ),
              const SizedBox(height: AppSpacing.xxs),
              const WpNote(
                Icons.timer_off_outlined,
                'No time to crack is shown: it depends entirely on the '
                "attacker's hardware.",
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Predict, then reveal ─────────────────────────────────────────────────

class Wpa2PasswordPredict extends StatelessWidget {
  const Wpa2PasswordPredict({super.key, required this.controller});
  final Wpa2PasswordController controller;

  static const String question =
      'Your password is one of 5,000, picked at random, and the attacker has '
      'the list. How much of the list can they try on WPA2, and on WPA3?';

  static final String answerWpa2 =
      'WPA2: all ${WpFormat.integer(WpWfaExample.passwords)}. With one '
      'recorded association they test every password on their own computer '
      'and find it for certain. Your AP never sees a guess.';

  static final String answerWpa3 =
      'WPA3: one per live exchange with your AP. After '
      '${WpFormat.integer(WpWfaExample.halfwayAttempts)} tries the chance is '
      '${WpFormat.chance(wpChanceFound(WpWfaExample.halfwayAttempts, BigInt.from(WpWfaExample.passwords)))}, '
      'and ${WpFormat.integer(WpWfaExample.halfwayAttempts)} failed '
      'authentications is the kind of pattern the Wi-Fi Alliance says an AP '
      'should detect and limit long before the chance gets that high.';

  static const String credit =
      'The Wi-Fi Alliance\'s own example (WPA3 Security Considerations, '
      '2019).';

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

    return WpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const WpSectionLabel('Predict, then reveal'),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(answerWpa2, style: body()),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(answerWpa3, style: body()),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              credit,
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}
