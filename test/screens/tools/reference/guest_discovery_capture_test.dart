// Why the TV and the Printer Vanish on Guest Wi-Fi: full-length screenshots for visual
// review, on the Find My capture pattern.
//
// Renders the whole lesson in dark and light, at a phone width and a desktop
// width, twice: at the first step, and at step 2 with the switch on Isolation
// (the question stopping at the access point). Always renders and asserts; writes
// PNGs ONLY when asked, per test/support/figure_write_gate.dart:
//   WRITE_FIGURES=1 flutter test --tags capture \
//     test/screens/tools/reference/guest_discovery_capture_test.dart
// Output: build/guest-discovery-screens/<mode>-<width>-<state>.png (gitignored).
@Tags(<String>['capture'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/screens/tools/reference/guest_discovery_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import '../../../support/figure_write_gate.dart';

const String _outDir = 'build/guest-discovery-screens';
const double _ratio = 2.0;
const double _tall = 5200;

final GlobalKey _key = GlobalKey();

Future<void> _write(WidgetTester tester, String name) async {
  if (!kWriteFigures) return;
  final RenderRepaintBoundary boundary =
      _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: _ratio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_outDir).createSync(recursive: true);
    File('$_outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  for (final bool light in <bool>[false, true]) {
    for (final double width in <double>[360, 1024]) {
      final String name = '${light ? 'light' : 'dark'}-${width.toInt()}';
      testWidgets('captures the full lesson ($name)', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, _tall));
        tester.view.physicalSize = Size(width * _ratio, _tall * _ratio);
        tester.view.devicePixelRatio = _ratio;
        addTearDown(() => tester.binding.setSurfaceSize(null));
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          RepaintBoundary(
            key: _key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: light ? AppTheme.light() : AppTheme.dark(),
              home: const GuestDiscoveryScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Where these facts come from'), findsOneWidget);
        await _write(tester, '$name-step1');

        await tester.tap(find.text('Step').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Isolation'));
        await tester.pumpAndSettle();
        expect(find.text('The question stops here'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _write(tester, '$name-step2-isolation');
      });
    }
  }
}
