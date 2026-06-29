// Spectrum Analysis — wiring + hub + topic-screen smoke tests.
//
// Guards:
//  (a) the catalog / route / help-id wiring for the `spectrum-analysis` id (an
//      in-app reference in Educational Resources, like Antenna Fundamentals);
//  (b) that the hub renders its honest "a phone cannot capture RF" scope note
//      and all eight numbered topic cards, in both dark and light themes without
//      throwing;
//  (c) that tapping each topic card navigates to its teaching screen, including
//      the signature gallery (which builds nine DarkRasterDiagramCards; the
//      bundled rasters do not decode in the test asset bundle, so each collapses
//      gracefully without throwing).
//
// The module pushes its eight topic screens via MaterialPageRoute, so the test
// drives navigation through the live hub rather than named routes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/educational/spectrum_analysis_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Widget _harness({required bool light}) => MaterialApp(
      theme: light ? AppTheme.light() : AppTheme.dark(),
      home: const SpectrumAnalysisScreen(),
    );

ToolEntry _entry() => kToolCategories
    .expand((ToolCategory c) => c.tools)
    .firstWhere((ToolEntry t) => t.id == 'spectrum-analysis');

/// The hub is a ListView; cards below the first viewport are not built until
/// scrolled into view. Scroll until [finder] resolves, mirroring a reader.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
}

void main() {
  group('catalog + route wiring', () {
    test('the id resolves to a live ToolEntry in Educational Resources', () {
      final ToolEntry entry = _entry();
      expect(entry.title, 'Spectrum Analysis');
      expect(entry.routeName, '/tools/spectrum-analysis');
      expect(entry.isLive, isTrue);
      // Educational Resources is not a subgroup-ordered category → no subgroup.
      expect(entry.subgroup, isNull);

      final ToolCategory cat = kToolCategories.firstWhere(
        (ToolCategory c) =>
            c.tools.any((ToolEntry t) => t.id == 'spectrum-analysis'),
      );
      expect(cat.id, 'educational-resources');
    });

    test('the route is registered and follows the /tools/<id> convention', () {
      expect(
        AppRouter.routes.containsKey(AppRouter.spectrumAnalysis),
        isTrue,
      );
      expect(AppRouter.spectrumAnalysis, '/tools/spectrum-analysis');
    });

    test('the tool-id constant is stable', () {
      expect(kSpectrumAnalysisToolId, 'spectrum-analysis');
    });
  });

  group('hub (dark)', () {
    testWidgets('renders the title, lead, scope note, and eight topic cards',
        (WidgetTester tester) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();

      expect(find.text('Spectrum Analysis'), findsWidgets);
      // The honest scope note leads the module.
      expect(
        find.textContaining('Your phone cannot run a spectrum analyzer'),
        findsOneWidget,
      );
      // All eight numbered topic titles are reachable on the hub by scrolling.
      for (final String title in <String>[
        'Why a spectrum analyzer?',
        'How it works',
        'The knobs',
        'The three views',
        'Fingerprinting interferers',
        'Comparing captures',
        'The tools',
        'Mitigation',
      ]) {
        await _scrollTo(tester, find.text(title));
        expect(find.text(title), findsOneWidget, reason: 'topic "$title"');
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('hub (light)', () {
    testWidgets('renders without throwing in light theme',
        (WidgetTester tester) async {
      await tester.pumpWidget(_harness(light: true));
      await tester.pump();
      expect(find.text('Spectrum Analysis'), findsWidgets);
      await _scrollTo(tester, find.text('Mitigation'));
      expect(find.text('Mitigation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('topic navigation', () {
    /// Scroll the hub to a topic card by title, tap it, and settle on the
    /// pushed teaching screen.
    Future<void> openTopic(WidgetTester tester, String title) async {
      await _scrollTo(tester, find.text(title));
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
    }

    testWidgets('each topic card opens its teaching screen',
        (WidgetTester tester) async {
      // (hub title, an excerpt from the top-of-page lead of the pushed screen,
      // which is always in the first viewport so no detail scroll is needed).
      const List<List<String>> topics = <List<String>>[
        <String>[
          'Why a spectrum analyzer?',
          'reveals the non-Wi-Fi interferers a Wi-Fi adapter',
        ],
        <String>['How it works', 'There are two architectures'],
        <String>['The knobs', 'A handful of controls decide what the trace'],
        <String>['The three views', 'Three views answer three different'],
        <String>['Fingerprinting interferers', 'Every interferer has a shape'],
        <String>[
          'Comparing captures',
          'Max-hold and averaging answer opposite questions',
        ],
        <String>['The tools', 'Current leaders first'],
        <String>['Mitigation', 'Removing the source is the only complete fix'],
      ];

      // Pump the hub ONCE, then navigate in and back out per topic (re-pumping
      // a fresh harness each loop introduces a transient empty-scrollable frame).
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();

      for (final List<String> t in topics) {
        await openTopic(tester, t[0]);
        expect(
          find.textContaining(t[1]),
          findsWidgets,
          reason: 'opening "${t[0]}" should show its lead "${t[1]}"',
        );
        expect(tester.takeException(), isNull, reason: 'on "${t[0]}"');
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('the signature gallery renders all nine interferer names',
        (WidgetTester tester) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      await openTopic(tester, 'Fingerprinting interferers');

      // The nine signature names, each above its (gracefully degrading) raster.
      final Scrollable scroll =
          tester.widget(find.byType(Scrollable).first);
      for (final String name in <String>[
        'Microwave oven',
        'Bluetooth Classic',
        'Analog video camera',
        'Bluetooth Low Energy (BLE)',
        'Baby monitor (analog)',
        'Drone / FPV downlink',
        'ZigBee / 802.15.4',
        'Analog cordless phone',
        'Continuous wireless bridge',
      ]) {
        await tester.scrollUntilVisible(
          find.text(name),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(name), findsOneWidget, reason: 'signature "$name"');
      }
      // Ensure the gallery is actually a scroll (the harness above touched it).
      expect(scroll.axisDirection, AxisDirection.down);
      expect(tester.takeException(), isNull);
    });
  });
}
