// Presenter-mode test for Antenna Pattern's Floor coverage view (spec 46):
// no overflow and no page scroll at 1920x1080, 1440x900 and 1470x923 in
// both themes for every preset; the keys the view declares work (Up/Down
// mount height, Right next preset, R first preset, V switches views).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_floor_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_floor_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<FloorCoverageController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const AntennaPatternScreen(initialView: AntennaStageView.floor),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<FloorCoverageStage>(find.byType(FloorCoverageStage))
      .floor;
}

void main() {
  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final Size window in const <Size>[
      Size(1920, 1080),
      Size(1440, 900),
      Size(1470, 923),
    ]) {
      testWidgets('$name ${window.width.toInt()}x${window.height.toInt()}: '
          'every preset fits with no overflow and no scroll', (
        WidgetTester tester,
      ) async {
        final FloorCoverageController f = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        for (final FloorPreset p in FloorPreset.values) {
          f.applyPreset(p);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: p.name);
          expect(pageScrollables(tester), isEmpty, reason: p.name);
          expect(controlsOverflow(tester), 0, reason: p.name);
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        }
        // The fullest panel: every disclosure open.
        for (final String t in <String>[
          'Readouts, both directions',
          'Power, band and client',
        ]) {
          await tester.tap(find.text(t));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
      });
    }
  }

  testWidgets('the headline numbers are on the stage', (
    WidgetTester tester,
  ) async {
    final FloorCoverageController f = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    f.applyPreset(FloorPreset.warehouseDipole);
    await tester.pumpAndSettle();
    final Finder stage = find.byKey(PresenterLayout.stageKey);
    expect(
      find.descendant(of: stage, matching: find.text('9.0 m (29.5 ft)')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: stage, matching: find.text('17.9 m (58.7 ft)')),
      findsOneWidget,
    );
    final Finder view = find.byWidgetPredicate(
      (Widget w) => w is CustomPaint && w.painter is FloorSidePainter,
    );
    expect(tester.getSize(view).height, greaterThan(400));
    // Vera gate B: the 9 m dipole's null is the model's 60 dB floor
    // (-114.2 dBm), so the headline gives the bound, not the figure.
    expect(
      find.descendant(of: stage, matching: find.text('below \u221295 dBm')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: stage, matching: find.textContaining('114.2')),
      findsNothing,
    );
    expect(
      find.descendant(of: stage, matching: find.textContaining('60.0 dB')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: stage,
        matching: find.text('Directly below, in the null'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Up and Down move the mount height, Right steps the preset, R '
      'goes back to the first, and the "?" list names them', (
    WidgetTester tester,
  ) async {
    final FloorCoverageController f = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    f.applyPreset(FloorPreset.warehouseDipole);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(f.heightM, 9.5);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(f.heightM, 8.5);

    f.applyPreset(FloorPreset.warehouseDipole);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(f.preset, FloorPreset.warehouseHighGainOmni);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pumpAndSettle();
    expect(f.preset, FloorPreset.office);

    await tester.tap(find.text('Shortcuts'));
    await tester.pump();
    expect(find.text('Mount height up'), findsOneWidget);
    expect(find.text('Next preset'), findsOneWidget);
    expect(find.text('Show the 3D pattern'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the antenna fold names the antenna a preset loads, even when '
      'its slider key does not change', (WidgetTester tester) async {
    final FloorCoverageController f = await _present(
      tester,
      window: const Size(1470, 923),
    );
    f.applyPreset(FloorPreset.warehouseHighGainOmni);
    await tester.pumpAndSettle();
    expect(find.text('Antenna: Omni, set by gain'), findsOneWidget);
    // Omni and directional both put Gain on Up and Down.
    f.applyPreset(FloorPreset.warehouseDirectional);
    await tester.pumpAndSettle();
    expect(find.text('Antenna: Directional (patch or sector)'), findsOneWidget);
    expect(find.text('Antenna: Omni, set by gain'), findsNothing);
  });

  testWidgets('V switches to the 3D view and back; the 3D keys return', (
    WidgetTester tester,
  ) async {
    final FloorCoverageController f = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    f.applyPreset(FloorPreset.warehouseHighGainOmni);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();
    expect(f.view, AntennaStageView.pattern);
    expect(find.byType(AntennaPatternStage), findsOneWidget);
    // Up is the omni's gain again in the 3D view.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(f.lab.omniGainDbi, 9);
    expect(f.heightM, 9);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();
    expect(f.view, AntennaStageView.floor);
    expect(find.byType(FloorCoverageStage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
