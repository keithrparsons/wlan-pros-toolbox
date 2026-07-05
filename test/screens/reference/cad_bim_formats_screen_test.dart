// Tests for the CAD & BIM Formats reference screen, a Field & Trade Reference
// set entry (2026-07-05). Text-reference only (no decoder plate). Three layers,
// mirroring the Site Access reference tests:
//   1. Data fidelity (GL-005): the typed const dataset carries Penn's approved,
//      voice-gated facts verbatim (the seven-format decode table, the six LOD
//      rungs, the three import steps), plus the no-em-dash and "Wi-Fi" glyph
//      guards across all rendered prose, with a data-fidelity count guard.
//   2. Registration: a live Quick Reference tile in the "AEC & Documentation"
//      subgroup, a registered route builder, and a keyword set.
//   3. Widget render: the read-only screen renders its title and key content in
//      BOTH dark and light themes with no RenderFlex overflow at 320/375/768/
//      1280 widths; no decoder plate is present.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/cad_bim_formats_data.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/cad_bim_formats_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('data fidelity (GL-005) — Penn\'s approved copy verbatim', () {
    test('format decode table: exactly 7 formats in order', () {
      expect(kCadFormats.length, 7);
      expect(
        kCadFormats.map((CadFormatRow r) => r.format).toList(),
        <String>['DWG', 'DXF', 'DGN', 'IFC', 'RVT', 'NWD / NWC', 'COBie'],
      );
    });

    test('anchor formats carry the load-bearing facts', () {
      CadFormatRow byFmt(String f) =>
          kCadFormats.firstWhere((CadFormatRow r) => r.format == f);
      expect(byFmt('DWG').whatItIs.contains('native CAD format'), isTrue);
      expect(byFmt('IFC').whatItIs.contains('buildingSMART'), isTrue);
      expect(byFmt('RVT').whatItIs.contains('Revit'), isTrue);
    });

    test('LOD ladder: exactly 6 rungs, 300 and 350 anchored', () {
      expect(kLodLevels.length, 6);
      expect(
        kLodLevels.map((LodLevel l) => l.level).toList(),
        <String>[
          'LOD 100',
          'LOD 200',
          'LOD 300',
          'LOD 350',
          'LOD 400',
          'LOD 500',
        ],
      );
      final LodLevel l300 =
          kLodLevels.firstWhere((LodLevel l) => l.level == 'LOD 300');
      final LodLevel l350 =
          kLodLevels.firstWhere((LodLevel l) => l.level == 'LOD 350');
      expect(l300.meaning.contains('dimensioned geometry'), isTrue);
      expect(l350.meaning.contains('connections to other elements'), isTrue);
    });

    test('import steps: exactly 3, scale calibration is step 2', () {
      expect(kCadImportSteps.length, 3);
      expect(kCadImportSteps[1].contains('Calibrate the scale'), isTrue);
      expect(kCadImportSteps[1].contains('matters most'), isTrue);
    });

    test('no em dash in any rendered prose; "Wi-Fi" casing where used', () {
      final List<String> prose = <String>[
        kCadBimLead,
        kLodWhyMatters,
        kCadImportIntro,
        kCadImportPrep,
        kCadBoundary,
        kCadBimWlanCares,
        kCadBimDeferNote,
        ...kCadImportSteps,
        for (final CadFormatRow r in kCadFormats) ...<String>[
          r.format,
          r.whatItIs,
          r.authoredBy,
        ],
        for (final LodLevel l in kLodLevels) ...<String>[l.level, l.meaning],
      ];
      for (final String s in prose) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        expect(s.contains('WiFi'), isFalse, reason: 'must be "Wi-Fi" in "$s"');
      }
    });
  });

  group('registration (catalog + subgroup + router + keywords)', () {
    test('live Quick Reference tile in the "AEC & Documentation" subgroup', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final ToolEntry t = qr.tools.firstWhere(
        (ToolEntry e) => e.id == 'cad-bim-formats',
      );
      expect(t.isLive, isTrue);
      expect(t.routeName, '/tools/cad-bim-formats');
      expect(t.title, 'CAD & BIM Formats');
      expect(t.subgroup, 'AEC & Documentation');
    });

    test('grouping places the tool under "AEC & Documentation", not "Other"', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final List<ToolSection> sections = groupedCategoryTools(qr);
      for (final ToolSection s in sections.where(
        (ToolSection s) => s.header == 'Other',
      )) {
        expect(
          s.tools.any((ToolEntry e) => e.id == 'cad-bim-formats'),
          isFalse,
          reason: 'cad-bim-formats orphaned into Other',
        );
      }
      final ToolSection codes =
          sections.firstWhere((ToolSection s) => s.header == 'AEC & Documentation');
      expect(
        codes.tools.any((ToolEntry e) => e.id == 'cad-bim-formats'),
        isTrue,
      );
    });

    test('route resolves to a registered builder', () {
      expect(AppRouter.routes.containsKey('/tools/cad-bim-formats'), isTrue);
    });

    test('carries a non-empty keyword set', () {
      expect(kToolKeywords.containsKey('cad-bim-formats'), isTrue);
      expect(kToolKeywords['cad-bim-formats']!, isNotEmpty);
      expect(kToolKeywords['cad-bim-formats']!.contains('ifc'), isTrue);
    });
  });

  group('widget render (dark + light, no overflow)', () {
    testWidgets('renders title + key content in dark + light, no plate',
        (tester) async {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.dark(),
        AppTheme.light(),
      ]) {
        await _withViewport(tester, const Size(375, 5200), () async {
          await tester.pumpWidget(
            MaterialApp(theme: theme, home: const CadBimFormatsScreen()),
          );
          await tester.pump();
          expect(find.text('CAD & BIM Formats'), findsWidgets);
          expect(find.text('The format decode table'), findsOneWidget);
          expect(find.text('Why a WLAN pro cares'), findsOneWidget);
          expect(find.byType(TextField), findsNothing);
        });
      }
    });

    testWidgets('no overflow at 320/375/768/1280 widths', (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 5200), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const CadBimFormatsScreen(),
            ),
          );
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'overflow at ${width}px',
          );
        });
      }
    });
  });
}

Future<void> _withViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await body();
}
