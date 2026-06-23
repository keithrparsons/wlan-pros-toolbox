// Widget + data tests for the About screen (feat/about-section).
//
// Coverage:
// - Smoke: the screen mounts with the "About" app-bar title and renders.
// - Section coverage: all 9 SOP-020 item titles render exactly once.
// - Resolved decisions: the real version value, the "Data not collected."
//   privacy line, and the "View licenses" entry are present (no placeholders).
// - Route integrity: AppRouter registers the /about route to AboutScreen.
// - Responsive: renders at a 375x900 iPhone viewport without RenderFlex
//   overflow.
// - Runtime version: the build badge + item-8 line render the RUNTIME version +
//   build number (package_info_plus, mocked) in the "Version X (build Y)" form.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:wlan_pros_toolbox/data/app_version.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/about_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// A deterministic build identity used across the runtime-version tests. The
/// buildNumber mimics the CFBundleVersion timestamp ship_ios.sh injects.
const String _kMockVersion = '1.1.0';
const String _kMockBuild = '202606052247';

Future<void> _pumpAbout(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.dark(), home: const AboutScreen()),
  );
  await tester.pumpAndSettle();
}

/// Pump the About screen in a TALL viewport so the lazily-built ListView lays
/// out every section at once. The screen is a scrolling list; in the real app
/// off-screen sections build on scroll, so content tests size the viewport tall
/// enough to materialize all nine sections rather than scrolling each into view.
Future<void> _pumpAboutTall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await _pumpAbout(tester);
}

