// LivePrimingCard — the post-install "finish setup" priming step.
//
// WHY THIS EXISTS (2026-06-26, Keith device round 2): iOS gives an app NO way to
// query whether a Shortcut is installed. The app only learns the companion "WLAN
// Pros Live" Shortcut exists by RECEIVING a payload, which flips the honest
// install-state flag. Right after the user adds the Shortcut, no payload has
// arrived yet, so the live tools kept showing the cold "Set up live Wi-Fi" prompt
// even though the Shortcut was just installed ("it doesn't KNOW the companion
// shortcut is there"). Two device facts make the first round-trip fail silently:
//   1. iOS cannot auto-return from an iCloud Shortcut INSTALL link, so the user
//      lands back in the app manually and needs a clear next step.
//   2. The FIRST run of a new Shortcut raises iOS's one-time permission prompt
//      ("Allow WLAN Pros Live to run?"), which eats that first invocation — no
//      payload arrives, so install-state never flips.
//
// This card is the honest priming step shown while setup has been started but no
// payload has completed the round-trip ([controller.setupInitiated] &&
// !hasEverReceived). It names the one action that finishes setup (a one-shot
// "Get reading") AND sets the expectation about the first-run permission prompt,
// so a first-fire interruption reads as "tap once more", never as a dead end.
//
// Styling mirrors [LiveSetupCard] (GL-003 App Mode): surface1 card, hairline
// border, textSecondary body, a quiet textTertiary state glyph, and a single
// lime-primary FilledButton carrying the custom [GetReadingIcon]. iOS-only — the
// snapshot platforms read natively and never prime.

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import 'get_reading_icon.dart';

/// The post-install priming step: "tap Get reading to finish; iOS asks permission
/// the first time." Shown only in the priming window (setup started, no payload
/// yet). [onGetReading] fires the one-shot prime (the x-callback form that
/// auto-returns on success and routes to the not-found recovery on x-error).
class LivePrimingCard extends StatelessWidget {
  const LivePrimingCard({
    super.key,
    required this.onGetReading,
    this.label = 'Get reading',
  }) : assert(label != '');

  /// Fires the one-shot priming read. Pass the host screen's `getReadingOnce`.
  final VoidCallback onGetReading;

  /// The action-button label. Defaults to "Get reading" (the finish-setup tap).
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Decorative state glyph — the title carries the meaning.
              Icon(
                Icons.touch_app_outlined,
                size: 22,
                color: colors.textTertiary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Almost set up',
                  style: text.titleSmall?.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // The honest first-run-permission guidance, in a liveRegion so the step
          // is announced when it replaces the cold setup prompt after install.
          Semantics(
            liveRegion: true,
            child: Text(
              'Tap Get reading to finish. The first time it runs, iOS asks to '
              'allow the "WLAN Pros Live" Shortcut to share your network '
              'details, so tap Always Allow. If that first tap gets interrupted, '
              'tap Get reading once more.',
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            button: true,
            label: label,
            child: FilledButton.icon(
              onPressed: onGetReading,
              icon: const GetReadingIcon(),
              label: Text(label),
            ),
          ),
        ],
      ),
    );
  }
}
