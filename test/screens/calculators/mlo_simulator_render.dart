// Render-proof capture for the Multi-Link Operation screen (NOT a golden,
// NOT a gate). The `_render.dart` suffix keeps it out of the default
// `flutter test` run, so it only executes when asked:
//
//   flutter test test/screens/calculators/mlo_simulator_render.dart
//
// WHAT IT IS FOR. The widget tests assert strings, states and that nothing
// overflows. They cannot say whether the lanes read at phone width, whether
// the histogram labels collide, or whether the link hues sit well on a light
// card. These frames are for looking: dark and light, 390 and 1280 px.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mlo_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mlo_simulator_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mlo_simulator_state.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/mlo_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _outDir =
    '/Users/keithparsons/myPKA/Deliverables/'
    '2026-09-25-wifi-lab-cleanroom/evidence/mlo-simulator';

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  required MloPreset preset,
  MloMode lane = MloMode.str,
  MloWindow window = MloWindow.ms5,
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
        home: MloSimulatorScreen(preset: preset),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final MloSimulatorState s = tester
      .widget<MloSimulatorStage>(find.byType(MloSimulatorStage))
      .state;
  s.laneMode = lane;
  s.window = window;
  s.windowStartUs = startUs;
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
      await _shot(
        tester,
        light: light,
        size: const Size(390, 4200),
        slug: 'equal_str_${mode}_390',
        preset: MloPreset.equal,
        startUs: 20000,
      );
      await _shot(
        tester,
        light: light,
        size: const Size(390, 4200),
        slug: 'slow_link_nstr_${mode}_390',
        preset: MloPreset.slowLink,
        lane: MloMode.nstr,
        startUs: 40000,
      );
      await _shot(
        tester,
        light: light,
        size: const Size(1280, 3600),
        slug: 'switch_cost_emlsr_${mode}_1280',
        preset: MloPreset.switchCost,
        lane: MloMode.emlsr,
        window: MloWindow.ms2,
        startUs: 30000,
      );
    }
  });
}
