// Presenter-mode test for the Heat Map Builder (spec 00 "Done means": no
// overflow, no page scroll, keyboard actions). Held at 1920x1080, 1440x900
// and 1470x923 in both themes in the fullest state (a 1 m grid, noise and
// averaging, the lesson banner, an inspected cell, the revealed wall on the
// error map, and the spacing experiment's plot on the stage), and again with
// the worked-example fold open.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/heat_map_builder_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/heat_map_builder_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/heat_map_builder_engine.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<HeatMapBuilderController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  final HeatMapBuilderController c = HeatMapBuilderController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: HeatMapBuilderScreen(controller: c),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return c;
}

void _expectFits(WidgetTester tester, Size window) {
  expect(tester.takeException(), isNull);
  expect(pageScrollables(tester), isEmpty);
  expect(controlsOverflow(tester), 0);
  expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
}

/// Everything on at once.
Future<void> _fullest(WidgetTester tester, HeatMapBuilderController c) async {
  c.startLesson();
  c.nextReveal();
  c.nextReveal();
  c.spacingM = 1;
  c.useGrid();
  c.sigmaDb = 6;
  c.averaging = 9;
  c.inspect((x: 30, y: 22));
  c.runExperiment();
  await tester.pump();
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
      // A 13/15-inch MacBook Air in full screen (spec 00 adoption notes).
      Size(1470, 923),
    ]) {
      final String size = '${window.width.toInt()}x${window.height.toInt()}';
      testWidgets('$name $size fullest state: fits with no overflow and no '
          'scroll', (WidgetTester tester) async {
        final HeatMapBuilderController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        await _fullest(tester, c);
        expect(c.experiment, hasLength(3));
        expect(c.lesson, HmLessonStep.wallRevealed);
        _expectFits(tester, window);
        // The numbers the lesson is about sit on the stage.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('Root mean square error (RMSE)'),
          ),
          findsOneWidget,
        );
      });

      testWidgets('$name $size fresh (empty floor): fits', (
        WidgetTester tester,
      ) async {
        await _present(tester, window: window, theme: theme());
        _expectFits(tester, window);
      });
    }
  }

  testWidgets('Space takes the samples again, R resets, Up and Down move the '
      'guess range, P, E, W and N do their jobs', (WidgetTester tester) async {
    final HeatMapBuilderController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    c.useGrid();
    c.sigmaDb = 4;
    await tester.pump();
    final int seed = c.noise.seed;
    final double before = c.samples.first.dbm;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.noise.seed, seed + 1);
    expect(c.samples.first.dbm, isNot(before));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.settings.guessRangeM, kHmDefaultGuessRangeM + 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.settings.guessRangeM, kHmDefaultGuessRangeM - 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(c.settings.power, 4);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(c.view, HmView.truth);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.pump();
    expect(c.wallRevealed, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(c.lesson, HmLessonStep.predict);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.points, isEmpty);
    expect(c.settings, const HmSettings());
    expect(c.wallRevealed, isFalse);
    expect(c.lesson, HmLessonStep.off);
    expect(tester.takeException(), isNull);
  });

  testWidgets('state set before presenting is still set inside and after', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1440, 900));
    installFakeWindow();
    final HeatMapBuilderController c = HeatMapBuilderController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: HeatMapBuilderScreen(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    c.useWalk();
    c.power = 4;
    await tester.pump();
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
    expect(c.layout, HmLayout.walk);
    expect(c.settings.power, 4);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PresenterLayout), findsNothing);
    expect(c.layout, HmLayout.walk);
    expect(c.settings.power, 4);
  });

  for (final String fold in <String>[
    'Worked example: three samples',
    'Noise, the floor, and inspecting by keyboard',
  ]) {
    testWidgets('the "$fold" fold opens without an exception', (
      WidgetTester tester,
    ) async {
      await _present(tester, window: const Size(1440, 900));
      await tester.tap(find.text(fold));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(pageScrollables(tester), isEmpty);
    });
  }

  testWidgets('the phone prose stays off the presenter', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    expect(find.text('What this models, and what it leaves out'), findsNothing);
    expect(find.textContaining('Only the lime dots are measurements'), findsNothing);
  });
}
