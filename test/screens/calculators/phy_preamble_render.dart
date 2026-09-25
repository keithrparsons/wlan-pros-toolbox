// Render-proof capture for the PHY Preamble Reference screen (NOT a golden,
// NOT a gate). The `_render.dart` suffix keeps it out of the default
// `flutter test` run, so it only executes when asked:
//
//   flutter test test/screens/calculators/phy_preamble_render.dart
//
// The widget tests assert strings, states and that nothing scrolls sideways.
// They cannot say whether the leader labels read, whether sand and blue sit
// apart on both themes, or whether a bit table is comfortable on a phone.
// These frames are for looking: Legacy, VHT and HE SU with a bit table open,
// dark and light, 390 and 1280 px, plus HE MU, EHT MU and a mystery walk.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/phy_preamble_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/phy_preamble_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/phy_preamble_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/phy_preamble.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _outDir =
    '/Users/keithparsons/myPKA/Deliverables/'
    '2026-09-25-wifi-lab-cleanroom/evidence/phy-preamble';

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  required PreambleSettings settings,
  String? open,
  PreambleMode mode = PreambleMode.explore,
  void Function(PhyPreambleModel m)? setup,
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
        home: PhyPreambleScreen(
          key: UniqueKey(),
          initial: settings,
          initialMode: mode,
          initialSelection: open,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (setup != null) {
    setup(tester.widget<PhyPreambleStage>(find.byType(PhyPreambleStage)).model);
    await tester.pumpAndSettle();
  }
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

void main() {
  testWidgets('capture', (WidgetTester tester) async {
    final List<(PreambleSettings, String, String)> cases =
        <(PreambleSettings, String, String)>[
          (const PreambleSettings(type: PpduType.nonHt), 'L-SIG', 'legacy'),
          (
            const PreambleSettings(type: PpduType.vht, streams: 3),
            'VHT-SIG-A',
            'vht',
          ),
          (
            const PreambleSettings(type: PpduType.heSu, streams: 2),
            'HE-SIG-A',
            'he_su',
          ),
        ];
    for (final bool light in <bool>[false, true]) {
      final String mode = light ? 'light' : 'dark';
      for (final double w in <double>[390, 1280]) {
        final Size size = Size(w, w < 720 ? 7000 : 6000);
        final int px = w.round();
        for (final (PreambleSettings s, String open, String slug) c in cases) {
          await _shot(
            tester,
            light: light,
            size: size,
            slug: '${c.$3}_${mode}_$px',
            settings: c.$1,
            open: c.$2,
          );
        }
      }
    }
    await _shot(
      tester,
      light: false,
      size: const Size(390, 6000),
      slug: 'he_mu_sigb_dark_390',
      settings: const PreambleSettings(
        type: PpduType.heMu,
        streams: 4,
        sigSymbols: 3,
      ),
      open: 'HE-SIG-B',
    );
    await _shot(
      tester,
      light: true,
      size: const Size(390, 3600),
      slug: 'eht_mu_usig_light_390',
      settings: const PreambleSettings(
        type: PpduType.ehtMu,
        streams: 2,
        ltf: HeLtfMode.x4gi32,
      ),
      open: 'U-SIG',
    );
    await _shot(
      tester,
      light: false,
      size: const Size(390, 2400),
      slug: 'mystery_midwalk_dark_390',
      settings: const PreambleSettings(type: PpduType.heErSu),
      mode: PreambleMode.identify,
      setup: (PhyPreambleModel m) {
        // A mystery, then force a known type through the same path the
        // model uses, two questions in.
        m.newMystery();
        m.stepWalk();
        m.stepWalk();
      },
    );
    await _shot(
      tester,
      light: true,
      size: const Size(1280, 2400),
      slug: 'walk_done_ersu_light_1280',
      settings: const PreambleSettings(type: PpduType.heErSu),
      mode: PreambleMode.identify,
      setup: (PhyPreambleModel m) => m.revealWalk(),
    );
    await _shot(
      tester,
      light: false,
      size: const Size(390, 4200),
      slug: 'vht_8ss_sigb40_dark_390',
      settings: const PreambleSettings(
        type: PpduType.vht,
        streams: 8,
        widthMhz: 40,
      ),
      open: 'VHT-SIG-B',
    );
  });
}
