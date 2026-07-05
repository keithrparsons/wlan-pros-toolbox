// Render-proof capture for the LED Decoder's colored-ball indicators (NOT a
// golden test). Writes PNG snapshots of two vendor state tables in BOTH themes
// to the myPKA Deliverables folder so Vera (and Keith) can eyeball the literal
// LED "balls" — color, solid vs flashing, the off / no-signal / undocumented
// glyphs — on both canvases without a device build.
//
// Captured under REDUCED MOTION so the render is deterministic AND the static
// flashing cue (the concentric halo ring around a flashing dot) is visible in
// the still image. The animated pulse is exercised by the widget test, not here.
//
// This is a capture utility, not a regression gate. Run it explicitly:
//   flutter test test/screens/tools/reference/led_decoder_render.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/led_decoder_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _outDir =
    '/Users/keithparsons/myPKA/Deliverables/'
    '2026-07-05-field-trade-reference/led-decoder-renders';

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String filename,
) async {
  final RenderRepaintBoundary boundary = boundaryKey.currentContext!
      .findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final ByteData? bytes =
        await image.toByteData(format: ui.ImageByteFormat.png);
    final File out = File('$_outDir/$filename');
    await out.create(recursive: true);
    await out.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _render(
  WidgetTester tester,
  ThemeData theme,
  String themeName,
  String vendorTapLabel,
  String slug, {
  String? lineTapLabel,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final GlobalKey boundaryKey = GlobalKey();
  final Widget app = RepaintBoundary(
    key: boundaryKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Builder(
        builder: (BuildContext context) {
          // Reduced motion -> deterministic render + the static flashing halo.
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: const LedDecoderScreen(),
          );
        },
      ),
    ),
  );

  await tester.pumpWidget(app);
  await tester.pump();
  await tester.tap(find.text(vendorTapLabel));
  await tester.pumpAndSettle();
  if (lineTapLabel != null) {
    await tester.tap(find.text(lineTapLabel));
    await tester.pumpAndSettle();
  }
  await _capture(tester, boundaryKey, 'led-decoder_${slug}_$themeName.png');
}

void main() {
  // Juniper Mist: the richest palette (green / amber / red / blue / white /
  // purple), solid + flashing, single line so it jumps straight to the table.
  testWidgets('mist dark', (tester) async {
    await _render(tester, AppTheme.dark(), 'dark', 'Juniper Mist', 'mist');
  });
  testWidgets('mist light', (tester) async {
    await _render(tester, AppTheme.light(), 'light', 'Juniper Mist', 'mist');
  });

  // HPE Aruba (Campus, its first line): exercises the neutral "no distinct
  // signal" dash (by-design) and the undocumented "?" glyph (lab-confirm)
  // alongside real colors.
  testWidgets('aruba dark', (tester) async {
    await _render(tester, AppTheme.dark(), 'dark', 'HPE Aruba', 'aruba-campus',
        lineTapLabel: 'Aruba Campus (AOS / Instant)');
  });
  testWidgets('aruba light', (tester) async {
    await _render(tester, AppTheme.light(), 'light', 'HPE Aruba', 'aruba-campus',
        lineTapLabel: 'Aruba Campus (AOS / Instant)');
  });
}
