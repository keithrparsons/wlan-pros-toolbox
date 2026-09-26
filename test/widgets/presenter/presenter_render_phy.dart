// Render-proof capture of the presenter layout for five Wi-Fi Classroom tools
// (NOT a golden, NOT a gate): Fourier and FFT (all four modes), MIMO and
// Beamforming, Antenna Pattern, PHY Preamble Reference, Spatial Reuse.
// Same pattern as presenter_render.dart; a separate file so the branches
// converting other tools do not all edit one list. The `_render.dart`-style
// name keeps it out of the default `flutter test` run:
//
//   PRESENTER_RENDER_OUT=/some/dir \
//     flutter test test/widgets/presenter/presenter_render_phy.dart
//
// PRESENTER_RENDER_SIZES=all adds 1920x1080 and 1440x900 to the default
// 1470x923 (a MacBook Air in full screen).

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_mesh.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_painters.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fourier_fft_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fourier_fft_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fourier_fft_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mimo_beamforming_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mimo_beamforming_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mimo_beamforming_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/phy_preamble_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/phy_preamble_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/phy_preamble_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/spatial_reuse_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/spatial_reuse_stage.dart';
import 'package:wlan_pros_toolbox/services/audio/tone_engine.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/phy_preamble.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import 'presenter_test_support.dart';

final String _outDir =
    Platform.environment['PRESENTER_RENDER_OUT'] ?? '/tmp/presenter-render';

final List<Size> _sizes =
    Platform.environment['PRESENTER_RENDER_SIZES'] == 'all'
    ? const <Size>[Size(1470, 923), Size(1920, 1080), Size(1440, 900)]
    : const <Size>[Size(1470, 923)];

