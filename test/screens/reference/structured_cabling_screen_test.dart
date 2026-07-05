// Tests for the Structured Cabling reference screen, a Field & Trade Reference
// set entry (2026-07-05). Text-reference only (no decoder plate). Three layers,
// mirroring the Site Access reference tests:
//   1. Data fidelity (GL-005): the typed const dataset carries Penn's approved,
//      voice-gated facts verbatim (the four TIA standards, the four cable
//      categories, the 90+10 m channel rule), plus the no-em-dash and "Wi-Fi"
//      glyph guards across all rendered prose, with a data-fidelity count guard.
//   2. Registration: a live Quick Reference tile in the "Codes & Safety"
//      subgroup, a registered route builder, and a keyword set.
//   3. Widget render: the read-only screen renders its title and key content in
//      BOTH dark and light themes with no RenderFlex overflow at 320/375/768/
//      1280 widths.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/structured_cabling_data.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/structured_cabling_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('data fidelity (GL-005) — Penn\'s approved copy verbatim', () {
    test('TIA family: exactly 4 standards in order', () {
      expect(kTiaStandards.length, 4);
      expect(
        kTiaStandards.map((TiaStandard s) => s.number).toList(),
        <String>[
          'ANSI/TIA-568',
          'ANSI/TIA-569',
          'ANSI/TIA-606',
          'ANSI/TIA-607 (also J-STD-607)',
        ],
      );
    });

    test('anchor TIA standards carry the load-bearing facts', () {
      TiaStandard byNum(String prefix) => kTiaStandards
          .firstWhere((TiaStandard s) => s.number.startsWith(prefix));
      expect(byNum('ANSI/TIA-568').description.contains('cabling itself'),
          isTrue);
      expect(byNum('ANSI/TIA-607').description.contains('bonding and grounding'),
          isTrue);
    });

    test('cable categories: exactly 4, Cat 6A is the multi-gig bar', () {
      expect(kCableCategories.length, 4);
      expect(
        kCableCategories.map((CableCategory c) => c.category).toList(),
        <String>['Cat 5e', 'Cat 6', 'Cat 6A', 'Cat 8'],
      );
      final CableCategory cat6a = kCableCategories
          .firstWhere((CableCategory c) => c.category == 'Cat 6A');
      expect(cat6a.reach.contains('10 Gbps to 100 m'), isTrue);
      expect(cat6a.reach.contains('Wi-Fi 6, 6E, and 7'), isTrue);
    });

    test('the 90+10 m channel rule is stated', () {
      expect(kChannelIntro.contains('90 m'), isTrue);
      expect(kChannelIntro.contains('100 m channel maximum'), isTrue);
      expect(kChannelApReality.contains('IDF'), isTrue);
    });

    test('no em dash in any rendered prose; "Wi-Fi" casing where used', () {
      final List<String> prose = <String>[
        kStructuredCablingLead,
        kChannelIntro,
        kChannelApReality,
        kPinoutNote,
        kTopologyNote,
        kBicsiNote,
        kStructuredCablingWlanCares,
        kStructuredCablingDeferNote,
        for (final TiaStandard s in kTiaStandards) ...<String>[
          s.number,
          s.description,
        ],
        for (final CableCategory c in kCableCategories) ...<String>[
          c.category,
          c.reach,
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
        (ToolEntry e) => e.id == 'structured-cabling',
      );
      expect(t.isLive, isTrue);
      expect(t.routeName, '/tools/structured-cabling');
      expect(t.title, 'Structured Cabling');
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
          s.tools.any((ToolEntry e) => e.id == 'structured-cabling'),
          isFalse,
          reason: 'structured-cabling orphaned into Other',
        );
      }
      final ToolSection codes =
          sections.firstWhere((ToolSection s) => s.header == 'Codes & Safety');
      expect(
        codes.tools.any((ToolEntry e) => e.id == 'structured-cabling'),
        isTrue,
      );
    });

    test('route resolves to a registered builder', () {
      expect(AppRouter.routes.containsKey('/tools/structured-cabling'), isTrue);
    });

    test('carries a non-empty keyword set', () {
      expect(kToolKeywords.containsKey('structured-cabling'), isTrue);
      expect(kToolKeywords['structured-cabling']!, isNotEmpty);
      expect(kToolKeywords['structured-cabling']!.contains('rcdd'), isTrue);
    });
  });

  group('widget render (dark + light, no overflow)', () {
    testWidgets('renders title + key content in dark + light', (tester) async {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.dark(),
        AppTheme.light(),
      ]) {
        await _withViewport(tester, const Size(375, 5200), () async {
          await tester.pumpWidget(
            MaterialApp(theme: theme, home: const StructuredCablingScreen()),
          );
          await tester.pump();
          expect(find.text('Structured Cabling'), findsWidgets);
          expect(find.text('The TIA family'), findsOneWidget);
          expect(find.text('Cable categories'), findsOneWidget);
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
              home: const StructuredCablingScreen(),
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
