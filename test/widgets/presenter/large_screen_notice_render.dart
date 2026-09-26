// Render-proof capture of the Wi-Fi Classroom large-screen notice (NOT a golden,
// NOT a gate). The `_render.dart` suffix keeps it out of the default run:
//
//   LARGE_SCREEN_RENDER_OUT=/some/dir \
//     flutter test test/widgets/presenter/large_screen_notice_render.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/large_screen_gate.dart';

final String _outDir =
    Platform.environment['LARGE_SCREEN_RENDER_OUT'] ??
    '/tmp/large-screen-render';

void main() {
  const List<Size> sizes = <Size>[Size(390, 844), Size(480, 320)];
  for (final Size size in sizes) {
    for (final bool light in <bool>[false, true]) {
      final String slug =
          'notice-${size.width.toInt()}x${size.height.toInt()}-'
          '${light ? 'light' : 'dark'}';
      testWidgets(slug, (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        resetLargeScreenNoticeForTest();
        final GlobalKey key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: light ? AppTheme.light() : AppTheme.dark(),
              routes: AppRouter.routes,
              initialRoute: AppRouter.modulationSimulator,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(kLargeScreenNoticeTitle), findsOneWidget);
        expect(tester.takeException(), isNull);
        final RenderRepaintBoundary boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final ui.Image image = await boundary.toImage(pixelRatio: 2);
          final ByteData? bytes = await image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final File out = File('$_outDir/$slug.png');
          await out.create(recursive: true);
          await out.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      });
    }
  }
}
