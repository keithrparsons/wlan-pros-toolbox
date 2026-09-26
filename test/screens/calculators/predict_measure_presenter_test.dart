// Presenter-mode test for Predict, Then Measure (spec 00 "Done means": no
// overflow, no page scroll, keyboard actions; spec 32: Space reveals, the
// maps cycle, R resets). Held at 1920x1080, 1440x900 and 1470x923 in both
// themes in the fullest state (a both-sides walk with noise, the model
// updated, the truth revealed, the largest scenario) and fresh, and with
// each fold open.
//
// Spec 32 asks for Tab to cycle the maps. Tab stays the keyboard's way
// between controls in presenter mode (WCAG 2.1.1, and the shell's own
// shortcut list), so the maps are on M; a test below pins that Tab does not
// change the map.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/predict_measure_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/predict_measure_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/predict_measure_engine.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<PredictMeasureController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  final PredictMeasureController c = PredictMeasureController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: PredictMeasureScreen(controller: c),
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

Future<void> _fullest(WidgetTester tester, PredictMeasureController c) async {
  c.preset = PmPreset.office; // the most walls
  c.useBothSidesWalk();
  c.sigmaDb = 3;
  c.updateModel();
  c.revealed = true;
  c.view = PmMapView.difference;
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
        final PredictMeasureController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        await _fullest(tester, c);
        expect(c.revealed, isTrue);
        _expectFits(tester, window);
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('Walls tested'),
          ),
          findsOneWidget,
        );
      });

      testWidgets('$name $size fresh: fits', (WidgetTester tester) async {
        await _present(tester, window: window, theme: theme());
        _expectFits(tester, window);
      });
    }
  }

  testWidgets('Space reveals and hides, M cycles the maps, R resets, U, C, B '
      'and O do their jobs, Up and Down move the noise', (
    WidgetTester tester,
  ) async {
    final PredictMeasureController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.pump();
    expect(c.hasWalk, isTrue);
    expect(c.testedCount, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(c.testedCount, c.walls.length);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.pump();
    expect(c.updatedWalls, hasLength(c.walls.length));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(c.view, PmMapView.measured);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(c.view, PmMapView.predicted, reason: 'no Truth before the reveal');

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.revealed, isTrue);
    expect(c.view, PmMapView.truth);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.revealed, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.sigmaDb, 0.5);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.sigmaDb, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();
    expect(c.hasWalk, isFalse);

    c.useBothSidesWalk();
    c.selectedWall = 3;
    c.predictedLossDb = 30;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.hasWalk, isFalse);
    expect(c.walls[3].predictedLossDb, c.walls[3].material.defaultLossDb);
    expect(c.view, PmMapView.predicted);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tab moves focus and does not change the map', (
    WidgetTester tester,
  ) async {
    final PredictMeasureController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(c.view, PmMapView.predicted);
  });

  testWidgets('the shortcut list says what Space does here', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.pumpAndSettle();
    expect(find.text('Reveal or hide the truth'), findsOneWidget);
    expect(find.text('Play or pause'), findsNothing);
  });

  testWidgets('state set before presenting is still set inside and after', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1440, 900));
    installFakeWindow();
    final PredictMeasureController c = PredictMeasureController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: PredictMeasureScreen(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    c.preset = PmPreset.school;
    c.useBothSidesWalk();
    await tester.pump();
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
    expect(c.preset, PmPreset.school);
    expect(c.testedCount, c.walls.length);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PresenterLayout), findsNothing);
    expect(c.preset, PmPreset.school);
    expect(c.testedCount, c.walls.length);
  });

  for (final String fold in <String>[
    'Wall losses: the design',
    'AP position',
    'Instructor: the hidden truth',
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
    expect(
      find.textContaining('Only the lime dots on the walk are measurements'),
      findsNothing,
    );
  });
}
