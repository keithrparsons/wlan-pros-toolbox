// Unit tests for FsplMath (Wi-Fi Classroom FSPL Simulator).
//
// Reference values were computed independently of this code (Python, exact
// c = 299,792,458 m/s) and are pinned here to +/-0.02 dB, per spec 03
// "Done means".

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/fspl_math.dart';

const double _tol = 0.02;

/// The three default channels: 2.4 GHz ch 6, 5 GHz ch 100, 6 GHz ch 37, plus
/// the second 6 GHz default, ch 117.
final Map<double, List<double>> _expected = <double, List<double>>{
  // freq MHz: FSPL at 1 m, 10 m, 100 m.
  2437: <double>[40.18, 60.18, 80.18],
  5500: <double>[47.26, 67.26, 87.26],
  6135: <double>[48.20, 68.20, 88.20],
  6535: <double>[48.75, 68.75, 88.75],
};

void main() {
  group('FSPL at 1, 10 and 100 m', () {
    _expected.forEach((double f, List<double> want) {
      const List<double> d = <double>[1, 10, 100];
      for (int i = 0; i < 3; i++) {
        test('$f MHz at ${d[i]} m', () {
          expect(FsplMath.fsplDb(d[i], f), closeTo(want[i], _tol));
          expect(FsplMath.fsplRoundedDb(d[i], f), closeTo(want[i], _tol));
        });
      }
    });

    test('spec worked example: 2437 MHz at 10 m', () {
      // 60.18 exact, 60.19 with the rounded -27.55 constant.
      expect(FsplMath.fsplDb(10, 2437), closeTo(60.1849, 0.0005));
      expect(FsplMath.fsplRoundedDb(10, 2437), closeTo(60.1871, 0.0005));
    });

    test('the rounded constant stands for 27.5522', () {
      expect(FsplMath.exactConstantDb, closeTo(27.5522, 0.0001));
    });

    test('every doubling of distance costs 6.02 dB', () {
      for (final double d in <double>[1, 3, 12.5, 400]) {
        expect(
          FsplMath.fsplDb(2 * d, 5500) - FsplMath.fsplDb(d, 5500),
          closeTo(20 * math.log(2) / math.ln10, 1e-9),
        );
      }
    });
  });

  group('spreading loss + aperture term = FSPL', () {
    for (final double f in <double>[2437, 5500, 6135, 6535]) {
      test('$f MHz', () {
        for (final double d in <double>[1, 2, 10, 37.5, 100, 1000]) {
          expect(
            FsplMath.spreadingLossDb(d) + FsplMath.apertureTermDb(f),
            closeTo(FsplMath.fsplDb(d, f), 1e-9),
          );
        }
      });
    }

    test('spreading loss does not depend on frequency', () {
      // Same number whatever the band: it takes no frequency argument, and at
      // 10 m it is 10 log10(4 pi 100) = 30.99 dB.
      expect(FsplMath.spreadingLossDb(10), closeTo(30.99, _tol));
    });

    test('only the aperture term changes between bands', () {
      // Aperture term difference equals the full band difference.
      expect(
        FsplMath.apertureTermDb(5500) - FsplMath.apertureTermDb(2437),
        closeTo(FsplMath.bandDifferenceDb(2437, 5500), 1e-9),
      );
      expect(FsplMath.apertureTermDb(2437), closeTo(29.19, _tol));
    });

    test('isotropic aperture at 2437 MHz is about 12 cm^2', () {
      expect(FsplMath.isotropicApertureM2(2437) * 1e4, closeTo(12.04, 0.01));
    });
  });

  group('band difference at equal distance', () {
    test('2.437 -> 5.500 GHz is 7.07 dB', () {
      expect(FsplMath.bandDifferenceDb(2437, 5500), closeTo(7.07, _tol));
    });
    test('2.437 -> 6.535 GHz is 8.57 dB', () {
      expect(FsplMath.bandDifferenceDb(2437, 6535), closeTo(8.57, _tol));
    });
    test('equals the FSPL difference at any distance', () {
      for (final double d in <double>[1, 10, 100]) {
        expect(
          FsplMath.fsplDb(d, 6535) - FsplMath.fsplDb(d, 2437),
          closeTo(8.57, _tol),
        );
      }
    });
  });

  group('log-distance model', () {
    test('n = 2 equals free space', () {
      for (final double f in <double>[2437, 5500, 6135]) {
        for (final double d in <double>[1, 5, 10, 100, 1000]) {
          expect(
            FsplMath.logDistanceDb(d, f, 2),
            closeTo(FsplMath.fsplDb(d, f), 1e-9),
          );
        }
      }
    });

    test('n = 3 adds 10 dB per decade over free space', () {
      expect(
        FsplMath.logDistanceDb(10, 2437, 3) - FsplMath.fsplDb(10, 2437),
        closeTo(10, 1e-9),
      );
      expect(FsplMath.logDistanceDb(100, 2437, 3), closeTo(100.18, _tol));
    });

    test('at 1 m every exponent gives FSPL(1 m)', () {
      for (final double n in <double>[2, 2.5, 3, 4]) {
        expect(
          FsplMath.logDistanceDb(1, 5500, n),
          closeTo(FsplMath.fsplDb(1, 5500), 1e-9),
        );
      }
    });
  });

  group('received power', () {
    test('Tx + gains - path loss - other losses', () {
      expect(
        FsplMath.receivedPowerDbm(
          txPowerDbm: 20,
          txGainDbi: 4,
          rxGainDbi: 2,
          pathLossDb: 60.18,
          otherLossesDb: 3,
        ),
        closeTo(-37.18, 1e-9),
      );
    });

    test('other losses default to zero', () {
      expect(
        FsplMath.receivedPowerDbm(
          txPowerDbm: 17,
          txGainDbi: 0,
          rxGainDbi: 0,
          pathLossDb: 80,
        ),
        -63,
      );
    });

    test('pathLossForRssi inverts receivedPowerDbm', () {
      const double pl = 71.3;
      final double rssi = FsplMath.receivedPowerDbm(
        txPowerDbm: 18,
        txGainDbi: 3,
        rxGainDbi: -1,
        pathLossDb: pl,
        otherLossesDb: 2,
      );
      expect(
        FsplMath.pathLossForRssi(
          rssiDbm: rssi,
          txPowerDbm: 18,
          txGainDbi: 3,
          rxGainDbi: -1,
          otherLossesDb: 2,
        ),
        closeTo(pl, 1e-9),
      );
    });
  });
}
