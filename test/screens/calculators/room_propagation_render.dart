// Render-proof capture for the Room Propagation screen (NOT a golden, NOT a
// gate). The `_render.dart` suffix keeps it out of the default `flutter test`
// run, so it only executes when asked:
//
//   flutter test test/screens/calculators/room_propagation_render.dart
//
// WHAT IT IS FOR. The widget tests assert strings, states and that nothing
// overflows. They cannot say whether the heat map reads, whether walls stand
// out on every shade, or whether the close-up's fringes are visible. These
// frames are for looking. The maps are computed at full resolution (20 cm
// cells, 125 x 125 close-up), synchronously.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/room_propagation_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/room_propagation_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/room_propagation_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/room_propagation_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _outDir =
    '/Users/keithparsons/myPKA/Deliverables/'
    '2026-09-25-wifi-lab-cleanroom/evidence/room-propagation';

Future<RoomFieldResult> _sync(RoomFieldJob job) =>
    Future<RoomFieldResult>.value(computeRoomField(job));

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  int preset = 0,
  void Function(RoomPropagationController c)? setup,
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
        home: RoomPropagationScreen(runner: _sync, presetIndex: preset),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final RoomPropagationController c = tester
      .widget<RoomPropagationStage>(find.byType(RoomPropagationStage))
      .controller;
  setup?.call(c);
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
      // Drywall offices: several walls and four doorways.
      await _shot(
        tester,
        light: light,
        size: const Size(390, 3900),
        slug: 'drywall_offices_24_${mode}_390',
      );
      await _shot(
        tester,
        light: light,
        size: const Size(1280, 3300),
        slug: 'drywall_offices_24_${mode}_1280',
      );
      // Concrete corridor at 6 GHz with two bounces: doorways and shadows.
      await _shot(
        tester,
        light: light,
        size: const Size(390, 3900),
        slug: 'concrete_corridor_6g_${mode}_390',
        preset: 1,
        setup: (RoomPropagationController c) {
          c.band = WifiBand.band6;
          c.reflectionOrder = 2;
        },
      );
      await _shot(
        tester,
        light: light,
        size: const Size(1280, 3300),
        slug: 'concrete_corridor_24_${mode}_1280',
        preset: 1,
      );
    }
    // Open office, client near the metal cabinets for the close-up fringes.
    await _shot(
      tester,
      light: false,
      size: const Size(1280, 3300),
      slug: 'open_office_metal_ripple_dark_1280',
      preset: 2,
      setup: (RoomPropagationController c) => c.moveClient(const P2(9, 7.3)),
    );
    await _shot(
      tester,
      light: false,
      size: const Size(390, 3900),
      slug: 'glass_meeting_room_dark_390',
      preset: 3,
    );
  });
}
