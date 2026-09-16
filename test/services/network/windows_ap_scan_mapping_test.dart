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

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ap_scan_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart'
    show LocationAuthStatus, WifiInfoUnavailable, WifiInfoUnavailableReason;
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
  _wiringTests();
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

    test('every row carries exactly the seven shared-model keys, no noise or SNR',
        () {
      // The Native Wifi BSS list has no per-BSS noise floor. Nothing may be
      // derived to fill the gap (GL-005 / GL-008).
      //
      // SIX became SEVEN on 2026-09-16 when `security` landed on this path.
      // That is not this guard weakening: macOS has emitted `security` since
      // 2026-09-13 (ApScanChannel.swift), so the shared model already had seven
      // keys and Windows was the one out of step. The guard's real job is the
      // two assertions below it, that nothing invents a noise floor or an SNR,
      // and those are untouched.
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
          'security',
        },
      );
      expect(rows.single.containsKey('noiseDbm'), isFalse);
      expect(rows.single.containsKey('snrDb'), isFalse);
    });

    test('a candidate with NO IE blob reports EMPTY security, never open', () {
      // The helper builds candidates without IEs. Empty must stay empty: an
      // open BSS reports the token `none`, and absence of information is not
      // information (ScannedAp.security, GL-005).
      final List<Map<String, Object?>> rows = scannedApRowsFromBssCandidates(
        <WifiBssCandidate>[
          _candidate(bssid: 'a4:83:e7:00:11:22', centerFreqKhz: 5180000),
        ],
      );
      expect(rows.single['security'], isEmpty);
      expect(rows.single['security'], isNot(contains('none')));
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

// ===========================================================================
// THE WIRING, added 2026-09-06 after it shipped broken for about an hour.
//
// THE DEFECT: Windows was added to ApScanService.wiredPlatforms the moment the
// FFI enumeration was proven on real hardware, and the tool went live -- but
// nothing routed Windows to that enumeration. `scan()` still called
// `_invoke(method)`, a MethodChannel that only Android and macOS answer
// natively. Keith opened the tool on the Framework and got
// `MissingPluginException - no implementation found`.
//
// WHY IT REACHED HIM RAW: MissingPluginException is NOT a PlatformException,
// so the `on PlatformException` catch in that method never saw it. There was no
// honest error card either -- the exception escaped the service entirely.
//
// WHY NO EXISTING TEST CAUGHT IT: every Windows test above is a PURE MAPPING
// test, and its own header says so -- "A passing test here is NOT evidence the
// Windows scan works". It was right. The mapping was always correct; the wiring
// never existed. A green suite proved a claim nobody had made.
//
// These tests bind the wiring itself, which is the thing that broke.

void _wiringTests() {
  group('Windows scan wiring (the MissingPluginException defect)', () {
    test('scan() reads the FFI enumeration and NEVER touches the channel',
        () async {
      bool channelTouched = false;
      final ApScanService svc = ApScanService(
        platformOverride: 'windows',
        invoke: (String method, [dynamic args]) async {
          channelTouched = true;
          throw MissingPluginException('no implementation found for $method');
        },
        windowsScan: () async => <Map<String, Object?>>[
          <String, Object?>{
            'ssid': 'KeithNet',
            'bssid': '94:2a:6f:42:e5:3f',
            'rssiDbm': -33,
            'channel': 117,
            'band': '6 GHz',
            'frequencyMhz': 6535,
          },
        ],
      );

      final ApScanSnapshot snap = await svc.scan();

      expect(channelTouched, isFalse,
          reason: 'the channel call is the defect; Windows has no handler for '
              'it and MissingPluginException is not caught by the '
              'PlatformException guard');
      expect(snap.accessPoints, hasLength(1));
      expect(snap.accessPoints.single.ssid, 'KeithNet');
      expect(snap.accessPoints.single.channel, 117);
    });

    test('no Location gate on Windows, and no channel call to discover that',
        () async {
      bool channelTouched = false;
      final ApScanService svc = ApScanService(
        platformOverride: 'windows',
        invoke: (String method, [dynamic args]) async {
          channelTouched = true;
          throw MissingPluginException('no implementation found for $method');
        },
        invokeWifiInfo: (String method, [dynamic args]) async {
          channelTouched = true;
          throw MissingPluginException('no implementation found for $method');
        },
        windowsScan: () async => const <Map<String, Object?>>[],
      );

      // Proven, not assumed: the live run enumerated 57 BSS with no prompt.
      expect(await svc.isLocationAuthorized(), isTrue);
      expect(await svc.requestLocationPermission(), isTrue);
      expect(await svc.locationAuthorizationStatus(),
          LocationAuthStatus.authorized);
      expect(await svc.openLocationSettings(), isFalse);
      expect(channelTouched, isFalse);
    });

    test('an FFI failure becomes an honest error card, not a raw exception',
        () async {
      final ApScanService svc = ApScanService(
        platformOverride: 'windows',
        invoke: (String method, [dynamic args]) async => null,
        windowsScan: () async => throw const WifiInfoUnavailable(
          WifiInfoUnavailableReason.channelError,
          'wlanapi returned ERROR_INVALID_HANDLE',
        ),
      );
      await expectLater(
        svc.scan(),
        throwsA(isA<ApScanUnavailable>().having(
          (ApScanUnavailable e) => e.reason,
          'reason',
          ApScanUnavailableReason.channelError,
        )),
      );
    });
  });
}
