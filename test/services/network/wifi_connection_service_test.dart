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

WifiConnectionService _service({
  String? wifiIp,
  String? wifiIpv6,
  bool throws = false,
  bool ipv6Throws = false,
  TargetPlatform platform = TargetPlatform.iOS,
}) {
  return WifiConnectionService(
    networkInfo: _FakeNetworkInfo(
      wifiIp: wifiIp,
      wifiIpv6: wifiIpv6,
      throws: throws,
      ipv6Throws: ipv6Throws,
    ),
    platformOverride: platform,
  );
}

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
}
