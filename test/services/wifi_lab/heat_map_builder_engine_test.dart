// Heat Map Builder engine tests (Wi-Fi Classroom spec 27, "Done means").
//
// The worked-example and extrapolation numbers are the spec's acceptance
// values, checked by hand before this file was written:
//   p = 1: -60.45, p = 2: -58.06, p = 4: -55.75, p = 2 in mW: -56.22 dBm;
//   10 x 3 x log10(1.5) = 5.28 dB; 5.28 + 12 = 17.28 dB.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/heat_map_builder_engine.dart';

/// One AP at (5, 12.5), no walls unless given; n = 3.
HmFloor _lineFloor({List<HmWall> walls = const <HmWall>[]}) => HmFloor(
  aps: const <HmPoint>[(x: 5, y: 12.5)],
  walls: walls,
  pathLossExponent: 3,
);

/// A survey of the west part of the floor only: a 2.5 m grid over
/// x = 0..15 m, so the last column is 10 m from the AP.
List<HmPoint> _westSurvey() => <HmPoint>[
  for (double x = 0; x <= 15 + 1e-9; x += 2.5)
    for (double y = 0; y <= 25 + 1e-9; y += 2.5) (x: x, y: y),
];

/// A 3 m guess range, so the cell 15 m from the AP (5 m past the last
/// column) is beyond it and the extrapolation mode decides its value.
HmSettings _beyond(HmExtrapolation x) =>
    HmSettings(guessRangeM: 3, extrapolation: x);

