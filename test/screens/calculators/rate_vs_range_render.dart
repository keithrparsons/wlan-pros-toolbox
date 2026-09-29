// Render-proof capture for Rate vs Range with the Rate set card (NOT a
// golden, NOT a gate). The `_render.dart` suffix keeps it out of the default
// `flutter test` run:
//
//   RVR_RENDER_OUT=/some/dir \
//     flutter test test/screens/calculators/rate_vs_range_render.dart
//
// Frames for looking: the phone at 390 px (default, and 2.4 GHz with an
// 802.11b client refused), and the presenter at 1920x1080 and 1470x923 with
// the folds closed and open, dark and light.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_vs_range_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_vs_range_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_vs_range_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/rate_set_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import '../../widgets/presenter/presenter_test_support.dart';

final String _outDir =
    Platform.environment['RVR_RENDER_OUT'] ?? '/tmp/rate-vs-range-render';

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  bool present = false,
  List<String> open = const <String>[],
  void Function(RateVsRangeModel m)? setup,
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
        home: const RateVsRangeScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (present) {
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
  }
  final RateVsRangeModel m = tester
      .widget<RateVsRangeStage>(find.byType(RateVsRangeStage).last)
      .model;
  setup?.call(m);
  await tester.pumpAndSettle();
  for (final String t in open) {
    await tester.tap(find.text(t));
    await tester.pumpAndSettle();
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
}

void _refused(RateVsRangeModel m) => m
  ..setBand(WifiBand.band24)
  ..setRsClient(RsClient.dot11b);

void _dsssBasic(RateVsRangeModel m) {
  m
    ..setBand(WifiBand.band24)
    ..setRsClient(RsClient.wifi6);
  for (final RsRate r in RsRate.ofClass(RsModClass.dsss)) {
    m.cycleRate(r); // supported -> basic
  }
}

void main() {
  testWidgets('capture', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      final String mode = light ? 'light' : 'dark';
      await _shot(
        tester,
        light: light,
        size: const Size(390, 5200),
        slug: 'rvr-$mode-390-default',
      );
      await _shot(
        tester,
        light: light,
        size: const Size(390, 5200),
        slug: 'rvr-$mode-390-24ghz-80211b-refused',
        setup: _refused,
      );
      await _shot(
        tester,
        light: light,
        size: const Size(390, 5200),
        slug: 'rvr-$mode-390-24ghz-dsss-basic',
        setup: _dsssBasic,
      );
      for (final Size s in const <Size>[Size(1920, 1080), Size(1470, 923)]) {
        final String dim = '${s.width.toInt()}x${s.height.toInt()}';
        await _shot(
          tester,
          light: light,
          size: s,
          slug: 'rvr-presenter-$mode-$dim-80211b-refused',
          present: true,
          setup: _refused,
        );
        await _shot(
          tester,
          light: light,
          size: s,
          slug: 'rvr-presenter-$mode-$dim-folds-open',
          present: true,
          setup: _refused,
          open: const <String>['Rate set and client'],
        );
        await _shot(
          tester,
          light: light,
          size: s,
          slug: 'rvr-presenter-$mode-$dim-ack-open',
          present: true,
          open: const <String>['ACK to a frame sent at X'],
        );
      }
    }
  });
}
