// Presenter-mode test for the Channel Planner (spec 00 "Done means": no
// overflow, no page scroll, the tool's keys). Held at 1920x1080, 1440x900
// and 1470x923 in both themes, on both bands, with the fullest plan: twelve
// APs, walls, the wall tool on and an AP selected.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/channel_planner_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/channel_planner_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/channel_planner_state.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/channel_planner_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<ChannelPlannerState> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const ChannelPlannerScreen(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<ChannelPlannerStage>(find.byType(ChannelPlannerStage).last)
      .state;
}

void _fullest(ChannelPlannerState s, PlannerBand band) {
  s.setBand(band);
  while (s.canAdd) {
    s.addAp();
  }
  s.addWallAcross(vertical: true);
  s.addWallAcross(vertical: false);
  s.setWallMode(true);
  s.select(11);
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
      for (final PlannerBand band in PlannerBand.values) {
        testWidgets('$name ${window.width.toInt()}x${window.height.toInt()} '
            '${band.label}: fits with no overflow and no scroll', (
          WidgetTester tester,
        ) async {
          final ChannelPlannerState s = await _present(
            tester,
            window: window,
            theme: theme(),
          );
          _fullest(s, band);
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0);
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
          // The number the lesson is about sits on the stage.
          expect(
            find.descendant(
              of: find.byKey(PresenterLayout.stageKey),
              matching: find.text('Largest contention domain'),
            ),
            findsOneWidget,
          );
        });
      }
    }
  }

  testWidgets('R resets, Up and Down step the channel width', (
    WidgetTester tester,
  ) async {
    final ChannelPlannerState s = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    expect(s.width, 40);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(s.width, 80);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();
    expect(s.width, 20);
    // Already the narrowest: nothing happens.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(s.width, 20);

    s.addAp();
    await tester.pump();
    expect(s.apCount, 7);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(s.apCount, 6);
    expect(s.width, 40);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the phone readouts stay off the presenter panel; folds open', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    expect(find.text('This plan'), findsNothing);
    expect(find.textContaining('A greedy teaching heuristic'), findsNothing);
    await tester.tap(find.textContaining('When an AP defers'));
    await tester.pump();
    expect(find.textContaining('Levels are per 20 MHz'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
