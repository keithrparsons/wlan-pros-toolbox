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

      await _pump(tester, toolId: 'eirp', isDesktop: false);
      expect(
        find.byWidgetPredicate(
          (Widget w) => w is SizedBox && w.height == 140,
        ),
        findsOneWidget,
      );

      await _pump(tester, toolId: 'eirp', isDesktop: true);
      expect(
        find.byWidgetPredicate(
          (Widget w) => w is SizedBox && w.height == 160,
        ),
        findsOneWidget,
      );
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
