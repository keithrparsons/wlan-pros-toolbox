// Sparkline — rendered-pixel golden tests (visual-regression coverage).
//
// sparkline_test.dart asserts the widget renders without throwing across the
// edge cases and that the a11y contract holds, but no one had snapshotted the
// actual painted pixels — so a geometry regression (a broken polyline, a
// missing latest-dot, a gap drawn as a line through a fabricated 0) could ship
// unseen. These goldens lock the painter output for two representative cases:
//
//   * multipoint  — a multi-sample line that ends on a PRESENT sample, so both
//                   the polyline and the latest-point dot render.
//   * null_gap    — a window with an interior gap (a null) AND a trailing gap,
//                   proving the line breaks at the gap and the head stays
//                   undotted when the most recent sample is absent.
//
// The chart is decorative (ExcludeSemantics in the widget); these tests are the
// VISUAL guard the semantic tests cannot give.
//
// Generating the baselines (Larry runs centrally):
//   flutter test --update-goldens test/widgets/sparkline_golden_test.dart
// then eyeball test/widgets/goldens/sparkline_*.png before commit —
// --update-goldens writes whatever renders, so the first generation IS the
// visual gate. Re-running without the flag compares against the baselines and
// fails on any pixel drift.
//
// The line color is pinned to the §8.3 lime primary so the baseline does not
// depend on a caller passing a status tint.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/theme/app_tokens.dart';
import 'package:wlan_pros_toolbox/widgets/sparkline.dart';

// A fixed capture box: a realistic inline-chart footprint, big enough that the
// polyline and the 2.5px latest-dot are both legible in the baseline.
const Size _captureSize = Size(200, 40);

Future<void> _pumpAndCapture(
  WidgetTester tester,
  List<double?> values,
  String goldenPath,
) async {
  tester.view.physicalSize = _captureSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        // A flat dark surface so the lime line reads against the same canvas it
        // ships on (§8.1 surface0); keeps the baseline free of any card chrome.
        backgroundColor: AppColors.surface0,
        body: Center(
          child: SizedBox(
            width: _captureSize.width,
            height: _captureSize.height,
            child: Sparkline(
              values: values,
              semanticLabel: 'trend',
              // Pinned so the baseline does not depend on the default; this is
              // the §8.3 lime accent the production chart uses at rest.
              lineColor: AppColors.primary,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await expectLater(
    find.byType(Sparkline),
    matchesGoldenFile(goldenPath),
  );
}

void main() {
  group('Sparkline goldens', () {
    testWidgets('multi-point line ends on a present sample (line + latest dot)',
        (WidgetTester tester) async {
      await _pumpAndCapture(
        tester,
        // Oldest → newest; the window ends on a present value, so the latest
        // dot renders at the right edge.
        const <double?>[-72, -65, -68, -58, -54, -60, -52],
        'goldens/sparkline_multipoint.png',
      );
    });

    testWidgets('window with a null gap breaks the line and undots the head',
        (WidgetTester tester) async {
      await _pumpAndCapture(
        tester,
        // Interior gap (null at index 2) breaks the polyline; the trailing null
        // means the most recent sample is absent, so the head stays undotted.
        const <double?>[-70, -64, null, -58, -55, null],
        'goldens/sparkline_null_gap.png',
      );
    });
  });
}
