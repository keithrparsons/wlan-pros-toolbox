// Render-proof capture for the DFS and Radar screen (NOT a golden, NOT a
// gate). The `_render.dart` suffix keeps it out of the default `flutter test`
// run, so it only executes when asked:
//
//   flutter test test/screens/calculators/dfs_simulator_render.dart
//
// WHAT IT IS FOR. The widget tests assert strings, states and that nothing
// overflows. They cannot say whether the channel strip reads at phone width,
// whether the timeline labels collide, or whether the status tints sit well
// on a light card. These frames are for looking: dark and light, 390 and
// 1280 px, each with a radar event mid-run.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dfs_simulator_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dfs_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dfs_simulator_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/dfs_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _outDir =
    '/Users/keithparsons/myPKA/Deliverables/'
    '2026-09-25-wifi-lab-cleanroom/evidence/dfs-simulator';

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  required DfsConfig config,
  required double atS,
  DfsTimelineView view = DfsTimelineView.hour,
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
        home: DfsSimulatorScreen(initial: config),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final DfsSimulatorController c = tester
      .widget<DfsSimulatorStage>(find.byType(DfsSimulatorStage))
      .controller;
  c.seek(atS);
  c.view = view;
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
      // US 100, radar at 5:00 and 20:00 with "Another DFS": two moves, two
      // CACs, two blocks; seen at 22:00 over the whole hour.
      await _shot(
        tester,
        light: light,
        size: const Size(390, 3000),
        slug: 'us_two_radars_hour_${mode}_390',
        config: const DfsConfig(
          policy: NewChannelPolicy.anotherDfs,
          manualRadarS: <double>[300, 1200],
        ),
        atS: 1320,
      );
      // EU 116-120 at 40 MHz, radar at 5:00, zoomed mid-CAC on the next
      // channel (124-128, 10-minute CAC).
      await _shot(
        tester,
        light: light,
        size: const Size(390, 3000),
        slug: 'eu_radar_zoom_${mode}_390',
        config: const DfsConfig(
          region: DfsRegion.eu,
          widthMHz: 40,
          startChannel: 116,
          policy: NewChannelPolicy.anotherDfs,
          manualRadarS: <double>[300],
        ),
        atS: 400,
        view: DfsTimelineView.zoom,
      );
      await _shot(
        tester,
        light: light,
        size: const Size(1280, 2600),
        slug: 'us_radar_prefer_nondfs_${mode}_1280',
        config: const DfsConfig(
          widthMHz: 80,
          startChannel: 100,
          manualRadarS: <double>[300],
          radarPerHour: 6,
        ),
        atS: 900,
      );
    }
    await _shot(
      tester,
      light: false,
      size: const Size(390, 2600),
      slug: 'fresh_dark_390',
      config: const DfsConfig(),
      atS: 0,
    );
  });
}
