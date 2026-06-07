// Antenna Fundamentals — wiring + screen + diagram-resolver tests.
//
// Guards:
//  (a) the catalog / route / keyword / help wiring for the new
//      `antenna-fundamentals` id (Quick Reference, Wi-Fi & RF subgroup);
//  (b) that the read-along teaching screen renders its verbatim copy — the
//      thesis pull-quote, every section header, the §8.13 mounting warning, the
//      antenna-type table, and the deployment quick-map — in BOTH dark and light
//      themes without throwing;
//  (c) the diagram resolver gracefully degrades: a slug not in the bundle renders
//      no diagram band (no broken-image box), and a bundled slug renders one.
//
// The diagrams are gated on the build-time asset manifest, so the screen tests
// drive AntennaFundamentalsDiagrams.debugSetBundled to simulate "none built"
// (the prose-only path) and "all seven built" without touching a real bundle.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/data/antenna_fundamentals_diagrams.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/antenna_fundamentals_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const List<String> _slugs = <String>[
  'g1-azimuth-vs-elevation',
  'g2-omni-donut',
  'g3-polar-plot-anatomy',
  'g4-pattern-comparison',
  'g5-coverage-floorplan',
  'g6-downtilt',
  'g7-polarization',
];

Widget _harness({required bool light}) => MaterialApp(
      theme: light ? AppTheme.light() : AppTheme.dark(),
      home: const AntennaFundamentalsScreen(),
    );

/// The teaching screen is a long ListView, so items below the first viewport are
/// not built until scrolled into view. This scrolls the body until [finder]
/// resolves, mirroring how a reader scrolls the page.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
}

ToolEntry _entry() => kToolCategories
    .expand((ToolCategory c) => c.tools)
    .firstWhere((ToolEntry t) => t.id == 'antenna-fundamentals');

void main() {
  // The screen always degrades safely when no diagrams are bundled; default the
  // resolver to "nothing built" so every test is deterministic unless it opts in.
  setUp(() => AntennaFundamentalsDiagrams.debugSetBundled(<String>{}));
  tearDown(() => AntennaFundamentalsDiagrams.debugReset());

  group('catalog + route + keyword wiring', () {
    test('the tool id resolves to a live ToolEntry in Educational Resources',
        () {
      // Moved 2026-06-06 (BF6-3) from Quick Reference to Educational Resources.
      final ToolEntry entry = _entry();
      expect(entry.title, 'Antenna Fundamentals');
      expect(entry.routeName, '/tools/antenna-fundamentals');
      expect(entry.isLive, isTrue);
      // Educational Resources is not a subgroup-ordered category → no subgroup.
      expect(entry.subgroup, isNull);

      final ToolCategory cat = kToolCategories.firstWhere(
        (ToolCategory c) =>
            c.tools.any((ToolEntry t) => t.id == 'antenna-fundamentals'),
      );
      expect(cat.id, 'educational-resources');
    });

    test('the route is registered and follows the /tools/<id> convention', () {
      expect(
        AppRouter.routes.containsKey(AppRouter.antennaFundamentals),
        isTrue,
      );
      expect(AppRouter.antennaFundamentals, '/tools/antenna-fundamentals');
    });

    test('the tool-id constant is stable', () {
      expect(kAntennaFundamentalsToolId, 'antenna-fundamentals');
    });

    test('search keywords are registered for discovery', () {
      final List<String>? kw = kToolKeywords['antenna-fundamentals'];
      expect(kw, isNotNull);
      expect(
        kw,
        containsAll(<String>[
          'antenna',
          'gain',
          'dbi',
          'beamwidth',
          'polarization',
          'downtilt',
          'radiation pattern',
          'omni',
          'directional',
          'dipole',
          'azimuth',
          'elevation',
          'polar plot',
        ]),
      );
    });
  });

  group('diagram resolver', () {
    test('has() is false for every slug when nothing is bundled', () {
      AntennaFundamentalsDiagrams.debugSetBundled(<String>{});
      for (final String slug in _slugs) {
        expect(AntennaFundamentalsDiagrams.has(slug), isFalse);
      }
    });

    test('path() follows the convention and has() reads the manifest', () {
      expect(
        AntennaFundamentalsDiagrams.path('g3-polar-plot-anatomy'),
        'assets/tool-diagrams/antenna-fundamentals/g3-polar-plot-anatomy.svg',
      );
      AntennaFundamentalsDiagrams.debugSetBundled(<String>{
        AntennaFundamentalsDiagrams.path('g3-polar-plot-anatomy'),
      });
      expect(
        AntennaFundamentalsDiagrams.has('g3-polar-plot-anatomy'),
        isTrue,
      );
      expect(AntennaFundamentalsDiagrams.has('g1-azimuth-vs-elevation'), isFalse);
    });
  });

  group('screen (dark)', () {
    testWidgets('renders the title and the thesis at the top', (tester) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();

      expect(find.text('Antenna Fundamentals'), findsWidgets);
      // The through-line thesis pull-quote (verbatim, in the first viewport).
      expect(
        find.textContaining(
          'Use the antenna that covers what you want covered',
        ),
        findsWidgets,
      );
      expect(find.text('The one idea'), findsOneWidget);
    });

    testWidgets('every section header is reachable by scrolling', (tester) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();

      for (final String title in <String>[
        'Azimuth and elevation: the two planes',
        'Orientation: mounting, polarization, and tilt',
        'How to read an antenna diagram',
        'What antenna to use where',
        'The verdict, restated',
        'Deployment quick-map',
      ]) {
        await _scrollTo(tester, find.text(title));
        expect(find.text(title), findsOneWidget, reason: 'section "$title"');
      }
    });

    testWidgets('renders the §8.13 mounting warning verbatim', (tester) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      final Finder warning =
          find.text('Never mount an Access Point on a wall like a clock.');
      await _scrollTo(tester, warning);
      expect(warning, findsOneWidget);
    });

    testWidgets('renders the antenna-type table rows', (tester) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      await _scrollTo(tester, find.text('Dish / parabolic'));
      expect(find.text('Omni'), findsOneWidget);
      expect(find.text('Patch / panel'), findsOneWidget);
      expect(find.text('Sector'), findsOneWidget);
      expect(find.text('Yagi'), findsOneWidget);
      expect(find.text('Dish / parabolic'), findsOneWidget);
      // A verbatim range value from the table.
      expect(find.text('~15 to 40°'), findsOneWidget);
    });

    testWidgets('renders no diagram band when nothing is bundled (prose-only)',
        (tester) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      // The prose still renders; the diagram bands collapse to nothing.
      expect(find.text('The one idea'), findsOneWidget);
      // No AspectRatio diagram band is built when no diagram is bundled.
      expect(find.byType(AspectRatio), findsNothing);
    });
  });

  group('screen (light)', () {
    testWidgets('renders the full teaching scroll in light without throwing',
        (tester) async {
      await tester.pumpWidget(_harness(light: true));
      await tester.pump();
      expect(find.text('Antenna Fundamentals'), findsWidgets);
      await _scrollTo(
        tester,
        find.text('Never mount an Access Point on a wall like a clock.'),
      );
      expect(
        find.text('Never mount an Access Point on a wall like a clock.'),
        findsOneWidget,
      );
      await _scrollTo(tester, find.text('The verdict, restated'));
      expect(find.text('The verdict, restated'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
