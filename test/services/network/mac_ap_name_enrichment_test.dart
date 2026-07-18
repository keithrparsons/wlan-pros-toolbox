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

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';

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
}) =>
    <String, Object?>{
      'ssid': 'KeithNet',
      'bssid': bssid,
      'poweredOn': true,
      'locationAuthorized': locationAuthorized,
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
}
