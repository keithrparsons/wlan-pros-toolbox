// Presenter-mode test for Body Loss (spec 00 "Done means": a presenter test
// with no overflow and no page scroll; spec 34: Left and Right rotate the
// holder, Space toggles the crowd, R resets). Held at 1920x1080, 1440x900
// and 1470x923 in both themes, in the fullest state. Nothing animates, so
// Space and Right are this tool's crowd and turn keys, and the shortcut list
// says so rather than "Play or pause" and "Step".

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/body_loss_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/body_loss_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/body_loss_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<BodyLossController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(theme: theme ?? AppTheme.dark(), home: const BodyLossScreen()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<BodyLossStage>(find.byType(BodyLossStage).last)
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
      // A 13/15-inch MacBook Air in full screen, measured 2026-09-26.
      Size(1470, 923),
    ]) {
      testWidgets('$name ${window.width.toInt()}x${window.height.toInt()}: '
          'fullest state fits with no overflow and no scroll', (
        WidgetTester tester,
      ) async {
        final BodyLossController k = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        k
          ..setBand(WifiBand.band6)
          ..setCrowdSize(50)
          ..setHolderLoss(20)
          ..setPerPersonLoss(10)
          ..setRevealed(true);
        for (final bool occupied in <bool>[true, false]) {
          k
            ..setOccupied(occupied)
            ..backToAp();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'occupied $occupied');
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0, reason: 'occupied $occupied');
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        }
        // The readouts and the prediction are on the stage.
        for (final String t in <String>[
          'Loss from the holder  ',
          'Loss from the crowd  ',
          'Empty vs occupied  ',
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

  testWidgets('Left and Right turn the holder, Space toggles the crowd, Up '
      'and Down change its size, R resets', (WidgetTester tester) async {
    final BodyLossController k = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    final double f0 = k.config.facingDeg;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(k.config.facingDeg, closeTo((f0 + 15) % 360, 1e-9));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(k.config.facingDeg, closeTo((f0 - 15) % 360, 1e-9));

    expect(k.config.occupied, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(k.config.occupied, isFalse);
    expect(k.config.crowdLossDb, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(k.config.occupied, isTrue);

    final int n0 = k.config.crowdSize;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(k.config.crowdSize, n0 + 5);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(k.config.crowdSize, n0 - 5);

    k
      ..setBand(WifiBand.band24)
      ..setHolderLoss(17)
      ..setOccupied(false);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pumpAndSettle();
    expect(k.config.band, WifiBand.band5);
    expect(k.config.holderLossDb, BlConfig.defaultHolderLossDb);
    expect(k.config.occupied, isTrue);
    expect(k.config.facingDeg, BlConfig.defaultFacingDeg);
    expect(tester.takeException(), isNull);
  });

  testWidgets('P reveals the answer', (WidgetTester tester) async {
    final BodyLossController k = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
    expect(k.revealed, isTrue);
    expect(find.textContaining('The level drops'), findsOneWidget);
  });

  testWidgets('the shortcut list says what Space and Right do here', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.pumpAndSettle();
    expect(find.text('Empty the room or fill it'), findsOneWidget);
    expect(find.text('Turn the holder clockwise'), findsOneWidget);
    expect(find.text('Turn the holder counterclockwise'), findsOneWidget);
    expect(find.text('Crowd size up'), findsOneWidget);
    expect(find.text('Play or pause'), findsNothing);
    expect(find.text('Step'), findsNothing);
  });

  testWidgets('the phone prose is gone, the illustrative labels stay, and the '
      'fold opens', (WidgetTester tester) async {
    await _present(tester, window: const Size(1920, 1080));
    expect(find.text('What the bodies cost'), findsNothing);
    expect(find.textContaining('Defaults are illustrative'), findsNothing);
    expect(find.text(BlLabels.lossesSection), findsOneWidget);
    expect(find.text(BlLabels.holderLoss), findsOneWidget);
    expect(find.text(BlLabels.perPersonLoss), findsOneWidget);
    expect(find.text(BlLabels.multiplier5), findsNothing);
    await tester.tap(find.text('Band multipliers (illustrative)'));
    await tester.pumpAndSettle();
    expect(find.text(BlLabels.multiplier5), findsOneWidget);
    expect(find.text(BlLabels.multiplier6), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('state set before presenting is still set inside and after', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1920, 1080));
    installFakeWindow();
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const BodyLossScreen()),
    );
    await tester.pumpAndSettle();
    final BodyLossController k = tester
        .widget<BodyLossStage>(find.byType(BodyLossStage))
        .controller;
    k
      ..setHolderLoss(12)
      ..setCrowdSize(44);
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
    final BodyLossController inside = tester
        .widget<BodyLossStage>(find.byType(BodyLossStage).last)
        .controller;
    expect(identical(inside, k), isTrue);
    expect(inside.config.holderLossDb, 12);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PresenterLayout), findsNothing);
    expect(k.config.crowdSize, 44);
  });
}
