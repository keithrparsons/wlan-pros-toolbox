// Render-proof capture of PoE: Why the New AP Runs at Half Strength (NOT a golden, NOT a gate): the
// presenter layout at 1470x923 (a MacBook Air in full screen) and 1440x900,
// and the normal desktop and phone layouts, both themes. Same pattern as
// presenter_render_rf.dart, in its own file so sibling tools do not collide.
// The `_render.dart` suffix keeps it out of the default `flutter test` run:
//
//   PRESENTER_RENDER_OUT=/some/dir \
//     flutter test test/widgets/presenter/presenter_render_poe_half_strength.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/poe_half_strength_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/poe_half_strength_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/poe_half_strength_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import 'presenter_test_support.dart';

final String _outDir =
    Platform.environment['PRESENTER_RENDER_OUT'] ?? '/tmp/presenter-render';

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  required bool present,
  void Function(PoeHalfStrengthController k)? setup,
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
        home: const PoeHalfStrengthScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (present) {
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
  }
  setup?.call(
    tester
        .widget<PoeHalfStrengthStage>(find.byType(PoeHalfStrengthStage).last)
        .controller,
  );
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
  testWidgets('poe half strength', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      final String t = light ? 'light' : 'dark';
      for (final PhPort p in PhPort.values) {
        await _shot(
          tester,
          light: light,
          size: const Size(1470, 923),
          slug: 'poe-$t-present-${p.name}',
          present: true,
          setup: (PoeHalfStrengthController k) => k
            ..setPort(p)
            ..setRevealed(p == PhPort.at),
        );
      }
      await _shot(
        tester,
        light: light,
        size: const Size(1280, 900),
        slug: 'poe-$t-desktop-two4x4',
        present: false,
        setup: (PoeHalfStrengthController k) => k.setAtMode(PhAtMode.twoAt4x4),
      );
      await _shot(
        tester,
        light: light,
        size: const Size(390, 844),
        slug: 'poe-$t-phone',
        present: false,
      );
    }
  });
}
