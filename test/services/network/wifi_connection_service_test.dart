// Unit tests for [WifiConnectionService] — the honest "is this device on Wi-Fi?"
// probe (2026-06-25; hardened 2026-07-13; corrected 2026-07-13 round 3).
//
// Exercises all THREE honest verdicts (onWifi / notOnWifi / unknown) without a
// live network, by injecting a fake [NetworkInfo] and a platform override.
//
// READ THIS BEFORE CHANGING AN EXPECTATION HERE. Round 2 of this file asserted
// TWO things that were false, and the suite then DEFENDED them
// ([[feedback_tests_that_enshrine_the_bug]]):
//
//   1. It fed a GLOBAL IPv6 (`2606:4700:4700::1111`) through the fake and asserted
//      `onWifi`. THE REAL PLUGIN NEVER RETURNS A GLOBAL. `getWifiIPv6` keeps the
//      FIRST AF_INET6 address on an `en*` interface (`if (addr) return;`,
//      FPPNetworkInfoPlusPlugin.m:78-86) and the kernel lists the LINK-LOCAL
//      first. The test passed against a shape the system does not produce — the
//      exact failure mode of [[feedback_tests_that_cannot_fail]].
//
//   2. It asserted "no IPv4 + link-local IPv6 -> notOnWifi" AS CORRECT. That is
//      the IPv6-only-Wi-Fi device being told it has no Wi-Fi. The bug, written
//      down as the spec.
//
// THE MEASUREMENT that settles it (2026-07-13, reproducing
// `enumerateWifiAddresses:AF_INET6` in C against the live BSD stack): on an
// ASSOCIATED en0, `getWifiIPv6()` returns `fe80::10b4:5ba5:5d42:a691%en0`. And
// every `en*` interface with `status: inactive` carries NO address of either
// family — which is what makes the negative verdict sound.
//
// So the fakes below feed the shape the REAL plugin produces (a link-local, or
// nothing at all), and the contract under test is:
//
//   | Device state              | IPv4    | IPv6 on en*    | Verdict     |
//   |---------------------------|---------|----------------|-------------|
//   | Normal Wi-Fi              | present | any            | onWifi      |
//   | Cellular only / Wi-Fi off | null    | NONE           | notOnWifi   |
//   | IPv6-only Wi-Fi, joined    | null    | any (fe80/GUA) | unknown     |
//
// TWO invariants are under test, and they pull in OPPOSITE directions — which is
// the whole difficulty of this probe:
//
//   1. NEVER A FALSE NEGATIVE (GL-005). A null / ambiguous read must never resolve
//      to `notOnWifi`. A wired Mac, a denied read, an absent method channel, an
//      un-attributable IPv6: all `unknown`.
//
//   2. `notOnWifi` MUST STILL BE REACHABLE. If every shape resolved to `unknown`
//      the probe would be inert and Keith's original bug (a stale 29 Mbps Wi-Fi
//      rate on a cellular-only iPhone) would be back. The cellular-only group is
//      the guard on that, and it is why "no address at all" is kept distinct from
//      "some address we cannot attribute".

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_path_probe.dart';

/// In-memory fake of [NetworkInfo]: returns canned Wi-Fi IPv4 / IPv6 addresses
/// (or throws to simulate a denied/unsupported read).
///
/// It models BOTH address families because the real plugin exposes both, and the
/// probe is only honest when it consults both.
class _FakeNetworkInfo implements NetworkInfo {
  _FakeNetworkInfo({
    this.wifiIp,
    this.wifiIpv6,
    this.throws = false,
    this.ipv6Throws = false,
  });

  final String? wifiIp;
  final String? wifiIpv6;
  final bool throws;
  final bool ipv6Throws;

  @override
  Future<String?> getWifiIP() async {
    if (throws) throw Exception('getWifiIP denied');
    return wifiIp;
  }

