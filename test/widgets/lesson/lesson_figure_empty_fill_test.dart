// A lesson figure's gridlines draw at their own color, as a browser draws
// them. Regression guard for Weak Cell Signal Figure 10 (step 9): its
// #E5E5E5 gridlines drew at 178/255 in the app and ran dark through the bar
// labels, because a <line> inherits SVG's default black fill, flutter_svg
// fills the empty path, and the antialiased edge leaks black into the two
// pixels a line straddles. tool/extract_lesson_figures.py now writes
// fill="none" on every shape with no area (unfill_empty_shapes).

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Weak Cell Signal Figure 10 gridlines are never darker than '
      'their own #E5E5E5 stroke', (WidgetTester tester) async {
    final GlobalKey boundary = GlobalKey();
    // The figure's own viewBox size, at 1x: the 80 dB gridline sits at
    // x = 640.00, on a pixel edge, where the fill leak showed.
    await tester.binding.setSurfaceSize(const Size(800, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: boundary,
            child: Container(
              color: const Color(0xFFFFFFFF),
              width: 720,
              height: 176,
              child: SvgPicture.asset(
                'assets/lesson-figures/weak-cell-signal/fig-10.svg',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    final List<int> reds = await tester.runAsync<List<int>>(() async {
          final RenderRepaintBoundary rb =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final ui.Image image = await rb.toImage();
          final ByteData raw = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          // Row 100 lies between the second and third bars, clear of text.
          int red(int x) => raw.getUint8((100 * image.width + x) * 4);
          return <int>[red(639), red(640)];
        }) ??
        <int>[];

    expect(reds, hasLength(2));
    // #E5E5E5 is 229. Half coverage on white is about 242; nothing on this
    // line may come out darker than the stroke itself.
    for (final int r in reds) {
      expect(r, greaterThanOrEqualTo(0xE5), reason: 'gridline pixels $reds');
    }
    // And the line is drawn at all.
    expect(reds.any((int r) => r < 0xFF), isTrue, reason: 'pixels $reds');
  });
}
