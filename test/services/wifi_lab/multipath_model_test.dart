// Tests for the Multipath Simulator model (Wi-Fi Classroom spec 07, "Done means").
//
// Each group maps to one clause of the spec:
//   - two equal paths with a pi phase difference sum to zero;
//   - standing-wave null spacing equals lambda/2 for all three bands within
//     0.1 mm;
//   - with many equal-power random paths, mean normalized power converges to
//     1 and the share below -10 dB approaches 1 - e^(-0.1) = 9.5% (seeded;
//     tolerances stated at each assertion);
//   - 240 m of extra path is 0.8 us of delay.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/multipath_model.dart';

void main() {
  group('superposition', () {
    test('two equal paths with a pi phase difference sum to zero', () {
      const double r = 5.0;
      final List<MultipathPath> paths = <MultipathPath>[
        const MultipathPath(length: r, coefficient: Complex.one),
        MultipathPath(length: r, coefficient: Complex.polar(1, math.pi)),
      ];
      for (final MultipathBand b in MultipathBand.values) {
        expect(MultipathMath.field(paths, b.k).abs, lessThan(1e-15));
      }
    });

    test('two equal phasors in phase double the field (+6.02 dB)', () {
      const double r = 5.0;
      final List<MultipathPath> paths = <MultipathPath>[
        const MultipathPath(length: r, coefficient: Complex.one),
        const MultipathPath(length: r, coefficient: Complex.one),
      ];
      final double db = MultipathMath.relativePowerDb(
        paths,
        MultipathBand.b55.k,
        r,
      );
      expect(db, closeTo(6.0206, 1e-4));
    });

    test('a half-wavelength path difference cancels two equal copies', () {
      // No reflection phase: the half wavelength of extra travel supplies the
      // pi. Amplitudes are made equal by scaling a to the 1/r spread.
      for (final MultipathBand b in MultipathBand.values) {
        const double r1 = 3.0;
        final double r2 = r1 + b.wavelength / 2;
        final List<MultipathPath> paths = <MultipathPath>[
          const MultipathPath(length: r1, coefficient: Complex.one),
          MultipathPath(length: r2, coefficient: Complex(r2 / r1, 0)),
        ];
        expect(MultipathMath.field(paths, b.k).abs, lessThan(1e-12));
      }
    });

    test('direct path alone reads 0 dB', () {
      const TwoRayScene scene = TwoRayScene();
      final double db = scene.powerDb(
        0.5,
        reflectionCoefficient(0),
        MultipathBand.b24,
      );
      expect(db, closeTo(0, 1e-9));
    });

    test('normalized phasors put the direct path at 1 + 0j', () {
      const TwoRayScene scene = TwoRayScene();
      final List<MultipathPath> paths = scene.paths(
        0.3,
        reflectionCoefficient(0.39),
      );
      final double k = MultipathBand.b65.k;
      final Complex ref = MultipathMath.contribution(paths.first, k);
      final List<Complex> ph = MultipathMath.normalizedPhasors(paths, k, ref);
      expect(ph.first.re, closeTo(1, 1e-12));
      expect(ph.first.im, closeTo(0, 1e-12));
      // The resultant's length is the amplitude ratio the dB readout uses.
      final double db = MultipathMath.amplitudeRatioToDb(
        MultipathMath.sum(ph).abs,
      );
      expect(
        db,
        closeTo(
          scene.powerDb(0.3, reflectionCoefficient(0.39), MultipathBand.b65),
          1e-9,
        ),
      );
    });
  });

  group('two-ray geometry (image method)', () {
    test('reflected path equals the two legs via the reflection point', () {
      const TwoRayScene s = TwoRayScene();
      for (final double t in <double>[0, 0.25, 0.5, 1.0]) {
        final double px = s.reflectionPointX(t);
        final double leg1 = math.sqrt(
          (px - s.txX) * (px - s.txX) + s.txY * s.txY,
        );
        final double leg2 = math.sqrt(
          (s.rxX(t) - px) * (s.rxX(t) - px) + s.rxY * s.rxY,
        );
        expect(leg1 + leg2, closeTo(s.reflectedLength(t), 1e-12));
        expect(s.reflectedLength(t), greaterThan(s.directLength(t)));
      }
    });

    test('metal gives deeper dips than drywall over the 1 m track', () {
      const TwoRayScene s = TwoRayScene();
      final List<double> metal = s.sweepDb(
        reflectionCoefficient(1),
        MultipathBand.b55,
        2001,
      );
      final List<double> drywall = s.sweepDb(
        reflectionCoefficient(0.1),
        MultipathBand.b55,
        2001,
      );
      expect(metal.reduce(math.min), lessThan(-10));
      // |Gamma| = 0.1 can move power by at most 20 log10(1.1) = +0.83 dB and
      // 20 log10(0.9) = -0.92 dB.
      expect(drywall.reduce(math.min), greaterThan(-0.92));
      expect(drywall.reduce(math.max), lessThan(0.83));
    });
  });

  group('standing wave', () {
    test('null spacing equals lambda/2 in every band, within 0.1 mm', () {
      const StandingWaveScene s = StandingWaveScene();
      final Complex metal = reflectionCoefficient(1);
      for (final MultipathBand b in MultipathBand.values) {
        final List<double> nulls = s.nulls(metal, b);
        final double half = b.wavelength / 2;
        // 0.4 m holds at least 6 half wavelengths even at 2.4 GHz.
        expect(nulls.length, greaterThanOrEqualTo(6), reason: b.label);
        for (int i = 1; i < nulls.length; i++) {
          expect(
            nulls[i] - nulls[i - 1],
            closeTo(half, 1e-4),
            reason: '${b.label} null ${i - 1} to $i',
          );
        }
        // And the first one sits half a wavelength off the wall.
        expect(nulls.first, closeTo(half, 1e-4), reason: b.label);
      }
    });

    test('the spec numbers: 6.2 cm, 2.7 cm, 2.3 cm', () {
      expect(MultipathBand.b24.wavelength / 2 * 100, closeTo(6.2, 0.05));
      expect(MultipathBand.b55.wavelength / 2 * 100, closeTo(2.7, 0.05));
      expect(MultipathBand.b65.wavelength / 2 * 100, closeTo(2.3, 0.05));
    });

    test('metal nulls are deep; concrete ripple is about 7.2 dB', () {
      const StandingWaveScene s = StandingWaveScene();
      final List<double> metal = s.sweepDb(
        reflectionCoefficient(1),
        MultipathBand.b24,
        8001,
      );
      expect(metal.sublist(100).reduce(math.min), lessThan(-30));

      expect(StandingWaveScene.rippleDb(0.39), closeTo(7.2, 0.05));
      final List<double> concrete = s.sweepDb(
        reflectionCoefficient(0.39),
        MultipathBand.b24,
        8001,
      );
      final double swing =
          concrete.reduce(math.max) - concrete.reduce(math.min);
      // The 1/r spread over 0.4 m moves this by a few hundredths of a dB.
      expect(swing, closeTo(7.2, 0.1));
    });
  });

  group('many paths (Rayleigh)', () {
    // Ensemble over seeds at a fixed track point: each seed is an
    // independent random layout, so the samples are independent.
    const int seeds = 4000;
    const int count = 30;

    List<double> ensemble(MultipathBand band) => <double>[
      for (int s = 0; s < seeds; s++)
        ManyPathScene.generate(
          seed: s,
          count: count,
        ).normalizedPower(1.0, band),
    ];

    test('mean normalized power converges to 1 (tolerance +/-0.05)', () {
      final List<double> p = ensemble(MultipathBand.b55);
      final double mean = p.reduce((double a, double b) => a + b) / p.length;
      // Exponential power has standard deviation 1, so the standard error of
      // a 4000-sample mean is 1/sqrt(4000) = 0.016; 0.05 is about 3 sigma.
      expect(mean, closeTo(1, 0.05));
    });

    test('share below -10 dB approaches 1 - e^(-0.1) = 9.5% '
        '(tolerance +/-1.5 points)', () {
      final double expected = 1 - math.exp(-0.1);
      expect(MultipathMath.rayleighCdf(-10), closeTo(expected, 1e-12));
      expect(expected, closeTo(0.0952, 1e-4));
      final List<double> p = ensemble(MultipathBand.b24);
      final double below = p.where((double v) => v < 0.1).length / p.length;
      // Binomial standard error sqrt(0.095 * 0.905 / 4000) = 0.46 points;
      // 1.5 points is about 3 sigma.
      expect(below, closeTo(expected, 0.015));
    });

    test('along one track the share below -10 dB is near 9.5% too', () {
      // One long track: a spatial average rather than an ensemble. Samples
      // along a track are correlated, so the tolerance is wider (+/-3 points).
      final ManyPathScene scene = ManyPathScene.generate(
        seed: 7,
        count: count,
        trackLength: 40,
      );
      final List<double> db = scene.sweepDb(MultipathBand.b55, 20000);
      final double below =
          db.where((double v) => v < kFadeThresholdDb).length / db.length;
      expect(below, closeTo(1 - math.exp(-0.1), 0.03));
    });

    test('same seed, same layout; different seed, different layout', () {
      final ManyPathScene a = ManyPathScene.generate(seed: 42, count: 12);
      final ManyPathScene b = ManyPathScene.generate(seed: 42, count: 12);
      final ManyPathScene c = ManyPathScene.generate(seed: 43, count: 12);
      expect(
        a.normalizedPower(0.5, MultipathBand.b24),
        b.normalizedPower(0.5, MultipathBand.b24),
      );
      expect(
        a.normalizedPower(0.5, MultipathBand.b24),
        isNot(c.normalizedPower(0.5, MultipathBand.b24)),
      );
    });

    test('extra lengths are never negative (triangle inequality)', () {
      for (final ScatterEnvironment e in ScatterEnvironment.values) {
        final ManyPathScene s = ManyPathScene.generate(
          seed: 3,
          count: 30,
          environment: e,
        );
        for (final double x in s.extraLengths(1.0)) {
          expect(x, greaterThanOrEqualTo(-1e-9));
        }
      }
    });
  });

  group('diversity and histogram', () {
    test('zero antenna offset: both antennas fade together', () {
      final ManyPathScene s = ManyPathScene.generate(seed: 1, count: 20);
      final List<double> a = s.sweepDb(MultipathBand.b55, 4000);
      final List<double> b = s.sweepDb(MultipathBand.b55, 4000, offset: 0);
      final FadeStats st = FadeStats.from(a, b);
      expect(st.fadedBoth, st.fadedA);
      expect(st.fadedA, st.fadedB);
    });

    test('half a wavelength apart, both faded at once is rare', () {
      // Long track so the fraction is stable: both faded should be far below
      // either alone (independent fading would give 0.095^2 = 0.9%).
      final ManyPathScene s = ManyPathScene.generate(
        seed: 11,
        count: 30,
        trackLength: 40,
      );
      const MultipathBand band = MultipathBand.b55;
      final List<double> a = s.sweepDb(band, 20000);
      final List<double> b = s.sweepDb(
        band,
        20000,
        offset: band.wavelength / 2,
      );
      final FadeStats st = FadeStats.from(a, b);
      expect(st.fractionBoth, lessThan(st.fractionA / 3));
      expect(st.fractionBoth, lessThan(0.03));
    });

    test('histogram keeps every sample; Rayleigh bins sum to 1', () {
      final PowerHistogram h = PowerHistogram.of(<double>[-50, -10, 0, 25]);
      expect(h.counts.reduce((int a, int b) => a + b), 4);
      expect(h.counts.first, 1);
      expect(h.counts.last, 1);
      double total = 0;
      for (int i = 0; i < h.bins; i++) {
        total += h.rayleighFraction(i);
      }
      expect(total, closeTo(1, 1e-12));
    });
  });

  group('delay and the guard interval', () {
    test('240 m of extra path is 0.8 us (within 1 ns)', () {
      expect(MultipathMath.delayNs(240), closeTo(800, 1));
      expect(MultipathMath.guardIntervalMeters, closeTo(239.83, 0.01));
    });

    test('exceeds the guard interval only past 800 ns', () {
      expect(MultipathMath.exceedsGuardInterval(799.9), isFalse);
      expect(MultipathMath.exceedsGuardInterval(800.1), isTrue);
      expect(
        MultipathMath.exceedsGuardInterval(MultipathMath.delayNs(300)),
        isTrue,
      );
    });

    test('outdoors puts some paths past the guard interval, a room none', () {
      final ManyPathScene room = ManyPathScene.generate(seed: 5, count: 30);
      final ManyPathScene out = ManyPathScene.generate(
        seed: 5,
        count: 30,
        environment: ScatterEnvironment.outdoors,
      );
      bool past(ManyPathScene s) => s
          .extraLengths(1.0)
          .any(
            (double m) =>
                MultipathMath.exceedsGuardInterval(MultipathMath.delayNs(m)),
          );
      expect(past(room), isFalse);
      expect(past(out), isTrue);
    });
  });
}
