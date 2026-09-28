// Home Internet, Explained: wiring + screen + figure tests.
//
// Guards:
//  (a) the catalog / route / keyword / help wiring for the
//      `home-internet-explained` id (Wi-Fi Classroom, Guided Lessons shelf);
//  (b) the lesson renders its verbatim copy (title, first section, every
//      section header, the comparison rows) in BOTH dark and light;
//  (c) the figure resolver degrades gracefully: a slug missing from the bundle
//      renders no figure band (its caption still reads), and a bundled slug
//      renders one;
//  (d) the checklist ticks, and inline markup never reaches the screen as raw
//      backticks or asterisks;
//  (e) the Starlink, Explained link is resolved from the catalog by id: a
//      button when that lesson is in the build, none when it is not, and the
//      sentence naming it reads either way;
//  (f) the two figures the guide calls to scale stay to scale.
//
// Figures are gated on the build-time asset manifest, so the tests drive
// HomeInternetDiagrams.debugSetBundled to simulate "none built" and "one
// built" without depending on a real manifest.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/data/home_internet_diagrams.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/home_internet_explained_screen.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const List<String> _slugs = <String>[
  'cover-roads-to-the-house',
  'f1-six-roads',
  'f2-every-road-is-shared',
  'f3-orbit-heights',
  'f4-idle-latency',
  'f5-download-upload',
  'f6-where-the-fcc-measures',
];

const List<String> _sectionTitles = <String>[
  'The short answer',
  'Six roads to your house',
  'Every road is shared',
  'The wired options',
  'The wireless options',
  'Latency: why lag is its own number',
  'Upload, and data limits',
  'All the options side by side',
  'Where the FCC measures, and where you do',
  'Which one should I pick?',
  'Six things people get wrong',
  'Check, challenge, test',
  'Where these facts come from',
];

Widget _harness({required bool light}) => MaterialApp(
  theme: light ? AppTheme.light() : AppTheme.dark(),
  // Every tool route except "/", which `home` stands in for, so the Starlink
  // link can navigate.
  routes: Map<String, WidgetBuilder>.of(AppRouter.routes)
    ..remove(Navigator.defaultRouteName),
  home: const HomeInternetExplainedScreen(),
);

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
}

Iterable<ToolEntry> get _allTools =>
    kToolCategories.expand((ToolCategory c) => c.tools);

ToolEntry _entry() =>
    _allTools.firstWhere((ToolEntry t) => t.id == 'home-internet-explained');

