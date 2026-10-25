// MacWifiInfoAdapter — AP-name enrichment (2026-07-17, feature/ap-name-decoder).
//
// The macOS adapter optionally reads the connected AP's beacon IE bytes (a
// separate CoreWLAN scan via the `connectedApIeBlob` channel) and decodes the
// vendor-advertised AP name onto the ConnectedAp. These tests drive the adapter
// with a fake WifiInfoService (no platform channel) and prove:
//   - a real UniFi Tag 221 name blob decodes and attaches when authorized;
//   - enrichment is OFF by default and when Location is unauthorized (honest
//     null, no fabricated name);
//   - a stale-scan BSSID mismatch, an empty blob, or a channel failure all yield
//     honest null and never throw into the RF read.
//
// The same beacon scan also settles security when macOS says "open": CoreWLAN
// reports Enhanced Open (OWE) as `.none` (seen 25 OCT 2026 on Keith Guest), so
// the adapter upgrades to OWE only when the connected BSS's own beacon carries
// AKM 00-0F-AC:18. Those tests use real beacon bytes from Keith's AP.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ap_name_cache.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_security.dart';

import '../../fixtures/keith_guest_ch108_beacons.dart';

/// One non-extended IE element: [id][len][...data].
List<int> _ie(int id, List<int> data) => <int>[id, data.length, ...data];

/// A synthetic UniFi (Ubiquiti) Tag 221 AP-name IE: OUI 00:15:6D, type 0x01,
/// ASCII name to end.
List<int> _unifiNameBlob(String name) =>
    _ie(221, <int>[0x00, 0x15, 0x6D, 0x01, ...name.codeUnits]);

/// Builds a getWifiInfo payload with the given bssid and Location grant.
Map<String, Object?> _wifiInfoMap({
  required String? bssid,
  required bool locationAuthorized,
  String? securityToken,
}) =>
    <String, Object?>{
      'ssid': 'KeithNet',
      'bssid': bssid,
      'poweredOn': true,
      'locationAuthorized': locationAuthorized,
      'securityToken': securityToken,
    };

/// A counting fake WifiInfoService (platform macos). [ieBlobFor] returns the IE
/// blob payload; [scanCount] records how many times the scan channel was hit, so
/// the cache/throttle can be asserted.
class _CountingService {
  _CountingService({required this.wifiInfo, required this.ieBlob});

  Map<dynamic, dynamic>? wifiInfo;
  Map<dynamic, dynamic>? ieBlob;
  int scanCount = 0;

  WifiInfoService get service => WifiInfoService(
        platformOverride: 'macos',
        invoke: (String method, [dynamic args]) async {
          switch (method) {
            case 'getWifiInfo':
              return wifiInfo;
            case 'connectedApIeBlob':
              scanCount++;
              return ieBlob;
            default:
              return null;
          }
        },
      );
}

Map<String, Object?> _blob(String? bssid, List<int>? ieBytes) => <String, Object?>{
      'ieBytes': ieBytes == null ? null : Uint8List.fromList(ieBytes),
      'bssid': bssid,
      'locationAuthorized': true,
    };

