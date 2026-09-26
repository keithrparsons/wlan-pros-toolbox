// Widget tests for the Wi-Fi Classroom "Survey Walk" screen (spec 26).
//
// The model is pinned in test/services/wifi_lab/survey_walk_engine_test.dart;
// these cover the screen contract: catalog, route and help registration, the
// fresh state, Step, the Rule 4 verdict in words, the NIC presets, hybrid
// refused with one NIC, the active-survey limits, the opening question and
// its reveal, stage and controls as separate widgets, the copy text, phone
// and desktop widths in both themes with no overflow, and (Keith,
// 2026-09-26) no product name and no "Signal Propagation Assessment" in any
// string the tool ships.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/survey_walk_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/survey_walk_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/survey_walk_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/survey_walk_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/survey_walk_engine.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<SurveyWalkController> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  double width = 1024,
  double height = 1366,
  SurveyWalkConfig? initial,
}) async {
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          disableAnimations: true,
        ),
        child: SurveyWalkScreen(initial: initial),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester
      .widget<SurveyWalkStage>(find.byType(SurveyWalkStage))
      .controller;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Survey product and platform names the tool must never show (spec 26).
const List<String> _productNames = <String>[
  'sidekick',
  'ekahau',
  'hamina',
  'tamograph',
  'airmagnet',
  'acrylic',
  'netspot',
  'oscium',
  'nomad',
  'android',
  'iphone',
  'linux',
  'mac80211',
  'autopilot',
];

