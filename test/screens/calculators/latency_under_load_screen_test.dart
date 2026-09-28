// Widget tests for the Wi-Fi Classroom "Why a Busy Line Lags" screen
// (latency-under-load). The math has its own tests (test/services/wifi_lab/
// latency_under_load_model_test.dart); these check the screen: registration
// (catalog, route, help, keywords, icon), the defaults on screen, the one
// switch and its visible change, the line picker, the playhead, Play and
// Reset, reduced motion, the illustrative and FCC labels, the links to the
// measuring tools, acronyms spelled out in the help, and phone and desktop
// widths in both themes laying out with no overflow.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/latency_under_load_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/latency_under_load_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/latency_under_load_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/latency_under_load_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<LatencyUnderLoadController> _open(
  WidgetTester tester, {
  Size size = const Size(800, 4000),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final LatencyUnderLoadController c = LatencyUnderLoadController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: LatencyUnderLoadScreen(controller: c),
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
            as Map<String, dynamic>)[kLatencyUnderLoadToolId]
        as Map<String, dynamic>;

void main() {
  group('registration', () {
    test('catalog: Wi-Fi Classroom, Network Design and Security, with its '
        'route', () {
      final ToolCategory cat = kToolCategories.firstWhere(
        (ToolCategory c) =>
            c.tools.any((ToolEntry e) => e.id == kLatencyUnderLoadToolId),
      );
      expect(cat.id, 'wifi-classroom');
      final ToolEntry t = cat.tools.firstWhere(
        (ToolEntry e) => e.id == kLatencyUnderLoadToolId,
      );
      expect(kLatencyUnderLoadToolId, 'latency-under-load');
      expect(t.title, 'Why a Busy Line Lags');
      expect(t.subgroup, 'Network Design and Security');
      expect(t.routeName, '/tools/latency-under-load');
      expect(AppRouter.latencyUnderLoad, t.routeName);
      expect(AppRouter.routes.containsKey(t.routeName), isTrue);
      expect(
        kToolCategories
            .expand((ToolCategory c) => c.tools)
            .where((ToolEntry e) => e.id == kLatencyUnderLoadToolId),
        hasLength(1),
      );
    });

    test('icon and keywords', () {
      final File icon = File('assets/tool-icons/latency-under-load.svg');
      expect(icon.existsSync(), isTrue);
      final String svg = icon.readAsStringSync();
      expect(svg, contains('viewBox="0 0 24 24"'));
      expect(svg, contains('currentColor'));
      expect(svg, isNot(contains('#')));
      final List<String> words = kToolKeywords[kLatencyUnderLoadToolId]!;
      for (final String w in <String>[
        'bufferbloat',
        'latency under load',
        'lag',
        'sqm',
        'smart queue management',
        'fq-codel',
      ]) {
        expect(words, contains(w), reason: w);
      }
    });

    test('help: acronyms spelled out, the SQM-on curve called illustrative, '
        'the measuring tools named, Present and its keys', () {
      final Map<String, dynamic> h = _help();
      expect(h['name'], 'Why a Busy Line Lags');
      expect(h['category'], 'Wireless Classroom');
      final String all = jsonEncode(h);
      for (final String spelled in <String>[
        'smart queue management (SQM)',
        'FCC (Federal Communications Commission)',
        'DSL (digital subscriber line)',
        'active queue management (AQM)',
        'FQ-CoDel (flow queue controlled delay)',
        'RFC: Request for Comments',
      ]) {
        expect(all, contains(spelled), reason: spelled);
      }
      final List<dynamic> notes = h['fieldNotes'] as List<dynamic>;
      expect(
        notes.any(
          (dynamic n) =>
              (n as String).startsWith('The SQM-on curve is illustrative'),
        ),
        isTrue,
      );
      expect(all, contains('Network Quality'));
      expect(all, contains('Test My Connection'));
      expect(all, contains('Present opens this simulator'));
      expect(all, contains('Left out:'));
      expect(all, isNot(contains('—')), reason: 'no em dashes');
    });
  });

  testWidgets('opens on cable, SQM off, the whole run drawn', (
    WidgetTester tester,
  ) async {
    final LatencyUnderLoadController c = await _open(tester);
    expect(c.config, const LulConfig());
    expect(c.timeS.value, kLulRunS);
    expect(c.playing, isFalse);
    expect(find.text('225 ms'), findsOneWidget);
    expect(find.text('18 ms'), findsWidgets);
    expect(find.text('FCC measured 12 ms to 24 ms'), findsOneWidget);
    expect(
      find.textContaining('FCC chart reading, approximate'),
      findsOneWidget,
    );
  });

  testWidgets('the one switch: SQM on drops the busy figure toward idle and '
      'says it is illustrative', (WidgetTester tester) async {
    final LatencyUnderLoadController c = await _open(tester);
    await _tap(tester, find.text('On'));
    expect(c.config.sqm, isTrue);
    expect(find.text('23 ms'), findsOneWidget);
    expect(find.text('225 ms'), findsNothing);
    expect(find.textContaining('1.3 times idle; illustrative'), findsOneWidget);
    expect(find.textContaining('SQM on is illustrative'), findsOneWidget);
    await _tap(tester, find.text('Off'));
    expect(c.config.sqm, isFalse);
    expect(find.text('225 ms'), findsOneWidget);
  });

  testWidgets('the line picker follows the FCC figures', (
    WidgetTester tester,
  ) async {
    final LatencyUnderLoadController c = await _open(tester);
    await _tap(tester, find.text('DSL'));
    expect(c.config.line, LulLine.dsl);
    expect(find.text('665 ms'), findsOneWidget);
    expect(find.text('FCC measured 23 ms to 34 ms'), findsOneWidget);
    expect(find.text(lulSourcesText(LulLine.dsl)), findsOneWidget);
    await _tap(tester, find.text('Fiber'));
    expect(find.text('30 ms'), findsOneWidget);
  });

  testWidgets('the playhead: before the upload the call is at idle, during '
      'it the queue picture says how long it waits', (
    WidgetTester tester,
  ) async {
    final LatencyUnderLoadController c = await _open(tester);
    c.seek(2);
    await tester.pump();
    expect(find.text('Line idle'), findsOneWidget);
    expect(find.text('Video call delay at 2.0 s'), findsOneWidget);
    c.seek(12);
    await tester.pump();
    expect(find.text('Upload running'), findsOneWidget);
    expect(find.textContaining('waits behind every upload'), findsOneWidget);
    c.sqm = true;
    await tester.pump();
    expect(find.textContaining('goes in its turn'), findsOneWidget);
  });

  testWidgets('Play runs the call from 0; 1 s on steps; Reset returns to the '
      'opening scene', (WidgetTester tester) async {
    final LatencyUnderLoadController c = await _open(tester);
    await _tap(tester, find.text('Play the call'));
    expect(c.playing, isTrue);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(c.timeS.value, inInclusiveRange(1.0, 2.0));
    expect(find.text('Pause'), findsOneWidget);
    await _tap(tester, find.text('Pause'));
    expect(c.playing, isFalse);
    final double at = c.timeS.value;
    await _tap(tester, find.text('1 s on'));
    expect(c.timeS.value, closeTo(at + 1, 1e-9));
    c.sqm = true;
    c.line = LulLine.dsl;
    await _tap(tester, find.text('Reset'));
    expect(c.config, const LulConfig());
    expect(c.timeS.value, kLulRunS);
  });

  testWidgets('the run stops at its end and does not loop', (
    WidgetTester tester,
  ) async {
    final LatencyUnderLoadController c = await _open(tester);
    c.seek(kLulRunS - 0.5);
    c.togglePlay();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(c.playing, isFalse);
    expect(c.timeS.value, kLulRunS);
  });

  testWidgets('with reduced motion nothing plays by itself', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final LatencyUnderLoadController c = LatencyUnderLoadController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: LatencyUnderLoadScreen(controller: c),
        ),
      ),
    );
    await tester.pump();
    expect(c.reducedMotion, isTrue);
    c.sqm = true;
    await tester.pump(const Duration(seconds: 2));
    expect(c.playing, isFalse);
    expect(c.timeS.value, kLulRunS);
  });

  testWidgets('stage and controls are separate widgets; the About card '
      'links the measuring tools', (WidgetTester tester) async {
    await _open(tester);
    expect(find.byType(LatencyUnderLoadStage), findsOneWidget);
    expect(find.byType(LatencyUnderLoadControls), findsOneWidget);
    expect(find.text('Open Network Quality'), findsOneWidget);
    expect(find.text('Open Test My Connection'), findsOneWidget);
    expect(find.text('Why a faster plan does not fix it'), findsOneWidget);
  });

  test('copy text carries both settings and the sources', () {
    final LatencyUnderLoadController c = LatencyUnderLoadController();
    addTearDown(c.dispose);
    final String t = c.copyText();
    expect(t, contains('Cable line, smart queue management off'));
    expect(
      t,
      contains('Idle: 18 ms (FCC measured cable ISPs: 12 ms to 24 ms)'),
    );
    expect(t, contains('SQM off: 225 ms (FCC chart reading, approximate'));
    expect(t, contains('SQM on: 23 ms (illustrative'));
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
        final LatencyUnderLoadController c = await _open(
          tester,
          size: Size(width, 5200),
          theme: theme(),
        );
        for (final LulLine l in LulLine.values) {
          for (final bool on in <bool>[false, true]) {
            c.line = l;
            c.sqm = on;
            c.seek(10);
            await tester.pump();
            expect(tester.takeException(), isNull, reason: '$l $on');
          }
        }
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
