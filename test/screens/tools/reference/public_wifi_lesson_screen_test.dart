// Public Wi-Fi Guided Lesson: wiring, rendering in both themes and at phone
// and desktop widths, the control driving the rows, and Predict, then reveal.
// The model's teaching claims are pinned separately in
// test/services/wifi_lab/public_wifi_model_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/data/content_type.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/public_wifi_lesson_screen.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lesson_parts.dart'
    show LessonSection;
import 'package:wlan_pros_toolbox/theme/app_color_scheme.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/lesson/lesson.dart'
    show LessonBlockRef, LessonMythView, lessonMythKey;
import 'package:wlan_pros_toolbox/widgets/app_select.dart';
import 'package:wlan_pros_toolbox/widgets/app_toggle.dart';

const List<String> _sectionTitles = <String>[
  'The short answer',
  'Try it: pick the network',
  'Predict, then reveal',
  'The four networks',
  'Three things people get wrong',
  'Where Wi-Fi encryption stops',
  'Where these facts come from',
];

Widget _harness({bool light = false}) => MaterialApp(
  theme: light ? AppTheme.light() : AppTheme.dark(),
  home: const PublicWifiLessonScreen(),
);

Future<void> _size(WidgetTester tester, double w, double h) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
}

ToolEntry _entry() => kToolCategories
    .expand((ToolCategory c) => c.tools)
    .firstWhere((ToolEntry t) => t.id == 'public-wifi');

