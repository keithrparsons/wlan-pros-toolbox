// Render-proof capture for the 1.12 merge of the three ladder branches
// (security-compat, eap-break-it, six-ghz-race). NOT a golden, NOT a gate.
// The `_render.dart` suffix keeps it out of the default `flutter test` run:
//
//   MERGE112_RENDER_OUT=/some/dir flutter test \
//       test/screens/calculators/merge_112_render.dart
//
// Presenter at 1920x1080, dark: Association, Frame by Frame in Why won't it
// associate?; the same after pressing S (the race is not offered there, so
// the frame must not change); the race on in Play the association; the
// 802.1X and EAP Ladder with a Break it fault; and the ? list in each mode.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_jr_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/join_ladder_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/eap_ladder.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/join_roam.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/security_compat_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import '../../widgets/presenter/presenter_test_support.dart';

final String _outDir =
    Platform.environment['MERGE112_RENDER_OUT'] ?? '/tmp/merge-112-render';

const Size _window = Size(1920, 1080);

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

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 500));
}

/// Opens [screen] in the presenter, runs [setup] (which may press keys),
/// and captures [slug]. With [keys], opens the ? list and captures it too.
Future<void> _present(
  WidgetTester tester, {
  required Widget screen,
  required String slug,
  required Future<void> Function(EapLadderController c) setup,
  bool keys = false,
}) async {
  await tester.binding.setSurfaceSize(_window);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = _window;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  installFakeWindow();
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
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
  await setup(c);
  await _settle(tester);
  await _capture(tester, key, slug);
  // ignore: avoid_print
  print(
    '$slug: mode ${c.mode.name}, why ${c.whyMode}, race ${c.raceActive}, '
    'keys ${c.presenterActions.extra.map((e) => e.keyLabel).join(' ')}, '
    'controls overflow ${controlsOverflow(tester)}',
  );
  if (keys) {
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await _settle(tester);
    await _capture(tester, key, '$slug--keys');
  }
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void _why(EapLadderController c) {
  c.whyMode = true;
  c.scPreset = ScClientPreset.olderLaptop;
  c.scNetSecurity = ScNetSecurity.wpa3Personal;
  c.showAll();
}

void main() {
  testWidgets('merge 1.12 presenter renders', (WidgetTester tester) async {
    await _present(
      tester,
      screen: const JoinLadderScreen(),
      slug: '01_association_why_wont_it_associate_dark_1920x1080',
      keys: true,
      setup: (EapLadderController c) async => _why(c),
    );
    await _present(
      tester,
      screen: const JoinLadderScreen(),
      slug: '02_association_why_then_S_pressed_dark_1920x1080',
      setup: (EapLadderController c) async {
        _why(c);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.pump();
      },
    );
    await _present(
      tester,
      screen: const JoinLadderScreen(),
      slug: '03_association_race_on_play_the_association_dark_1920x1080',
      keys: true,
      setup: (EapLadderController c) async {
        // From Why won't it associate?, back to Play the association, then S.
        _why(c);
        await tester.pump();
        c.whyMode = false;
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.pump();
        c.showAll();
      },
    );
    await _present(
      tester,
      screen: const EapLadderScreen(),
      slug: '04_8021x_break_it_untrusted_cert_dark_1920x1080',
      keys: true,
      setup: (EapLadderController c) async {
        c.method = LadderMethod.peap;
        c.fault = LadderFault.untrustedServerCert;
        c.showAll();
      },
    );
    await _present(
      tester,
      screen: const EapLadderScreen(),
      slug: '05_8021x_roam_dark_1920x1080',
      keys: true,
      setup: (EapLadderController c) async {
        c.mode = LadderMode.roam;
        c.showAll();
      },
    );
  });
}
