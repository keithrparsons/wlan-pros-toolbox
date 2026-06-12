// Tests for the two integration-batch Tier-1 reference screens (2026-06-12):
//   rf-bands  — RF Bands at a Glance frequency map
//   wifi-halow — Wi-Fi HaLow (IEEE 802.11ah) sub-GHz reference
//
// Three layers, mirroring tier1_references_pass2b_test.dart:
//   1. Data fidelity (GL-005): the typed const datasets carry the load-bearing
//      facts and caveats from the staged DATA (the 86.7 Mbps single-stream max
//      and NOT 433.3 as fact; 8191 devices/AP; region-locked bands; the Wi-Fi
//      rows flagged in the RF map), plus the no-em-dash rule across the prose.
//   2. Registration: each new tool has a catalog tile in Wi-Fi & RF, a
//      registered route builder, and a keyword set. (Help-count guard lives in
//      tool_help_loader_test: 138 -> 140.)
//   3. Widget render: each read-only screen renders its title across
//      phone/tablet/desktop widths in BOTH dark and light themes with no
//      RenderFlex overflow; the embedded-PNG plate is omitted when the asset is
//      not bundled (graceful degradation) and shown when it is.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/reference_images.dart';
import 'package:wlan_pros_toolbox/data/rf_bands_data.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/wifi_halow_data.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/rf_bands_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/wifi_halow_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/dark_raster_diagram_card.dart';

