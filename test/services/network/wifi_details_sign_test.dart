// Covers the boundary that shipped a false RF verdict.
//
// Reported by a user on 2026-07-30: "SNR is with negative and RSSI without" on iOS,
// while Windows looked correct. Cause: fromMap took RSSI and Noise verbatim, so an
// unsigned payload gave snr = 55 - 95 = -40 dB, which grades POOR. A user on an
// excellent link was told their Wi-Fi was bad.
//
// Every pre-existing fixture fed PRE-NEGATED values and the round-trip test built
// WiFiDetails directly, so fromMap had never been exercised with a real payload shape.
// These tests exist so that gap cannot reopen.
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';

void main() {
  group('WiFiDetails.fromMap dBm sign handling', () {
    test('unsigned payload is normalised, and SNR comes out positive', () {
      final d = WiFiDetails.fromMap(<String, dynamic>{'RSSI': 55, 'Noise': 95});
      expect(d.rssi, -55, reason: 'a received signal is never +55 dBm');
      expect(d.noise, -95);
      expect(d.snr, 40, reason: 'the bug produced -40 here and graded it POOR');
    });

    test('already-negative payload is left exactly as it is', () {
      final d = WiFiDetails.fromMap(<String, dynamic>{'RSSI': -55, 'Noise': -95});
      expect(d.rssi, -55);
      expect(d.noise, -95);
      expect(d.snr, 40);
    });

    test('a mixed payload still yields a sane SNR', () {
      final d = WiFiDetails.fromMap(<String, dynamic>{'RSSI': 55, 'Noise': -95});
      expect(d.rssi, -55);
      expect(d.snr, 40);
    });

    test('values carrying a unit suffix survive normalisation', () {
      final d = WiFiDetails.fromMap(<String, dynamic>{'RSSI': '55 dBm', 'Noise': '95 dBm'});
      expect(d.rssi, -55);
      expect(d.snr, 40);
    });

    test('zero is left alone rather than given an invented sign', () {
      final d = WiFiDetails.fromMap(<String, dynamic>{'RSSI': 0, 'Noise': -95});
      expect(d.rssi, 0);
    });

    test('a missing input still refuses to compute SNR', () {
      final d = WiFiDetails.fromMap(<String, dynamic>{'RSSI': 55});
      expect(d.rssi, -55);
      expect(d.noise, isNull);
      expect(d.snr, isNull, reason: 'computing from a missing input is a fabricated number');
    });
  });
}
