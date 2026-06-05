// LookupErrorCard — the shared error presentation for the API-backed network
// tools (BGP/ASN Lookup, IP Geolocation).
//
// WHY THIS EXISTS: both screens used to render every failure through one
// generic "Lookup failed" card, discarding the precise [JsonHttpErrorKind] the
// service already attached to the result. That made a timeout, a rate-limit, a
// dead network, and a typo all look identical, and offered no way to retry the
// recoverable ones. This widget branches the TITLE + ICON on the error kind and
// surfaces a "Try again" control on the kinds a retry can actually fix.
//
// DESIGN-SYSTEM NOTES (GL-003 §8):
//  - Icons stay neutral (`textTertiary`). Status colors (red/green) are §8.4
//    v1.1-deferred — NOT introduced here. Meaning is carried by the TITLE text
//    and BODY message, never by color alone.
//  - The retry affordance is a real ≥48dp control (OutlinedButton via the
//    app theme's 48dp button height) with an explicit Semantics label.
//  - Card surface/border/radius/spacing all come from tokens.

import 'package:flutter/material.dart';

import '../../../services/network/json_http_client.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';

/// The presentation a given [JsonHttpErrorKind] maps to: a short [title], a
/// neutral [icon], and whether a plain retry can plausibly fix it ([retryable]).
///
/// A null kind means the failure was a client-side input/validation rejection
/// (the service never reached the network), e.g. "enter a valid IP or ASN".
/// Those are not retryable as-is — the user has to change the input first.
@immutable
class LookupErrorPresentation {
  const LookupErrorPresentation({
    required this.title,
    required this.icon,
    required this.retryable,
  });

  final String title;
  final IconData icon;
  final bool retryable;

  @override
  bool operator ==(Object other) =>
      other is LookupErrorPresentation &&
      other.title == title &&
      other.icon == icon &&
      other.retryable == retryable;

  @override
  int get hashCode => Object.hash(title, icon, retryable);
}

/// Map a [JsonHttpErrorKind] (or null = input/validation) to its title, icon,
/// and retryability. Pure — unit-tested directly, no widget tree required.
///
/// Recoverable-by-retry kinds (timeout, rateLimited, transport) return
/// `retryable: true`; bad input, bad URL, HTTP status, and bad JSON do not,
/// because re-running the identical query would just fail the same way.
LookupErrorPresentation errorPresentationFor(JsonHttpErrorKind? kind) {
  switch (kind) {
    case JsonHttpErrorKind.rateLimited:
      return const LookupErrorPresentation(
        title: 'Rate-limited',
        icon: Icons.hourglass_empty,
        retryable: true,
      );
    case JsonHttpErrorKind.timeout:
      return const LookupErrorPresentation(
        title: 'Timed out',
        icon: Icons.schedule,
        retryable: true,
      );
    case JsonHttpErrorKind.transport:
      return const LookupErrorPresentation(
        title: 'Cannot reach API',
        icon: Icons.cloud_off,
        retryable: true,
      );
    case JsonHttpErrorKind.httpStatus:
      return const LookupErrorPresentation(
        title: 'API error',
        icon: Icons.error_outline,
        retryable: false,
      );
    case JsonHttpErrorKind.badJson:
      return const LookupErrorPresentation(
        title: 'Unexpected response',
        icon: Icons.report_gmailerrorred,
        retryable: false,
      );
    case JsonHttpErrorKind.badUrl:
      return const LookupErrorPresentation(
        title: 'Lookup failed',
        icon: Icons.error_outline,
        retryable: false,
      );
    case null:
      // No network kind attached → client-side input/validation rejection.
      return const LookupErrorPresentation(
        title: 'Check your input',
        icon: Icons.edit_outlined,
        retryable: false,
      );
  }
}

/// The error card itself: a kind-aware title + icon, the precise service
/// message as the body, and a "Try again" button on recoverable kinds.
class LookupErrorCard extends StatelessWidget {
  const LookupErrorCard({
    super.key,
    required this.errorKind,
    required this.message,
    required this.onRetry,
  });

  /// The error kind from the result; null for input/validation failures.
  final JsonHttpErrorKind? errorKind;

  /// The precise, user-facing message from the service.
  final String message;

  /// Re-runs the last query. Always supplied; the button only shows when the
  /// kind is retryable.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final LookupErrorPresentation p = errorPresentationFor(errorKind);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(p.icon, size: 20, color: colors.textTertiary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.title,
                      style: text.bodyLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: text.labelMedium
                          ?.copyWith(color: colors.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (p.retryable) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                label: 'Try the lookup again',
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Try again'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
