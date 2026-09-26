// Widget tests for the Wi-Fi Classroom "DFS and Radar" screen (dfs-simulator).
//
// The rules and the run are pinned in test/services/wifi_lab/
// dfs_model_test.dart; these cover the screen contract: catalog
// registration, the fresh state, the CAC counting down to first
// transmission, a radar event mid-run (log, blocked channel, outage), Radar
// now disabled with its reason on a non-DFS channel, the EU plan dropping
// 144, Play and Pause, the stage and controls as separate widgets, the copy
// text, and phone and desktop widths in both themes laying out with no
// overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dfs_simulator_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dfs_simulator_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dfs_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dfs_simulator_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/dfs_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<void> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  double width = 390,
  double height = 844,
  bool reduceMotion = true,
  DfsConfig? initial,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          disableAnimations: reduceMotion,
        ),
        child: DfsSimulatorScreen(initial: initial),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _valueOf(WidgetTester tester, String label) {
  final Finder row = find
      .ancestor(of: find.text(label), matching: find.byType(Row))
      .first;
  final List<Text> texts = tester
      .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
      .toList();
  return texts.last.data ?? '';
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _steps(WidgetTester tester, int n) async {
  final Finder step = find.text('Step 10 s');
  for (int i = 0; i < n; i++) {
    await tester.ensureVisible(step);
    await tester.pumpAndSettle();
    await tester.tap(step);
    await tester.pumpAndSettle();
  }
}

DfsSimulatorController _controller(WidgetTester tester) =>
    tester.widget<DfsSimulatorStage>(find.byType(DfsSimulatorStage)).controller;

void main() {
  test(
    'catalog registers dfs-simulator in Wi-Fi Classroom, with its route',
    () {
      final ToolCategory rf = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'wifi-classroom',
      );
      final ToolEntry e = rf.tools.firstWhere(
        (ToolEntry t) => t.id == kDfsSimulatorToolId,
      );
      expect(e.title, 'DFS and Radar');
      expect(e.subgroup, 'Network Design and Security');
      expect(e.isLive, isTrue);
      expect(e.routeName, '/tools/dfs-simulator');
      expect(AppRouter.dfsSimulator, '/tools/dfs-simulator');
    },
  );

  testWidgets('fresh: 0:00, paused, CAC running on 100, no radar yet', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.text('DFS and Radar'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.textContaining('Reduced motion is on'), findsOneWidget);
    expect(
      find.textContaining('No radar yet. Press Radar now'),
      findsOneWidget,
    );
    expect(_valueOf(tester, 'AP'), contains('Listening (CAC) on 100'));
    expect(_valueOf(tester, 'AP'), contains('60.0 s left'));
    expect(_valueOf(tester, 'Time to first transmission'), contains('Not yet'));
    expect(_valueOf(tester, 'Blocked channels'), 'None');
    final OutlinedButton restart = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Restart'),
        matching: find.byWidgetPredicate((Widget w) => w is OutlinedButton),
      ),
    );
    expect(restart.onPressed, isNull);
    // Stage and controls are separate widgets over one controller.
    expect(find.byType(DfsSimulatorStage), findsOneWidget);
    expect(find.byType(DfsSimulatorControls), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Channel 100, DFS, channel availability check'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('A teaching model of one AP'), findsOneWidget);
  });

  testWidgets('the CAC counts down to first transmission at 1:00', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await _steps(tester, 6);
    expect(_valueOf(tester, 'AP'), 'Serving on 100 at 20 MHz, DFS');
    expect(_valueOf(tester, 'Time to first transmission'), '60.0 s');
    expect(find.bySemanticsLabel('Channel 100, DFS, in use'), findsOneWidget);
  });

  testWidgets('radar mid-run: log, blocked channel, outage, move to 36', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await _steps(tester, 30); // 5:00
    await _tap(tester, find.text('Radar now'));
    expect(find.text('Radar 1 at 5:00 on 100'), findsOneWidget);
    expect(_valueOf(tester, 'AP'), 'Radar: leaving 100');
    expect(_valueOf(tester, 'Radar events'), '1');
    expect(
      _valueOf(tester, 'Blocked channels'),
      contains('100: blocked until 35:00'),
    );
    await _steps(tester, 1); // 5:10
    expect(_valueOf(tester, 'AP'), 'Serving on 36 at 20 MHz');
    expect(_valueOf(tester, 'Outage, last radar'), '1.0 s outage');
    expect(
      find.bySemanticsLabel(RegExp(r'^Channel 100, DFS, blocked after radar')),
      findsOneWidget,
    );
    expect(
      find.textContaining('clients follow the channel switch'),
      findsOneWidget,
    );
    // On 36 there is no radar to detect.
    expect(find.textContaining('is not a DFS channel'), findsOneWidget);
    final OutlinedButton radar = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Radar now'),
        matching: find.byWidgetPredicate((Widget w) => w is OutlinedButton),
      ),
    );
    expect(radar.onPressed, isNull);
    // Copy text carries the event.
    final String copy = _controller(tester).copyText();
    expect(copy, contains('5:00 radar on 100, moved to 36 at 20 MHz (no CAC)'));
    expect(copy, contains('Blocked: 100 until 35:00'));
    // Restart clears the radar the student added.
    await _tap(tester, find.text('Restart'));
    expect(_valueOf(tester, 'Radar events'), '0');
    expect(_controller(tester).config.manualRadarS, isEmpty);
  });

  testWidgets('Step stays put when the Radar now reason comes and goes', (
    WidgetTester tester,
  ) async {
    // Regression: the reason line sat between the Play row and the Step row,
    // so Step jumped under the finger as the AP moved from leaving a channel
    // (reason shown) to a CAC on the next one (reason gone).
    await _pump(
      tester,
      initial: const DfsConfig(
        policy: NewChannelPolicy.anotherDfs,
        manualRadarS: <double>[300],
      ),
    );
    double gap() =>
        tester.getCenter(find.text('Step 10 s')).dy -
        tester.getCenter(find.text('Play')).dy;
    _controller(tester).seek(300.5); // leaving 100: reason shown
    await tester.pumpAndSettle();
    expect(find.textContaining('already leaving'), findsOneWidget);
    final double leaving = gap();
    _controller(tester).seek(310); // CAC on 104: reason gone
    await tester.pumpAndSettle();
    expect(find.textContaining('already leaving'), findsNothing);
    expect(gap(), leaving);
  });

  testWidgets('Another DFS: the outage runs through a new 60 s CAC', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      initial: const DfsConfig(policy: NewChannelPolicy.anotherDfs),
    );
    await _steps(tester, 30);
    await _tap(tester, find.text('Radar now'));
    await _steps(tester, 3); // 5:30
    expect(_valueOf(tester, 'AP'), contains('Listening (CAC) on 104'));
    expect(
      _valueOf(tester, 'Outage, last radar'),
      contains('so far, still out'),
    );
    expect(
      find.textContaining('Clients drop and rejoin after'),
      findsOneWidget,
    );
    await _steps(tester, 4); // 6:10
    expect(_valueOf(tester, 'Outage, last radar'), '61.0 s outage');
  });

  testWidgets('non-DFS start: serves at once; Radar now off with reason', (
    WidgetTester tester,
  ) async {
    await _pump(tester, initial: const DfsConfig(startChannel: 36));
    expect(
      _valueOf(tester, 'Time to first transmission'),
      '0 s, no CAC needed',
    );
    expect(
      find.textContaining('Channel 36 is not a DFS channel'),
      findsOneWidget,
    );
    expect(find.textContaining('does not listen for radar'), findsOneWidget);
  });

  testWidgets('EU: 144 is not in the plan; 120 carries the 10-min bracket', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await _tap(tester, find.text('EU (ETSI)'));
    expect(
      find.bySemanticsLabel('Channel 144, not in this plan'),
      findsOneWidget,
    );
    expect(find.text('5600-5650 MHz: 10-min CAC'), findsOneWidget);
    expect(_valueOf(tester, 'Channel availability check'), contains('10 min'));
    // Starting channel 100 is kept (still in the EU plan).
    expect(_controller(tester).startPlacement.components, <int>[100]);
  });

  testWidgets('normal motion: Play runs, Pause stops', (
    WidgetTester tester,
  ) async {
    await _pump(tester, reduceMotion: false);
    expect(find.textContaining('Reduced motion is on'), findsNothing);
    await tester.ensureVisible(find.text('Play'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_controller(tester).timeS, greaterThan(0));
    await tester.tap(find.text('Pause'));
    await tester.pump();
    final double t = _controller(tester).timeS;
    await tester.pump(const Duration(seconds: 1));
    expect(_controller(tester).timeS, t);
  });

  for (final bool light in <bool>[false, true]) {
    for (final double w in <double>[390, 1280]) {
      testWidgets(
        'lays out at $w px, ${light ? 'light' : 'dark'}, with radar',
        (WidgetTester tester) async {
          await _pump(
            tester,
            width: w,
            theme: light ? AppTheme.light() : AppTheme.dark(),
            initial: const DfsConfig(
              region: DfsRegion.eu,
              widthMHz: 40,
              startChannel: 116,
              policy: NewChannelPolicy.anotherDfs,
              manualRadarS: <double>[300],
            ),
          );
          _controller(tester).seek(420);
          await tester.pumpAndSettle();
          _controller(tester).view = DfsTimelineView.zoom;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Radar 1 at 5:00 on 116-120'), findsOneWidget);
        },
      );
    }
  }
}