  @override
  Future<String?> getWifiIPv6() async {
    if (ipv6Throws) throw Exception('getWifiIPv6 unavailable');
    return wifiIpv6;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The address the REAL plugin hands back on an associated interface. Measured,
/// not assumed: see the file header. Every "device is on an IPv6-only SSID" case
/// below uses this, because this is the only IPv6 the app can ever actually see.
const String kMeasuredLinkLocal = 'fe80::10b4:5ba5:5d42:a691%en0';

/// A [WifiPathProbe] with a scripted answer. `null` facts model "the platform did
/// not answer" (the channel is absent off iOS, or the native monitor timed out),
/// which is what sends [WifiConnectionService] to the address-probe FALLBACK.
class _FakePathProbe implements WifiPathProbe {
  const _FakePathProbe(this.facts);
  final WifiPathFacts? facts;
  @override
  Future<WifiPathFacts?> read() async => facts;
}

/// "iOS did not answer." EVERY address-probe test below passes this EXPLICITLY.
///
/// It would work implicitly too — the real `MethodChannelWifiPathProbe` has no
/// channel under `flutter_test` and returns null — but relying on that would make
/// the entire fallback suite depend on an accident of the test harness, and a
/// stray mock handler registered by some other test could silently flip these
/// tests onto the native path without a single assertion changing. State it.
const WifiPathProbe kNativeSilent = _FakePathProbe(null);

WifiConnectionService _service({
  String? wifiIp,
  String? wifiIpv6,
  bool throws = false,
  bool ipv6Throws = false,
  TargetPlatform platform = TargetPlatform.iOS,
  WifiPathProbe pathProbe = kNativeSilent,
}) {
  return WifiConnectionService(
    networkInfo: _FakeNetworkInfo(
      wifiIp: wifiIp,
      wifiIpv6: wifiIpv6,
      throws: throws,
      ipv6Throws: ipv6Throws,
    ),
    platformOverride: platform,
    pathProbe: pathProbe,
  );
}

/// A service whose ADDRESS probe would say "cellular-only" (no address of either
/// family) — so that when the NATIVE path says something different, we can prove
/// which one actually decided the verdict. Without this, a native `notOnWifi` test
/// would pass even if the native path were ignored entirely.
WifiConnectionService _nativeService(WifiPathFacts? facts) => WifiConnectionService(
      networkInfo: _FakeNetworkInfo(wifiIp: null, wifiIpv6: null),
      platformOverride: TargetPlatform.iOS,
      pathProbe: _FakePathProbe(facts),
    );

void main() {
  group('WifiConnectionService.status — onWifi', () {
    test('a non-empty Wi-Fi IP -> onWifi (iOS)', () async {
      final s = _service(wifiIp: '192.168.1.42');
      expect(await s.status(), WifiConnectionStatus.onWifi);
    });

    test('a non-empty Wi-Fi IP -> onWifi (macOS)', () async {
      final s = _service(wifiIp: '10.0.0.5', platform: TargetPlatform.macOS);
      expect(await s.status(), WifiConnectionStatus.onWifi);
    });

    test('a Wi-Fi IPv4 wins even with only a link-local IPv6 alongside it',
        () async {
      // The ordinary dual-stack phone on a normal SSID: a DHCP v4 plus the
      // interface's link-local. The v4 settles it; the v6 is never consulted.
      final s = _service(wifiIp: '192.168.1.42', wifiIpv6: kMeasuredLinkLocal);
      expect(await s.status(), WifiConnectionStatus.onWifi);
    });

    test('a resolved native SSID -> onWifi even with no Wi-Fi IP', () async {
      // A native NEHotspotNetwork SSID can only come from an active Wi-Fi join,
      // so it is a definitive positive even when getWifiIP returns null.
      final s = _service(wifiIp: null);
      expect(
        await s.status(nativeSsid: 'KeithNet'),
        WifiConnectionStatus.onWifi,
      );
    });

    test('a blank native SSID is ignored (falls through to the IP probe)',
        () async {
      // A whitespace-only SSID is not a real join; it must not assert onWifi. No
      // addresses of either family behind it, so the probe lands on notOnWifi.
      final s = _service(wifiIp: null, wifiIpv6: null);
      expect(await s.status(nativeSsid: '   '), WifiConnectionStatus.notOnWifi);
    });
  });

  // ==========================================================================
  // THE IPv6-ONLY WI-FI NETWORK (cold-eyes F3, corrected in round 3).
  //
  // THE DANGEROUS DIRECTION: over-suppression — the probe claiming "not on Wi-Fi"
  // about a device that IS on Wi-Fi. Keith runs CONFERENCE Wi-Fi, and NAT64/DNS64
  // IPv6-only SSIDs are common there.
  //
  // We cannot prove the association (the only IPv6 the plugin will hand us is the
  // link-local, which an idle interface could also carry), so we do not claim it
  // in EITHER direction. `unknown` = "leave prior behavior alone, assert nothing".
  // The residual cost is documented in the service's KNOWN LIMITS: a stale reading
  // may persist on such a network. A stale reading is a smaller lie than telling a
  // connected user they have no Wi-Fi, and it is the one we choose knowingly.
  // ==========================================================================
  group('WifiConnectionService.status — an IPv6-only Wi-Fi device is never '
      'declared off Wi-Fi', () {
    test('iOS, no IPv4, LINK-LOCAL IPv6 (what the plugin really returns) -> '
        'unknown, NOT notOnWifi', () async {
      // THE CENTRAL CASE. An iPhone joined to an IPv6-only SSID: getWifiIP() is
      // AF_INET-only so it is null, and getWifiIPv6() hands back the interface's
      // link-local. Round 2 discarded that as "not routable" and returned
      // notOnWifi — declaring a fully-associated phone disconnected, tearing down
      // its live stream and blanking its link.
      final s = _service(wifiIp: null, wifiIpv6: kMeasuredLinkLocal);
      expect(
        await s.status(),
        WifiConnectionStatus.unknown,
        reason: 'an fe80:: on en0 does not PROVE association, but it absolutely '
            'does not prove its absence either. The only honest answer is '
            'unknown. notOnWifi here is the bug.',
      );
      expect(
        await s.status(),
        isNot(WifiConnectionStatus.notOnWifi),
        reason: 'stated separately because THIS is the regression: a device on '
            'Wi-Fi must never be told it is not on Wi-Fi',
      );
    });

    test('iOS, no IPv4, a bare link-local with no %zone -> unknown', () async {
      final s = _service(wifiIp: null, wifiIpv6: 'fe80::1c9a:b2ff:fe4d:1');
      expect(await s.status(), WifiConnectionStatus.unknown);
    });

    test('iOS, no IPv4, a GLOBAL IPv6 -> unknown (not notOnWifi)', () async {
      // The plugin does not in practice return a global (it keeps the FIRST
      // AF_INET6 on en*, which is the link-local), so this shape is not expected
      // in the field. It is pinned anyway: whatever address turns up, the ONE
      // thing the probe may never do is call this device off-Wi-Fi.
      final s = _service(wifiIp: null, wifiIpv6: '2606:4700:4700::1111');
      expect(await s.status(), WifiConnectionStatus.unknown);
    });

    test('iOS, no IPv4, a ULA IPv6 -> unknown (not notOnWifi)', () async {
      final s = _service(wifiIp: null, wifiIpv6: 'fd12:3456:789a::1');
      expect(await s.status(), WifiConnectionStatus.unknown);
    });

    test('a failed IPv6 read -> unknown, never notOnWifi', () async {
      // If the IPv6 accessor is unavailable we cannot prove "no Wi-Fi address at
      // all", so we must not claim it. The live tools revert to their prior
      // behavior rather than make a false claim (GL-005).
      final s = _service(wifiIp: null, ipv6Throws: true);
      expect(await s.status(), WifiConnectionStatus.unknown);
    });

    test('IPv6 is only consulted on iOS (macOS null IPv4 stays unknown)',
        () async {
      // A wired Mac has no Wi-Fi IPv4 AND no Wi-Fi IPv6, but a null there is
      // ambiguous regardless of family — it must never assert notOnWifi.
      final s = _service(
        wifiIp: null,
        wifiIpv6: null,
        platform: TargetPlatform.macOS,
      );
      expect(await s.status(), WifiConnectionStatus.unknown);
    });
  });

  // ==========================================================================
  // THE CELLULAR-ONLY iPHONE — Keith's actual bug, and the reason the probe
  // exists. If this group ever goes soft, the stale 29 Mbps Wi-Fi rate comes back.
  //
  // The verdict rests on a MEASURED property: an interface with no active link
  // carries no addresses at all. On macOS every `en*` reporting `status: inactive`
  // has neither an `inet` nor an `inet6` line, while the active en0 has both. So
  // "no IPv4 and no IPv6 anywhere on en*" is a real signal, not an inference.
  // ==========================================================================
  group('WifiConnectionService.status — notOnWifi (no address of EITHER family)',
      () {
    test('iOS, no IPv4 and NO IPv6 at all -> notOnWifi (the cellular-only case)',
        () async {
      // THE BUG KEITH REPORTED. Wi-Fi off / cellular only: en0 has no active link,
      // so it carries nothing in either family. This is the ONLY shape that may
      // assert notOnWifi, and it MUST still assert it — an `unknown` here would
      // hand the user back the stale Wi-Fi reading under a live badge.
      final s = _service(wifiIp: null, wifiIpv6: null);
      expect(
        await s.status(),
        WifiConnectionStatus.notOnWifi,
        reason: 'a cellular-only iPhone must be positively identified as off '
            'Wi-Fi, or every live Wi-Fi surface goes back to showing a '
            'remembered reading as if it were current',
      );
    });

    test('empty-string reads on both families -> notOnWifi', () async {
      final s = _service(wifiIp: '', wifiIpv6: '');
      expect(await s.status(), WifiConnectionStatus.notOnWifi);
    });

    test('whitespace-only IPv6 counts as absent -> notOnWifi', () async {
      final s = _service(wifiIp: null, wifiIpv6: '   ');
      expect(await s.status(), WifiConnectionStatus.notOnWifi);
    });

    test('all-zeros placeholder IPv4, no IPv6 -> notOnWifi', () async {
      // Some platforms return 0.0.0.0 for "no address"; treat as no Wi-Fi IP.
      final s = _service(wifiIp: '0.0.0.0', wifiIpv6: null);
      expect(await s.status(), WifiConnectionStatus.notOnWifi);
    });
  });

  group('WifiConnectionService.status — unknown (never a false notOnWifi)', () {
    test('null Wi-Fi IP on macOS -> unknown (wired desktop is ambiguous)',
        () async {
      // A wired-only Mac legitimately has no Wi-Fi IP — must NOT be told to
      // "connect to Wi-Fi" (GL-005).
      final s = _service(wifiIp: null, platform: TargetPlatform.macOS);
      expect(await s.status(), WifiConnectionStatus.unknown);
    });

    test('null Wi-Fi IP on Android -> unknown', () async {
      final s = _service(wifiIp: null, platform: TargetPlatform.android);
      expect(await s.status(), WifiConnectionStatus.unknown);
    });

    test('a thrown IPv4 read resolves to unknown, not notOnWifi (even on iOS)',
        () async {
      // A denied/unsupported read is ambiguous — never a false negative.
      final s = _service(throws: true, platform: TargetPlatform.iOS);
      expect(await s.status(), WifiConnectionStatus.unknown);
    });
  });

  // ==========================================================================
  // THE NATIVE PATH (round 4) — the PRIMARY signal.
  //
  // Rounds 1-3 asked `network_info_plus` for an IP ADDRESS and inferred the link
  // from whether one came back. That is the wrong question. The plugin's filter is
  // `strncmp(name, "en", 2)` — not Wi-Fi-specific, matches a USB tether — and it
  // returns the FIRST address, which is the link-local. Every round-2/3 bug fell
  // out of that.
  //
  // iOS answers the real question: `NWPathMonitor` reports the interface TYPES the
  // path runs over, and `.wifi` is a distinct type from `.cellular` and
  // `.wiredEthernet` (SDK: Network.framework/Headers/interface.h:47-52).
  //
  // EVERY test below pairs the native facts with an address probe that would say
  // "cellular-only". So if the service ever stopped consulting the native path,
  // the onWifi/unknown cases would collapse to notOnWifi and these tests go red.
  // That is deliberate: it proves the native path is the thing deciding.
  // ==========================================================================
  group('WifiConnectionService.status — the native NWPathMonitor path is PRIMARY',
      () {
    test('the default route runs over Wi-Fi -> onWifi', () async {
      // MEASURED SHAPE (2026-07-13, live NWPathMonitor): on an associated Wi-Fi
      // link the default path reports usesInterfaceType(.wifi) = true. A device
      // cannot route over a Wi-Fi interface it is not joined to.
      final s = _nativeService(const WifiPathFacts(
        usesWifi: true,
        wifiSatisfied: true,
        wifiInterfacePresent: true,
      ));
      expect(
        await s.status(),
        WifiConnectionStatus.onWifi,
        reason: 'the address probe here says cellular-only; the NATIVE path must '
            'override it. If this reads notOnWifi, the native signal is being '
            'ignored and we are back to inferring Wi-Fi from addresses.',
      );
    });

    test('usesWifi ALONE is enough -> onWifi (the first disjunct, isolated)',
        () async {
      // EACH POSITIVE IS INDEPENDENTLY SUFFICIENT, and each must be proven so on
      // its own. Every other test here sets `usesWifi` and `wifiSatisfied`
      // TOGETHER, which means either one could be silently ignored and the suite
      // would never notice — mutating `usesWifi` out of the disjunct left this
      // group green until this test existed. A disjunct whose branches are never
      // isolated is a disjunct with only one tested branch.
      final s = _nativeService(const WifiPathFacts(
        usesWifi: true,
        wifiSatisfied: false,
        wifiInterfacePresent: true,
      ));
      expect(
        await s.status(),
        WifiConnectionStatus.onWifi,
        reason: 'the default route running over Wi-Fi is by itself definitive — a '
            'device cannot route over a Wi-Fi interface it is not joined to',
      );
    });

    test('wifiSatisfied ALONE is enough -> onWifi (the second disjunct, '
        'isolated)', () async {
      final s = _nativeService(const WifiPathFacts(
        usesWifi: false,
        wifiSatisfied: true,
        wifiInterfacePresent: true,
      ));
      expect(await s.status(), WifiConnectionStatus.onWifi);
    });

    test('a satisfied Wi-Fi path -> onWifi even when the default route is not '
        'Wi-Fi', () async {
      // The phone is on Wi-Fi AND cellular, and iOS prefers cellular for the
      // default route (a captive portal, or Wi-Fi Assist). There IS a Wi-Fi link;
      // its data is real and must not be blanked.
      final s = _nativeService(const WifiPathFacts(
        usesWifi: false,
        wifiSatisfied: true,
        wifiInterfacePresent: true,
      ));
      expect(await s.status(), WifiConnectionStatus.onWifi);
    });

    test('THE IPv6-ONLY SSID: a Wi-Fi path with no IPv4 anywhere -> onWifi',
        () async {
      // THE CASE THAT BROKE ROUND 2, AND THE ONE KEITH IS LIVE ON RIGHT NOW
      // (a conference NAT64/DNS64 SSID). The address probe is blind here:
      // getWifiIP() is AF_INET-only so it returns null, and getWifiIPv6() hands
      // back a link-local that proves nothing — which is why the FALLBACK can only
      // reach `unknown` on this device (see the IPv6-only group above).
      //
      // The native path is not blind: an IPv6-only Wi-Fi network is still a Wi-Fi
      // PATH, so it reports .wifi and the device is correctly `onWifi`. This is the
      // first time in four rounds this device gets the right answer rather than the
      // least-wrong one.
      final s = _nativeService(const WifiPathFacts(
        usesWifi: true,
        wifiSatisfied: true,
        wifiInterfacePresent: true,
      ));
      expect(
        await s.status(),
        WifiConnectionStatus.onWifi,
        reason: 'an IPv6-only SSID is a Wi-Fi path. The address probe cannot see '
            'it; NWPathMonitor can.',
      );
    });

    test('THE USB TETHER: a wired path with no Wi-Fi interface -> notOnWifi',
        () async {
      // The Xcode debugging configuration, and the shape that makes the address
      // probe lie: `network_info_plus` matches ANY `en*`, so a USB-tethered
      // interface hands back an IPv4 and the old probe concluded "on Wi-Fi".
      //
      // NWPathMonitor types the interface as .wiredEthernet, NOT .wifi, so no Wi-Fi
      // interface appears on the path at all. Note the address probe behind this
      // fake says cellular-only, so this test does not prove the tether's IPv4 is
      // ignored — what it proves is that the NATIVE verdict is taken and that a
      // path with no .wifi interface is correctly notOnWifi.
      final s = _nativeService(const WifiPathFacts(
        usesWifi: false,
        wifiSatisfied: false,
        wifiInterfacePresent: false,
      ));
      expect(await s.status(), WifiConnectionStatus.notOnWifi);
    });

    test('THE CELLULAR-ONLY iPHONE: no Wi-Fi interface on the path -> notOnWifi',
        () async {
      // KEITH'S BUG. MEASURED SHAPE: an interface that cannot carry a path reports
      // status=unsatisfied, usesInterfaceType=false, availableInterfaces=[]. This
      // is the ONLY native shape permitted to assert notOnWifi.
      final s = _nativeService(const WifiPathFacts(
        usesWifi: false,
        wifiSatisfied: false,
        wifiInterfacePresent: false,
      ));
      expect(
        await s.status(),
        WifiConnectionStatus.notOnWifi,
        reason: 'notOnWifi MUST stay reachable. If every native shape resolved to '
            'unknown the probe would be inert and the stale 29 Mbps reading comes '
            'straight back.',
      );
    });

    test('a Wi-Fi interface present but carrying NO usable route -> unknown',
        () async {
      // AMBIGUOUS, AND DELIBERATELY UNRESOLVED. A radio powered but unassociated, a
      // captive portal mid-join, or a phone HOSTING a Personal Hotspot could all
      // present this shape — none was measured on a real device, so the service
      // refuses to guess. `unknown` = the caller keeps its prior behavior.
      //
      // This is the fail-safe that makes the unmeasured shapes tolerable: being
      // wrong here costs a stale reading, never a false "you have no Wi-Fi".
      final s = _nativeService(const WifiPathFacts(
        usesWifi: false,
        wifiSatisfied: false,
        wifiInterfacePresent: true,
      ));
      expect(await s.status(), WifiConnectionStatus.unknown);
      expect(
        await s.status(),
        isNot(WifiConnectionStatus.notOnWifi),
        reason: 'stated separately: an ambiguous native shape must NEVER become a '
            'false "not on Wi-Fi"',
      );
    });

    test('a native SSID still wins over the native path (strongest positive)',
        () async {
      final s = _nativeService(const WifiPathFacts(
        usesWifi: false,
        wifiSatisfied: false,
        wifiInterfacePresent: false,
      ));
      expect(
        await s.status(nativeSsid: 'KeithNet'),
        WifiConnectionStatus.onWifi,
        reason: 'a resolved SSID can only come from an active association',
      );
    });

    test('when the native path does not answer, the ADDRESS FALLBACK decides',
        () async {
      // The seam that keeps every non-iOS platform working exactly as before.
      final s = WifiConnectionService(
        networkInfo: _FakeNetworkInfo(wifiIp: '192.168.1.42'),
        platformOverride: TargetPlatform.iOS,
        pathProbe: kNativeSilent,
      );
      expect(await s.status(), WifiConnectionStatus.onWifi);
    });
  });

  // ==========================================================================
  // THE ALL-ZEROS IPv6 PLACEHOLDER (round-4 cold-eyes LOW).
  //
  // `_readWifiIp` normalized the IPv4 placeholder `0.0.0.0` to "absent" but
  // `_readWifiIpv6` did NOT normalize its IPv6 twin, `::`. An unspecified address
  // is not an address. Reading `::` as "an address is present" would resolve a
  // cellular-only iPhone to `unknown` instead of `notOnWifi` — suppressing the
  // honest state and handing the user back the stale reading. It failed SAFE, which
  // is exactly why it could sit there untested.
  // ==========================================================================
  group('WifiConnectionService — the all-zeros IPv6 placeholder is not an address',
      () {
    test('iOS, no IPv4, IPv6 reads `::` -> notOnWifi', () async {
      final s = _service(wifiIp: null, wifiIpv6: '::');
      expect(
        await s.status(),
        WifiConnectionStatus.notOnWifi,
        reason: '`::` is the IPv6 unspecified address — the exact twin of the '
            '`0.0.0.0` the IPv4 read already normalizes. It is not an address, and '
            'treating it as one suppresses the honest cellular-only verdict.',
      );
    });

    test('the fully expanded `0:0:0:0:0:0:0:0` is also not an address', () async {
      final s = _service(wifiIp: null, wifiIpv6: '0:0:0:0:0:0:0:0');
      expect(await s.status(), WifiConnectionStatus.notOnWifi);
    });

    test('a zoned `::%en0` is also not an address', () async {
      final s = _service(wifiIp: null, wifiIpv6: '::%en0');
      expect(await s.status(), WifiConnectionStatus.notOnWifi);
    });

    test('the LOOPBACK `::1` IS a real address -> unknown, never notOnWifi',
        () async {
      // The guard must normalize only the UNSPECIFIED address, not every address
      // that happens to contain `::`. `::1` has a non-zero group. Over-matching here
      // would be the dangerous direction: it would let a real address be read as
      // "no address" and produce a false notOnWifi.
      final s = _service(wifiIp: null, wifiIpv6: '::1');
      expect(await s.status(), WifiConnectionStatus.unknown);
    });

    test('a link-local is still a real address -> unknown, never notOnWifi',
        () async {
      final s = _service(wifiIp: null, wifiIpv6: kMeasuredLinkLocal);
      expect(await s.status(), WifiConnectionStatus.unknown);
    });
  });
}
