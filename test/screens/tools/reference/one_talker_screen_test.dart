// One Talker per Channel: wiring + screen tests (spec 48, "Done means" 2).
//
// Guards:
//  (a) the catalog / route / keyword / help wiring for `one-talker` (Wi-Fi
//      Classroom, Guided Lessons shelf, guide content type, ungated);
//  (b) every section renders in dark and light, the walkie-talkie analogy and
//      the rule scoped to one channel are on screen, and the banned wording
//      (a microphone meeting, a peace pipe, "join", any outside lab) is not,
//      on screen, in the help entry or in the Field Manual entry;
//  (c) the stage: plus and minus change the bars, the second access point
//      makes one waiting line or two, the slow device takes 57%;
//  (d) phone widths 360 and 390, both themes, fullest state: no overflow and
//      nothing painted past the right edge (no sideways scroll).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/data/content_type.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/one_talker_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/one_talker_parts.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/one_talker_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/one_talker_stage.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_toggle.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/large_screen_gate.dart';

const List<String> _sectionTitles = <String>[
  'The short answer',
  'Like a walkie-talkie',
  'Try it: add devices',
  'Two access points: one channel or two',
  'One slow talker',
  'What you can do about it',
  'Next',
  'Where these facts come from',
];

/// Wording the lesson must never use (Keith's rulings, 2026-09-29).
final RegExp _banned = RegExp(
  r'microphone|peace pipe|tepee|\bjoin(s|ed|ing)?\b|SIAM|Semfio|\bEd\b',
  caseSensitive: false,
);

const double _tall = 6400;

Widget _harness({required bool light}) => MaterialApp(
  theme: light ? AppTheme.light() : AppTheme.dark(),
  home: const OneTalkerScreen(),
);

ToolEntry _entry() => kToolCategories
    .expand((ToolCategory c) => c.tools)
    .firstWhere((ToolEntry t) => t.id == 'one-talker');

/// Renders the whole lesson at [width] on a tall surface, so the ListView
/// builds every section.
Future<OneTalkerController> _pumpTall(
  WidgetTester tester, {
  required double width,
  bool light = false,
}) async {
  tester.view.physicalSize = Size(width, _tall);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_harness(light: light));
  await tester.pumpAndSettle();
  return tester.widget<OneTalkerStage>(find.byType(OneTalkerStage)).controller;
}

List<String> _allText(WidgetTester tester) => <String>[
  for (final RichText r in tester.widgetList<RichText>(find.byType(RichText)))
    r.text.toPlainText(),
];

/// A button by its label (the prose draws UI names as chips too).
Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((Widget w) => w is ButtonStyleButton),
);

