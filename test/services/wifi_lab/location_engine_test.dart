// Pins the Where Am I? engine (spec 33 "Done means", the math half).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/location_engine.dart';

void main() {
  group('signal strength', () {
    test('with sigma = 0 and matching n, the estimate equals the true '
        'distance', () {
      for (final double n in <double>[2, 2.7, 3, 4]) {
        for (final double d in <double>[0.5, 1, 4.2, 10, 25, 36]) {
          final double rssi = locRssiDbm(d, n: n);
          expect(locDistanceFromRssi(rssi, n: n), closeTo(d, 1e-9));
        }
      }
      final LocRun run = runLocation(
        const LocSettings(sigmaDb: 0, ftmErrorM: 0),
      );
      for (final LocApReading a in run.drawn) {
        expect(a.signalDistanceM, closeTo(a.trueDistanceM, 1e-9));
      }
    });

    test('a mismatched exponent biases the estimate', () {
      final LocRun run = runLocation(
        const LocSettings(sigmaDb: 0, exponent: 3, modelExponent: 2),
      );
      // Real walls lose more than the model assumes: everything reads far.
      for (final LocApReading a in run.drawn) {
        if (a.trueDistanceM > 1.5) {
          expect(a.signalDistanceM, greaterThan(a.trueDistanceM));
        }
      }
    });

    test('the error factor for sigma = 6, n = 3 is 1.585', () {
      expect(locErrorFactor(6, 3).toStringAsFixed(3), '1.585');
      expect(locErrorFactor(6, 3), closeTo(math.pow(10, 0.2), 1e-12));
      expect(locErrorFactor(0, 3), 1);
    });

    test('a one-sigma error at 10 m reads about 6.3 m and 15.8 m', () {
      final (double lo, double hi) = locOneSigmaRange(10, 6, 3);
      expect(lo.toStringAsFixed(1), '6.3');
      expect(hi.toStringAsFixed(1), '15.8');
    });

    test('a one-sigma shadowing draw moves the estimate by exactly the '
        'factor', () {
      const double d = 10;
      final double rssi = locRssiDbm(d, n: 3, shadowDb: -6);
      expect(
        locDistanceFromRssi(rssi, n: 3),
        closeTo(d * locErrorFactor(6, 3), 1e-9),
      );
    });

    test('the error grows with distance (same dB, more meters)', () {
      final (double lo5, double hi5) = locOneSigmaRange(5, 6, 3);
      final (double lo20, double hi20) = locOneSigmaRange(20, 6, 3);
      expect(hi20 - lo20, greaterThan(hi5 - lo5));
    });
  });

  group('timing', () {
    test('light covers about 30 cm per nanosecond; 1 ns of round trip is '
        'about 15 cm', () {
      expect(kLocMetersPerNs, closeTo(0.2998, 1e-4));
      expect(locDistanceFromRoundTripNs(1), closeTo(0.1499, 1e-4));
      expect(locRoundTripNs(10), closeTo(66.71, 0.01));
      expect(
        locDistanceFromRoundTripNs(locRoundTripNs(12.3)),
        closeTo(12.3, 1e-9),
      );
    });

    test('with FTM error 0 and no blocked paths, trilateration returns the '
        'true position', () {
      for (int n = kLocMinAps; n <= kLocMaxAps; n++) {
        for (final LocPoint dev in <LocPoint>[
          kLocDefaultDevice,
          (x: 22, y: 14),
          (x: 1, y: 19),
          (x: 15, y: 10),
        ]) {
          final LocSettings s = LocSettings(
            aps: defaultLocAps(n),
            device: dev,
            ftmErrorM: 0,
          );
          final LocRun run = runLocation(s);
          final LocFix fix = run.ftm.fix!;
          expect(fix.position.x, closeTo(dev.x, 1e-6), reason: '$n APs $dev');
          expect(fix.position.y, closeTo(dev.y, 1e-6), reason: '$n APs $dev');
          expect(fix.rmsResidualM, closeTo(0, 1e-6));
          expect(run.ftm.spreadRadiusM, closeTo(0, 1e-6));
          expect(run.ftm.nonMeetingPairs, isEmpty);
        }
      }
    });

    test('a blocked-path bias makes that AP read long, and only that AP', () {
      const LocSettings clear = LocSettings(ftmErrorM: 0);
      final LocSettings blocked = clear.copyWith(
        blocked: const <bool>[false, true],
        blockedBiasM: 5,
      );
      final List<LocApReading> a = runLocation(clear).drawn;
      final List<LocApReading> b = runLocation(blocked).drawn;
      expect(b[1].ftmDistanceM, closeTo(a[1].trueDistanceM + 5, 1e-9));
      expect(b[1].errorFor(LocMethod.ftm), greaterThan(0));
      expect(b[0].ftmDistanceM, closeTo(a[0].ftmDistanceM, 1e-9));
      // The fix moves off the true position.
      expect(runLocation(blocked).ftm.positionErrorM, greaterThan(0.5));
    });

    test('a blocked bias with the default timing error still reads long on '
        'average', () {
      final LocSettings s = const LocSettings().copyWith(
        blocked: const <bool>[true],
      );
      final LocRun run = runLocation(s);
      double sum = 0;
      for (final List<LocApReading> t in run.readings) {
        sum += t[0].errorFor(LocMethod.ftm);
      }
      expect(sum / run.readings.length, greaterThan(2.5));
    });
  });

  group('trilateration and spread', () {
    test('position spread for signal strength exceeds timing at the '
        'defaults', () {
      final LocRun run = runLocation(const LocSettings());
      expect(run.signal.scatter, hasLength(kLocTrials));
      expect(run.ftm.scatter, hasLength(kLocTrials));
      expect(run.signal.spreadRadiusM, greaterThan(2 * run.ftm.spreadRadiusM));
      expect(run.signal.rmsErrorM, greaterThan(run.ftm.rmsErrorM));
    });

    test('deterministic with a seed; a new seed gives new draws', () {
      final LocRun a = runLocation(const LocSettings(seed: 7));
      final LocRun b = runLocation(const LocSettings(seed: 7));
      final LocRun c = runLocation(const LocSettings(seed: 8));
      expect(a.signal.fix!.position, b.signal.fix!.position);
      expect(a.ftm.spreadRadiusM, b.ftm.spreadRadiusM);
      expect(a.signal.fix!.position, isNot(c.signal.fix!.position));
    });

    // Regression (2026-09-26 render): 6 APs, sigma 10 dB, device at (22, 14)
    // drew a signal-strength spread radius of 22,548,072.1 m, because an
    // undamped Gauss-Newton step from a badly conditioned start ran away.
    test('a bad set of circles never sends the fix off to infinity', () {
      for (int seed = 1; seed <= 40; seed++) {
        final LocSettings s = LocSettings(
          aps: defaultLocAps(6),
          device: (x: 22, y: 14),
          sigmaDb: 10,
          blocked: const <bool>[true, false, false, true],
          blockedBiasM: 10,
          seed: seed,
        );
        final LocRun run = runLocation(s);
        for (final LocMethodResult r in <LocMethodResult>[
          run.signal,
          run.ftm,
        ]) {
          expect(r.spreadRadiusM, lessThan(60), reason: 'seed $seed');
          for (final LocPoint p in r.scatter) {
            expect(p.x.isFinite && p.y.isFinite, isTrue);
            expect(p.x, inInclusiveRange(-120, 150), reason: 'seed $seed');
            expect(p.y, inInclusiveRange(-120, 140), reason: 'seed $seed');
          }
        }
      }
    });

    test(
      'the damped solve still fits at least as well as the linear start',
      () {
        final LocRun run = runLocation(const LocSettings(sigmaDb: 8, seed: 3));
        for (final List<LocApReading> t in run.readings.take(10)) {
          final List<double> r = <double>[
            for (final LocApReading a in t) a.signalDistanceM,
          ];
          final LocFix fix = trilaterate(const LocSettings().aps, r)!;
          // Nudging the answer in any direction makes the fit no better.
          double cost(LocPoint p) {
            double c = 0;
            for (int i = 0; i < r.length; i++) {
              final double f =
                  locDistance(p, const LocSettings().aps[i]) - r[i];
              c += f * f;
            }
            return c;
          }

          final double here = cost(fix.position);
          for (final (double dx, double dy) in <(double, double)>[
            (0.05, 0),
            (-0.05, 0),
            (0, 0.05),
            (0, -0.05),
          ]) {
            expect(
              cost((x: fix.position.x + dx, y: fix.position.y + dy)),
              greaterThanOrEqualTo(here - 1e-6),
            );
          }
        }
      },
    );

    test('circles that cannot meet are named', () {
      // Two APs 24 m apart, each reading 5 m: no shared point.
      final List<(int, int)> pairs = locNonMeetingPairs(
        const <LocPoint>[(x: 3, y: 3), (x: 27, y: 3), (x: 15, y: 17)],
        const <double>[5, 5, 30],
      );
      expect(pairs, contains((0, 1)));
      expect(pairs, contains((0, 2)), reason: 'circle 0 sits inside 2');
    });

    test('collinear APs give no fix rather than a wrong one', () {
      expect(
        trilaterate(
          const <LocPoint>[(x: 0, y: 0), (x: 10, y: 0), (x: 20, y: 0)],
          const <double>[5, 5, 15],
        ),
        isNull,
      );
    });

    test('the AP layouts sit on the floor, 3 to 6 of them', () {
      for (int n = kLocMinAps; n <= kLocMaxAps; n++) {
        final List<LocPoint> aps = defaultLocAps(n);
        expect(aps, hasLength(n));
        for (final LocPoint p in aps) {
          expect(p.x, inInclusiveRange(0, kLocFloorWidthM));
          expect(p.y, inInclusiveRange(0, kLocFloorDepthM));
        }
      }
      expect(const LocSettings().aps, defaultLocAps(kLocDefaultAps));
    });
  });
}
