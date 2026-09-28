// Presenter-mode test for Why a Busy Line Lags (spec 00 "Done means"): no
// overflow and no page scroll at 1920x1080, 1440x900 and 1470x923 in both
// themes, on every line with SQM off and on, and its keys: Space plays,
// Right steps one second, Up turns SQM on and Down off, Q switches it, R
// resets.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/latency_under_load_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/latency_under_load_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<LatencyUnderLoadController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  final LatencyUnderLoadController c = LatencyUnderLoadController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: LatencyUnderLoadScreen(controller: c),
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
        final LatencyUnderLoadController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        for (final LulLine l in LulLine.values) {
          for (final bool on in <bool>[false, true]) {
            c.line = l;
            c.sqm = on;
            c.seek(10);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(pageScrollables(tester), isEmpty);
            expect(controlsOverflow(tester), 0);
            expectOnScreen(
              tester,
              find.byKey(PresenterLayout.stageKey),
              window,
            );
          }
        }
        // The headline number is on the stage.
        c.line = LulLine.cable;
        c.sqm = false;
        c.seek(2);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('225 ms'),
          ),
          findsOneWidget,
        );
      });
    }
  }

  testWidgets('Space plays, Right steps, Up and Down switch SQM, Q toggles, '
      'R resets', (WidgetTester tester) async {
    final LatencyUnderLoadController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(c.timeS.value, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isFalse);

    final double at = c.timeS.value;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.timeS.value, closeTo(at + kLulStepS, 1e-9));

    expect(c.config.sqm, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.config.sqm, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.config.sqm, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pump();
    expect(c.config.sqm, isTrue);

    c.line = LulLine.dsl;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.config, const LulConfig());
    expect(c.timeS.value, kLulRunS);
    expect(tester.takeException(), isNull);
  });
}
