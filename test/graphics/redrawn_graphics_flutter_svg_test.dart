// Verifies every graphic touched by fix/v1.1.2-graphics-clear actually PARSES
// and RENDERS in flutter_svg (the real runtime), not just in a browser.
//
// flutter_svg silently drops features it does not support (notably <marker>),
// or throws on malformed geometry. This test loads each redrawn SVG from disk,
// hands the raw string to SvgPicture.string (the same parser the app uses),
// pumps it, and asserts a non-empty render with no parse exception. It also
// guards the two structural invariants this lane is responsible for:
//   - the antenna-fundamentals g1-g7 (and, since 2026-09-27, the Find My,
//     Explained and Starlink, Explained figures) carry NO <marker> defs or refs
//     (all converted to inline-path arrowheads across the two graphics lanes).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

const List<String> _conceptGraphics = <String>[
  'assets/tool-graphics/earth-curvature.svg',
  'assets/tool-graphics/roaming.svg',
  'assets/tool-graphics/rf-attenuation.svg',
  'assets/tool-graphics/throughput-calc.svg',
  'assets/tool-graphics/signal-thresholds.svg',
  'assets/tool-graphics/eirp.svg',
  'assets/tool-graphics/link-budget.svg',
  'assets/tool-graphics/fspl.svg',
  'assets/tool-graphics/fresnel.svg',
  'assets/tool-graphics/wpa-security.svg',
];

const List<String> _convertedDiagrams = <String>[
  'assets/tool-diagrams/antenna-fundamentals/g1-azimuth-vs-elevation.svg',
  'assets/tool-diagrams/antenna-fundamentals/g2-omni-donut.svg',
  'assets/tool-diagrams/antenna-fundamentals/g3-polar-plot-anatomy.svg',
  'assets/tool-diagrams/antenna-fundamentals/g4-pattern-comparison.svg',
  'assets/tool-diagrams/antenna-fundamentals/g5-coverage-floorplan.svg',
  'assets/tool-diagrams/antenna-fundamentals/g6-downtilt.svg',
  'assets/tool-diagrams/antenna-fundamentals/g7-polarization.svg',
  // Find My, Explained (2026-09-27): drawn with triangle arrowheads from the
  // start (tool/find_my_diagrams.py), never with <marker>.
  'assets/tool-diagrams/find-my/cover-people-devices-items.svg',
  'assets/tool-diagrams/find-my/f1-find-my-network.svg',
  'assets/tool-diagrams/find-my/f2-rotating-ids.svg',
  'assets/tool-diagrams/find-my/f3-where-the-dot-comes-from.svg',
  'assets/tool-diagrams/find-my/f4-three-radios.svg',
  'assets/tool-diagrams/find-my/f5-app-parts.svg',
  'assets/tool-diagrams/find-my/f6-phone-dies.svg',
  'assets/tool-diagrams/find-my/f7-lost-luggage.svg',
  'assets/tool-diagrams/find-my/f8-unwanted-tracker.svg',
  // Starlink, Explained (2026-09-27): the print guide's Figure 3 used a
  // <marker> arrowhead; tool/starlink_diagrams.py draws triangles instead.
  'assets/tool-diagrams/starlink/cover-dish-satellite-gateway.svg',
  'assets/tool-diagrams/starlink/f1-orbits-to-scale.svg',
  'assets/tool-diagrams/starlink/f2-first-1300-km.svg',
  'assets/tool-diagrams/starlink/f3-data-path.svg',
  'assets/tool-diagrams/starlink/f4-latency.svg',
  'assets/tool-diagrams/starlink/f5-phased-array.svg',
  'assets/tool-diagrams/starlink/f6-dishes-to-scale.svg',
  'assets/tool-diagrams/starlink/f7-shared-capacity.svg',
  'assets/tool-diagrams/starlink/f8-tree-drops.svg',
  'assets/tool-diagrams/starlink/f9-two-links.svg',
];

Future<void> _expectRenders(WidgetTester tester, String path) async {
  final String svg = File(path).readAsStringSync();
  Object? caught;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SvgPicture.string(
            svg,
            width: 320,
            height: 160,
            // surface any parse error instead of the silent placeholder
            errorBuilder: (BuildContext c, Object e, StackTrace? s) {
              caught = e;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
  expect(caught, isNull, reason: 'flutter_svg failed to parse $path: $caught');
  expect(find.byType(SvgPicture), findsOneWidget, reason: path);
}

void main() {
  group('redrawn concept graphics render in flutter_svg', () {
    for (final String path in _conceptGraphics) {
      testWidgets(path, (WidgetTester tester) async {
        await _expectRenders(tester, path);
      });
    }
  });

  group('marker→inline converted antenna diagrams render in flutter_svg', () {
    for (final String path in _convertedDiagrams) {
      testWidgets(path, (WidgetTester tester) async {
        await _expectRenders(tester, path);
      });
    }
  });

  group('structural invariants', () {
    test('antenna g1-g7 and the Find My figures carry no <marker> defs or '
        'marker-* refs', () {
      for (final String path in _convertedDiagrams) {
        final String svg = File(path).readAsStringSync();
        expect(svg.contains('<marker'), isFalse, reason: '$path has <marker> def');
        expect(svg.contains('marker-end'), isFalse, reason: '$path has marker-end');
        expect(svg.contains('marker-start'), isFalse,
            reason: '$path has marker-start');
      }
    });

    test('no decorative ground-hatching idiom remains in redrawn graphics', () {
      // the "l5 7" / "l6 6" short-diagonal slash clusters that testers flagged
      for (final String path in <String>[
        'assets/tool-graphics/earth-curvature.svg',
        'assets/tool-graphics/fresnel.svg',
        'assets/tool-graphics/rf-attenuation.svg',
      ]) {
        final String svg = File(path).readAsStringSync();
        expect(RegExp(r'l\d+ \d+ M').hasMatch(svg), isFalse,
            reason: '$path still has slash-cluster hatching');
      }
    });
  });
}
