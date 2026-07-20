// Web-unavailable contract (interface parity, Keith 2026-06-09).
//
// THE NEW WEB CONTRACT: the web build no longer HIDES the network/Wi-Fi tools.
// Every tile appears on web exactly as on macOS/Android (interface parity), and
// tools that genuinely can't run in a browser carry an honest web-unavailable
// warning (a "Web" badge on the tile + the existing NetworkUnavailableView on
// the screen). This test pins that contract:
//
//   1. Every id in `kWebUnavailableToolIds` is a real, live tool in the full
//      catalog (no typo'd or stale id silently warning on nothing).
//   2. The tools that DO work in a browser are NOT in the set (GL-005 honesty —
//      don't warn on a tool that works), and ARE present in the catalog.
//   3. `toolUnavailableOnWeb` is false off web (this test host is the VM, where
//      kIsWeb is false), so native iOS/macOS/Android tile behavior is unchanged.
//   4. The two formerly-web-gated network categories now appear in the catalog
//      on the (native) test host — the same list every platform reads — and
//      their socket/native tools are all flagged web-unavailable.
//
// NOTE on platform: `flutter test` runs on the Dart VM, so `kIsWeb` is false
// here. We assert the platform-independent SSOT (the membership set) plus the
// off-web behavior of the gate; the actual on-web rendering is exercised by the
// `flutter build web` gate and the per-screen NetworkUnavailableView tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';

void main() {
  group('web-unavailable contract', () {
    test('the set is non-empty (the network tools DO carry a web warning)', () {
      expect(kWebUnavailableToolIds, isNotEmpty);
    });

    test('every web-unavailable id resolves to a real catalog tool', () {
      // Use the full platform-agnostic catalog: nativeScanOnly tools (nearby-ap-scan)
      // are dropped on this native test host but are still legitimate members of
      // the set (they show with a web warning on web). So check membership
      // against the FULL id universe, not the native-filtered one.
      final Set<String> fullCatalogIds = <String>{
        for (final ToolCategory c in kToolCategories) ...c.tools.map((t) => t.id),
        // nativeScanOnly tools are dropped on the native host; add the known one so
        // the set membership check is honest about what exists in the product.
        'nearby-ap-scan',
      };
      final List<String> orphans = kWebUnavailableToolIds
          .where((String id) => !fullCatalogIds.contains(id))
          .toList();
      expect(
        orphans,
        isEmpty,
        reason: 'web-unavailable ids with no catalog tool: ${orphans.join(", ")}',
      );
    });

    test('tools that work in a browser are NOT flagged web-unavailable', () {
      // GL-005: do not warn on a tool that works. These run identically in a
      // browser (bundled offline data, pure math, or the browser Geolocation
      // API) and must behave normally on web.
      const List<String> webSafe = <String>[
        'mac-oui-lookup', // bundled offline IEEE OUI table
        'ipv4-subnet', // pure subnet math
        'ipv6-subnet', // pure subnet math
        'my-current-location', // browser Geolocation API via geolocator
      ];
      for (final String id in webSafe) {
        expect(
          kWebUnavailableToolIds.contains(id),
          isFalse,
          reason: '$id works in a browser and must not carry a web warning',
        );
      }
    });

    test('every Calculator and Quick Reference tool works on web (no warning)',
        () {
      // Calculators (pure math) and Quick Reference (bundled tables) run
      // identically in a browser; none of them may be flagged web-unavailable.
      const Set<String> webSafeCategoryIds = <String>{
        'rf-calculators',
        'quick-reference',
        'educational-resources',
      };
      for (final ToolCategory c in kToolCategories) {
        if (!webSafeCategoryIds.contains(c.id)) continue;
        for (final ToolEntry t in c.tools) {
          expect(
            kWebUnavailableToolIds.contains(t.id),
            isFalse,
            reason: '${c.id}/${t.id} is web-safe and must not be web-flagged',
          );
        }
      }
    });

    test('toolUnavailableOnWeb is false off web (native behavior unchanged)',
        () {
      // This test host is the Dart VM (kIsWeb == false), so the gate must
      // short-circuit to false for EVERY id — including the network tools and
      // the Android-only scan. This is the guard that keeps native iOS/macOS/
      // Android tile behavior byte-for-byte unchanged.
      for (final String id in kWebUnavailableToolIds) {
        expect(
          toolUnavailableOnWeb(id),
          isFalse,
          reason: 'off web, $id must not be flagged (native unchanged)',
        );
      }
      expect(toolUnavailableOnWeb('fspl'), isFalse);
      expect(toolUnavailableOnWeb('not-a-real-id'), isFalse);
    });

    test('the formerly-web-gated network categories are in the catalog', () {
      // The old kWebGatedCategoryIds removed these on web. They now appear in
      // the single catalog every platform reads.
      final Set<String> categoryIds =
          kToolCategories.map((ToolCategory c) => c.id).toSet();
      expect(categoryIds.contains('test-network'), isTrue);
      expect(categoryIds.contains('networking'), isTrue);
    });

    test('every Test Network tool is flagged web-unavailable', () {
      final ToolCategory testNetwork = kToolCategories
          .firstWhere((ToolCategory c) => c.id == 'test-network');
      for (final ToolEntry t in testNetwork.tools) {
        expect(
          kWebUnavailableToolIds.contains(t.id),
          isTrue,
          reason: 'test-network/${t.id} needs a web warning (live diagnostics)',
        );
      }
    });
  });
}
