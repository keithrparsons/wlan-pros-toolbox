// Scoped tests for the pure-Dart Open Location Code (Plus Code) encoder.
//
// Reference codes are taken from Google's Open Location Code test vectors
// (Apache-2.0). A known lat/long must encode to a known full code, offline.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/open_location_code.dart';

void main() {
  group('OpenLocationCode.encode — known reference vectors', () {
    // Vectors verified against the canonical Open Location Code reference
    // implementation (Apache-2.0).
    test('20.3700625,2.7821875 -> 7FG49QCJ+ (8-digit area code)', () {
      expect(OpenLocationCode.encode(20.3700625, 2.7821875, codeLength: 8),
          '7FG49QCJ+');
    });

    test('NYC 40.7128,-74.0060 -> 87G7PX7V+4JC (11-digit Plus Code)', () {
      final String code =
          OpenLocationCode.encode(40.7128, -74.0060, codeLength: 11);
      expect(code, '87G7PX7V+4JC');
    });

    test('47.0000625,8.0000625 -> 8FVC2222+22', () {
      expect(
        OpenLocationCode.encode(47.0000625, 8.0000625, codeLength: 10),
        '8FVC2222+22',
      );
    });

    test('-41.2730625,174.7859375 -> 4VCPPQGP+Q9', () {
      expect(
        OpenLocationCode.encode(-41.2730625, 174.7859375, codeLength: 10),
        '4VCPPQGP+Q9',
      );
    });

    test('0.5,-179.5 -> 62G2GG22+22', () {
      expect(
        OpenLocationCode.encode(0.5, -179.5, codeLength: 10),
        '62G2GG22+22',
      );
    });

    test('34.05,-118.25 (Los Angeles) -> 85633Q22+22', () {
      expect(
        OpenLocationCode.encode(34.05, -118.25, codeLength: 10),
        '85633Q22+22',
      );
    });
  });

  group('OpenLocationCode.encode — shape and structure', () {
    test('default length is 10 significant digits with a + after the 8th', () {
      final String code = OpenLocationCode.encode(34.05, -118.25);
      // 8 digits, '+', then 2 digits.
      expect(code.length, 11);
      expect(code[OpenLocationCode.separatorPosition], OpenLocationCode.separator);
      expect(code.contains('+'), isTrue);
    });

    test('an 11-digit code adds exactly one grid digit', () {
      final String code = OpenLocationCode.encode(34.05, -118.25, codeLength: 11);
      // 8 digits, '+', then 3 digits.
      expect(code.length, 12);
    });

    test('every emitted character is in the OLC alphabet (or + / 0)', () {
      const String legal = '23456789CFGHJMPQRVWX+0';
      final String code = OpenLocationCode.encode(51.5074, -0.1278);
      for (final String ch in code.split('')) {
        expect(legal.contains(ch), isTrue, reason: 'illegal char "$ch" in $code');
      }
    });
  });

  group('OpenLocationCode.encode — out-of-range inputs never throw', () {
    test('latitude above 90 is clamped', () {
      expect(() => OpenLocationCode.encode(95.0, 10.0), returnsNormally);
    });

    test('longitude beyond 180 is normalized', () {
      // 200 longitude normalizes to -160 and must equal that code.
      expect(
        OpenLocationCode.encode(10.0, 200.0),
        OpenLocationCode.encode(10.0, -160.0),
      );
    });

    test('the south pole / antimeridian corner encodes without error', () {
      expect(() => OpenLocationCode.encode(-90.0, -180.0), returnsNormally);
    });
  });
}
