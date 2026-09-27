// The app-wide metric / imperial preference: default, persistence, and the
// one switch driving every open Classroom tool (Keith, 2026-09-27).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_simulator_chart.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wifi_through_a_wall_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/units/unit_system.dart';
import 'package:wlan_pros_toolbox/widgets/unit_system_switch.dart';

Future<void> _pump(
  WidgetTester tester,
  UnitSystemController c,
  Widget home, {
  Size size = const Size(1280, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UnitSystemScope(
      controller: c,
      child: MaterialApp(theme: AppTheme.dark(), home: home),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('UnitSystemController', () {
    test('defaults to metric with nothing stored', () async {
      final UnitSystemController c = UnitSystemController();
      await c.load();
      expect(c.system, UnitSystem.metric);
    });

    test('a pick persists and a fresh controller loads it', () async {
      final UnitSystemController a = UnitSystemController();
      await a.setSystem(UnitSystem.imperial);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(UnitSystemController.prefsKey), 'imperial');

      final UnitSystemController b = UnitSystemController();
      await b.load();
      expect(b.system, UnitSystem.imperial);
    });

    test('a garbage stored value falls back to metric', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        UnitSystemController.prefsKey: 'furlongs',
      });
      final UnitSystemController c = UnitSystemController();
      await c.load();
      expect(c.system, UnitSystem.metric);
    });
  });

  testWidgets('the switch lists Metric first and flips the app pick', (
    WidgetTester tester,
  ) async {
    final UnitSystemController c = UnitSystemController();
    await _pump(tester, c, const FsplSimulatorScreen());
    final Finder sw = find.byKey(UnitSystemSwitch.switchKey);
    expect(sw, findsOneWidget);
    final Offset metric = tester.getCenter(
      find.descendant(of: sw, matching: find.text('Metric')),
    );
    final Offset imperial = tester.getCenter(
      find.descendant(of: sw, matching: find.text('Imperial')),
    );
    expect(metric.dx, lessThan(imperial.dx));
    await tester.tap(find.descendant(of: sw, matching: find.text('Imperial')));
    await tester.pump();
    expect(c.system, UnitSystem.imperial);
  });

  testWidgets('flipping the switch in one tool changes another tool', (
    WidgetTester tester,
  ) async {
    final UnitSystemController c = UnitSystemController();
    // One tool open, flipped there.
    await _pump(tester, c, const FsplSimulatorScreen());
    expect(find.text('100 m'), findsWidgets);
    await tester.tap(
      find.descendant(
        of: find.byKey(UnitSystemSwitch.switchKey),
        matching: find.text('Imperial'),
      ),
    );
    await tester.pump();
    expect(find.text('300 ft'), findsWidgets);
    expect(find.text('100 m'), findsNothing);

    // A different tool, opened afterwards, is already imperial.
    await _pump(tester, c, const WifiThroughAWallScreen());
    expect(find.textContaining('(in, 0.39 to 19.7)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the wall shows and accepts cm in metric, inches in imperial', (
    WidgetTester tester,
  ) async {
    final UnitSystemController c = UnitSystemController();
    await _pump(tester, c, const WifiThroughAWallScreen());
    final Finder field = find.byType(TextField);
    await tester.ensureVisible(field);
    expect(find.textContaining('(cm, 1 to 50)'), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, '10.2');

    await tester.enterText(field, '20');
    await tester.pump();
    expect(find.textContaining('Concrete, 20 cm'), findsWidgets);

    // Below the 1 cm floor is rejected too (Keith, 2026-09-27: 1 to 50 cm).
    await tester.enterText(field, '0.5');
    await tester.pump();
    expect(find.text('Enter a thickness from 1 to 50 cm'), findsOneWidget);
    await tester.enterText(field, '51');
    await tester.pump();
    expect(find.text('Enter a thickness from 1 to 50 cm'), findsOneWidget);

    // Flip: the field rewrites itself in inches, and typed inches land.
    await c.setSystem(UnitSystem.imperial);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '7.9');
    expect(find.text('Enter a thickness from 1 to 50 cm'), findsNothing);
    await tester.enterText(field, '8');
    await tester.pump();
    expect(find.textContaining('Concrete, 8 in'), findsWidgets);
    await tester.enterText(field, '20');
    await tester.pump();
    expect(find.text('Enter a thickness from 0.39 to 19.7 in'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  group('FSPL axis ticks in imperial', () {
    test('linear 300 ft axis ticks every 50 ft, labelled in round feet', () {
      final List<FsplDistanceTick> t = FsplChartPainter.distanceTicks(
        units: UnitSystem.imperial,
        minDistanceM: 0.9144,
        maxDistanceM: 91.44,
        logDistance: false,
      );
      final List<String> labels = <String>[
        for (final FsplDistanceTick x in t)
          if (x.label != null) x.label!,
      ];
      expect(labels, <String>[
        '0',
        '50 ft',
        '100 ft',
        '150 ft',
        '200 ft',
        '250 ft',
        '300 ft',
      ]);
    });

    test('log 3 ft to 300 ft labels the ends and the decades', () {
      final List<FsplDistanceTick> t = FsplChartPainter.distanceTicks(
        units: UnitSystem.imperial,
        minDistanceM: 0.9144,
        maxDistanceM: 91.44,
        logDistance: true,
      );
      expect(
        <String>[
          for (final FsplDistanceTick x in t)
            if (x.label != null) x.label!,
        ],
        <String>['3 ft', '10 ft', '100 ft', '300 ft'],
      );
    });

    test('metric ticks are unchanged: 1, 10, 100 m', () {
      final List<FsplDistanceTick> t = FsplChartPainter.distanceTicks(
        units: UnitSystem.metric,
        minDistanceM: 1,
        maxDistanceM: 100,
        logDistance: true,
      );
      expect(
        <String>[
          for (final FsplDistanceTick x in t)
            if (x.label != null) x.label!,
        ],
        <String>['1 m', '10 m', '100 m'],
      );
    });
  });
}
