// One-tap "Get Reading" trigger affordance (TICKET-03).
//
// Shared by the Wi-Fi Information and Cellular Information iOS screens. It is the
// PRIMARY action that fires the companion Shortcut via the run-shortcut
// x-callback URL, replacing the old "go run the Shortcut manually" UX. iOS flicks
// to Shortcuts, runs the one-shot Shortcut (which stores its payload to the App
// Group), then returns to the app; the host screen re-reads the payload on
// resume and refreshes.
//
// States (SOP-007 §5):
//   * idle        -> a primary FilledButton labelled "Get Reading".
//   * triggering  -> the button is disabled with a spinner + "Getting reading…"
//                    (the app is backgrounded during the flick; this is the
//                    brief in-between).
//   * error       -> an honest error banner above the button (Shortcut missing /
//                    cancelled) with a link to the install how-to as the
//                    fallback. The button stays available to retry.
//
// GL-003: surface1 card / hairline border for the error banner, lime primary for
// the button, §8.13 statusDanger reserved for the verdict word + icon (paired
// with text, never color-only). GL-004 strings: "Wi-Fi" spelling owned by the
// caller's [errorMessage]; US spelling; no em dashes.

import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';

/// The primary "Get Reading" trigger button plus its triggering/error states.
class GetReadingAction extends StatelessWidget {
  const GetReadingAction({
    super.key,
    required this.onGetReading,
    required this.triggering,
    required this.triggerError,
    required this.errorMessage,
    required this.onOpenInstall,
  });

  /// Fires the trigger. Null while [triggering] so a second tap is impossible.
  final VoidCallback? onGetReading;

  /// True while the app is backgrounded during the flick to Shortcuts.
  final bool triggering;

  /// True when the last trigger returned x-error (Shortcut missing / cancelled).
  final bool triggerError;

  /// The honest error line shown when [triggerError] is true.
  final String errorMessage;

  /// Opens the install / how-to sheet — the fallback when the Shortcut is not
  /// found. Surfaced as a text link inside the error banner.
  final VoidCallback onOpenInstall;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (triggerError) ...[
          _TriggerErrorBanner(
            message: errorMessage,
            onOpenInstall: onOpenInstall,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Semantics(
          button: true,
          enabled: !triggering,
          label: triggering ? 'Getting reading' : 'Get reading',
          child: FilledButton.icon(
            onPressed: onGetReading,
            icon: triggering
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      // On the lime FilledButton fill, the spinner reads against
                      // the charcoal foreground used for primary-button content.
                      color: AppColors.secondary,
                    ),
                  )
                : const Icon(Icons.download_done_outlined),
            label: Text(triggering ? 'Getting reading…' : 'Get Reading'),
          ),
        ),
      ],
    );
  }
}

/// Honest error banner: the Shortcut could not run (missing / errored / the user
/// cancelled). Pairs the §8.13 danger verdict (icon + word) with the message and
/// offers the install how-to as the fallback path.
class _TriggerErrorBanner extends StatelessWidget {
  const _TriggerErrorBanner({
    required this.message,
    required this.onOpenInstall,
  });

  final String message;
  final VoidCallback onOpenInstall;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // §8.13: the danger hue carries a verdict and is always paired
              // with text — never color-only.
              const Icon(
                Icons.error_outline,
                size: 20,
                color: AppColors.statusDanger,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    style: text.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              button: true,
              label: 'How to install the Shortcut',
              child: TextButton(
                onPressed: onOpenInstall,
                child: const Text('Install the Shortcut'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
