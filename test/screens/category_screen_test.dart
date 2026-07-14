// Widget tests for the grouped CategoryScreen (Ticket 2, mockup 02).
//
// Covers: grouped categories render section headers + count chips + content-type
// chips; the in-category search filters to matching rows and shows the
// no-results state; tapping a live row navigates; the flat Test Network category
// renders its pinned order with NO section headers (the pin path is untouched).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/screens/category_screen.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/section_header.dart';
import 'package:wlan_pros_toolbox/widgets/tool_row.dart';

ToolCategory _cat(String id) =>
    kToolCategories.firstWhere((ToolCategory c) => c.id == id);

Widget _harness(ToolCategory cat, {Map<String, WidgetBuilder>? routes}) =>
    MaterialApp(
      theme: AppTheme.dark(),
      home: CategoryScreen(category: cat),
      routes: routes ?? <String, WidgetBuilder>{},
    );

Widget _harnessWith(
  ToolCategory cat, {
  WifiInfoSource? source,
  WiFiDetailsBridge? bridge,
}) =>
    MaterialApp(
      theme: AppTheme.dark(),
      home: CategoryScreen(
        category: cat,
        sourceOverride: source,
        iosBridge: bridge,
      ),
    );

/// Minimal fake bridge for the live-setup banner: only [hasEverReceivedPayload]
/// and [openUrl] are exercised.
class _FakeBridge implements WiFiDetailsBridge {
  _FakeBridge({this.everReceived = false});

  @override
  Future<bool> consumeShortcutMissing() async => false;
  @override
  Future<void> markSetupInitiated() async {}
  @override
  Future<bool> hasInitiatedSetup() async => false;
  @override
  Future<bool> isShortcutsAppInstalled() async => true;
  @override
  Future<void> setLiveOriginRoute(String route) async {}
  @override
  Future<String?> consumeLiveErrorNav() async => null;

  bool everReceived;

  @override
  Future<bool> hasEverReceivedPayload() async => everReceived;
  @override
  Future<DateTime?> payloadReceivedAt() async => null;

  @override
  Future<bool> openUrl(String url) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('grouped category renders its section headers in order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_harness(_cat('rf-calculators')));
    await tester.pump();

    expect(find.byType(SectionHeader), findsWidgets);
    // The first editorial section for rf-calculators is "RF & Propagation".
    // The section name also appears in the filter-chip row, so scope the
    // assertion to the SectionHeader to count only the header instance.
    expect(
      find.descendant(
        of: find.byType(SectionHeader),
        matching: find.text('RF & Propagation'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(SectionHeader),
        matching: find.text('Antenna & Coverage'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the in-category search field filters to matching rows', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_cat('rf-calculators')));
    await tester.pump();

    // Type a term that matches only a couple of tools.
    await tester.enterText(find.byType(TextField), 'fresnel');
    await tester.pump();

    // Filtering collapses section headers; the matching row(s) remain.
    expect(find.byType(SectionHeader), findsNothing);
    expect(find.byType(ToolRow), findsWidgets);
    expect(find.text('Fresnel Zone'), findsOneWidget);
  });

  testWidgets('a no-match in-category query shows the no-results state', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_cat('rf-calculators')));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'zzzznotarealterm');
    await tester.pump();
    expect(find.textContaining('No tools match'), findsOneWidget);
    expect(find.byType(ToolRow), findsNothing);
  });

  testWidgets('tapping a live row navigates to its route', (tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    bool navigated = false;
    await tester.pumpWidget(
      _harness(
        _cat('rf-calculators'),
        routes: <String, WidgetBuilder>{
          '/tools/fspl': (_) {
            navigated = true;
            return const Scaffold(body: Text('FSPL'));
          },
        },
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Free Space Path Loss'));
    await tester.pumpAndSettle();
    expect(navigated, isTrue);
  });

  testWidgets('flat Test Network renders the pinned order with no headers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_harness(_cat('test-network')));
    await tester.pump();

    // Flat category → no section headers.
    expect(find.byType(SectionHeader), findsNothing);

    // The grouping helper still returns the pinned order for the flat path.
    // Wave 4 (2026-06-04): the merged connection tile was removed from the
    // catalog (reached via the home hero), so Network Quality leads the pins.
    final List<ToolSection> sections = groupedCategoryTools(_cat('test-network'));
    expect(sections, hasLength(1));
    expect(sections.single.tools.first.id, 'net-quality');
  });

  group('Test Network — one-time live-setup banner (iOS only)', () {
    testWidgets(
        'iOS + never received a payload SHOWS the actionable setup banner',
        (tester) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_harnessWith(
        _cat('test-network'),
        source: WifiInfoSource.iosShortcuts,
        bridge: _FakeBridge(everReceived: false),
      ));
      await tester.pumpAndSettle();

      // New iOS user, no payload ever → learn about the one-time Shortcut BEFORE
      // tapping into a live tool. The banner carries the setup button.
      expect(find.text('Set up live Wi-Fi (one-time)'), findsOneWidget);
    });

    testWidgets('iOS + already received a payload HIDES the banner (no nag)',
        (tester) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_harnessWith(
        _cat('test-network'),
        source: WifiInfoSource.iosShortcuts,
        bridge: _FakeBridge(everReceived: true),
      ));
      await tester.pumpAndSettle();

      // The Shortcut demonstrably works → the banner is gone permanently.
      expect(find.text('Set up live Wi-Fi (one-time)'), findsNothing);
    });

    testWidgets('macOS never shows the banner (CoreWLAN, no Shortcut)',
        (tester) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_harnessWith(
        _cat('test-network'),
        source: WifiInfoSource.macosCoreWlan,
        bridge: _FakeBridge(everReceived: false),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Set up live Wi-Fi (one-time)'), findsNothing);
    });

    testWidgets('the banner only appears on the Test Network category',
        (tester) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_harnessWith(
        _cat('networking'),
        source: WifiInfoSource.iosShortcuts,
        bridge: _FakeBridge(everReceived: false),
      ));
      await tester.pumpAndSettle();

      // Even on iOS + not set up, a non-Test-Network category has no banner.
      expect(find.text('Set up live Wi-Fi (one-time)'), findsNothing);
    });

    testWidgets('tapping the banner button opens the install sheet',
        (tester) async {
      tester.view.physicalSize = const Size(420, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_harnessWith(
        _cat('test-network'),
        source: WifiInfoSource.iosShortcuts,
        bridge: _FakeBridge(everReceived: false),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Set up live Wi-Fi (one-time)'));
      await tester.pumpAndSettle();

      // The one-time onboarding sheet opens with the crystal-clear steps.
      expect(find.text('Tap Add the Shortcut below.'), findsOneWidget);
      expect(find.text('Add the Shortcut'), findsOneWidget);
    });
  });
}
