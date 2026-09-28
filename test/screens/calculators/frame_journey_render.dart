// Render-proof capture for Down the Stack and A Frame's Journey (NOT a
// golden, NOT a gate). The `_render.dart` suffix keeps it out of the default
// `flutter test` run, so it only executes when asked:
//
//   FJ_RENDER_OUT=/some/dir \
//     flutter test test/screens/calculators/frame_journey_render.dart
//
// The normal screen at 390, 820 and 1280 px and the presenter layout at
// 1440x900 and 1920x1080, dark and light.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/down_the_stack_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/frame_journey_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/frame_journey_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import '../../widgets/presenter/presenter_test_support.dart';

final String _outDir =
    Platform.environment['FJ_RENDER_OUT'] ?? '/tmp/frame-journey-render';

Future<void> _shot(
  WidgetTester tester, {
  required Widget Function() screen,
  required bool light,
  required Size size,
  required String slug,
  bool present = false,
  void Function()? setup,
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
        home: screen(),
      ),
    ),
  );
  await tester.pump();
  if (present) {
    await tester.tap(find.text('Present'));
    await tester.pump(const Duration(seconds: 1));
  }
  setup?.call();
  for (int i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
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

void main() {
  testWidgets('capture', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      final String mode = light ? 'light' : 'dark';

      // Down the Stack: the laptop's data link step (Address 3 = router).
      for (final double w in <double>[390, 820, 1280]) {
        final DownTheStackController c = DownTheStackController();
        await _shot(
          tester,
          screen: () => DownTheStackScreen(controller: c),
          light: light,
          size: Size(w, 3000),
          slug: 'dts-$mode-${w.toInt()}',
          setup: () => c.index = 3,
        );
        c.dispose();
      }
      for (final Size s in const <Size>[Size(1440, 900), Size(1920, 1080)]) {
        final DownTheStackController c = DownTheStackController();
        await _shot(
          tester,
          screen: () => DownTheStackScreen(controller: c),
          light: light,
          size: s,
          slug: 'dts-presenter-$mode-${s.width.toInt()}',
          present: true,
          setup: () => c.index = 14,
        );
        c.dispose();
        final DownTheStackController d = DownTheStackController();
        await _shot(
          tester,
          screen: () => DownTheStackScreen(controller: d),
          light: light,
          size: s,
          slug: 'dts-presenter-ds11-$mode-${s.width.toInt()}',
          present: true,
          setup: () {
            d.view = DtsView.addresses;
            d.dsCase = DsCase.both;
          },
        );
        d.dispose();
      }

      // A Frame's Journey: a corrupted first attempt at the FCS check.
      for (final double w in <double>[390, 820, 1280]) {
        final FrameJourneyController c = FrameJourneyController();
        await _shot(
          tester,
          screen: () => FrameJourneyScreen(controller: c),
          light: light,
          size: Size(w, 3000),
          slug: 'fj-$mode-${w.toInt()}',
          setup: () {
            c.corrupt = true;
            c.index = c.hop.indexWhere((FhStep s) => s.stage == FjHopStage.fcs);
          },
        );
        c.dispose();
      }
      for (final Size s in const <Size>[Size(1440, 900), Size(1920, 1080)]) {
        final FrameJourneyController c = FrameJourneyController();
        await _shot(
          tester,
          screen: () => FrameJourneyScreen(controller: c),
          light: light,
          size: s,
          slug: 'fj-presenter-$mode-${s.width.toInt()}',
          present: true,
          setup: () {
            c.index = c.hop.indexWhere(
              (FhStep s) => s.stage == FjHopStage.sifs,
            );
          },
        );
        c.dispose();
      }
    }
  });
}
