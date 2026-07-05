// Tests for the Safety Basics (PPE + ESD) reference screen, a Field & Trade
// Reference set entry (2026-07-05). Three layers, mirroring the Enclosure
// Ratings reference tests:
//   1. Data fidelity (GL-005): the typed const datasets carry Penn's approved,
//      voice-gated facts verbatim (the four PPE items + standards, the four
//      named recognize-and-STOP hazards), plus the no-em-dash and "Wi-Fi" glyph
//      guards across all rendered prose, with a data-fidelity count guard.
//   2. Registration: a live Quick Reference tile in the "Codes & Safety"
//      subgroup, a registered route builder, a keyword set, and a help entry.
//   3. Widget render: the read-only screen renders its title and key content in
//      BOTH dark and light themes with no RenderFlex overflow; the embedded-PNG
//      plate is omitted when the asset is not bundled and shown once when it is.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/reference_images.dart';
import 'package:wlan_pros_toolbox/data/safety_basics_data.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/safety_basics_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/dark_raster_diagram_card.dart';

void main() {
  group('data fidelity (GL-005) — Penn\'s approved copy verbatim', () {
    test('PPE ladder: exactly 4 items with their standards', () {
      expect(kPpeItems.length, 4);
      final PpeItem hat =
          kPpeItems.firstWhere((PpeItem p) => p.name.startsWith('Hard hat'));
      expect(hat.standard, 'ANSI/ISEA Z89.1');
      final PpeItem eyes =
          kPpeItems.firstWhere((PpeItem p) => p.name == 'Eye protection');
      expect(eyes.standard, 'ANSI Z87.1');
      expect(
        kPpeItems.map((PpeItem p) => p.standard).toList(),
        <String>['ANSI/ISEA Z89.1', 'ASTM F2413', 'ANSI/ISEA 107', 'ANSI Z87.1'],
      );
    });

    test('recognize-and-STOP: 4 named hazards, named-and-stopped verbatim', () {
      expect(kSafetyStopHazards.length, 4);
      expect(
        kSafetyStopHazards[0].startsWith('Asbestos or lead in older buildings.'),
        isTrue,
      );
      expect(kSafetyStopHazards[1].contains('Arc flash'), isTrue);
      expect(kSafetyStopHazards[1].contains('NFPA 70E'), isTrue);
      expect(kSafetyStopHazards[2].contains('Confined spaces'), isTrue);
      expect(kSafetyStopHazards[3].contains('Seismic bracing'), isTrue);
      // Named-and-stopped: the closing line forbids treating them as procedure.
      expect(
        kSafetyStopClosing,
        'Never treat any of these as a procedure to run yourself.',
      );
    });

    test('ESD note names the standard and the latent-damage risk', () {
      expect(kEsdParagraphs.length, 2);
      expect(kEsdParagraphs[1].contains('ANSI/ESD S20.20'), isTrue);
      expect(kEsdParagraphs[0].contains('latent damage'), isTrue);
    });

    test('no em dash in any rendered prose; "Wi-Fi" casing where used', () {
      final List<String> prose = <String>[
        kSafetyLead,
        kPpeIntro,
        kPpeNote,
        kSafetyStopIntro,
        kSafetyStopClosing,
        kSafetyWlanCares,
        kSafetyDeferNote,
        ...kEsdParagraphs,
        ...kSafetyStopHazards,
        for (final PpeItem p in kPpeItems) ...<String>[
          p.name,
          p.standard,
          p.meaning,
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
        (ToolEntry e) => e.id == 'safety-basics',
      );
      expect(t.isLive, isTrue);
      expect(t.routeName, '/tools/safety-basics');
      expect(t.title, 'Safety Basics');
      expect(t.subgroup, 'Codes & Safety');
    });

    test('grouping places the tool under "Codes & Safety", not "Other"', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final List<ToolSection> sections = groupedCategoryTools(qr);
      for (final ToolSection s in sections.where(
        (ToolSection s) => s.header == 'Other',
      )) {
        expect(
          s.tools.any((ToolEntry e) => e.id == 'safety-basics'),
          isFalse,
          reason: 'safety-basics orphaned into Other',
        );
      }
      final ToolSection codes =
          sections.firstWhere((ToolSection s) => s.header == 'Codes & Safety');
      expect(
        codes.tools.any((ToolEntry e) => e.id == 'safety-basics'),
        isTrue,
      );
    });

    test('route resolves to a registered builder', () {
      expect(AppRouter.routes.containsKey('/tools/safety-basics'), isTrue);
    });

    test('carries a non-empty keyword set', () {
      expect(kToolKeywords.containsKey('safety-basics'), isTrue);
      expect(kToolKeywords['safety-basics']!, isNotEmpty);
      expect(kToolKeywords['safety-basics']!.contains('ppe'), isTrue);
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
        await _withViewport(tester, const Size(375, 4000), () async {
          await tester.pumpWidget(
            MaterialApp(theme: theme, home: const SafetyBasicsScreen()),
          );
          await tester.pump();
          expect(find.text('Safety Basics'), findsWidgets);
          expect(find.text('The PPE ladder'), findsOneWidget);
          expect(find.text('Recognize and STOP'), findsOneWidget);
          expect(
            find.text('ESD: protecting the gear, not the person'),
            findsOneWidget,
          );
          expect(find.byType(TextField), findsNothing);
          expect(find.byType(DarkRasterDiagramCard), findsNothing);
        });
      }
    });

    testWidgets('shows exactly one plate card when the PNG is bundled',
        (tester) async {
      ReferenceImages.debugSetBundled(<String>{
        ReferenceImages.pathFor('safety-basics'),
      });
      addTearDown(ReferenceImages.debugReset);
      await _withViewport(tester, const Size(375, 4000), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const SafetyBasicsScreen()),
        );
        await tester.pump();
        expect(find.byType(DarkRasterDiagramCard), findsOneWidget);
      });
    });

    testWidgets('no overflow at 320/375/768/1280 widths', (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 3600), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const SafetyBasicsScreen(),
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
