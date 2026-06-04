// HelpBrowseScreen tests.
//
// Coverage:
// - buildHelpGroups() groups the loaded help by catalog category, in catalog
//   order, skipping tools with no entry and empty categories.
// - The screen renders the category headings and a row per help-bearing tool.
// - Tapping a row opens the shared ToolHelpSheet (the tool's name appears).
// - Route integrity: AppRouter registers /help -> HelpBrowseScreen.
// - Honest empty state: with no store loaded, the screen shows the "could not be
//   loaded" message rather than a blank list.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/help_browse_screen.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help_loader.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

// A small store keyed by REAL catalog tool ids so grouping resolves against the
// live catalog. fspl + wavelength are Calculators & Tools; wifi-channels is
// Quick Reference. test-my-connection is Test Network. unknown-id is not in the
// catalog and must be ignored by the grouping.
const String _fixture = '''
{
  "tools": {
    "fspl": { "name": "Free Space Path Loss", "category": "Calculators & Tools", "purpose": "Path loss.", "whyHere": "Link budget.", "howToUse": [], "inputs": [], "algorithm": null, "example": null, "fieldNotes": [], "source": "x" },
    "wavelength": { "name": "Wavelength", "category": "Calculators & Tools", "purpose": "Wavelength from frequency.", "whyHere": "Antenna sizing.", "howToUse": [], "inputs": [], "algorithm": null, "example": null, "fieldNotes": [], "source": "x" },
    "wifi-channels": { "name": "Wi-Fi Channels", "category": "Quick Reference", "purpose": "Channels by band.", "whyHere": "Lookup.", "howToUse": [], "inputs": [], "algorithm": null, "example": null, "fieldNotes": [], "source": "x" },
    "unknown-id-not-in-catalog": { "name": "Ghost", "category": "Nowhere", "purpose": "n/a", "whyHere": "n/a", "howToUse": [], "inputs": [], "algorithm": null, "example": null, "fieldNotes": [], "source": "x" }
  }
}
''';

Future<void> _pumpBrowse(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: const HelpBrowseScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => ToolHelpLoader.debugSetStore(ToolHelpStore.fromJson(_fixture)));
  tearDown(() => ToolHelpLoader.debugSetStore(null));

  group('buildHelpGroups', () {
    test('groups by catalog category in catalog order, dropping unknowns', () {
      final List<HelpGroup> groups = buildHelpGroups();
      // Only categories with at least one help-bearing tool appear.
      final List<String> titles = groups.map((HelpGroup g) => g.title).toList();
      expect(titles, contains('Calculators & Tools'));
      expect(titles, contains('Quick Reference'));

      // Calculators & Tools comes before Quick Reference (catalog/home order).
      expect(
        titles.indexOf('Calculators & Tools'),
        lessThan(titles.indexOf('Quick Reference')),
      );

      // The unknown id is grouped under no catalog category, so it never shows.
      final bool hasGhost = groups.any(
        (HelpGroup g) => g.entries.any((HelpRow r) => r.title == 'Ghost'),
      );
      expect(hasGhost, isFalse);

      // Calculators & Tools holds both fspl and wavelength.
      final HelpGroup calc =
          groups.firstWhere((HelpGroup g) => g.title == 'Calculators & Tools');
      expect(calc.entries.length, 2);
    });
  });

  group('HelpBrowseScreen widget', () {
    testWidgets('renders category headings and a row per tool', (tester) async {
      await _pumpBrowse(tester);

      expect(find.text('Help & Documentation'), findsOneWidget);
      expect(find.text('Calculators & Tools'), findsOneWidget);
      expect(find.text('Quick Reference'), findsOneWidget);

      // Catalog titles appear as rows.
      expect(find.text('Free Space Path Loss'), findsOneWidget);
      expect(find.text('Wavelength'), findsOneWidget);
      expect(find.text('Wi-Fi Channels'), findsOneWidget);
    });

    testWidgets('tapping a row opens the help sheet', (tester) async {
      await _pumpBrowse(tester);

      await tester.tap(find.text('Free Space Path Loss'));
      await tester.pumpAndSettle();

      // The sheet's Close affordance and a section heading confirm it opened.
      // Close moved to the top-right of the title row as a labelled icon button.
      expect(find.bySemanticsLabel('Close help'), findsOneWidget);
      expect(find.text('Purpose'), findsOneWidget);
    });

    testWidgets('honest empty state when no store is loaded', (tester) async {
      ToolHelpLoader.debugSetStore(null);
      await _pumpBrowse(tester);
      expect(find.text('Tool help could not be loaded'), findsOneWidget);
    });
  });

  group('route integrity', () {
    test('AppRouter registers /help to HelpBrowseScreen', () {
      expect(AppRouter.routes.containsKey(AppRouter.helpBrowse), isTrue);
      expect(AppRouter.helpBrowse, '/help');
    });
  });
}
