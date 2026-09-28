// Presenter-mode tests for the two tools over the shared frame model (spec 00
// "Done means"): Down the Stack and A Frame's Journey fit with no overflow
// and no page scroll at 1920x1080, 1440x900 and 1470x923 in both themes, in
// their fullest states, and their keys do what the help says.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/down_the_stack_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/frame_journey_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/frame_journey_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<void> _present(
  WidgetTester tester,
  Widget screen, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(theme: theme ?? AppTheme.dark(), home: screen),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
}

void _fits(WidgetTester tester, Size window) {
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

      testWidgets('Down the Stack, $name $size: fits on every step and view', (
        WidgetTester tester,
      ) async {
        final DownTheStackController c = DownTheStackController();
        addTearDown(c.dispose);
        await _present(
          tester,
          DownTheStackScreen(controller: c),
          window: window,
          theme: theme(),
        );
        for (int i = 0; i < c.stepCount; i++) {
          c.index = i;
          await tester.pump();
          _fits(tester, window);
        }
        c.ask();
        await tester.pump();
        _fits(tester, window);
        c.guess = DtsGuess.router;
        c.reveal();
        await tester.pump();
        _fits(tester, window);
        c.view = DtsView.addresses;
        for (final DsCase d in DsCase.values) {
          c.dsCase = d;
          await tester.pump();
          _fits(tester, window);
        }
      });

      testWidgets('A Frame\'s Journey, $name $size: fits on every step', (
        WidgetTester tester,
      ) async {
        final FrameJourneyController c = FrameJourneyController();
        addTearDown(c.dispose);
        await _present(
          tester,
          FrameJourneyScreen(controller: c),
          window: window,
          theme: theme(),
        );
        c.corrupt = true;
        c.band = FjBand.ghz24;
        for (int i = 0; i < c.stepCount; i++) {
          c.index = i;
          await tester.pump();
          _fits(tester, window);
        }
        c.ask();
        await tester.pump();
        _fits(tester, window);
        c.reveal();
        await tester.pump();
        _fits(tester, window);
      });
    }
  }

  testWidgets('Down the Stack keys: Space, Right, R, Up and Down, D, V', (
    WidgetTester tester,
  ) async {
    final DownTheStackController c = DownTheStackController();
    addTearDown(c.dispose);
    await _present(
      tester,
      DownTheStackScreen(controller: c),
      window: const Size(1920, 1080),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isTrue);
    await tester.pump(kDtsStepDuration * 2);
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
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.index, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.index, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pump();
    expect(c.view, DtsView.addresses);
    expect(c.dsCase, DsCase.both);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pump();
    expect(c.view, DtsView.journey);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A Frame\'s Journey keys: Space, Right, R, Up and Down, C, B', (
    WidgetTester tester,
  ) async {
    final FrameJourneyController c = FrameJourneyController();
    addTearDown(c.dispose);
    await _present(
      tester,
      FrameJourneyScreen(controller: c),
      window: const Size(1920, 1080),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isTrue);
    await tester.pump(kFhStepDuration * 2);
    expect(c.index, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.index, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.index, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.config.distanceM, kFjDefaultDistanceM + 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.config.distanceM, kFjDefaultDistanceM - 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();
    expect(c.config.corrupt, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(c.config.band, FjBand.ghz6);
    expect(tester.takeException(), isNull);
  });
}
