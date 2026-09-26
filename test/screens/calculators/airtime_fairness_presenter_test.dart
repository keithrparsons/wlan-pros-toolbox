// Presenter-mode test for Airtime Fairness (spec 00 "Done means"): no
// overflow and no page scroll at 1920x1080, 1440x900 and 1470x923 in both
// themes, in the fullest state (eight clients, Compare, a custom rate open),
// and the round's play / step / reset and the sharing rule by keyboard.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/airtime_fairness_common.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/airtime_fairness_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<AirtimeFairnessController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  final AirtimeFairnessController c = AirtimeFairnessController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: AirtimeFairnessScreen(controller: c),
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
          'eight clients fit with no overflow and no scroll', (
        WidgetTester tester,
      ) async {
        final AirtimeFairnessController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        for (int i = c.clients.length; i < 8; i++) {
          c.addClient();
        }
        // One custom rate open: the tallest client line.
        c.edit(() => c.clients.last.preset = null);
        c.clients.last.controller.text = '1201';
        c.edit(() {});
        await tester.pumpAndSettle();
        expect(c.clients, hasLength(8));
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
        expect(controlsOverflow(tester), 0);
        expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        // The lesson's numbers are on the stage.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('Airtime fairness, total'),
          ),
          findsOneWidget,
        );
      });
    }
  }

  testWidgets('Space plays and pauses the round, Right steps, R resets, '
      'Up and Down change the sharing rule', (WidgetTester tester) async {
    final AirtimeFairnessController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    expect(c.round.value, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.round.value, 0);
    expect(c.playing, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    final double afterOne = c.round.value;
    expect(afterOne, greaterThan(0));
    expect(afterOne, lessThan(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.round.value, greaterThan(afterOne));

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isTrue);
    expect(find.text('Pause'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isFalse);

    expect(c.view, FairnessView.compare);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.view, FairnessView.airtime);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();
    expect(c.view, FairnessView.packet);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.view, FairnessView.airtime);
    // The edit replays the round; let it finish.
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone-only prose stays off the presenter panel', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    expect(find.textContaining('Plain 802.11 contention gives'), findsNothing);
    expect(find.text('What this models'), findsNothing);
    await tester.tap(find.textContaining('alone on the air'));
    await tester.pump();
    expect(find.textContaining('A: Each turn:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
