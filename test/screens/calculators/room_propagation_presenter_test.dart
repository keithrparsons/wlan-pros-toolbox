// Presenter-mode test for Room Propagation (spec 00 "Done means": a
// presenter test at 1920x1080 with no overflow and no page scroll; the tool
// has no play or step, so its keys are R and the EIRP slider). Also held at
// 1440x900, both themes, every preset, with the close-up on and off, and at
// the full-resolution grid to confirm a full-screen redraw stays cheap.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/room_propagation_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/room_propagation_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/room_propagation_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/room_propagation_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

/// Runs every map job on the test thread at a coarse grid (the model tests
/// pin the physics at full resolution).
Future<RoomFieldResult> _coarse(RoomFieldJob job) =>
    Future<RoomFieldResult>.value(
      computeRoomField(
        RoomFieldJob(
          walls: job.walls,
          ap: job.ap,
          radio: job.radio,
          widthM: job.widthM,
          heightM: job.heightM,
          cellM: 1,
          rippleCenter: job.rippleCenter,
          rippleCells: 20,
          includeAverage: job.includeAverage,
        ),
      ),
    );

/// The real grid, still on the test thread.
Future<RoomFieldResult> _full(RoomFieldJob job) =>
    Future<RoomFieldResult>.value(computeRoomField(job));

Future<RoomPropagationController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
  int preset = 0,
  RoomFieldRunner runner = _coarse,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: RoomPropagationScreen(runner: runner, presetIndex: preset),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<RoomPropagationStage>(find.byType(RoomPropagationStage).first)
      .controller;
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
      // A 13/15-inch MacBook Air in full screen, measured 2026-09-26.
      Size(1470, 923),
    ]) {
      testWidgets(
        '$name ${window.width.toInt()}x${window.height.toInt()}: every '
        'preset fits with no overflow and no scroll',
        (WidgetTester tester) async {
          final RoomPropagationController c = await _present(
            tester,
            window: window,
            theme: theme(),
          );
          for (int p = 0; p < RoomPropagationController.presets.length; p++) {
            c.loadPreset(p);
            await tester.pumpAndSettle();
            for (final bool closeUp in <bool>[true, false]) {
              c.showCloseUp = closeUp;
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: 'preset $p');
              expect(pageScrollables(tester), isEmpty);
              expect(controlsOverflow(tester), 0, reason: 'preset $p');
            }
          }
          // The client readout is on the stage, at full size.
          expect(
            find.descendant(
              of: find.byKey(PresenterLayout.stageKey),
              matching: find.text('Received at the client'),
            ),
            findsOneWidget,
          );
        },
      );
    }
  }

  testWidgets('Up and Down move the EIRP; R reloads the plan', (
    WidgetTester tester,
  ) async {
    final RoomPropagationController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    expect(c.eirpDbm, 20);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();
    expect(c.eirpDbm, 22);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.eirpDbm, 21);

    c.moveClient(const P2(2, 2));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pumpAndSettle();
    expect(c.client, RoomPropagationController.presets[0].client);
    // No play or step on this tool: Space does nothing.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('full-resolution maps at full-screen size: moving the client '
      'redraws without recomputing the map', (WidgetTester tester) async {
    int jobs = 0;
    Future<RoomFieldResult> counting(RoomFieldJob job) {
      if (job.includeAverage) jobs++;
      return _full(job);
    }

    final RoomPropagationController c = await _present(
      tester,
      window: const Size(1920, 1080),
      runner: counting,
    );
    final int before = jobs;
    // The map's cost is set by the plan's cells (20 cm), not by pixels, so
    // a full-screen plan costs what a phone plan costs. Moving the client or
    // the EIRP recomputes no map at all.
    c.moveClient(const P2(9, 7));
    c.eirpDbm = 25;
    await tester.pumpAndSettle();
    expect(jobs, before);
    expect(tester.takeException(), isNull);
  });
}
