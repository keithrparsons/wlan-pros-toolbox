// Tests for the Healthcare Wi-Fi reference screen, a Field & Trade Reference set
// entry (2026-07-05). Three layers: data fidelity (the three WMTS bands, the
// five authorities incl. the biomed handoff, the eight-item pre-quote checklist,
// plus the no-em-dash / "Wi-Fi" guards), registration (a live "Verticals" Quick
// Reference tile, route, keywords), and widget render (dark + light, no overflow
// at 320/375/768/1280, the shielded-rooms caution rendered as a warning band,
// plate omitted when unbundled and shown once when bundled).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/healthcare_vertical_data.dart';
import 'package:wlan_pros_toolbox/data/reference_images.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/healthcare_vertical_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/dark_raster_diagram_card.dart';

List<String> _allProse() => <String>[
      kHealthcareLead,
      kHealthcareThroughLine,
      kHealthcareNotOffice,
      kWmtsIntro,
      ...kWmtsBands,
      kWmtsHistory,
      kWmtsTakeaway,
      kHealthcareSharedAir,
      kEmcStandard,
      kEmcDesignerRead,
      kRoamingHard,
      kCoverageGrade,
      kRtlsIntro,
      ...kRtlsLandscape,
      kRtlsGradeDriver,
      kHealthcareSegmentation,
      kHealthcareBuildingWarning,
      kHealthcareAuthoritiesIntro,
      ...kHealthcarePreQuote,
      kHealthcareWlanCares,
      kHealthcareDeferNote,
      for (final HealthcareAuthority a in kHealthcareAuthorities) ...<String>[
        a.authority,
        a.governs,
        a.yourMove,
      ],
    ];

void main() {
  group('data fidelity (GL-005) — Penn\'s approved copy verbatim', () {
    test('WMTS bands: exactly 3, the 608-614 band anchored', () {
      expect(kWmtsBands.length, 3);
      expect(kWmtsBands.first, '608 to 614 MHz');
    });

    test('authorities: exactly 5, the biomed handoff last', () {
      expect(kHealthcareAuthorities.length, 5);
      expect(
        kHealthcareAuthorities.last.authority
            .contains('biomedical engineering'),
        isTrue,
      );
      expect(
        kHealthcareAuthorities.last.yourMove.contains('coordinate with biomed'),
        isTrue,
      );
    });

    test('pre-quote checklist: exactly 8; RTLS landscape: exactly 3', () {
      expect(kHealthcarePreQuote.length, 8);
      expect(kRtlsLandscape.length, 3);
      expect(kHealthcarePreQuote[2].contains('voice-and-RTLS grade'), isTrue);
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
        (ToolEntry e) => e.id == 'healthcare-vertical',
      );
      expect(t.isLive, isTrue);
      expect(t.routeName, '/tools/healthcare-vertical');
      expect(t.title, 'Healthcare Wi-Fi');
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
          s.tools.any((ToolEntry e) => e.id == 'healthcare-vertical'),
          isFalse,
          reason: 'healthcare-vertical orphaned into Other',
        );
      }
      final ToolSection v = sections.firstWhere(
        (ToolSection s) => s.header == 'Verticals',
      );
      expect(v.tools.any((ToolEntry e) => e.id == 'healthcare-vertical'), isTrue);
    });

    test('route resolves to a registered builder', () {
      expect(AppRouter.routes.containsKey('/tools/healthcare-vertical'), isTrue);
    });

    test('carries a non-empty keyword set', () {
      expect(kToolKeywords.containsKey('healthcare-vertical'), isTrue);
      expect(kToolKeywords['healthcare-vertical']!, isNotEmpty);
      expect(kToolKeywords['healthcare-vertical']!.contains('wmts'), isTrue);
    });
  });

  group('widget render (dark + light, no overflow)', () {
    setUp(() {
      ReferenceImages.debugSetBundled(const <String>{});
    });
    tearDown(ReferenceImages.debugReset);

    testWidgets(
        'renders title + key content + warning band in dark + light, plate '
        'omitted', (tester) async {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.dark(),
        AppTheme.light(),
      ]) {
        await _withViewport(tester, const Size(375, 8000), () async {
          await tester.pumpWidget(
            MaterialApp(theme: theme, home: const HealthcareVerticalScreen()),
          );
          await tester.pump();
          expect(find.text('Healthcare Wi-Fi'), findsWidgets);
          expect(find.text('Before you quote a hospital'), findsOneWidget);
          expect(find.text('Why a WLAN pro cares'), findsOneWidget);
          expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
          expect(find.byType(TextField), findsNothing);
          expect(find.byType(DarkRasterDiagramCard), findsNothing);
        });
      }
    });

    testWidgets('shows exactly one plate card when the PNG is bundled',
        (tester) async {
      ReferenceImages.debugSetBundled(<String>{
        ReferenceImages.pathFor('healthcare-vertical'),
      });
      addTearDown(ReferenceImages.debugReset);
      await _withViewport(tester, const Size(375, 8000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const HealthcareVerticalScreen(),
          ),
        );
        await tester.pump();
        expect(find.byType(DarkRasterDiagramCard), findsOneWidget);
      });
    });

    testWidgets('no overflow at 320/375/768/1280 widths', (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 8000), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const HealthcareVerticalScreen(),
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
