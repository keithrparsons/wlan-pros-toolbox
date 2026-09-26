// Render-proof capture for Band Steering (NOT a golden, NOT a gate). The
// `_render.dart` suffix keeps it out of the default `flutter test` run, so it
// only executes when asked:
//
//   BS_RENDER_OUT=/some/dir \
//     flutter test test/screens/calculators/band_steering_render.dart
//
// The widget tests assert strings, states and that nothing overflows. These
// frames are for looking: the normal screen at 390, 820 and 1280 px and the
// presenter layout at 1470x923, dark and light.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/band_steering_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/band_steering_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import '../../widgets/presenter/presenter_test_support.dart';

final String _outDir =
    Platform.environment['BS_RENDER_OUT'] ?? '/tmp/band-steering-render';

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  bool present = false,
  void Function(BandSteeringController c)? setup,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  installFakeWindow();
  final BandSteeringController c = BandSteeringController();
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: light ? AppTheme.light() : AppTheme.dark(),
        home: BandSteeringScreen(controller: c),
      ),
    ),
  );
  await tester.pump();
  if (present) {
    await tester.tap(find.text('Present'));
    await tester.pump(const Duration(seconds: 1));
  }
  setup?.call(c);
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  final RenderRepaintBoundary boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage();
    final ByteData? bytes = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final File out = File('$_outDir/$slug.png');
    await out.create(recursive: true);
    await out.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
  await tester.pumpWidget(const SizedBox());
  c.dispose();
}

void main() {
  testWidgets('capture', (WidgetTester tester) async {
    void scene(BandSteeringController c) {
      c.profile = ClientProfile.b;
      c.mode = SteeringMode.probeSuppression;
      c.path = WalkPath.apToEdge;
      c.index = 24;
    }

    for (final bool light in <bool>[false, true]) {
      final String mode = light ? 'light' : 'dark';
      for (final double w in <double>[390, 820, 1280]) {
        await _shot(
          tester,
          light: light,
          size: Size(w, 3200),
          slug: 'band-steering-$mode-${w.toInt()}',
          setup: scene,
        );
      }
      await _shot(
        tester,
        light: light,
        size: const Size(1470, 923),
        slug: 'band-steering-presenter-$mode-1470x923',
        present: true,
        setup: scene,
      );
      await _shot(
        tester,
        light: light,
        size: const Size(1470, 923),
        slug: 'band-steering-presenter-refusal-$mode-1470x923',
        present: true,
        setup: (BandSteeringController c) {
          c.mode = SteeringMode.authRefusal;
          c.path = WalkPath.apToEdge;
          c.index = 13;
        },
      );
    }
  });
}
