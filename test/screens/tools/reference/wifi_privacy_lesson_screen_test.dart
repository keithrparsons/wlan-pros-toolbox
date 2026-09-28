// Wi-Fi Privacy Myths Guided Lesson: wiring, rendering in both themes, both
// controls driving their stages, Predict then reveal, and no OS names on
// screen. The model's teaching claims are pinned separately in
// test/services/wifi_lab/wifi_privacy_model_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/data/content_type.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/wifi_privacy_lesson_screen.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lesson_parts.dart'
    show LessonSection;
import 'package:wlan_pros_toolbox/theme/app_color_scheme.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/lesson/lesson.dart'
    show LessonBlockRef, LessonMythView, lessonMythKey;
import 'package:wlan_pros_toolbox/widgets/app_toggle.dart';

const List<String> _sectionTitles = <String>[
  'The short answer',
  "Your phone's private Wi-Fi address",
  'Try it: what the routers record',
  'Predict, then reveal',
  'Why MAC filtering keeps no one out',
  'Hiding the network name',
  'Try it: hide the name',
  'Three things people get wrong',
  'Where these facts come from',
];

Widget _harness({bool light = false}) => MaterialApp(
  theme: light ? AppTheme.light() : AppTheme.dark(),
  home: const WifiPrivacyLessonScreen(),
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

Future<void> _tapSegment(
  WidgetTester tester,
  String toggleLabel,
  String seg,
) async {
  final Finder f = find.descendant(
    of: find.byWidgetPredicate(
      (Widget w) => w is AppToggle && w.label == toggleLabel,
    ),
    matching: find.text(seg),
  );
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pump();
}

ToolEntry _entry() => kToolCategories
    .expand((ToolCategory c) => c.tools)
    .firstWhere((ToolEntry t) => t.id == 'wifi-privacy-myths');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('catalog + route + keyword + help wiring', () {
    test('a live Guided Lesson in the Wi-Fi Classroom', () {
      final ToolEntry e = _entry();
      expect(e.title, 'Wi-Fi Privacy Myths');
      expect(e.routeName, '/tools/wifi-privacy-myths');
      expect(e.isLive, isTrue);
      expect(e.subgroup, 'Guided Lessons');
      final ToolCategory cat = kToolCategories.firstWhere(
        (ToolCategory c) =>
            c.tools.any((ToolEntry t) => t.id == 'wifi-privacy-myths'),
      );
      expect(cat.id, 'wifi-classroom');
      expect(contentTypeFor(e, cat.id), ContentType.guide);
    });

    test('route, keywords and help entry', () async {
      expect(AppRouter.routes.containsKey(AppRouter.wifiPrivacyMyths), isTrue);
      expect(kWifiPrivacyMythsToolId, 'wifi-privacy-myths');
      expect(
        kToolKeywords['wifi-privacy-myths'],
        containsAll(<String>[
          'mac filtering',
          'hidden ssid',
          'private address',
        ]),
      );
      final ToolHelpStore store = ToolHelpStore.fromJson(
        await rootBundle.loadString('assets/help/tool_help.json'),
      );
      expect(store.forId('wifi-privacy-myths')?.name, 'Wi-Fi Privacy Myths');
    });
  });

  for (final bool light in <bool>[false, true]) {
    testWidgets('every section renders (${light ? 'light' : 'dark'})', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(light: light));
      await tester.pump();
      for (final String t in _sectionTitles) {
        await _scrollTo(tester, find.text(t));
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('part 1: the address setting drives the three scenes', (
    tester,
  ) async {
    await _size(tester, 1024, 3000);
    await tester.pumpWidget(_harness());
    await tester.pump();

    // Off: the documentation-range hardware address everywhere.
    expect(find.text('00:00:5E:00:53:1A'), findsNWidgets(4));
    expect(find.text('Can be matched'), findsNWidgets(2));
    expect(find.text('Let in'), findsOneWidget);

    await _tapSegment(tester, 'Private Wi-Fi address', 'Fixed');
    expect(find.text('00:00:5E:00:53:1A'), findsNothing);
    expect(find.text("Can't be matched"), findsOneWidget);
    expect(find.text('Can be matched'), findsOneWidget);
    expect(find.text('Let in'), findsOneWidget);

    await _tapSegment(tester, 'Private Wi-Fi address', 'Rotating');
    expect(find.text("Can't be matched"), findsNWidgets(2));
    expect(find.text('Turned away'), findsOneWidget);
    expect(find.textContaining('every two weeks'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('part 2: hiding the name moves it into the probes', (
    tester,
  ) async {
    await _size(tester, 1024, 3000);
    await tester.pumpWidget(_harness());
    await tester.pump();
    await _scrollTo(tester, find.text('Try it: hide the name'));
    await tester.pump();
    expect(find.text('Network name: HomeNet'), findsOneWidget);
    expect(find.text('"Any networks here?"'), findsNWidgets(3));

    await _tapSegment(tester, 'Hide the network name', 'On');
    expect(find.text('Network name: (blank)'), findsOneWidget);
    expect(find.text('"Is HomeNet here?"'), findsNWidgets(3));
    expect(find.text('Names your network'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('predict, then reveal; Show me on Fixed sets the control', (
    tester,
  ) async {
    await _size(tester, 1024, 3000);
    await tester.pumpWidget(_harness());
    await tester.pump();
    final Finder reveal = find.text('Reveal the answer');
    await _scrollTo(tester, reveal);
    await tester.tap(reveal);
    await tester.pump();
    expect(find.textContaining("The cafe can't match your phone"), findsOne);
    await tester.ensureVisible(find.text('Show me on Fixed'));
    await tester.tap(find.text('Show me on Fixed'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.textContaining('Your phone makes up a different address'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('Your phone makes up a different address'),
      findsOne,
    );
  });

  testWidgets('no OS or phone-maker names above the Sources section', (
    tester,
  ) async {
    await _size(tester, 1024, 8000);
    await tester.pumpWidget(_harness());
    await tester.pump();
    final List<String> shown = <String>[
      for (final Element e in find.byType(RichText).evaluate())
        (e.widget as RichText).text.toPlainText(),
    ];
    final int sources = shown.indexWhere(
      (String s) => s.startsWith('Checked 27 September 2026'),
    );
    expect(sources, greaterThan(0));
    for (final String s in shown.take(sources)) {
      for (final String name in <String>[
        'Apple',
        'iPhone',
        'iOS',
        'Android',
        'Google',
        'Samsung',
        'Windows',
      ]) {
        expect(s.contains(name), isFalse, reason: '"$name" in: $s');
      }
    }
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
      'Addresses cross the air unencrypted',
      findRichText: true,
    );
    expect(fact, findsNothing);
    final Finder reveal = find.byKey(lessonMythKey(const LessonBlockRef(8, 0)));
    await tester.ensureVisible(reveal);
    await tester.pumpAndSettle();
    await tester.tap(reveal);
    await tester.pumpAndSettle();
    expect(fact, findsOneWidget);
  });
}
