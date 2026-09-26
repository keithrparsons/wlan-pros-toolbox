// Presenter-mode test for Multi-Link Operation (spec 00 "Done means": no
// overflow and no page scroll; this tool has no clock, so no play or step).
// Held at 1920x1080, 1440x900 and 1470x923 in both themes, on every lesson
// with all three links on (the fullest lanes and panel), and proves the
// tool's keys: R back to the lesson, Up and Down slide the lanes, N draws
// new traffic.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mlo_simulator_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mlo_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mlo_simulator_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mlo_simulator_state.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/mlo_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<MloSimulatorState> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const MloSimulatorScreen(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<MloSimulatorStage>(find.byType(MloSimulatorStage).last)
      .state;
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
      for (final MloPreset lesson in MloPreset.values) {
        testWidgets('$name ${window.width.toInt()}x${window.height.toInt()} '
            '${lesson.name}: fits with no overflow and no scroll', (
          WidgetTester tester,
        ) async {
          final MloSimulatorState s = await _present(
            tester,
            window: window,
            theme: theme(),
          );
          s.preset = lesson;
          for (final MloBand b in MloBand.values) {
            s.setBandEnabled(b, true);
          }
          s.laneMode = MloMode.emlsr;
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0);
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
          // The verdict, the sentence the lesson is about, is on the stage.
          expect(
            find.descendant(
              of: find.byKey(PresenterLayout.stageKey),
              matching: find.text(mloVerdict(s)),
            ),
            findsOneWidget,
          );
        });
      }
    }
  }

  testWidgets('R returns to the lesson, Up and Down slide the lanes, N draws '
      'new traffic', (WidgetTester tester) async {
    final MloSimulatorState s = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    expect(s.windowStartUs, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(s.windowStartUs, s.window.us / 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();
    expect(s.windowStartUs, 0);

    final int seed = s.config.seed;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(s.config.seed, seed + 1);
    expect(s.preset, MloPreset.equal);

    s.setBusyFraction(MloBand.ghz5, 0.8);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(s.preset, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(s.preset, MloPreset.equal);
    expect(s.config.links, MloPreset.equal.config.links);
    expect(s.windowStartUs, 0);
    expect(tester.takeException(), isNull);
  });
}
