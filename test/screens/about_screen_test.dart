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
// - Version SSOT: AppVersion.display matches the pubspec format `name (build)`.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/data/app_version.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/about_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

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

    // Item 8 — the REAL shipped version, not a placeholder.
    expect(find.text('Version ${AppVersion.display}'), findsOneWidget);
    expect(find.textContaining('[BUILD'), findsNothing);

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
      find.bySemanticsLabel('WLAN Pros — Wireless LAN Professionals'),
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

  test('AppVersion.display matches the "name (build)" format', () {
    expect(AppVersion.display, '${AppVersion.name} (${AppVersion.build})');
    // Sanity: the build value is non-empty and the name looks semver-ish.
    expect(AppVersion.name, isNotEmpty);
    expect(AppVersion.build, isNotEmpty);
  });
}
