// Tests for the Enclosure Ratings reference screen (IP / NEMA), the pilot
// REFERENCE-screen entry of the Field & Trade Reference set (2026-07-05).
//
// Three layers, mirroring the established per-screen reference tests:
//   1. Data fidelity (GL-005): the typed const datasets carry Penn's approved,
//      voice-gated facts verbatim (the IP digit ladders, the common-IP table,
//      the NEMA types, the one-way NEMA->IP mapping, the placement guidance),
//      plus the no-em-dash and "Wi-Fi" glyph rules across all rendered prose.
//   2. Registration: the tool has a live Quick Reference tile in the proposed
//      "Codes & Safety" subgroup, a registered route builder, a keyword set, and
//      a help entry. The help count guard is asserted in tool_help_loader_test.
//   3. Widget render: the read-only screen renders its title and key content
//      across phone/tablet/desktop widths, in BOTH dark and light themes, with
//      no RenderFlex overflow; the embedded-PNG plate is omitted when the asset
//      is not bundled (graceful degradation) and shown once when it is.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/enclosure_ratings_data.dart';
import 'package:wlan_pros_toolbox/data/reference_images.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/enclosure_ratings_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/dark_raster_diagram_card.dart';

void main() {
  group('data fidelity (GL-005) — Penn\'s approved copy verbatim', () {
    test('IP first digit: 7 rungs, 6 = dust-tight, ladder ends at 4 (1 mm)', () {
      expect(kIpSolidsDigits.length, 7);
      expect(kIpSolidsDigits.first.code, '0');
      final IpDigit six =
          kIpSolidsDigits.firstWhere((IpDigit d) => d.code == '6');
      expect(six.label, 'Dust-tight');
      expect(six.detail, 'No dust ingress at all');
      // The object-size gate is defined only through digit 4 (1.0 mm).
      final IpDigit four =
          kIpSolidsDigits.firstWhere((IpDigit d) => d.code == '4');
      expect(four.detail.contains('1.0 mm'), isTrue);
    });

    test('IP second digit: 10 rungs, 7 = 1 m immersion, top rung is 9K', () {
      expect(kIpWaterDigits.length, 10);
      final IpDigit seven =
          kIpWaterDigits.firstWhere((IpDigit d) => d.code == '7');
      expect(seven.label, 'Immersion');
      expect(seven.detail, 'Temporary immersion to 1 m for 30 min');
      expect(kIpWaterDigits.last.code, '9K');
      // 8 is manufacturer-defined depth, not a fixed figure.
      final IpDigit eight =
          kIpWaterDigits.firstWhere((IpDigit d) => d.code == '8');
      expect(eight.detail.contains('set by the manufacturer'), isTrue);
    });

    test('common IP ratings include IP66 (mainstream outdoor) and IP69K', () {
      final IpRating ip66 =
          kCommonIpRatings.firstWhere((IpRating r) => r.rating == 'IP66');
      expect(ip66.meaning, 'Dust-tight, powerful jets');
      expect(ip66.example, 'Mainstream outdoor AP or antenna');
      expect(
        kCommonIpRatings.any((IpRating r) => r.rating == 'IP69K'),
        isTrue,
      );
    });

    test('NEMA 4X carries the corrosion point ("X" is the whole point)', () {
      final NemaType x = kNemaTypes.firstWhere((NemaType n) => n.type == '4X');
      expect(x.meaning.contains('corrosion resistance'), isTrue);
      expect(x.meaning.contains('The "X" is the whole point'), isTrue);
    });

    test('NEMA-to-IP is a MINIMUM-floor mapping (one-way rule)', () {
      // The rule text is the load-bearing caveat.
      expect(kNemaToIpRule, 'NEMA to IP: valid as a minimum. IP to NEMA: not valid.');
      final NemaIpMapping four =
          kNemaToIp.firstWhere((NemaIpMapping m) => m.nemaType == '4');
      expect(four.minimumIp, 'IP66');
      // Rows where sources disagree show both cited values.
      final NemaIpMapping threeR =
          kNemaToIp.firstWhere((NemaIpMapping m) => m.nemaType == '3R');
      expect(threeR.minimumIp.contains('also cited'), isTrue);
    });

    test('placement guidance: coastal reaches for NEMA 4X (salt = corrosion)', () {
      final PlacementGuidance coastal = kPlacementGuidance.firstWhere(
        (PlacementGuidance p) => p.placement == 'Coastal or marine',
      );
      expect(coastal.reachFor.contains('NEMA 4X'), isTrue);
      expect(coastal.why.contains('salt'), isTrue);
    });

    test('no em dash in any rendered prose; "Wi-Fi" casing where used', () {
      final List<String> prose = <String>[
        kEnclosureLead,
        kIpCodeIntro,
        kIpCodeExample,
        kIpSolidsNote,
        kIpWaterNote,
        kNemaIntro,
        kNemaFullListNote,
        kNemaToIpIntro,
        kNemaToIpRule,
        kNemaToIpNote,
        kEnclosureDeferNote,
        ...kIpLetterNotes,
        ...kEnclosureMyths,
        ...kEnclosureWlanCares,
        for (final IpDigit d in kIpSolidsDigits) ...<String>[d.label, d.detail],
        for (final IpDigit d in kIpWaterDigits) ...<String>[d.label, d.detail],
        for (final IpRating r in kCommonIpRatings) ...<String>[
          r.meaning,
          r.example,
        ],
        for (final NemaType n in kNemaTypes) n.meaning,
        for (final NemaIpMapping m in kNemaToIp) m.minimumIp,
        for (final PlacementGuidance p in kPlacementGuidance) ...<String>[
          p.placement,
          p.reachFor,
          p.why,
        ],
      ];
      for (final String s in prose) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        expect(s.contains('WiFi'), isFalse, reason: 'must be "Wi-Fi" in "$s"');
      }
    });
  });

  group('registration (catalog + subgroup + router + keywords)', () {
    test('live Quick Reference tile in the proposed "Codes & Safety" subgroup',
        () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final ToolEntry t = qr.tools.firstWhere(
        (ToolEntry e) => e.id == 'enclosure-ratings',
      );
      expect(t.isLive, isTrue);
      expect(t.routeName, '/tools/enclosure-ratings');
      expect(t.title, 'Enclosure Ratings');
      expect(t.subgroup, 'Codes & Safety');
    });

    test('"Codes & Safety" is a registered subgroup header for quick-reference',
        () {
      expect(
        kCategorySubgroupOrder['quick-reference']!.contains('Codes & Safety'),
        isTrue,
      );
    });

    test('no orphaned subgroup — grouping places the tool under its header', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final List<ToolSection> sections = groupedCategoryTools(qr);
      // The tool must not fall into a trailing "Other" bucket.
      final Iterable<ToolSection> other =
          sections.where((ToolSection s) => s.header == 'Other');
      for (final ToolSection s in other) {
        expect(
          s.tools.any((ToolEntry e) => e.id == 'enclosure-ratings'),
          isFalse,
          reason: 'enclosure-ratings orphaned into Other',
        );
      }
      final ToolSection codes =
          sections.firstWhere((ToolSection s) => s.header == 'Codes & Safety');
      expect(
        codes.tools.any((ToolEntry e) => e.id == 'enclosure-ratings'),
        isTrue,
      );
    });

    test('route resolves to a registered builder', () {
      expect(
        AppRouter.routes.containsKey('/tools/enclosure-ratings'),
        isTrue,
      );
    });

    test('carries a non-empty keyword set', () {
      expect(kToolKeywords.containsKey('enclosure-ratings'), isTrue);
      expect(kToolKeywords['enclosure-ratings']!, isNotEmpty);
      expect(kToolKeywords['enclosure-ratings']!.contains('nema'), isTrue);
    });
  });

  group('widget render (dark + light, no overflow)', () {
    setUp(() {
      // No reference PNG bundled by default -> the plate is omitted and the page
      // must still render fully as native text (graceful degradation).
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
            MaterialApp(
              theme: theme,
              home: const EnclosureRatingsScreen(),
            ),
          );
          await tester.pump();
          expect(find.text('Enclosure Ratings'), findsWidgets);
          expect(find.text('IP code (IEC 60529)'), findsOneWidget);
          expect(find.text('NEMA (NEMA 250)'), findsOneWidget);
          expect(
            find.text('NEMA to IP: a one-way relationship'),
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
        ReferenceImages.pathFor('enclosure-ratings'),
      });
      addTearDown(ReferenceImages.debugReset);
      await _withViewport(tester, const Size(375, 4000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const EnclosureRatingsScreen(),
          ),
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
              home: const EnclosureRatingsScreen(),
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
