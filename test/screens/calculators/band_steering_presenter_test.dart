// Presenter-mode test for Band Steering (spec 00 "Done means"): no overflow
// and no page scroll at 1920x1080, 1440x900 and 1470x923 in both themes, in
// its fullest state (Client C with its driver switch, authentication refusal
// with the tolerance slider live, the question revealed), and its keys:
// Space walks or pauses, Right steps 1 m, R resets, Up and Down move the
// client 5 m (spec 38).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/band_steering_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/band_steering_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<BandSteeringController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  final BandSteeringController c = BandSteeringController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: BandSteeringScreen(controller: c),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return c;
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
      testWidgets('$name ${window.width.toInt()}x${window.height.toInt()}: '
          'fits with no overflow and no scroll', (WidgetTester tester) async {
        final BandSteeringController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        c.profile = ClientProfile.c;
        c.mode = SteeringMode.authRefusal;
        c.path = WalkPath.apToEdge;
        c.index = 34;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
        expect(controlsOverflow(tester), 0);
        expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        // The band and the reason are on the stage.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('Client C is on'),
          ),
          findsOneWidget,
        );

        // The question asked, then revealed.
        c.ask();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(controlsOverflow(tester), 0);
        expect(find.text('Reveal'), findsOneWidget);
        c.guess = BsGuess.no;
        c.reveal();
        await tester.pump(kBsStepDuration * 60);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
        expect(controlsOverflow(tester), 0);
      });
    }
  }

  testWidgets('Space walks, Right steps 1 m, R resets, Up and Down move 5 m', (
    WidgetTester tester,
  ) async {
    final BandSteeringController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isTrue);
    await tester.pump(kBsStepDuration * 2);
    expect(c.index, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.index, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.index, 1);
    expect(c.step.distanceM, 54);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.index, 6);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    // The start of the walk: Down stops there.
    expect(c.index, 0);
    expect(tester.takeException(), isNull);
  });
}
