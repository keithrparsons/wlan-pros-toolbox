// Render-proof capture of the network-group presenter conversions (Channel
// Planner, Roaming Walk, DFS, 802.1X and EAP Ladder, Multi-Link Operation).
// NOT a golden, NOT a gate; the `_render.dart`-style name keeps it out of the
// default `flutter test` run. Same capture as presenter_render.dart, in its
// own file so the four presenter worktrees do not edit one list.
//
//   PRESENTER_RENDER_OUT=/some/dir PRESENTER_RENDER_TOOL=dfs \
//     flutter test test/widgets/presenter/presenter_render_network.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/channel_planner_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/channel_planner_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/channel_planner_state.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dfs_simulator_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dfs_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dfs_simulator_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mlo_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mlo_simulator_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mlo_simulator_state.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/roaming_walk_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/roaming_walk_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/roaming_walk_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/roaming_walk_engine.dart'
    as roam;
import 'package:wlan_pros_toolbox/services/wifi_lab/dfs_model.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/eap_ladder.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/mlo_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import 'presenter_test_support.dart';

final String _outDir =
    Platform.environment['PRESENTER_RENDER_OUT'] ?? '/tmp/presenter-render';
final String? _only = Platform.environment['PRESENTER_RENDER_TOOL'];

const List<Size> _sizes = <Size>[Size(1470, 923)];

Future<void> _shot(
  WidgetTester tester, {
  required Widget screen,
  required bool light,
  required Size size,
  required String slug,
  Future<void> Function()? setup,
  Duration settle = Duration.zero,
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
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.text('Present'));
  await tester.pump(const Duration(milliseconds: 500));
  await setup?.call();
  // Two frames: Material buttons animate their enabled look, and the first
  // frame after a change only starts that animation.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 500));
  if (settle > Duration.zero) await tester.pump(settle);
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
  await tester.pump(const Duration(seconds: 1));
}

bool _want(String tool) => _only == null || _only == tool;

void main() {
  testWidgets('channel planner', (WidgetTester tester) async {
    if (!_want('channel')) return;
    for (final bool light in <bool>[false, true]) {
      for (final Size s in _sizes) {
        await _shot(
          tester,
          screen: const ChannelPlannerScreen(),
          light: light,
          size: s,
          slug:
              'channel-planner-${light ? 'light' : 'dark'}-'
              '${s.width.toInt()}x${s.height.toInt()}',
          setup: () async {
            final ChannelPlannerState c = tester
                .widget<ChannelPlannerStage>(
                  find.byType(ChannelPlannerStage).last,
                )
                .state;
            c.addAp();
            c.addAp();
            c.addWallAcross(vertical: true);
            c.runAutoPlan();
            c.select(2);
          },
        );
      }
    }
  });

  testWidgets('roaming walk', (WidgetTester tester) async {
    if (!_want('roaming')) return;
    for (final bool light in <bool>[false, true]) {
      for (final Size s in _sizes) {
        await _shot(
          tester,
          screen: const RoamingWalkScreen(),
          light: light,
          size: s,
          slug:
              'roaming-walk-${light ? 'light' : 'dark'}-'
              '${s.width.toInt()}x${s.height.toInt()}',
          setup: () async {
            final RoamingWalkController c = tester
                .widget<RoamingWalkStage>(find.byType(RoamingWalkStage).last)
                .controller;
            c.apCount = roam.kMaxAps;
            c.applyPreset(roam.ClientPreset.jumpy);
            c.shadowSigmaDb = 4;
            c.seek(c.result.durationS * 0.6);
          },
        );
      }
    }
  });

  testWidgets('dfs', (WidgetTester tester) async {
    if (!_want('dfs')) return;
    for (final bool light in <bool>[false, true]) {
      for (final Size s in _sizes) {
        await _shot(
          tester,
          screen: const DfsSimulatorScreen(),
          light: light,
          size: s,
          slug:
              'dfs-${light ? 'light' : 'dark'}-'
              '${s.width.toInt()}x${s.height.toInt()}',
          setup: () async {
            final DfsSimulatorController c = tester
                .widget<DfsSimulatorStage>(find.byType(DfsSimulatorStage).last)
                .controller;
            c.region = DfsRegion.eu;
            c.start = c.startChoices.firstWhere(
              (b) => b.components.first == 100,
            );
            c.seek(700);
            c.radarNow();
            c.seek(760);
          },
        );
      }
    }
  });

  testWidgets('eap ladder', (WidgetTester tester) async {
    if (!_want('eap')) return;
    for (final bool light in <bool>[false, true]) {
      for (final Size s in _sizes) {
        await _shot(
          tester,
          screen: const EapLadderScreen(),
          light: light,
          size: s,
          slug:
              'eap-ladder-${light ? 'light' : 'dark'}-'
              '${s.width.toInt()}x${s.height.toInt()}',
          setup: () async {
            final EapLadderController c = tester
                .widget<EapLadderStage>(find.byType(EapLadderStage).last)
                .controller;
            c.method = LadderMethod.eapTtls;
            c.certFragments = 4;
            for (int i = 0; i < 17; i++) {
              c.step();
            }
          },
        );
      }
    }
  });

  testWidgets('mlo', (WidgetTester tester) async {
    if (!_want('mlo')) return;
    for (final bool light in <bool>[false, true]) {
      for (final Size s in _sizes) {
        await _shot(
          tester,
          screen: const MloSimulatorScreen(),
          light: light,
          size: s,
          slug:
              'mlo-${light ? 'light' : 'dark'}-'
              '${s.width.toInt()}x${s.height.toInt()}',
          setup: () async {
            final MloSimulatorState c = tester
                .widget<MloSimulatorStage>(find.byType(MloSimulatorStage).last)
                .state;
            c.setBandEnabled(MloBand.ghz24, true);
            c.laneMode = MloMode.emlsr;
          },
        );
      }
    }
  });
}
