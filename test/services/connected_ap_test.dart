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

  group('ConnectedAp.fromAndroidWifiInfo (Android)', () {
    WifiInfo androidInfo({double? rxRateMbps}) => WifiInfo(
          interfaceName: 'wlan0',
          ssid: 'KeithNet',
          bssid: 'a4:83:e7:00:11:22',
          rssiDbm: -52,
          // Android exposes no noise floor.
          noiseDbm: null,
          snrDb: null,
          txRateMbps: 433,
          rxRateMbps: rxRateMbps,
          phyMode: '802.11ax (Wi-Fi 6)',
          channel: 36,
          channelWidthMhz: null,
          band: '5 GHz',
          countryCode: null,
          hardwareAddress: null,
          poweredOn: true,
          locationAuthorized: true,
        );

    test('FIX 2: a real Rx value flows through; rxRateAvailable stays true', () {
      final ap = ConnectedAp.fromAndroidWifiInfo(androidInfo(rxRateMbps: 650));
      expect(ap.rxRateMbps, 650);
      expect(ap.rxRateAvailable, isTrue);
      expect(ap.txRateMbps, 433);
    });

    test('FIX 2: a null Rx (the -1 sentinel) stays null but the platform CAN '
        'expose Rx — so rxRateAvailable is true and the row reads as a limit, '
        'never a fabricated value', () {
      final ap = ConnectedAp.fromAndroidWifiInfo(androidInfo(rxRateMbps: null));
      expect(ap.rxRateMbps, isNull);
      expect(ap.rxRateAvailable, isTrue);
    });

    test('noise and SNR are honestly null (no noise-floor API) and not derived',
        () {
      final ap = ConnectedAp.fromAndroidWifiInfo(androidInfo());
      expect(ap.noiseDbm, isNull);
      expect(ap.snrDb, isNull);
      expect(ap.snrDerived, isFalse);
    });

    test('channel width absent → channelWidthAvailable false', () {
      final ap = ConnectedAp.fromAndroidWifiInfo(androidInfo());
      expect(ap.channelWidthMhz, isNull);
      expect(ap.channelWidthAvailable, isFalse);
    });
  });

  group('ConnectedAp.fromWindowsWifiInfo (Windows Native Wifi)', () {
    // The shape the windows_wifi_ffi reader produces: real dBm RSSI from the BSS
    // entry, BOTH Tx and Rx rates from the association attributes, no noise
    // floor (→ null SNR), channel width deferred (IE parse) → null.
    WifiInfo windowsInfo({int? channelWidthMhz}) => WifiInfo(
          interfaceName: null, // Native Wifi exposes a GUID, not a BSD name.
          ssid: 'KeithNet',
          bssid: 'a4:83:e7:00:11:22',
          rssiDbm: -47, // real dBm from lRssi
          noiseDbm: null,
          snrDb: null,
          txRateMbps: 866,
          rxRateMbps: 780, // Windows supplies Rx (macOS does not)
          phyMode: '802.11ax',
          channel: 36,
          channelWidthMhz: channelWidthMhz,
          band: '5 GHz',
          countryCode: null,
          hardwareAddress: null,
          securityToken: 'wpa3Personal',
          poweredOn: true,
          locationAuthorized: true,
        );

    test('maps the core fields incl. real dBm RSSI', () {
      final ap = ConnectedAp.fromWindowsWifiInfo(windowsInfo());
      expect(ap.ssid, 'KeithNet');
      expect(ap.bssid, 'a4:83:e7:00:11:22');
      expect(ap.rssiDbm, -47);
      expect(ap.channel, 36);
      expect(ap.band, '5 GHz');
    });

    test('exposes BOTH Tx and Rx rate (the macOS Rx gap is closed)', () {
      final ap = ConnectedAp.fromWindowsWifiInfo(windowsInfo());
      expect(ap.txRateMbps, 866);
      expect(ap.rxRateMbps, 780);
      expect(ap.rxRateAvailable, isTrue);
    });

    test('noise and SNR are honestly null (no noise-floor API) and not derived',
        () {
      final ap = ConnectedAp.fromWindowsWifiInfo(windowsInfo());
      expect(ap.noiseDbm, isNull);
      expect(ap.snrDb, isNull);
      expect(ap.snrDerived, isFalse);
    });

    test('channel width deferred (IE parse) → channelWidthAvailable false', () {
      final ap = ConnectedAp.fromWindowsWifiInfo(windowsInfo());
      expect(ap.channelWidthMhz, isNull);
      expect(ap.channelWidthAvailable, isFalse);
    });

    test('a resolved channel width flips channelWidthAvailable true', () {
      final ap =
          ConnectedAp.fromWindowsWifiInfo(windowsInfo(channelWidthMhz: 80));
      expect(ap.channelWidthMhz, 80);
      expect(ap.channelWidthAvailable, isTrue);
    });

    test('security is the FINE token (WPA3 Personal), classified by the shared '
        'classifier', () {
      final ap = ConnectedAp.fromWindowsWifiInfo(windowsInfo());
      expect(ap.securityAvailable, isTrue);
      expect(ap.securityType?.label, 'WPA3 Personal');
    });

    test('labels the standard with its Wi-Fi generation', () {
      expect(
        ConnectedAp.fromWindowsWifiInfo(windowsInfo()).standard,
        '802.11ax (Wi-Fi 6)',
      );
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

    test('Android resolves to the WifiManager source', () {
      expect(
        WifiInfoSourceResolver.resolve(
            platformOverride: TargetPlatform.android),
        WifiInfoSource.androidWifiManager,
      );
    });

    test('Windows resolves to the Native Wifi source', () {
      expect(
        WifiInfoSourceResolver.resolve(
            platformOverride: TargetPlatform.windows),
        WifiInfoSource.windowsNativeWifi,
      );
    });

    test('remaining native platforms resolve to unsupported', () {
      expect(
        WifiInfoSourceResolver.resolve(
            platformOverride: TargetPlatform.linux),
        WifiInfoSource.unsupported,
      );
      expect(
        WifiInfoSourceResolver.resolve(
            platformOverride: TargetPlatform.fuchsia),
        WifiInfoSource.unsupported,
      );
    });
  });
}