/// A silent tone voice, so Fourier's Waves mode needs no audio device.
class _SilentVoice implements ToneEngine {
  @override
  Future<ToneEngineStatus> init() async => ToneEngineStatus.ready;
  @override
  ToneEngineStatus get status => ToneEngineStatus.ready;
  @override
  bool get isPlaying => false;
  @override
  Future<void> playTone({required double hz, required ToneWave wave}) async {}
  @override
  Future<void> setFrequency(double hz) async {}
  @override
  Future<void> setWaveform(ToneWave wave) async {}
  @override
  Future<void> setVolume(double zeroToOne) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

Future<void> _shot(
  WidgetTester tester, {
  required Widget screen,
  required bool light,
  required Size size,
  required String slug,
  Future<void> Function()? setup,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  installFakeWindow();
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: light ? AppTheme.light() : AppTheme.dark(),
        home: screen,
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('Present'));
  await tester.pump(const Duration(milliseconds: 600));
  await setup?.call();
  await tester.pump(const Duration(milliseconds: 600));
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
  // ignore: avoid_print
  print(
    '$slug controls overflow ${controlsOverflow(tester)}, '
    'page scrollables ${pageScrollables(tester).length}, '
    'exception ${tester.takeException()}',
  );
  await tester.pumpWidget(const SizedBox());
}

/// `tool-theme-WxH[-case]`, the naming the other presenter frames use.
String _name(String tool, bool light, Size s, [String extra = '']) =>
    '$tool-${light ? 'light' : 'dark'}-'
    '${s.width.toInt()}x${s.height.toInt()}${extra.isEmpty ? '' : '-$extra'}';

void main() {
  testWidgets('spatial reuse', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      for (final Size s in _sizes) {
        for (final double pd in <double>[-82, -70]) {
          await _shot(
            tester,
            screen: const SpatialReuseScreen(),
            light: light,
            size: s,
            slug: _name('spatial-reuse', light, s, 'obsspd${pd.round()}'),
            setup: () async {
              tester
                  .widget<SpatialReuseStage>(find.byType(SpatialReuseStage))
                  .state
                  .setObssPd(pd);
            },
          );
        }
      }
    }
  });

  testWidgets('mimo', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      for (final Size s in _sizes) {
        await _shot(
          tester,
          screen: const MimoBeamformingScreen(),
          light: light,
          size: s,
          slug: _name('mimo-beamforming', light, s),
        );
        await _shot(
          tester,
          screen: const MimoBeamformingScreen(initialApChains: 8),
          light: light,
          size: s,
          slug: _name('mimo-beamforming', light, s, '8x2-sniffer2'),
          setup: () async {
            final MimoController c = tester
                .widget<MimoStage>(find.byType(MimoStage))
                .controller;
            c.snifferChains = 2;
          },
        );
      }
    }
  });

  testWidgets('phy preamble', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      for (final Size s in _sizes) {
        for (final (PpduType t, String block) in <(PpduType, String)>[
          (PpduType.heSu, 'HE-SIG-A'),
          (PpduType.ehtMu, 'U-SIG'),
          (PpduType.vht, 'VHT-SIG-A'),
        ]) {
          await _shot(
            tester,
            screen: PhyPreambleScreen(
              initial: PreambleSettings(type: t),
              initialSelection: block,
            ),
            light: light,
            size: s,
            slug: _name('phy-preamble', light, s, t.name),
          );
        }
        await _shot(
          tester,
          screen: const PhyPreambleScreen(
            initial: PreambleSettings(type: PpduType.ehtMu),
            initialMode: PreambleMode.identify,
          ),
          light: light,
          size: s,
          slug: _name('phy-preamble', light, s, 'walk'),
          setup: () async {
            final PhyPreambleModel m = tester
                .widget<PhyPreambleStage>(find.byType(PhyPreambleStage))
                .model;
            m.revealWalk();
          },
        );
      }
    }
  });

  testWidgets('antenna pattern', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      for (final Size s in _sizes) {
        for (final AntennaModelKind k in <AntennaModelKind>[
          AntennaModelKind.omni,
          AntennaModelKind.directional,
          AntennaModelKind.imported,
        ]) {
          await _shot(
            tester,
            screen: AntennaPatternScreen(initialKind: k),
            light: light,
            size: s,
            slug: _name('antenna-pattern', light, s, k.name),
            setup: () async {
              if (k != AntennaModelKind.imported) return;
              tester
                  .widget<AntennaPatternStage>(find.byType(AntennaPatternStage))
                  .lab
                  .loadExample(PatternExample.tiltedSector);
            },
          );
        }
      }
    }
  });

  testWidgets('fourier', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      for (final Size s in _sizes) {
        for (final FourierMode mode in FourierMode.values) {
          await _shot(
            tester,
            screen: FourierFftScreen(
              initialMode: mode,
              toneEngineFactory: _SilentVoice.new,
            ),
            light: light,
            size: s,
            slug: _name('fourier-fft', light, s, mode.name),
            setup: () async {
              final FourierLabModel m = tester
                  .widget<FourierStage>(find.byType(FourierStage))
                  .model;
              switch (mode) {
                case FourierMode.waves:
                  m.applyPreset(WavePreset.square);
                case FourierMode.fft:
                  m.applyLesson(FftLesson.weakNeighbor);
                case FourierMode.race:
                  break;
                case FourierMode.ofdm:
                  m.ofdm.allOn();
              }
            },
          );
        }
      }
    }
  });

  // Rotation cost at presenter size. One spin frame does what OrbitPainter
  // does: project the 16,380 mesh vertices through the camera, bucket-sort
  // the 16,200 quads, and record one drawVertices. Timed on the Dart side in
  // this (JIT, debug-mode) test process, so a release build is faster; the
  // GPU raster of the recorded picture is not measured here. Also timed: a
  // software raster of a few frames (toImage), an upper bound on raster.
  testWidgets('antenna rotation timing', (WidgetTester tester) async {
    for (final AntennaModelKind k in <AntennaModelKind>[
      AntennaModelKind.directional,
      AntennaModelKind.collinear,
    ]) {
      final AntennaPatternLab lab = AntennaPatternLab(initialKind: k);
      final PatternMesh mesh = lab.mesh!;
      // The 3D viewport's size, measured from the laid-out widgets on
      // 2026-09-26: presenter at 1920x1080 and 1470x923, and the desktop
      // screen (598 x 400) for comparison.
      for (final ui.Size size in const <ui.Size>[
        ui.Size(814, 745),
        ui.Size(549, 606),
        ui.Size(598, 400),
      ]) {
        OrbitView view = OrbitView.initial;
        const int frames = 300;
        // Warm up the JIT.
        for (int i = 0; i < 30; i++) {
          final ui.PictureRecorder rec = ui.PictureRecorder();
          OrbitPainter(
            mesh: mesh,
            view: ValueNotifier<OrbitView>(view),
            surface: MountSurface.ceiling,
            labelStyle: const TextStyle(fontSize: 11),
            frontLabel: 'Front',
          ).paint(ui.Canvas(rec), size);
          rec.endRecording().dispose();
          view = view.rotated(-0.5, 0);
        }
        final ValueNotifier<OrbitView> notifier = ValueNotifier<OrbitView>(
          view,
        );
        final OrbitPainter painter = OrbitPainter(
          mesh: mesh,
          view: notifier,
          surface: MountSurface.ceiling,
          labelStyle: const TextStyle(fontSize: 11),
          frontLabel: 'Front',
        );
        final List<int> us = <int>[];
        for (int i = 0; i < frames; i++) {
          notifier.value = notifier.value.rotated(-0.5, 0);
          final Stopwatch sw = Stopwatch()..start();
          final ui.PictureRecorder rec = ui.PictureRecorder();
          painter.paint(ui.Canvas(rec), size);
          final ui.Picture pic = rec.endRecording();
          sw.stop();
          us.add(sw.elapsedMicroseconds);
          pic.dispose();
        }
        us.sort();
        final double mean = us.reduce((int a, int b) => a + b) / frames / 1000;
        final double p95 = us[(frames * 0.95).floor()] / 1000;
        // Software raster of a few frames.
        final List<int> raster = <int>[];
        await tester.runAsync(() async {
          for (int i = 0; i < 10; i++) {
            notifier.value = notifier.value.rotated(-3, 0);
            final ui.PictureRecorder rec = ui.PictureRecorder();
            painter.paint(ui.Canvas(rec), size);
            final ui.Picture pic = rec.endRecording();
            final Stopwatch sw = Stopwatch()..start();
            final ui.Image img = await pic.toImage(
              size.width.round(),
              size.height.round(),
            );
            sw.stop();
            raster.add(sw.elapsedMicroseconds);
            img.dispose();
            pic.dispose();
          }
        });
        raster.sort();
        // ignore: avoid_print
        print(
          'rotation ${k.name} ${size.width.toInt()}x${size.height.toInt()}: '
          'paint mean ${mean.toStringAsFixed(2)} ms, p95 '
          '${p95.toStringAsFixed(2)} ms over $frames frames; software raster '
          'median ${(raster[raster.length ~/ 2] / 1000).toStringAsFixed(2)} ms',
        );
        notifier.dispose();
      }
      lab.dispose();
    }
  });
}
