// Render-proof capture for Joining a Network, Frame by Frame (join-ladder)
// and the Roam mode of the 802.1X and EAP Ladder (NOT a golden, NOT a gate).
// The `_render.dart` suffix keeps it out of the default `flutter test` run:
//
//   JR_RENDER_OUT=/some/dir flutter test \
//       test/screens/calculators/join_ladder_render.dart
//
// The widget tests assert strings, states and that nothing overflows. These
// frames are for looking: the channel strip, the bridged arrows, the M / D
// marks, the lock and shield, the timeline, and the presenter layout, dark
// and light.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_jr_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/join_ladder_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/join_roam.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import '../../widgets/presenter/presenter_test_support.dart';

final String _outDir =
    Platform.environment['JR_RENDER_OUT'] ?? '/tmp/join-ladder-render';

Future<void> _capture(WidgetTester tester, GlobalKey key, String slug) async {
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
}

Future<void> _page(
  WidgetTester tester, {
  required Widget screen,
  required bool light,
  required Size size,
  required String slug,
  required void Function(EapLadderController c) setup,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
  final EapLadderController c = find.byType(JoinRoamStage).evaluate().isEmpty
      ? tester.widget<EapLadderStage>(find.byType(EapLadderStage)).controller
      : tester.widget<JoinRoamStage>(find.byType(JoinRoamStage)).controller;
  setup(c);
  await tester.pumpAndSettle();
  await _capture(tester, key, slug);
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _present(
  WidgetTester tester, {
  required Widget screen,
  required bool light,
  required Size size,
  required String slug,
  required void Function(EapLadderController c) setup,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
  final EapLadderController c = find.byType(JoinRoamStage).evaluate().isEmpty
      ? tester
            .widget<EapLadderStage>(find.byType(EapLadderStage).last)
            .controller
      : tester
            .widget<JoinRoamStage>(find.byType(JoinRoamStage).last)
            .controller;
  setup(c);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 500));
  await _capture(tester, key, slug);
  // ignore: avoid_print
  print('$slug controls overflow ${controlsOverflow(tester)}');
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void _stepTo(EapLadderController c, bool Function(JrMessage m) hit) {
  c.reset();
  while (!c.atEnd) {
    c.step();
    if (hit(c.currentJr!)) return;
  }
}

void main() {
  testWidgets('join pages', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      final String mode = light ? 'light' : 'dark';
      await _page(
        tester,
        screen: const JoinLadderScreen(),
        light: light,
        size: const Size(1280, 3000),
        slug: 'join_psk_assoc_inspect_${mode}_1280',
        setup: (EapLadderController c) {
          c.showAll();
          c.inspect(
            c.jr.messages.indexWhere(
              (JrMessage m) => m.label == 'Association Request',
            ),
          );
        },
      );
      await _page(
        tester,
        screen: const JoinLadderScreen(
          initial: JrConfig(scanType: JrScanType.passive),
        ),
        light: light,
        size: const Size(1280, 3000),
        slug: 'join_passive_dhcp_${mode}_1280',
        setup: (EapLadderController c) =>
            _stepTo(c, (JrMessage m) => m.label == 'DHCP Offer'),
      );
    }
    await _page(
      tester,
      screen: const JoinLadderScreen(
        initial: JrConfig(scanType: JrScanType.passive, passiveDwellMs: 40),
      ),
      light: false,
      size: const Size(1280, 2400),
      slug: 'join_not_found_dark_1280',
      setup: (EapLadderController c) => c.step(),
    );
    await _page(
      tester,
      screen: const JoinLadderScreen(
        initial: JrConfig(security: JrSecurity.dot1x),
      ),
      light: false,
      size: const Size(390, 4200),
      slug: 'join_dot1x_dark_390',
      setup: (EapLadderController c) => c.showAll(),
    );
  });

  testWidgets('presenter', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      final String mode = light ? 'light' : 'dark';
      await _present(
        tester,
        screen: const JoinLadderScreen(
          initial: JrConfig(band: JrBand.g6, scanType: JrScanType.passive),
        ),
        light: light,
        size: const Size(1470, 923),
        slug: 'join_presenter_6ghz_${mode}_1470x923',
        setup: (EapLadderController c) =>
            _stepTo(c, (JrMessage m) => m.label == 'ARP Probe 2 of 3'),
      );
      await _present(
        tester,
        screen: const EapLadderScreen(),
        light: light,
        size: const Size(1470, 923),
        slug: 'roam_presenter_ftds_${mode}_1470x923',
        setup: (EapLadderController c) {
          c.mode = LadderMode.roam;
          c.jrConfig = c.jrConfig.copyWith(roamMethod: JrRoamMethod.ftOverDs);
          c.showAll();
        },
      );
    }
    await _present(
      tester,
      screen: const EapLadderScreen(),
      light: false,
      size: const Size(1440, 900),
      slug: 'authenticate_presenter_dark_1440x900',
      setup: (EapLadderController c) {
        for (int i = 0; i < 12; i++) {
          c.step();
        }
      },
    );
  });

  testWidgets('roam page', (WidgetTester tester) async {
    await _page(
      tester,
      screen: const EapLadderScreen(),
      light: false,
      size: const Size(1280, 3200),
      slug: 'roam_full_dark_1280',
      setup: (EapLadderController c) {
        c.mode = LadderMode.roam;
        c.showAll();
      },
    );
  });
}
