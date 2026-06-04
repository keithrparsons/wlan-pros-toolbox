// Widget tests for the two bespoke Tier-2 icons added on feat/glossary-edu-icons:
//   * the Wi-Fi Glossary TOOL icon (assets/tool-icons/wifi-glossary.svg),
//     resolved by the <id>.svg convention in ToolAssets and rendered by ToolRow;
//   * the Educational Resources CATEGORY icon
//     (assets/tool-icons/educational-resources.svg), wired via the new
//     ToolCategory.iconAsset field and rendered on the home-grid tile.
//
// Both assert the SVG path is taken (an SvgPicture renders) rather than the
// fallback (the ToolRow lime-bolt Icon / the category Material Icon). Asset
// presence is simulated with ToolAssets.debugSetBundledAssets so the tests do
// not depend on a real bundle, matching concept_graphic_band_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_assets.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/screens/home_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/tool_row.dart';

ToolEntry _glossaryEntry() => kToolCategories
    .expand((ToolCategory c) => c.tools)
    .firstWhere((ToolEntry t) => t.id == 'wifi-glossary');

ToolCategory _eduCategory() =>
    kToolCategories.firstWhere((ToolCategory c) => c.id == 'educational-resources');

void main() {
  tearDown(ToolAssets.debugReset);

  group('Wi-Fi Glossary tool icon', () {
    testWidgets(
      'ToolRow renders the bespoke SVG (not the bolt fallback) when bundled',
      (tester) async {
        ToolAssets.debugSetBundledAssets(
          <String>{'assets/tool-icons/wifi-glossary.svg'},
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(body: ToolRow(tool: _glossaryEntry())),
          ),
        );

        // The leading tile renders the convention-resolved SVG...
        expect(find.byType(SvgPicture), findsOneWidget);
        // ...and NOT the lime-bolt fallback the row shows when no icon is built.
        expect(find.byIcon(Icons.bolt), findsNothing);
      },
    );

    test('the convention path resolves to the bundled tool-icons asset', () {
      expect(
        ToolAssets.iconPath('wifi-glossary'),
        'assets/tool-icons/wifi-glossary.svg',
      );
    });
  });

  group('Educational Resources category icon', () {
    test('the category carries the bespoke iconAsset path', () {
      expect(
        _eduCategory().iconAsset,
        'assets/tool-icons/educational-resources.svg',
      );
      // The Material glyph is kept as the fallback.
      expect(_eduCategory().icon, Icons.school_outlined);
    });

    testWidgets('the home tile renders an SvgPicture for the edu category', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark(), home: const HomeScreen()),
      );
      await tester.pumpAndSettle();

      // The edu tile is the only category with iconAsset set, so exactly one
      // category-glyph SvgPicture appears on the grid.
      final int categoriesWithSvg =
          kToolCategories.where((ToolCategory c) => c.iconAsset != null).length;
      expect(categoriesWithSvg, 1);
      expect(find.byType(SvgPicture), findsNWidgets(categoriesWithSvg));
    });
  });
}
