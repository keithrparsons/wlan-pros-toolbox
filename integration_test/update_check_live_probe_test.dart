// TEMPORARY manual probe (not for CI): drives the update check against the REAL
// GitHub API on the real macOS embedder, and renders the real About screen so
// the three visible states can be seen rather than assumed.
//
// Run: flutter test integration_test/update_check_live_probe_test.dart -d macos

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/screens/about_screen.dart';
import 'package:wlan_pros_toolbox/services/app_update_service.dart';
import 'package:wlan_pros_toolbox/services/network/json_http_client.dart';
import 'package:wlan_pros_toolbox/services/update/update_platform_io.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LIVE: channel + real GitHub fetch on macOS', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    debugPrint('MAS receipt present: ${macHasAppStoreReceipt()}');
    debugPrint('resolved channel:    ${resolveUpdateChannel()}');

    // Raw live payload, so we see exactly what the API returned.
    final Map<String, dynamic> raw =
        await fetchLatestRelease(const Duration(seconds: 10));
    debugPrint('live tag_name: ${raw['tag_name']}');
    debugPrint('live html_url: ${raw['html_url']}');

    // Real running version against the real feed.
    final AppUpdateResult live =
        await AppUpdateService().check(currentVersion: '1.8.1');
    debugPrint('LIVE verdict for 1.8.1: ${live.status}');

    // Force the update-available branch off the same live data.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppUpdateResult old =
        await AppUpdateService().check(currentVersion: '0.9.0');
    debugPrint(
      'LIVE verdict for 0.9.0: ${old.status} -> ${old.latestVersion} '
      '${old.releaseUrl}',
    );

    // A real transport failure, injected at the seam.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppUpdateResult offline = await AppUpdateService(
      fetcher: (Duration _) async => throw const JsonHttpException(
        JsonHttpErrorKind.transport,
        'Failed host lookup: api.github.com',
      ),
      resolveChannel: () => UpdateChannel.githubReleases,
    ).check(currentVersion: '1.8.1');
    debugPrint('INJECTED offline verdict: ${offline.status}');

    // And a genuinely unroutable host, so the offline path is exercised end to
    // end through the real dart:io stack rather than only at the seam.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppUpdateResult deadHost = await AppUpdateService(
      fetcher: (Duration t) =>
          JsonHttpClient().getJson('https://api.github.invalid/x', timeout: t),
      resolveChannel: () => UpdateChannel.githubReleases,
    ).check(currentVersion: '1.8.1');
    debugPrint('REAL dead-host verdict: ${deadHost.status}');

    expect(live.status, isNot(AppUpdateStatus.notApplicable));
    expect(offline.status, AppUpdateStatus.unknown);
    expect(deadHost.status, AppUpdateStatus.unknown);
  });

  testWidgets('LIVE: real About screen renders the real verdict', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    tester.view.physicalSize = const Size(420, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // The genuine About screen with the genuine theme, hitting the real API.
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const AboutScreen(),
    ));

    // Frame 1: before the async check resolves, nothing is claimed.
    await tester.pump();
    await tester.pump();
    debugPrint('--- first frame, update line texts ---');
    _dumpUpdateTexts(tester);

    // Real socket I/O only runs outside the fake-async test zone.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 5));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    debugPrint('--- after live check ---');
    _dumpUpdateTexts(tester);
  });
}

/// Print every rendered string that the update line could be showing, so the
/// real on-screen wording is observed rather than assumed.
void _dumpUpdateTexts(WidgetTester tester) {
  const List<String> needles = <String>[
    'This is the latest published version.',
    'Could not check for a newer version.',
    'is available.',
    'Get the update',
  ];
  bool any = false;
  for (final Widget w in tester.widgetList<Text>(find.byType(Text))) {
    final String? d = (w as Text).data;
    if (d == null) continue;
    for (final String n in needles) {
      if (d.contains(n)) {
        debugPrint('VISIBLE: "$d"');
        any = true;
      }
    }
  }
  if (!any) debugPrint('VISIBLE: (no update line rendered)');
}