void main() {
  // The name cache is now the app-wide singleton, so reset it between cases to
  // keep each test's adapter cold (these tests reuse the same BSSID).
  setUp(() => ApNameCache.instance.clear());

  group('MacWifiInfoAdapter AP-name enrichment (fire-and-forget + cache)', () {
    test('first fetch is honest-null (does not wait on the scan); the name '
        'fills in and is then served FROM CACHE with no further scan', () async {
      const String bssid = 'aa:bb:cc:dd:ee:ff';
      final _CountingService fake = _CountingService(
        wifiInfo: _wifiInfoMap(bssid: bssid, locationAuthorized: true),
        ieBlob: _blob(bssid, _unifiNameBlob('UAP-Lobby')),
      );
      final MacWifiInfoAdapter adapter =
          MacWifiInfoAdapter(service: fake.service, enrichApName: true);

      // Fire-and-forget: fetch returns immediately with honest-null, having only
      // SCHEDULED the scan.
      final ConnectedAp first = await adapter.fetch();
      expect(first.apName, isNull);
      expect(first.bssid, bssid);

      // Let the background scan resolve and cache the decoded name.
      await adapter.pendingApNameScan;
      expect(fake.scanCount, 1);

      // The next fetch serves the cached name with NO additional scan.
      final ConnectedAp second = await adapter.fetch();
      expect(second.apName, 'UAP-Lobby');
      await adapter.pendingApNameScan; // nothing scheduled
      expect(fake.scanCount, 1);

      // And a third fetch is still cache-only.
      final ConnectedAp third = await adapter.fetch();
      expect(third.apName, 'UAP-Lobby');
      expect(fake.scanCount, 1);
    });

    test('enrichment OFF by default never scans and leaves apName null',
        () async {
      const String bssid = 'aa:bb:cc:dd:ee:ff';
      final _CountingService fake = _CountingService(
        wifiInfo: _wifiInfoMap(bssid: bssid, locationAuthorized: true),
        ieBlob: _blob(bssid, _unifiNameBlob('UAP-Lobby')),
      );
      final MacWifiInfoAdapter adapter = MacWifiInfoAdapter(service: fake.service);

      final ConnectedAp ap = await adapter.fetch();
      await adapter.pendingApNameScan;
      expect(ap.apName, isNull);
      expect(fake.scanCount, 0);
    });

    test('unauthorized Location never scans (IE bytes would be nil anyway)',
        () async {
      final _CountingService fake = _CountingService(
        wifiInfo: _wifiInfoMap(bssid: null, locationAuthorized: false),
        ieBlob: _blob('aa:bb:cc:dd:ee:ff', _unifiNameBlob('UAP-Lobby')),
      );
      final MacWifiInfoAdapter adapter =
          MacWifiInfoAdapter(service: fake.service, enrichApName: true);

      final ConnectedAp ap = await adapter.fetch();
      await adapter.pendingApNameScan;
      expect(ap.apName, isNull);
      expect(fake.scanCount, 0);
    });

    test('a stale-scan BSSID mismatch caches nothing (never a wrong name)',
        () async {
      const String bssid = 'aa:bb:cc:dd:ee:ff';
      final _CountingService fake = _CountingService(
        wifiInfo: _wifiInfoMap(bssid: bssid, locationAuthorized: true),
        // The scan matched a DIFFERENT BSS than the connected one.
        ieBlob: _blob('11:22:33:44:55:66', _unifiNameBlob('SomeOtherAP')),
      );
      final MacWifiInfoAdapter adapter =
          MacWifiInfoAdapter(service: fake.service, enrichApName: true);

      await adapter.fetch();
      await adapter.pendingApNameScan;
      final ConnectedAp second = await adapter.fetch();
      expect(second.apName, isNull);
    });

    test('an unnamed BSSID is not re-scanned until the floor elapses (throttle)',
        () async {
      const String bssid = 'aa:bb:cc:dd:ee:ff';
      DateTime clock = DateTime(2026, 7, 17, 12, 0, 0);
      final _CountingService fake = _CountingService(
        wifiInfo: _wifiInfoMap(bssid: bssid, locationAuthorized: true),
        ieBlob: _blob(bssid, null), // scan returns no IE data → no name cached
      );
      final MacWifiInfoAdapter adapter = MacWifiInfoAdapter(
        service: fake.service,
        enrichApName: true,
        apNameRescanFloor: const Duration(seconds: 30),
        now: () => clock,
      );

      // First poll scans (finds no name), second poll (same second) is throttled.
      await adapter.fetch();
      await adapter.pendingApNameScan;
      await adapter.fetch();
      await adapter.pendingApNameScan;
      expect(fake.scanCount, 1);

      // Advance past the floor: a re-scan is allowed.
      clock = clock.add(const Duration(seconds: 31));
      await adapter.fetch();
      await adapter.pendingApNameScan;
      expect(fake.scanCount, 2);
    });
  });

  group('MacWifiInfoAdapter OWE from the beacon when macOS says open', () {
    const String oweBssid = 'b2:05:d6:56:cb:2c';

    _CountingService macSays(String token, Map<String, Object?> blob) =>
        _CountingService(
          wifiInfo: _wifiInfoMap(
            bssid: oweBssid,
            locationAuthorized: true,
            securityToken: token,
          ),
          ieBlob: blob,
        );

    test('Open first, then OWE once the beacon shows AKM 00-0F-AC:18',
        () async {
      final _CountingService fake = macSays(
        'open',
        _blob(oweBssid, hexBytes(kKeithGuestOweBeaconIes)),
      );
      final MacWifiInfoAdapter adapter =
          MacWifiInfoAdapter(service: fake.service, enrichApName: true);

      final ConnectedAp first = await adapter.fetch();
      expect(first.securityType, WifiSecurity.open);
      await adapter.pendingApNameScan;

      final ConnectedAp second = await adapter.fetch();
      expect(second.securityType, WifiSecurity.owe);
    });

    test('the open half of a transition pair stays Open, and once its beacon '
        'is read (no RSN element) the Open is confirmed', () async {
      final _CountingService fake = macSays(
        'open',
        _blob(oweBssid, hexBytes(kKeithGuestOpenHalfBeaconIes)),
      );
      final MacWifiInfoAdapter adapter =
          MacWifiInfoAdapter(service: fake.service, enrichApName: true);

      final ConnectedAp first = await adapter.fetch();
      expect(first.beaconConfirmsOpen, isFalse); // no evidence yet
      await adapter.pendingApNameScan;
      final ConnectedAp second = await adapter.fetch();
      expect(second.securityType, WifiSecurity.open);
      expect(second.beaconConfirmsOpen, isTrue);
    });

    test('an OWE beacon never confirms Open', () async {
      final _CountingService fake = macSays(
        'open',
        _blob(oweBssid, hexBytes(kKeithGuestOweBeaconIes)),
      );
      final MacWifiInfoAdapter adapter =
          MacWifiInfoAdapter(service: fake.service, enrichApName: true);

      await adapter.fetch();
      await adapter.pendingApNameScan;
      expect((await adapter.fetch()).beaconConfirmsOpen, isFalse);
    });

    test('a non-open macOS answer is never marked confirmed open', () async {
      final _CountingService fake = macSays(
        'wpa2Personal',
        _blob(oweBssid, hexBytes(kKeithGuestOpenHalfBeaconIes)),
      );
      final MacWifiInfoAdapter adapter =
          MacWifiInfoAdapter(service: fake.service, enrichApName: true);

      await adapter.fetch();
      await adapter.pendingApNameScan;
      expect((await adapter.fetch()).beaconConfirmsOpen, isFalse);
    });

    test('an unmatched BSSID gives no evidence: Open stays unconfirmed',
        () async {
      final _CountingService fake = macSays(
        'open',
        _blob('22:0b:8b:c2:76:c4', hexBytes(kKeithGuestOpenHalfBeaconIes)),
      );
      final MacWifiInfoAdapter adapter =
          MacWifiInfoAdapter(service: fake.service, enrichApName: true);

      await adapter.fetch();
      await adapter.pendingApNameScan;
      expect((await adapter.fetch()).beaconConfirmsOpen, isFalse);
    });

    test('a non-open macOS answer is never overridden by the beacon', () async {
      final _CountingService fake = macSays(
        'wpa3Personal',
        _blob(oweBssid, hexBytes(kKeithGuestOweBeaconIes)),
      );
      final MacWifiInfoAdapter adapter =
          MacWifiInfoAdapter(service: fake.service, enrichApName: true);

      await adapter.fetch();
      await adapter.pendingApNameScan;
      final ConnectedAp second = await adapter.fetch();
      expect(second.securityType, WifiSecurity.wpa3Personal);
    });

    test('bytes returned without a BSSID are no evidence either way',
        () async {
      final _CountingService fake = macSays(
        'open',
        _blob(null, hexBytes(kKeithGuestOweBeaconIes)),
      );
      final MacWifiInfoAdapter adapter =
          MacWifiInfoAdapter(service: fake.service, enrichApName: true);

      await adapter.fetch();
      await adapter.pendingApNameScan;
      final ConnectedAp second = await adapter.fetch();
      expect(second.securityType, WifiSecurity.open);
      expect(second.beaconConfirmsOpen, isFalse);
    });

    test('a stale-scan BSSID mismatch never upgrades', () async {
      final _CountingService fake = macSays(
        'open',
        _blob('ae:05:d6:56:cb:2c', hexBytes(kKeithGuestOweBeaconIes)),
      );
      final MacWifiInfoAdapter adapter =
          MacWifiInfoAdapter(service: fake.service, enrichApName: true);

      await adapter.fetch();
      await adapter.pendingApNameScan;
      final ConnectedAp second = await adapter.fetch();
      expect(second.securityType, WifiSecurity.open);
    });

    test('a cached AP name still gets one scan to settle Open vs OWE, then '
        'none', () async {
      ApNameCache.instance.cacheName(oweBssid, 'Workroom');
      final _CountingService fake = macSays(
        'open',
        _blob(oweBssid, hexBytes(kKeithGuestOweBeaconIes)),
      );
      final MacWifiInfoAdapter adapter =
          MacWifiInfoAdapter(service: fake.service, enrichApName: true);

      final ConnectedAp first = await adapter.fetch();
      expect(first.apName, 'Workroom');
      await adapter.pendingApNameScan;
      expect(fake.scanCount, 1);

      final ConnectedAp second = await adapter.fetch();
      await adapter.pendingApNameScan;
      expect(second.securityType, WifiSecurity.owe);
      expect(second.apName, 'Workroom');
      expect(fake.scanCount, 1);
    });

    test('an OWE verdict is re-read after 5 minutes, so an AP switched back '
        'to open is not called OWE for the rest of the session', () async {
      // Keith switched Keith Guest between OWE and OWE Transition on 25 OCT
      // 2026; the same BSSID can stop being OWE while the app stays open.
      DateTime clock = DateTime(2026, 10, 25, 12, 0, 0);
      final _CountingService fake = macSays(
        'open',
        _blob(oweBssid, hexBytes(kKeithGuestOweBeaconIes)),
      );
      final MacWifiInfoAdapter adapter = MacWifiInfoAdapter(
        service: fake.service,
        enrichApName: true,
        now: () => clock,
      );

      await adapter.fetch();
      await adapter.pendingApNameScan;
      expect((await adapter.fetch()).securityType, WifiSecurity.owe);
      await adapter.pendingApNameScan;
      expect(fake.scanCount, 1);

      // Inside 5 minutes the verdict stands without another scan.
      clock = clock.add(const Duration(minutes: 4));
      expect((await adapter.fetch()).securityType, WifiSecurity.owe);
      await adapter.pendingApNameScan;
      expect(fake.scanCount, 1);

      // The AP is reconfigured: this BSSID now beacons as plain open.
      fake.ieBlob = _blob(oweBssid, hexBytes(kKeithGuestOpenHalfBeaconIes));
      clock = clock.add(const Duration(minutes: 2));
      await adapter.fetch();
      await adapter.pendingApNameScan;
      expect(fake.scanCount, 2);
      expect((await adapter.fetch()).securityType, WifiSecurity.open);
    });
  });
}