void main() {
  test('catalog, route and help register survey-walk in Wi-Fi Classroom', () {
    final ToolCategory c = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'wifi-classroom',
    );
    final ToolEntry e = c.tools.firstWhere(
      (ToolEntry t) => t.id == kSurveyWalkToolId,
    );
    expect(e.title, 'Survey Walk');
    expect(e.subgroup, 'Network Design and Security');
    expect(e.routeName, AppRouter.surveyWalk);
    expect(AppRouter.routes.containsKey('/tools/survey-walk'), isTrue);
    expect(File('assets/tool-icons/survey-walk.svg').existsSync(), isTrue);

    final Map<String, dynamic> help =
        ((jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                    as Map<String, dynamic>)['tools']
                as Map<String, dynamic>)['survey-walk']
            as Map<String, dynamic>;
    final String how = (help['howToUse'] as List<dynamic>).join(' ');
    expect(how, contains('Present'));
    for (final String k in <String>[
      'Space',
      'Right arrow',
      'R restarts',
      'Up and Down',
    ]) {
      expect(how, contains(k));
    }

    final List<String> kw = kToolKeywords['survey-walk']!;
    for (final String k in <String>[
      'survey',
      'walking speed',
      'scan',
      'dwell',
      'nic',
      'adapter',
      'guess range',
      'accuracy distance',
      'interpolation distance',
      'continuous',
      'stop and go',
      'line survey',
      'passive',
      'active',
      'hybrid',
    ]) {
      expect(kw, contains(k));
    }
  });

  test('no product name and no "Signal Propagation Assessment" in any '
      'string the tool ships', () {
    final List<String> sources = <String>[
      for (final String f in <String>[
        'survey_walk_controller.dart',
        'survey_walk_controls.dart',
        'survey_walk_painters.dart',
        'survey_walk_screen.dart',
        'survey_walk_stage.dart',
      ])
        File('lib/screens/tools/calculators/$f').readAsStringSync(),
      File('lib/services/wifi_lab/survey_walk_engine.dart').readAsStringSync(),
      jsonEncode(
        ((jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                as Map<String, dynamic>)['tools']
            as Map<String, dynamic>)['survey-walk'],
      ),
      kToolKeywords['survey-walk']!.join(' '),
      kToolCategories
          .expand((ToolCategory c) => c.tools)
          .firstWhere((ToolEntry t) => t.id == kSurveyWalkToolId)
          .description,
    ];
    for (final String s in sources) {
      final String lower = s.toLowerCase();
      for (final String name in _productNames) {
        expect(lower.contains(name), isFalse, reason: 'found "$name"');
      }
      expect(lower.contains('signal propagation assessment'), isFalse);
    }
    for (int n = 1; n <= 4; n++) {
      for (final String name in _productNames) {
        expect(nicPresetLabel(n).toLowerCase().contains(name), isFalse);
      }
    }
  });

  testWidgets('fresh: 0 s, the opening question waits, Rule 4 fails in '
      'words for 1 NIC', (WidgetTester tester) async {
    final SurveyWalkController c = await _pump(tester);
    expect(c.timeS, 0);
    expect(c.playing, isFalse);
    expect(
      find.text(
        'RF (radio frequency) energy travels at the speed of light, so does '
        'walking speed matter?',
      ),
      findsOneWidget,
    );
    expect(
      find.text('The answer appears after the first full walk.'),
      findsOneWidget,
    );
    expect(find.textContaining('Fail: longest revisit 7.0 s'), findsOneWidget);
    expect(find.text('Revisit, 5 GHz'), findsOneWidget);
    expect(find.textContaining('7.0 s, spacing 9.8 m'), findsWidgets);
  });

  testWidgets('Step moves 1 s; the walk end reveals the answer', (
    WidgetTester tester,
  ) async {
    final SurveyWalkController c = await _pump(tester);
    await _tap(tester, find.text('Step'));
    expect(c.timeS, kSurveyStepSeconds);
    await _tap(tester, find.text('Yes, it matters'));
    expect(c.prediction, SurveyPrediction.matters);
    c.seek(c.result.durationS);
    await tester.pumpAndSettle();
    expect(c.revealed, isTrue);
    expect(find.text('Right, and not because of light.'), findsOneWidget);
    expect(find.textContaining('holds still for 14 to 37 ms'), findsOneWidget);
    expect(find.text('Walk again'), findsOneWidget);
  });

  testWidgets('the NIC presets change only the radio count, and 2 NICs '
      'pass Rule 4', (WidgetTester tester) async {
    final SurveyWalkController c = await _pump(tester);
    c.dwellMs = 200;
    c.radios = 2;
    await tester.pumpAndSettle();
    expect(c.config.scanner.dwellMs, 200);
    expect(c.config.scanner.channelSet, ChannelSetPreset.g24g5);
    c.dwellMs = 250;
    await tester.pumpAndSettle();
    expect(find.textContaining('Pass: longest revisit 3.5 s'), findsOneWidget);
    expect(find.text('2 NICs'), findsOneWidget);
  });

  testWidgets('hybrid is refused with 1 NIC and the reason is shown', (
    WidgetTester tester,
  ) async {
    final SurveyWalkController c = await _pump(tester);
    await _tap(tester, find.text('Hybrid').first);
    expect(c.config.effectiveType, SurveyType.passive);
    expect(
      find.textContaining('Hybrid is not available: A hybrid survey needs'),
      findsOneWidget,
    );
    c.radios = 2;
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Hybrid').first);
    expect(c.config.effectiveType, SurveyType.hybrid);
    expect(find.textContaining('Hybrid is not available'), findsNothing);
    // Back to 1 NIC: hybrid falls back to passive.
    c.radios = 1;
    await tester.pumpAndSettle();
    expect(c.config.effectiveType, SurveyType.passive);
  });

  testWidgets('active shows the five limits', (WidgetTester tester) async {
    final SurveyWalkController c = await _pump(tester);
    expect(find.text('What an active survey cannot show'), findsNothing);
    await _tap(tester, find.text('Active').first);
    expect(c.config.effectiveType, SurveyType.active);
    expect(find.text('What an active survey cannot show'), findsOneWidget);
    for (final String l in kActiveSurveyLimits) {
      expect(find.text(l), findsOneWidget);
    }
    expect(c.result.servingApAt(0), isNotNull);
  });

  testWidgets('the door pause shows a position error in meters', (
    WidgetTester tester,
  ) async {
    final SurveyWalkController c = await _pump(tester);
    expect(find.textContaining('up to 0.0 m'), findsOneWidget);
    c.doorPause = true;
    await tester.pumpAndSettle();
    expect(find.textContaining('up to 2.0 m'), findsOneWidget);
  });

  testWidgets('stage and controls are separate widgets on one controller', (
    WidgetTester tester,
  ) async {
    final SurveyWalkController c = await _pump(tester);
    expect(find.byType(SurveyWalkStage), findsOneWidget);
    expect(find.byType(SurveyWalkControls), findsNWidgets(2));
    for (final SurveyWalkControls w in tester.widgetList<SurveyWalkControls>(
      find.byType(SurveyWalkControls),
    )) {
      expect(w.controller, same(c));
    }
  });

  testWidgets('copy text names the device, Rule 4 and the error', (
    WidgetTester tester,
  ) async {
    final SurveyWalkController c = await _pump(tester);
    final String t = c.copyText();
    expect(t, contains("Device: 1 NIC (a laptop's built-in radio)"));
    expect(t, contains('Rule 4: longest allowed revisit 3.57 s'));
    expect(t, contains('fail'));
    expect(t, contains('5 GHz: revisit 7.0 s, spacing 9.8 m'));
  });

  testWidgets('signal layer and all-channels view build', (
    WidgetTester tester,
  ) async {
    final SurveyWalkController c = await _pump(tester);
    c.showSignal = true;
    c.seek(20);
    await tester.pumpAndSettle();
    expect(find.textContaining('Signal along the path (dBm)'), findsOneWidget);
    c.shownChannel = null;
    await tester.pumpAndSettle();
    expect(find.textContaining('Signal along the path (dBm)'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final (double w, double h) in <(double, double)>[
      (390, 844),
      (1024, 1366),
      (1440, 900),
    ]) {
      testWidgets('$name ${w.toInt()} wide mid-walk: no overflow', (
        WidgetTester tester,
      ) async {
        final SurveyWalkController c = await _pump(
          tester,
          theme: theme(),
          width: w,
          height: h,
          initial: SurveyWalkConfig(
            scanner: const ScannerConfig(
              radios: 3,
              algorithm: HoppingAlgorithm.priority,
            ),
            doorPause: true,
          ),
        );
        c.showSignal = true;
        c.seek(c.result.durationS * 0.6);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('drawing a path: floor taps add points; Use this path applies', (
    WidgetTester tester,
  ) async {
    final SurveyWalkController c = await _pump(tester);
    c.pathPreset = SurveyPathPreset.custom;
    await tester.pumpAndSettle();
    expect(c.drawing, isTrue);
    c.addWaypoint((x: 5, y: 10));
    c.addWaypoint((x: 40, y: 10));
    c.addWaypoint((x: 40, y: 3));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Use this path'));
    expect(c.drawing, isFalse);
    expect(c.pathPreset, SurveyPathPreset.custom);
    expect(c.result.plan.lengthM, closeTo(42, 1e-9));
  });
}
