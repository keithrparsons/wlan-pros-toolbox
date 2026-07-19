// Unit tests for the normalized WiFiDetails model (TICKET-02).
//
// Covers the case-insensitive parser against the real device-verified payload,
// the documented spelling variants, tolerant int parsing, missing-field nulls,
// the SNR computation, and the channel→band derivation (including ch 197 → 6 GHz
// and the 2.4/5/6 GHz overlap handling). No native channel is touched.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';

void main() {
  group('WiFiDetails.fromJsonString — canonical capitalized-key payload', () {
    // The exact real payload from the ticket (device-captured, Wi-Fi 7 / 6 GHz).
    const String realPayload = '{"SSID":"Keith",'
        '"BSSID":"94:2a:6f:a0:a5:5d","Channel":"197","RSSI":"-45",'
        '"Noise":"-95","Standard":"802.11be - Wi-Fi 7","RX Rate":"864",'
        '"TX Rate":"1297"}';

    test('parses every field from the capitalized keys the Shortcut emits', () {
      final WiFiDetails? d = WiFiDetails.fromJsonString(realPayload);
      expect(d, isNotNull);
      expect(d!.ssid, 'Keith');
      expect(d.bssid, '94:2a:6f:a0:a5:5d');
      expect(d.channel, 197);
      expect(d.rssi, -45);
      expect(d.noise, -95);
      expect(d.standard, '802.11be - Wi-Fi 7');
      expect(d.rxRate, 864);
      expect(d.txRate, 1297);
    });

    test('derives SNR = rssi − noise', () {
      final WiFiDetails d = WiFiDetails.fromJsonString(realPayload)!;
      expect(d.snr, 50); // -45 − (-95) = 50 dB
    });

    test('derives 6 GHz band from channel 197', () {
      final WiFiDetails d = WiFiDetails.fromJsonString(realPayload)!;
      expect(d.band, WiFiBand.band6);
      expect(d.band!.label, '6 GHz');
    });

    test('channel width is honestly unavailable (never fabricated)', () {
      final WiFiDetails d = WiFiDetails.fromJsonString(realPayload)!;
      expect(d.hasChannelWidth, isFalse);
    });

    test('hasAnyData is true for a populated payload', () {
      final WiFiDetails d = WiFiDetails.fromJsonString(realPayload)!;
      expect(d.hasAnyData, isTrue);
    });
  });

  group('WiFiDetails — case-insensitive matching', () {
    test('matches lower-case keys from a hand-built Shortcut', () {
      const String json = '{"ssid":"Net","bssid":"a4:11:62:00:11:22",'
          '"channel":"149","rssi":"-52","noise":"-94",'
          '"standard":"802.11ax","rx rate":"1200","tx rate":"1300"}';
      final WiFiDetails d = WiFiDetails.fromJsonString(json)!;
      expect(d.ssid, 'Net');
      expect(d.bssid, 'a4:11:62:00:11:22');
      expect(d.channel, 149);
      expect(d.rssi, -52);
      expect(d.rxRate, 1200);
      expect(d.txRate, 1300);
    });

    test('matches mixed-case and documented variant keys', () {
      const String json = '{"Ssid":"Net","Channel Number":"6",'
          '"Wi-Fi Standard":"802.11n","RX":"144","TX":"150"}';
      final WiFiDetails d = WiFiDetails.fromJsonString(json)!;
      expect(d.ssid, 'Net');
      expect(d.channel, 6);
      expect(d.standard, '802.11n');
      expect(d.rxRate, 144);
      expect(d.txRate, 150);
    });
  });

  group('WiFiDetails — tolerant int parsing', () {
    test('coerces numeric (non-string) JSON values', () {
      const String json = '{"Channel":36,"RSSI":-60,"Noise":-95}';
      final WiFiDetails d = WiFiDetails.fromJsonString(json)!;
      expect(d.channel, 36);
      expect(d.rssi, -60);
      expect(d.noise, -95);
    });

    test('strips a trailing unit and keeps sign + digits', () {
      const String json = '{"RSSI":"-45 dBm","RX Rate":"864 Mbps"}';
      final WiFiDetails d = WiFiDetails.fromJsonString(json)!;
      expect(d.rssi, -45);
      expect(d.rxRate, 864);
    });

    test('non-numeric value for an int field yields null', () {
      const String json = '{"Channel":"auto"}';
      final WiFiDetails d = WiFiDetails.fromJsonString(json)!;
      expect(d.channel, isNull);
    });
  });

  group('WiFiDetails — missing fields surface as null', () {
    test('omitted fields are null; present fields parse (location-gating case)',
        () {
      // Simulates a payload missing SSID/BSSID while the RF fields survive.
      const String json = '{"Channel":"44","RSSI":"-58","Noise":"-92",'
          '"Standard":"802.11ax","RX Rate":"600","TX Rate":"600"}';
      final WiFiDetails d = WiFiDetails.fromJsonString(json)!;
      expect(d.ssid, isNull);
      expect(d.bssid, isNull);
      expect(d.channel, 44);
      expect(d.rssi, -58);
    });

    test('SNR is null when noise is absent (never computed from a null input)',
        () {
      const String json = '{"RSSI":"-58"}';
      final WiFiDetails d = WiFiDetails.fromJsonString(json)!;
      expect(d.snr, isNull);
    });

    test('SNR is null when rssi is absent', () {
      const String json = '{"Noise":"-92"}';
      final WiFiDetails d = WiFiDetails.fromJsonString(json)!;
      expect(d.snr, isNull);
    });

    test('band is null when channel is absent', () {
      const String json = '{"SSID":"Net"}';
      final WiFiDetails d = WiFiDetails.fromJsonString(json)!;
      expect(d.band, isNull);
    });

    test('empty whitespace-only string values are treated as absent', () {
      const String json = '{"SSID":"  ","Channel":"   "}';
      final WiFiDetails d = WiFiDetails.fromJsonString(json)!;
      expect(d.ssid, isNull);
      expect(d.channel, isNull);
      expect(d.hasAnyData, isFalse);
    });
  });

  group('WiFiDetails.fromJsonString — invalid input', () {
    test('malformed JSON returns null (no throw)', () {
      expect(WiFiDetails.fromJsonString('not json {'), isNull);
    });

    test('a JSON array (non-object) returns null', () {
      expect(WiFiDetails.fromJsonString('[1,2,3]'), isNull);
    });

    test('a JSON scalar returns null', () {
      expect(WiFiDetails.fromJsonString('"just a string"'), isNull);
    });

    test('an empty string returns null', () {
      expect(WiFiDetails.fromJsonString('   '), isNull);
    });

    test('an empty object parses but carries no data', () {
      final WiFiDetails? d = WiFiDetails.fromJsonString('{}');
      expect(d, isNotNull);
      expect(d!.hasAnyData, isFalse);
    });
  });

  group('WiFiBand.fromChannel — precise per-channel derivation', () {
    test('unambiguous 2.4 GHz channels resolve to 2.4 GHz', () {
      // 2.4-GHz-only numbers (i.e. not also a valid 6 GHz PSC-grid channel).
      for (final int ch in <int>[3, 4, 6, 7, 8, 10, 11, 12, 14]) {
        expect(WiFiBand.fromChannel(ch), WiFiBand.band24, reason: 'ch $ch');
        expect(WiFiBand.bandFromChannelIsAmbiguous(ch), isFalse,
            reason: 'ch $ch');
      }
    });

    test('unambiguous 5 GHz channels resolve to 5 GHz', () {
      // UNII-1/2A/2C below 149 — all multiples of 4, valid only in 5 GHz.
      for (final int ch in <int>[
        36, 40, 44, 48, 52, 56, 60, 64, //
        100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144,
      ]) {
        expect(WiFiBand.fromChannel(ch), WiFiBand.band5, reason: 'ch $ch');
        expect(WiFiBand.bandFromChannelIsAmbiguous(ch), isFalse,
            reason: 'ch $ch');
      }
    });

    test('unambiguous 6 GHz channels resolve to 6 GHz (the core fix)', () {
      // The real Summit channels: valid ONLY in 6 GHz. The old 36..177 hack
      // mislabeled the lower ones "5 GHz (derived)"; they are 6 GHz, certain.
      for (final int ch in <int>[
        17, 21, 25, 29, 33, 37, 41, 45, 49, 53, 69, 85, 93, 101, 117, 133, //
        145, 181, 185, 197, 213, 229, 233,
      ]) {
        expect(WiFiBand.fromChannel(ch), WiFiBand.band6, reason: 'ch $ch');
        expect(WiFiBand.bandFromChannelIsAmbiguous(ch), isFalse,
            reason: 'ch $ch');
      }
    });

    test('the Summit 6 GHz set is 6 GHz and NOT derived', () {
      for (final int ch in <int>[
        21, 37, 53, 69, 85, 93, 101, 117, 133, 197, 213,
      ]) {
        expect(WiFiBand.fromChannel(ch), WiFiBand.band6, reason: 'ch $ch');
        expect(WiFiBand.bandFromChannelIsAmbiguous(ch), isFalse,
            reason: 'ch $ch');
      }
    });

    test('2.4/6 GHz ambiguous channels default to 2.4 GHz and are derived', () {
      // 1/5/9/13 are valid in both 2.4 and 6 GHz; 2 is 2.4 GHz vs the special
      // 6 GHz 5935 MHz guard channel (app-data discrepancy vs the brief).
      for (final int ch in <int>[1, 2, 5, 9, 13]) {
        expect(WiFiBand.fromChannel(ch), WiFiBand.band24, reason: 'ch $ch');
        expect(WiFiBand.bandFromChannelIsAmbiguous(ch), isTrue,
            reason: 'ch $ch');
      }
    });

    test('5/6 GHz ambiguous channels default to 5 GHz and are derived', () {
      for (final int ch in <int>[149, 153, 157, 161, 165, 169, 173, 177]) {
        expect(WiFiBand.fromChannel(ch), WiFiBand.band5, reason: 'ch $ch');
        expect(WiFiBand.bandFromChannelIsAmbiguous(ch), isTrue,
            reason: 'ch $ch');
      }
    });

    test('ch 197 (real Wi-Fi 7 / 6 GHz sample payload) is 6 GHz, not derived', () {
      expect(WiFiBand.fromChannel(197), WiFiBand.band6);
      expect(WiFiBand.bandFromChannelIsAmbiguous(197), isFalse);
    });

    test('off-plan channel numbers derive no band and are not ambiguous', () {
      for (final int ch in <int>[0, 15, 35, 51, 178, 179, 300]) {
        expect(WiFiBand.fromChannel(ch), isNull, reason: 'ch $ch');
        expect(WiFiBand.bandFromChannelIsAmbiguous(ch), isFalse,
            reason: 'ch $ch');
      }
      expect(WiFiBand.fromChannel(null), isNull);
      expect(WiFiBand.bandFromChannelIsAmbiguous(null), isFalse);
    });

    test('band labels', () {
      expect(WiFiBand.band24.label, '2.4 GHz');
      expect(WiFiBand.band5.label, '5 GHz');
      expect(WiFiBand.band6.label, '6 GHz');
    });
  });

  group('WiFiDetails — value semantics', () {
    test('equal field sets compare equal and share a hashCode', () {
      const String json = '{"SSID":"X","Channel":"36","RSSI":"-50",'
          '"Noise":"-90"}';
      final WiFiDetails a = WiFiDetails.fromJsonString(json)!;
      final WiFiDetails b = WiFiDetails.fromJsonString(json)!;
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
