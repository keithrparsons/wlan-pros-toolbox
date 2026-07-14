// Unit tests for [WifiConnectionService] — the honest "is this device on Wi-Fi?"
// probe (2026-06-25, hardened 2026-07-13).
//
// Exercises all THREE honest verdicts (onWifi / notOnWifi / unknown) without a
// live network, by injecting a fake [NetworkInfo] and a platform override.
//
// TWO invariants are under test, and they pull in OPPOSITE directions — which is
// the whole difficulty of this probe:
//
//   1. NEVER A FALSE NEGATIVE (GL-005). A null / ambiguous read must never resolve
//      to `notOnWifi`. A wired Mac, a denied read, an absent method channel: all
//      `unknown`.
//
//   2. NEVER A FALSE `notOnWifi` FOR A DEVICE THAT IS ACTUALLY ON WI-FI. This is
//      the one the first round got wrong. `getWifiIP()` enumerates AF_INET ONLY
//      (network_info_plus-6.1.4, FPPNetworkInfoPlusPlugin.m:68), so an iPhone on an
//      IPv6-ONLY Wi-Fi network — NAT64/DNS64, common on carrier and CONFERENCE
//      SSIDs, and Keith runs conference Wi-Fi — returns a CLEAN NULL while fully
//      associated. Asserting `notOnWifi` from that null declared the device NOT ON
//      WI-FI WHILE ON WI-FI: it nulled the details, tore down the live stream,
//      cleared the App Group loop flag, and rewrote the verdict. The IPv6 group
//      below is the guard on that.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';

/// In-memory fake of [NetworkInfo]: returns canned Wi-Fi IPv4 / IPv6 addresses
/// (or throws to simulate a denied/unsupported read).
///
/// It models BOTH address families because the real plugin exposes both, and the
/// probe is only honest when it consults both. A fake that answered IPv4 alone is
/// what let the IPv6 hole through the first time.
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
      // A whitespace-only SSID is not a real join; it must not assert onWifi.
      final s = _service(wifiIp: null, platform: TargetPlatform.iOS);
      expect(await s.status(nativeSsid: '   '), WifiConnectionStatus.notOnWifi);
    });
  });

  // ==========================================================================
  // THE IPv6-ONLY WI-FI NETWORK (cold-eyes F3). The dangerous one: this is
  // OVER-suppression — the probe claiming "not on Wi-Fi" about a device that is
  // on Wi-Fi. Pre-fix these were all `notOnWifi`.
  // ==========================================================================
  group('WifiConnectionService.status — IPv6-only Wi-Fi is still Wi-Fi', () {
    test('iOS, no IPv4 but a GLOBAL IPv6 on the Wi-Fi interface -> onWifi',
        () async {
      // The conference / carrier NAT64 case. getWifiIP() is AF_INET-only, so it
      // returns null here while the phone is fully associated and working.
      final s = _service(
        wifiIp: null,
        wifiIpv6: '2606:4700:4700::1111',
      );
      expect(
        await s.status(),
        WifiConnectionStatus.onWifi,
        reason: 'an iPhone on an IPv6-only SSID is ON WI-FI; declaring it '
            'notOnWifi blanks a live link and tears down a live stream',
      );
    });

    test('iOS, no IPv4 but a ULA IPv6 -> onWifi', () async {
      // fc00::/7 — a real, provisioned address handed out by the network.
      final s = _service(wifiIp: null, wifiIpv6: 'fd12:3456:789a::1');
      expect(await s.status(), WifiConnectionStatus.onWifi);
    });

    test('iOS, no IPv4 and only a LINK-LOCAL IPv6 -> notOnWifi', () async {
      // fe80::/10 is self-assigned and does not prove an association with a
      // network. Counting it as a positive would make `notOnWifi` unreachable and
      // re-open the stale-reading bug. Documented in the KNOWN LIMITS of the
      // service: a Wi-Fi network handing out neither IPv4 nor a routable IPv6 is
      // read as no-Wi-Fi (and offers no working path anyway).
      final s = _service(wifiIp: null, wifiIpv6: 'fe80::1c9a:b2ff:fe4d:1');
      expect(await s.status(), WifiConnectionStatus.notOnWifi);
    });

    test('a link-local IPv6 with a %zone suffix is still link-local', () async {
      final s = _service(wifiIp: null, wifiIpv6: 'fe80::1c9a:b2ff:fe4d:1%en0');
      expect(await s.status(), WifiConnectionStatus.notOnWifi);
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

    test('the routable-IPv6 classifier', () {
      // Positives: a real, provisioned address on the Wi-Fi interface.
      expect(WifiConnectionService.isRoutableIpv6('2001:db8::1'), isTrue);
      expect(WifiConnectionService.isRoutableIpv6('fd00::1'), isTrue);
      expect(WifiConnectionService.isRoutableIpv6('FE00::1'), isTrue);
      // Negatives: link-local (fe80..febf), loopback, unspecified, empty.
      expect(WifiConnectionService.isRoutableIpv6('fe80::1'), isFalse);
      expect(WifiConnectionService.isRoutableIpv6('FEBF::1'), isFalse);
      expect(WifiConnectionService.isRoutableIpv6('fe90::1'), isFalse);
      expect(WifiConnectionService.isRoutableIpv6('::1'), isFalse);
      expect(WifiConnectionService.isRoutableIpv6('::'), isFalse);
      expect(WifiConnectionService.isRoutableIpv6('   '), isFalse);
    });
  });

  group('WifiConnectionService.status — notOnWifi (positive signal only)', () {
    test('no IPv4 AND no IPv6 on iOS -> notOnWifi (the cellular-only case)',
        () async {
      // BOTH families read clean and empty. This — and only this — is the honest
      // cellular-only signal.
      final s = _service(wifiIp: null, wifiIpv6: null);
      expect(await s.status(), WifiConnectionStatus.notOnWifi);
    });

    test('empty Wi-Fi IP on iOS (no IPv6 either) -> notOnWifi', () async {
      final s = _service(wifiIp: '', wifiIpv6: '');
      expect(await s.status(), WifiConnectionStatus.notOnWifi);
    });

    test('all-zeros placeholder IP on iOS (no IPv6 either) -> notOnWifi',
        () async {
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

    test('a thrown read resolves to unknown, not notOnWifi (even on iOS)',
        () async {
      // A denied/unsupported read is ambiguous — never a false negative.
      final s = _service(throws: true, platform: TargetPlatform.iOS);
      expect(await s.status(), WifiConnectionStatus.unknown);
    });
  });
}