void main() {
  setUp(() {
    // Bind a deterministic runtime build identity so PackageInfo.fromPlatform
    // resolves immediately to known values inside widget tests.
    PackageInfo.setMockInitialValues(
      appName: 'WLAN Pros Toolbox',
      packageName: 'com.wlanpros.toolbox',
      version: _kMockVersion,
      buildNumber: _kMockBuild,
      buildSignature: '',
    );
  });

  testWidgets('About screen mounts with the About app-bar title', (
    tester,
  ) async {
    await _pumpAbout(tester);
    expect(find.widgetWithText(AppBar, 'About'), findsOneWidget);
  });

  testWidgets('All 9 SOP-020 section titles render exactly once', (
    tester,
  ) async {
    await _pumpAboutTall(tester);

    const List<String> titles = <String>[
      'Why this toolbox',
      'Why Gratis',
      'Who is WLAN Pros',
      'The #WLPC Conference',
      'Get in touch',
      'Help and Documentation',
      'Privacy',
      'Version and Feedback',
      'Credits',
    ];
    for (final String title in titles) {
      expect(
        find.text(title),
        findsOneWidget,
        reason: 'expected the "$title" section heading exactly once',
      );
    }
  });

  testWidgets('Resolved decisions are present (version, privacy, licenses)', (
    tester,
  ) async {
    await _pumpAboutTall(tester);

    // The REAL runtime version + build (package_info_plus), in the labeled
    // "Version X (build Y)" form, rendered in BOTH the top build badge and the
    // item-8 Version section — so it appears exactly twice.
    const String expected = 'Version $_kMockVersion (build $_kMockBuild)';
    expect(find.text(expected), findsNWidgets(2));
    expect(find.textContaining('[BUILD'), findsNothing);
    // No placeholder left behind once the Future resolves.
    expect(find.text('Version…'), findsNothing);

    // Item 7 — privacy verdict.
    expect(find.text('We don\'t collect your data.'), findsOneWidget);

    // Item 9 — OSS attributions via the built-in registry, not a hand list.
    expect(find.text('View licenses'), findsOneWidget);
  });

  testWidgets('External link buttons render for the linked sections', (
    tester,
  ) async {
    await _pumpAboutTall(tester);

    // The five brand links (2026-06-05), slotted across the linked sections:
    //   item 3 → Main site and resource library (wlanprofessionals.com)
    //   item 4 → The conference (thewlpc.com) + #WLPC Weekly signup
    //   item 5 → Training and classes + Contact and feedback
    expect(find.text('Main site and resource library'), findsOneWidget);
    expect(find.text('The conference'), findsOneWidget);
    expect(find.text('#WLPC Weekly signup'), findsOneWidget);
    expect(find.text('Training and classes'), findsOneWidget);
    expect(find.text('Contact and feedback'), findsOneWidget);
    // "Send feedback" appears in both Help (item 6) and Version (item 8).
    expect(find.text('Send feedback'), findsNWidgets(2));
  });

  testWidgets('Brand lockup renders on its §8.21 white plate at the top', (
    tester,
  ) async {
    await _pumpAboutTall(tester);

    // The §8.21 lockup image is bundled and surfaced with an accessible name.
    expect(
      find.image(const AssetImage('assets/brand/wlan_pros_logo.png')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('WLAN Pros, Wireless LAN Professionals'),
      findsOneWidget,
    );
  });

  testWidgets('About screen fits a 375x900 iPhone viewport without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final List<Object> overflows = <Object>[];
    final FlutterExceptionHandler? previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exception.toString().contains('RenderFlex overflowed') ||
          details.exception.toString().contains('overflowed by')) {
        overflows.add(details.exception);
      }
    };
    addTearDown(() => FlutterError.onError = previous);

    await _pumpAbout(tester);

    expect(
      overflows,
      isEmpty,
      reason: 'About screen overflowed at 375x900: '
          '${overflows.map((Object e) => e.toString()).join("; ")}',
    );
  });

  test('AppRouter registers /about to a builder', () {
    expect(AppRouter.routes.containsKey(AppRouter.about), isTrue);
    expect(AppRouter.about, '/about');
  });

  test('AppVersion.load reads the runtime version + build number', () async {
    final AppVersionInfo info = await AppVersion.load();
    expect(info.version, _kMockVersion);
    expect(info.buildNumber, _kMockBuild);
    expect(info.display, 'Version $_kMockVersion (build $_kMockBuild)');
  });

  test('AppVersionInfo.display omits the build clause when blank', () {
    const AppVersionInfo info = AppVersionInfo(version: '2.0.0', buildNumber: '');
    expect(info.display, 'Version 2.0.0');
  });

  testWidgets('Build badge resolves the runtime value without crashing', (
    tester,
  ) async {
    // initState kicks off the PackageInfo Future; the badge starts at its
    // placeholder ('Version…', _version == null) and swaps to the real value
    // once it resolves. The mocked PackageInfo resolves on a microtask, so by
    // pumpAndSettle the placeholder is gone and the real value is shown — and
    // the screen never throws while the value is in flight.
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const AboutScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Version…'), findsNothing);
    expect(find.text('Version $_kMockVersion (build $_kMockBuild)'),
        findsWidgets);
  });

  testWidgets('Build badge carries a copy affordance', (tester) async {
    await _pumpAboutTall(tester);
    // §8.16 AppCopyAction renders an enabled copy control once the runtime
    // value resolves; its tooltip mirrors the idle label.
    expect(find.byTooltip('Copy version and build'), findsOneWidget);
  });

  // ---- "Set up live Wi-Fi" — iOS-only install entry point ----
  //
  // On iOS the only way to install the "WLAN Pros Live" companion Shortcut was
  // from inside the live tools; this About row is the findable entry point. The
  // gate reads `defaultTargetPlatform` (via WifiInfoSourceResolver), so it is
  // driven here with `debugDefaultTargetPlatformOverride`.

  testWidgets('Set up live Wi-Fi row renders on iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await _pumpAboutTall(tester);

    // The section heading + the action button both carry the label.
    expect(find.text('Set up live Wi-Fi'), findsNWidgets(2));

    // Reset synchronously before the test body ends so the binding's
    // foundation-var invariant check passes.
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Set up live Wi-Fi row is ABSENT on macOS', (tester) async {
    // macOS reads CoreWLAN natively and has no Shortcut — the row must not
    // render (and must take no vertical space).
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await _pumpAboutTall(tester);

    expect(find.text('Set up live Wi-Fi'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });
}
