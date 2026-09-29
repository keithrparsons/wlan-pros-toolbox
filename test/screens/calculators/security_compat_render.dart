// Render-proof capture for Why won't it associate? (spec 43), the security-
// compatibility mode of Association, Frame by Frame (join-ladder). NOT a
// golden, NOT a gate. The `_render.dart` suffix keeps it out of the default
// `flutter test` run:
//
//   SC_RENDER_OUT=/some/dir flutter test \
//       test/screens/calculators/security_compat_render.dart
//
// Frames for looking: each outcome at phone width (390 px, where a long word
// would break mid-word), one wide page, and the presenter layout.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_jr_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/join_ladder_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/join_roam.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/security_compat_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import '../../widgets/presenter/presenter_test_support.dart';

final String _outDir =
    Platform.environment['SC_RENDER_OUT'] ?? '/tmp/security-compat-render';

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

void _why(
  EapLadderController c, {
  required ScClientPreset client,
  required ScNetSecurity net,
  JrBand band = JrBand.g5,
  JrPmf pmf = JrPmf.optional,
  bool wifi7 = false,
}) {
  c.whyMode = true;
  c.jrConfig = c.jrConfig.copyWith(band: band, pmf: pmf);
  c.scPreset = client;
  c.scNetSecurity = net;
  c.apWifi7 = wifi7;
  c.showAll();
}

void main() {
  testWidgets('phone and wide pages', (WidgetTester tester) async {
    const Size phone = Size(390, 5200);
    await _page(
      tester,
      screen: const JoinLadderScreen(),
      light: false,
      size: phone,
      slug: 'sc_never_tries_wpa2_vs_wpa3_dark_390',
      setup: (EapLadderController c) => _why(
        c,
        client: ScClientPreset.olderLaptop,
        net: ScNetSecurity.wpa3Personal,
      ),
    );
    await _page(
      tester,
      screen: const JoinLadderScreen(),
      light: true,
      size: phone,
      slug: 'sc_refused_31_printer_light_390',
      setup: (EapLadderController c) => _why(
        c,
        client: ScClientPreset.printer,
        net: ScNetSecurity.wpa2Personal,
        pmf: JrPmf.required,
      ),
    );
    await _page(
      tester,
      screen: const JoinLadderScreen(),
      light: false,
      size: phone,
      slug: 'sc_not_offered_6ghz_psk_dark_390',
      setup: (EapLadderController c) => _why(
        c,
        client: ScClientPreset.newLaptop,
        net: ScNetSecurity.wpa2Personal,
        band: JrBand.g6,
      ),
    );
    await _page(
      tester,
      screen: const JoinLadderScreen(),
      light: false,
      size: phone,
      slug: 'sc_no_band_6ghz_dark_390',
      setup: (EapLadderController c) => _why(
        c,
        client: ScClientPreset.phoneWpa3,
        net: ScNetSecurity.wpa3Personal,
        band: JrBand.g6,
      ),
    );
    await _page(
      tester,
      screen: const JoinLadderScreen(),
      light: false,
      size: const Size(390, 7400),
      slug: 'sc_wifi7_connection_dark_390',
      setup: (EapLadderController c) => _why(
        c,
        client: ScClientPreset.phoneWifi7,
        net: ScNetSecurity.wpa3Personal,
        wifi7: true,
      ),
    );
    await _page(
      tester,
      screen: const JoinLadderScreen(),
      light: true,
      size: const Size(390, 7400),
      slug: 'sc_wifi6_fallback_light_390',
      setup: (EapLadderController c) => _why(
        c,
        client: ScClientPreset.phoneWifi7,
        net: ScNetSecurity.wpa2Personal,
        wifi7: true,
      ),
    );
    for (final bool light in <bool>[false, true]) {
      await _page(
        tester,
        screen: const JoinLadderScreen(),
        light: light,
        size: const Size(1280, 3600),
        slug: 'sc_transition_assoc_request_${light ? 'light' : 'dark'}_1280',
        setup: (EapLadderController c) {
          _why(
            c,
            client: ScClientPreset.olderLaptop,
            net: ScNetSecurity.wpa3Transition,
          );
          c.inspect(
            c.jr.messages.indexWhere(
              (JrMessage m) => m.label == 'Association Request',
            ),
          );
        },
      );
    }
    // Play the association, at 390 px: the existing mode with the new select.
    await _page(
      tester,
      screen: const JoinLadderScreen(),
      light: false,
      size: const Size(390, 5200),
      slug: 'play_mode_psk_dark_390',
      setup: (EapLadderController c) => c.showAll(),
    );
  });

  testWidgets('presenter', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      await _present(
        tester,
        screen: const JoinLadderScreen(),
        light: light,
        size: const Size(1920, 1080),
        slug: 'sc_presenter_refused_31_${light ? 'light' : 'dark'}_1920x1080',
        setup: (EapLadderController c) => _why(
          c,
          client: ScClientPreset.printer,
          net: ScNetSecurity.wpa2Personal,
          pmf: JrPmf.required,
        ),
      );
    }
    await _present(
      tester,
      screen: const JoinLadderScreen(),
      light: false,
      size: const Size(1440, 900),
      slug: 'sc_presenter_never_tries_dark_1440x900',
      setup: (EapLadderController c) => _why(
        c,
        client: ScClientPreset.olderLaptop,
        net: ScNetSecurity.wpa3Personal,
      ),
    );
    await _present(
      tester,
      screen: const JoinLadderScreen(),
      light: true,
      size: const Size(1470, 923),
      slug: 'sc_presenter_wifi7_light_1470x923',
      setup: (EapLadderController c) => _why(
        c,
        client: ScClientPreset.phoneWifi7,
        net: ScNetSecurity.wpa3Personal,
        wifi7: true,
      ),
    );
  });
}
