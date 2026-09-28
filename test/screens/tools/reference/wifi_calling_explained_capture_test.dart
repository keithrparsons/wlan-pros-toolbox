// Wi-Fi Calling, Explained: full-length screenshots for visual review.
//
// Renders the whole lesson top to bottom, with the REAL bundled figures (the
// asset manifest is loaded, so every figure band draws its SVG), in dark and
// light, at a phone width and a desktop width. The viewport is made tall
// enough that the ListView builds every section, so one PNG is the whole page.
//
// Always renders and asserts (every figure band present, nothing thrown).
// Writes PNGs ONLY when asked, per test/support/figure_write_gate.dart:
//   WRITE_FIGURES=1 flutter test --tags capture \
//     test/screens/tools/reference/wifi_calling_explained_capture_test.dart
// Output: build/wifi-calling-explained-screens/<mode>-<width>.png (gitignored).
@Tags(<String>['capture'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/data/wifi_calling_diagrams.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/wifi_calling_explained_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import '../../../support/figure_write_gate.dart';

const String _outDir = 'build/wifi-calling-explained-screens';
const double _ratio = 2.0;
const double _tall = 26000;

final GlobalKey _key = GlobalKey();

Future<void> _pumpFrames(WidgetTester tester) async {
  for (int i = 0; i < 30; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  for (final bool light in <bool>[false, true]) {
    for (final double width in <double>[393, 1024]) {
      final String name = '${light ? 'light' : 'dark'}-${width.toInt()}';
      testWidgets('captures the full lesson ($name)', (tester) async {
        WifiCallingDiagrams.debugReset();
        WifiCallingExplainedScreen.debugClearFigureCache();
        // flutter_svg's global picture cache holds futures from the previous
        // test's zone, which never complete here; start each capture clean.
        svg.cache.clear();
        await tester.runAsync(WifiCallingDiagrams.ensureLoaded);

        await tester.binding.setSurfaceSize(Size(width, _tall));
        tester.view.physicalSize = Size(width * _ratio, _tall * _ratio);
        tester.view.devicePixelRatio = _ratio;
        addTearDown(() => tester.binding.setSurfaceSize(null));
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(WifiCallingDiagrams.debugReset);

        await tester.pumpWidget(
          RepaintBoundary(
            key: _key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: light ? AppTheme.light() : AppTheme.dark(),
              home: const WifiCallingExplainedScreen(),
            ),
          ),
        );
        await _pumpFrames(tester);

        for (final String slug in <String>[
          'cover-two-roads',
          'f1-two-roads',
          'f8-what-wifi-owes',
        ]) {
          expect(
            find.byKey(ValueKey<String>('wifi-calling-figure-$slug')),
            findsOneWidget,
            reason: '$slug should be bundled and drawn',
          );
        }
        expect(find.text('Where these facts come from'), findsOneWidget);
        expect(tester.takeException(), isNull);

        if (!kWriteFigures) return;
        final RenderRepaintBoundary boundary =
            _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        // Crop to the content: the footer is the last child of the list.
        await tester.runAsync(() async {
          final ui.Image image = await boundary.toImage(pixelRatio: _ratio);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory(_outDir).createSync(recursive: true);
          File(
            '$_outDir/$name.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      });
    }
  }
}
