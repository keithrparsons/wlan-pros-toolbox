// Pins every number the Rate vs Range tool shows (spec 18, "Done means").
//
// The expected sensitivity table below is typed independently from
// Deliverables/2026-09-25-wifi-lab-wave3-research/brief.md section 10, so a
// slip in rate_vs_range_math.dart fails here instead of passing against
// itself.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/rf/ssid_airtime.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/fspl_math.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/rate_vs_range_math.dart';

/// Brief section 10: MCS 0..13 rows, 20/40/80/160/320 MHz columns.
const List<List<int>> _brief = <List<int>>[
  <int>[-82, -79, -76, -73, -70],
  <int>[-79, -76, -73, -70, -67],
  <int>[-77, -74, -71, -68, -65],
  <int>[-74, -71, -68, -65, -62],
  <int>[-70, -67, -64, -61, -58],
  <int>[-66, -63, -60, -57, -54],
  <int>[-65, -62, -59, -56, -53],
  <int>[-64, -61, -58, -55, -52],
  <int>[-59, -56, -53, -50, -47],
  <int>[-57, -54, -51, -48, -45],
  <int>[-54, -51, -48, -45, -42],
  <int>[-52, -49, -46, -43, -40],
  <int>[-49, -46, -43, -40, -37],
  <int>[-46, -43, -40, -37, -34],
];

const List<int> _widths = <int>[20, 40, 80, 160, 320];

double _ring(int mcs, int w, {double n = 3, double margin = 0}) =>
    RateVsRangeMath.ringRadiusM(
      mcs: mcs,
      widthMHz: w,
      eirpDbm: 20,
      clientGainDbi: 0,
      freqMHz: 5500,
      exponent: n,
      marginDb: margin,
    );

