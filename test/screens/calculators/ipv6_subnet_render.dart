// Render-proof capture for the IPv6 Subnet screen (NOT a golden, NOT a gate).
// Same shape as led_decoder_render.dart: a `_render.dart` suffix keeps it out
// of the default `flutter test` run, so it only executes when asked.
//
//   flutter test test/screens/calculators/ipv6_subnet_render.dart
//
// WHAT IT IS FOR. Two things on this screen are only checkable by looking:
//
//   1. THE TWO CARDS AGREE. The Subnet card's Compressed row and the
//      transition card's "Same, in hex" row are ~200 px apart and used to
//      print two different compressions of one address (Vera's gate, HIGH-1,
//      2026-08-02). `mapped_*` puts both in one frame.
//   2. THE ZONE CAVEAT FITS. It is the longest wrapped prose the Subnet card
//      renders and it interpolates numbers, so its worst case is the "%2512"
//      string at the narrowest supported width.
//
// The widget tests assert the STRINGS and that nothing overflows. They cannot
// say whether a reader can read it. That is what these frames are for.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ipv6_subnet_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _outDir =
    '/Users/keithparsons/myPKA/Deliverables/'
    '2026-08-02-ip-address-math-gate/evidence/felix-fix-renders';

Future<void> _shot(
  WidgetTester tester,
  String address,
  String prefix,
  bool light,
  Size size,
  String slug,
) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        theme: light ? AppTheme.light() : AppTheme.dark(),
        home: const Ipv6SubnetScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), address);
  await tester.enterText(find.byType(TextField).at(1), prefix);
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

void main() {
  testWidgets('capture the fixed surfaces', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      final String mode = light ? 'light' : 'dark';
      await _shot(
        tester,
        '::ffff:192.0.2.1',
        '96',
        light,
        const Size(390, 1500),
        'mapped_${mode}_390',
      );
      await _shot(
        tester,
        'fe80::1%2512',
        '64',
        light,
        const Size(390, 1100),
        'zone_2512_${mode}_390',
      );
      await _shot(
        tester,
        'fe80::1%25',
        '64',
        light,
        const Size(320, 1100),
        'zone_25_${mode}_320',
      );
      await _shot(
        tester,
        'fe80::1%en0',
        '64',
        light,
        const Size(1280, 1100),
        'zone_en0_${mode}_1280',
      );
    }
  });
}