void main() {
  group('data fidelity (GL-005)', () {
    test('RF Bands: five neighborhoods low->high, Wi-Fi rows flagged', () {
      expect(kRfBandGroups.length, 5);
      // Every group has rows and a takeaway.
      for (final RfBandGroup g in kRfBandGroups) {
        expect(g.rows, isNotEmpty);
        expect(g.takeaway, isNotEmpty);
      }
      // The Wi-Fi home turf is flagged so the screen can accent it.
      expect(
        kRfBandGroups.expand((RfBandGroup g) => g.rows).any(
          (RfBandRow r) => r.isWiFi,
        ),
        isTrue,
      );
      // The headline region-variance flags include the 6 GHz US/EU split.
      expect(
        kRfRegionFlags.any((RfRegionFlag f) => f.topic.contains('6 GHz')),
        isTrue,
      );
    });

    test('Wi-Fi HaLow: 86.7 Mbps single-stream max, NOT 433 as fact', () {
      // MCS 9 / 16 MHz / SGI carries 86.7 Mbps.
      final HalowMcs mcs9 =
          kHalowMcs.firstWhere((HalowMcs m) => m.mcs == 9);
      expect(mcs9.w16.endsWith('86.7'), isTrue);
      // The headline number is 86.7 Mbps, and the contested 433.3 is never
      // printed as a fact (only named in the honesty note as Wikipedia's claim).
      final HalowHeadline rate = kHalowHeadlines.firstWhere(
        (HalowHeadline h) => h.value == '86.7 Mbps',
      );
      expect(rate.value, '86.7 Mbps');
      expect(kHalowRateHonesty.contains('433.3'), isTrue,
          reason: 'the note names the contested figure to refute it');
      // No headline VALUE is 433.3.
      expect(
        kHalowHeadlines.any((HalowHeadline h) => h.value.contains('433')),
        isFalse,
      );
      // Capacity 8191 devices/AP.
      expect(
        kHalowHeadlines.any((HalowHeadline h) => h.value.contains('8,191')),
        isTrue,
      );
      // The region-lock caveat is carried.
      expect(kHalowRegionLock.toLowerCase().contains('region'), isTrue);
      expect(
        kHalowNotMainstreamBands.contains('does NOT use 2.4, 5, or 6 GHz'),
        isTrue,
      );
      // The MCS table has all 11 rows (MCS 0-10).
      expect(kHalowMcs.length, 11);
    });

    test('no em dash in any rendered prose across the datasets', () {
      final List<String> prose = <String>[
        kRfBandsNote,
        for (final RfBandGroup g in kRfBandGroups) ...<String>[
          g.subtitle,
          g.takeaway,
          for (final RfBandRow r in g.rows) ...<String>[r.use, r.note],
        ],
        for (final RfRegionFlag f in kRfRegionFlags) f.detail,
        kHalowOneLiner,
        kHalowRegionLock,
        kHalowNotMainstreamBands,
        kHalowBandsNote,
        kHalowChannelsNote,
        kHalowRateHonesty,
        kHalowPhyNote,
        kHalowVersusVerdict,
        kHalowMaturityNote,
        for (final HalowHeadline h in kHalowHeadlines) h.note,
        for (final String u in kHalowUseCases) u,
      ];
      for (final String s in prose) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
      }
    });
  });

  group('registration (catalog + router + keywords)', () {
    const Map<String, String> subgroupById = <String, String>{
      'rf-bands': 'Wi-Fi & RF',
      'wifi-halow': 'Wi-Fi & RF',
    };

    test('each new tool is a live Quick Reference tile in Wi-Fi & RF', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      subgroupById.forEach((String id, String subgroup) {
        final ToolEntry t = qr.tools.firstWhere((ToolEntry e) => e.id == id);
        expect(t.isLive, isTrue, reason: '$id must be live');
        expect(t.routeName, '/tools/$id', reason: '$id route convention');
        expect(t.subgroup, subgroup, reason: '$id subgroup');
      });
    });

    test('each new route resolves to a registered builder', () {
      for (final String id in subgroupById.keys) {
        expect(
          AppRouter.routes.containsKey('/tools/$id'),
          isTrue,
          reason: 'no registered route for $id',
        );
      }
    });

    test('each new tool carries a keyword set', () {
      for (final String id in subgroupById.keys) {
        expect(kToolKeywords.containsKey(id), isTrue, reason: '$id keywords');
        expect(kToolKeywords[id]!, isNotEmpty);
      }
    });
  });

  group('widget render (dark + light, no overflow)', () {
    setUp(() {
      // No plate bundled by default -> the image card is omitted and the page
      // must still render fully as native text.
      ReferenceImages.debugSetBundled(const <String>{});
    });
    tearDown(ReferenceImages.debugReset);

    final List<(String, Widget)> screens = <(String, Widget)>[
      ('RF Bands', const RfBandsScreen()),
      ('Wi-Fi HaLow', const WifiHalowScreen()),
    ];

    for (final (String title, Widget screen) in screens) {
      testWidgets('$title renders its title in dark + light', (tester) async {
        for (final ThemeData theme in <ThemeData>[
          AppTheme.dark(),
          AppTheme.light(),
        ]) {
          await _withViewport(tester, const Size(375, 5200), () async {
            await tester.pumpWidget(MaterialApp(theme: theme, home: screen));
            await tester.pump();
            expect(find.text(title), findsWidgets);
            expect(find.byType(TextField), findsNothing);
            // No plate bundled -> no embedded image card.
            expect(find.byType(DarkRasterDiagramCard), findsNothing);
          });
        }
      });

      testWidgets('$title: no overflow at 320/375/768/1280 widths', (
        tester,
      ) async {
        for (final double width in <double>[320, 375, 768, 1280]) {
          await _withViewport(tester, Size(width, 5200), () async {
            await tester.pumpWidget(
              MaterialApp(theme: AppTheme.dark(), home: screen),
            );
            await tester.pump();
            expect(
              tester.takeException(),
              isNull,
              reason: '$title overflow at ${width}px',
            );
          });
        }
      });
    }

    testWidgets('embedded plate appears for each screen when bundled', (
      tester,
    ) async {
      ReferenceImages.debugSetBundled(<String>{
        ReferenceImages.pathFor('rf-bands'),
        ReferenceImages.pathFor('wifi-halow'),
      });
      addTearDown(ReferenceImages.debugReset);

      final List<Widget> withPlate = <Widget>[
        const RfBandsScreen(),
        const WifiHalowScreen(),
      ];
      for (final Widget screen in withPlate) {
        await _withViewport(tester, const Size(375, 5200), () async {
          await tester.pumpWidget(
            MaterialApp(theme: AppTheme.dark(), home: screen),
          );
          await tester.pump();
          expect(find.byType(DarkRasterDiagramCard), findsOneWidget);
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
