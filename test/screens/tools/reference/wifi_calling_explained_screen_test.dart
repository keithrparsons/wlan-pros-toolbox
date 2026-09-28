// Wi-Fi Calling, Explained: wiring + screen + figure-resolver tests.
//
// Guards:
//  (a) the catalog / route / keyword / help wiring for the
//      `wifi-calling-explained` id (Wi-Fi Classroom, Guided Lessons shelf);
//  (b) the lesson renders its verbatim copy (title, first section, every
//      section header) in BOTH dark and light;
//  (c) the two "Keith's note" boxes of the print guide are NOT in the lesson
//      (not yet approved by Keith), and no "page N" pointer survives;
//  (d) the emergency table's verdicts carry an icon, so color is never the
//      only cue, and the tables render their rows verbatim;
//  (e) the figure resolver degrades gracefully: a slug missing from the bundle
//      renders no figure band (its caption still reads), and a bundled slug
//      renders one;
//  (f) both checklists tick independently, and the inline menu-path markup
//      never reaches the screen as raw backticks or asterisks.
//
// Figures are gated on the build-time asset manifest, so the tests drive
// WifiCallingDiagrams.debugSetBundled to simulate "none built" and "one
// built" without depending on a real manifest.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/wifi_calling_diagrams.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/wifi_calling_explained_screen.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const List<String> _slugs = <String>[
  'cover-two-roads',
  'f1-two-roads',
  'f2-when-wifi',
  'f3-walking-out',
  'f4-emergency-call',
  'f5-other-devices',
  'f6-abroad',
  'f7-vs-apps',
  'f8-what-wifi-owes',
];

const List<String> _sectionTitles = <String>[
  'The short answer',
  'Two roads to the same phone company',
  'When your phone uses Wi-Fi',
  'Walking out the door mid-call',
  'Emergency calls',
  'Emergency calls around the world',
  'iPad, Mac and Apple Watch',
  'Calling home from abroad',
  'Wi-Fi Calling vs WhatsApp and FaceTime',
  'What your Wi-Fi owes a phone call',
  'Six things people get wrong',
  'How to turn it on',
  'Checklists',
  'Where these facts come from',
];

Widget _harness({required bool light}) => MaterialApp(
  theme: light ? AppTheme.light() : AppTheme.dark(),
  home: const WifiCallingExplainedScreen(),
);

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
}

/// Scrolls the whole lesson top to bottom, collecting every Text's plain
/// string along the way (the ListView builds sections lazily).
Future<String> _allText(WidgetTester tester) async {
  final StringBuffer out = StringBuffer();
  final ScrollableState scroll = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  while (true) {
    for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
      out.writeln(t.data ?? t.textSpan?.toPlainText() ?? '');
    }
    final ScrollPosition p = scroll.position;
    if (p.pixels >= p.maxScrollExtent) break;
    p.jumpTo((p.pixels + 400).clamp(0, p.maxScrollExtent));
    await tester.pump();
  }
  return out.toString();
}

