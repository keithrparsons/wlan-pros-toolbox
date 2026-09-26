// Presenter-mode test for the FSPL Simulator (spec 00 "Done means": a
// presenter test with no overflow and no page scroll). Held at 1920x1080,
// 1440x900 and 1470x923 in both themes, in the fullest state: every band,
// the indoor model, a measured point and the 1 km axis. Nothing animates, so
// the keys are the cursor distance (Up doubles, Down halves).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_simulator_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_simulator_panels.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_simulator_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<FsplSimModel> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const FsplSimulatorScreen(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester.widget<FsplStage>(find.byType(FsplStage).last).model;
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
      testWidgets('$name ${window.width.toInt()}x${window.height.toInt()}: '
          'fullest state fits with no overflow and no scroll', (
        WidgetTester tester,
      ) async {
        final FsplSimModel m = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        for (final FsplView view in FsplView.values) {
          m
            ..setView(view)
            ..setRange(FsplRange.km1)
            ..setIndoor(true)
            ..setOtherLoss(12)
            ..setMeasuredText(rssi: '-71', dist: '40')
            ..setCursor(300);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: view.name);
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0, reason: view.name);
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        }
        // The cursor numbers are on the stage, not in the panel.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.byType(FsplCursorHeadline),
          ),
          findsOneWidget,
        );
        // No band on: the empty state still fits.
        for (final b in m.bands.toList()) {
          m.setBand(b, false);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(controlsOverflow(tester), 0);
      });
    }
  }

  testWidgets('Up doubles and Down halves the cursor; Space and R do nothing', (
    WidgetTester tester,
  ) async {
    final FsplSimModel m = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    expect(m.cursorM, 10);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(m.cursorM, 20);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(m.cursorM, 5);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(m.cursorM, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the phone prose is gone and the folds open', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    expect(find.text('What the curve says'), findsNothing);
    expect(find.textContaining('0 dBi is an isotropic antenna'), findsNothing);
    expect(find.text('2.4 GHz channel'), findsNothing);
    await tester.tap(find.text('Channels'));
    await tester.pumpAndSettle();
    expect(find.text('2.4 GHz channel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
