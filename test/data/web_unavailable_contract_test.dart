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
import 'package:wlan_pros_toolbox/services/network/join_backend_selector.dart';

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
        for (final ToolCategory c in kToolCategories)
          ...c.tools.map((t) => t.id),
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
        reason:
            'web-unavailable ids with no catalog tool: ${orphans.join(", ")}',
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

    test(
      'every Calculator and Quick Reference tool works on web (no warning)',
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
      },
    );

    test('toolUnavailableOnWeb is false off web (native behavior unchanged)', () {
      // This test host is the Dart VM (kIsWeb == false), so the gate must
      // short-circuit to false for EVERY id — including the network tools and
      // the Android-only scan. This is the guard that keeps native iOS/macOS/
      // Android tile behavior byte-for-byte unchanged.
      for (final String id in kWebUnavailableToolIds) {
        // PI-ONLY TOOLS ARE THE ONE EXCEPTION, ADDED 2026-09-04, AND THE
        // EXCEPTION IS THE POINT rather than a loosening of this guard.
        //
        // This assertion used to cover EVERY id, on the reasoning that the set
        // holds tools a BROWSER cannot run, so off web there is nothing to warn
        // about. That held while every member was a native-capable tool.
        // `join-network` is the inverse shape: it runs ONLY in a browser served
        // BY a Pi, and on macOS it was therefore offered with no badge,
        // described as associating "this WLAN Pi's own radio" to a man holding
        // a MacBook, and could not work at all (Keith found it by using it).
        //
        // So the contract is now NARROWER, not weaker: off web the gate is
        // false for everything EXCEPT tools that exist only on a Pi. The
        // positive half is asserted in the next test, so neither half can be
        // quietly dropped.
        if (kPiOnlyToolIds.contains(id)) continue;
        expect(
          toolUnavailableOnWeb(id),
          isFalse,
          reason: 'off web, $id must not be flagged (native unchanged)',
        );
      }
      expect(toolUnavailableOnWeb('fspl'), isFalse);
      expect(toolUnavailableOnWeb('not-a-real-id'), isFalse);
    });

    test('a Pi-only tool IS flagged off a Pi, unless the device serves it', () {
      // The other half of the contract above. This test host is the Dart VM
      // with no Pi backend, which is exactly the macOS case Keith hit.
      //
      // AMENDED 2026-09-17, and the amendment is narrow on purpose. Native
      // join landed for macOS and Windows, so join-network is no longer
      // "only a Pi can run this" on those two. Every other Pi-only tool is
      // unchanged, and join-network is still flagged on iOS, Android and web.
      // The rule is not "Pi-only tools are always flagged"; it is "a tool is
      // flagged unless something here can actually run it".
      expect(
        kPiOnlyToolIds,
        isNotEmpty,
        reason: 'the set exists to name tools that only a Pi can run',
      );
      for (final String id in kPiOnlyToolIds) {
        if (id == 'join-network' && deviceCanJoinNatively) {
          expect(
            toolUnavailableOnWeb(id),
            isFalse,
            reason:
                'this host joins with its own radio, so offering the tool '
                'is honest rather than a promise it cannot keep',
          );
          continue;
        }
        expect(
          toolUnavailableOnWeb(id),
          isTrue,
          reason:
              '$id runs only on a WLAN Pi and must not be offered as '
              'though it works here',
        );
      }
    });

    test('every Pi-only id is a real, live catalog tool', () {
      // Same guard the web-unavailable set gets: a typo'd id would silently
      // gate nothing, and the tool would go on being offered where it cannot
      // run -- the exact defect this set was added to fix.
      final Set<String> all = <String>{
        for (final ToolCategory c in kToolCategories)
          for (final ToolEntry t in c.tools) t.id,
      };
      for (final String id in kPiOnlyToolIds) {
        expect(
          all,
          contains(id),
          reason: '$id is in kPiOnlyToolIds but not in the catalog',
        );
      }
    });

    test('no Pi-only tool describes hardware the reader may not have', () {
      // The tile copy said "this WLAN Pi's own radio" on a Mac. The gate now
      // stops the tile appearing there, but copy that only makes sense when a
      // gate holds is one edit away from being wrong again.
      for (final ToolCategory c in kToolCategories) {
        for (final ToolEntry t in c.tools) {
          if (!kPiOnlyToolIds.contains(t.id)) continue;
          expect(
            t.description.contains("this WLAN Pi's"),
            isFalse,
            reason:
                '${t.id}: do not say "this WLAN Pi" to a reader who may be '
                'on a Mac; name the hardware without assuming they hold it',
          );
        }
      }
    });

    test('the formerly-web-gated network categories are in the catalog', () {
      // The old kWebGatedCategoryIds removed these on web. They now appear in
      // the single catalog every platform reads.
      final Set<String> categoryIds = kToolCategories
          .map((ToolCategory c) => c.id)
          .toSet();
      expect(categoryIds.contains('test-network'), isTrue);
      expect(categoryIds.contains('networking'), isTrue);
    });

    test('every Test Network tool is flagged web-unavailable', () {
      final ToolCategory testNetwork = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'test-network',
      );
      for (final ToolEntry t in testNetwork.tools) {
        expect(
          kWebUnavailableToolIds.contains(t.id),
          isTrue,
          reason: 'test-network/${t.id} needs a web warning (live diagnostics)',
        );
      }
    });

    // REGRESSION GUARD (2026-08-09). `ntp-time` shipped with its screen
    // returning NetworkUnavailableView on web (ntp_screen.dart `_body()`, gated
    // on `NetworkSupport.ntpSupported => !kIsWeb`) while its tile carried no web
    // badge, because nothing forced a decision when a tool was added to the
    // Networking category. The Test Network category above has had a
    // whole-category guard since 2026-06-09; Networking had none, so a new
    // socket tool could be added and silently default to "works on web".
    //
    // The rule this pins: a Networking tool is web-unavailable BY DEFAULT.
    // Anything that genuinely runs in a browser must be added to the explicit
    // allow-list below, which makes the claim visible and reviewable rather
    // than inferred from an omission.
    test('every Networking tool is flagged web-unavailable or explicitly '
        'allow-listed as web-safe', () {
      // Tools in the Networking category that genuinely run in a browser:
      // bundled offline data, pure math, or a browser-native API. Each one is
      // a deliberate claim that the tool works on web (GL-005 — never warn on
      // a tool that works).
      const Set<String> webSafeNetworkingIds = <String>{
        'mac-oui-lookup', // bundled offline IEEE OUI table, no I/O
        'ipv4-subnet', // pure subnet math, no I/O
        'ipv6-subnet', // pure subnet math, no I/O
        'subnet-planner', // pure subnet math, no I/O
        'my-current-location', // browser Geolocation API via geolocator
      };

      final ToolCategory networking = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'networking',
      );
      final List<String> undecided = networking.tools
          .map((ToolEntry t) => t.id)
          .where(
            (String id) =>
                !kWebUnavailableToolIds.contains(id) &&
                !webSafeNetworkingIds.contains(id),
          )
          .toList();

      expect(
        undecided,
        isEmpty,
        reason:
            'Networking tools with no web verdict: ${undecided.join(", ")}. '
            'Add each to kWebUnavailableToolIds (its screen refuses on web) or '
            'to webSafeNetworkingIds (it genuinely runs in a browser).',
      );
    });

    test('ntp-time carries a web warning (its screen refuses on web)', () {
      // Pins the specific defect: SNTP needs an outbound UDP/123 datagram
      // socket, which no browser can open, so ntp_screen.dart renders
      // NetworkUnavailableView. The tile must say so too.
      expect(kWebUnavailableToolIds.contains('ntp-time'), isTrue);
    });
  });
}