ToolEntry _entry() => kToolCategories
    .expand((ToolCategory c) => c.tools)
    .firstWhere((ToolEntry t) => t.id == 'wifi-calling-explained');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    WifiCallingDiagrams.debugSetBundled(<String>{});
    WifiCallingExplainedScreen.debugClearFigureCache();
  });
  tearDown(() => WifiCallingDiagrams.debugReset());

  group('catalog + route + keyword + help wiring', () {
    test('the id is a live Guided Lesson in Wi-Fi Classroom', () {
      final ToolEntry entry = _entry();
      expect(entry.title, 'Wi-Fi Calling, Explained');
      expect(entry.routeName, '/tools/wifi-calling-explained');
      expect(entry.isLive, isTrue);
      expect(entry.subgroup, 'Guided Lessons');
      final ToolCategory cat = kToolCategories.firstWhere(
        (ToolCategory c) =>
            c.tools.any((ToolEntry t) => t.id == 'wifi-calling-explained'),
      );
      expect(cat.id, 'wifi-classroom');
    });

    test('the route is registered and follows /tools/<id>', () {
      expect(
        AppRouter.routes.containsKey(AppRouter.wifiCallingExplained),
        isTrue,
      );
      expect(AppRouter.wifiCallingExplained, '/tools/wifi-calling-explained');
      expect(kWifiCallingExplainedToolId, 'wifi-calling-explained');
    });

    test('search keywords are registered', () {
      expect(
        kToolKeywords['wifi-calling-explained'],
        containsAll(<String>['wi-fi calling', 'wifi calling', 'e911']),
      );
    });

    test('the help entry exists', () async {
      final ToolHelpStore store = ToolHelpStore.fromJson(
        await rootBundle.loadString('assets/help/tool_help.json'),
      );
      expect(
        store.forId('wifi-calling-explained')?.name,
        'Wi-Fi Calling, Explained',
      );
    });
  });

  group('figure resolver', () {
    test('has() is false for every slug when nothing is bundled', () {
      for (final String slug in _slugs) {
        expect(WifiCallingDiagrams.has(slug), isFalse);
      }
    });

    test('path() follows the convention and has() reads the manifest', () {
      expect(
        WifiCallingDiagrams.path('f4-emergency-call'),
        'assets/tool-diagrams/wifi-calling/f4-emergency-call.svg',
      );
      WifiCallingDiagrams.debugSetBundled(<String>{
        WifiCallingDiagrams.path('f4-emergency-call'),
      });
      expect(WifiCallingDiagrams.has('f4-emergency-call'), isTrue);
      expect(WifiCallingDiagrams.has('f1-two-roads'), isFalse);
    });
  });

  for (final bool light in <bool>[false, true]) {
    final String mode = light ? 'light' : 'dark';

    group('screen ($mode)', () {
      testWidgets('renders the title and the first section', (tester) async {
        await tester.pumpWidget(_harness(light: light));
        await tester.pump();
        expect(find.text('Wi-Fi Calling, Explained'), findsOneWidget);
        expect(find.text('The short answer'), findsOneWidget);
        expect(
          find.textContaining('Wi-Fi Calling is not an app. It is your own'),
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
    testWidgets("the unapproved Keith's notes are left out, and no page "
        'pointer survives', (tester) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      final String all = await _allText(tester);
      // Sanity: the collector really walked the whole lesson.
      expect(all, contains('Where these facts come from'));
      expect(all, contains('About this guide'));
      expect(all, isNot(contains("Keith's note")));
      expect(all, isNot(contains("the drop that isn't your carrier's fault")));
      expect(all, isNot(contains('the emergency trap')));
      expect(all, isNot(contains('It is usually the Wi-Fi.')));
      expect(RegExp(r'\b[Pp]age \d').hasMatch(all), isFalse);
    });

    testWidgets('the emergency table renders verbatim, each verdict with its '
        'icon', (tester) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      final Finder vodafone = find.textContaining(
        'The phone will try "a normal mobile network only.',
      );
      await _scrollTo(tester, vodafone);
      expect(vodafone, findsOneWidget);
      // Red row: a block icon sits beside it.
      final Finder row = find.ancestor(
        of: vodafone,
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: row.first, matching: find.byIcon(Icons.block)),
        findsOneWidget,
      );
      final Finder ee = find.textContaining(
        'Works. "We will try to send them your location',
      );
      await _scrollTo(tester, ee);
      expect(
        find.descendant(
          of: find.ancestor(of: ee, matching: find.byType(Row)).first,
          matching: find.byIcon(Icons.error_outline),
        ),
        findsOneWidget,
      );
    });

    testWidgets('menu paths render without their markup characters', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      final Finder path = find.textContaining(
        'Open Settings › Cellular. If you have more than one line',
      );
      await _scrollTo(tester, path);
      expect(path, findsOneWidget);
      final String shown = tester.widget<Text>(path).textSpan!.toPlainText();
      expect(shown.contains('`'), isFalse);
      expect(shown.contains('**'), isFalse);
    });

    testWidgets('each checklist ticks on its own', (tester) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      Future<Finder> box(String label) async {
        final Finder item = find.text(label);
        await _scrollTo(tester, item);
        await tester.ensureVisible(item);
        await tester.pumpAndSettle();
        return find.ancestor(of: item, matching: find.byType(CheckboxListTile));
      }

      const String home = 'The emergency address is your current address';
      const String trip =
          "You know the local emergency number where you're going";
      final Finder homeBox = await box(home);
      expect(tester.widget<CheckboxListTile>(homeBox).value, isFalse);
      await tester.tap(find.text(home));
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(homeBox).value, isTrue);

      final Finder tripBox = await box(trip);
      expect(tester.widget<CheckboxListTile>(tripBox).value, isFalse);
      await tester.tap(find.text(trip));
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(tripBox).value, isTrue);
      await tester.tap(find.text(trip));
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(tripBox).value, isFalse);
    });
  });

  group('figure band', () {
    testWidgets('renders nothing for a slug that is not bundled, and the '
        'caption still reads', (tester) async {
      await tester.pumpWidget(_harness(light: false));
      await tester.pump();
      expect(
        find.byKey(
          const ValueKey<String>('wifi-calling-figure-cover-two-roads'),
        ),
        findsNothing,
      );
      final Finder caption = find.textContaining(
        'Both roads end at the same carrier calling system',
      );
      await _scrollTo(tester, caption);
      expect(caption, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('wifi-calling-figure-f1-two-roads')),
        findsNothing,
      );
    });

    for (final bool light in <bool>[false, true]) {
      testWidgets('renders a band for a bundled slug (light: $light)', (
        tester,
      ) async {
        WifiCallingDiagrams.debugSetBundled(<String>{
          WifiCallingDiagrams.path('f1-two-roads'),
        });
        await tester.pumpWidget(_harness(light: light));
        await tester.pump();
        final Finder band = find.byKey(
          const ValueKey<String>('wifi-calling-figure-f1-two-roads'),
        );
        await _scrollTo(tester, band);
        expect(band, findsOneWidget);
        expect(
          find.byKey(
            const ValueKey<String>('wifi-calling-figure-f2-when-wifi'),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
