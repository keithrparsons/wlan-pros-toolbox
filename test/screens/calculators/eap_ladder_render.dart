// Render-proof capture for the 802.1X and EAP Ladder screen (NOT a golden,
// NOT a gate). The `_render.dart` suffix keeps it out of the default
// `flutter test` run, so it only executes when asked:
//
//   flutter test test/screens/calculators/eap_ladder_render.dart
//
// The widget tests assert strings, states and that nothing overflows. They
// cannot say whether labels fit between the lanes, whether the two leg hues
// read apart on both themes, or whether the milestone bands sit well. These
// frames are for looking: EAP-TLS, PEAP and SAE, dark and light, 390 and
// 1280 px.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/eap_ladder.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _outDir =
    '/Users/keithparsons/myPKA/Deliverables/'
    '2026-09-25-wifi-lab-cleanroom/evidence/eap-ladder';

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  required LadderConfig config,
  required void Function(EapLadderController c) setup,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: light ? AppTheme.light() : AppTheme.dark(),
        home: EapLadderScreen(key: UniqueKey(), initial: config),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final EapLadderController c = tester
      .widget<EapLadderStage>(find.byType(EapLadderStage))
      .controller;
  setup(c);
  await tester.pumpAndSettle();
  final RenderRepaintBoundary boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
    final ByteData? bytes = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final File out = File('$_outDir/$slug.png');
    await out.create(recursive: true);
    await out.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void _stepTo(EapLadderController c, bool Function(LadderMessage m) hit) {
  c.reset();
  while (!c.atEnd) {
    c.step();
    if (hit(c.current!)) return;
  }
}

void main() {
  testWidgets('capture', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      final String mode = light ? 'light' : 'dark';
      for (final double w in <double>[390, 1280]) {
        final Size size = Size(w, w < 720 ? 2900 : 2300);
        final int px = w.round();
        await _shot(
          tester,
          light: light,
          size: size,
          slug: 'eap_tls_keys_${mode}_$px',
          config: const LadderConfig(certFragments: 2),
          setup: (EapLadderController c) =>
              _stepTo(c, (LadderMessage m) => m.label == 'Access-Accept'),
        );
        await _shot(
          tester,
          light: light,
          size: size,
          slug: 'peap_tunnel_${mode}_$px',
          config: const LadderConfig(method: LadderMethod.peap),
          setup: (EapLadderController c) => _stepTo(
            c,
            (LadderMessage m) =>
                m.tunneled && (m.detail ?? '').contains('Response'),
          ),
        );
        await _shot(
          tester,
          light: light,
          size: size,
          slug: 'sae_all_${mode}_$px',
          config: const LadderConfig(method: LadderMethod.sae),
          setup: (EapLadderController c) => c.showAll(),
        );
      }
    }
    await _shot(
      tester,
      light: false,
      size: const Size(390, 2900),
      slug: 'fresh_dark_390',
      config: const LadderConfig(),
      setup: (EapLadderController c) {},
    );
    await _shot(
      tester,
      light: false,
      size: const Size(390, 2900),
      slug: 'ft_all_dark_390',
      config: const LadderConfig(
        method: LadderMethod.peap,
        roam: LadderRoam.ftOverAir,
      ),
      setup: (EapLadderController c) => c.showAll(),
    );
  });
}