Finder _segment(String label) => find.descendant(
  of: find.byWidgetPredicate((Widget w) => w is AppToggle),
  matching: find.text(label),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('catalog + route + keyword + help wiring', () {
    test('the id is a live, ungated Guided Lesson in Wi-Fi Classroom', () {
      final ToolEntry entry = _entry();
      expect(entry.title, kOneTalkerTitle);
      expect(entry.routeName, '/tools/one-talker');
      expect(entry.isLive, isTrue);
      expect(entry.subgroup, 'Guided Lessons');
      final ToolCategory cat = kToolCategories.firstWhere(
        (ToolCategory c) => c.tools.any((ToolEntry t) => t.id == 'one-talker'),
      );
      expect(cat.id, 'wifi-classroom');
      expect(contentTypeFor(entry, cat.id), ContentType.guide);
      expect(
        wifiLabTools().map((ToolEntry t) => t.id),
        isNot(contains('one-talker')),
        reason: 'a lesson is readable on a phone, never gated',
      );
    });

    test('the route is registered and follows /tools/<id>', () {
      expect(AppRouter.routes.containsKey(AppRouter.oneTalker), isTrue);
      expect(AppRouter.oneTalker, '/tools/one-talker');
      expect(kOneTalkerToolId, 'one-talker');
    });

    test('search keywords are registered', () {
      expect(
        kToolKeywords['one-talker'],
        containsAll(<String>['airtime', 'walkie-talkie', 'same channel']),
      );
    });

    test('the help and Field Manual entries exist and use none of the '
        'banned wording', () async {
      final String raw = await rootBundle.loadString(
        'assets/help/tool_help.json',
      );
      final ToolHelpStore store = ToolHelpStore.fromJson(raw);
      expect(store.forId('one-talker')?.name, kOneTalkerTitle);
      final int start = raw.indexOf('"one-talker": {');
      final String entry = raw.substring(start, raw.indexOf('\n    },', start));
      expect(_banned.firstMatch(entry)?.group(0), isNull);
      expect(entry, contains('walkie-talkie'));

      final String md = await rootBundle.loadString(
        'assets/guides/field-manual.md',
      );
      final int at = md.indexOf('### One Talker per Channel');
      expect(at, greaterThan(0));
      final String section = md.substring(at, md.indexOf('\n### ', at + 5));
      expect(_banned.firstMatch(section)?.group(0), isNull);
    });
  });

  for (final bool light in <bool>[false, true]) {
    testWidgets('every section renders, the analogy and the scoped rule are '
        'there, and no banned wording (${light ? 'light' : 'dark'})', (
      WidgetTester tester,
    ) async {
      await _pumpTall(tester, width: 1024, light: light);
      for (final String title in _sectionTitles) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      final String all = _allText(tester).join('\n');
      expect(all, contains('Think of a pair of walkie-talkies'));
      expect(all, contains('say "over"'));
      expect(all, contains(kOneTalkerRule));
      expect(all, contains('OFDMA and $kMuMimo'));
      expect(all, contains('associates'));
      expect(_banned.firstMatch(all)?.group(0), isNull);
      expect(find.byType(WalkieTalkiePair), findsOneWidget);
      expect(find.bySemanticsLabel(WalkieTalkiePair.semantics), findsOneWidget);
      // The three links resolve to live tools.
      for (final String id in <String>[
        'airtime-fairness',
        'channel-planner',
        'medium-access-simulator',
      ]) {
        expect(find.byKey(ValueKey<String>('lesson-link:$id')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('plus and minus change the bars; minus stops at 1, plus at 12', (
    WidgetTester tester,
  ) async {
    final OneTalkerController k = await _pumpTall(tester, width: 390);
    expect(find.text('25%'), findsNWidgets(4));
    await tester.tap(find.byTooltip('Add a device to access point 1'));
    await tester.pumpAndSettle();
    expect(k.config.clientsA, 5);
    expect(find.text('20%'), findsNWidgets(5));
    expect(
      find.textContaining('5 devices take turns. Each gets 1/5'),
      findsOneWidget,
    );
    for (int i = 0; i < 10; i++) {
      await tester.tap(find.byTooltip('Remove a device from access point 1'));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(k.config.clientsA, 1);
    expect(find.text('100%'), findsOneWidget);
    expect(find.textContaining('no one to wait for'), findsOneWidget);
    final IconButton minus = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.remove_rounded),
    );
    expect(minus.onPressed, isNull, reason: 'minus disabled at 1');
    k.shiftClientsA(40);
    await tester.pumpAndSettle();
    expect(k.config.clientsA, 12);
    expect(k.canAddA, isFalse);
    expect(find.text('8%'), findsNWidgets(12));
  });

  testWidgets('second access point: one waiting line, or two', (
    WidgetTester tester,
  ) async {
    final OneTalkerController k = await _pumpTall(tester, width: 390);
    await tester.tap(_segment('Same'));
    await tester.pumpAndSettle();
    expect(k.config.secondAp, SecondAp.sameChannel);
    expect(find.text('14%'), findsNWidgets(7));
    expect(
      find.text('Same channel: one waiting line for both access points.'),
      findsOneWidget,
    );
    expect(find.text('Devices on access point 2'), findsOneWidget);

    await tester.tap(_segment('Other'));
    await tester.pumpAndSettle();
    expect(find.text('25%'), findsNWidgets(4));
    expect(find.text('33%'), findsNWidgets(3));
    expect(find.text('Channel 149 time'), findsOneWidget);
    expect(
      find.textContaining('two devices can transmit at once'),
      findsOneWidget,
    );

    // Next turn: one talker per channel, so two talking lines.
    await tester.tap(_button('Next turn'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Channel 36, talking now: B.'), findsOneWidget);
    expect(find.textContaining('Channel 149, talking now: F.'), findsOneWidget);

    await tester.tap(_segment('None'));
    await tester.pumpAndSettle();
    expect(find.text('Devices on access point 2'), findsNothing);
  });

  testWidgets('the slow device: equal turns, 57% of the time', (
    WidgetTester tester,
  ) async {
    final OneTalkerController k = await _pumpTall(tester, width: 390);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(k.config.slowTalker, isTrue);
    expect(find.text('57%'), findsOneWidget);
    expect(find.text('14%'), findsNWidgets(3));
    expect(find.text('slow'), findsOneWidget);
    expect(
      find.textContaining('slow device A uses 57% of the time'),
      findsOneWidget,
    );
    // Reset brings back the opening scene and disables itself.
    await tester.tap(_button('Reset'));
    await tester.pumpAndSettle();
    expect(k.isDefault, isTrue);
    expect(find.text('25%'), findsNWidgets(4));
  });

  for (final double width in <double>[360, 390]) {
    for (final bool light in <bool>[false, true]) {
      testWidgets('phone ${width.toInt()} ${light ? 'light' : 'dark'}: no '
          'overflow and nothing past the right edge, fullest state', (
        WidgetTester tester,
      ) async {
        final OneTalkerController k = await _pumpTall(
          tester,
          width: width,
          light: light,
        );
        for (final SecondAp ap in SecondAp.values) {
          k
            ..setSecondAp(ap)
            ..shiftClientsA(20)
            ..shiftClientsB(20)
            ..setSlowTalker(true)
            ..nextTurn();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$ap');
          for (final Element e in find.byType(RichText).evaluate()) {
            final RenderBox box = e.renderObject! as RenderBox;
            if (!box.hasSize) continue;
            final double right = box
                .localToGlobal(Offset(box.size.width, 0))
                .dx;
            expect(
              right,
              lessThanOrEqualTo(width + 0.5),
              reason: '${(e.widget as RichText).text.toPlainText()} at $ap',
            );
          }
          // No horizontal scrollable that can move.
          for (final ScrollableState s in tester.stateList<ScrollableState>(
            find.byType(Scrollable),
          )) {
            if (s.widget.axisDirection == AxisDirection.right ||
                s.widget.axisDirection == AxisDirection.left) {
              expect(s.position.maxScrollExtent, 0);
            }
          }
        }
      });
    }
  }
}
