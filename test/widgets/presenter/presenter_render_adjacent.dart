// Render-proof capture of Adjacent Channels and AP Stacking (spec 29):
// presenter layout at 1470x923 and 1920x1080, both themes, in three states
// (the fresh 36/44 scene at 3 m, the opening question's 30 cm scene, a 160
// MHz neighbor on the next channel in 6 GHz), plus the phone-width stack.
// NOT a golden, NOT a gate; the `_render.dart`-style name keeps it out of the
// default `flutter test` run. Own file so parallel worktrees do not edit one
// list.
//
//   PRESENTER_RENDER_OUT=/some/dir \
//     flutter test test/widgets/presenter/presenter_render_adjacent.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/adjacent_channel_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/adjacent_channel_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/adjacent_channel_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/adjacent_channel_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import 'presenter_test_support.dart';

final String _outDir =
    Platform.environment['PRESENTER_RENDER_OUT'] ?? '/tmp/presenter-render';

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  required void Function(AdjacentChannelController c) setup,
  bool present = true,
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
        home: const AdjacentChannelScreen(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  if (present) {
    await tester.tap(find.text('Present'));
    await tester.pump(const Duration(milliseconds: 500));
  }
  setup(
    tester
        .widget<AdjacentChannelStage>(find.byType(AdjacentChannelStage).last)
        .controller,
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 16));
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
  if (present) {
    // ignore: avoid_print
    print('$slug controls overflow ${controlsOverflow(tester)}');
  }
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  final Map<String, void Function(AdjacentChannelController)> states =
      <String, void Function(AdjacentChannelController)>{
        'fresh': (AdjacentChannelController c) {},
        'question-30cm': (AdjacentChannelController c) => c.reveal(),
        'six-160-adjacent': (AdjacentChannelController c) => c
          ..band = WifiBand.band6
          ..neighborWidthMHz = 160
          ..separation = AciSeparation.adjacent
          ..neighborDistanceM = 1.5,
      };

  testWidgets('adjacent channel', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      final String theme = light ? 'light' : 'dark';
      for (final Size s in const <Size>[Size(1470, 923), Size(1920, 1080)]) {
        for (final MapEntry<String, void Function(AdjacentChannelController)> e
            in states.entries) {
          await _shot(
            tester,
            light: light,
            size: s,
            slug:
                'adjacent-channel-$theme-${s.width.toInt()}x${s.height.toInt()}-'
                '${e.key}',
            setup: e.value,
          );
        }
      }
      await _shot(
        tester,
        light: light,
        size: const Size(700, 2600),
        slug: 'adjacent-channel-$theme-700-phone-stack',
        present: false,
        setup: (AdjacentChannelController c) => c
          ..band = WifiBand.band24
          ..neighborDistanceM = 1,
      );
    }
  });
}
