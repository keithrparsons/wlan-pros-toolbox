// Presenter-mode test for "PoE: Why the New AP Runs at Half Strength"
// (spec 00 "Done means": no overflow, no page scroll, the keys work). Held
// at 1920x1080, 1440x900 and 1470x923 in both themes, in the fullest state.
// Nothing animates, so Space and Right are relabeled in the shortcut list.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/poe_half_strength_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/poe_half_strength_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/poe_half_strength_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<PoeHalfStrengthController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const PoeHalfStrengthScreen(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<PoeHalfStrengthStage>(find.byType(PoeHalfStrengthStage).last)
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
      Size(1470, 923),
    ]) {
      testWidgets('$name ${window.width.toInt()}x${window.height.toInt()}: '
          'every state fits with no overflow and no scroll', (
        WidgetTester tester,
      ) async {
        final PoeHalfStrengthController k = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        for (final PhPort p in PhPort.values) {
          k
            ..setPort(p)
            ..setAtMode(PhAtMode.twoAt4x4)
            ..setRevealed(true);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: p.standard);
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0, reason: p.standard);
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        }
        for (final String t in <String>[
          'Radios live  ',
          'Power light  ',
          'Predict, then reveal',
        ]) {
          expect(
            find.descendant(
              of: find.byKey(PresenterLayout.stageKey),
              matching: find.text(t),
            ),
            findsOneWidget,
            reason: t,
          );
        }
      });
    }
  }

  testWidgets('Up, Down and Right step the port; 1 2 3 pick it; Space '
      'switches the 802.3at choice; P reveals; R resets', (
    WidgetTester tester,
  ) async {
    final PoeHalfStrengthController k = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    expect(k.config.port, PhPort.at);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(k.config.port, PhPort.bt);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(k.config.port, PhPort.bt, reason: 'no wrap');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(k.config.port, PhPort.af);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(k.config.port, PhPort.at);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    expect(k.config.port, PhPort.bt);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(k.config.port, PhPort.af);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pump();
    expect(k.config.port, PhPort.at);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(k.config.atMode, PhAtMode.twoAt4x4);
    expect(k.config.streamsLive, 8);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(k.revealed, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pumpAndSettle();
    expect(k.config, const PhConfig());
    expect(k.revealed, isFalse);
    expect(tester.takeException(), isNull);
  });
}
