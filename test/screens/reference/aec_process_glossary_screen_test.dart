// Tests for the AEC Process & Glossary reference screen, a Field & Trade
// Reference set entry (2026-07-05). Text-reference only (no decoder plate),
// glossary-heavy. Three layers, mirroring the Site Access reference tests:
//   1. Data fidelity (GL-005): the typed const datasets carry Penn's approved,
//      voice-gated facts verbatim (the six design phases with when-Wi-Fi-
//      engages, the AEC glossary terms), plus the no-em-dash and "Wi-Fi" glyph
//      guards across all rendered prose, with a data-fidelity count guard.
//   2. Registration: a live Quick Reference tile in the "Codes & Safety"
//      subgroup, a registered route builder, and a keyword set.
//   3. Widget render: the read-only screen renders its title and key content in
//      BOTH dark and light themes with no RenderFlex overflow at 320/375/768/
//      1280 widths.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/aec_process_glossary_data.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/aec_process_glossary_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('data fidelity (GL-005) — Penn\'s approved copy verbatim', () {
    test('design phases: exactly 6 in order, with acronyms', () {
      expect(kAecPhases.length, 6);
      expect(
        kAecPhases.map((AecPhase p) => p.phase).toList(),
        <String>[
          'Programming',
          'Schematic Design',
          'Design Development',
          'Construction Documents',
          'Bidding / Negotiation',
          'Construction Administration',
        ],
      );
      expect(
        kAecPhases.map((AecPhase p) => p.abbr).toList(),
        <String>['', 'SD', 'DD', 'CD', '', 'CA'],
      );
    });

    test('SD is the moment to establish RF requirements', () {
      final AecPhase sd =
          kAecPhases.firstWhere((AecPhase p) => p.abbr == 'SD');
      expect(sd.whenWifi.contains('establish RF requirements'), isTrue);
      expect(kEngageSdNote.contains('designing Wi-Fi in'), isTrue);
    });

    test('glossary carries the load-bearing terms verbatim', () {
      GlossaryTerm byAbbr(String a) =>
          kAecGlossary.firstWhere((GlossaryTerm g) => g.abbr == a);
      GlossaryTerm byTerm(String t) =>
          kAecGlossary.firstWhere((GlossaryTerm g) => g.term == t);
      expect(kAecGlossary.length, 14);
      expect(byAbbr('RFI').term, 'Request for Information');
      expect(byAbbr('RFI').definition.contains('formal question'), isTrue);
      expect(byAbbr('AHJ').term, 'Authority Having Jurisdiction');
      expect(byAbbr('AHJ').definition.contains('word governs'), isTrue);
      expect(byTerm('Submittal').abbr, '');
      expect(byTerm('Submittal').definition.contains('contractor\'s proof'),
          isTrue);
    });

    test('no em dash in any rendered prose; "Wi-Fi" casing where used', () {
      final List<String> prose = <String>[
        kAecProcessLead,
        kEngageSdNote,
        kAiaNote,
        kAecProcessWlanCares,
        kAecProcessDeferNote,
        for (final AecPhase p in kAecPhases) ...<String>[
          p.abbr,
          p.phase,
          p.whatHappens,
          p.whenWifi,
        ],
        for (final GlossaryTerm g in kAecGlossary) ...<String>[
          g.abbr,
          g.term,
          g.definition,
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
        (ToolEntry e) => e.id == 'aec-process-glossary',
      );
      expect(t.isLive, isTrue);
      expect(t.routeName, '/tools/aec-process-glossary');
      expect(t.title, 'AEC Process & Glossary');
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
          s.tools.any((ToolEntry e) => e.id == 'aec-process-glossary'),
          isFalse,
          reason: 'aec-process-glossary orphaned into Other',
        );
      }
      final ToolSection codes =
          sections.firstWhere((ToolSection s) => s.header == 'Codes & Safety');
      expect(
        codes.tools.any((ToolEntry e) => e.id == 'aec-process-glossary'),
        isTrue,
      );
    });

    test('route resolves to a registered builder', () {
      expect(
        AppRouter.routes.containsKey('/tools/aec-process-glossary'),
        isTrue,
      );
    });

    test('carries a non-empty keyword set', () {
      expect(kToolKeywords.containsKey('aec-process-glossary'), isTrue);
      expect(kToolKeywords['aec-process-glossary']!, isNotEmpty);
      expect(kToolKeywords['aec-process-glossary']!.contains('rfi'), isTrue);
    });
  });

  group('widget render (dark + light, no overflow)', () {
    testWidgets('renders title + key content in dark + light', (tester) async {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.dark(),
        AppTheme.light(),
      ]) {
        await _withViewport(tester, const Size(375, 6000), () async {
          await tester.pumpWidget(
            MaterialApp(theme: theme, home: const AecProcessGlossaryScreen()),
          );
          await tester.pump();
          expect(find.text('AEC Process & Glossary'), findsWidgets);
          expect(
            find.text('The design phases, and when Wi-Fi should engage'),
            findsOneWidget,
          );
          expect(
            find.text('The glossary that trips WLAN pros up'),
            findsOneWidget,
          );
          expect(find.byType(TextField), findsNothing);
        });
      }
    });

    testWidgets('no overflow at 320/375/768/1280 widths', (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 6000), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const AecProcessGlossaryScreen(),
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
