// Widget tests for the Wi-Fi Classroom "Repeaters and Mesh Backhaul" screen
// (repeater-mesh). The math has its own tests (test/services/wifi_lab/
// repeater_mesh_model_test.dart); these check the screen: registration
// (catalog, route, help, keywords, icon), the defaults on screen, the
// backhaul modes, dragging a relay, predict-then-reveal, a hop with no link
// said in words, Play and Reset, stage and controls as separate widgets,
// the illustrative labels, acronyms spelled out in the help, and phone and
// desktop widths in both themes laying out with no overflow.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/repeater_mesh_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/repeater_mesh_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/repeater_mesh_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/repeater_mesh_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<RepeaterMeshController> _open(
  WidgetTester tester, {
  Size size = const Size(800, 4000),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final RepeaterMeshController c = RepeaterMeshController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: RepeaterMeshScreen(controller: c),
    ),
  );
  await tester.pump();
  return c;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
}

Map<String, dynamic> _help() =>
    ((jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                as Map<String, dynamic>)['tools']
            as Map<String, dynamic>)[kRepeaterMeshToolId]
        as Map<String, dynamic>;

void main() {
  group('registration', () {
    test('catalog: Wi-Fi Classroom, Network Design and Security, with its '
        'route', () {
      final ToolCategory cat = kToolCategories.firstWhere(
        (ToolCategory c) =>
            c.tools.any((ToolEntry e) => e.id == kRepeaterMeshToolId),
      );
      expect(cat.id, 'wifi-classroom');
      final ToolEntry t = cat.tools.firstWhere(
        (ToolEntry e) => e.id == kRepeaterMeshToolId,
      );
      expect(kRepeaterMeshToolId, 'repeater-mesh');
      expect(t.title, 'Repeaters and Mesh Backhaul');
      expect(t.subgroup, 'Network Design and Security');
      expect(t.routeName, '/tools/repeater-mesh');
      expect(AppRouter.repeaterMesh, t.routeName);
      expect(AppRouter.routes.containsKey(t.routeName), isTrue);
      // The id is used once in the whole catalog.
      expect(
        kToolCategories
            .expand((ToolCategory c) => c.tools)
            .where((ToolEntry e) => e.id == kRepeaterMeshToolId),
        hasLength(1),
      );
    });

    test('icon and keywords', () {
      expect(File('assets/tool-icons/repeater-mesh.svg').existsSync(), isTrue);
      final String svg = File(
        'assets/tool-icons/repeater-mesh.svg',
      ).readAsStringSync();
      expect(svg, contains('viewBox="0 0 24 24"'));
      expect(svg, contains('currentColor'));
      expect(svg, isNot(contains('#')));
      final List<String> words = kToolKeywords[kRepeaterMeshToolId]!;
      for (final String w in <String>[
        'repeater',
        'extender',
        'mesh',
        'backhaul',
        'relay',
        'multihop',
        'half throughput',
        'wireless backhaul',
      ]) {
        expect(words, contains(w), reason: w);
      }
    });

    test('help: spells out PHY at first use and says the formula is for one '
        'radio on one channel', () {
      final Map<String, dynamic> h = _help();
      expect(h['name'], 'Repeaters and Mesh Backhaul');
      expect(h['category'], 'Wireless Classroom');
      final String all = <String>[
        h['purpose'] as String,
        h['whyHere'] as String,
        ...(h['howToUse'] as List<dynamic>).cast<String>(),
        for (final dynamic i in h['inputs'] as List<dynamic>)
          '${(i as Map<String, dynamic>)['name']} ${i['unit']} ${i['range']}',
        h['algorithm'] as String,
        h['example'] as String,
        ...(h['fieldNotes'] as List<dynamic>).cast<String>(),
        h['source'] as String,
      ].join('\n');
      for (final (String short, String long) in <(String, String)>[
        ('PHY', 'PHY (physical layer)'),
        ('MCS', 'MCS (modulation and coding scheme'),
        ('EIRP', 'EIRP (equivalent isotropically radiated power)'),
      ]) {
        final int first = all.indexOf(RegExp('\\b$short\\b'));
        expect(first, greaterThanOrEqualTo(0), reason: short);
        expect(all.indexOf(long), first, reason: short);
      }
      expect(
        h['fieldNotes'] as List<dynamic>,
        contains(
          startsWith(
            'The formula 1/T = 1/T1 + 1/T2 is for one radio relaying on one '
            'channel.',
          ),
        ),
      );
      expect(h['whyHere'], contains('For one radio relaying on one channel'));
      // Present and the keys, in one line (spec 00).
      expect(
        (h['howToUse'] as List<dynamic>).last,
        allOf(
          contains('Present'),
          contains('Space'),
          contains('Up and Down'),
          contains('R resets'),
        ),
      );
      expect(all, contains('illustrative'));
    });
  });

  testWidgets('opens on the defaults: two equal hops give exactly half', (
    WidgetTester tester,
  ) async {
    final RepeaterMeshController c = await _open(tester);
    expect(find.text('Repeaters and Mesh Backhaul'), findsOneWidget);
    expect(find.byType(RepeaterMeshStage), findsOneWidget);
    expect(find.byType(RepeaterMeshControls), findsOneWidget);
    final RmResult r = c.result;
    expect(r.endToEndMbps, r.hops.first.throughputMbps / 2);
    expect(find.text('86.5 Mb/s'), findsWidgets);
    expect(find.text('43.2 Mb/s'), findsOneWidget);
    expect(find.text('2.0 times straight to the AP'), findsOneWidget);
    expect(find.text('-64.9 dBm, MCS 3, 172.9 Mb/s'), findsNWidgets(2));
    // Illustrative values are labeled so.
    expect(find.text('Efficiency (illustrative)'), findsOneWidget);
    expect(
      find.text('Forwarding delay per hop (illustrative)'),
      findsOneWidget,
    );
    expect(find.text(kRmAssumptions), findsOneWidget);
    expect(kRmAssumptions, contains('(illustrative)'));
  });

  testWidgets('dedicated backhaul gives the slower hop; wired gives the last '
      'hop', (WidgetTester tester) async {
    final RepeaterMeshController c = await _open(tester);
    c.backhaul = RmBackhaul.dedicated;
    await tester.pump();
    expect(find.text('172.9 Mb/s'), findsWidgets);
    expect(
      find.textContaining('Hop 1, own channel, busy 100%'),
      findsOneWidget,
    );
    c.backhaul = RmBackhaul.wired;
    await tester.pump();
    expect(find.text('cable'), findsOneWidget);
    expect(c.result.endToEndMbps, c.result.hops.last.throughputMbps);
  });

  testWidgets('dragging the relay toward the AP moves it and speeds the '
      'backhaul hop', (WidgetTester tester) async {
    final RepeaterMeshController c = await _open(tester);
    final double before = c.result.hops.first.link.phyMbps;
    final Finder corridor = find.descendant(
      of: find.byType(RepeaterMeshStage),
      matching: find.byType(CustomPaint),
    );
    final Rect box = tester.getRect(corridor.first);
    // The relay sits at 18 of 60 m; drag it left by a fifth of the width.
    final double pad = 28;
    final Offset relay = Offset(
      box.left + pad + (box.width - 2 * pad) * 18 / 60,
      box.center.dy,
    );
    await tester.dragFrom(relay, Offset(-box.width / 5, 0));
    await tester.pump();
    expect(c.config.relaysM.single, lessThan(18));
    expect(c.result.hops.first.link.phyMbps, greaterThan(before));
  });

  testWidgets('position sliders move a node from the keyboard side', (
    WidgetTester tester,
  ) async {
    final RepeaterMeshController c = await _open(tester);
    expect(find.text('Relay position'), findsOneWidget);
    expect(find.text('Client position'), findsOneWidget);
    c.relayCount = 3;
    await tester.pump();
    expect(find.text('Relay 3 position'), findsOneWidget);
    expect(c.config.relaysM, <double>[9, 18, 27]);
  });

  testWidgets('predict, then reveal hides the throughputs until Reveal', (
    WidgetTester tester,
  ) async {
    final RepeaterMeshController c = await _open(tester);
    c.relayCount = 2;
    await tester.pump();
    await _tap(tester, find.text('Ask the class'));
    expect(c.config, kRmQuestionConfig);
    expect(find.text(kRmQuestionText), findsOneWidget);
    expect(find.text('77.2 Mb/s'), findsNothing);
    expect(find.text('?'), findsWidgets);
    await _tap(tester, find.text(RmGuess.tooClose.label));
    await _tap(tester, find.text('Reveal'));
    expect(find.text('77.2 Mb/s'), findsWidgets);
    expect(
      find.text(
        'Straight to the AP: 86.5 Mb/s. Through the repeater: 77.2 Mb/s.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('The class picked "'), findsOneWidget);
    await _tap(tester, find.text('Done'));
    expect(find.text('Ask the class'), findsOneWidget);
  });

  testWidgets('a hop with no link says so in words', (
    WidgetTester tester,
  ) async {
    final RepeaterMeshController c = await _open(tester);
    c.moveNode(2, 60);
    c.moveNode(1, 55);
    await tester.pump();
    expect(c.result.broken, isTrue);
    expect(
      find.text('A hop has no link, so nothing gets through'),
      findsOneWidget,
    );
    expect(find.textContaining('no link'), findsWidgets);
  });

  testWidgets('Play runs the frames; Reset returns to the opening scene', (
    WidgetTester tester,
  ) async {
    final RepeaterMeshController c = await _open(tester);
    c.backhaul = RmBackhaul.wired;
    await tester.pump();
    await _tap(tester, find.text('Play the frames'));
    expect(c.playing, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(c.phase.value, closeTo(0.25, 0.02));
    // It loops rather than stopping.
    await tester.pump(const Duration(seconds: 4));
    expect(c.playing, isTrue);
    expect(c.phase.value, closeTo(0.25, 0.02));
    await _tap(tester, find.text('Pause'));
    expect(c.playing, isFalse);
    await _tap(tester, find.text('Reset'));
    expect(c.phase.value, 0);
    expect(c.config, RmConfig());
  });

  testWidgets('with reduced motion nothing plays by itself', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final RepeaterMeshController c = RepeaterMeshController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: RepeaterMeshScreen(controller: c),
        ),
      ),
    );
    await tester.pump();
    expect(c.reducedMotion, isTrue);
    c.ask();
    c.reveal();
    await tester.pump(const Duration(seconds: 2));
    expect(c.playing, isFalse);
    expect(c.phase.value, 0);
  });

  test('copy text carries every hop and the comparison', () {
    final RepeaterMeshController c = RepeaterMeshController();
    addTearDown(c.dispose);
    final String t = c.copyText();
    expect(
      t,
      contains('Hop 1, AP to Relay, 18 m: -64.9 dBm, MCS 3, 172.9 Mb/s'),
    );
    expect(t, contains('End to end: 86.5 Mb/s, delay 2 ms'));
    expect(t, contains('Straight to the AP from 36 m: 43.2 Mb/s, delay 1 ms'));
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final double width in <double>[320, 390, 1024]) {
      testWidgets('$name: ${width.toInt()} px lays out with no overflow', (
        WidgetTester tester,
      ) async {
        final RepeaterMeshController c = await _open(
          tester,
          size: Size(width, 5200),
          theme: theme(),
        );
        c.relayCount = 3;
        c.backhaul = RmBackhaul.dedicated;
        await tester.pump();
        expect(tester.takeException(), isNull);
        c.ask();
        await tester.pump();
        expect(tester.takeException(), isNull);
        final Iterable<Scrollable> horizontal = tester
            .widgetList<Scrollable>(find.byType(Scrollable))
            .where(
              (Scrollable s) =>
                  s.axisDirection == AxisDirection.right ||
                  s.axisDirection == AxisDirection.left,
            );
        expect(horizontal, isEmpty);
      });
    }
  }
}
