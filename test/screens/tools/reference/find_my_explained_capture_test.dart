// Find My, Explained: full-length screenshots for visual review.
//
// Renders the whole lesson top to bottom, with the REAL bundled figures (the
// asset manifest is loaded, so every figure band draws its SVG), in dark and
// light, at a phone width and a desktop width. The viewport is made tall
// enough that the ListView builds every section, so one PNG is the whole page.
//
// Always renders and asserts (every figure band present, nothing thrown).
// Writes PNGs ONLY when asked, per test/support/figure_write_gate.dart:
//   WRITE_FIGURES=1 flutter test --tags capture \
//     test/screens/tools/reference/find_my_explained_capture_test.dart
// Output: build/find-my-explained-screens/<mode>-<width>.png (gitignored).
@Tags(<String>['capture'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/data/find_my_diagrams.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/find_my_explained_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import '../../../support/figure_write_gate.dart';

const String _outDir = 'build/find-my-explained-screens';
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
        FindMyDiagrams.debugReset();
        FindMyExplainedScreen.debugClearFigureCache();
        // flutter_svg's global picture cache holds futures from the previous
        // test's zone, which never complete here; start each capture clean.
        svg.cache.clear();
        await tester.runAsync(FindMyDiagrams.ensureLoaded);

        await tester.binding.setSurfaceSize(Size(width, _tall));
        tester.view.physicalSize = Size(width * _ratio, _tall * _ratio);
        tester.view.devicePixelRatio = _ratio;
        addTearDown(() => tester.binding.setSurfaceSize(null));
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(FindMyDiagrams.debugReset);

        await tester.pumpWidget(
          RepaintBoundary(
            key: _key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: light ? AppTheme.light() : AppTheme.dark(),
              home: const FindMyExplainedScreen(),
            ),
          ),
        );
        await _pumpFrames(tester);

        for (final String slug in <String>[
          'cover-people-devices-items',
          'f1-find-my-network',
          'f8-unwanted-tracker',
        ]) {
          expect(
            find.byKey(ValueKey<String>('find-my-figure-$slug')),
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
          File('$_outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      });
    }
  }
}
