// Tests for the Facility Spaces reference screen, a Field & Trade Reference set
// entry (2026-07-05). Three layers: data fidelity (the six-term decode table,
// plus the no-em-dash / "Wi-Fi" guards), registration (a live "Verticals" Quick
// Reference tile, route, keywords), and widget render (dark + light, no overflow
// at 320/375/768/1280, plate omitted when unbundled and shown once when
// bundled).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/facility_spaces_data.dart';
import 'package:wlan_pros_toolbox/data/reference_images.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/facility_spaces_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/dark_raster_diagram_card.dart';

List<String> _allProse() => <String>[
      kFacilityLead,
      kFacilityStandard,
      kFacilitySameRoom,
      kFacilityTopology,
      kFacilityShape,
      kFacilityInternational,
      kFacilityWlanCares,
      kFacilityDeferNote,
      for (final TelecomSpaceRow s in kTelecomSpaces) ...<String>[
        s.term,
        s.whatItIs,
        s.standardOrField,
      ],
    ];

void main() {
  group('data fidelity (GL-005) — Penn\'s approved copy verbatim', () {
    test('decode table: exactly 6 terms; TR / IDF / Data closet anchored', () {
      expect(kTelecomSpaces.length, 6);
      TelecomSpaceRow byTerm(String prefix) => kTelecomSpaces
          .firstWhere((TelecomSpaceRow s) => s.term.startsWith(prefix));
      expect(byTerm('Telecommunications Room').standardOrField,
          'Current standard vocabulary');
      expect(
        byTerm('IDF').whatItIs.contains('Functionally the same as a TR'),
        isTrue,
      );
      expect(byTerm('Data closet').standardOrField, 'Slang');
    });

    test('no em dash in any rendered prose; "Wi-Fi" casing where used', () {
      for (final String s in _allProse()) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        expect(s.contains('WiFi'), isFalse, reason: 'must be "Wi-Fi" in "$s"');
      }
    });
  });

  group('registration (catalog + subgroup + router + keywords)', () {
    test('live Quick Reference tile in "Verticals"', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final ToolEntry t = qr.tools.firstWhere(
        (ToolEntry e) => e.id == 'facility-spaces',
      );
      expect(t.isLive, isTrue);
      expect(t.routeName, '/tools/facility-spaces');
      expect(t.title, 'Facility Spaces');
      expect(t.subgroup, 'Verticals');
    });

    test('grouping places the tool under "Verticals", not "Other"', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final List<ToolSection> sections = groupedCategoryTools(qr);
      for (final ToolSection s
          in sections.where((ToolSection s) => s.header == 'Other')) {
        expect(
          s.tools.any((ToolEntry e) => e.id == 'facility-spaces'),
          isFalse,
          reason: 'facility-spaces orphaned into Other',
        );
      }
      final ToolSection v = sections.firstWhere(
        (ToolSection s) => s.header == 'Verticals',
      );
      expect(v.tools.any((ToolEntry e) => e.id == 'facility-spaces'), isTrue);
    });

    test('route resolves to a registered builder', () {
      expect(AppRouter.routes.containsKey('/tools/facility-spaces'), isTrue);
    });

    test('carries a non-empty keyword set', () {
      expect(kToolKeywords.containsKey('facility-spaces'), isTrue);
      expect(kToolKeywords['facility-spaces']!, isNotEmpty);
      expect(kToolKeywords['facility-spaces']!.contains('idf'), isTrue);
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
            MaterialApp(theme: theme, home: const FacilitySpacesScreen()),
          );
          await tester.pump();
          expect(find.text('Facility Spaces'), findsWidgets);
          expect(find.text('The terms, decoded'), findsOneWidget);
          expect(find.text('Why a WLAN pro cares'), findsOneWidget);
          expect(find.byType(TextField), findsNothing);
          expect(find.byType(DarkRasterDiagramCard), findsNothing);
        });
      }
    });

    testWidgets('shows exactly one plate card when the PNG is bundled',
        (tester) async {
      ReferenceImages.debugSetBundled(<String>{
        ReferenceImages.pathFor('facility-spaces'),
      });
      addTearDown(ReferenceImages.debugReset);
      await _withViewport(tester, const Size(375, 6000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const FacilitySpacesScreen(),
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
              home: const FacilitySpacesScreen(),
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
