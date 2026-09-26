// Presenter-mode test for Power Save (spec 00 "Done means"): no overflow and
// no page scroll at 1920x1080, 1440x900 and 1470x923 in both themes, in its
// fullest state (two modes, U-APSD vs TWT, with group frames missed), and
// the keys it has: Right slides the window, R returns it to the start, Up
// and Down change the DTIM period. There is no clock, so no Play.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/power_save_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/power_save_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<PowerSaveController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  final PowerSaveController c = PowerSaveController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: PowerSaveScreen(controller: c),
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
          'two modes fit with no overflow and no scroll', (
        WidgetTester tester,
      ) async {
        final PowerSaveController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        c.mode = PsMode.uapsd;
        c.compare = PsMode.twt;
        await tester.pumpAndSettle();
        expect(c.runs, hasLength(2));
        expect(c.runs.any((PsRun r) => r.groupMissed > 0), isTrue);
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
        expect(controlsOverflow(tester), 0);
        expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        // Time awake, the lesson's number, is on the stage for both modes.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.textContaining(': time awake'),
          ),
          findsNWidgets(2),
        );
      });
    }
  }

  testWidgets('Right slides the window, R returns it, Up and Down set DTIM', (
    WidgetTester tester,
  ) async {
    final PowerSaveController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    expect(c.startUs, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.startUs, c.view.spanUs / 4);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.startUs, 0);

    final int dtim = c.config.dtimPeriod;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.config.dtimPeriod, dtim + 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();
    expect(c.config.dtimPeriod, dtim - 1);
    // No clock: Space does nothing and nothing breaks.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
