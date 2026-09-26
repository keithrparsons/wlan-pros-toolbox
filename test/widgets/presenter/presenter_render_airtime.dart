// Render-proof capture of the presenter layout for five Wi-Fi Classroom tools:
// Airtime Fairness, Airtime Anatomy, OFDMA Resource Units, Rate Adaptation
// and Power Save (NOT a golden, NOT a gate). Same harness as
// presenter_render.dart, kept in its own file so the tool batches converted
// in parallel do not edit one file. The `_render.dart` suffix keeps it out of
// the default `flutter test` run:
//
//   PRESENTER_RENDER_OUT=/some/dir \
//     flutter test test/widgets/presenter/presenter_render_airtime.dart
//
// PRESENTER_RENDER_SIZES=all adds 1920x1080 and 1440x900 to the default
// 1470x923 (a MacBook Air in full screen). Each frame is the tool's fullest
// state, dark and light.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/airtime_anatomy_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/airtime_anatomy_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/airtime_fairness_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ofdma_simulator_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ofdma_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/power_save_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_adaptation_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_adaptation_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/airtime_anatomy.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/power_save_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import 'presenter_test_support.dart';

final String _outDir =
    Platform.environment['PRESENTER_RENDER_OUT'] ?? '/tmp/presenter-render';

final List<Size> _sizes =
    Platform.environment['PRESENTER_RENDER_SIZES'] == 'all'
    ? const <Size>[Size(1470, 923), Size(1920, 1080), Size(1440, 900)]
    : const <Size>[Size(1470, 923)];

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
  await tester.pump(const Duration(seconds: 3));
  await tester.tap(find.text('Present'));
  await tester.pump(const Duration(seconds: 1));
  await setup?.call();
  // Several frames, so a transition the setup started (a button's color,
  // 200 ms) has run to its end before the capture.
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 500));
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
  // ignore: avoid_print
  print('$slug controls overflow ${controlsOverflow(tester)}');
  await tester.pumpWidget(const SizedBox());
}

/// `airtime-fairness-dark-1470x923`, the evidence folder's naming.
String _slug(String tool, bool light, Size s) =>
    '$tool-${light ? 'light' : 'dark'}-'
    '${s.width.toInt()}x${s.height.toInt()}';

void main() {
  testWidgets('airtime fairness', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      for (final Size s in _sizes) {
        final AirtimeFairnessController c = AirtimeFairnessController();
        await _shot(
          tester,
          screen: AirtimeFairnessScreen(controller: c),
          light: light,
          size: s,
          slug: _slug('airtime-fairness', light, s),
          setup: () async {
            for (int i = c.clients.length; i < 8; i++) {
              c.addClient();
            }
            // Stop the round mid-way so the playhead shows.
            c.resetRound();
            for (int i = 0; i < 9; i++) {
              c.stepTransmission();
            }
          },
        );
        c.dispose();
      }
    }
  });

  testWidgets('airtime anatomy', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      for (final Size s in _sizes) {
        final AirtimeAnatomyModel m = AirtimeAnatomyModel();
        await _shot(
          tester,
          screen: AirtimeAnatomyScreen(model: m),
          light: light,
          size: s,
          slug: _slug('airtime-anatomy', light, s),
          setup: () async {
            m.setEditing(1);
            m.edit((AirtimeScenario x) => x.copyWith(rtsCts: true));
            m.select(1, TxopSegmentKind.data);
          },
        );
        m.dispose();
      }
    }
  });

  testWidgets('ofdma', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      for (final Size s in _sizes) {
        final OfdmaSimulatorModel m = OfdmaSimulatorModel();
        await _shot(
          tester,
          screen: OfdmaSimulatorScreen(model: m),
          light: light,
          size: s,
          slug: _slug('ofdma-simulator', light, s),
          setup: () async {
            m.setWidth(80);
            m.setClientCount(kOfdmaMaxClients);
            m.equalRus();
            m.select(2);
          },
        );
        m.dispose();
      }
    }
  });

  testWidgets('rate adaptation', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      for (final Size s in _sizes) {
        final RateAdaptationController c = RateAdaptationController();
        await _shot(
          tester,
          screen: RateAdaptationScreen(controller: c),
          light: light,
          size: s,
          slug: _slug('rate-adaptation', light, s),
          setup: () async {
            c.advanceBy(14e6);
          },
        );
        c.dispose();
      }
    }
  });

  testWidgets('power save', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      for (final Size s in _sizes) {
        final PowerSaveController c = PowerSaveController();
        await _shot(
          tester,
          screen: PowerSaveScreen(controller: c),
          light: light,
          size: s,
          slug: _slug('power-save', light, s),
          setup: () async {
            c.mode = PsMode.uapsd;
            c.compare = PsMode.twt;
          },
        );
        c.dispose();
      }
    }
  });
}
