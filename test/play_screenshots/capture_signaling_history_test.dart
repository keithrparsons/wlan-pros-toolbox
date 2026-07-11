@Tags(['capture'])
library;

// Capture harness for the Telephone Signaling History modes (2026-06-11) — for
// Felix's self-check and Vera's visual gate. Renders the DTMF Generator screen
// in all three modes (DTMF / Blue Box / Red Box), at phone width, in both dark
// and light themes, and writes PNGs to play_screenshots/signaling-history/.
//
// Tagged `capture` so a normal `flutter test` ignores it (asserts no committed
// baseline). Run:
//   flutter test --tags capture test/play_screenshots/capture_signaling_history_test.dart

import 'dart:io';

import '../support/figure_write_gate.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/screens/tools/calculators/dtmf_generator_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const double kW = 390;
const double kH = 1100;
const double kRatio = 2.0;
const String kOut = 'play_screenshots/signaling-history';

final GlobalKey _key = GlobalKey();

Widget _host(ThemeData theme) => MediaQuery(
      data: const MediaQueryData(
        size: Size(kW, kH),
        devicePixelRatio: kRatio,
        textScaler: TextScaler.linear(1.0),
      ),
      child: RepaintBoundary(
        key: _key,
        child: SizedBox(
          width: kW,
          height: kH,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: const DtmfGeneratorScreen(),
          ),
        ),
      ),
    );

Future<void> _write(WidgetTester tester, String id) async {
  final RenderRepaintBoundary boundary =
      _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: kRatio);
    final ByteData? bytes =
        await image.toByteData(format: ui.ImageByteFormat.png);
    final Directory dir = Directory(kOut);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    if (kWriteFigures) {
      File('$kOut/$id.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }
    // ignore: avoid_print
    print('WROTE $id.png ${image.width}x${image.height}');
    image.dispose();
  });
}

Future<void> _shoot(
  WidgetTester tester, {
  required String id,
  required ThemeData theme,
  String? tapMode,
}) async {
  await tester.binding.setSurfaceSize(const Size(kW, kH));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = const Size(kW * kRatio, kH * kRatio);
  tester.view.devicePixelRatio = kRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_host(theme));
  await tester.pumpAndSettle();
  if (tapMode != null) {
    await tester.tap(find.text(tapMode));
    await tester.pumpAndSettle();
  }
  // Note: we do NOT tap a signal key here — that would reach just_audio, which
  // has no headless backend. The pad, honesty note, and empty readout render
  // fully without it, which is what the visual gate needs.
  await _write(tester, id);
}

void main() {
  for (final (String name, ThemeData theme) in <(String, ThemeData)>[
    ('dark', AppTheme.dark()),
    ('light', AppTheme.light()),
  ]) {
    testWidgets('$name — DTMF mode', (tester) async {
      await _shoot(tester, id: 'dtmf-$name', theme: theme);
    });

    testWidgets('$name — Blue Box mode', (tester) async {
      await _shoot(
        tester,
        id: 'bluebox-$name',
        theme: theme,
        tapMode: 'Blue Box',
      );
    });

    testWidgets('$name — Red Box mode', (tester) async {
      await _shoot(
        tester,
        id: 'redbox-$name',
        theme: theme,
        tapMode: 'Red Box',
      );
    });
  }
}
