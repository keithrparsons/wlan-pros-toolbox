// Render-proof capture of What an Interferer Costs (interferer-cost):
// presenter layout at 1470x923 and 1920x1080, both themes, in four states
// (the fresh Wi-Fi neighbor, the revealed question, the video sender, the
// oven on 5 GHz where it is absent), plus the phone-width stack.
// NOT a golden, NOT a gate; the `_render.dart`-style name keeps it out of the
// default `flutter test` run. Own file so parallel worktrees do not edit one
// list.
//
//   PRESENTER_RENDER_OUT=/some/dir \
//     flutter test test/widgets/presenter/presenter_render_interferer.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/interferer_cost_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/interferer_cost_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/interferer_cost_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/interferer_cost_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import 'presenter_test_support.dart';

final String _outDir =
    Platform.environment['PRESENTER_RENDER_OUT'] ?? '/tmp/presenter-render';

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  required void Function(InterfererCostController c) setup,
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
        home: const InterfererCostScreen(),
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
        .widget<InterfererCostStage>(find.byType(InterfererCostStage).last)
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
  final Map<String, void Function(InterfererCostController)> states =
      <String, void Function(InterfererCostController)>{
        'fresh': (InterfererCostController c) {},
        'question': (InterfererCostController c) => c.reveal(),
        'video': (InterfererCostController c) =>
            c.source = IcSource.videoSender,
        'oven-5ghz-160': (InterfererCostController c) => c
          ..source = IcSource.microwave
          ..channel = IcChannel.ch36
          ..widthMHz = 160,
      };

  testWidgets('interferer cost', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      final String theme = light ? 'light' : 'dark';
      for (final Size s in const <Size>[Size(1470, 923), Size(1920, 1080)]) {
        for (final MapEntry<String, void Function(InterfererCostController)> e
            in states.entries) {
          await _shot(
            tester,
            light: light,
            size: s,
            slug:
                'interferer-cost-$theme-${s.width.toInt()}x${s.height.toInt()}-'
                '${e.key}',
            setup: e.value,
          );
        }
      }
      await _shot(
        tester,
        light: light,
        size: const Size(390, 3400),
        slug: 'interferer-cost-$theme-390-phone-stack',
        present: false,
        setup: (InterfererCostController c) => c.source = IcSource.microwave,
      );
      await _shot(
        tester,
        light: light,
        size: const Size(1280, 1600),
        slug: 'interferer-cost-$theme-1280-desktop',
        present: false,
        setup: (InterfererCostController c) => c.source = IcSource.bluetooth,
      );
    }
  });
}
