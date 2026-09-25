// Render-proof capture for the Power Save screen (NOT a golden, NOT a gate).
// The `_render.dart` suffix keeps it out of the default `flutter test` run,
// so it only executes when asked:
//
//   flutter test test/screens/calculators/power_save_render.dart
//
// WHAT IT IS FOR. The widget tests assert strings, states and that nothing
// overflows. They cannot say whether the timeline reads at phone width,
// whether the axis labels collide, or whether the state hues sit well on a
// light card. These frames are for looking: dark and light, 390 and 1280 px,
// comparing legacy PS with TWT.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/power_save_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/power_save_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/power_save_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/power_save_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _outDir =
    '/Users/keithparsons/myPKA/Deliverables/'
    '2026-09-25-wifi-lab-cleanroom/evidence/power-save';

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  required PsConfig config,
  PsMode? compare = PsMode.twt,
  PsView view = PsView.s1,
  double startUs = 0,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: light ? AppTheme.light() : AppTheme.dark(),
        home: PowerSaveScreen(initial: config, compare: compare),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final PowerSaveController c = tester
      .widget<PowerSaveStage>(find.byType(PowerSaveStage))
      .controller;
  c.view = view;
  c.seek(startUs);
  await tester.pumpAndSettle();
  final RenderRepaintBoundary boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
    final ByteData? bytes = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final File out = File('$_outDir/$slug.png');
    await out.create(recursive: true);
    await out.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets('capture', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      final String mode = light ? 'light' : 'dark';
      // Legacy PS vs TWT at 1 s, phone-idle traffic, the 1 s window.
      await _shot(
        tester,
        light: light,
        size: const Size(390, 4600),
        slug: 'legacy_vs_twt_1s_${mode}_390',
        config: const PsConfig(),
      );
      await _shot(
        tester,
        light: light,
        size: const Size(1280, 4000),
        slug: 'legacy_vs_twt_1s_${mode}_1280',
        config: const PsConfig(),
      );
      // Sensor on a 30 s TWT vs legacy PS, 60 s window.
      await _shot(
        tester,
        light: light,
        size: const Size(390, 4600),
        slug: 'sensor_legacy_vs_twt30_60s_${mode}_390',
        config: PsConfig(
          traffic: PsScenario.sensor.traffic,
          twt: const TwtSettings(mantissa: 58594, exponent: 9),
        ),
        view: PsView.s60,
      );
    }
    // Voice call, legacy PS vs U-APSD, 0.3 s window.
    await _shot(
      tester,
      light: false,
      size: const Size(1280, 4000),
      slug: 'voice_legacy_vs_uapsd_dark_1280',
      config: PsConfig(traffic: PsScenario.voice.traffic),
      compare: PsMode.uapsd,
      view: PsView.ms300,
      startUs: 1000000,
    );
  });
}
