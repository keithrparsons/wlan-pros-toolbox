// Presenter-mode test for Wi-Fi Through a Wall (spec 00 "Done means": a
// presenter test with no overflow and no page scroll, and keyboard play
// where the tool has it). Held at 1920x1080, 1440x900 and 1470x923 in both
// themes, in the fullest state: the wave playing, the inside-wavelength view
// on, and a metal wall (which adds the "too small to see" note) as well as
// a thin panel with the angle and TM set. The wave runs on a clock, so the
// test pumps fixed durations rather than settling.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wifi_through_a_wall_parts.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wifi_through_a_wall_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wifi_through_a_wall_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/wall_slab_physics.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

/// Past the presenter route's fade, without waiting on the wave's clock.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<WallSlabController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const WifiThroughAWallScreen(),
    ),
  );
  await _settle(tester);
  await tester.tap(find.text('Present'));
  await _settle(tester);
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<WallSlabStage>(find.byType(WallSlabStage).last)
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
        final WallSlabController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        c
          ..setPlaying(true)
          ..setShowMaterialWavelength(true);
        for (final WallConfig w in const <WallConfig>[
          WallConfig(material: WallMaterial.metal, thicknessMm: 2),
          WallConfig(
            band: WifiBand.band24,
            channel: 11,
            material: WallMaterial.plasterboard,
            thicknessMm: 12.7,
            angleDeg: 80,
            polarization: Polarization.tm,
          ),
          WallConfig(
            band: WifiBand.band6,
            channel: 233,
            material: WallMaterial.chipboard,
            thicknessMm: 500,
          ),
        ]) {
          c.setConfig(w);
          await _settle(tester);
          final String why = '${w.material.name} ${w.thicknessMm} mm';
          expect(tester.takeException(), isNull, reason: why);
          expect(pageScrollables(tester), isEmpty, reason: why);
          expect(controlsOverflow(tester), 0, reason: why);
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        }
        // The loss is on the stage in headline type.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('Through the wall'),
          ),
          findsOneWidget,
        );
        c.setPlaying(false);
        await _settle(tester);
      });
    }
  }

  testWidgets('Space plays and pauses, R returns to the opening wall, Up and '
      'Down change the thickness', (WidgetTester tester) async {
    final WallSlabController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    // Reduced motion is off in the test binding, so the wave opens running.
    expect(c.playing, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isFalse);
    expect(find.text('Play'), findsWidgets);
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

    expect(c.config.thicknessMm, 102);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.config.thicknessMm, greaterThan(102));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();
    expect(c.config.thicknessMm, lessThan(102));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.config, const WallConfig());
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wall set on the phone screen is the wall presented, and the '
      'wave keeps its wavelength inside by default', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1920, 1080));
    installFakeWindow();
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const WifiThroughAWallScreen()),
    );
    await _settle(tester);
    final WallSlabController phone = tester
        .widget<WallSlabStage>(find.byType(WallSlabStage))
        .controller;
    phone.setConfig(
      const WallConfig(material: WallMaterial.brick, thicknessMm: 230),
    );
    await _settle(tester);
    await tester.tap(find.text('Present'));
    await _settle(tester);
    final WallSlabController shown = tester
        .widget<WallSlabStage>(find.byType(WallSlabStage).last)
        .controller;
    expect(identical(shown, phone), isTrue);
    expect(
      find.descendant(
        of: find.byKey(PresenterLayout.stageKey),
        matching: find.textContaining('230 mm brick'),
      ),
      findsOneWidget,
    );
    expect(shown.showMaterialWavelength, isFalse);
    final Finder painter = find.descendant(
      of: find.byKey(PresenterLayout.stageKey),
      matching: find.byWidgetPredicate(
        (Widget w) => w is CustomPaint && w.painter is WallWavePainter,
      ),
    );
    expect(
      (tester.widget<CustomPaint>(painter).painter! as WallWavePainter)
          .showMaterialWavelength,
      isFalse,
    );
    expect(find.textContaining('Frequency never changes.'), findsWidgets);
    shown.setPlaying(false);
    await _settle(tester);
  });
}