Future<void> _tapSegment(WidgetTester tester, String label) async {
  final Finder f = find.descendant(
    of: find.byWidgetPredicate((Widget w) => w is AppToggle),
    matching: find.text(label),
  );
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('catalog + route + keyword + help wiring', () {
    test('a live Guided Lesson in the Wi-Fi Classroom', () {
      final ToolEntry e = _entry();
      expect(e.title, 'Public Wi-Fi');
      expect(e.routeName, '/tools/public-wifi');
      expect(e.isLive, isTrue);
      expect(e.subgroup, 'Guided Lessons');
      final ToolCategory cat = kToolCategories.firstWhere(
        (ToolCategory c) => c.tools.any((ToolEntry t) => t.id == 'public-wifi'),
      );
      expect(cat.id, 'wifi-classroom');
      expect(contentTypeFor(e, cat.id), ContentType.guide);
    });

    test('route, keywords and help entry', () async {
      expect(AppRouter.routes.containsKey(AppRouter.publicWifi), isTrue);
      expect(kPublicWifiToolId, 'public-wifi');
      expect(
        kToolKeywords['public-wifi'],
        containsAll(<String>['public wi-fi', 'enhanced open', 'wpa3']),
      );
      final ToolHelpStore store = ToolHelpStore.fromJson(
        await rootBundle.loadString('assets/help/tool_help.json'),
      );
      expect(store.forId('public-wifi')?.name, 'Public Wi-Fi');
    });
  });

  for (final bool light in <bool>[false, true]) {
    testWidgets('every section renders (${light ? 'light' : 'dark'})', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(light: light));
      await tester.pump();
      expect(find.text('Public Wi-Fi'), findsOneWidget);
      for (final String t in _sectionTitles) {
        await _scrollTo(tester, find.text(t));
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('phone width: a select, no overflow; desktop: a toggle', (
    tester,
  ) async {
    await _size(tester, 320, 800);
    await tester.pumpWidget(_harness());
    await tester.pump();
    await _scrollTo(tester, find.text('Network type'));
    expect(
      find.byWidgetPredicate((Widget w) => w is AppSelect),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await _size(tester, 1024, 900);
    await tester.pumpWidget(_harness());
    await tester.pump();
    await _scrollTo(tester, find.text('Network type'));
    expect(find.byWidgetPredicate((Widget w) => w is AppSelect), findsNothing);
    expect(find.text('Enhanced Open'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the control drives what the bystander can see', (tester) async {
    await _size(tester, 1024, 2400);
    await tester.pumpWidget(_harness());
    await tester.pump();

    // Open (the default): unencrypted traffic is readable, HTTPS sealed.
    expect(find.text('What the person next to you can see on Open'), findsOne);
    expect(find.text('Can read it'), findsOneWidget);
    expect(find.text('Sealed'), findsOneWidget);
    // Each row speaks its verdict in words, never color alone.
    expect(
      find.byWidgetPredicate(
        (Widget w) =>
            w is Semantics &&
            (w.properties.label ?? '').startsWith(
              'What you read and type on a secure site: Sealed.',
            ),
      ),
      findsOneWidget,
    );

    // The WPA2 / WPA3 choice is disabled until Password, and says why.
    expect(
      find.text('Pick Password to compare WPA2 and WPA3.'),
      findsOneWidget,
    );

    await _tapSegment(tester, 'Enhanced Open');
    expect(find.text('Can read it'), findsNothing);
    expect(find.text('Sealed'), findsNWidgets(3));
    expect(
      find.textContaining('Your network list still shows no lock'),
      findsOne,
    );

    await _tapSegment(tester, 'Password');
    expect(find.text('Pick Password to compare WPA2 and WPA3.'), findsNothing);
    expect(
      find.text('What the person next to you can see on WPA2-Personal'),
      findsOne,
    );
    // The guard: a shared password does not hide you on WPA2.
    expect(find.text('Can read it'), findsOneWidget);

    await _tapSegment(tester, 'WPA3');
    expect(
      find.text('What the person next to you can see on WPA3-Personal'),
      findsOne,
    );
    expect(find.text('Can read it'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('predict, then reveal; Show me on Open resets the control', (
    tester,
  ) async {
    await _size(tester, 1024, 2400);
    await tester.pumpWidget(_harness());
    await tester.pump();
    await _tapSegment(tester, 'Enhanced Open');
    expect(find.text('Can read it'), findsNothing);

    final Finder reveal = find.text('Reveal the answer');
    await _scrollTo(tester, reveal);
    await tester.tap(reveal);
    await tester.pump();
    expect(
      find.textContaining('Not your password and not your balance'),
      findsOne,
    );

    await tester.ensureVisible(find.text('Show me on Open'));
    await tester.tap(find.text('Show me on Open'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Can read it'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Can read it'), findsOneWidget);
  });

  testWidgets('no markup characters reach the screen', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();
    final Finder p = find.textContaining('HTTPS protects what you send');
    expect(p, findsOneWidget);
    final String shown = tester.widget<Text>(p).textSpan!.toPlainText();
    expect(shown.contains('**'), isFalse);
  });

  // GL-003 §12.10-2 (Keith, 2026-09-28): a Guided Lesson's myth is the
  // stacked pair, myth first and the fact revealed by a tap under it, with
  // no red, no amber and no fill. This lesson used the old red myth panel.
  testWidgets('myths are the stacked pair: no red, fact hidden until tapped', (
    tester,
  ) async {
    await _size(tester, 390, 844);
    await tester.pumpWidget(_harness(light: true));
    await tester.pumpAndSettle();
    final Finder title = find.text('Three things people get wrong');
    await _scrollTo(tester, title);
    final Finder section = find.ancestor(
      of: title,
      matching: find.byType(LessonSection),
    );
    expect(
      find.descendant(of: section, matching: find.byType(LessonMythView)),
      findsNWidgets(3),
    );
    final AppColorScheme c = AppColorScheme.light();
    final Set<Color> warm = <Color>{
      c.statusDanger,
      c.statusDangerFill,
      c.statusWarning,
      c.statusWarningFill,
    };
    for (final Container box in tester.widgetList<Container>(
      find.descendant(of: section, matching: find.byType(Container)),
    )) {
      final Decoration? d = box.decoration;
      final Color? fill = box.color ?? (d is BoxDecoration ? d.color : null);
      expect(warm.contains(fill), isFalse, reason: '$fill');
    }
    final Finder fact = find.textContaining(
      'The FTC says connecting through public Wi-Fi is usually',
      findRichText: true,
    );
    expect(fact, findsNothing);
    final Finder reveal = find.byKey(lessonMythKey(const LessonBlockRef(5, 0)));
    await tester.ensureVisible(reveal);
    await tester.pumpAndSettle();
    await tester.tap(reveal);
    await tester.pumpAndSettle();
    expect(fact, findsOneWidget);
  });
}
