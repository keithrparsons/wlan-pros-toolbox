// NotOnWifiCard — the honest "you're not connected to Wi-Fi" state.
//
// WHY THIS EXISTS (2026-06-25, Keith): a user spent hours debugging "no live
// data" on the live Wi-Fi surfaces when the real cause was simply that the
// iPhone was on CELLULAR, not Wi-Fi — and the app showed NOTHING (or a perpetual
// "Waiting for the first reading…"). Every tester on cellular, or stuck on a
// half-joined captive portal, hits the same wall. This card replaces that silent
// dead-end with a plain, honest message and a "Check again" affordance, so the
// live tools never look broken when the device is simply off Wi-Fi.
//
// It is only ever shown when the connection probe returns a POSITIVE
// not-on-Wi-Fi signal (WifiConnectionStatus.notOnWifi) AND no live reading has
// arrived — never from missing/ambiguous data (GL-005). A wired desktop or a
// Location-gated read resolves to `unknown` and never reaches this card.
//
// Styling is GL-003 App Mode: surface1 card, hairline border, textSecondary
// copy, a quiet textTertiary state glyph, and a single lime-primary FilledButton
// for the "Check again" action. Mirrors LiveRfLockedCard so the two pre-data
// states read as siblings.

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';

/// The honest "not connected to Wi-Fi" card shown on the live Wi-Fi surfaces when
/// the device is demonstrably off Wi-Fi (e.g. cellular-only) and no live reading
/// has arrived. Carries a plain explanation and a "Check again" retry.
class NotOnWifiCard extends StatelessWidget {
  const NotOnWifiCard({
    super.key,
    required this.onRetry,
    this.title = "You're not connected to Wi-Fi",
    this.message = 'You may be on cellular, Wi-Fi may be turned off, or you '
        'joined a network that has not finished connecting. Connect to a Wi-Fi '
        'network to see live Wi-Fi data.',
  });

  /// Re-runs the connection probe (and native identity read). Wired to the
  /// "Check again" button so a user who has just joined Wi-Fi can re-check in
  /// place, without leaving the screen.
  final VoidCallback onRetry;

  /// The headline. Overridable so a host surface (e.g. Test My Connection's
  /// Wi-Fi-signal section) can scope the wording to its own context.
  final String title;

  /// The explanatory body copy. Overridable for the same reason as [title].
  final String message;

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
              // Decorative state glyph — the title carries the meaning, so the
              // icon is excluded from semantics (no duplicate announcement).
              Icon(
                Icons.wifi_off_outlined,
                size: 22,
                color: colors.textTertiary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                // liveRegion so a screen-reader user who is on-screen when the
                // probe flips to not-on-Wi-Fi hears the state change announced
                // (WCAG SC 4.1.3), matching LivePrimingCard's parity.
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    title,
                    style: text.titleSmall?.copyWith(color: colors.textPrimary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            button: true,
            label: 'Check again',
            child: FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Check again'),
            ),
          ),
        ],
      ),
    );
  }
}
