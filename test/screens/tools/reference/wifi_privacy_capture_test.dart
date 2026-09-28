// Wi-Fi Privacy Myths lesson: full-length screenshots for visual review, at phone,
// tablet and desktop widths, dark and light, Off with the name shown, and Rotating with it hidden.
//
// Always renders and asserts (nothing thrown). Writes PNGs ONLY when asked,
// per test/support/figure_write_gate.dart:
//   WRITE_FIGURES=1 flutter test --tags capture \
//     test/screens/tools/reference/wifi_privacy_capture_test.dart
// Output: build/wifi-privacy-myths-screens/<mode>-<width>-<state>.png (gitignored).
@Tags(<String>['capture'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/screens/tools/reference/wifi_privacy_lesson_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_toggle.dart';

import '../../../support/figure_write_gate.dart';

const String _outDir = 'build/wifi-privacy-myths-screens';
const double _ratio = 2.0;
const double _tall = 7000;

final GlobalKey _key = GlobalKey();

void main() {
  for (final bool light in <bool>[false, true]) {
    for (final double width in <double>[393, 768, 1024]) {
      for (final bool changed in <bool>[false, true]) {
        final String name =
            '${light ? 'light' : 'dark'}-${width.toInt()}-'
            '${changed ? 'rotating-hidden' : 'off-shown'}';
        testWidgets('captures the lesson ($name)', (tester) async {
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
                home: const WifiPrivacyLessonScreen(),
              ),
            ),
          );
          await tester.pump();

          if (changed) {
            for (final (String toggle, String seg) in <(String, String)>[
              ('Private Wi-Fi address', 'Rotating'),
              ('Hide the network name', 'On'),
            ]) {
              await tester.tap(
                find.descendant(
                  of: find.byWidgetPredicate(
                    (Widget w) => w is AppToggle && w.label == toggle,
                  ),
                  matching: find.text(seg),
                ),
              );
              await tester.pump();
            }
            expect(find.text('Turned away'), findsOneWidget);
            expect(find.text('Network name: (blank)'), findsOneWidget);
          }
          expect(find.text('Where these facts come from'), findsOneWidget);
          expect(tester.takeException(), isNull);

          if (!kWriteFigures) return;
          final RenderRepaintBoundary boundary =
              _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final ui.Image image = await boundary.toImage(pixelRatio: _ratio);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            Directory(_outDir).createSync(recursive: true);
            File(
              '$_outDir/$name.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
          });
        });
      }
    }
  }
}
