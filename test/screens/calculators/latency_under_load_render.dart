// Render-proof capture for Why a Busy Line Lags (NOT a golden, NOT a
// gate). The `_render.dart` suffix keeps it out of the default `flutter test`
// run, so it only executes when asked:
//
//   LUL_RENDER_OUT=/some/dir \
//     flutter test test/screens/calculators/latency_under_load_render.dart
//
// The widget tests assert strings, states and that nothing overflows. These
// frames are for looking: the normal screen at 390 and 1280 px and the
// presenter layout at 1470x923, dark and light, SQM off and on.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/latency_under_load_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/latency_under_load_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import '../../widgets/presenter/presenter_test_support.dart';

final String _outDir =
    Platform.environment['LUL_RENDER_OUT'] ?? '/tmp/latency-under-load-render';

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  bool present = false,
  void Function(LatencyUnderLoadController c)? setup,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  installFakeWindow();
  final LatencyUnderLoadController c = LatencyUnderLoadController();
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: light ? AppTheme.light() : AppTheme.dark(),
        home: LatencyUnderLoadScreen(controller: c),
      ),
    ),
  );
  await tester.pump();
  if (present) {
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
  }
  setup?.call(c);
  await tester.pump();
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
  c.dispose();
}

void main() {
  testWidgets('capture', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      final String mode = light ? 'light' : 'dark';
      for (final double w in <double>[390, 1280]) {
        await _shot(
          tester,
          light: light,
          size: Size(w, 2600),
          slug: 'lul-$mode-${w.toInt()}',
          setup: (LatencyUnderLoadController c) => c.seek(10),
        );
      }
      for (final bool on in <bool>[false, true]) {
        await _shot(
          tester,
          light: light,
          size: const Size(1470, 923),
          slug: 'lul-presenter-$mode-sqm${on ? 'on' : 'off'}-1470x923',
          present: true,
          setup: (LatencyUnderLoadController c) {
            c.sqm = on;
            c.seek(10);
          },
        );
      }
      await _shot(
        tester,
        light: light,
        size: const Size(1440, 900),
        slug: 'lul-presenter-$mode-dsl-end-1440x900',
        present: true,
        setup: (LatencyUnderLoadController c) {
          c.line = LulLine.dsl;
        },
      );
    }
  });
}
