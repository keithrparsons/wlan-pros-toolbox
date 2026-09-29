// Tests for antenna diversity in the Multipath Simulator (Wireless Classroom
// spec 41, "Done means").
//
//   - closed forms: one antenna's 1% level is -20.0 dB; diversity gain at 1%
//     is 10.2 dB (selection, 2), 11.7 dB (MRC, 2), 15.8 dB (selection, 4) and
//     19.1 dB (MRC, 4);
//   - the combined signal is never below any one antenna, and MRC is never
//     below selection;
//   - over many seeded layouts, the simulated shares agree with the closed
//     forms (tolerances stated at each assertion).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/multipath_model.dart';

void main() {
  group('closed forms (independent Rayleigh antennas)', () {
    test('one antenna is below -20.0 dB 1% of the time', () {
      // x = -ln(0.99) = 0.010050; 10 log10(x) = -19.978 dB.
      final double level = DiversityMath.levelAtOutageDb(
        CombineMethod.aOnly,
        1,
        0.01,
      );
      expect(level, closeTo(-19.978, 0.001));
      expect(level.toStringAsFixed(1), '-20.0');
    });

    test('diversity gain at 1%: 10.2, 11.7, 15.8, 19.1 dB', () {
      // Selection 2: (1 - e^-x)^2 = 0.01, x = -ln(0.9) = 0.10536, -9.773 dB.
      expect(
        DiversityMath.gainDb(CombineMethod.selection, 2),
        closeTo(10.205, 0.001),
      );
      // MRC 2: 1 - e^-x (1 + x) = 0.01, x = 0.14860, -8.281 dB.
      expect(
        DiversityMath.gainDb(CombineMethod.mrc, 2),
        closeTo(11.697, 0.001),
      );
      // Selection 4: 1 - e^-x = 0.01^(1/4), x = 0.38013, -4.201 dB.
      expect(
        DiversityMath.gainDb(CombineMethod.selection, 4),
        closeTo(15.778, 0.001),
      );
      // MRC 4: 1 - e^-x (1 + x + x^2/2 + x^3/6) = 0.01, x = 0.82383,
      // -0.842 dB. The planning note said 19.2; it computes to 19.13.
      expect(
        DiversityMath.gainDb(CombineMethod.mrc, 4),
        closeTo(19.134, 0.001),
      );
      expect(DiversityMath.gainDb(CombineMethod.mrc, 4).toStringAsFixed(1),
          '19.1');
    });

    test('share below -10 dB: 9.5%, then 0.91% and 0.47% with two', () {
      expect(
        DiversityMath.outageAtDb(CombineMethod.aOnly, -10, 1),
        closeTo(1 - math.exp(-0.1), 1e-12),
      );
      expect(
        DiversityMath.outageAtDb(CombineMethod.selection, -10, 2),
        closeTo(0.0090559, 1e-6),
      );
      expect(
        DiversityMath.outageAtDb(CombineMethod.mrc, -10, 2),
        closeTo(0.0046788, 1e-6),
      );
    });

    test('with one antenna every method is the same', () {
      for (final double db in <double>[-30, -10, 0, 5]) {
        final double one = DiversityMath.outageAtDb(CombineMethod.aOnly, db, 1);
        expect(
          DiversityMath.outageAtDb(CombineMethod.selection, db, 1),
          closeTo(one, 1e-12),
        );
        expect(
          DiversityMath.outageAtDb(CombineMethod.mrc, db, 1),
          closeTo(one, 1e-12),
        );
      }
    });

    test('MRC beats selection, and four beat two, at every level', () {
      for (double db = -30; db <= 5; db += 0.5) {
        final double s2 = DiversityMath.outageAtDb(
          CombineMethod.selection,
          db,
          2,
        );
        final double m2 = DiversityMath.outageAtDb(CombineMethod.mrc, db, 2);
        final double s4 = DiversityMath.outageAtDb(
          CombineMethod.selection,
          db,
          4,
        );
        final double m4 = DiversityMath.outageAtDb(CombineMethod.mrc, db, 4);
        expect(m2, lessThanOrEqualTo(s2 + 1e-15));
        expect(m4, lessThanOrEqualTo(s4 + 1e-15));
        expect(s4, lessThanOrEqualTo(s2 + 1e-15));
        expect(m4, lessThanOrEqualTo(m2 + 1e-15));
      }
    });
  });

  group('combining along a track', () {
    const MultipathBand band = MultipathBand.b55;
    final ManyPathScene scene = ManyPathScene.generate(seed: 5, count: 20);
    final double spacing = band.wavelength / 2;

    for (final int m in <int>[2, 4]) {
      test('$m antennas: combined is never below any antenna', () {
        final List<List<double>> branches = scene.branchSweepsDb(
          band,
          2001,
          antennas: m,
          spacing: spacing,
        );
        final List<double> sel = scene.combinedSweep(
          CombineMethod.selection,
          band,
          2001,
          antennas: m,
          spacing: spacing,
        );
        final List<double> mrc = scene.combinedSweep(
          CombineMethod.mrc,
          band,
          2001,
          antennas: m,
          spacing: spacing,
        );
        for (int i = 0; i < sel.length; i++) {
          for (final List<double> b in branches) {
            expect(sel[i], greaterThanOrEqualTo(b[i] - 1e-9));
            expect(mrc[i], greaterThanOrEqualTo(b[i] - 1e-9));
          }
          expect(mrc[i], greaterThanOrEqualTo(sel[i] - 1e-9));
        }
      });
    }

    test('A only is antenna A, unchanged', () {
      final List<double> a = scene.sweepDb(band, 501);
      final List<double> c = scene.combinedSweep(
        CombineMethod.aOnly,
        band,
        501,
        spacing: spacing,
      );
      for (int i = 0; i < a.length; i++) {
        expect(c[i], closeTo(a[i], 1e-9));
      }
    });

    test('zero spacing: selection is antenna A, MRC is A plus 3.01 dB', () {
      final List<double> a = scene.sweepDb(band, 501);
      final List<double> sel = scene.combinedSweep(
        CombineMethod.selection,
        band,
        501,
        spacing: 0,
      );
      final List<double> mrc = scene.combinedSweep(
        CombineMethod.mrc,
        band,
        501,
        spacing: 0,
      );
      for (int i = 0; i < a.length; i++) {
        expect(sel[i], closeTo(a[i], 1e-9));
        expect(mrc[i], closeTo(a[i] + 10 * math.log(2) / math.ln10, 1e-9));
      }
    });
  });

  group('simulated vs closed form, over many layouts', () {
    // One sample per seeded layout at a fixed track point, so samples are
    // independent across seeds. Antennas sit 0.383 wavelengths apart, the
    // first zero of the Bessel function J0 (k d = 2.405): with reflectors
    // all around, neighboring antennas are then uncorrelated, the case the
    // closed forms describe. Four antennas at that spacing keep small
    // correlations between non-neighbors (J0^2 below 0.09), which the
    // tolerances allow for.
    const int seeds = 6000;
    const MultipathBand band = MultipathBand.b55;
    final double spacing = 2.4048 / band.k;

    List<List<double>> branchPowers(int m) => <List<double>>[
      for (int s = 0; s < seeds; s++)
        () {
          final ManyPathScene sc = ManyPathScene.generate(seed: s, count: 30);
          return <double>[
            for (int j = 0; j < m; j++)
              sc.normalizedPower(1.0 + j * spacing, band),
          ];
        }(),
    ];

    final List<List<double>> two = branchPowers(2);
    final List<List<double>> four = branchPowers(4);

    double shareBelow(
      List<List<double>> p,
      CombineMethod method,
      double x,
    ) =>
        p.where((List<double> b) => DiversityMath.combine(method, b) < x).length /
        p.length;

    for (final CombineMethod method in <CombineMethod>[
      CombineMethod.selection,
      CombineMethod.mrc,
    ]) {
      test('${method.label}, 2: share below -10 dB matches the closed form', () {
        final double want = DiversityMath.outageAtDb(method, -10, 2);
        final double got = shareBelow(two, method, 0.1);
        // Binomial standard error at 0.9% and 6000 samples is 0.12 points;
        // allow 0.5 points.
        expect(got, closeTo(want, 0.005));
      });

      test('${method.label}, 2 and 4: the 1% gain is near the closed form', () {
        for (final (int m, List<List<double>> p)
            in <(int, List<List<double>>)>[(2, two), (4, four)]) {
          final List<double> combined = <double>[
            for (final List<double> b in p)
              MultipathMath.powerRatioToDb(DiversityMath.combine(method, b)),
          ];
          final List<double> single = <double>[
            for (final List<double> b in p) MultipathMath.powerRatioToDb(b[0]),
          ];
          final double got =
              DiversityMath.percentileDb(combined, 0.01) -
              DiversityMath.percentileDb(single, 0.01);
          // A 1% quantile from 6000 samples rests on about 60 of them, so
          // each level moves by a few tenths of a dB. Measured 2026-09-29:
          // within 0.3 dB of every closed form. Allow 1 dB.
          expect(got, closeTo(DiversityMath.gainDb(method, m), 1.0),
              reason: '${method.label}, $m antennas');
        }
      });
    }

    test('the mean MRC power is the antenna count', () {
      double sum = 0;
      for (final List<double> b in four) {
        sum += DiversityMath.combine(CombineMethod.mrc, b);
      }
      // Each branch averages 1 with standard deviation 1; four add to a mean
      // of 4 with standard error about 2 / sqrt(6000) = 0.026.
      expect(sum / four.length, closeTo(4, 0.1));
    });
  });

  test('percentile and share helpers', () {
    final List<double> v = <double>[for (int i = 0; i < 100; i++) i.toDouble()];
    expect(DiversityMath.percentileDb(v, 0.01), 1);
    expect(DiversityMath.percentileDb(v, 0), 0);
    expect(DiversityMath.fractionBelow(v, 10), 0.1);
    expect(DiversityMath.dbToPower(kPowerFloorDb), 0);
    expect(DiversityMath.dbToPower(10), closeTo(10, 1e-12));
  });
}
