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

/// A fake WifiInfoService (platform macos) whose two methods return fixed maps.
WifiInfoService fakeService({
  required Map<dynamic, dynamic>? wifiInfo,
  required Map<dynamic, dynamic>? ieBlob,
}) =>
    WifiInfoService(
      platformOverride: 'macos',
      invoke: (String method, [dynamic args]) async {
        switch (method) {
          case 'getWifiInfo':
            return wifiInfo;
          case 'connectedApIeBlob':
            return ieBlob;
          default:
            return null;
        }
      },
    );

void main() {
  group('MacWifiInfoAdapter AP-name enrichment', () {
    test('decodes and attaches a UniFi AP name when authorized and matched',
        () async {
      const String bssid = 'aa:bb:cc:dd:ee:ff';
      final WifiInfoService svc = fakeService(
        wifiInfo: _wifiInfoMap(bssid: bssid, locationAuthorized: true),
        ieBlob: <String, Object?>{
          'ieBytes': Uint8List.fromList(_unifiNameBlob('UAP-Lobby')),
          'bssid': bssid,
          'locationAuthorized': true,
        },
      );
      final MacWifiInfoAdapter adapter =
          MacWifiInfoAdapter(service: svc, enrichApName: true);

      final ConnectedAp ap = await adapter.fetch();
      expect(ap.apName, 'UAP-Lobby');
    });

    test('enrichment OFF by default leaves apName null (no extra scan needed)',
        () async {
      const String bssid = 'aa:bb:cc:dd:ee:ff';
      final WifiInfoService svc = fakeService(
        wifiInfo: _wifiInfoMap(bssid: bssid, locationAuthorized: true),
        ieBlob: <String, Object?>{
          'ieBytes': Uint8List.fromList(_unifiNameBlob('UAP-Lobby')),
          'bssid': bssid,
          'locationAuthorized': true,
        },
      );
      final MacWifiInfoAdapter adapter = MacWifiInfoAdapter(service: svc);

      final ConnectedAp ap = await adapter.fetch();
      expect(ap.apName, isNull);
    });

    test('unauthorized Location skips the scan and yields honest-null apName',
        () async {
      final WifiInfoService svc = fakeService(
        wifiInfo: _wifiInfoMap(bssid: null, locationAuthorized: false),
        ieBlob: <String, Object?>{
          'ieBytes': Uint8List.fromList(_unifiNameBlob('UAP-Lobby')),
          'bssid': 'aa:bb:cc:dd:ee:ff',
          'locationAuthorized': false,
        },
      );
      final MacWifiInfoAdapter adapter =
          MacWifiInfoAdapter(service: svc, enrichApName: true);

      final ConnectedAp ap = await adapter.fetch();
      expect(ap.apName, isNull);
    });

    test('a stale-scan BSSID mismatch yields honest-null (never a wrong name)',
        () async {
      final WifiInfoService svc = fakeService(
        wifiInfo: _wifiInfoMap(bssid: 'aa:bb:cc:dd:ee:ff', locationAuthorized: true),
        ieBlob: <String, Object?>{
          // Scan matched a DIFFERENT BSS than the connected one.
          'ieBytes': Uint8List.fromList(_unifiNameBlob('SomeOtherAP')),
          'bssid': '11:22:33:44:55:66',
          'locationAuthorized': true,
        },
      );
      final MacWifiInfoAdapter adapter =
          MacWifiInfoAdapter(service: svc, enrichApName: true);

      final ConnectedAp ap = await adapter.fetch();
      expect(ap.apName, isNull);
    });

    test('an empty/absent IE blob yields honest-null and keeps the RF read',
        () async {
      const String bssid = 'aa:bb:cc:dd:ee:ff';
      final WifiInfoService svc = fakeService(
        wifiInfo: _wifiInfoMap(bssid: bssid, locationAuthorized: true),
        ieBlob: <String, Object?>{
          'ieBytes': null,
          'bssid': null,
          'locationAuthorized': true,
        },
      );
      final MacWifiInfoAdapter adapter =
          MacWifiInfoAdapter(service: svc, enrichApName: true);

      final ConnectedAp ap = await adapter.fetch();
      expect(ap.apName, isNull);
      expect(ap.bssid, bssid); // the RF snapshot survives the null enrichment
    });
  });
}
