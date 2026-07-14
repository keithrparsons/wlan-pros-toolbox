// InterfaceInfoService unit tests — the Batch-1 enrichment: SSID/BSSID/interface
// /MAC are re-sourced from the native ConnectedAp subsystem, and the honest
// macOS "needs Location" gate is reported when the name is absent AND Location
// is unauthorized.
//
// The connected-AP read is injected (ConnectedApRead seam) so no platform/native
// channel is touched. The interface lister is stubbed empty; NetworkInfo is the
// real instance (its calls return null off-platform, which the service swallows)
// — these tests assert the IDENTITY merge, not the addressing fields.

import 'dart:io' show NetworkInterface;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap_cache.dart';
import 'package:wlan_pros_toolbox/services/network/interface_info_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';

void main() {
  // Each service gets its OWN empty cache so the warm-path (Batch 8 item 1)
  // never leaks the process-wide singleton's state into these reader-seam tests.
  InterfaceInfoService serviceWith({
    ConnectedAp? ap,
    bool authorized = true,
    ConnectedApCache? cache,
  }) {
    return InterfaceInfoService(
      interfaceLister: () async => const [],
      connectedApReader: () async => (ap: ap, authorized: authorized),
      connectedApCache: cache ?? ConnectedApCache(),
    );
  }

  group('Wi-Fi identity is sourced from ConnectedAp', () {
    test('SSID/BSSID/interface/MAC come from the connected-AP read', () async {
      const ap = ConnectedAp(
        ssid: 'KeithNet',
        bssid: 'a4:83:e7:00:11:22',
        interfaceName: 'en0',
        hardwareAddress: 'a4:83:e7:aa:bb:cc',
      );
      final snap = await serviceWith(ap: ap).read();
      expect(snap.wifi.ssid, 'KeithNet');
      expect(snap.wifi.bssid, 'a4:83:e7:00:11:22');
      expect(snap.wifi.interfaceName, 'en0');
      expect(snap.wifi.hardwareAddress, 'a4:83:e7:aa:bb:cc');
      expect(snap.wifi.locationNeeded, isFalse);
    });

    test('blank ConnectedAp fields normalize to null', () async {
      const ap = ConnectedAp(ssid: '  ', bssid: '', interfaceName: '');
      final snap = await serviceWith(ap: ap).read();
      expect(snap.wifi.ssid, isNull);
      expect(snap.wifi.bssid, isNull);
      expect(snap.wifi.interfaceName, isNull);
    });
  });

  group('macOS Location gate', () {
    test('name absent + Location unauthorized → locationNeeded true', () async {
      // macOS returns an AP with RF data but null SSID/BSSID when Location is off.
      const ap = ConnectedAp(rssiDbm: -50, hardwareAddress: 'a4:83:e7:aa:bb:cc');
      final snap =
          await serviceWith(ap: ap, authorized: false).read();
      expect(snap.wifi.ssid, isNull);
      expect(snap.wifi.locationNeeded, isTrue);
      // The MAC is still read independent of the name gate.
      expect(snap.wifi.hardwareAddress, 'a4:83:e7:aa:bb:cc');
    });

    test('name absent but authorized → not a Location problem', () async {
      const ap = ConnectedAp(rssiDbm: -50);
      final snap = await serviceWith(ap: ap, authorized: true).read();
      expect(snap.wifi.locationNeeded, isFalse);
    });

    test('name present → locationNeeded false regardless', () async {
      const ap = ConnectedAp(ssid: 'KeithNet');
      final snap = await serviceWith(ap: ap, authorized: false).read();
      expect(snap.wifi.locationNeeded, isFalse);
    });

    test('no AP reading at all + unauthorized → locationNeeded true', () async {
      final snap = await serviceWith(ap: null, authorized: false).read();
      expect(snap.wifi.ssid, isNull);
      expect(snap.wifi.locationNeeded, isTrue);
    });
  });

  test('a thrown connected-AP read degrades to empty Wi-Fi identity', () async {
    final svc = InterfaceInfoService(
      interfaceLister: () async => const [],
      connectedApReader: () async => throw StateError('read failed'),
      connectedApCache: ConnectedApCache(),
    );
    final snap = await svc.read();
    expect(snap.wifi.ssid, isNull);
    expect(snap.wifi.bssid, isNull);
    // A failed read is not a Location problem (authorized defaults true on error).
    expect(snap.wifi.locationNeeded, isFalse);
  });

  group('warm shared cache (Batch 8 item 1)', () {
    test('a warm cache supplies the identity without the cold reader firing',
        () async {
      final cache = ConnectedApCache()
        ..update(const ConnectedAp(
          ssid: 'KeithNet',
          bssid: 'a4:83:e7:00:11:22',
        ));
      bool coldReaderCalled = false;
      final svc = InterfaceInfoService(
        interfaceLister: () async => const [],
        connectedApReader: () async {
          coldReaderCalled = true;
          return (ap: null, authorized: true);
        },
        connectedApCache: cache,
      );
      final snap = await svc.read();
      // Identity comes from the cache; the cold (Shortcut-bounce) reader is
      // never consulted — the whole point of item 1.
      expect(snap.wifi.ssid, 'KeithNet');
      expect(snap.wifi.bssid, 'a4:83:e7:00:11:22');
      expect(coldReaderCalled, isFalse);
      expect(snap.wifi.locationNeeded, isFalse);
    });

    test('a cold cache falls through to the per-platform reader', () async {
      bool coldReaderCalled = false;
      final svc = InterfaceInfoService(
        interfaceLister: () async => const [],
        connectedApReader: () async {
          coldReaderCalled = true;
          return (
            ap: const ConnectedAp(ssid: 'FromReader'),
            authorized: true,
          );
        },
        connectedApCache: ConnectedApCache(), // empty
      );
      final snap = await svc.read();
      expect(coldReaderCalled, isTrue);
      expect(snap.wifi.ssid, 'FromReader');
    });

    test('a data-empty cache entry is ignored and the reader still runs',
        () async {
      // An all-null reading never enters the cache (update ignores it), so a
      // cache that only ever saw empties stays cold and the reader fires.
      final cache = ConnectedApCache()..update(const ConnectedAp());
      bool coldReaderCalled = false;
      final svc = InterfaceInfoService(
        interfaceLister: () async => const [],
        connectedApReader: () async {
          coldReaderCalled = true;
          return (ap: const ConnectedAp(ssid: 'FromReader'), authorized: true);
        },
        connectedApCache: cache,
      );
      final snap = await svc.read();
      expect(coldReaderCalled, isTrue);
      expect(snap.wifi.ssid, 'FromReader');
    });

    test('a warm cache stamps cachedAt; the fresh reader path does NOT',
        () async {
      // Warm path: cachedAt is the cache updatedAt, isCacheSourced is true.
      final cache = ConnectedApCache()
        ..update(const ConnectedAp(ssid: 'KeithNet'));
      final warmSvc = InterfaceInfoService(
        interfaceLister: () async => const [],
        connectedApReader: () async => (ap: null, authorized: true),
        connectedApCache: cache,
      );
      final warm = await warmSvc.read();
      expect(warm.wifi.ssid, 'KeithNet');
      expect(warm.wifi.isCacheSourced, isTrue);
      expect(warm.wifi.cachedAt, isNotNull);
      expect(warm.wifi.cachedAt, cache.updatedAt);

      // Fresh read path (cold cache): identity comes from the reader and carries
      // NO as-of stamp — a genuinely live reading is never labelled "as of".
      final freshSvc = InterfaceInfoService(
        interfaceLister: () async => const [],
        connectedApReader: () async =>
            (ap: const ConnectedAp(ssid: 'FromReader'), authorized: true),
        connectedApCache: ConnectedApCache(), // cold
      );
      final fresh = await freshSvc.read();
      expect(fresh.wifi.ssid, 'FromReader');
      expect(fresh.wifi.isCacheSourced, isFalse);
      expect(fresh.wifi.cachedAt, isNull);
    });

    test('a cache reading older than the stale threshold is bypassed', () async {
      // Cache holds the PREVIOUS network; its updatedAt is well past the
      // threshold, so the service must NOT serve it as current — it falls
      // through to the fresh per-platform read instead (truthfulness fix).
      final cache = ConnectedApCache()
        ..update(const ConnectedAp(ssid: 'OldNetwork'));
      final DateTime cachedMoment = cache.updatedAt!;
      bool coldReaderCalled = false;
      final svc = InterfaceInfoService(
        interfaceLister: () async => const [],
        connectedApReader: () async {
          coldReaderCalled = true;
          return (ap: const ConnectedAp(ssid: 'CurrentNetwork'), authorized: true);
        },
        connectedApCache: cache,
        // Pretend it is well past the staleness window since the cache was set.
        now: () => cachedMoment.add(
          InterfaceInfoService.cacheStaleThreshold + const Duration(minutes: 1),
        ),
      );
      final snap = await svc.read();
      expect(coldReaderCalled, isTrue);
      expect(snap.wifi.ssid, 'CurrentNetwork');
      // A fresh read → no as-of stamp.
      expect(snap.wifi.isCacheSourced, isFalse);
      expect(snap.wifi.cachedAt, isNull);
    });

    test('a cache reading within the stale threshold is served with cachedAt',
        () async {
      final cache = ConnectedApCache()
        ..update(const ConnectedAp(ssid: 'StillCurrent'));
      final DateTime cachedMoment = cache.updatedAt!;
      bool coldReaderCalled = false;
      final svc = InterfaceInfoService(
        interfaceLister: () async => const [],
        connectedApReader: () async {
          coldReaderCalled = true;
          return (ap: null, authorized: true);
        },
        connectedApCache: cache,
        // Just inside the window.
        now: () => cachedMoment.add(
          InterfaceInfoService.cacheStaleThreshold - const Duration(seconds: 1),
        ),
      );
      final snap = await svc.read();
      expect(coldReaderCalled, isFalse);
      expect(snap.wifi.ssid, 'StillCurrent');
      expect(snap.wifi.isCacheSourced, isTrue);
      expect(snap.wifi.cachedAt, cachedMoment);
    });
  });

  // BF5-4: the hostname normalizer must never surface "localhost" (the iOS
  // loopback name) — it collapses to null so the UI shows the honest
  // "Not available on this platform" treatment. Real machine hostnames pass
  // through unchanged.
  group('hostname normalization (BF5-4)', () {
    test('loopback-style names collapse to null', () {
      expect(InterfaceInfoService.normalizeHostname('localhost'), isNull);
      expect(InterfaceInfoService.normalizeHostname('LocalHost'), isNull);
      expect(
          InterfaceInfoService.normalizeHostname('localhost.localdomain'),
          isNull);
      expect(InterfaceInfoService.normalizeHostname('ip6-localhost'), isNull);
      expect(InterfaceInfoService.normalizeHostname('loopback'), isNull);
      expect(InterfaceInfoService.normalizeHostname(''), isNull);
      expect(InterfaceInfoService.normalizeHostname('   '), isNull);
      expect(InterfaceInfoService.normalizeHostname(null), isNull);
    });

    test('a real machine hostname passes through (trimmed)', () {
      expect(InterfaceInfoService.normalizeHostname('Keiths-MacBook-Pro'),
          'Keiths-MacBook-Pro');
      expect(InterfaceInfoService.normalizeHostname('  wlan-pi.local  '),
          'wlan-pi.local');
      // "localhostnamed" is a real name that merely starts with the letters —
      // it must NOT be treated as the loopback name.
      expect(InterfaceInfoService.normalizeHostname('localhostnamed'),
          'localhostnamed');
    });
  });

  // ==========================================================================
  // THE CONNECTIVITY GATE (cold-eyes MEDIUM-3, 2026-07-13).
  //
  // The Wi-Fi identity was gated on a 5-MINUTE FRESHNESS TIMER and nothing else.
  // A timer bounds how OLD a remembered reading is; it cannot tell you the link is
  // GONE. So inside that window a cellular-only iPhone rendered the PREVIOUS
  // network's SSID/BSSID as its CURRENT Wi-Fi link — and on the iOS cold path with
  // `cachedAt: null`, which by this file's own rule means it got NO "as of HH:MM"
  // disclosure at all. A remembered reading, presented as a fresh one.
  // ==========================================================================
  group('a cellular-only device is never served a remembered Wi-Fi identity', () {
    test('a WARM cache is suppressed when the probe says not-on-Wi-Fi', () async {
      // The cache is FRESH by the timer (written just now) and would have been
      // served. The probe says there is no Wi-Fi. The probe wins.
      final ConnectedApCache cache = ConnectedApCache();
      cache.update(const ConnectedAp(
        ssid: 'KeithHome',
        bssid: '94:2a:6f:a0:a5:5d',
        rssiDbm: -61,
      ));

      final InterfaceInfoService svc = InterfaceInfoService(
        interfaceLister: () async => const <NetworkInterface>[],
        connectedApCache: cache,
        connectedApReader: () async => (ap: null, authorized: true),
        connectionService: WifiConnectionService(
          networkInfo: _CellularOnlyNetworkInfo(),
          platformOverride: TargetPlatform.iOS,
        ),
      );

      final InterfaceInfoSnapshot snap = await svc.read();
      expect(snap.wifi.notOnWifi, isTrue,
          reason: 'the honest state must be NAMED, not left as a pile of nulls');
      expect(snap.wifi.ssid, isNull,
          reason: 'the previous network\'s SSID must not render as the current '
              'Wi-Fi link');
      expect(snap.wifi.bssid, isNull);
    });

    test('the iOS COLD path is suppressed too (the one with no as-of stamp)',
        () async {
      // The path the reviewer flagged: an EMPTY cache, so the service falls
      // through to the per-platform read — which on iOS is `bridge.readLatest()`,
      // the App Group's last stored payload. It was returned as the CURRENT link
      // with `authorized: true` and `cachedAt: null`: no time bound, no disclosure.
      final InterfaceInfoService svc = InterfaceInfoService(
        interfaceLister: () async => const <NetworkInterface>[],
        connectedApCache: ConnectedApCache(), // cold
        // Stands in for `WiFiDetailsBridge.readLatest()`: it hands back the stale
        // payload forever, and nothing in it knows the link is gone.
        connectedApReader: () async => (
          ap: const ConnectedAp(ssid: 'KeithHome', rssiDbm: -61),
          authorized: true,
        ),
        connectionService: WifiConnectionService(
          networkInfo: _CellularOnlyNetworkInfo(),
          platformOverride: TargetPlatform.iOS,
        ),
      );

      final InterfaceInfoSnapshot snap = await svc.read();
      expect(snap.wifi.ssid, isNull,
          reason: 'the stale App Group payload must not be presented as the '
              'current Wi-Fi link');
      expect(snap.wifi.notOnWifi, isTrue);
    });

    test('an AMBIGUOUS probe changes nothing (no false suppression)', () async {
      // GL-005, and the guard against over-correcting. A wired Mac, a denied read,
      // an un-attributable IPv6: all resolve to `unknown`, and `unknown` must leave
      // the prior behavior EXACTLY as it was. A gate that suppresses on missing
      // data is just the original bug pointing the other way.
      final ConnectedApCache cache = ConnectedApCache();
      cache.update(const ConnectedAp(ssid: 'KeithHome', rssiDbm: -61));

      final InterfaceInfoService svc = InterfaceInfoService(
        interfaceLister: () async => const <NetworkInterface>[],
        connectedApCache: cache,
        connectedApReader: () async => (ap: null, authorized: true),
        connectionService: WifiConnectionService(
          networkInfo: _CellularOnlyNetworkInfo(),
          // macOS: a null Wi-Fi IP is ambiguous, so the probe returns `unknown`.
          platformOverride: TargetPlatform.macOS,
        ),
      );

      final InterfaceInfoSnapshot snap = await svc.read();
      expect(snap.wifi.notOnWifi, isFalse);
      expect(snap.wifi.ssid, 'KeithHome',
          reason: 'an ambiguous probe must NOT blank a real cached reading');
    });
  });
}

/// A cellular-only iPhone: the Wi-Fi interface carries no address of either
/// family. See [WifiConnectionService] and its measured KNOWN LIMITS.
class _CellularOnlyNetworkInfo implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => null;
  @override
  Future<String?> getWifiIPv6() async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