/// Reads the numeric attribute [name] from one SVG element's source.
double _attr(String element, String name) => double.parse(
  RegExp(' $name="([0-9.]+)"').firstMatch(element)!.group(1)!,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    HomeInternetDiagrams.debugSetBundled(<String>{});
    HomeInternetExplainedScreen.debugClearFigureCache();
  });
  tearDown(() => HomeInternetDiagrams.debugReset());

  group('catalog + route + keyword + help wiring', () {
    test('the id is a live Guided Lesson in Wi-Fi Classroom', () {
      final ToolEntry entry = _entry();
      expect(entry.title, 'Home Internet, Explained');
      expect(entry.routeName, '/tools/home-internet-explained');
      expect(entry.isLive, isTrue);
      expect(entry.subgroup, 'Guided Lessons');
      final ToolCategory cat = kToolCategories.firstWhere(
        (ToolCategory c) =>
            c.tools.any((ToolEntry t) => t.id == 'home-internet-explained'),
      );
      expect(cat.id, 'wifi-classroom');
    });

    test('the route is registered and follows /tools/<id>', () {
      expect(
        AppRouter.routes.containsKey(AppRouter.homeInternetExplained),
        isTrue,
      );
      expect(
        AppRouter.homeInternetExplained,
        '/tools/home-internet-explained',
      );
      expect(kHomeInternetExplainedToolId, 'home-internet-explained');
    });

    test('search keywords are registered', () {
      expect(
        kToolKeywords['home-internet-explained'],
        containsAll(<String>['home internet', 'fiber', 'starlink', 'latency']),
      );
    });

    test('the help entry exists and names the related tools', () async {
      final ToolHelpStore store = ToolHelpStore.fromJson(
        await rootBundle.loadString('assets/help/tool_help.json'),
      );
      expect(
        store.forId('home-internet-explained')?.name,
        'Home Internet, Explained',
      );
      final String raw = await rootBundle.loadString(
        'assets/help/tool_help.json',
      );
      expect(raw, contains('Why a Busy Line Lags'));
      expect(raw, contains('The Slowest Link Wins'));
    });
  });

  group('figure resolver', () {
    test('has() is false for every slug when nothing is bundled', () {
      for (final String slug in _slugs) {
        expect(HomeInternetDiagrams.has(slug), isFalse);
      }
    });

    test('path() follows the convention and has() reads the manifest', () {
      expect(
        HomeInternetDiagrams.path('f4-idle-latency'),
        'assets/tool-diagrams/home-internet/f4-idle-latency.svg',
      );
      HomeInternetDiagrams.debugSetBundled(<String>{
        HomeInternetDiagrams.path('f4-idle-latency'),
      });
      expect(HomeInternetDiagrams.has('f4-idle-latency'), isTrue);
      expect(HomeInternetDiagrams.has('f1-six-roads'), isFalse);
    });

    test('every figure is on disk', () {
      for (final String slug in _slugs) {
        expect(
          File(HomeInternetDiagrams.path(slug)).existsSync(),
          isTrue,
          reason: slug,
        );
      }
    });
  });

  group('figures the guide calls to scale', () {
    test('Figure 3: 618 px for 35,786 km; GPS sits at 20,200 km', () {
      final String svg = File(
        HomeInternetDiagrams.path('f3-orbit-heights'),
      ).readAsStringSync();
      // Every orbit dot is a circle on the y = 100 line.
      final List<double> xs = RegExp(r'<circle cx="([0-9.]+)" cy="100"')
          .allMatches(svg)
          .map((RegExpMatch m) => double.parse(m.group(1)!))
          .toList();
      const double pxPerKm = 618 / 35786;
      expect(xs, contains(closeTo(46 + 20200 * pxPerKm, 0.1)));
      expect(xs, contains(closeTo(46 + 480 * pxPerKm, 0.1)));
      expect(xs, contains(closeTo(664, 0.1)));
    });

    test('Figure 4: bars sit on their axes (3.5 px/ms, then 0.375 px/ms '
        'from 400 ms); the high-orbit bar ends at 680 ms', () {
      final String svg = File(
        HomeInternetDiagrams.path('f4-idle-latency'),
      ).readAsStringSync();
      // Fiber, 7 to 14 ms, is the first 18-high bar.
      final RegExp bar = RegExp(r'<rect [^>]*height="18"[^>]*>');
      final String fiber = bar.firstMatch(svg)!.group(0)!;
      expect(_attr(fiber, 'x'), closeTo(150 + 7 * 3.5, 0.1));
      expect(_attr(fiber, 'width'), closeTo(7 * 3.5, 0.1));
      // High orbit: the last 18-high bar, from 480 to 680 ms on axis B.
      final String high = bar.allMatches(svg).last.group(0)!;
      double b(double ms) => 540 + (ms - 400) * 0.375;
      expect(_attr(high, 'x'), closeTo(b(480), 0.1));
      expect(_attr(high, 'width'), closeTo(b(680) - b(480), 0.1));
    });
  });

  for (final bool light in <bool>[false, true]) {
    final String mode = light ? 'light' : 'dark';

    group('screen ($mode)', () {
      testWidgets('renders the title and the first section', (tester) async {
        await tester.pumpWidget(_harness(light: light));
        await tester.pump();
        expect(find.text('Home Internet, Explained'), findsOneWidget);
        expect(find.text('The short answer'), findsOneWidget);
        expect(
          find.textContaining('Internet service reaches a house in one of six'),
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
    testWidgets('the comparison renders every service, verbatim', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      await _scrollTo(tester, find.text('All the options side by side'));
      for (final String cell in <String>[
        'Low-orbit satellite (Starlink)',
        'Amazon Leo',
        'Phone hotspot',
        'About 0.5 to 0.7 seconds',
        'Not selling to homes as of July 2026',
        'Needs open sky; see its own lesson',
      ]) {
        await _scrollTo(tester, find.text(cell));
        expect(find.text(cell), findsOneWidget, reason: cell);
      }
    });

    testWidgets('no page numbers survive from the print guide', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      await _scrollTo(tester, find.text('Where these facts come from'));
      expect(find.textContaining('(page '), findsNothing);
      expect(find.textContaining('on page 14'), findsNothing);
    });

    testWidgets('inline markup renders without its characters', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      final Finder task = find.text("1. See what's offered at your address");
      await _scrollTo(tester, task);
      final Finder path = find.textContaining('Go to broadbandmap.fcc.gov');
      expect(path, findsOneWidget);
      final String shown = tester.widget<Text>(path).textSpan!.toPlainText();
      expect(shown.contains('`'), isFalse);
      expect(shown.contains('**'), isFalse);
    });

    testWidgets('a checklist item ticks and unticks', (tester) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      final Finder item = find.text(
        'Your address on the FCC map, with every technology listed',
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

    testWidgets('the Starlink lesson link follows the catalog', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      final Finder sentence = find.textContaining(
        'Starlink has a Guided Lesson of its own, Starlink, Explained.',
      );
      await _scrollTo(tester, sentence);
      expect(sentence, findsOneWidget);
      final Finder button = find.byKey(
        const ValueKey<String>('home-internet-link-starlink-explained'),
      );
      final bool inBuild = _allTools.any(
        (ToolEntry t) => t.id == kStarlinkLessonToolId && t.isLive,
      );
      if (!inBuild) {
        // Before wifi-lab/starlink-lesson merges: no button, sentence reads.
        expect(button, findsNothing);
        return;
      }
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(find.text('Open Starlink, Explained'), findsOneWidget);
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(find.byType(HomeInternetExplainedScreen), findsNothing);
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
            'home-internet-figure-cover-roads-to-the-house',
          ),
        ),
        findsNothing,
      );
      final Finder caption = find.textContaining(
        'Six ways in, one handoff point.',
      );
      await _scrollTo(tester, caption);
      expect(caption, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('home-internet-figure-f1-six-roads')),
        findsNothing,
      );
    });

    for (final bool light in <bool>[false, true]) {
      testWidgets('renders a band for a bundled slug (light: $light)', (
        tester,
      ) async {
        HomeInternetDiagrams.debugSetBundled(<String>{
          HomeInternetDiagrams.path('f1-six-roads'),
        });
        await tester.pumpWidget(_harness(light: light));
        await tester.pump();
        final Finder band = find.byKey(
          const ValueKey<String>('home-internet-figure-f1-six-roads'),
        );
        await _scrollTo(tester, band);
        expect(band, findsOneWidget);
        expect(
          find.byKey(
            const ValueKey<String>(
              'home-internet-figure-f2-every-road-is-shared',
            ),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
