// Presenter-mode test for Polarization (spec 45 "Done means" 4; spec 00: no
// overflow, no page scroll, keyboard play). Held at 1920x1080, 1440x900 and
// 1470x923 in both themes, in the fullest state: playing, components on, the
// Adjust fold open, every preset. The wave runs on a clock, so the test
// pumps fixed durations rather than settling.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/polarization_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/polarization_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/polarization_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<PolarizationController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const PolarizationScreen(),
    ),
  );
  await _settle(tester);
  await tester.tap(find.text('Present'));
  await _settle(tester);
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<PolarizationStage>(find.byType(PolarizationStage).last)
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
        final PolarizationController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        c.setShowComponents(true);
        await _settle(tester);
        await tester.tap(
          find.text('Adjust: amplitudes and phase difference').last,
        );
        await _settle(tester);
        for (final PolarizationPreset p in <PolarizationPreset>[
          ...PolarizationPreset.named,
          PolarizationPreset.custom,
        ]) {
          if (p == PolarizationPreset.custom) {
            c.setField(c.state.copyWith(ax: 0.35, deltaDeg: 60));
          } else {
            c.setPreset(p);
          }
          await _settle(tester);
          expect(tester.takeException(), isNull, reason: p.label);
          expect(pageScrollables(tester), isEmpty, reason: p.label);
          expect(controlsOverflow(tester), 0, reason: p.label);
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        }
        // The polarization is on the stage in headline type.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('The tip traces'),
          ),
          findsOneWidget,
        );
        c.setPlaying(false);
        await _settle(tester);
      });
    }
  }

  testWidgets('Space plays and pauses, P and Up step the preset, Down steps '
      'back, R resets the preset and the view', (WidgetTester tester) async {
    final PolarizationController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    // Reduced motion is off in the test binding, so the wave opens running.
    expect(c.playing, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isFalse);
    final double frozen = c.phase;
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.phase, frozen);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.playing, isTrue);
    expect(c.phase, isNot(frozen));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(c.preset, PolarizationPreset.vertical);
    final List<PolarizationPreset> seen = <PolarizationPreset>[];
    for (int i = 0; i < PolarizationPreset.named.length; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.pump();
      seen.add(c.preset);
    }
    expect(seen, <PolarizationPreset>[
      PolarizationPreset.horizontal,
      PolarizationPreset.slant45,
      PolarizationPreset.circular,
      PolarizationPreset.elliptical,
      PolarizationPreset.vertical,
    ]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.preset, PolarizationPreset.horizontal);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.preset, PolarizationPreset.elliptical);

    c.view.value = c.view.value.rotated(40, 10);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.preset, PolarizationPreset.vertical);
    expect(c.view.value, PolarizationController.initialView);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a preset picked on the phone screen is the one presented', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1920, 1080));
    installFakeWindow();
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const PolarizationScreen()),
    );
    await _settle(tester);
    final PolarizationController phone = tester
        .widget<PolarizationStage>(find.byType(PolarizationStage))
        .controller;
    phone.setPreset(PolarizationPreset.circular);
    await _settle(tester);
    await tester.tap(find.text('Present'));
    await _settle(tester);
    final PolarizationController shown = tester
        .widget<PolarizationStage>(find.byType(PolarizationStage).last)
        .controller;
    expect(identical(shown, phone), isTrue);
    expect(
      find.descendant(
        of: find.byKey(PresenterLayout.stageKey),
        matching: find.text('a circle'),
      ),
      findsOneWidget,
    );
    shown.setPlaying(false);
    await _settle(tester);
  });
}
