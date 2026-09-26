// Presenter-mode test for 6 GHz Power and PSD (spec 00 "Done means": a
// presenter test with no overflow and no page scroll). Held at 1920x1080,
// 1440x900 and 1470x923 in both themes, in the fullest state: every US class
// on, in all three views (the spectrum view adds its class picker), plus the
// EU region. Nothing animates, so the keys are the channel width.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/six_ghz_psd_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/six_ghz_psd_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/six_ghz_psd_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/six_ghz_psd_math.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<SixGhzPsdModel> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(theme: theme ?? AppTheme.dark(), home: const SixGhzPsdScreen()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester.widget<SixGhzPsdStage>(find.byType(SixGhzPsdStage).last).model;
}

Future<void> _expectFits(WidgetTester tester, Size window, String why) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: why);
  expect(pageScrollables(tester), isEmpty, reason: why);
  expect(controlsOverflow(tester), 0, reason: why);
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
      // A 13/15-inch MacBook Air in full screen, measured 2026-09-26.
      Size(1470, 923),
    ]) {
      testWidgets('$name ${window.width.toInt()}x${window.height.toInt()}: '
          'fullest state fits with no overflow and no scroll', (
        WidgetTester tester,
      ) async {
        final SixGhzPsdModel m = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        // The default three classes, in headline type.
        await _expectFits(tester, window, 'default');
        for (final PowerClass c in m.regionClasses) {
          m.setShown(c, true);
        }
        m.setExtraLoss(20);
        for (final PsdView v in PsdView.values) {
          m.setView(v);
          for (final int i in <int>[0, 4]) {
            m.setWidthIndex(i);
            await _expectFits(tester, window, 'US all, ${v.name}, width $i');
          }
        }
        m.setRegion(PsdRegion.eu);
        for (final PowerClass c in m.regionClasses) {
          m.setShown(c, true);
        }
        await _expectFits(tester, window, 'EU all');
        // The per-class numbers are on the stage.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.textContaining('At 320 MHz'),
          ),
          findsOneWidget,
        );
      });
    }
  }

  testWidgets('Up and Down step the channel width; nothing else is bound', (
    WidgetTester tester,
  ) async {
    final SixGhzPsdModel m = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    expect(m.widthMHz, 80);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(m.widthMHz, 160);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(m.widthMHz, 320);
    for (int i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.pump();
    expect(m.widthMHz, 20);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(m.widthMHz, 20);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the phone prose is gone and the folds open', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    expect(find.text('What the chart says'), findsNothing);
    expect(find.text('Noise figure'), findsNothing);
    await tester.tap(find.text('Link: distance, walls, noise figure'));
    await tester.pumpAndSettle();
    expect(find.text('Noise figure'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
