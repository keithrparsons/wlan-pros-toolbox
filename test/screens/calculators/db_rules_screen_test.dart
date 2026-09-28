// Screen tests for Decibels in Your Head, the Rules of 3 and 10 (db-rules):
// registration (catalog, route, large-screen gate, help, keywords, icon),
// the slider and the rule buttons, the readouts, predict-then-reveal, the two
// tools it points to, and clean rendering on phone, tablet and desktop in
// both themes.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/db_rules_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/db_rules_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/db_rules_painter.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/db_rules_parts.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/db_rules_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/db_rules_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/large_screen_gate.dart';

Future<DbRulesController> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const DbRulesScreen(),
      routes: <String, WidgetBuilder>{
        AppRouter.dbmWatt: (_) => const Scaffold(body: Text('DBMW')),
        AppRouter.dbReference: (_) => const Scaffold(body: Text('DBREF')),
      },
    ),
  );
  await tester.pumpAndSettle();
  return tester.widget<DbRulesStage>(find.byType(DbRulesStage)).controller;
}

Map<String, dynamic> _help() =>
    ((jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                as Map<String, dynamic>)['tools']
            as Map<String, dynamic>)[kDbRulesToolId]
        as Map<String, dynamic>;

String _helpText() {
  final Map<String, dynamic> h = _help();
  return <String>[
    h['purpose'] as String,
    h['whyHere'] as String,
    ...(h['howToUse'] as List<dynamic>).cast<String>(),
    ...(h['inputs'] as List<dynamic>).map(jsonEncode),
    h['algorithm'] as String,
    h['example'] as String,
    ...(h['fieldNotes'] as List<dynamic>).cast<String>(),
    h['source'] as String,
  ].join('\n');
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

DbRulesPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(DbRulesStage),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((CustomPaint p) => p.painter)
    .whereType<DbRulesPainter>()
    .single;

void main() {
  group('registration', () {
    test('catalog: Wi-Fi Classroom, first on RF and Propagation, live, '
        'routed, with an icon', () {
      final ToolCategory cls = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == kWifiClassroomCategoryId,
      );
      final List<ToolEntry> shelf = cls.tools
          .where((ToolEntry t) => t.subgroup == 'RF and Propagation')
          .toList();
      final ToolEntry e = shelf.first;
      expect(e.id, kDbRulesToolId);
      expect(kDbRulesToolId, 'db-rules');
      expect(e.title, kDbRulesTitle);
      expect(kWifiClassroomSimulatorSubgroups, contains(e.subgroup));
      expect(e.isLive, isTrue);
      expect(e.routeName, AppRouter.dbRules);
      expect(AppRouter.routes[AppRouter.dbRules], isNotNull);
      final File icon = File('assets/tool-icons/db-rules.svg');
      expect(icon.existsSync(), isTrue);
      expect(
        icon.readAsStringSync(),
        allOf(
          contains('viewBox="0 0 24 24"'),
          contains('currentColor'),
          isNot(contains('#')),
        ),
      );
    });

    testWidgets('the router puts the large-screen notice in front of it', (
      WidgetTester tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      );
      final Widget w = AppRouter.routes[AppRouter.dbRules]!(ctx);
      expect(w, isA<LargeScreenGate>());
      expect((w as LargeScreenGate).toolTitle, kDbRulesTitle);
    });

    test('keywords carry the words a student types', () {
      expect(
        kToolKeywords[kDbRulesToolId],
        containsAll(<String>[
          'decibel',
          'rule of 3',
          'rule of 10',
          'dbm to mw',
          'wi-fi classroom',
        ]),
      );
    });

    test('help: acronyms spelled out at first use, about double for 1.995, '
        'points to the dBm / Watt Converter and dB Reference, Present and the '
        'keys', () {
      final Map<String, dynamic> h = _help();
      expect(h['category'], 'Wireless Classroom');
      final String all = _helpText();
      for (final (String short, String long) in <(String, String)>[
        ('dB', 'decibel'),
        ('dBm', 'decibels relative to one milliwatt'),
        ('CWNA', 'certified wireless network administrator'),
        ('pW', 'trillionths of a watt'),
      ]) {
        final int first = all.indexOf(short);
        expect(first, greaterThanOrEqualTo(0), reason: short);
        expect(
          all.substring(first, first + short.length + 45).toLowerCase(),
          contains(long),
          reason: short,
        );
      }
      expect(all, contains('1.995'));
      expect(all, contains('about double'));
      expect(all, contains('dBm / Watt Converter'));
      expect(all, contains('dB Reference'));
      expect(all, contains('Predict, then reveal'));
      expect(all, contains('Present opens'));
      for (final String key in <String>[
        'Up and Down',
        'Right adds 3 dB',
        'Left takes 3 dB away',
        'Page Up and Page Down',
        'Space',
        'P reveals',
        'R resets',
        'Esc',
      ]) {
        expect(all, contains(key));
      }
      expect(
        (h['fieldNotes'] as List<dynamic>).cast<String>(),
        contains(
          'The Wireless Classroom is designed for tablets and computers, and on '
          'a phone some views are cramped.',
        ),
      );
    });
  });

  testWidgets('opens at the reference: -70 dBm, the same power, no steps', (
    WidgetTester tester,
  ) async {
    final DbRulesController k = await _pump(tester);
    expect(k.dbm, -70);
    expect(find.text('1x, the same power'), findsOneWidget);
    expect(find.textContaining('the same power'), findsWidgets);
    expect(find.textContaining('No steps'), findsOneWidget);
    expect(_painter(tester).dbm, -70);
  });

  testWidgets('+3 dB reads 1.995x, about double, 199.5 pW against 100.0 pW', (
    WidgetTester tester,
  ) async {
    final DbRulesController k = await _pump(tester);
    await _tap(tester, find.text('+3 dB'));
    expect(k.dbm, -67);
    expect(find.text('199.5 pW'), findsOneWidget);
    expect(find.text('100.0 pW'), findsOneWidget);
    expect(find.text('1.995x, about double the power'), findsOneWidget);
    expect(find.text('+3 dB: x2 = 2x'), findsOneWidget);
    expect(_painter(tester).dbm, -67);
  });

  testWidgets('+10 dB is exactly ten times; +1 dB shows the rules path', (
    WidgetTester tester,
  ) async {
    final DbRulesController k = await _pump(tester);
    await _tap(tester, find.text('+10 dB'));
    expect(k.dbm, -60);
    expect(find.text('10.0x, exactly ten times the power'), findsOneWidget);
    k.setDbm(-69);
    await tester.pumpAndSettle();
    expect(find.text('+10 -3 -3 -3 dB: x10 /2 /2 /2 = 1.25x'), findsOneWidget);
    expect(find.text('1.259x'), findsWidgets);
  });

  testWidgets('a rule step that would leave the range is turned off', (
    WidgetTester tester,
  ) async {
    final DbRulesController k = await _pump(tester);
    k.setDbm(-62);
    await tester.pumpAndSettle();
    OutlinedButton b(String t) => tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text(t),
        matching: find.byWidgetPredicate((Widget w) => w is OutlinedButton),
      ),
    );
    expect(b('+3 dB').onPressed, isNull);
    expect(b('+10 dB').onPressed, isNull);
    expect(b('-3 dB').onPressed, isNotNull);
    expect(b('-10 dB').onPressed, isNotNull);
  });

  testWidgets('the slider moves the level in whole dB within -80 to -60', (
    WidgetTester tester,
  ) async {
    final DbRulesController k = await _pump(tester);
    final Slider s = tester.widget<Slider>(find.byType(Slider));
    expect(s.min, -80);
    expect(s.max, -60);
    expect(s.divisions, 20);
    s.onChanged!(-73.4);
    await tester.pumpAndSettle();
    expect(k.dbm, -73);
    k.setDbm(-200);
    expect(k.dbm, -80);
  });

  testWidgets('predict, then reveal, then show -67 against -70', (
    WidgetTester tester,
  ) async {
    final DbRulesController k = await _pump(tester);
    expect(find.text(DbRulesPredict.question), findsOneWidget);
    expect(find.text(DbRulesPredict.answer), findsNothing);
    await _tap(tester, find.text('Reveal the answer'));
    expect(k.revealed, isTrue);
    expect(find.text(DbRulesPredict.answer), findsOneWidget);
    await _tap(tester, find.text('Show -67 dBm against -70 dBm'));
    expect(k.dbm, -67);
    final TextButton again = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Show -67 dBm against -70 dBm'),
        matching: find.byWidgetPredicate((Widget w) => w is TextButton),
      ),
    );
    expect(again.onPressed, isNull, reason: 'already showing');
    await _tap(tester, find.text('Hide the answer'));
    expect(find.text(DbRulesPredict.answer), findsNothing);
  });

  testWidgets('the explainer opens the dBm / Watt Converter and dB Reference', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    for (final (String label, String page) in <(String, String)>[
      ('Open dBm / Watt Converter', 'DBMW'),
      ('Open dB Reference', 'DBREF'),
    ]) {
      await _tap(tester, find.text(label));
      expect(find.text(page), findsOneWidget);
      Navigator.of(tester.element(find.text(page))).pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Reset returns to -70 dBm and hides the answer', (
    WidgetTester tester,
  ) async {
    final DbRulesController k = await _pump(tester);
    k
      ..setDbm(-61)
      ..setRevealed(true);
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Reset'));
    expect(k.dbm, -70);
    expect(k.revealed, isFalse);
  });

  testWidgets('the copy payload carries the levels, the ratio and the path', (
    WidgetTester tester,
  ) async {
    final DbRulesController k = await _pump(tester);
    k.setDbm(-63);
    final String t = k.copyText();
    expect(t, contains('-63 dBm'));
    expect(t, contains('+7 dB: 5.012x the power'));
    expect(t, contains('+10 -3 dB: x10 /2 = 5x'));
    expect(t, contains('exact 5.012x'));
  });

  testWidgets('stage and controls are separate widgets', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    expect(find.byType(DbRulesStage), findsOneWidget);
    expect(find.byType(DbRulesControls), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DbRulesStage),
        matching: find.byType(DbRulesControls),
      ),
      findsNothing,
    );
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final Size size in <Size>[
      const Size(390, 844),
      const Size(768, 1024),
      const Size(1280, 900),
    ]) {
      testWidgets('$name theme at ${size.width.toInt()} wide renders cleanly '
          'across the range', (WidgetTester tester) async {
        final DbRulesController k = await _pump(
          tester,
          theme: theme(),
          size: size,
        );
        k.setRevealed(true);
        for (int d = -80; d <= -60; d++) {
          k.setDbm(d);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$d');
        }
      });
    }
  }
}
