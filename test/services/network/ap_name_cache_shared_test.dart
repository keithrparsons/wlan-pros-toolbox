// Shared AP-name cache — cross-adapter behavior (feature/shared-apname-cache).
//
// The name cache and scan throttle used to live per-adapter, so every screen
// started COLD: even after the Roaming Log decoded an AP's name, a freshly-opened
// Wi-Fi Info screen (its own adapter) re-ran the slow beacon scan. These tests
// prove the cache is now app-wide via [ApNameCache.instance]:
//   1. A name decoded by adapter A is served by a SEPARATE adapter B on B's
//      FIRST fetch with ZERO scans on B — the instant cross-screen hit.
//   2. A genuinely-new BSSID triggers EXACTLY ONE throttled scan app-wide across
//      two adapters — the throttle timestamp is shared, so the second adapter
//      does not re-storm the radio for the same not-yet-known BSSID.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ap_name_cache.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';

/// One non-extended IE element: [id][len][...data].
List<int> _ie(int id, List<int> data) => <int>[id, data.length, ...data];

/// A synthetic UniFi (Ubiquiti) Tag 221 AP-name IE: OUI 00:15:6D, type 0x01.
List<int> _unifiNameBlob(String name) =>
    _ie(221, <int>[0x00, 0x15, 0x6D, 0x01, ...name.codeUnits]);

Map<String, Object?> _wifiInfoMap(String bssid) => <String, Object?>{
      'ssid': 'KeithNet',
      'bssid': bssid,
      'poweredOn': true,
      'locationAuthorized': true,
    };

Map<String, Object?> _blob(String? bssid, List<int>? ieBytes) => <String, Object?>{
      'ieBytes': ieBytes == null ? null : Uint8List.fromList(ieBytes),
      'bssid': bssid,
      'locationAuthorized': true,
    };

/// A counting fake WifiInfoService (platform macos). [scanCount] records how
/// many times the beacon-IE scan channel was hit, so a per-adapter scan count
/// (or a shared app-wide count) can be asserted.
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

void main() {
  // These tests exercise the app-wide singleton directly, so reset it between
  // cases to keep each start cold.
  setUp(() => ApNameCache.instance.clear());

  test(
    'a name decoded by adapter A is served by a SEPARATE adapter B on B\'s '
    'FIRST fetch, with NO scan on B (instant cross-screen hit)',
    () async {
      const String bssid = 'aa:bb:cc:dd:ee:ff';

      // Adapter A (e.g. the Roaming Log sampler) decodes and caches the name.
      final _CountingService fakeA = _CountingService(
        wifiInfo: _wifiInfoMap(bssid),
        ieBlob: _blob(bssid, _unifiNameBlob('UAP-Lobby')),
      );
      final MacWifiInfoAdapter adapterA =
          MacWifiInfoAdapter(service: fakeA.service, enrichApName: true);

      await adapterA.fetch(); // honest-null first read, schedules the scan
      await adapterA.pendingApNameScan; // scan resolves, caches into the singleton
      expect(fakeA.scanCount, 1);

      // Adapter B is a DIFFERENT instance with its OWN service (a freshly-opened
      // Wi-Fi Info screen). It shares the app-wide cache, so its FIRST fetch
      // serves the name instantly — B never touches its scan channel.
      final _CountingService fakeB = _CountingService(
        wifiInfo: _wifiInfoMap(bssid),
        ieBlob: _blob(bssid, _unifiNameBlob('UAP-Lobby')),
      );
      final MacWifiInfoAdapter adapterB =
          MacWifiInfoAdapter(service: fakeB.service, enrichApName: true);

      final ConnectedAp firstOnB = await adapterB.fetch();
      expect(firstOnB.apName, 'UAP-Lobby'); // instant, no cold-start wait
      await adapterB.pendingApNameScan; // nothing was scheduled
      expect(fakeB.scanCount, 0); // B NEVER scanned — the whole point
    },
  );

  test(
    'a not-yet-known BSSID triggers EXACTLY ONE scan app-wide across two '
    'adapters (the throttle is shared, not per-screen)',
    () async {
      const String bssid = '11:22:33:44:55:66';
      final DateTime clock = DateTime(2026, 7, 19, 12, 0, 0);

      // ONE counting service shared by both adapters, so scanCount is the
      // app-wide total. The scan returns no IE data → no name is ever cached,
      // so ONLY the shared throttle can stop a second scan.
      final _CountingService fake = _CountingService(
        wifiInfo: _wifiInfoMap(bssid),
        ieBlob: _blob(bssid, null),
      );

      final MacWifiInfoAdapter adapterA = MacWifiInfoAdapter(
        service: fake.service,
        enrichApName: true,
        apNameRescanFloor: const Duration(seconds: 30),
        now: () => clock,
      );
      final MacWifiInfoAdapter adapterB = MacWifiInfoAdapter(
        service: fake.service,
        enrichApName: true,
        apNameRescanFloor: const Duration(seconds: 30),
        now: () => clock,
      );

      // Adapter A scans first and stamps the shared last-scan timestamp.
      await adapterA.fetch();
      await adapterA.pendingApNameScan;
      expect(fake.scanCount, 1);

      // Adapter B, at the same instant, sees A's shared timestamp inside the
      // floor and DEFERS — it does not re-scan the same not-yet-known BSSID.
      await adapterB.fetch();
      await adapterB.pendingApNameScan;
      expect(fake.scanCount, 1); // still one scan app-wide, not two
    },
  );
}
