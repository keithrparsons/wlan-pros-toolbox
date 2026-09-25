// Render-proof capture for Fourier and FFT part 2 (NOT a golden, NOT a gate).
// The `_render.dart` suffix keeps it out of the default `flutter test` run:
//
//   flutter test test/screens/calculators/fourier_fft_part2_render.dart
//
// The widget tests assert strings, states and no overflow. They cannot say
// whether the waterfalls read, whether the lime sweep diagonal shows on the
// rainbow, or whether the sincs' zeros line up visibly. These frames are for
// looking, dark and light, at 390 and 1280 px.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fourier_fft_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fourier_fft_ofdm_state.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fourier_fft_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fourier_fft_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/fourier_ofdm.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _outDir =
    '/Users/keithparsons/myPKA/Deliverables/'
    '2026-09-25-wifi-lab-cleanroom/evidence/fourier-part2';

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  required FourierMode mode,
  void Function(FourierLabModel m)? setup,
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
        home: FourierFftScreen(initialMode: mode),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final FourierLabModel m = tester
      .widget<FourierStage>(find.byType(FourierStage))
      .model;
  setup?.call(m);
  await tester.pump();
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
  // Leave no playback running into the next frame.
  if (m.race.animating) m.race.setProgress(1);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('capture', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      final String t = light ? 'light' : 'dark';
      await _shot(
        tester,
        light: light,
        size: const Size(390, 4600),
        slug: 'race_default_${t}_390',
        mode: FourierMode.race,
      );
      await _shot(
        tester,
        light: light,
        size: const Size(1280, 3000),
        slug: 'race_default_${t}_1280',
        mode: FourierMode.race,
      );
      await _shot(
        tester,
        light: light,
        size: const Size(390, 4800),
        slug: 'ofdm_teaching_${t}_390',
        mode: FourierMode.ofdm,
      );
      await _shot(
        tester,
        light: light,
        size: const Size(1280, 3600),
        slug: 'ofdm_teaching_${t}_1280',
        mode: FourierMode.ofdm,
      );
    }
    await _shot(
      tester,
      light: false,
      size: const Size(390, 1600),
      slug: 'race_10khz_dark_390',
      mode: FourierMode.race,
      setup: (FourierLabModel m) => m.race.setRbw(10e3),
    );
    await _shot(
      tester,
      light: false,
      size: const Size(390, 1600),
      slug: 'race_1mhz_1s_dark_390',
      mode: FourierMode.race,
      setup: (FourierLabModel m) {
        m.race.setRbw(1e6);
        m.race.setRunSeconds(1);
      },
    );
    await _shot(
      tester,
      light: false,
      size: const Size(390, 1600),
      slug: 'race_midplay_dark_390',
      mode: FourierMode.race,
      setup: (FourierLabModel m) {
        m.race.startRun();
        m.race.setProgress(0.45);
      },
    );
    await _shot(
      tester,
      light: false,
      size: const Size(390, 2000),
      slug: 'ofdm_he_allon_gi32_dark_390',
      mode: FourierMode.ofdm,
      setup: (FourierLabModel m) {
        m.ofdm.allOn();
        m.ofdm.setNumerology(OfdmNumerology.he);
        m.ofdm.setGuard(3.2e-6);
      },
    );
    await _shot(
      tester,
      light: true,
      size: const Size(1280, 2200),
      slug: 'ofdm_real_he_light_1280',
      mode: FourierMode.ofdm,
      setup: (FourierLabModel m) {
        m.ofdm.setView(OfdmView.real);
        m.ofdm.setNumerology(OfdmNumerology.he);
      },
    );
    await _shot(
      tester,
      light: false,
      size: const Size(390, 2000),
      slug: 'ofdm_real_legacy_dark_390',
      mode: FourierMode.ofdm,
      setup: (FourierLabModel m) => m.ofdm.setView(OfdmView.real),
    );
    await _shot(
      tester,
      light: false,
      size: const Size(390, 2000),
      slug: 'ofdm_empty_dark_390',
      mode: FourierMode.ofdm,
      setup: (FourierLabModel m) => m.ofdm.allOff(),
    );
  });
}
