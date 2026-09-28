// Starlink, Explained: wiring + screen + figure tests.
//
// Guards:
//  (a) the catalog / route / keyword / help wiring for the
//      `starlink-explained` id (Wi-Fi Classroom, Guided Lessons shelf);
//  (b) the lesson renders its verbatim copy (title, first section, every
//      section header, the plan and router cards, the dated plan line) in
//      BOTH dark and light;
//  (c) the figure resolver degrades gracefully: a slug missing from the bundle
//      renders no figure band (its caption still reads), and a bundled slug
//      renders one;
//  (d) the Appendix B checklist ticks, and the inline menu-path markup never
//      reaches the screen as raw backticks or asterisks;
//  (e) the figure files keep the rules they were drawn to: only §8.20.7
//      allow-list colors, ASCII-only <text> (GL-003 §8.6.1), no <marker>, and
//      the aspect the band reserves matches each SVG's own viewBox.
//
// Figures are gated on the build-time asset manifest, so the tests drive
// StarlinkDiagrams.debugSetBundled to simulate "none built" and "one built"
// without depending on a real manifest.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/data/starlink_diagrams.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/starlink_explained_screen.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const List<String> _slugs = <String>[
  'cover-dish-satellite-gateway',
  'f1-orbits-to-scale',
  'f2-first-1300-km',
  'f3-data-path',
  'f4-latency',
  'f5-phased-array',
  'f6-dishes-to-scale',
  'f7-shared-capacity',
  'f8-tree-drops',
  'f9-two-links',
];

const List<String> _sectionTitles = <String>[
  'The short answer',
  'How high the satellites fly',
  'The path your data takes',
  'Where the milliseconds go',
  'A flat antenna that aims without moving',
  'Why speeds change',
  'Plans for homes and RVs',
  'Trees, snow and rain',
  'The Wi-Fi inside',
  'Six things people get wrong',
  'Step by step in the Starlink app',
  'Before you blame Starlink',
  'Where these facts come from',
];

/// The §8.20.7 allow-list: the swap keys plus the #1A1A1A pass-through.
const Set<String> _allowed = <String>{
  '#E5E5E5',
  '#9C9C9C',
  '#A2CC3A',
  '#A1CC3A',
  '#3A3A3A',
  '#F26E6E',
  '#E0A23A',
  '#5BD68A',
  '#1A1A1A',
};

Widget _harness({required bool light}) => MaterialApp(
  theme: light ? AppTheme.light() : AppTheme.dark(),
  home: const StarlinkExplainedScreen(),
);

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
}

