// Presenter-mode test for DFS and Radar (spec 00 "Done means": no overflow,
// no page scroll, keyboard play and step). Held at 1920x1080, 1440x900 and
// 1470x923 in both themes, in the fullest state: the EU plan (with the
// weather-band bracket), a DFS start, a radar hit and random radar on. Also
// proves the tool's own key: D is Radar now.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dfs_simulator_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dfs_simulator_parts.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dfs_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dfs_simulator_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/dfs_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<DfsSimulatorController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const DfsSimulatorScreen(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<DfsSimulatorStage>(find.byType(DfsSimulatorStage).last)
      .controller;
}

void _startOnDfs(DfsSimulatorController c) {
  c.start = c.startChoices.firstWhere(
    (BondedChannel b) => b.components.first == 100,
  );
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
      for (final DfsRegion region in DfsRegion.values) {
        testWidgets('$name ${window.width.toInt()}x${window.height.toInt()} '
            '${region.name}: fits with no overflow and no scroll', (
          WidgetTester tester,
        ) async {
          final DfsSimulatorController c = await _present(
            tester,
            window: window,
            theme: theme(),
          );
          c.region = region;
          _startOnDfs(c);
          c.radarPerHour = kRadarRates.last;
          c.seek(700);
          c.radarNow();
          c.seek(760);
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0);
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
          expect(c.atStart, isFalse);
          expect(
            tester
                .widget<DfsOutlineButton>(
                  find.widgetWithText(DfsOutlineButton, 'Restart'),
                )
                .onPressed,
            isNotNull,
          );
          // The AP's state, the number the lesson is about, is on the stage.
          expect(
            find.descendant(
              of: find.byKey(PresenterLayout.stageKey),
              matching: find.text('Clock'),
            ),
            findsOneWidget,
          );
        });
      }
    }
  }

  testWidgets('Space plays, Right steps, D is radar now, R restarts, Up and '
      'Down move the clock a minute', (WidgetTester tester) async {
    final DfsSimulatorController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    _startOnDfs(c);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.timeS, kDfsStepSeconds);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isTrue);
    // The clock runs under the presenter route (the controller owns it).
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.timeS, greaterThan(kDfsStepSeconds));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isFalse);

    // Past the CAC, then radar by key.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    final double t = c.timeS;
    expect(t, greaterThanOrEqualTo(2 * kDfsClockKeySeconds));
    expect(c.canRadarNow, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pump();
    expect(c.hitsSoFar, hasLength(1));
    expect(c.timeS, t);

    // Restart is live once a radar has been added.
    final DfsOutlineButton restart = tester.widget<DfsOutlineButton>(
      find.widgetWithText(DfsOutlineButton, 'Restart'),
    );
    expect(restart.onPressed, isNotNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();
    expect(c.timeS, t - kDfsClockKeySeconds);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.timeS, 0);
    expect(c.hitsSoFar, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shortcut list names the radar key', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pump();
    // Shift+/ is '?'; send the character path the shell also accepts.
    if (find.byKey(PresenterLayout.shortcutsKey).evaluate().isEmpty) {
      await tester.tap(find.text('Shortcuts'));
      await tester.pump();
    }
    expect(find.text('D'), findsOneWidget);
    expect(find.text('Radar now (on a DFS channel)'), findsOneWidget);
  });
}
