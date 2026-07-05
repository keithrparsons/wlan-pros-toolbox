// Tests for the Plan-Set Literacy reference screen, a Field & Trade Reference
// set entry (2026-07-05). Three layers, mirroring the Enclosure Ratings tests:
//   1. Data fidelity (GL-005): the typed const datasets carry Penn's approved,
//      voice-gated facts verbatim (the discipline designators incl. A/E/T, the
//      sheet-type digits, the three RCP reasons, the six plan-set elements),
//      plus the no-em-dash and "Wi-Fi" glyph guards, with a count guard.
//   2. Registration: a live Quick Reference tile in the "AEC & Documentation"
//      subgroup (placement flagged for Keith; AEC & Documentation is a
//      Calculators subgroup, not a reference subgroup), a registered route
//      builder, a keyword set, and a help entry.
//   3. Widget render: the read-only screen renders its title and key content in
//      BOTH dark and light themes with no RenderFlex overflow; the embedded-PNG
//      plate is omitted when the asset is not bundled and shown once when it is.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/plan_set_literacy_data.dart';
import 'package:wlan_pros_toolbox/data/reference_images.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/plan_set_literacy_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/dark_raster_diagram_card.dart';

void main() {
  group('data fidelity (GL-005) — Penn\'s approved copy verbatim', () {
    test('discipline designators: 11 primary letters incl. A/E/T', () {
      expect(kDisciplineDesignators.length, 11);
      DisciplineDesignator byLetter(String l) =>
          kDisciplineDesignators.firstWhere((DisciplineDesignator d) =>
              d.letter == l);
      expect(byLetter('A').discipline, 'Architectural');
      expect(byLetter('E').discipline, 'Electrical');
      expect(byLetter('T').discipline, 'Telecommunications');
    });

    test('sheet-type digits: 9 rows, 1 = Plans, 6 = Schedules and Diagrams', () {
      expect(kSheetTypeDigits.length, 9);
      expect(
        kSheetTypeDigits.firstWhere((SheetTypeDigit s) => s.digit == '1').meaning,
        'Plans',
      );
      expect(
        kSheetTypeDigits.firstWhere((SheetTypeDigit s) => s.digit == '6').meaning,
        'Schedules and Diagrams',
      );
    });

    test('the RCP is the AP sheet: 3 reasons, mounting-height first', () {
      expect(kRcpReasons.length, 3);
      expect(kRcpReasons.first.contains('mounting-height reality'), isTrue);
      expect(kRcpIntro.contains('mirror on the floor reflects the ceiling'),
          isTrue);
    });

    test('the rest of a plan set: exactly 6 elements incl. title block', () {
      expect(kPlanSetElements.length, 6);
      expect(kPlanSetElements.first.startsWith('Title block:'), isTrue);
    });

    test('no em dash in any rendered prose; "Wi-Fi" casing where used', () {
      final List<String> prose = <String>[
        kPlanSetLead,
        kSheetNumberIntro,
        kSheetNumberExample,
        kDisciplineNote,
        kTelecomDisciplineNote,
        kSheetTypeNote,
        kRcpIntro,
        kRcpWhyIntro,
        kRcpAntiPattern,
        kScalesNote,
        kPlanSetWlanCares,
        kPlanSetDeferNote,
        ...kRcpReasons,
        ...kPlanSetElements,
        for (final DisciplineDesignator d in kDisciplineDesignators)
          d.discipline,
        for (final SheetTypeDigit s in kSheetTypeDigits) s.meaning,
      ];
      for (final String s in prose) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        expect(s.contains('WiFi'), isFalse, reason: 'must be "Wi-Fi" in "$s"');
      }
    });
  });

  group('registration (catalog + subgroup + router + keywords)', () {
    test('live Quick Reference tile, defaulted to "AEC & Documentation"', () {
      // Placement flagged for Keith: an "AEC & Documentation" subgroup exists
      // only under Calculators & Tools (for the Architectural Scale calc), not
      // as a reference subgroup, so this reference screen defaults here.
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final ToolEntry t = qr.tools.firstWhere(
        (ToolEntry e) => e.id == 'plan-set-literacy',
      );
      expect(t.isLive, isTrue);
      expect(t.routeName, '/tools/plan-set-literacy');
      expect(t.title, 'Plan-Set Literacy');
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
          s.tools.any((ToolEntry e) => e.id == 'plan-set-literacy'),
          isFalse,
          reason: 'plan-set-literacy orphaned into Other',
        );
      }
      final ToolSection codes =
          sections.firstWhere((ToolSection s) => s.header == 'AEC & Documentation');
      expect(
        codes.tools.any((ToolEntry e) => e.id == 'plan-set-literacy'),
        isTrue,
      );
    });

    test('route resolves to a registered builder', () {
      expect(AppRouter.routes.containsKey('/tools/plan-set-literacy'), isTrue);
    });

    test('carries a non-empty keyword set', () {
      expect(kToolKeywords.containsKey('plan-set-literacy'), isTrue);
      expect(kToolKeywords['plan-set-literacy']!, isNotEmpty);
      expect(kToolKeywords['plan-set-literacy']!.contains('rcp'), isTrue);
    });
  });

  group('widget render (dark + light, no overflow)', () {
    setUp(() {
      ReferenceImages.debugSetBundled(const <String>{});
    });
    tearDown(ReferenceImages.debugReset);

    testWidgets('renders title + key content in dark + light, plate omitted',
        (tester) async {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.dark(),
        AppTheme.light(),
      ]) {
        await _withViewport(tester, const Size(375, 4600), () async {
          await tester.pumpWidget(
            MaterialApp(theme: theme, home: const PlanSetLiteracyScreen()),
          );
          await tester.pump();
          expect(find.text('Plan-Set Literacy'), findsWidgets);
          expect(find.text('Reading a sheet number'), findsOneWidget);
          expect(
            find.text('The Reflected Ceiling Plan is the AP sheet'),
            findsOneWidget,
          );
          expect(find.text('Scales'), findsOneWidget);
          expect(find.byType(TextField), findsNothing);
          expect(find.byType(DarkRasterDiagramCard), findsNothing);
        });
      }
    });

    testWidgets('shows exactly one plate card when the PNG is bundled',
        (tester) async {
      ReferenceImages.debugSetBundled(<String>{
        ReferenceImages.pathFor('plan-set-literacy'),
      });
      addTearDown(ReferenceImages.debugReset);
      await _withViewport(tester, const Size(375, 4600), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const PlanSetLiteracyScreen(),
          ),
        );
        await tester.pump();
        expect(find.byType(DarkRasterDiagramCard), findsOneWidget);
      });
    });

    testWidgets('no overflow at 320/375/768/1280 widths', (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 4200), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const PlanSetLiteracyScreen(),
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