void main() {
  group('sensitivity table (brief section 10)', () {
    for (int m = 0; m <= 13; m++) {
      for (int c = 0; c < 5; c++) {
        test('MCS $m at ${_widths[c]} MHz = ${_brief[m][c]} dBm', () {
          expect(
            RateVsRangeMath.sensitivityDbm(m, _widths[c]),
            _brief[m][c].toDouble(),
          );
        });
      }
    }

    test('has exactly 14 rows of 5 columns', () {
      expect(RateVsRangeMath.sensitivityTable.length, 14);
      for (final List<double> row in RateVsRangeMath.sensitivityTable) {
        expect(row.length, 5);
      }
    });

    test('+3 dB per width doubling, every MCS', () {
      for (int m = 0; m <= 13; m++) {
        for (int c = 1; c < 5; c++) {
          expect(
            RateVsRangeMath.sensitivityDbm(m, _widths[c]) -
                RateVsRangeMath.sensitivityDbm(m, _widths[c - 1]),
            3,
          );
        }
      }
    });

    test('modulation labels follow the brief', () {
      expect(RateVsRangeMath.mcsInfo[0].modulation, 'BPSK');
      expect(RateVsRangeMath.mcsInfo[5].codeRate, '2/3');
      expect(RateVsRangeMath.mcsInfo[13].modulation, '4096-QAM');
      expect(RateVsRangeMath.mcsInfo[13].codeRate, '5/6');
    });

    test('an unknown width throws', () {
      expect(() => RateVsRangeMath.sensitivityDbm(0, 30), throwsArgumentError);
    });
  });

  group('rings', () {
    test('radii strictly decrease with MCS at every width and exponent', () {
      for (final double n in <double>[2, 3, 4]) {
        for (final int w in _widths) {
          for (int m = 1; m <= 13; m++) {
            expect(
              _ring(m, w, n: n),
              lessThan(_ring(m - 1, w, n: n)),
              reason: 'MCS $m at $w MHz, n = $n',
            );
          }
        }
      }
    });

    test('at n = 2, doubling width shrinks every radius by 10^(3/20)', () {
      final double k = math.pow(10, 3 / 20).toDouble();
      expect(k, closeTo(1.41, 0.005));
      for (int m = 0; m <= 13; m++) {
        for (int c = 1; c < 5; c++) {
          expect(
            _ring(m, _widths[c - 1], n: 2) / _ring(m, _widths[c], n: 2),
            closeTo(k, 1e-9),
          );
        }
      }
    });

    test('received power at the ring radius equals the sensitivity', () {
      for (int m = 0; m <= 13; m += 3) {
        final double r = _ring(m, 80);
        final double rx = RateVsRangeMath.receivedDbm(
          eirpDbm: 20,
          clientGainDbi: 0,
          distanceM: r,
          freqMHz: 5500,
          exponent: 3,
        );
        expect(rx, closeTo(RateVsRangeMath.sensitivityDbm(m, 80), 1e-9));
      }
    });

    test('path loss is FSPL(1 m) + 10 n log10(d) from fspl_math', () {
      expect(
        RateVsRangeMath.pathLossDb(10, 5500, 3),
        closeTo(FsplMath.fsplDb(1, 5500) + 30, 1e-9),
      );
    });

    test('a margin shrinks every ring', () {
      for (int m = 0; m <= 13; m++) {
        expect(_ring(m, 20, margin: 6), lessThan(_ring(m, 20)));
      }
    });

    test('worked example: MCS 0 at 20 MHz, 20 dBm, 5500 MHz, n = 3', () {
      // FSPL(1 m) at 5500 MHz = 47.25 dB; budget 20 - 47.25 + 82 = 54.75 dB.
      expect(FsplMath.fsplDb(1, 5500), closeTo(47.25, 0.01));
      expect(_ring(0, 20), closeTo(66.8, 0.1));
    });

    test('mcsFor picks the highest MCS the signal clears', () {
      expect(RateVsRangeMath.mcsFor(-82, 20), 0);
      expect(RateVsRangeMath.mcsFor(-82.1, 20), isNull);
      expect(RateVsRangeMath.mcsFor(-64, 20), 7);
      expect(RateVsRangeMath.mcsFor(-30, 320), 13);
      expect(RateVsRangeMath.mcsFor(-64, 20, marginDb: 1), 6);
      expect(RateVsRangeMath.mcsFor(-64, 40), 4); // MCS 5 needs -63 at 40
    });
  });

  group('noise floor', () {
    test('thermal noise before NF: -101 / -98 / -95 / -92 / -89 dBm', () {
      const List<double> want = <double>[-101.0, -98.0, -95.0, -92.0, -89.0];
      for (int c = 0; c < 5; c++) {
        expect(
          RateVsRangeMath.thermalNoiseDbm(_widths[c]),
          closeTo(want[c], 0.1),
        );
      }
      expect(RateVsRangeMath.thermalNoiseDbm(320), closeTo(-88.95, 0.01));
    });

    test('noise figure adds on top, default 7 dB', () {
      expect(RateVsRangeMath.defaultNoiseFigureDb, 7);
      expect(
        RateVsRangeMath.noiseFloorDbm(20, 7),
        closeTo(RateVsRangeMath.thermalNoiseDbm(20) + 7, 1e-9),
      );
    });
  });

  group('basic rates and beacons', () {
    test('MCS-equivalent mapping and cell-edge floors', () {
      expect(RvrBasicRate.values.map((RvrBasicRate r) => r.mbps.round()), <int>[
        6,
        12,
        18,
        24,
        36,
        48,
        54,
      ]);
      expect(RateVsRangeMath.basicRateSensitivityDbm(RvrBasicRate.mbps6), -82);
      expect(RateVsRangeMath.basicRateSensitivityDbm(RvrBasicRate.mbps24), -74);
      expect(RateVsRangeMath.basicRateSensitivityDbm(RvrBasicRate.mbps54), -65);
      // Only 6 Mbps is backed directly; the rest must be labeled
      // MCS-equivalent.
      expect(
        RvrBasicRate.values.where((RvrBasicRate r) => r.isSourcedDirectly),
        <RvrBasicRate>[RvrBasicRate.mbps6],
      );
    });

    test('9 Mbps and DSSS rates are not offered', () {
      final Set<double> offered = RvrBasicRate.values
          .map((RvrBasicRate r) => r.mbps)
          .toSet();
      for (final double r in <double>[1, 2, 5.5, 9, 11]) {
        expect(offered.contains(r), isFalse);
      }
    });

    test('beacon airtime at 24 Mbps is about a quarter of 6 Mbps', () {
      for (final int n in <int>[1, 4, 8, 16]) {
        final double at6 = RateVsRangeMath.beaconAirtimePercent(
          RvrBasicRate.mbps6,
          n,
        );
        final double at24 = RateVsRangeMath.beaconAirtimePercent(
          RvrBasicRate.mbps24,
          n,
        );
        expect(at24 / at6, inInclusiveRange(0.25, 0.30), reason: '$n SSIDs');
      }
    });

    test('beacon airtime comes from the ssid-airtime calculator', () {
      const SsidAirtimeCalculator calc = SsidAirtimeCalculator(
        SsidAirtimeShared(),
      );
      final double want = calc
          .compute(const SsidAirtimeBand(name: 'x', ssids: 4, rate: 12))
          .beaconPercent;
      expect(
        RateVsRangeMath.beaconAirtimePercent(RvrBasicRate.mbps12, 4),
        want,
      );
      // 400-byte 802.11ax beacon: 560 us at 6 Mbps, 156 us at 24 Mbps.
      expect(RateVsRangeMath.beaconFrameUs(RvrBasicRate.mbps6), 560);
      expect(RateVsRangeMath.beaconFrameUs(RvrBasicRate.mbps24), 156);
      expect(560 / 156, closeTo(3.6, 0.05)); // the explainer's 3.6 times
    });
  });
}
