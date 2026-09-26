// Presenter-mode test for the Survey Walk (spec 00 "Done means": no
// overflow, no page scroll, keyboard play, step, reset and the main slider).
// Held at 1920x1080, 1440x900 and 1470x923 in both themes: mid-walk with
// the signal layer on and priority hopping, with Active chosen (its five
// limits replace the channel strip on the stage), and while drawing a path.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/survey_walk_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/survey_walk_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/survey_walk_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/survey_walk_engine.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<SurveyWalkController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const SurveyWalkScreen(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<SurveyWalkStage>(find.byType(SurveyWalkStage).last)
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
      Size(1470, 923),
    ]) {
      final String size = '${window.width.toInt()}x${window.height.toInt()}';
      testWidgets('$name $size mid-walk with the signal layer: fits', (
        WidgetTester tester,
      ) async {
        final SurveyWalkController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        c.radios = 3;
        c.algorithm = HoppingAlgorithm.priority;
        c.doorPause = true;
        c.showSignal = true;
        c.seek(c.result.durationS * 0.6);
        await tester.pump();
        _expectFits(tester, window);
        // The number the lesson is about sits on the stage.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('Spacing, ch 36'),
          ),
          findsOneWidget,
        );
      });

      testWidgets('$name $size active with its limits open: fits', (
        WidgetTester tester,
      ) async {
        final SurveyWalkController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        c.surveyType = SurveyType.active;
        c.seek(10);
        await tester.pump();
        _expectFits(tester, window);
        // The five limits sit on the stage, in place of the channel strip.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('A single AP at a time'),
          ),
          findsOneWidget,
        );
      });

      testWidgets('$name $size drawing a path: fits', (
        WidgetTester tester,
      ) async {
        final SurveyWalkController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        c.pathPreset = SurveyPathPreset.custom;
        c.addWaypoint((x: 5, y: 5));
        c.addWaypoint((x: 40, y: 12));
        await tester.pump();
        expect(c.drawing, isTrue);
        _expectFits(tester, window);
      });
    }
  }

  testWidgets('Space plays and pauses, Right steps, R restarts, Up and Down '
      'change the pace', (WidgetTester tester) async {
    final SurveyWalkController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.timeS, kSurveyStepSeconds);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.timeS, greaterThan(kSurveyStepSeconds));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.timeS, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.config.paceMps, closeTo(1.5, 1e-9));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.config.paceMps, closeTo(1.3, 1e-9));
  });

  testWidgets('state set before presenting is kept inside and after', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1920, 1080));
    installFakeWindow();
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const SurveyWalkScreen()),
    );
    await tester.pumpAndSettle();
    final SurveyWalkController c = tester
        .widget<SurveyWalkStage>(find.byType(SurveyWalkStage))
        .controller;
    c.radios = 2;
    c.guessRangeM = 8;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
    final SurveyWalkController inside = tester
        .widget<SurveyWalkStage>(find.byType(SurveyWalkStage).last)
        .controller;
    expect(inside, same(c));
    expect(inside.config.scanner.radios, 2);
    expect(inside.config.guessRangeM, 8);
  });
}
