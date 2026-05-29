// NetworkUnavailableView — the web (and platform-missing) fallback state for
// active-network tools.
//
// Per brief §15: network-dependent tools are HIDDEN/disabled on web with a
// clear "download the native app" prompt — never a crash, never a broken
// control. Per §10 anti-patterns: the message is precise and non-apologetic.
//
// This is the single, reusable empty/unavailable surface shared by Interface
// Information, DNS Lookup, and Port Scan so the message stays consistent.

import 'package:flutter/material.dart';

import '../../../services/network/network_support.dart';
import '../../../theme/app_tokens.dart';

class NetworkUnavailableView extends StatelessWidget {
  const NetworkUnavailableView({
    super.key,
    required this.toolName,
    required this.reason,
  });

  /// The tool the user tried to open, named in the message.
  final String toolName;

  final NetworkUnavailableReason reason;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    final (IconData icon, String headline, String body) = switch (reason) {
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
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: AppColors.textTertiary),
              const SizedBox(height: AppSpacing.sm),
              Text(
                headline,
                style: text.headlineSmall?.copyWith(
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                body,
                style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
