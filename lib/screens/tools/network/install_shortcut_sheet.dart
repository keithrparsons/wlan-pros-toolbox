// One-time "set up live Wi-Fi" onboarding sheet.
//
// This is the single, discoverable place a new iOS user installs the combined
// "WLAN Pros Live" companion Shortcut that drives every live tool (Wi-Fi
// Information, Test My Connection, Cellular Information). iOS cannot auto-install
// a Shortcut and cannot report whether one is installed, so the app never claims
// a fake "installed"; it explains the one-time step in three short moves and
// opens the iCloud link.
//
// The link and name come from [WifiLiveShortcutsConfig] — the SAME Shortcut the
// live tools actually trigger by name — so what the sheet installs and what the
// tools run can never drift. (The earlier draft installed the legacy single-tap
// "WLAN Pros Wi-Fi" Shortcut, which is NOT what Live mode runs; that was the
// root cause testers saw "live tools don't work" after installing.)
//
// Styling is GL-003 App Mode: surface2 sheet, card radius, lime primary for the
// install button, textSecondary on the no-permission reassurance note (§8.13:
// status verdict tokens are never decorative), IBM Plex Sans body. iOS-only —
// macOS reads CoreWLAN natively and never presents this sheet.

import 'package:flutter/material.dart';

import '../../../services/network/wifi_live_shortcuts_config.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import 'setup_live_wifi_icon.dart';

/// Opens an external URL (the iCloud Shortcut link). Both [WiFiDetailsBridge]
/// and [CellularInfoBridge] expose a method with this signature, so the sheet
/// depends on the capability, not on a specific bridge class — that keeps the
/// one onboarding sheet reusable across every live tool regardless of which
/// bridge the host screen owns.
typedef ShortcutLinkOpener = Future<bool> Function(String url);

/// Opens the one-time live-setup sheet as a modal bottom sheet, styled per the
/// GL-003 App Mode sheet convention (surface2 fill, scroll-controlled).
/// [openUrl] opens the iCloud link (pass the host bridge's `openUrl`);
/// [onInstalled] runs after the user taps "I've added it" so the host can
/// re-resolve install-state / kick off a reading.
Future<void> showInstallShortcutSheet({
  required BuildContext context,
  required ShortcutLinkOpener openUrl,
  required Future<void> Function() onInstalled,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.surface2,
    isScrollControlled: true,
    builder: (_) => InstallShortcutSheet(
      openUrl: openUrl,
      onInstalled: onInstalled,
    ),
  );
}

class InstallShortcutSheet extends StatelessWidget {
  const InstallShortcutSheet({
    super.key,
    required this.openUrl,
    required this.onInstalled,
  });

  /// Opens the iCloud link. Pass the host bridge's `openUrl` method.
  final ShortcutLinkOpener openUrl;

  /// Called after the user taps "I've added it" so the host can re-resolve
  /// install-state and begin a live reading.
  final Future<void> Function() onInstalled;

  Future<void> _install(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final bool ok = await openUrl(WifiLiveShortcutsConfig.kLiveShortcutUrl);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the Shortcut link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool isPlaceholder =
        WifiLiveShortcutsConfig.isLiveShortcutUrlPlaceholder;

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
                'Set up live Wi-Fi',
                style: text.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'iOS reads live Wi-Fi and cellular details through a small '
                'companion Shortcut, "WLAN Pros Live". You add it once, and '
                'every live tool works from then on. It takes about a minute.',
                style: text.bodyLarge?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              const _Step(
                number: 1,
                text: 'Tap Add the Shortcut below.',
              ),
              const _Step(
                number: 2,
                text: 'In the Shortcuts app, tap Add Shortcut.',
              ),
              const _Step(
                number: 3,
                text: 'Come back here and tap Start — live Wi-Fi now works.',
              ),
              const SizedBox(height: AppSpacing.xs),
              const _NoPermissionNote(),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: isPlaceholder ? null : () => _install(context),
                icon: const SetupLiveWifiIcon(),
                label: const Text('Add the Shortcut'),
              ),
              if (isPlaceholder) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Install link coming soon.',
                  // Muted disabled-affordance caption (F-04).
                  style: text.bodySmall?.copyWith(color: colors.textTertiary),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              OutlinedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await onInstalled();
                },
                child: const Text("I've added it"),
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
    final AppColorScheme colors = context.colors;
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
            decoration: BoxDecoration(
              color: colors.surface3,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: textTheme.labelMedium?.copyWith(
                color: colors.textPrimary,
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_open_outlined,
            // Reassurance, not a computed verdict -> textSecondary (§8.13
            // rule 1: status tokens are never used decoratively).
            color: colors.textSecondary,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'No Location permission is required. The Shortcut reads your '
              'network without any location prompt.',
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
