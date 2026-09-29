// Vera gate A fixes (2026-09-29): Presenter frames of the two reworded
// Stopped-band sentences. Render proof only, not a gate.
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

void main() {
  testWidgets('capture presenter 1470x923, Vera fixes', (
    WidgetTester tester,
  ) async {
    for (final LadderMethod m in <LadderMethod>[
      LadderMethod.eapTls,
      LadderMethod.peap,
    ]) {
      for (final LadderFault f in <LadderFault>[
        LadderFault.untrustedServerCert,
        LadderFault.wrongRadiusSecret,
      ]) {
        setWindow(tester, const Size(1470, 923));
        installFakeWindow();
        final GlobalKey key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.dark(),
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
        c.method = m;
        c.fault = f;
        c.showAll();
        await tester.pumpAndSettle();
        await _capture(tester, key, 'presenter_${m.name}_${f.name}_1470');
      }
    }
  });
}
