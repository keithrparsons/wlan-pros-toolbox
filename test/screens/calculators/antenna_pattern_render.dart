// Render-proof capture for the Antenna Pattern screen (NOT a golden, NOT a
// gate). The `_render.dart` suffix keeps it out of the default `flutter test`
// run, so it only executes when asked:
//
//   flutter test test/screens/calculators/antenna_pattern_render.dart
//
// WHAT IT IS FOR. The widget tests assert strings, states and that nothing
// overflows. They cannot say whether the 3D surface reads as a shape, whether
// the painter's-algorithm sort leaves holes when rotated, or whether the dark
// viewport sits well inside a light-theme card. These frames are for looking.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_mesh.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _outDir =
    '/Users/keithparsons/myPKA/Deliverables/'
    '2026-09-25-wifi-lab-cleanroom/evidence/antenna-pattern';

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  required AntennaModelKind kind,
  void Function(AntennaPatternLab lab)? setup,
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
        home: AntennaPatternScreen(initialKind: kind),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final AntennaPatternLab lab = tester
      .widget<AntennaPatternStage>(find.byType(AntennaPatternStage))
      .lab;
  setup?.call(lab);
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
        size: const Size(390, 2600),
        slug: 'omni12_${mode}_390',
        kind: AntennaModelKind.omni,
        setup: (AntennaPatternLab l) => l.setOmniGain(12),
      );
      await _shot(
        tester,
        light: light,
        size: const Size(390, 2600),
        slug: 'directional_rotated_${mode}_390',
        kind: AntennaModelKind.directional,
        setup: (AntennaPatternLab l) {
          l.setSideLobe(18);
          l.setFrontToBack(22);
          l.view.value = const OrbitView(yawDeg: 150, pitchDeg: 40, zoom: 1.2);
        },
      );
      await _shot(
        tester,
        light: light,
        size: const Size(1280, 2200),
        slug: 'imported_tilted_${mode}_1280',
        kind: AntennaModelKind.imported,
        setup: (AntennaPatternLab l) {
          l.loadExample(PatternExample.tiltedSector);
          l.view.value = const OrbitView(yawDeg: 210, pitchDeg: -25);
        },
      );
      await _shot(
        tester,
        light: light,
        size: const Size(1280, 2000),
        slug: 'collinear_wall_${mode}_1280',
        kind: AntennaModelKind.collinear,
        setup: (AntennaPatternLab l) {
          l.setElements(6);
          l.setCollinearTilt(8);
          l.setMount(AntennaMount.wall);
        },
      );
    }
    await _shot(
      tester,
      light: false,
      size: const Size(390, 1100),
      slug: 'imported_empty_dark_390',
      kind: AntennaModelKind.imported,
    );
    await _shot(
      tester,
      light: false,
      size: const Size(390, 1600),
      slug: 'dipole_dark_390',
      kind: AntennaModelKind.dipole,
    );
  });
}
