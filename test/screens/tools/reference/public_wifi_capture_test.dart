// Public Wi-Fi lesson: full-length screenshots for visual review, at phone,
// tablet and desktop widths, dark and light, on Open and on WPA2-Personal.
//
// Always renders and asserts (nothing thrown). Writes PNGs ONLY when asked,
// per test/support/figure_write_gate.dart:
//   WRITE_FIGURES=1 flutter test --tags capture \
//     test/screens/tools/reference/public_wifi_capture_test.dart
// Output: build/public-wifi-screens/<mode>-<width>-<network>.png (gitignored).
@Tags(<String>['capture'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/screens/tools/reference/public_wifi_lesson_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_toggle.dart';

import '../../../support/figure_write_gate.dart';

const String _outDir = 'build/public-wifi-screens';
const double _ratio = 2.0;
const double _tall = 7000;

final GlobalKey _key = GlobalKey();

void main() {
  for (final bool light in <bool>[false, true]) {
    for (final double width in <double>[393, 768, 1024]) {
      for (final bool wpa2 in <bool>[false, true]) {
        final String name =
            '${light ? 'light' : 'dark'}-${width.toInt()}-'
            '${wpa2 ? 'wpa2' : 'open'}';
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
                home: const PublicWifiLessonScreen(),
              ),
            ),
          );
          await tester.pump();

          if (wpa2) {
            // Password is a toggle segment on wide screens, a select item on
            // a phone.
            final Finder seg = find.descendant(
              of: find.byWidgetPredicate((Widget w) => w is AppToggle),
              matching: find.text('Password'),
            );
            if (seg.evaluate().isNotEmpty) {
              await tester.tap(seg);
            } else {
              await tester.tap(find.text('Open').first);
              await tester.pumpAndSettle();
              await tester.tap(find.text('Password').last);
            }
            await tester.pumpAndSettle();
            expect(
              find.text('What the person next to you can see on WPA2-Personal'),
              findsOneWidget,
            );
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
