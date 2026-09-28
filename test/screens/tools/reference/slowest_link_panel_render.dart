// Render-proof capture for The Slowest Link Wins panel (NOT a golden, NOT a
// gate). The `_render.dart` suffix keeps it out of the default run:
//
//   SL_RENDER_OUT=/some/dir \
//     flutter test test/screens/tools/reference/slowest_link_panel_render.dart
//
// The PDF itself does not paint in the test engine (pdfx is a platform
// view); these frames are for looking at the panel beside and below it.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

final String _outDir =
    Platform.environment['SL_RENDER_OUT'] ?? '/tmp/slowest-link-render';

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  String? tap,
}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: light ? AppTheme.light() : AppTheme.dark(),
        home: Builder(
          builder: (BuildContext c) =>
              AppRouter.routes[AppRouter.throughputTestingWhere]!(c),
        ),
      ),
    ),
  );
  await tester.pump();
  if (tap != null) {
    await tester.ensureVisible(find.text(tap));
    await tester.tap(find.text(tap));
    await tester.pump();
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
  await tester.pumpWidget(const SizedBox());
  await tester.binding.setSurfaceSize(null);
}

void main() {
  testWidgets('capture', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      final String mode = light ? 'light' : 'dark';
      await _shot(
        tester,
        light: light,
        size: const Size(1440, 900),
        slug: 'sl-$mode-1440-port',
      );
      await _shot(
        tester,
        light: light,
        size: const Size(1440, 900),
        slug: 'sl-$mode-1440-wifi',
        tap: 'Wi-Fi',
      );
      await _shot(
        tester,
        light: light,
        size: const Size(390, 844),
        slug: 'sl-$mode-390-isp',
        tap: 'ISP plan',
      );
    }
  });
}
