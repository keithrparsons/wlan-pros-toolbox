// Render-proof capture of Why Two Devices Disagree (NOT a golden, NOT a
// gate): the presenter layout at 1470x923 and the normal screen at phone,
// tablet and desktop sizes, both themes. Not a *_test.dart file, so the
// default `flutter test` run skips it:
//
//   RENDER_OUT=/some/dir \
//     flutter test test/screens/calculators/devices_disagree_render.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/devices_disagree_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/devices_disagree_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/devices_disagree_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import '../../widgets/presenter/presenter_test_support.dart';

final String _out =
    Platform.environment['RENDER_OUT'] ?? '/tmp/devices-disagree-render';

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  bool present = false,
  void Function(DevicesDisagreeController c)? setup,
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
        home: const DevicesDisagreeScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (present) {
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
  }
  final DevicesDisagreeController c = tester
      .widget<DevicesDisagreeStage>(find.byType(DevicesDisagreeStage).last)
      .controller;
  setup?.call(c);
  await tester.pumpAndSettle();
  final RenderRepaintBoundary b =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await b.toImage();
    final ByteData? bytes = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final File f = File('$_out/$slug.png');
    await f.create(recursive: true);
    await f.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
  await tester.pumpWidget(const SizedBox());
}

void main() {
  testWidgets('render', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      final String t = light ? 'light' : 'dark';
      await _shot(
        tester,
        light: light,
        size: const Size(1470, 923),
        slug: 'present-$t',
        present: true,
      );
      await _shot(
        tester,
        light: light,
        size: const Size(1470, 923),
        slug: 'present-$t-revealed-offsets',
        present: true,
        setup: (DevicesDisagreeController c) => c
          ..reveal()
          ..applyOffsets = true,
      );
      await _shot(
        tester,
        light: light,
        size: const Size(1280, 1400),
        slug: 'desktop-$t',
      );
      await _shot(
        tester,
        light: light,
        size: const Size(768, 2600),
        slug: 'tablet-$t',
      );
      await _shot(
        tester,
        light: light,
        size: const Size(390, 3000),
        slug: 'phone-$t',
      );
    }
  });
}
