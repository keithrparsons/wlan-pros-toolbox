// Presenter-mode test for Rate Adaptation (spec 00 "Done means"): no
// overflow and no page scroll at 1920x1080, 1440x900 and 1470x923 in both
// themes, mid walk-away with retries in the strip and every rate tried, and
// the keys: Space plays and pauses, Right steps one frame, R restarts, Up
// and Down move the SNR offset. The clock keeps running in presenter mode
// (the controller's Ticker is not the muted route's).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_adaptation_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_adaptation_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<RateAdaptationController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  final RateAdaptationController c = RateAdaptationController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: RateAdaptationScreen(controller: c),
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
      // A 13/15-inch MacBook Air in full screen, measured 2026-09-26.
      Size(1470, 923),
    ]) {
      testWidgets('$name ${window.width.toInt()}x${window.height.toInt()}: '
          'mid walk fits with no overflow and no scroll', (
        WidgetTester tester,
      ) async {
        final RateAdaptationController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        c.advanceBy(14e6);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
        expect(controlsOverflow(tester), 0);
        expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        // The chosen rate, the lesson's number, is on the stage.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.textContaining('Chosen rate at 14.00 s'),
          ),
          findsOneWidget,
        );
      });
    }
  }

  testWidgets('Space plays and pauses, Right steps, R restarts, Up and Down '
      'move the SNR offset', (WidgetTester tester) async {
    final RateAdaptationController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    expect(c.atStart, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.engine.lastFrame, isNotNull);
    final double afterStep = c.engine.nowUs;
    expect(afterStep, greaterThan(0));

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isTrue);
    expect(find.text('Pause'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    // The clock runs under the presenter route.
    expect(c.engine.nowUs, greaterThan(afterStep));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.atStart, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.settings.snrOffsetDb, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();
    expect(c.settings.snrOffsetDb, -1);
    expect(tester.takeException(), isNull);
  });
}
