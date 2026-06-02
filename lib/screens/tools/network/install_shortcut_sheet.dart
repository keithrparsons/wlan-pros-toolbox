// Install-the-companion-Shortcut onboarding sheet (TICKET-03 A1).
//
// Explains the one-time install, opens the iCloud Shortcut link via the bridge,
// and offers an honest "I've installed it, run it" affordance. iOS cannot report
// whether a Shortcut is installed, so the app never claims a fake "installed".
// Install copy states plainly that NO Location permission is required
// (confirmed TICKET-01).
//
// Styling is GL-003: surface2 sheet, card radius, lime primary for the install
// button, textSecondary on the no-permission reassurance note (§8.13: status
// verdict tokens are never decorative), IBM Plex Sans body.

import 'package:flutter/material.dart';

import '../../../services/network/shortcuts_config.dart';
import '../../../services/network/wifi_details_bridge.dart';
import '../../../theme/app_tokens.dart';

class InstallShortcutSheet extends StatelessWidget {
  const InstallShortcutSheet({
    super.key,
    required this.bridge,
    required this.onInstalled,
  });

  /// Bridge used to open the iCloud link (and shared with the host screen).
  final WiFiDetailsBridge bridge;

  /// Called after the user taps "I've installed it, run it" so the host can
  /// re-resolve install-state from the App Group.
  final Future<void> Function() onInstalled;

  Future<void> _install(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final bool ok =
        await bridge.openUrl(ShortcutsConfig.kCompanionShortcutUrl);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the Shortcut link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool isPlaceholder = ShortcutsConfig.isShortcutUrlPlaceholder;

    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Install the companion Shortcut',
                style: text.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Live mode reads your network from the "WLAN Pros Live" '
                'Shortcut you install once. After installing, tap Start to '
                'begin live readings on this screen.',
                style:
                    text.bodyLarge?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              const _Step(
                number: 1,
                text: 'Tap Install Shortcut to open it in the Shortcuts app, '
                    'then add it.',
              ),
              const _Step(
                number: 2,
                text: 'Back here, tap Start to begin live readings. Your '
                    'network details stream onto this screen.',
              ),
              const SizedBox(height: AppSpacing.sm),
              const _NoPermissionNote(),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: isPlaceholder ? null : () => _install(context),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Install Shortcut'),
              ),
              if (isPlaceholder) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Install link coming soon.',
                  // Muted disabled-affordance caption (F-04).
                  style:
                      text.bodySmall?.copyWith(color: AppColors.textTertiary),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              OutlinedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await onInstalled();
                },
                child: const Text("I've installed it, run it"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppSpacing.md,
            height: AppSpacing.md,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.surface3,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: textTheme.labelMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoPermissionNote extends StatelessWidget {
  const _NoPermissionNote();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lock_open_outlined,
            // Reassurance, not a computed verdict -> textSecondary (§8.13
            // rule 1: status tokens are never used decoratively).
            color: AppColors.textSecondary,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'No Location permission is required. The Shortcut reads your '
              'network without any location prompt.',
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
