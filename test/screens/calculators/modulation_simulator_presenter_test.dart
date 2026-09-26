// Presenter-mode test for the Modulation Simulator (spec 00 "Done means":
// each converted tool has a presenter test at 1920x1080 with no overflow, no
// page scroll, and keyboard play/step). Also held at 1440x900, in both themes,
// with the random and the text bit source.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/modulation_simulator_screen.dart';
import 'package:wlan_pros_toolbox/services/rf/modulation_math.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/modulation_simulator_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<ModulationSimulatorController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const ModulationSimulatorScreen(seed: 1),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<ModulationSimulatorStage>(find.byType(ModulationSimulatorStage))
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
      for (final BitSource source in BitSource.values) {
        testWidgets('$name ${window.width.toInt()}x${window.height.toInt()} '
            '${source.name} bits: fits with no overflow and no scroll', (
          WidgetTester tester,
        ) async {
          final ModulationSimulatorController c = await _present(
            tester,
            window: window,
            theme: theme(),
          );
          c.setSource(source);
          c.burst();
          await tester.pump();
          // The densest order: 12-bit labels and the probe readout.
          c.setModulation(Modulation.qam4096);
          c.burst();
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0);
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        });
      }
    }
  }

  testWidgets('Space plays and pauses, Right steps, R resets, Up raises SNR', (
    WidgetTester tester,
  ) async {
    final ModulationSimulatorController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.sent, 1);
    expect(find.text('Decided as'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isTrue);
    expect(find.text('Pause'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(c.sent, greaterThanOrEqualTo(4));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.sent, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.snrDb, 26);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();
    expect(c.snrDb, 24);
  });

  testWidgets('the phone column does not render inside presenter mode', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    // The explainer and the phone readouts card are phone-only.
    expect(find.text('What you are seeing'), findsNothing);
    expect(find.text('Readouts'), findsNothing);
    // The fold opens to show the EVM limits.
    await tester.tap(find.textContaining('facts and 802.11 EVM limits'));
    await tester.pump();
    expect(find.text('Scale (K_MOD)'), findsOneWidget);
    expect(controlsOverflow(tester), greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);
  });
}
