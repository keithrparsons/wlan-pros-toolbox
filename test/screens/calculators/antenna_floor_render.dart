// Render-proof capture of Antenna Pattern's Floor coverage view (spec 46;
// NOT a golden, NOT a gate): phone, tablet and desktop layouts and the
// presenter layout, both themes, every preset. The `_render.dart` suffix
// keeps it out of the default `flutter test` run:
//
//   FLOOR_RENDER_OUT=/some/dir \
//     flutter test test/screens/calculators/antenna_floor_render.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_floor_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_floor_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import '../../widgets/presenter/presenter_test_support.dart';

final String _outDir =
    Platform.environment['FLOOR_RENDER_OUT'] ?? '/tmp/floor-render';

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  bool present = false,
  FloorPreset? preset,
  void Function(FloorCoverageController f)? setup,
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
        home: const AntennaPatternScreen(initialView: AntennaStageView.floor),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (present) {
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
  }
  final FloorCoverageController f = tester
      .widget<FloorCoverageStage>(find.byType(FloorCoverageStage).last)
      .floor;
  if (preset != null) f.applyPreset(preset);
  setup?.call(f);
  await tester.pumpAndSettle();
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
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('floor coverage', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      final String t = light ? 'light' : 'dark';
      for (final FloorPreset p in FloorPreset.values) {
        await _shot(
          tester,
          light: light,
          size: const Size(1470, 923),
          slug: 'present-1470-$t-${p.index + 1}-${p.name}',
          present: true,
          preset: p,
        );
      }
      await _shot(
        tester,
        light: light,
        size: const Size(1920, 1080),
        slug: 'present-1920-$t-2-warehouseDipole',
        present: true,
        preset: FloorPreset.warehouseDipole,
      );
      await _shot(
        tester,
        light: light,
        size: const Size(1440, 900),
        slug: 'present-1440-$t-5-warehouseDirectional',
        present: true,
        preset: FloorPreset.warehouseDirectional,
      );
      await _shot(
        tester,
        light: light,
        size: const Size(390, 2900),
        slug: 'phone-390-$t-2-warehouseDipole',
        preset: FloorPreset.warehouseDipole,
      );
      await _shot(
        tester,
        light: light,
        size: const Size(768, 2600),
        slug: 'tablet-768-$t-3-warehouseHighGainOmni',
        preset: FloorPreset.warehouseHighGainOmni,
      );
      await _shot(
        tester,
        light: light,
        size: const Size(1280, 2400),
        slug: 'desktop-1280-$t-1-office',
        preset: FloorPreset.office,
      );
    }
    await _shot(
      tester,
      light: false,
      size: const Size(320, 2900),
      slug: 'phone-320-dark-5-warehouseDirectional',
      preset: FloorPreset.warehouseDirectional,
    );
    await _shot(
      tester,
      light: false,
      size: const Size(1280, 2400),
      slug: 'desktop-1280-dark-wall-directional-tilt',
      preset: FloorPreset.warehouseDirectional,
      setup: (FloorCoverageController f) {
        f.lab.setMount(AntennaMount.wall);
        f.lab.setSectorTilt(20);
        f.setClientX(25);
      },
    );
  });
}
