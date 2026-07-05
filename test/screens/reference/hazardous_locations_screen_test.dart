// Tests for the Hazardous (Classified) Locations reference screen — Field
// Reference #3 of the Field & Trade Reference set (2026-07-05).
//
// Three layers, mirroring the enclosure-ratings pilot test:
//   1. Data fidelity (GL-005): the typed const datasets carry Penn's approved,
//      voice-gated facts verbatim (Class / Division / Zone ladders, the
//      Division-to-Zone mapping, the protection concepts, the load-bearing
//      ignition-source warning, the AHJ / licensed-electrician defer line), plus
//      the no-em-dash and "Wi-Fi" glyph rules across all rendered prose.
//   2. Registration: the tool has a live Quick Reference tile in the "Codes &
//      Safety" subgroup, a registered route builder, and a keyword set. The help
//      count guard is asserted in tool_help_loader_test.
//   3. Widget render: the read-only screen renders its title and key content
//      across phone/tablet/desktop widths, in BOTH dark and light themes, with
//      no RenderFlex overflow; the embedded-PNG plate is omitted when the asset
//      is not bundled (graceful degradation) and shown once when it is.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/hazardous_locations_data.dart';
import 'package:wlan_pros_toolbox/data/reference_images.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/hazardous_locations_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/dark_raster_diagram_card.dart';

