// Tests for the Vendor Model Decode screen — the INTERACTIVE per-vendor AP
// model-number decoder (Field & Trade Reference set, 2026-07-05).
//
// Four layers:
//   1. Data fidelity (GL-005): the typed const dataset carries the voice-gated,
//      fact-confirmed facts verbatim (the per-vendor token schemes, the worked
//      examples, the E-letter collision, the Aruba even/odd rule with its
//      "confirmed back to Wi-Fi 5, 200-series unverified" caveat, Extreme's
//      Medium confidence), plus the no-em-dash / "Wi-Fi" glyph rules.
//   2. Honest-schema guard: the screen is NOT a paste-a-model auto-decoder (no
//      TextField), because several vendors do not digit-encode generation /
//      streams / antenna; the Extreme note says so explicitly.
//   3. Registration: a live Quick Reference tile in the proposed "Vendor &
//      Hardware" subgroup, a registered route builder, a keyword set, and a help
//      entry (count asserted in tool_help_loader_test).
//   4. Widget render + DRILL-DOWN: the vendor picker renders with the E-letter
//      warning up front; tapping a vendor drills into its token table + worked
//      example; no RenderFlex overflow at 320/375/768/1280 in dark and light.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/data/vendor_model_decode_data.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/vendor_model_decode_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('data fidelity (GL-005) — voice-gated copy verbatim', () {
    test('five vendors decode here; Juniper/Fortinet/Cambium/Omada are backlog',
        () {
      expect(kDecodeVendors.map((DecodeVendor v) => v.id),
          containsAll(<String>['cisco', 'aruba', 'unifi', 'ruckus', 'extreme']));
      expect(kDecodeBacklogNote.contains('Juniper Mist'), isTrue);
      expect(kDecodeBacklogNote.contains('Omada'), isTrue);
    });

    test('the E-letter collision is the load-bearing honest rule', () {
      expect(kDecodeHonestRule.contains('Cisco -E'), isTrue);
      expect(kDecodeHonestRule.contains('external antenna'), isTrue);
      expect(kDecodeHonestRule.contains('UniFi Enterprise'), isTrue);
    });

    test('Aruba even/odd antenna rule carries the age caveat', () {
      final DecodeVendor aruba =
          kDecodeVendors.firstWhere((DecodeVendor v) => v.id == 'aruba');
      expect(aruba.confidence, 'High (with one age caveat)');
      // even = external, odd = internal.
      final ModelToken last = aruba.tokens
          .firstWhere((ModelToken t) => t.token.contains('Last digit'));
      expect(last.encodes.contains('even = external antenna, odd = internal'),
          isTrue);
      // Confirmed back to Wi-Fi 5 (300 series); 200 series unverified.
      expect(aruba.confidenceNote.contains('confirmed back to the Wi-Fi 5'),
          isTrue);
      expect(aruba.confidenceNote.contains('200 series'), isTrue);
      expect(aruba.confidenceNote.contains('unverified'), isTrue);
    });

    test('Extreme is Medium confidence: only the first digit decodes', () {
      final DecodeVendor extreme =
          kDecodeVendors.firstWhere((DecodeVendor v) => v.id == 'extreme');
      expect(extreme.confidence, 'Medium');
      expect(
        extreme.tokens.any((ModelToken t) =>
            t.encodes.contains('Stated per model, NOT digit-encoded')),
        isTrue,
      );
      expect(
        extreme.confidenceNote.contains('per-model datasheet lookup'),
        isTrue,
      );
    });

    test('Cisco worked example decodes C9130AXI-B end to end', () {
      final DecodeVendor cisco =
          kDecodeVendors.firstWhere((DecodeVendor v) => v.id == 'cisco');
      expect(cisco.exampleSku, 'C9130AXI-B');
      final DecodeStep domain = cisco.exampleSteps
          .firstWhere((DecodeStep s) => s.segment == '-B');
      expect(domain.meaning.contains('not the antenna E'), isTrue);
      expect(cisco.readBack.contains('internal antennas'), isTrue);
    });

    test('no em dash in any rendered prose; "Wi-Fi" casing where used', () {
      final List<String> prose = <String>[
        kDecodeLead,
        kDecodeHonestRule,
        kDecodeStandingCaveat,
        kDecodeDeferNote,
        kDecodeBacklogNote,
        for (final DecodeVendor v in kDecodeVendors) ...<String>[
          v.name,
          v.intro,
          v.readBack,
          v.confidenceNote,
          if (v.suffixTitle != null) v.suffixTitle!,
          ...v.suffixMeanings,
          for (final ModelToken t in v.tokens) ...<String>[
            t.token,
            t.encodes,
            t.example,
          ],
          for (final DecodeStep s in v.exampleSteps) ...<String>[
            s.segment,
            s.meaning,
          ],
        ],
      ];
      for (final String s in prose) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        expect(s.contains('WiFi'), isFalse, reason: 'must be "Wi-Fi" in "$s"');
      }
    });
  });

  group('registration (catalog + subgroup + router + keywords)', () {
    test('live Quick Reference tile in the proposed "Vendor & Hardware" subgroup',
        () {
      final ToolCategory qr = kToolCategories
          .firstWhere((ToolCategory c) => c.id == 'quick-reference');
      final ToolEntry t =
          qr.tools.firstWhere((ToolEntry e) => e.id == 'vendor-model-decode');
      expect(t.isLive, isTrue);
      expect(t.routeName, '/tools/vendor-model-decode');
      expect(t.title, 'Vendor Model Decode');
      expect(t.subgroup, 'Vendor & Hardware');
    });

    test('"Vendor & Hardware" is a registered subgroup header', () {
      expect(
        kCategorySubgroupOrder['quick-reference']!.contains('Vendor & Hardware'),
        isTrue,
      );
    });

    test('no orphaned subgroup — grouping places the tool under its header', () {
      final ToolCategory qr = kToolCategories
          .firstWhere((ToolCategory c) => c.id == 'quick-reference');
      final List<ToolSection> sections = groupedCategoryTools(qr);
      for (final ToolSection s
          in sections.where((ToolSection s) => s.header == 'Other')) {
        expect(
            s.tools.any((ToolEntry e) => e.id == 'vendor-model-decode'), isFalse);
      }
      final ToolSection vh = sections
          .firstWhere((ToolSection s) => s.header == 'Vendor & Hardware');
      expect(vh.tools.any((ToolEntry e) => e.id == 'vendor-model-decode'), isTrue);
    });

    test('route resolves to a registered builder', () {
      expect(AppRouter.routes.containsKey('/tools/vendor-model-decode'), isTrue);
    });

    test('carries a non-empty keyword set', () {
      expect(kToolKeywords.containsKey('vendor-model-decode'), isTrue);
      expect(kToolKeywords['vendor-model-decode']!.contains('model number'),
          isTrue);
    });
  });

  group('widget render + drill-down (dark + light, no overflow)', () {
    testWidgets('picker shows the E-letter warning up front, then drills in',
        (tester) async {
      await _withViewport(tester, const Size(375, 4000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const VendorModelDecodeScreen(),
          ),
        );
        await tester.pump();

        expect(find.text('Vendor Model Decode'), findsWidgets);
        expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
        // Honest schema, NOT an auto-decode input.
        expect(find.byType(TextField), findsNothing);

        // Drill into Cisco -> its token table + worked example.
        await tester.tap(find.text('Cisco (Catalyst / Aironet / IW, plus Meraki CW)'));
        await tester.pumpAndSettle();
        expect(find.text('Read the model left to right'), findsOneWidget);
        expect(find.text('Worked example: C9130AXI-B'), findsOneWidget);
        expect(find.text('Confidence and caveats'), findsOneWidget);

        // Back to the vendor picker.
        await tester.tap(find.text('All vendors'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Extreme Networks'), findsWidgets);
      });
    });

    testWidgets('Extreme detail states the no-auto-decode honesty', (tester) async {
      await _withViewport(tester, const Size(375, 4000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const VendorModelDecodeScreen(),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.text('Extreme Networks (AP3000 / AP4000 / AP5010 "Universal")'),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('NOT digit-encoded'), findsWidgets);
      });
    });

    testWidgets('no overflow at 320/375/768/1280 in dark + light', (tester) async {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.dark(),
        AppTheme.light(),
      ]) {
        for (final double width in <double>[320, 375, 768, 1280]) {
          await _withViewport(tester, Size(width, 3600), () async {
            await tester.pumpWidget(
              MaterialApp(theme: theme, home: const VendorModelDecodeScreen()),
            );
            await tester.pump();
            expect(tester.takeException(), isNull,
                reason: 'root overflow at ${width}px');
            // UniFi has the suffix-list card + worked example — the widest detail.
            await tester.tap(find.textContaining('Ubiquiti UniFi'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull,
                reason: 'detail overflow at ${width}px');
          });
        }
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
