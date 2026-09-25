// Render-proof capture for the Rate Adaptation screen (NOT a golden, NOT a
// gate). The `_render.dart` suffix keeps it out of the default `flutter test`
// run, so it only executes when asked:
//
//   flutter test test/screens/calculators/rate_adaptation_render.dart
//
// WHAT IT IS FOR. The widget tests assert strings, states and that nothing
// overflows. They cannot say whether the attempts strip reads at phone width,
// whether the chart's step line and labels collide, or whether the table's
// hues sit well on a light card. These frames are for looking: dark and
// light, 390 and 1280 px, mid walk-away with retries in the strip, plus the
// fresh state.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_adaptation_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_adaptation_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_adaptation_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/rate_adaptation_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _outDir =
    '/Users/keithparsons/myPKA/Deliverables/'
    '2026-09-25-wifi-lab-cleanroom/evidence/rate-adaptation';

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  required double atUs,
  RaPath path = RaPath.walk,
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
        home: const RateAdaptationScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final RateAdaptationController c = tester
      .widget<RateAdaptationStage>(find.byType(RateAdaptationStage))
      .controller;
  c.path = path;
  if (atUs > 0) c.advanceBy(atUs);
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
        size: const Size(390, 3000),
        slug: 'walk_6s_${mode}_390',
        atUs: 6e6,
      );
      await _shot(
        tester,
        light: light,
        size: const Size(1280, 2000),
        slug: 'walk_14s_${mode}_1280',
        atUs: 14e6,
      );
    }
    await _shot(
      tester,
      light: false,
      size: const Size(390, 3000),
      slug: 'fresh_dark_390',
      atUs: 0,
    );
    await _shot(
      tester,
      light: false,
      size: const Size(390, 3000),
      slug: 'fading_4s_dark_390',
      atUs: 4e6,
      path: RaPath.fading,
    );
  });
}
