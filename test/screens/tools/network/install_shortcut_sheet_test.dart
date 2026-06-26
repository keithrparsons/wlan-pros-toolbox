// Widget tests for the one-time live-setup sheet (InstallShortcutSheet).
//
// Covers: the three crystal-clear steps render; "Add the Shortcut" opens the
// LIVE companion-Shortcut iCloud link (the one the live tools actually run, NOT
// the legacy single-tap Shortcut); "I've added it" pops the sheet and fires the
// onInstalled callback. The sheet depends only on an openUrl capability, so the
// test passes a plain function — no bridge class needed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/install_shortcut_sheet.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_live_shortcuts_config.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  Widget host(Widget child) => MaterialApp(theme: AppTheme.dark(), home: child);

  testWidgets('renders the three short setup steps', (tester) async {
    await tester.pumpWidget(host(
      InstallShortcutSheet(
        openUrl: (String _) async => true,
        onInstalled: () async {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Set up live Wi-Fi'), findsOneWidget);
    expect(find.text('Tap Add the Shortcut below.'), findsOneWidget);
    expect(find.text('In the Shortcuts app, tap Add Shortcut.'), findsOneWidget);
    // Step 3 now names the post-install priming round-trip (Get reading + the
    // first-run permission prompt), not "Start".
    expect(
      find.textContaining('tap Get reading'),
      findsOneWidget,
    );
    expect(find.textContaining('iOS asks'), findsOneWidget);
    // No Location permission reassurance is present.
    expect(find.textContaining('No Location permission'), findsOneWidget);
  });

  testWidgets('Add the Shortcut marks setup initiated (drives priming)',
      (tester) async {
    int setupInitiatedCalls = 0;
    await tester.pumpWidget(host(
      InstallShortcutSheet(
        openUrl: (String _) async => true,
        onInstalled: () async {},
        onSetupInitiated: () async => setupInitiatedCalls++,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add the Shortcut'));
    await tester.pumpAndSettle();

    // Tapping Add the Shortcut marks the priming flag so the live tools switch
    // from the cold setup prompt to the "tap Get reading to finish" step.
    expect(setupInitiatedCalls, 1);
  });

  testWidgets('absent Shortcuts app leads with the install-Shortcuts-app step',
      (tester) async {
    String? openedUrl;
    await tester.pumpWidget(host(
      InstallShortcutSheet(
        openUrl: (String url) async {
          openedUrl = url;
          return true;
        },
        onInstalled: () async {},
        // Best-effort presence check reports Shortcuts is NOT installed.
        isShortcutsAppInstalled: () async => false,
      ),
    ));
    await tester.pumpAndSettle();

    // The companion-Shortcut flow is replaced by the install-Shortcuts-app step.
    expect(find.text("Install Apple's Shortcuts app"), findsOneWidget);
    expect(find.text('Add the Shortcut'), findsNothing);

    await tester.tap(find.text('Get Shortcuts from the App Store'));
    await tester.pumpAndSettle();
    expect(openedUrl, WifiLiveShortcutsConfig.kShortcutsAppStoreUrl);
  });

  testWidgets('present Shortcuts app shows the normal companion-Shortcut flow',
      (tester) async {
    await tester.pumpWidget(host(
      InstallShortcutSheet(
        openUrl: (String _) async => true,
        onInstalled: () async {},
        isShortcutsAppInstalled: () async => true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Set up live Wi-Fi'), findsOneWidget);
    expect(find.text('Add the Shortcut'), findsOneWidget);
    expect(find.text("Install Apple's Shortcuts app"), findsNothing);
  });

  testWidgets('Add the Shortcut opens the LIVE companion-Shortcut iCloud link',
      (tester) async {
    String? openedUrl;
    await tester.pumpWidget(host(
      InstallShortcutSheet(
        openUrl: (String url) async {
          openedUrl = url;
          return true;
        },
        onInstalled: () async {},
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add the Shortcut'));
    await tester.pumpAndSettle();

    // It must open the LIVE Shortcut the live tools actually run — never the
    // legacy single-tap one. This is the bug testers hit: the sheet used to
    // install the wrong Shortcut.
    expect(openedUrl, WifiLiveShortcutsConfig.kLiveShortcutUrl);
  });

  testWidgets("I've added it pops the sheet and fires onInstalled",
      (tester) async {
    int installedCalls = 0;
    await tester.pumpWidget(host(
      Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showInstallShortcutSheet(
                context: context,
                openUrl: (String _) async => true,
                onInstalled: () async => installedCalls++,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Set up live Wi-Fi'), findsOneWidget);

    await tester.tap(find.text("I've added it"));
    await tester.pumpAndSettle();

    // The sheet is gone and the host's onInstalled ran (re-resolve / kick off).
    expect(find.text('Set up live Wi-Fi'), findsNothing);
    expect(installedCalls, 1);
  });
}