ToolEntry _entry() => kToolCategories
    .expand((ToolCategory c) => c.tools)
    .firstWhere((ToolEntry t) => t.id == 'starlink-explained');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    StarlinkDiagrams.debugSetBundled(<String>{});
    StarlinkExplainedScreen.debugClearFigureCache();
  });
  tearDown(() => StarlinkDiagrams.debugReset());

  group('catalog + route + keyword + help wiring', () {
    test('the id is a live Guided Lesson in Wi-Fi Classroom', () {
      final ToolEntry entry = _entry();
      expect(entry.title, 'Starlink, Explained');
      expect(entry.routeName, '/tools/starlink-explained');
      expect(entry.isLive, isTrue);
      expect(entry.subgroup, 'Guided Lessons');
      final ToolCategory cat = kToolCategories.firstWhere(
        (ToolCategory c) =>
            c.tools.any((ToolEntry t) => t.id == 'starlink-explained'),
      );
      expect(cat.id, 'wifi-classroom');
    });

    test('the route is registered and follows /tools/<id>', () {
      expect(AppRouter.routes.containsKey(AppRouter.starlinkExplained), isTrue);
      expect(AppRouter.starlinkExplained, '/tools/starlink-explained');
      expect(kStarlinkExplainedToolId, 'starlink-explained');
    });

    test('search keywords are registered', () {
      expect(
        kToolKeywords['starlink-explained'],
        containsAll(<String>['starlink', 'satellite internet', 'bypass mode']),
      );
    });

    test('the help entry exists', () async {
      final ToolHelpStore store = ToolHelpStore.fromJson(
        await rootBundle.loadString('assets/help/tool_help.json'),
      );
      expect(store.forId('starlink-explained')?.name, 'Starlink, Explained');
    });
  });

  group('figure resolver', () {
    test('has() is false for every slug when nothing is bundled', () {
      for (final String slug in _slugs) {
        expect(StarlinkDiagrams.has(slug), isFalse);
      }
    });

    test('path() follows the convention and has() reads the manifest', () {
      expect(
        StarlinkDiagrams.path('f2-first-1300-km'),
        'assets/tool-diagrams/starlink/f2-first-1300-km.svg',
      );
      StarlinkDiagrams.debugSetBundled(<String>{
        StarlinkDiagrams.path('f2-first-1300-km'),
      });
      expect(StarlinkDiagrams.has('f2-first-1300-km'), isTrue);
      expect(StarlinkDiagrams.has('f1-orbits-to-scale'), isFalse);
    });
  });

  group('figure files', () {
    for (final String slug in _slugs) {
      test('$slug keeps its drawing rules', () {
        final String svg = File(StarlinkDiagrams.path(slug)).readAsStringSync();
        // Only allow-list colors, so the light swap recolors every mark.
        final Iterable<String> hexes = RegExp(
          r'#[0-9A-Fa-f]{6}\b',
        ).allMatches(svg).map((Match m) => m.group(0)!.toUpperCase());
        for (final String hex in hexes) {
          expect(_allowed, contains(hex), reason: '$slug uses off-list $hex');
        }
        for (final Match m in RegExp(r'rgba\([^)]*\)').allMatches(svg)) {
          expect(m.group(0), 'rgba(162,204,58,0.08)', reason: slug);
        }
        // ASCII-only <text>: a non-ASCII glyph tofus on the web path.
        for (final Match m in RegExp(
          r'<text[^>]*>([^<]*)</text>',
        ).allMatches(svg)) {
          final String t = m.group(1)!;
          expect(
            t.runes.every((int r) => r < 128),
            isTrue,
            reason: '$slug text "$t" is not ASCII',
          );
        }
        expect(svg.contains('<marker'), isFalse, reason: slug);
        expect(svg.contains('<style'), isFalse, reason: slug);
        // The band reserves this aspect before the SVG loads.
        final RegExpMatch vb = RegExp(
          r'viewBox="0 0 (\d+) (\d+)"',
        ).firstMatch(svg)!;
        final double aspect =
            double.parse(vb.group(1)!) / double.parse(vb.group(2)!);
        expect(
          debugStarlinkFigureAspects[slug],
          closeTo(aspect, 1e-9),
          reason: '$slug aspect table out of step with its viewBox',
        );
      });
    }
  });

  for (final bool light in <bool>[false, true]) {
    final String mode = light ? 'light' : 'dark';

    group('screen ($mode)', () {
      testWidgets('renders the title and the first section', (tester) async {
        await tester.pumpWidget(_harness(light: light));
        await tester.pump();
        expect(find.text('Starlink, Explained'), findsOneWidget);
        expect(find.text('The short answer'), findsOneWidget);
        expect(
          find.textContaining('Starlink is internet service from satellites'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('every section header is reachable by scrolling', (
        tester,
      ) async {
        await tester.pumpWidget(_harness(light: light));
        await tester.pump();
        for (final String title in _sectionTitles) {
          await _scrollTo(tester, find.text(title));
          expect(find.text(title), findsOneWidget, reason: title);
        }
        expect(tester.takeException(), isNull);
      });
    });
  }

  group('screen content', () {
    testWidgets('renders the plan cards, verbatim, with their date', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      final Finder dated = find.textContaining(
        'US plan names and rules as of 27 September 2026',
      );
      await _scrollTo(tester, dated);
      expect(dated, findsOneWidget);
      for (final String plan in <String>[
        'Residential 100 Mbps',
        'Roam 100GB and 300GB',
        'Roam Unlimited',
      ]) {
        await _scrollTo(tester, find.text(plan));
        expect(find.text(plan), findsOneWidget, reason: plan);
      }
    });

    testWidgets('renders the router cards with their column labels', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      // 'Router 3' also names section 5's kit card, so scroll to a value only
      // the router cards carry.
      final Finder coverage = find.text('up to 297 m²');
      await _scrollTo(tester, coverage);
      expect(coverage, findsOneWidget);
      expect(find.text('up to 204 m²'), findsOneWidget);
      expect(find.text("per Starlink's Mini spec sheet"), findsOneWidget);
    });

    testWidgets('page references name the section instead', (tester) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      final Finder fact = find.textContaining(
        'Test next to the router first. See the section The Wi-Fi inside.',
      );
      await _scrollTo(tester, fact);
      expect(fact, findsOneWidget);
      expect(find.textContaining('Page 10'), findsNothing);
    });

    testWidgets('menu paths render without their markup characters', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      final Finder task = find.text(
        '1. Check for obstructions before you mount',
      );
      await _scrollTo(tester, task);
      final Finder path = find.textContaining(
        'Open the Starlink app and tap Check for Obstructions.',
      );
      expect(path, findsOneWidget);
      final String shown = tester.widget<Text>(path).textSpan!.toPlainText();
      expect(shown.contains('`'), isFalse);
      expect(shown.contains('**'), isFalse);
    });

    testWidgets('a checklist item ticks and unticks', (tester) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      final Finder item = find.text(
        'Notice the time. Evenings are the busiest hours in most areas.',
      );
      await _scrollTo(tester, item);
      await tester.ensureVisible(item);
      await tester.pumpAndSettle();
      final Finder box = find.ancestor(
        of: item,
        matching: find.byType(CheckboxListTile),
      );
      expect(tester.widget<CheckboxListTile>(box).value, isFalse);
      await tester.tap(item);
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(box).value, isTrue);
      await tester.tap(item);
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(box).value, isFalse);
    });
  });

  group('figure band', () {
    testWidgets('renders nothing for a slug that is not bundled, and the '
        'caption still reads', (tester) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      expect(
        find.byKey(
          const ValueKey<String>(
            'starlink-figure-cover-dish-satellite-gateway',
          ),
        ),
        findsNothing,
      );
      final Finder caption = find.textContaining(
        'Earth and every orbit are drawn at the same scale.',
      );
      await _scrollTo(tester, caption);
      expect(caption, findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>('starlink-figure-f1-orbits-to-scale'),
        ),
        findsNothing,
      );
    });

    for (final bool light in <bool>[false, true]) {
      testWidgets('renders a band for a bundled slug (light: $light)', (
        tester,
      ) async {
        StarlinkDiagrams.debugSetBundled(<String>{
          StarlinkDiagrams.path('f2-first-1300-km'),
        });
        await tester.pumpWidget(_harness(light: light));
        await tester.pump();
        final Finder band = find.byKey(
          const ValueKey<String>('starlink-figure-f2-first-1300-km'),
        );
        await _scrollTo(tester, band);
        expect(band, findsOneWidget);
        // The other figures stay absent.
        expect(
          find.byKey(
            const ValueKey<String>('starlink-figure-f1-orbits-to-scale'),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
