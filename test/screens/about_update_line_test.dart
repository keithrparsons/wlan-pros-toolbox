// The About screen's update line, rendered through the REAL AboutScreen.
//
// The load-bearing assertion is the negative one: an `unknown` result must not
// produce anything that reads like reassurance. A check that failed and a check
// that succeeded look different on screen, and only the successful one is
// allowed to say the build is current.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/screens/about_screen.dart';
import 'package:wlan_pros_toolbox/services/app_update_service.dart';
import 'package:wlan_pros_toolbox/services/network/json_http_client.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _kUpToDate = 'This is the latest published version.';
const String _kUnknown = 'Could not check for a newer version.';

/// An AppUpdateService pinned to the direct-download channel with a scripted
/// fetch, so the About screen renders a chosen verdict offline.
AppUpdateService scripted(ReleaseFetcher fetcher) => AppUpdateService(
      fetcher: fetcher,
      resolveChannel: () => UpdateChannel.githubReleases,
      getStore: SharedPreferences.getInstance,
    );

/// The About screen is a scrolling list, so the version section only builds
/// when the viewport is tall enough. Same tall-surface approach the sibling
/// about_screen_test.dart uses for its content assertions.
Future<void> pumpAbout(WidgetTester tester, AppUpdateService svc) async {
  tester.view.physicalSize = const Size(420, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: AboutScreen(updateService: svc),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Deterministic runtime build identity, so the version read resolves
    // immediately and the update check is what is under test.
    PackageInfo.setMockInitialValues(
      appName: 'WLAN Pros Toolbox',
      packageName: 'com.wlanpros.toolbox',
      version: '1.8.1',
      buildNumber: '26071901',
      buildSignature: '',
    );
  });

  testWidgets('an up-to-date result states the build is current',
      (WidgetTester tester) async {
    await pumpAbout(
      tester,
      scripted((Duration _) async => <String, dynamic>{'tag_name': 'v0.0.1'}),
    );
    expect(find.text(_kUpToDate), findsOneWidget);
    expect(find.text(_kUnknown), findsNothing);
  });

  testWidgets('an available update names the version and offers a link',
      (WidgetTester tester) async {
    await pumpAbout(
      tester,
      scripted((Duration _) async => <String, dynamic>{
            'tag_name': 'v99.0.0',
            'html_url': 'https://example.invalid/releases/tag/v99.0.0',
          }),
    );
    expect(find.text('Version 99.0.0 is available.'), findsOneWidget);
    expect(find.text('Get the update'), findsOneWidget);
    expect(find.text(_kUpToDate), findsNothing);
  });

  testWidgets('a failed check says so and NEVER claims the build is current',
      (WidgetTester tester) async {
    await pumpAbout(
      tester,
      scripted((Duration _) async => throw const JsonHttpException(
            JsonHttpErrorKind.transport,
            'Failed host lookup: api.github.com',
          )),
    );
    expect(find.text(_kUnknown), findsOneWidget);
    // The whole point: no reassurance, and no download link.
    expect(find.text(_kUpToDate), findsNothing);
    expect(find.text('Get the update'), findsNothing);
  });

  testWidgets('unknown is rendered in a different register than up to date',
      (WidgetTester tester) async {
    await pumpAbout(
      tester,
      scripted((Duration _) async => throw const JsonHttpException(
            JsonHttpErrorKind.transport,
            'offline',
          )),
    );
    final Color unknownColor =
        tester.widget<Text>(find.text(_kUnknown)).style!.color!;

    await tester.pumpWidget(const SizedBox.shrink());
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await pumpAbout(
      tester,
      scripted((Duration _) async => <String, dynamic>{'tag_name': 'v0.0.1'}),
    );
    final Color upToDateColor =
        tester.widget<Text>(find.text(_kUpToDate)).style!.color!;

    expect(unknownColor, isNot(upToDateColor));
  });

  testWidgets('a store-managed build shows no update line at all',
      (WidgetTester tester) async {
    await pumpAbout(
      tester,
      AppUpdateService(
        fetcher: (Duration _) async => <String, dynamic>{'tag_name': 'v99.0.0'},
        resolveChannel: () => UpdateChannel.managedByStore,
        getStore: SharedPreferences.getInstance,
      ),
    );
    expect(find.text(_kUpToDate), findsNothing);
    expect(find.text(_kUnknown), findsNothing);
    expect(find.text('Get the update'), findsNothing);
    expect(find.textContaining('is available.'), findsNothing);
  });

  testWidgets('nothing is claimed before the check resolves',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final Completer<Map<String, dynamic>> gate =
        Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: AboutScreen(
          updateService: scripted((Duration _) => gate.future),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // The About screen has rendered; the check has not answered.
    expect(find.text('Version and Feedback'), findsOneWidget);
    expect(find.text(_kUpToDate), findsNothing);
    expect(find.text(_kUnknown), findsNothing);

    gate.complete(<String, dynamic>{'tag_name': 'v0.0.1'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text(_kUpToDate), findsOneWidget);
  });
}
