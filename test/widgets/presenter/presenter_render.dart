// Render-proof capture of the presenter pilots (NOT a golden, NOT a gate).
// The `_render.dart` suffix keeps it out of the default `flutter test` run:
//
//   PRESENTER_RENDER_OUT=/some/dir \
//     flutter test test/widgets/presenter/presenter_render.dart
//
// Widget tests prove nothing overflows; these frames are for looking at the
// projector layout at 1920x1080 and 1440x900 in both themes.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/medium_access_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/medium_access_simulator_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/modulation_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/modulation_simulator_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/room_propagation_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/room_propagation_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import 'presenter_test_support.dart';

final String _outDir =
    Platform.environment['PRESENTER_RENDER_OUT'] ?? '/tmp/presenter-render';

Future<RoomFieldResult> _sync(RoomFieldJob job) =>
    Future<RoomFieldResult>.value(computeRoomField(job));

Future<void> _shot(
  WidgetTester tester, {
  required Widget screen,
  required bool light,
  required Size size,
  required String slug,
  Future<void> Function()? setup,
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
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  await setup?.call();
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
  // ignore: avoid_print
  print('$slug controls overflow ${controlsOverflow(tester)}');
  await tester.pumpWidget(const SizedBox());
}

void main() {
  const List<Size> sizes = <Size>[Size(1920, 1080), Size(1440, 900)];

  testWidgets('modulation', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      for (final Size s in sizes) {
        for (final BitSource src in BitSource.values) {
          await _shot(
            tester,
            screen: const ModulationSimulatorScreen(seed: 1),
            light: light,
            size: s,
            slug:
                'modulation_${light ? 'light' : 'dark'}_'
                '${s.width.toInt()}_${src.name}',
            setup: () async {
              final ModulationSimulatorController c = tester
                  .widget<ModulationSimulatorStage>(
                    find.byType(ModulationSimulatorStage),
                  )
                  .controller;
              c.setSource(src);
              for (int i = 0; i < 7; i++) {
                c.step();
              }
            },
          );
        }
      }
    }
  });

  testWidgets('medium access', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      for (final Size s in sizes) {
        await _shot(
          tester,
          screen: const MediumAccessSimulatorScreen(),
          light: light,
          size: s,
          slug: 'medium_access_${light ? 'light' : 'dark'}_${s.width.toInt()}',
          setup: () async {
            final MediumAccessSimulatorController c = tester
                .widget<MediumAccessSimulatorStage>(
                  find.byType(MediumAccessSimulatorStage),
                )
                .controller;
            for (int i = 0; i < 120; i++) {
              c.step();
            }
          },
        );
      }
    }
  });

  testWidgets('room propagation', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      for (final Size s in sizes) {
        await _shot(
          tester,
          screen: const RoomPropagationScreen(runner: _sync),
          light: light,
          size: s,
          slug: 'room_${light ? 'light' : 'dark'}_${s.width.toInt()}',
        );
      }
    }
  });
}
