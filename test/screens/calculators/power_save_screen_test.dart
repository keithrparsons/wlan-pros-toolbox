// Widget tests for the Wi-Fi Classroom "Power Save" screen (power-save).
//
// The rules and the run are pinned in test/services/wifi_lab/
// power_save_model_test.dart; these cover the screen contract: catalog
// registration and route, the fresh Legacy PS vs TWT state, the stage and
// controls as separate widgets over one controller, the TWT mantissa error
// state keeping the last valid run, the empty-traffic readouts, the
// disabled random-pattern button, the missed-group-frames verdict, the
// listen-interval alignment note, the copy text, and phone and desktop
// widths in both themes laying out with no overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/power_save_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/power_save_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/power_save_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/power_save_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/power_save_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<void> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  double width = 390,
  double height = 844,
  PsConfig? initial,
  PsMode? compare = PsMode.twt,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: PowerSaveScreen(initial: initial, compare: compare),
    ),
  );
  await tester.pumpAndSettle();
}

PowerSaveController _controller(WidgetTester tester) =>
    tester.widget<PowerSaveStage>(find.byType(PowerSaveStage)).controller;

void main() {
  test('catalog registers power-save in Wi-Fi Classroom, with its route', () {
    final ToolEntry t = kToolCategories
        .expand((ToolCategory c) => c.tools)
        .firstWhere((ToolEntry e) => e.id == kPowerSaveToolId);
    expect(t.title, 'Power Save');
    expect(t.subgroup, 'Wi-Fi Classroom');
    expect(t.routeName, '/tools/power-save');
    expect(t.isLive, isTrue);
    expect(AppRouter.powerSave, '/tools/power-save');
    final ToolCategory rf = kToolCategories.firstWhere(
      (ToolCategory c) => c.tools.any((ToolEntry e) => e.id == 'power-save'),
    );
    expect(rf.id, 'rf-calculators');
  });

  testWidgets('fresh: Legacy PS vs TWT, stage and controls share one '
      'controller', (WidgetTester tester) async {
    await _pump(tester);
    expect(find.text('Power Save'), findsOneWidget);
    expect(find.byType(PowerSaveStage), findsOneWidget);
    expect(find.byType(PowerSaveControls), findsOneWidget);
    final PowerSaveController c = _controller(tester);
    expect(
      tester
          .widget<PowerSaveControls>(find.byType(PowerSaveControls))
          .controller,
      same(c),
    );
    expect(c.runs.map((PsRun r) => r.mode), <PsMode>[
      PsMode.legacy,
      PsMode.twt,
    ]);
    expect(find.text('Timeline: Legacy PS vs TWT'), findsOneWidget);
    expect(find.text('Over the whole 60.00 s run'), findsOneWidget);
    // TWT is awake less than legacy PS.
    expect(c.compareRun!.awakeFraction, lessThan(c.run.awakeFraction));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the timeline carries a worded summary for screen readers', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final Finder f = find.bySemanticsLabel(
      RegExp(
        r'^Timeline from 0\.00 ms to 1\.00 s\. 10 beacons, 4 of them '
        r'DTIM\. Legacy PS: \d+ wakes',
      ),
    );
    expect(f, findsOneWidget);
  });

  testWidgets('a bad mantissa shows its reason and keeps the last valid run', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final PowerSaveController c = _controller(tester);
    final PsRun before = c.compareRun!;
    final Finder field = find.byKey(const ValueKey<String>('twt-mantissa'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '0');
    await tester.pumpAndSettle();
    expect(find.text('A mantissa of 0 gives no wake interval.'), findsWidgets);
    expect(c.config.twt.mantissa, 62500);
    expect(identical(c.compareRun, before), isTrue);

    await tester.enterText(field, '70000');
    await tester.pumpAndSettle();
    expect(find.text('The mantissa is 16 bits: 0 to 65535.'), findsWidgets);

    await tester.enterText(field, '31250');
    await tester.pumpAndSettle();
    expect(c.twtError, isNull);
    expect(c.config.twt.intervalUs, 500000);
  });

  testWidgets('the 30 s preset sets mantissa and exponent together', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final Finder b = find.text('30 s');
    await tester.ensureVisible(b);
    await tester.tap(b);
    await tester.pumpAndSettle();
    final PowerSaveController c = _controller(tester);
    expect(c.config.twt.mantissa, 58594);
    expect(c.config.twt.exponent, 9);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey<String>('twt-mantissa')))
          .controller!
          .text,
      '58594',
    );
    // Four cycles of 30 s.
    expect(c.config.horizonUs, 4 * 58594 * 512);
  });

  testWidgets('no traffic: the readouts say so', (WidgetTester tester) async {
    await _pump(
      tester,
      initial: const PsConfig(
        traffic: TrafficSettings(dlBurstsPerS: 0, ulPerS: 0, groupPerS: 0),
      ),
    );
    expect(find.text('No downlink'), findsWidgets);
    expect(find.text('No uplink'), findsWidgets);
    expect(find.text('None heard'), findsWidgets);
  });

  testWidgets('missed group frames are a worded verdict', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final PowerSaveController c = _controller(tester);
    expect(c.compareRun!.groupMissed, greaterThan(0));
    expect(find.text('${c.compareRun!.groupMissed} missed'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
  });

  testWidgets('New random pattern is disabled for regular arrivals', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      initial: const PsConfig(traffic: TrafficSettings(regular: true)),
    );
    expect(
      find.text(
        'Regular arrivals are evenly spaced, so there is no random pattern '
        'to change.',
      ),
      findsOneWidget,
    );
    final OutlinedButton b = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('New random pattern'),
        matching: find.byWidgetPredicate((Widget w) => w is OutlinedButton),
      ),
    );
    expect(b.onPressed, isNull);
  });

  testWidgets('listen interval and DTIM that do not line up get a note', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      initial: const PsConfig(dtimPeriod: 4, listenInterval: 3),
    );
    expect(
      find.textContaining('Listen interval 3 and DTIM 4 do not line up'),
      findsOneWidget,
    );
    expect(find.textContaining('6 of every 12 beacons'), findsOneWidget);
  });

  testWidgets('choosing the compared mode as the mode swaps them', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final PowerSaveController c = _controller(tester);
    c.mode = PsMode.twt;
    await tester.pumpAndSettle();
    expect(c.config.mode, PsMode.twt);
    expect(c.compare, PsMode.legacy);
    c.compare = null;
    await tester.pumpAndSettle();
    expect(c.runs, hasLength(1));
    expect(find.text('Timeline: TWT'), findsOneWidget);
  });

  testWidgets('copy text names both modes and their readouts', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final String t = _controller(tester).copyText();
    expect(t, contains('Power Save (WLAN Pros Toolbox, teaching model)'));
    expect(t, contains('Legacy PS (PS-Poll):'));
    expect(t, contains('Target Wake Time (TWT) (individual, 62500 x 2^4'));
    expect(t, contains('parameters, not measurements'));
  });

  for (final bool light in <bool>[false, true]) {
    for (final double w in <double>[390, 1280]) {
      testWidgets('lays out at $w px, ${light ? 'light' : 'dark'}, no '
          'overflow', (WidgetTester tester) async {
        await _pump(
          tester,
          width: w,
          theme: light ? AppTheme.light() : AppTheme.dark(),
        );
        final PowerSaveController c = _controller(tester);
        for (final PsView v in PsView.values) {
          c.view = v;
          await tester.pumpAndSettle();
        }
        c.mode = PsMode.uapsd;
        await tester.pumpAndSettle();
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -4000),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
