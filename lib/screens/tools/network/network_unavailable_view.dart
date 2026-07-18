// NetworkUnavailableView — the web (and platform-missing) fallback state for
// active-network tools.
//
// Per brief §15: network-dependent tools are HIDDEN/disabled on web with a
// clear "download the native app" prompt — never a crash, never a broken
// control. Per §10 anti-patterns: the message is precise and non-apologetic.
//
// This is the single, reusable empty/unavailable surface shared by Interface
// Information, DNS Lookup, and Port Scan so the message stays consistent.
//
// The default headline/body come from the [NetworkUnavailableReason] enum.
// Optional [headline] / [message] / [icon] overrides let a caller carry a
// precise, tool-specific verdict (e.g. a desktop build that cannot launch the
// system traceroute) through this same surface, so an expected platform limit
// never has to borrow an "error" affordance to be shown. All existing callers
// pass neither override and keep their reason-driven copy unchanged.

import 'package:flutter/material.dart';

import '../../../services/network/network_support.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';

class NetworkUnavailableView extends StatelessWidget {
  const NetworkUnavailableView({
    super.key,
    required this.toolName,
    required this.reason,
    this.headline,
    this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  /// The tool the user tried to open, named in the message.
  final String toolName;

  final NetworkUnavailableReason reason;

  /// Optional override for the headline. When null, the headline is derived
  /// from [reason] (the original behavior). Lets a caller state a precise,
  /// tool-specific verdict (for example a desktop build that cannot launch the
  /// system traceroute) through this same unavailable surface instead of a
  /// bespoke card, so every "not available" state reads the same.
  final String? headline;

  /// Optional override for the body copy. When null, the body is derived from
  /// [reason] (the original behavior). Use it to carry guidance the reason enum
  /// cannot express, such as which builds do work and what to use instead.
  final String? message;

  /// Optional override for the leading icon. When null, the icon is derived
  /// from [reason] (the original behavior).
  final IconData? icon;

  /// Optional action button label. When both [actionLabel] and [onAction] are
  /// non-null, a single primary action renders beneath the body — used by a
  /// RECOVERABLE state (for example [NetworkUnavailableReason.macosLocationDenied],
  /// which deep-links the Location Services settings pane) to give the user a way
  /// out. The permanent states ([web], [platformApiMissing]) pass neither and stay
  /// action-free, exactly as before.
  final String? actionLabel;

  /// Optional callback for the action button. Rendered only when paired with
  /// [actionLabel]. Kept a plain [VoidCallback] so the caller owns the async work
  /// (open the settings pane) and this view stays a stateless presentation layer.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    final (IconData defaultIcon, String defaultHeadline, String defaultBody) =
        switch (reason) {
      NetworkUnavailableReason.web => (
          Icons.download_outlined,
          'Available in the native app',
          '$toolName needs direct network access that browsers do not '
              'allow. Download the WLAN Pros Toolbox for macOS, Windows, '
              'Android, or iOS to use the active network tools.',
        ),
      NetworkUnavailableReason.platformApiMissing => (
          Icons.info_outline,
          'Not available on this platform',
          '$toolName relies on a system API this platform does not expose to '
              'apps. The rest of the toolbox works normally here.',
        ),
      NetworkUnavailableReason.macosLocationDenied => (
          Icons.location_off_outlined,
          'Location access needed',
          'macOS requires Location access to read Wi-Fi details like the network '
              'name and the access point each connection uses, so $toolName has '
              'nothing to record without it. Turn it on for WLAN Pros Toolbox in '
              'System Settings, under Privacy and Security, then Location '
              'Services. The button below opens that settings pane.',
        ),
    };

    final IconData resolvedIcon = icon ?? defaultIcon;
    final String resolvedHeadline = headline ?? defaultHeadline;
    final String resolvedBody = message ?? defaultBody;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(resolvedIcon, size: 48, color: colors.textTertiary),
              const SizedBox(height: AppSpacing.sm),
              Text(
                resolvedHeadline,
                style: text.headlineSmall?.copyWith(
                  color: colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                resolvedBody,
                style: text.bodyLarge?.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              if (actionLabel != null && onAction != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
