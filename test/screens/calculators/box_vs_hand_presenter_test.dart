// Presenter-mode test for The Number on the Box vs the Number in Your Hand
// (spec 00 "Done means": no overflow and no page scroll at projector sizes;
// Right and Left walk the steps, Space jumps between the box and the hand,
// Up and Down change the client, R resets). Held at 1920x1080, 1440x900 and
// 1470x923 in both themes, in the fullest state.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/box_vs_hand_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/box_vs_hand_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/box_vs_hand_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<BoxVsHandController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(theme: theme ?? AppTheme.dark(), home: const BoxVsHandScreen()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<BoxVsHandStage>(find.byType(BoxVsHandStage).last)
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
          'every step fits with no overflow and no scroll', (
        WidgetTester tester,
      ) async {
        final BoxVsHandController k = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        for (final BvhStep s in BvhStep.values) {
          for (final double d in <double>[5, 60]) {
            k
              ..setStep(s)
              ..setClient(BvhClient.reference4)
              ..setDistance(d);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$s $d');
            expect(pageScrollables(tester), isEmpty);
            expect(controlsOverflow(tester), 0, reason: '$s $d');
            expectOnScreen(
              tester,
              find.byKey(PresenterLayout.stageKey),
              window,
            );
          }
        }
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('Show the next step (Right)'),
          ),
          findsOneWidget,
        );
      });
    }
  }

  testWidgets('Right and Left walk the steps, Space jumps, Up and Down change '
      'the client, R resets', (WidgetTester tester) async {
    final BoxVsHandController k = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    expect(k.step, BvhStep.box);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(k.step, BvhStep.bestCase);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(k.step, BvhStep.atDistance, reason: 'stops at the last step');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(k.step, BvhStep.bestCase);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(k.step, BvhStep.atDistance);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(k.step, BvhStep.box);

    expect(k.client, BvhClient.phone2x2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(k.client, BvhClient.laptop2x2);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();
    expect(k.client, BvhClient.reference4);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(k.client, BvhClient.reference4, reason: 'clamped at the end');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(k.client, BvhClient.laptop2x2);

    k
      ..setDistance(30)
      ..setWidth(80)
      ..setStep(BvhStep.atDistance);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pumpAndSettle();
    expect(k.step, BvhStep.box);
    expect(k.client, BvhClient.phone2x2);
    expect(k.distanceM, BoxVsHand.defaultDistanceM);
    expect(k.widthMHz, BoxVsHand.defaultWidthMHz);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shortcut list says what Space, Right and Left do here', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.pumpAndSettle();
    expect(find.text('Jump between the box and the hand'), findsOneWidget);
    expect(find.text('Show the next step'), findsOneWidget);
    expect(find.text('Show the step before'), findsOneWidget);
    expect(find.text('Client up'), findsOneWidget);
    expect(find.text('Play or pause'), findsNothing);
    expect(find.text('Step'), findsNothing);
  });

  testWidgets('the phone prose is gone and the key hints are on the labels', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    expect(find.textContaining('2x2 means two antennas'), findsNothing);
    expect(
      find.text('Client, phone and laptop 2x2 (Up, Down)'),
      findsOneWidget,
    );
    expect(find.text('Reset (R)'), findsOneWidget);
  });

  testWidgets('state set before presenting is still set inside and after', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1920, 1080));
    installFakeWindow();
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const BoxVsHandScreen()),
    );
    await tester.pumpAndSettle();
    final BoxVsHandController k = tester
        .widget<BoxVsHandStage>(find.byType(BoxVsHandStage))
        .controller;
    k
      ..setClient(BvhClient.laptop2x2)
      ..setDistance(12)
      ..setStep(BvhStep.atDistance);
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
    final BoxVsHandController inside = tester
        .widget<BoxVsHandStage>(find.byType(BoxVsHandStage).last)
        .controller;
    expect(identical(inside, k), isTrue);
    expect(inside.client, BvhClient.laptop2x2);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PresenterLayout), findsNothing);
    expect(k.distanceM, 12);
    expect(k.step, BvhStep.atDistance);
  });
}
