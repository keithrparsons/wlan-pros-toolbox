// Render-proof capture of Predict, Then Measure (NOT a golden, NOT a gate).
// The `_render.dart` suffix keeps it out of the default `flutter test` run,
// and it lives in its own file so parallel Wi-Fi Classroom worktrees do not
// edit one shared list:
//
//   PRESENTER_RENDER_OUT=/some/dir \
//     flutter test test/screens/calculators/predict_measure_render.dart
//
// Frames: presenter at 1920x1080 and 1440x900 in both themes (fresh, a
// walk, the reveal), and the normal screen at phone and desktop widths.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/predict_measure_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/predict_measure_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import '../../widgets/presenter/presenter_test_support.dart';

final String _outDir =
    Platform.environment['PRESENTER_RENDER_OUT'] ?? '/tmp/presenter-render';

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  required bool present,
  void Function(PredictMeasureController c)? setup,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  installFakeWindow();
  final PredictMeasureController c = PredictMeasureController();
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: light ? AppTheme.light() : AppTheme.dark(),
        home: PredictMeasureScreen(controller: c),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (present) {
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
  }
  setup?.call(c);
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
  if (present) {
    // ignore: avoid_print
    print('$slug controls overflow ${controlsOverflow(tester)}');
  }
  await tester.pumpWidget(const SizedBox());
  c.dispose();
}

void _walk(PredictMeasureController c) {
  c.useBothSidesWalk();
  c.view = PmMapView.difference;
}

void _reveal(PredictMeasureController c) {
  c.useOneSideWalk();
  c.revealed = true;
}

void _measured(PredictMeasureController c) {
  c.useBothSidesWalk();
  c.sigmaDb = 3;
  c.view = PmMapView.measured;
}

void main() {
  testWidgets('predict then measure presenter', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      for (final Size s in const <Size>[Size(1920, 1080), Size(1440, 900)]) {
        final String t = '${light ? 'light' : 'dark'}_${s.width.toInt()}';
        await _shot(
          tester,
          light: light,
          size: s,
          present: true,
          slug: 'pm_present_fresh_$t',
        );
        await _shot(
          tester,
          light: light,
          size: s,
          present: true,
          slug: 'pm_present_walk_$t',
          setup: _walk,
        );
        await _shot(
          tester,
          light: light,
          size: s,
          present: true,
          slug: 'pm_present_reveal_$t',
          setup: _reveal,
        );
      }
    }
  });

  testWidgets('predict then measure screen', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      for (final Size s in const <Size>[Size(430, 4200), Size(1024, 3600)]) {
        await _shot(
          tester,
          light: light,
          size: s,
          present: false,
          slug: 'pm_screen_${light ? 'light' : 'dark'}_${s.width.toInt()}',
          setup: _measured,
        );
      }
    }
  });
}
