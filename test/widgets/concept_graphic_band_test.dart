// Widget tests for ConceptGraphicBand — the §8.6.2 per-tool concept-graphic
// header band and its convention-based, gracefully-degrading asset lookup.
//
// Covers the contract the build brief locked in:
//   - present: when the tool's graphic IS bundled, the band renders an
//     SvgPicture inside a card-styled container at the band height;
//   - absent (graceful fallback): when the graphic is NOT bundled, the band
//     collapses to SizedBox.shrink() — no SvgPicture, no broken-image box,
//     layout unchanged;
//   - decorative for screen readers: the band is wrapped in ExcludeSemantics
//     (§8.6.2 a11y rule 2);
//   - mobile vs desktop band height (140 / 160dp, §8.6.2 token).
//
// Uses ToolAssets.debugSetBundledAssets to simulate the build-time manifest so
// the test never depends on a real asset bundle.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_assets.dart';
import 'package:wlan_pros_toolbox/screens/tools/concept_graphic_band.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<void> _pump(
  WidgetTester tester, {
  required String toolId,
  bool isDesktop = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: ConceptGraphicBand(toolId: toolId, isDesktop: isDesktop),
      ),
    ),
  );
}

void main() {
  tearDown(ToolAssets.debugReset);

  group('ConceptGraphicBand', () {
    testWidgets('renders an SvgPicture when the graphic is bundled',
        (tester) async {
      ToolAssets.debugSetBundledAssets({'assets/tool-graphics/fspl.svg'});
      await _pump(tester, toolId: 'fspl');

      expect(find.byType(SvgPicture), findsOneWidget);
      // It sits in a card-styled container (its own Container with decoration).
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('collapses to nothing when the graphic is NOT bundled',
        (tester) async {
      ToolAssets.debugSetBundledAssets(<String>{}); // nothing built
      await _pump(tester, toolId: 'fspl');

      expect(find.byType(SvgPicture), findsNothing);
      expect(find.byType(SizedBox), findsOneWidget); // the shrink sentinel
    });

    testWidgets('a different tool with no asset also degrades cleanly',
        (tester) async {
      // Only fspl is bundled; link-budget is not → link-budget collapses.
      ToolAssets.debugSetBundledAssets({'assets/tool-graphics/fspl.svg'});
      await _pump(tester, toolId: 'link-budget');

      expect(find.byType(SvgPicture), findsNothing);
    });

    testWidgets('is marked decorative for screen readers', (tester) async {
      ToolAssets.debugSetBundledAssets({'assets/tool-graphics/fresnel.svg'});
      await _pump(tester, toolId: 'fresnel');

      // The band wraps in ExcludeSemantics; SvgPicture(excludeFromSemantics)
      // adds a second one — both intended (§8.6.2 a11y rule 2, belt + braces).
      expect(find.byType(ExcludeSemantics), findsWidgets);
    });

    testWidgets('uses the 140dp mobile / 160dp desktop band height',
        (tester) async {
      ToolAssets.debugSetBundledAssets({'assets/tool-graphics/eirp.svg'});

      // Assert the band's OWN full-width sizing box (width: double.infinity),
      // not the intrinsic box flutter_svg adds for the now-bundled eirp.svg.
      await _pump(tester, toolId: 'eirp', isDesktop: false);
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is SizedBox && w.height == 140 && w.width == double.infinity,
        ),
        findsOneWidget,
      );

      await _pump(tester, toolId: 'eirp', isDesktop: true);
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is SizedBox && w.height == 160 && w.width == double.infinity,
        ),
        findsOneWidget,
      );
    });
  });

  group('ConceptGraphicBand light-mode swap (§8.20.7)', () {
    test('recolors scaffold / muted / lime-foreground / status hues', () {
      const String svg =
          '<svg><path stroke="#E5E5E5"/><line stroke="#9C9C9C"/>'
          '<path stroke="#A2CC3A"/><rect stroke="#3A3A3A"/>'
          '<path stroke="#F26E6E"/><path stroke="#E0A23A"/>'
          '<path stroke="#5BD68A"/>'
          '<circle fill="rgba(162,204,58,0.08)"/></svg>';
      final String out = ConceptGraphicBand.debugApplyLightSwap(svg);

      // Dark scaffold/lime/status hexes are gone…
      expect(out.contains('#E5E5E5'), isFalse);
      expect(out.contains('#9C9C9C'), isFalse);
      expect(out.contains('#A2CC3A'), isFalse);
      expect(out.contains('#3A3A3A'), isFalse);
      expect(out.contains('#F26E6E'), isFalse);
      expect(out.contains('#E0A23A'), isFalse);
      expect(out.contains('#5BD68A'), isFalse);
      expect(out.contains('rgba(162,204,58,0.08)'), isFalse);

      // …replaced by the §8.20.1 / §8.20.2 light values.
      expect(out.contains('#4A4A4A'), isTrue); // textSecondary
      expect(out.contains('#646464'), isTrue); // textTertiary
      expect(out.contains('#5A7A1C'), isTrue); // textAccent (lime split)
      expect(out.contains('#E2E1E2'), isTrue); // border (faint hatch)
      expect(out.contains('#C62D2D'), isTrue); // statusDanger
      expect(out.contains('#8A5A00'), isTrue); // statusWarning (bronze)
      expect(out.contains('#1E7E45'), isTrue); // statusSuccess
      expect(out.contains('rgba(90,122,28,0.10)'), isTrue); // lime wash
    });

    test('PRESERVES §1d canonical T568 / copper data colors and #1A1A1A', () {
      const String svg =
          '<svg><rect fill="#C9A227"/><rect fill="#F58A1F"/>'
          '<rect fill="#3CA03C"/><rect fill="#2D6CDF"/>'
          '<rect fill="#7A4A22"/><circle fill="#1A1A1A"/></svg>';
      final String out = ConceptGraphicBand.debugApplyLightSwap(svg);

      // The color IS the information (T568 pinout, copper) — must survive intact.
      expect(out.contains('#C9A227'), isTrue); // copper/gold
      expect(out.contains('#F58A1F'), isTrue); // T568 orange
      expect(out.contains('#3CA03C'), isTrue); // T568 green
      expect(out.contains('#2D6CDF'), isTrue); // T568 blue
      expect(out.contains('#7A4A22'), isTrue); // T568 brown
      expect(out.contains('#1A1A1A'), isTrue); // anchor dot (no-op)
      // Nothing else changed: input == output for a canonical-only graphic.
      expect(out, equals(svg));
    });

    testWidgets('light theme renders the recolored graphic (no broken box)',
        (tester) async {
      // fspl IS a real bundled asset, so rootBundle.loadString resolves it.
      ToolAssets.debugSetBundledAssets({'assets/tool-graphics/fspl.svg'});
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: ConceptGraphicBand(toolId: 'fspl'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The light path draws via SvgPicture.string once the future resolves.
      expect(find.byType(SvgPicture), findsOneWidget);
    });
  });

  group('ToolAssets convention paths', () {
    test('icon and graphic paths derive from the tool id verbatim', () {
      expect(ToolAssets.iconPath('dbm-watt-converter'),
          'assets/tool-icons/dbm-watt-converter.svg');
      expect(ToolAssets.graphicPath('dbm-watt-converter'),
          'assets/tool-graphics/dbm-watt-converter.svg');
    });

    test('has* is false until the manifest is loaded (safe default)', () {
      ToolAssets.debugReset();
      expect(ToolAssets.hasGraphic('fspl'), isFalse);
      expect(ToolAssets.hasIcon('link-budget'), isFalse);
    });

    test('has* reflects the bundled set once loaded', () {
      ToolAssets.debugSetBundledAssets({
        'assets/tool-graphics/fspl.svg',
        'assets/tool-icons/link-budget.svg',
      });
      expect(ToolAssets.hasGraphic('fspl'), isTrue);
      expect(ToolAssets.hasGraphic('link-budget'), isFalse);
      expect(ToolAssets.hasIcon('link-budget'), isTrue);
      expect(ToolAssets.hasIcon('fspl'), isFalse);
    });
  });
}
