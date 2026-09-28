// Presenter-mode test for How to Measure Wall Attenuation (spec 00 "Done
// means": no overflow and no page scroll at 1920x1080, 1440x900 and
// 1470x923 in both themes; the tool's keys). Nothing animates, so Space and
// Right are this tool's take-readings and move keys.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/measure_wall_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/measure_wall_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/measure_wall_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<MeasureWallController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const MeasureWallScreen(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<MeasureWallStage>(find.byType(MeasureWallStage).last)
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
          'fullest state fits with no overflow and no scroll', (
        WidgetTester tester,
      ) async {
        final MeasureWallController k = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        k
          ..setRevealed(true)
          ..setSamples(30)
          ..setSpread(6);
        for (final MwSide side in MwSide.values) {
          k.setSide(side);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$side');
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0, reason: '$side');
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        }
        for (final String t in <String>[
          'Measured wall attenuation',
          'True wall loss',
          'Free-space error',
          'Fading residual',
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

  testWidgets('Right and Left move the laptop across the wall, Space takes '
      'new readings, S switches sides, Up and Down move the source, P '
      'reveals, R resets', (WidgetTester tester) async {
    final MeasureWallController k = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    final double g0 = k.config.nearGapM;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(k.config.nearGapM, closeTo(g0 - 0.1, 1e-9));
    for (int i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.pump();
    expect(k.config.side, MwSide.far);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    final List<double> far = k.config.farSeries.samplesDbm;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(k.config.farSeries.samplesDbm, isNot(far));

    final MwSide s0 = k.config.side;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    expect(k.config.side, isNot(s0));

    final double d0 = k.config.sourceToWallM;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(k.config.sourceToWallM, closeTo(d0 + 0.5, 1e-9));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(k.config.sourceToWallM, closeTo(d0 - 0.5, 1e-9));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(k.revealed, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(k.revealed, isFalse);
    expect(k.config.sourceToWallM, MwConfig.defaultSourceToWallM);
    expect(k.config.side, MwSide.near);
  });
}
