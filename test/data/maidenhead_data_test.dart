// Tests for the Maidenhead Grid Square engine (data/maidenhead_data.dart).
//
// Verified against published locators:
//   San Francisco Bay  37.75,  -122.45   -> CM87
//   Berlin             52.5 N,  13.4 E    -> JO62
//   Munich             48.14666, 11.60833 -> JN58td  (Wikipedia worked example)
// Plus encode/decode round-trip, case-insensitivity, boundary behavior, and the
// great-circle leg between two squares.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/maidenhead_data.dart';

void main() {
  group('encode — published anchors', () {
    test('San Francisco Bay -> CM87 (4 char)', () {
      expect(Maidenhead.encode(37.75, -122.45, precision: 4), 'CM87');
    });

    test('Berlin -> JO62 (4 char)', () {
      expect(Maidenhead.encode(52.5, 13.4, precision: 4), 'JO62');
    });

    test('Munich -> JN58td (6 char, Wikipedia worked example)', () {
      expect(Maidenhead.encode(48.14666, 11.60833, precision: 6), 'JN58td');
    });

    test('canonical case: UPPER field, lower subsquare', () {
      final String g = Maidenhead.encode(48.14666, 11.60833, precision: 6);
      expect(g.substring(0, 2), 'JN'); // field uppercase
      expect(g.substring(4, 6), 'td'); // subsquare lowercase
    });

    test('8-char extends the 6-char with a digit pair', () {
      final String six = Maidenhead.encode(48.14666, 11.60833, precision: 6);
      final String eight = Maidenhead.encode(48.14666, 11.60833, precision: 8);
      expect(eight.length, 8);
      expect(eight.startsWith(six), isTrue);
    });
  });

  group('encode — boundary + validation', () {
    test('a coordinate on a square boundary floors into the higher square', () {
      // lon -122.0 sits exactly on the CM8x/CM9x boundary; floor convention
      // puts it in CM9x. lat 37.4 -> square 7. Documents, not a bug.
      expect(Maidenhead.encode(37.4, -122.0, precision: 4), 'CM97');
    });

    test('the extreme corners do not index past the last cell', () {
      // +90 / +180 must clamp one ulp inside, landing in field R, not S.
      expect(Maidenhead.encode(90.0, 180.0, precision: 4).startsWith('RR'),
          isTrue);
      expect(Maidenhead.encode(-90.0, -180.0, precision: 4), 'AA00');
    });

    test('an unsupported precision throws', () {
      expect(() => Maidenhead.encode(0, 0, precision: 5),
          throwsA(isA<ArgumentError>()));
    });

    test('an out-of-range coordinate throws', () {
      expect(() => Maidenhead.encode(91, 0), throwsA(isA<ArgumentError>()));
      expect(() => Maidenhead.encode(0, 181), throwsA(isA<ArgumentError>()));
    });
  });

  group('decode', () {
    test('JO62 center is 52.5 N, 13.0 E', () {
      final MaidenheadCell c = Maidenhead.decode('JO62')!;
      expect(c.centerLat, closeTo(52.5, 1e-9));
      expect(c.centerLon, closeTo(13.0, 1e-9));
      // 4-char square is 2 deg lon x 1 deg lat.
      expect(c.lonWidth, closeTo(2.0, 1e-9));
      expect(c.latHeight, closeTo(1.0, 1e-9));
    });

    test('is case-insensitive', () {
      final MaidenheadCell a = Maidenhead.decode('JO62')!;
      final MaidenheadCell b = Maidenhead.decode('jo62')!;
      expect(b.centerLat, a.centerLat);
      expect(b.centerLon, a.centerLon);
    });

    test('rejects bad length and bad glyphs', () {
      expect(Maidenhead.decode('CM8'), isNull); // odd length
      expect(Maidenhead.decode('CM875'), isNull); // odd length
      expect(Maidenhead.decode('ZZ99'), isNull); // field Z > R
      expect(Maidenhead.decode('CMZZ'), isNull); // square not digits
      expect(Maidenhead.decode(''), isNull);
      expect(Maidenhead.isValid('CM87'), isTrue);
      expect(Maidenhead.isValid('JN58td'), isTrue);
    });
  });

  group('round-trip — original point lies inside its decoded cell', () {
    final List<(double, double)> points = <(double, double)>[
      (37.75, -122.45),
      (52.5, 13.4),
      (48.14666, 11.60833),
      (-33.8688, 151.2093), // Sydney
      (0.0, 0.0),
      (-45.0, -170.0),
    ];
    for (final (double lat, double lon) in points) {
      test('($lat, $lon) at 8-char', () {
        final String g = Maidenhead.encode(lat, lon, precision: 8);
        final MaidenheadCell c = Maidenhead.decode(g)!;
        expect(lat, greaterThanOrEqualTo(c.swLat));
        expect(lat, lessThanOrEqualTo(c.neLat));
        expect(lon, greaterThanOrEqualTo(c.swLon));
        expect(lon, lessThanOrEqualTo(c.neLon));
      });
    }
  });

  group('great-circle leg between two squares', () {
    test('CM87 -> JO62 is roughly 9000-9300 km, valid bearing', () {
      final GridLeg leg = Maidenhead.legBetween('CM87', 'JO62')!;
      expect(leg.km, greaterThan(8500));
      expect(leg.km, lessThan(9600));
      expect(leg.miles, closeTo(leg.km * 0.621371, 1e-6));
      expect(leg.bearingDeg, greaterThanOrEqualTo(0));
      expect(leg.bearingDeg, lessThan(360));
    });

    test('identical squares give zero distance', () {
      final GridLeg leg = Maidenhead.legBetween('JO62', 'JO62')!;
      expect(leg.km, closeTo(0.0, 1e-9));
    });

    test('an invalid locator yields null', () {
      expect(Maidenhead.legBetween('CM87', 'NOPE!'), isNull);
      expect(Maidenhead.legBetween('zzz', 'JO62'), isNull);
    });
  });
}