void main() {
  group('worked example (spec, to 0.1 dB)', () {
    test('p = 1, 2, 4 in dB', () {
      expect(HmWorkedExample.result(1, HmDomain.db), closeTo(-60.5, 0.1));
      expect(HmWorkedExample.result(2, HmDomain.db), closeTo(-58.1, 0.1));
      expect(HmWorkedExample.result(4, HmDomain.db), closeTo(-55.8, 0.1));
    });

    test('p = 2 averaged in milliwatts', () {
      expect(HmWorkedExample.result(2, HmDomain.mw), closeTo(-56.2, 0.1));
    });

    test('the weights the panel shows', () {
      final List<double> w1 = HmWorkedExample.weights(1);
      expect(w1[0], closeTo(0.500, 0.0005));
      expect(w1[1], closeTo(0.250, 0.0005));
      expect(w1[2], closeTo(0.167, 0.0005));
      final List<double> w2 = HmWorkedExample.weights(2);
      expect(w2[0], closeTo(0.250, 0.0005));
      expect(w2[1], closeTo(0.0625, 0.00005));
      expect(w2[2], closeTo(0.0278, 0.00005));
      final List<double> w4 = HmWorkedExample.weights(4);
      expect(w4[0], closeTo(0.0625, 0.00005));
      expect(w4[1], closeTo(0.0039, 0.00005));
      expect(w4[2], closeTo(0.0008, 0.00005));
    });

    test('nearest neighbor gives the nearest sample', () {
      expect(
        HmWorkedExample.result(2, HmDomain.db, nearest: true),
        HmWorkedExample.valuesDbm.first,
      );
    });
  });

  group('IDW', () {
    test('output always lies between the min and max sample', () {
      final math.Random r = math.Random(7);
      for (int trial = 0; trial < 500; trial++) {
        final int m = 1 + r.nextInt(8);
        final List<double> d = <double>[
          for (int i = 0; i < m; i++) 0.1 + r.nextDouble() * 20,
        ];
        final List<double> z = <double>[
          for (int i = 0; i < m; i++) -95 + r.nextDouble() * 65,
        ];
        final double p = 1 + r.nextDouble() * 5;
        final double lo = z.reduce(math.min);
        final double hi = z.reduce(math.max);
        for (final HmDomain dom in HmDomain.values) {
          final double v = idwCombine(d, z, p, dom);
          expect(v, greaterThanOrEqualTo(lo - 1e-9));
          expect(v, lessThanOrEqualTo(hi + 1e-9));
        }
      }
    });

    test('every map cell lies between the min and max sample', () {
      final HmFloor f = HmFloor();
      final List<HmSample> s = takeHmSamples(
        f,
        hmGridPoints(f, 5),
        const HmNoise(sigmaDb: 4, averaging: 1, seed: 3),
      );
      final double lo = s.map((HmSample x) => x.dbm).reduce(math.min);
      final double hi = s.map((HmSample x) => x.dbm).reduce(math.max);
      for (final HmDomain dom in HmDomain.values) {
        final HmMap m = buildHmMap(
          f,
          s,
          HmSettings(
            domain: dom,
            guessRangeM: 20,
            extrapolation: HmExtrapolation.flatIdw,
          ),
        );
        for (final double v in m.estimate) {
          expect(v, inInclusiveRange(lo - 1e-9, hi + 1e-9));
        }
      }
    });

    test('p = 6 is closer to nearest neighbor than p = 1', () {
      final HmFloor f = HmFloor();
      final List<HmSample> s = takeHmSamples(f, hmGridPoints(f, 5));
      const HmSettings base = HmSettings(guessRangeM: 20);
      final HmMap nn = buildHmMap(
        f,
        s,
        base.copyWith(method: HmMethod.nearest),
      );
      double gap(double p) {
        final HmMap m = buildHmMap(f, s, base.copyWith(power: p));
        double sum = 0;
        for (int i = 0; i < m.cellCount; i++) {
          sum += (m.estimate[i] - nn.estimate[i]).abs();
        }
        return sum / m.cellCount;
      }

      expect(gap(6), lessThan(gap(1)));
      // And the worked example agrees: p = 6 lands within 0.3 dB of -55.
      expect(HmWorkedExample.result(6, HmDomain.db), closeTo(-55, 0.3));
    });

    test('a cell on a sample takes the sample value exactly', () {
      final HmFloor f = _lineFloor();
      final List<HmSample> s = takeHmSamples(f, const <HmPoint>[
        (x: 10, y: 10),
        (x: 12, y: 10),
      ]);
      final HmCellEstimate e = HmEstimator(
        f,
        s,
        const HmSettings(),
      ).estimateAt((x: 10, y: 10));
      expect(e.dbm, s.first.dbm);
    });

    test('contribution shares sum to 1, largest first', () {
      final HmFloor f = HmFloor();
      final List<HmSample> s = takeHmSamples(f, hmGridPoints(f, 3));
      final HmCellEstimate e = HmEstimator(
        f,
        s,
        const HmSettings(),
      ).estimateAt((x: 11.3, y: 7.9));
      expect(e.contributions, hasLength(kHmIdwNeighbors));
      final double sum = e.contributions.fold(
        0,
        (double a, HmContribution c) => a + c.weightShare,
      );
      expect(sum, closeTo(1, 1e-9));
      for (int i = 1; i < e.contributions.length; i++) {
        expect(
          e.contributions[i].weightShare,
          lessThanOrEqualTo(e.contributions[i - 1].weightShare + 1e-12),
        );
      }
    });
  });

  group('guess range', () {
    test('cells beyond it are no data when extrapolation is off', () {
      final HmFloor f = HmFloor();
      final List<HmSample> s = takeHmSamples(f, hmWalkPoints(f, 2));
      const HmSettings set = HmSettings(guessRangeM: 5);
      final HmMap m = buildHmMap(f, s, set);
      int checked = 0;
      for (int r = 0; r < m.rows; r++) {
        for (int c = 0; c < m.cols; c++) {
          final HmPoint q = m.center(c, r);
          final double nearest = s
              .map(
                (HmSample x) =>
                    math.sqrt(math.pow(x.p.x - q.x, 2) + math.pow(x.p.y - q.y, 2)),
              )
              .reduce(math.min);
          if (nearest > 5) {
            expect(m.estimateAt(c, r).isNaN, isTrue);
            expect(m.fillAt(c, r), HmFill.none);
            checked++;
          } else {
            expect(m.estimateAt(c, r).isNaN, isFalse);
          }
        }
      }
      expect(checked, greaterThan(0));
      expect(m.noDataShare, greaterThan(0.3));
    });

    test('three dots with a 20 m range and flat IDW paint the whole floor', () {
      final HmFloor f = HmFloor();
      final List<HmSample> s = takeHmSamples(f, hmThreeDotPoints(f));
      final HmMap narrow = buildHmMap(f, s, const HmSettings());
      final HmMap wide = buildHmMap(
        f,
        s,
        const HmSettings(
          guessRangeM: 20,
          extrapolation: HmExtrapolation.flatIdw,
        ),
      );
      expect(narrow.noDataShare, greaterThan(0.8));
      expect(wide.noDataShare, 0);
    });
  });

  group('extrapolation (spec: n = 3, 10 m to 15 m)', () {
    test('the distance alone costs 5.3 dB', () {
      expect(hmDistanceLossDb(10, 15, 3), closeTo(5.3, 0.05));
      final HmFloor f = _lineFloor();
      expect(
        f.truthDbm((x: 15, y: 12.5)) - f.truthDbm((x: 20, y: 12.5)),
        closeTo(5.28, 0.01),
      );
    });

    test('flat IDW changes by less than 1 dB over those 5 m while the truth '
        'changes by about 5.3 dB', () {
      final HmFloor f = _lineFloor();
      final List<HmSample> s = takeHmSamples(f, _westSurvey());
      final HmEstimator e = HmEstimator(
        f,
        s,
        _beyond(HmExtrapolation.flatIdw),
      );
      final HmCellEstimate at10 = e.estimateAt((x: 15, y: 12.5));
      final HmCellEstimate at15 = e.estimateAt((x: 20, y: 12.5));
      expect(at15.fill, HmFill.flat);
      expect((at10.dbm! - at15.dbm!).abs(), lessThan(1));
      final double truthChange =
          f.truthDbm((x: 15, y: 12.5)) - f.truthDbm((x: 20, y: 12.5));
      expect(truthChange, closeTo(5.3, 0.1));
    });

    test('an unmeasured 12 dB wall raises the far-side error to about 17 dB',
        () {
      const HmWall wall = HmWall(
        a: (x: 17.5, y: 0),
        b: (x: 17.5, y: 25),
        lossDb: 12,
        hidden: true,
      );
      final HmFloor f = _lineFloor(walls: const <HmWall>[wall]);
      final List<HmSample> s = takeHmSamples(f, _westSurvey());
      final HmCellEstimate far = HmEstimator(
        f,
        s,
        _beyond(HmExtrapolation.flatIdw),
      ).estimateAt((x: 20, y: 12.5));
      final double error = far.dbm! - f.truthDbm((x: 20, y: 12.5));
      expect(error, closeTo(17.3, 1));
    });

    test('path-loss fill follows the distance but cannot see the wall', () {
      final HmFloor open = _lineFloor();
      final HmCellEstimate e = HmEstimator(
        open,
        takeHmSamples(open, _westSurvey()),
        _beyond(HmExtrapolation.pathLoss),
      ).estimateAt((x: 20, y: 12.5));
      expect(e.fill, HmFill.model);
      expect(e.dbm! - open.truthDbm((x: 20, y: 12.5)), closeTo(0, 0.1));

      final HmFloor walled = _lineFloor(
        walls: const <HmWall>[
          HmWall(
            a: (x: 17.5, y: 0),
            b: (x: 17.5, y: 25),
            lossDb: 12,
            hidden: true,
          ),
        ],
      );
      final HmCellEstimate w = HmEstimator(
        walled,
        takeHmSamples(walled, _westSurvey()),
        _beyond(HmExtrapolation.pathLoss),
      ).estimateAt((x: 20, y: 12.5));
      expect(w.dbm! - walled.truthDbm((x: 20, y: 12.5)), closeTo(12, 0.5));
    });

    test('the path-loss fit recovers n = 3 from clean samples', () {
      final HmFloor f = _lineFloor();
      final List<HmPathLossFit> fits = fitHmPathLoss(
        f,
        takeHmSamples(f, _westSurvey()),
      );
      expect(fits.single.exponent, closeTo(3, 1e-6));
    });
  });

  group('sample spacing', () {
    test('RMSE falls as grid spacing shrinks, noise at 0', () {
      final List<HmSpacingSeries> series = runHmSpacingExperiment(
        HmFloor(),
        const HmSettings(),
        const HmNoise(),
      );
      expect(series, hasLength(1));
      final List<double> rmse = series.single.rmseDb;
      // kHmExperimentSpacings runs 1, 2, 3, 5, 7, 10 m: each wider spacing
      // scores no better than the one before it.
      for (int i = 1; i < rmse.length; i++) {
        expect(rmse[i], greaterThan(rmse[i - 1]), reason: 'spacing $i');
      }
    });

    test('with noise, averaging lowers the error at tight spacing', () {
      final List<HmSpacingSeries> series = runHmSpacingExperiment(
        HmFloor(),
        const HmSettings(),
        const HmNoise(sigmaDb: 6, averaging: 16, seed: 2),
      );
      expect(series, hasLength(3));
      // At 1 m spacing, raw noise dominates; averaging brings it back down.
      expect(series[1].rmseDb.first, greaterThan(series[0].rmseDb.first));
      expect(series[2].rmseDb.first, lessThan(series[1].rmseDb.first));
    });

    test('averaging shrinks the noise by sqrt(count)', () {
      const HmNoise n = HmNoise(sigmaDb: 6, averaging: 36);
      expect(n.effectiveSigmaDb, closeTo(1, 1e-12));
      final HmFloor f = _lineFloor();
      final List<HmPoint> pts = <HmPoint>[
        for (int i = 0; i < 2000; i++) (x: 20, y: 12.5),
      ];
      double spread(HmNoise noise) {
        final List<HmSample> s = takeHmSamples(f, pts, noise);
        final double t = s.first.truthDbm;
        double ss = 0;
        for (final HmSample x in s) {
          ss += (x.dbm - t) * (x.dbm - t);
        }
        return math.sqrt(ss / s.length);
      }

      expect(spread(const HmNoise(sigmaDb: 6)), closeTo(6, 0.4));
      expect(spread(const HmNoise(sigmaDb: 6, averaging: 36)), closeTo(1, 0.1));
    });
  });

  group('determinism', () {
    test('same seed, same map; another seed, another map', () {
      final HmFloor f = HmFloor();
      final List<HmPoint> pts = hmGridPoints(f, 4);
      const HmNoise a = HmNoise(sigmaDb: 5, seed: 9);
      final HmMap m1 = buildHmMap(
        f,
        takeHmSamples(f, pts, a),
        const HmSettings(),
      );
      final HmMap m2 = buildHmMap(
        f,
        takeHmSamples(f, pts, a),
        const HmSettings(),
      );
      expect(m1.rmseDb, m2.rmseDb);
      final HmMap m3 = buildHmMap(
        f,
        takeHmSamples(f, pts, a.copyWith(seed: 10)),
        const HmSettings(),
      );
      expect(m3.rmseDb, isNot(m1.rmseDb));
    });

    test('adding a sample does not re-roll the others', () {
      final HmFloor f = HmFloor();
      const HmNoise n = HmNoise(sigmaDb: 5, seed: 4);
      final List<HmSample> a = takeHmSamples(f, const <HmPoint>[
        (x: 3, y: 3),
        (x: 9, y: 9),
      ], n);
      final List<HmSample> b = takeHmSamples(f, const <HmPoint>[
        (x: 3, y: 3),
        (x: 9, y: 9),
        (x: 20, y: 20),
      ], n);
      expect(b[0].dbm, a[0].dbm);
      expect(b[1].dbm, a[1].dbm);
    });
  });

  group('floor', () {
    test('a wall is charged only when crossed', () {
      final HmFloor f = _lineFloor(
        walls: const <HmWall>[
          HmWall(a: (x: 10, y: 0), b: (x: 10, y: 25), lossDb: 12),
        ],
      );
      final HmFloor open = _lineFloor();
      expect(
        open.truthDbm((x: 15, y: 12.5)) - f.truthDbm((x: 15, y: 12.5)),
        closeTo(12, 1e-9),
      );
      expect(f.truthDbm((x: 8, y: 12.5)), open.truthDbm((x: 8, y: 12.5)));
    });

    test('the default floor has one hidden wall and every preset stays on '
        'the floor', () {
      final HmFloor f = HmFloor();
      expect(f.walls.where((HmWall w) => w.hidden), hasLength(1));
      for (int n = kHmMinAps; n <= kHmMaxAps; n++) {
        final HmFloor g = f.copyWith(aps: defaultHmAps(n));
        expect(g.aps, hasLength(n));
        for (final HmPoint p in <HmPoint>[
          ...hmThreeDotPoints(g),
          ...hmGridPoints(g, 1),
          ...hmWalkPoints(g, 10),
        ]) {
          expect(g.contains(p), isTrue);
        }
      }
    });
  });
}
