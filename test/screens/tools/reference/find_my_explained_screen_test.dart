// Find My, Explained: wiring + screen + figure-resolver tests.
//
// Guards:
//  (a) the catalog / route / keyword / help wiring for the `find-my-explained`
//      id (Wi-Fi Classroom, Guided Lessons shelf);
//  (b) the lesson renders its verbatim copy (title, first section, every
//      section header, the devices table rows) in BOTH dark and light;
//  (c) the figure resolver degrades gracefully: a slug missing from the bundle
//      renders no figure band (its caption still reads), and a bundled slug
//      renders one;
//  (d) the travel checklist ticks, and the inline menu-path markup never
//      reaches the screen as raw backticks or asterisks.
//
// Figures are gated on the build-time asset manifest, so the tests drive
// FindMyDiagrams.debugSetBundled to simulate "none built" and "one built"
// without depending on a real manifest.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/data/find_my_diagrams.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/find_my_explained_screen.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const List<String> _slugs = <String>[
  'cover-people-devices-items',
  'f1-find-my-network',
  'f2-rotating-ids',
  'f3-where-the-dot-comes-from',
  'f4-three-radios',
  'f5-app-parts',
  'f6-phone-dies',
  'f7-lost-luggage',
  'f8-unwanted-tracker',
];

const List<String> _sectionTitles = <String>[
  'The short answer',
  "How a stranger's phone finds your bag",
  'Where the dot on the map comes from',
  'Three radios, three ranges',
  'Which of your devices can do what',
  'The four parts of the app',
  'Sharing with family and friends',
  'Your phone, even when it dies',
  'Lost luggage, step by step',
  "A tracker that isn't yours",
  'Six things people get wrong',
  'Step-by-step settings',
  'Travel checklist',
  'Where these facts come from',
];

Widget _harness({required bool light}) => MaterialApp(
  theme: light ? AppTheme.light() : AppTheme.dark(),
  home: const FindMyExplainedScreen(),
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
    .firstWhere((ToolEntry t) => t.id == 'find-my-explained');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FindMyDiagrams.debugSetBundled(<String>{});
    FindMyExplainedScreen.debugClearFigureCache();
  });
  tearDown(() => FindMyDiagrams.debugReset());

  group('catalog + route + keyword + help wiring', () {
    test('the id is a live Guided Lesson in Wi-Fi Classroom', () {
      final ToolEntry entry = _entry();
      expect(entry.title, 'Find My, Explained');
      expect(entry.routeName, '/tools/find-my-explained');
      expect(entry.isLive, isTrue);
      expect(entry.subgroup, 'Guided Lessons');
      final ToolCategory cat = kToolCategories.firstWhere(
        (ToolCategory c) =>
            c.tools.any((ToolEntry t) => t.id == 'find-my-explained'),
      );
      expect(cat.id, 'wifi-classroom');
    });

    test('the route is registered and follows /tools/<id>', () {
      expect(AppRouter.routes.containsKey(AppRouter.findMyExplained), isTrue);
      expect(AppRouter.findMyExplained, '/tools/find-my-explained');
      expect(kFindMyExplainedToolId, 'find-my-explained');
    });

    test('search keywords are registered', () {
      expect(
        kToolKeywords['find-my-explained'],
        containsAll(<String>['find my', 'airtag', 'wi-fi positioning']),
      );
    });

    test('the help entry exists', () async {
      final ToolHelpStore store = ToolHelpStore.fromJson(
        await rootBundle.loadString('assets/help/tool_help.json'),
      );
      expect(store.forId('find-my-explained')?.name, 'Find My, Explained');
    });
  });

  group('figure resolver', () {
    test('has() is false for every slug when nothing is bundled', () {
      for (final String slug in _slugs) {
        expect(FindMyDiagrams.has(slug), isFalse);
      }
    });

    test('path() follows the convention and has() reads the manifest', () {
      expect(
        FindMyDiagrams.path('f3-where-the-dot-comes-from'),
        'assets/tool-diagrams/find-my/f3-where-the-dot-comes-from.svg',
      );
      FindMyDiagrams.debugSetBundled(<String>{
        FindMyDiagrams.path('f3-where-the-dot-comes-from'),
      });
      expect(FindMyDiagrams.has('f3-where-the-dot-comes-from'), isTrue);
      expect(FindMyDiagrams.has('f1-find-my-network'), isFalse);
    });
  });

  for (final bool light in <bool>[false, true]) {
    final String mode = light ? 'light' : 'dark';

    group('screen ($mode)', () {
      testWidgets('renders the title and the first section', (tester) async {
        await tester.pumpWidget(_harness(light: light));
        await tester.pump();
        expect(find.text('Find My, Explained'), findsOneWidget);
        expect(find.text('The short answer'), findsOneWidget);
        expect(
          find.textContaining('Find My is one app that finds three kinds'),
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
    testWidgets('renders the devices table rows, verbatim', (tester) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      for (final String device in <String>[
        'iPhone 15, 16, 17 or iPhone Air',
        'iPhone 11 to 14',
        'iPhone SE, 16e, 17e',
        'Apple Watch Series 9 or later, Ultra 2 or later',
        'Apple Watch SE',
      ]) {
        await _scrollTo(tester, find.text(device));
        expect(find.text(device), findsOneWidget, reason: device);
      }
      expect(find.text('Standard range only'), findsOneWidget);
      expect(find.text('Yes (AirTag 2 only)'), findsOneWidget);
      expect(find.text('Yes, if they have iPhone 15 or later too'), findsOneWidget);
    });

    testWidgets('menu paths render without their markup characters', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      final Finder task = find.text('1. Turn on Find My for your iPhone');
      await _scrollTo(tester, task);
      final Finder path = find.textContaining(
        'Open Settings › [your name] › Find My.',
      );
      expect(path, findsOneWidget);
      final String shown = tester.widget<Text>(path).textSpan!.toPlainText();
      expect(shown.contains('`'), isFalse);
      expect(shown.contains('**'), isFalse);
    });

    testWidgets('a checklist item ticks and unticks', (tester) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      final Finder item = find.text('No tag shows a low-battery warning');
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
        find.byKey(const ValueKey<String>('find-my-figure-cover-people-devices-items')),
        findsNothing,
      );
      final Finder caption = find.textContaining('The Find My network. The');
      await _scrollTo(tester, caption);
      expect(caption, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('find-my-figure-f1-find-my-network')),
        findsNothing,
      );
      expect(find.byType(AspectRatio), findsNothing);
    });

    for (final bool light in <bool>[false, true]) {
      testWidgets('renders a band for a bundled slug (light: $light)', (
        tester,
      ) async {
        FindMyDiagrams.debugSetBundled(<String>{
          FindMyDiagrams.path('f1-find-my-network'),
        });
        await tester.pumpWidget(_harness(light: light));
        await tester.pump();
        final Finder band = find.byKey(
          const ValueKey<String>('find-my-figure-f1-find-my-network'),
        );
        await _scrollTo(tester, band);
        expect(band, findsOneWidget);
        // The other figures stay absent.
        expect(
          find.byKey(const ValueKey<String>('find-my-figure-f2-rotating-ids')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
