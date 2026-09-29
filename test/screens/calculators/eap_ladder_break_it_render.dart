// Render-proof capture for Break it on the 802.1X and EAP Ladder (spec 42).
// NOT a golden, NOT a gate: the `_render.dart` suffix keeps it out of the
// default `flutter test` run. Run it when asked:
//
//   flutter test test/screens/calculators/eap_ladder_break_it_render.dart
//
// The widget tests prove the marks exist and nothing overflows; these frames
// are for looking at the red X, the lost arrow, the Stopped here band and
// the help-desk caption, at phone width in both themes and in the presenter
// at 1920x1080.

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

import '../../widgets/presenter/presenter_test_support.dart';

const String _outDir =
    '/Users/keithparsons/myPKA/Deliverables/'
    '2026-09-29-classroom-eight-features/evidence/eap-break-it';

Future<void> _capture(WidgetTester tester, GlobalKey key, String slug) async {
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

Future<void> _phone(
  WidgetTester tester, {
  required bool light,
  required String slug,
  required LadderConfig config,
  required void Function(EapLadderController c) setup,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 3000));
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
  setup(tester.widget<EapLadderStage>(find.byType(EapLadderStage)).controller);
  await tester.pumpAndSettle();
  await _capture(tester, key, slug);
}

void main() {
  testWidgets('capture phone', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      final String mode = light ? 'light' : 'dark';
      await _phone(
        tester,
        light: light,
        slug: 'untrusted_cert_end_${mode}_390',
        config: const LadderConfig(fault: LadderFault.untrustedServerCert),
        setup: (EapLadderController c) => c.showAll(),
      );
      await _phone(
        tester,
        light: light,
        slug: 'wrong_secret_end_${mode}_390',
        config: const LadderConfig(
          method: LadderMethod.peap,
          fault: LadderFault.wrongRadiusSecret,
        ),
        setup: (EapLadderController c) => c.showAll(),
      );
      await _phone(
        tester,
        light: light,
        slug: 'wrong_psk_end_${mode}_390',
        config: const LadderConfig(
          method: LadderMethod.psk,
          fault: LadderFault.wrongPsk,
        ),
        setup: (EapLadderController c) => c.showAll(),
      );
    }
    await _phone(
      tester,
      light: false,
      slug: 'peap_wrong_password_at_failure_dark_390',
      config: const LadderConfig(
        method: LadderMethod.peap,
        fault: LadderFault.wrongPassword,
      ),
      setup: (EapLadderController c) {
        while (!c.atEnd) {
          c.step();
          if (c.current!.failure) return;
        }
      },
    );
  });

  testWidgets('capture presenter 1920x1080', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      setWindow(tester, const Size(1920, 1080));
      installFakeWindow();
      final GlobalKey key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: light ? AppTheme.light() : AppTheme.dark(),
            home: EapLadderScreen(key: UniqueKey()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Present'));
      await tester.pumpAndSettle();
      final EapLadderController c = tester
          .widget<EapLadderStage>(find.byType(EapLadderStage).last)
          .controller;
      c.method = LadderMethod.peap;
      c.fault = LadderFault.untrustedServerCert;
      c.showAll();
      await tester.pumpAndSettle();
      await _capture(
        tester,
        key,
        'presenter_untrusted_cert_end_${light ? 'light' : 'dark'}_1920',
      );
    }
  });
}
