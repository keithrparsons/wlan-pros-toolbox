// Pure nearby-AP row-mapping tests for the Windows Native Wifi FFI helpers
// (windows_wifi_ffi.dart). [scannedApRowsFromBssCandidates] is pure Dart over a
// plain [WifiBssCandidate] value object — it touches no win32 symbol — so it
// runs on macOS CI even though the FFI body that reads wlanapi.dll cannot.
// Importing the module here never triggers the lazy wlanapi.dll load, since
// these tests make no FFI call.
//
// SCOPE, said plainly: these tests cover the MAPPING only. The FFI enumeration
// that would feed it ([enumerateNearbyBssFromNativeWifi]) has never run against
// real hardware, and Windows is deliberately NOT a supported platform for the
// Nearby AP Scan tool. A passing test here is NOT evidence the Windows scan
// works ([[feedback_tests_that_cannot_fail]]); it only proves that IF the
// enumeration ever returns real BSS rows, they map to the shared payload shape
// correctly.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/windows_wifi_ffi.dart';

/// Builds a candidate. Center frequency is in kHz, as WLAN_BSS_ENTRY reports it.
WifiBssCandidate _candidate({
  required String bssid,
  String? ssid,
  int rssiDbm = -55,
  required int centerFreqKhz,
}) {
  return WifiBssCandidate(
    bssid: bssid,
    ssid: ssid,
    rssiDbm: rssiDbm,
    centerFreqKhz: centerFreqKhz,
  );
}

void main() {
  group('scannedApRowsFromBssCandidates — shared payload shape', () {
    test('maps kHz center frequency to the right channel, band, and MHz', () {
      final List<Map<String, Object?>> rows = scannedApRowsFromBssCandidates(
        <WifiBssCandidate>[
          _candidate(
            bssid: 'a4:83:e7:00:11:22',
            ssid: 'HomeNet',
            rssiDbm: -42,
            centerFreqKhz: 5180000, // 5180 MHz -> ch 36, 5 GHz
          ),
          _candidate(
            bssid: 'b8:27:eb:aa:bb:cc',
            ssid: 'HomeNet-2G',
            rssiDbm: -71,
            centerFreqKhz: 2437000, // 2437 MHz -> ch 6, 2.4 GHz
          ),
          _candidate(
            bssid: 'c0:ff:ee:00:00:01',
            ssid: 'HomeNet-6G',
            rssiDbm: -63,
            centerFreqKhz: 5975000, // 5975 MHz -> ch 5, 6 GHz
          ),
        ],
      );

      expect(rows.length, 3);
      expect(rows[0]['channel'], 36);
      expect(rows[0]['band'], '5 GHz');
      expect(rows[0]['frequencyMhz'], 5180);
      expect(rows[0]['rssiDbm'], -42);
      expect(rows[1]['channel'], 6);
      expect(rows[1]['band'], '2.4 GHz');
      expect(rows[2]['band'], '6 GHz');
    });

    test('every row carries exactly the six shared-model keys, no noise or SNR',
        () {
      // The Native Wifi BSS list has no per-BSS noise floor. Nothing may be
      // derived to fill the gap (GL-005 / GL-008).
      final List<Map<String, Object?>> rows = scannedApRowsFromBssCandidates(
        <WifiBssCandidate>[
          _candidate(bssid: 'a4:83:e7:00:11:22', centerFreqKhz: 5180000),
        ],
      );
      expect(
        rows.single.keys.toSet(),
        <String>{
          'ssid',
          'bssid',
          'rssiDbm',
          'channel',
          'band',
          'frequencyMhz',
        },
      );
      expect(rows.single.containsKey('noiseDbm'), isFalse);
      expect(rows.single.containsKey('snrDb'), isFalse);
    });

    test('a hidden network becomes a null SSID, never a blank or a made-up name',
        () {
      final List<Map<String, Object?>> rows = scannedApRowsFromBssCandidates(
        <WifiBssCandidate>[
          _candidate(bssid: 'c0:ff:ee:00:00:01', ssid: '', centerFreqKhz: 2437000),
          _candidate(bssid: 'c0:ff:ee:00:00:02', centerFreqKhz: 2437000),
        ],
      );
      expect(rows[0]['ssid'], isNull);
      expect(rows[1]['ssid'], isNull);
    });

    test('a frequency off the channel plan is DROPPED, not filed under a guess',
        () {
      final List<Map<String, Object?>> rows = scannedApRowsFromBssCandidates(
        <WifiBssCandidate>[
          _candidate(bssid: 'a4:83:e7:00:11:22', centerFreqKhz: 5180000),
          // 4000 MHz is not a Wi-Fi channel on any band.
          _candidate(bssid: 'de:ad:be:ef:00:01', centerFreqKhz: 4000000),
          // 0 kHz: the driver reported nothing usable.
          _candidate(bssid: 'de:ad:be:ef:00:02', centerFreqKhz: 0),
        ],
      );
      expect(rows.length, 1);
      expect(rows.single['bssid'], 'a4:83:e7:00:11:22');
    });

    test('duplicate BSSIDs collapse to one row', () {
      final List<Map<String, Object?>> rows = scannedApRowsFromBssCandidates(
        <WifiBssCandidate>[
          _candidate(bssid: 'a4:83:e7:00:11:22', centerFreqKhz: 5180000),
          _candidate(bssid: 'a4:83:e7:00:11:22', centerFreqKhz: 5180000),
        ],
      );
      expect(rows.length, 1);
    });

    test('an empty candidate list maps to an empty row list, never a null row',
        () {
      expect(scannedApRowsFromBssCandidates(<WifiBssCandidate>[]), isEmpty);
    });
  });
}