void main() {
  group('data fidelity (GL-005) — Penn\'s approved copy verbatim', () {
    test('Class ladder: 3 rungs, Class I = flammable gases or vapors', () {
      expect(kHazClasses.length, 3);
      expect(kHazClasses.first.cls, 'Class I');
      expect(kHazClasses.first.hazard, 'Flammable gases or vapors');
      final HazClass two =
          kHazClasses.firstWhere((HazClass c) => c.cls == 'Class II');
      expect(two.hazard, 'Combustible dust');
    });

    test('Division 1 is present during NORMAL operation (the explosive case)',
        () {
      expect(kHazDivisions.length, 2);
      expect(kHazDivisions[0].contains('present during normal operation'),
          isTrue);
      expect(kHazDivisions[1].contains('only under fault conditions'), isTrue);
      // Div 2 is the larger market for rated wireless.
      expect(kHazDivisionNote.contains('far larger'), isTrue);
    });

    test('Zone ladder maps to Division (one-way mapping pros need)', () {
      expect(kHazZones.length, 4);
      final HazZone zero =
          kHazZones.firstWhere((HazZone z) => z.zones == 'Zone 0');
      expect(zero.meaning, 'Present continuously or for long periods');
      expect(kHazZones.last.zones, 'Zone 20 / 21 / 22');
      expect(
        kHazZoneMapping.any((String m) => m.contains('Division 1 is roughly')),
        isTrue,
      );
    });

    test('protection concepts: Ex i is the only concept accepted in Zone 0', () {
      final HazConcept exI = kHazConcepts.firstWhere(
        (HazConcept c) => c.concept.contains('Intrinsically safe'),
      );
      expect(exI.how.contains('only concept accepted in Zone 0'), isTrue);
    });

    test('protection concepts: Ex e and Ex nR are split into their own rows', () {
      // Ex e (increased safety) is a Zone 1 concept, distinct from Ex nR.
      final HazConcept exE = kHazConcepts.firstWhere(
        (HazConcept c) => c.concept == 'Increased safety (Ex e)',
      );
      expect(exE.where, 'Zone 1');
      expect(exE.how.contains('prevents arcs and hot surfaces'), isTrue);
      // Ex nR (restricted breathing) is the common Div 2 / Zone 2 wireless case.
      final HazConcept exNr = kHazConcepts.firstWhere(
        (HazConcept c) => c.concept == 'Restricted breathing (Ex nR)',
      );
      expect(exNr.where.contains('common wireless case'), isTrue);
      expect(exNr.how.contains('sealed against gas ingress'), isTrue);
      // The split brings the concept table to five rows.
      expect(kHazConcepts.length, 5);
    });

    test('the load-bearing safety takeaway: a commercial AP is an ignition '
        'source', () {
      expect(kHazApWarning.contains('illegal, uninsurable'), isTrue);
      expect(kHazApWarning.contains('genuine ignition source'), isTrue);
      expect(kHazFieldRead.last, 'Never just mount a commercial AP there.');
    });

    test('defer footer names the AHJ and a licensed electrician', () {
      expect(kHazDeferNote.contains('AHJ'), isTrue);
      expect(kHazDeferNote.contains('licensed electrician'), isTrue);
    });

    test('no em dash in any rendered prose; "Wi-Fi" casing where used', () {
      final List<String> prose = <String>[
        kHazLead,
        kHazDivisionNote,
        kHazZoneIntro,
        kHazZoneMappingIntro,
        kHazZoneNote,
        kHazApBody,
        kHazApWarning,
        kHazProtectionIntro,
        kHazListingNote,
        kHazWlanCares,
        kHazDeferNote,
        ...kHazDivisions,
        ...kHazZoneMapping,
        ...kHazDiv2Buys,
        ...kHazFieldRead,
        for (final HazClass c in kHazClasses) ...<String>[
          c.cls,
          c.hazard,
          c.environments,
        ],
        for (final HazZone z in kHazZones) ...<String>[
          z.hazard,
          z.zones,
          z.meaning,
        ],
        for (final HazConcept c in kHazConcepts) ...<String>[
          c.concept,
          c.how,
          c.where,
        ],
      ];
      for (final String s in prose) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        expect(s.contains('WiFi'), isFalse, reason: 'must be "Wi-Fi" in "$s"');
      }
    });
  });

  group('registration (catalog + subgroup + router + keywords)', () {
    test('live Quick Reference tile in the "Codes & Safety" subgroup', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final ToolEntry t = qr.tools.firstWhere(
        (ToolEntry e) => e.id == 'hazardous-locations',
      );
      expect(t.isLive, isTrue);
      expect(t.routeName, '/tools/hazardous-locations');
      expect(t.title, 'Hazardous Locations');
      expect(t.subgroup, 'Codes & Safety');
    });

    test('no orphaned subgroup — grouping places the tool under its header', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final List<ToolSection> sections = groupedCategoryTools(qr);
      final ToolSection codes =
          sections.firstWhere((ToolSection s) => s.header == 'Codes & Safety');
      expect(
        codes.tools.any((ToolEntry e) => e.id == 'hazardous-locations'),
        isTrue,
      );
    });

    test('"Codes & Safety" is a registered subgroup header for quick-reference',
        () {
      expect(
        kCategorySubgroupOrder['quick-reference']!.contains('Codes & Safety'),
        isTrue,
      );
    });

    test('route resolves to a registered builder', () {
      expect(
        AppRouter.routes.containsKey('/tools/hazardous-locations'),
        isTrue,
      );
    });

    test('carries a non-empty keyword set', () {
      expect(kToolKeywords.containsKey('hazardous-locations'), isTrue);
      expect(kToolKeywords['hazardous-locations']!, isNotEmpty);
      expect(
        kToolKeywords['hazardous-locations']!.contains('atex'),
        isTrue,
      );
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
        await _withViewport(tester, const Size(375, 6000), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: const HazardousLocationsScreen(),
            ),
          );
          await tester.pump();
          expect(find.text('Hazardous Locations'), findsWidgets);
          expect(
            find.text('Class: what the hazard is made of'),
            findsOneWidget,
          );
          expect(find.text('Zone: the international system'), findsOneWidget);
          expect(
            find.text('Why a commercial AP cannot go there'),
            findsOneWidget,
          );
          // Read-only reference: no inputs.
          expect(find.byType(TextField), findsNothing);
          // No PNG bundled -> no embedded plate.
          expect(find.byType(DarkRasterDiagramCard), findsNothing);
        });
      }
    });

    testWidgets('shows exactly one plate card when the PNG is bundled',
        (tester) async {
      ReferenceImages.debugSetBundled(<String>{
        ReferenceImages.pathFor('hazardous-locations'),
      });
      addTearDown(ReferenceImages.debugReset);
      await _withViewport(tester, const Size(375, 6000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const HazardousLocationsScreen(),
          ),
        );
        await tester.pump();
        expect(find.byType(DarkRasterDiagramCard), findsOneWidget);
      });
    });

    testWidgets('no overflow at 320/375/768/1280 widths', (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 6000), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const HazardousLocationsScreen(),
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

/// Helper — run [body] with the test view sized to [size], then restore.
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
