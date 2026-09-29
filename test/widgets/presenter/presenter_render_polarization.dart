// Render-proof capture of Polarization (NOT a golden, NOT a gate): the
// presenter layout at 1920x1080, 1440x900 and 1470x923, the desktop layout and
// the 390 px phone, both themes, for each preset. The `_render.dart` suffix
// keeps it out of the default `flutter test` run:
//
//   PRESENTER_RENDER_OUT=/some/dir \
//     flutter test test/widgets/presenter/presenter_render_polarization.dart
//
// The field animates on a clock, so this pumps fixed durations and pauses the
// wave before each capture rather than settling.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/polarization_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/polarization_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/polarization_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import 'presenter_test_support.dart';

final String _outDir =
    Platform.environment['PRESENTER_RENDER_OUT'] ?? '/tmp/presenter-render';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  required bool present,
  void Function(PolarizationController c)? setup,
  Future<void> Function(WidgetTester tester)? after,
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
        home: const PolarizationScreen(),
      ),
    ),
  );
  await _settle(tester);
  if (present) {
    await tester.tap(find.text('Present'));
    await _settle(tester);
  }
  final PolarizationController c = tester
      .widget<PolarizationStage>(find.byType(PolarizationStage).last)
      .controller;
  c.setPlaying(false);
  setup?.call(c);
  await _settle(tester);
  await after?.call(tester);
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
  testWidgets('polarization', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      final String t = light ? 'light' : 'dark';
      for (final Size s in const <Size>[
        Size(1920, 1080),
        Size(1440, 900),
        Size(1470, 923),
      ]) {
        await _shot(
          tester,
          light: light,
          size: s,
          slug:
              'polarization-$t-present-${s.width.toInt()}x${s.height.toInt()}'
              '-circular-components',
          present: true,
          setup: (PolarizationController c) => c
            ..setPreset(PolarizationPreset.circular)
            ..setShowComponents(true),
        );
      }
      for (final PolarizationPreset p in PolarizationPreset.named) {
        await _shot(
          tester,
          light: light,
          size: const Size(1470, 923),
          slug: 'polarization-$t-present-1470x923-${p.name}',
          present: true,
          setup: (PolarizationController c) => c.setPreset(p),
        );
      }
      await _shot(
        tester,
        light: light,
        size: const Size(1280, 1400),
        slug: 'polarization-$t-desktop-slant-components',
        present: false,
        setup: (PolarizationController c) => c
          ..setPreset(PolarizationPreset.slant45)
          ..setShowComponents(true),
      );
      await _shot(
        tester,
        light: light,
        size: const Size(390, 1900),
        slug: 'polarization-$t-phone-390-elliptical-adjust',
        present: false,
        setup: (PolarizationController c) => c
          ..setPreset(PolarizationPreset.elliptical)
          ..setShowComponents(true),
        after: (WidgetTester tester) async {
          await tester.tap(find.text('Adjust: amplitudes and phase difference'));
          await _settle(tester);
        },
      );
      await _shot(
        tester,
        light: light,
        size: const Size(390, 1900),
        slug: 'polarization-$t-phone-390-no-field',
        present: false,
        setup: (PolarizationController c) => c.setField(
          const PolarizationState(ax: 0, ay: 0, deltaDeg: 0),
        ),
      );
    }
  });
}
