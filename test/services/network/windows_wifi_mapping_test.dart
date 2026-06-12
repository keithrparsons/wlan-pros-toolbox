// Pure-mapping tests for the Windows Native Wifi FFI helpers
// (windows_wifi_ffi.dart). These functions are pure Dart — they do NOT call any
// win32 symbol — so they run on macOS CI even though the FFI body that reads
// wlanapi.dll cannot. The win32 DynamicLibrary.open('wlanapi.dll') is a lazy
// top-level `final` that is only resolved on first FFI call, which these tests
// never make, so importing the module here is safe off Windows.
//
// feat/windows-port-prep (2026-06-11). This locks the value→token / standard /
// channel / band mappings that turn raw Native Wifi enums + frequencies into the
// shared WifiInfo contract, so a regression in the lookup tables is caught here
// rather than only on the Windows box on the 26th.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/services/network/windows_wifi_ffi.dart';
import 'package:wlan_pros_toolbox/services/network/windows_wifi_reader.dart';

void main() {
  group('WindowsWifiReader platform guard', () {
    test('off Windows, fetch throws unsupportedPlatform WITHOUT touching FFI',
        () async {
      // isWindowsOverride: false simulates a non-Windows host. The reader must
      // throw before any win32 symbol is referenced, so no wlanapi.dll load is
      // attempted (this is what keeps the package inert off Windows).
      final reader = WindowsWifiReader(isWindowsOverride: false);
      expect(reader.isSupported, isFalse);
      await expectLater(
        reader.fetch(),
        throwsA(
          isA<WifiInfoUnavailable>().having(
            (e) => e.reason,
            'reason',
            WifiInfoUnavailableReason.unsupportedPlatform,
          ),
        ),
      );
    });
  });

  group('phyTypeToStandard', () {
    test('maps the dot11 PHY-type enum to the 802.11 designation', () {
      expect(phyTypeToStandard(2), '802.11b'); // dsss
      expect(phyTypeToStandard(5), '802.11b'); // hrdsss
      expect(phyTypeToStandard(4), '802.11a'); // ofdm
      expect(phyTypeToStandard(6), '802.11g'); // erp
      expect(phyTypeToStandard(7), '802.11n'); // ht
      expect(phyTypeToStandard(8), '802.11ac'); // vht
      expect(phyTypeToStandard(10), '802.11ax'); // he
      expect(phyTypeToStandard(11), '802.11be'); // eht
    });

    test('an unknown PHY type → null (never a guessed standard)', () {
      expect(phyTypeToStandard(0), isNull);
      expect(phyTypeToStandard(99), isNull);
    });
  });

  group('securityTokenForAuthAlgo', () {
    test('maps DOT11_AUTH_ALGO_* to the shared WifiSecurityClassifier tokens',
        () {
      expect(securityTokenForAuthAlgo(1), 'open'); // 80211_OPEN
      expect(securityTokenForAuthAlgo(2), 'wep'); // 80211_SHARED_KEY
      expect(securityTokenForAuthAlgo(3), 'wpaEnterprise'); // WPA
      expect(securityTokenForAuthAlgo(4), 'wpaPersonal'); // WPA_PSK
      expect(securityTokenForAuthAlgo(6), 'wpa2Enterprise'); // RSNA
      expect(securityTokenForAuthAlgo(7), 'wpa2Personal'); // RSNA_PSK
      expect(securityTokenForAuthAlgo(8), 'wpa3Enterprise'); // WPA3 / WPA3_ENT
      expect(securityTokenForAuthAlgo(9), 'wpa3Personal'); // WPA3_SAE
      expect(securityTokenForAuthAlgo(10), 'owe'); // OWE
      expect(securityTokenForAuthAlgo(11), 'wpa3Enterprise'); // WPA3_ENT
    });

    test('an unmapped auth algorithm → the honest "unknown" token', () {
      expect(securityTokenForAuthAlgo(255), 'unknown');
    });
  });

  group('frequencyKhzToChannel', () {
    test('2.4 GHz channels', () {
      expect(frequencyKhzToChannel(2412000), 1);
      expect(frequencyKhzToChannel(2437000), 6);
      expect(frequencyKhzToChannel(2472000), 13);
      expect(frequencyKhzToChannel(2484000), 14);
    });

    test('5 GHz channels', () {
      expect(frequencyKhzToChannel(5180000), 36);
      expect(frequencyKhzToChannel(5500000), 100);
      expect(frequencyKhzToChannel(5745000), 149);
    });

    test('6 GHz channels (Wi-Fi 6E / 7)', () {
      expect(frequencyKhzToChannel(5955000), 1);
      expect(frequencyKhzToChannel(6175000), 45);
    });

    test('a frequency outside the known plans → null', () {
      expect(frequencyKhzToChannel(900000), isNull);
      expect(frequencyKhzToChannel(8000000), isNull);
    });
  });

  group('frequencyKhzToBand', () {
    test('classifies the three Wi-Fi bands', () {
      expect(frequencyKhzToBand(2437000), '2.4 GHz');
      expect(frequencyKhzToBand(5180000), '5 GHz');
      expect(frequencyKhzToBand(5955000), '6 GHz');
    });

    test('an out-of-band frequency → null', () {
      expect(frequencyKhzToBand(900000), isNull);
    });
  });
}
