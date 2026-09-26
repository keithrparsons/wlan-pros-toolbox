// Presenter-mode test for the Roaming Walk (spec 00 "Done means": no
// overflow, no page scroll, keyboard play and step). Held at 1920x1080,
// 1440x900 and 1470x923 in both themes, mid-walk with six APs, a jumpy
// client and shadowing, and again while drawing a path.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/roaming_walk_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/roaming_walk_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/roaming_walk_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/roaming_walk_engine.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<RoamingWalkController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const RoamingWalkScreen(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<RoamingWalkStage>(find.byType(RoamingWalkStage).last)
      .controller;
}

void _expectFits(WidgetTester tester, Size window) {
  expect(tester.takeException(), isNull);
  expect(pageScrollables(tester), isEmpty);
  expect(controlsOverflow(tester), 0);
  expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
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
      final String size = '${window.width.toInt()}x${window.height.toInt()}';
      testWidgets('$name $size mid-walk: fits with no overflow and no scroll', (
        WidgetTester tester,
      ) async {
        final RoamingWalkController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        c.apCount = kMaxAps;
        c.applyPreset(ClientPreset.jumpy);
        c.shadowSigmaDb = 4;
        c.seek(c.result.durationS * 0.6);
        await tester.pump();
        _expectFits(tester, window);
        // The number the lesson is about sits on the stage.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('Client now'),
          ),
          findsOneWidget,
        );
      });

      testWidgets('$name $size drawing a path: fits', (
        WidgetTester tester,
      ) async {
        final RoamingWalkController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        c.pathPreset = WalkPathPreset.custom;
        c.addWaypoint((x: 5, y: 5));
        c.addWaypoint((x: 40, y: 12));
        await tester.pump();
        expect(c.drawing, isTrue);
        _expectFits(tester, window);
      });
    }
  }

  testWidgets('Space plays and pauses, Right steps, R restarts, Up raises '
      'the trigger', (WidgetTester tester) async {
    final RoamingWalkController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.timeS, kRoamStepSeconds);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isTrue);
    // The clock runs under the presenter route (the controller owns it).
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.timeS, greaterThan(kRoamStepSeconds));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.timeS, 0);

    final double trigger = c.config.triggerDbm;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.config.triggerDbm, trigger + 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();
    expect(c.config.triggerDbm, trigger - 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the phone prose stays off the presenter; folds open', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    expect(find.textContaining('A teaching model: every AP'), findsNothing);
    expect(find.text('What this models, and what it leaves out'), findsNothing);
    await tester.tap(find.text('Roam log and totals'));
    await tester.pump();
    expect(find.text('Roam log'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
