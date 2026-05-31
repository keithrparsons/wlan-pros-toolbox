// ConnectedAp + WifiInfoSourceResolver — unit tests (TICKET-04).
//
// Covers the normalized model's two mappings (macOS CoreWLAN snapshot and iOS
// Shortcuts payload), the honest per-platform availability flags, the derived
// flags, and the per-platform source resolution.

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';

void main() {
  group('ConnectedAp.fromWifiInfo (macOS)', () {
    final WifiInfo info = WifiInfo(
      interfaceName: 'en0',
      ssid: 'KeithNet',
      bssid: 'a4:83:e7:00:11:22',
      rssiDbm: -50,
      noiseDbm: -95,
      snrDb: 45,
      txRateMbps: 866,
      phyMode: '802.11ax',
      channel: 36,
      channelWidthMhz: 80,
      band: '5 GHz',
      countryCode: 'US',
      hardwareAddress: 'a4:83:e7:aa:bb:cc',
      poweredOn: true,
      locationAuthorized: true,
    );

    test('maps the core fields', () {
      final ap = ConnectedAp.fromWifiInfo(info);
      expect(ap.ssid, 'KeithNet');
      expect(ap.rssiDbm, -50);
      expect(ap.snrDb, 45);
      expect(ap.channelWidthMhz, 80);
      expect(ap.interfaceName, 'en0');
    });

    test('labels the standard with its Wi-Fi generation', () {
      expect(ConnectedAp.fromWifiInfo(info).standard, '802.11ax (Wi-Fi 6)');
    });

    test('Rx rate is platform-unavailable; channel width is available', () {
      final ap = ConnectedAp.fromWifiInfo(info);
      expect(ap.rxRateMbps, isNull);
      expect(ap.rxRateAvailable, isFalse);
      expect(ap.channelWidthAvailable, isTrue);
    });

    test('band and SNR are source-reported, not derived', () {
      final ap = ConnectedAp.fromWifiInfo(info);
      expect(ap.bandDerived, isFalse);
      expect(ap.snrDerived, isFalse);
    });
  });

  group('ConnectedAp.fromWifiDetails (iOS)', () {
    final WiFiDetails d = WiFiDetails.fromMap(const <String, dynamic>{
      'SSID': 'KeithNet',
      'BSSID': 'a4:83:e7:00:11:22',
      'Channel': 36,
      'RSSI': -50,
      'Noise': -95,
      'Standard': '802.11ax - Wi-Fi 6',
      'RX Rate': 780,
      'TX Rate': 866,
    });

    test('maps the core fields and exposes Rx rate', () {
      final ap = ConnectedAp.fromWifiDetails(d);
      expect(ap.ssid, 'KeithNet');
      expect(ap.rssiDbm, -50);
      expect(ap.rxRateMbps, 780);
      expect(ap.rxRateAvailable, isTrue);
    });

    test('channel width is platform-unavailable on iOS', () {
      final ap = ConnectedAp.fromWifiDetails(d);
      expect(ap.channelWidthMhz, isNull);
      expect(ap.channelWidthAvailable, isFalse);
    });

    test('band and SNR are app-derived on iOS', () {
      final ap = ConnectedAp.fromWifiDetails(d);
      expect(ap.band, '5 GHz');
      expect(ap.bandDerived, isTrue);
      expect(ap.snrDb, 45);
      expect(ap.snrDerived, isTrue);
    });

    test('interface and country are absent on the iOS path', () {
      final ap = ConnectedAp.fromWifiDetails(d);
      expect(ap.interfaceName, isNull);
      expect(ap.countryCode, isNull);
    });
  });

  group('hasAnyData', () {
    test('false for an empty payload', () {
      expect(
        ConnectedAp.fromWifiDetails(const WiFiDetails()).hasAnyData,
        isFalse,
      );
    });

    test('true when any substantive field is present', () {
      expect(
        ConnectedAp.fromWifiDetails(
          WiFiDetails.fromMap(const <String, dynamic>{'SSID': 'x'}),
        ).hasAnyData,
        isTrue,
      );
    });
  });

  group('WifiInfoSourceResolver', () {
    test('macOS resolves to the CoreWLAN source', () {
      expect(
        WifiInfoSourceResolver.resolve(platformOverride: TargetPlatform.macOS),
        WifiInfoSource.macosCoreWlan,
      );
    });

    test('iOS resolves to the Shortcuts source', () {
      expect(
        WifiInfoSourceResolver.resolve(platformOverride: TargetPlatform.iOS),
        WifiInfoSource.iosShortcuts,
      );
    });

    test('other native platforms resolve to unsupported', () {
      expect(
        WifiInfoSourceResolver.resolve(
            platformOverride: TargetPlatform.android),
        WifiInfoSource.unsupported,
      );
      expect(
        WifiInfoSourceResolver.resolve(
            platformOverride: TargetPlatform.windows),
        WifiInfoSource.unsupported,
      );
    });
  });
}
