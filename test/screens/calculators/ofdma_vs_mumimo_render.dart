// Render-proof capture for OFDMA vs MU-MIMO (NOT a golden, NOT a gate). The
// `_render.dart` suffix keeps it out of the default `flutter test` run:
//
//   flutter test test/screens/calculators/ofdma_vs_mumimo_render.dart
//
// WHAT IT IS FOR. The widget tests assert strings, states and that nothing
// overflows. They cannot say whether the beams read, whether the badges wrap
// cleanly or whether a label breaks mid-word. These frames are for looking:
// dark and light, phone, desktop and presenter.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ofdma_vs_mumimo_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ofdma_vs_mumimo_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/mu_mimo_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import '../../widgets/presenter/presenter_test_support.dart';

// RENDER_OUT overrides the folder, so a re-render can sit beside the
// frames an earlier gate looked at instead of replacing them.
final String _outDir =
    Platform.environment['RENDER_OUT'] ??
    '/Users/keithparsons/myPKA/Deliverables/'
        '2026-09-29-classroom-eight-features/renders-ofdma-vs-mumimo';

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  required MuPreset preset,
  bool present = false,
  void Function(OfdmaVsMumimoController c)? edit,
}) async {
  final OfdmaVsMumimoController c = OfdmaVsMumimoController(preset: preset);
  addTearDown(c.dispose);
  final GlobalKey key = GlobalKey();
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  if (present) {
    setWindow(tester, size);
    installFakeWindow();
  }
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: light ? AppTheme.light() : AppTheme.dark(),
        home: OfdmaVsMumimoScreen(controller: c),
      ),
    ),
  );
  await tester.pumpAndSettle();
  edit?.call(c);
  await tester.pumpAndSettle();
  if (present) {
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
  }
  final RenderRepaintBoundary boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(
      pixelRatio: present ? 1.0 : 2.0,
    );
    final ByteData? bytes = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final File out = File('$_outDir/$slug.png');
    await out.create(recursive: true);
    await out.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
  // Leave presenter mode so the next pumpWidget starts clean.
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  testWidgets('capture', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      final String mode = light ? 'light' : 'dark';
      await _shot(
        tester,
        light: light,
        size: const Size(390, 3600),
        slug: 'spread_big_${mode}_390',
        preset: MuPreset.spreadBig,
        edit: (OfdmaVsMumimoController c) => c.toggleWorking(),
      );
      await _shot(
        tester,
        light: light,
        size: const Size(1280, 2600),
        slug: 'bunched_${mode}_1280',
        preset: MuPreset.bunched,
      );
      await _shot(
        tester,
        light: light,
        size: const Size(1920, 1080),
        slug: 'presenter_spread_big_${mode}_1920x1080',
        preset: MuPreset.spreadBig,
        present: true,
      );
      await _shot(
        tester,
        light: light,
        size: const Size(1440, 900),
        slug: 'presenter_one_far_reflection_${mode}_1440x900',
        preset: MuPreset.oneFar,
        present: true,
        edit: (OfdmaVsMumimoController c) => c.setReflection(true),
      );
    }
    await _shot(
      tester,
      light: false,
      size: const Size(1470, 923),
      slug: 'presenter_tiny_frames_dark_1470x923',
      preset: MuPreset.tinyFrames,
      present: true,
    );
    await _shot(
      tester,
      light: false,
      size: const Size(820, 2600),
      slug: 'too_many_clients_dark_820',
      preset: MuPreset.spreadBig,
      edit: (OfdmaVsMumimoController c) => c.setAntennas(3),
    );
  });
}
