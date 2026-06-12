@Tags(['capture'])
library;

// Re-gate capture harness for the Telephone Signaling History modes
// (DTMF / Blue Box / Red Box) — produced 2026-06-12 for Vera's re-gate of the
// light-mode disabled-foreground fix (GL-003 §8.3 / §8.20.1: light textDisabled
// 0xFF9A9A9A -> 0xFF6E6E6E, 2.37:1 -> 4.29:1 on disabledFill #ECEBEC).
//
// Renders the DTMF Generator screen in all three modes, at BOTH phone (390px)
// and desktop (1000px) widths, in BOTH dark and light themes, and writes PNGs
// straight to the prior gate's screenshot dir with a `regate-` prefix.
//
// The DTMF-mode render captures the "Play sequence" FilledButton in its DISABLED
// state at rest: the sequence TextField is empty, so onPressed == null. That is
// the previously-failing light-mode control Vera flagged; the light DTMF renders
// are where the 4.29:1 fix is verifiable.
//
// Tagged `capture` so a normal `flutter test` ignores it. Run:
//   flutter test --tags capture test/play_screenshots/regate_signaling_history_test.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/screens/tools/calculators/dtmf_generator_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const double kH = 1100;
const double kRatio = 2.0;
const String kOut =
    '/Users/keithparsons/Documents/myPKA/Deliverables/2026-06-11-redbox-bluebox-feasibility/screenshots';

final GlobalKey _key = GlobalKey();

Widget _host(ThemeData theme, double width) => MediaQuery(
      data: MediaQueryData(
        size: Size(width, kH),
        devicePixelRatio: kRatio,
        textScaler: const TextScaler.linear(1.0),
      ),
      child: RepaintBoundary(
        key: _key,
        child: SizedBox(
          width: width,
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
    File('$kOut/$id.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('WROTE $id.png ${image.width}x${image.height}');
    image.dispose();
  });
}

Future<void> _shoot(
  WidgetTester tester, {
  required String id,
  required ThemeData theme,
  required double width,
  String? tapMode,
}) async {
  await tester.binding.setSurfaceSize(Size(width, kH));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = Size(width * kRatio, kH * kRatio);
  tester.view.devicePixelRatio = kRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_host(theme, width));
  await tester.pumpAndSettle();
  if (tapMode != null) {
    await tester.tap(find.text(tapMode));
    await tester.pumpAndSettle();
  }
  // No signal key is tapped — that reaches just_audio, which has no headless
  // backend. The pad, honesty note, sequence card (with the DISABLED, empty-field
  // "Play sequence" button) and readout all render fully without it.
  await _write(tester, id);
}

void main() {
  for (final (String wName, double width) in <(String, double)>[
    ('phone', 390),
    ('desktop', 1000),
  ]) {
    for (final (String tName, ThemeData theme) in <(String, ThemeData)>[
      ('dark', AppTheme.dark()),
      ('light', AppTheme.light()),
    ]) {
      testWidgets('regate $wName $tName — DTMF mode (disabled Play sequence)',
          (tester) async {
        await _shoot(
          tester,
          id: 'regate-dtmf-$wName-$tName',
          theme: theme,
          width: width,
        );
      });

      testWidgets('regate $wName $tName — Blue Box mode', (tester) async {
        await _shoot(
          tester,
          id: 'regate-bluebox-$wName-$tName',
          theme: theme,
          width: width,
          tapMode: 'Blue Box',
        );
      });

      testWidgets('regate $wName $tName — Red Box mode', (tester) async {
        await _shoot(
          tester,
          id: 'regate-redbox-$wName-$tName',
          theme: theme,
          width: width,
          tapMode: 'Red Box',
        );
      });
    }
  }
}
