// Pins the Predict, Then Measure engine (Wi-Fi Classroom spec 32, "Done
// means"): deterministic with a seed; with true = predicted the Difference
// map is zero (noise off); a walk that stays on one side of a wall leaves it
// untested; a walk with samples on both sides estimates the true loss within
// 1 dB (noise off); "update model" makes the predicted map match the truth
// for every tested wall. Plus the scenario shape (6 to 12 walls, the spec's
// illustrative material defaults, two walls worse and one better by default)
// and the help entry's worked example.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/fspl_math.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/heat_map_builder_engine.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/predict_measure_engine.dart';

/// [m] with every true loss set to its predicted loss.
PmModel _honest(PmModel m) => m.copyWith(
  walls: <PmWall>[
    for (final PmWall w in m.walls) w.copyWith(trueLossDb: w.predictedLossDb),
  ],
);

double _maxAbs(Iterable<double> xs) =>
    xs.fold(0, (double a, double b) => math.max(a, b.abs()));

void main() {
  group('scenarios', () {
    test('each preset has 6 to 12 walls inside its floor', () {
      for (final PmPreset p in PmPreset.values) {
        final PmScenario s = pmScenario(p);
        expect(s.walls.length, inInclusiveRange(6, 12), reason: p.label);
        for (final PmWallSpec w in s.walls) {
          for (final HmPoint q in <HmPoint>[w.a, w.b]) {
            expect(q.x, inInclusiveRange(0, s.widthM), reason: p.label);
            expect(q.y, inInclusiveRange(0, s.depthM), reason: p.label);
          }
        }
      }
    });

    test('material defaults are the spec\'s illustrative values', () {
      expect(PmMaterial.drywall.defaultLossDb, 3);
      expect(PmMaterial.glass.defaultLossDb, 4);
      expect(PmMaterial.brick.defaultLossDb, 10);
      expect(PmMaterial.concrete.defaultLossDb, 15);
      expect(PmMaterial.elevatorShaft.defaultLossDb, 25);
    });

    test('the design opens at the material defaults', () {
      for (final PmPreset p in PmPreset.values) {
        final PmModel m = PmModel.fromScenario(pmScenario(p));
        for (final PmWall w in m.walls) {
          expect(w.predictedLossDb, w.material.defaultLossDb);
        }
      }
    });

    test('by default two walls are much worse than the design and one is '
        'better, for every preset and many seeds', () {
      for (final PmPreset p in PmPreset.values) {
        for (int seed = 1; seed <= 40; seed++) {
          final PmModel m = PmModel.fromScenario(pmScenario(p), seed: seed);
          final List<double> delta = <double>[
            for (final PmWall w in m.walls) w.trueLossDb - w.predictedLossDb,
          ];
          final int worse = delta.where((double d) => d >= 8).length;
          final int better = delta.where((double d) => d < 0).length;
          final int same = delta.where((double d) => d == 0).length;
          expect(worse, 2, reason: '${p.label} seed $seed');
          expect(better, 1, reason: '${p.label} seed $seed');
          expect(same, m.walls.length - 3, reason: '${p.label} seed $seed');
          for (final PmWall w in m.walls) {
            expect(w.trueLossDb, greaterThanOrEqualTo(1));
          }
        }
      }
    });

    test('deterministic with a seed: same seed, same truth; another seed, '
        'another truth', () {
      for (final PmPreset p in PmPreset.values) {
        final PmScenario s = pmScenario(p);
        expect(pmHiddenTruth(s, 5), pmHiddenTruth(s, 5));
        final Set<String> seen = <String>{
          for (int seed = 1; seed <= 6; seed++) pmHiddenTruth(s, seed).join(','),
        };
        expect(seen.length, greaterThan(1), reason: p.label);
      }
    });

    test('the default design looks fine and the default truth does not', () {
      for (final PmPreset p in PmPreset.values) {
        final PmModel m = PmModel.fromScenario(pmScenario(p));
        final PmMaps maps = buildPmMaps(m, PmSurvey.empty);
        expect(maps.predictedBelowTarget, lessThan(0.08), reason: p.label);
        expect(
          maps.truthBelowTarget - maps.predictedBelowTarget,
          greaterThan(0.05),
          reason: p.label,
        );
      }
    });
  });

  group('the walk', () {
    test('resample puts a sample every meter, keeping the start', () {
      final List<HmPoint> pts = pmResample(const <HmPoint>[
        (x: 0, y: 0),
        (x: 3, y: 0),
        (x: 3, y: 2.5),
      ]);
      expect(pts.first, (x: 0.0, y: 0.0));
      expect(pts, hasLength(7)); // 0,1,2,3 m along x; 1,2 m down; the end
      for (int i = 1; i < pts.length - 1; i++) {
        final double d = math.sqrt(
          math.pow(pts[i].x - pts[i - 1].x, 2) +
              math.pow(pts[i].y - pts[i - 1].y, 2),
        );
        expect(d, lessThanOrEqualTo(1 + 1e-9));
      }
      expect(pts.last, (x: 3.0, y: 2.5));
    });

    test('the same walk with the same noise seed reads the same', () {
      final PmModel m = PmModel.fromScenario(kPmOffice);
      const HmNoise n = HmNoise(sigmaDb: 4, seed: 9);
      final PmSurvey a = runPmSurvey(m, pmBothSidesWalk(m), noise: n);
      final PmSurvey b = runPmSurvey(m, pmBothSidesWalk(m), noise: n);
      expect(
        a.samples.map((HmSample s) => s.dbm).toList(),
        b.samples.map((HmSample s) => s.dbm).toList(),
      );
      expect(
        a.tests.values.map((PmWallTest t) => t.estimateDb).toList(),
        b.tests.values.map((PmWallTest t) => t.estimateDb).toList(),
      );
    });
  });

  group('Done means', () {
    test('with true = predicted for every wall, the Difference map is zero '
        '(noise off)', () {
      for (final PmPreset p in PmPreset.values) {
        final PmModel m = _honest(PmModel.fromScenario(pmScenario(p)));
        final List<List<HmPoint>> walk = <List<HmPoint>>[
          pmScenario(p).oneSideWalk,
          ...pmBothSidesWalk(m),
        ];
        final PmMaps maps = buildPmMaps(m, runPmSurvey(m, walk));
        final List<double> data = <double>[
          for (final double d in maps.difference)
            if (!d.isNaN) d,
        ];
        expect(data, isNotEmpty, reason: p.label);
        expect(_maxAbs(data), lessThan(1e-9), reason: p.label);
        expect(maps.diffOverShare, 0, reason: p.label);
        expect(maps.largestDiffDb!.abs(), lessThan(1e-9), reason: p.label);
      }
    });

    test('a walk that stays on one side of a wall leaves it untested', () {
      for (final PmPreset p in PmPreset.values) {
        final PmModel m = PmModel.fromScenario(pmScenario(p));
        final PmSurvey s = runPmSurvey(m, <List<HmPoint>>[
          pmScenario(p).oneSideWalk,
        ]);
        expect(s.samples, isNotEmpty, reason: p.label);
        expect(s.tests, isEmpty, reason: p.label);
      }
      // One wall, walked right up to on its AP side and along it, is still
      // untested: many samples, none on the far side.
      final PmModel m = PmModel.fromScenario(kPmOffice);
      const int wall = 9; // brick, (26,16)-(30,16)
      final PmSurvey s = runPmSurvey(m, <List<HmPoint>>[
        const <HmPoint>[(x: 25, y: 15.5), (x: 29.5, y: 15.5)],
      ]);
      expect(s.samples.length, greaterThan(3));
      expect(s.isTested(wall), isFalse);
    });

    test('a walk with samples on both sides estimates the true loss within '
        '1 dB (noise off)', () {
      for (final PmPreset p in PmPreset.values) {
        for (int seed = 1; seed <= 5; seed++) {
          final PmModel m = PmModel.fromScenario(pmScenario(p), seed: seed);
          final PmSurvey s = runPmSurvey(m, pmBothSidesWalk(m));
          expect(s.tests.length, m.walls.length, reason: p.label);
          for (final PmWallTest t in s.tests.values) {
            expect(
              (t.estimateDb - m.walls[t.wallIndex].trueLossDb).abs(),
              lessThan(1),
              reason: '${p.label} seed $seed W${t.wallIndex + 1}',
            );
          }
        }
      }
    });

    test('a single leg across one wall tests that wall only, and gets it '
        'right', () {
      final PmModel m = PmModel.fromScenario(kPmOffice);
      const int wall = 1; // glass, (9,0)-(9,7)
      final PmSurvey s = runPmSurvey(m, <List<HmPoint>>[
        const <HmPoint>[(x: 11, y: 4), (x: 7, y: 4)],
      ]);
      expect(s.tests.keys, <int>[wall]);
      expect(
        (s.tests[wall]!.estimateDb - m.walls[wall].trueLossDb).abs(),
        lessThan(1),
      );
    });

    test('"update model" makes the predicted map match the truth for all '
        'tested walls', () {
      for (final PmPreset p in PmPreset.values) {
        final PmModel m = PmModel.fromScenario(pmScenario(p));
        final PmSurvey s = runPmSurvey(m, pmBothSidesWalk(m));
        final PmModel updated = m.copyWith(walls: pmUpdateModel(m.walls, s));
        for (int i = 0; i < m.walls.length; i++) {
          expect(
            (updated.walls[i].predictedLossDb - m.walls[i].trueLossDb).abs(),
            lessThan(1e-6),
            reason: '${p.label} W${i + 1}',
          );
        }
        final PmMaps maps = buildPmMaps(updated, PmSurvey.empty);
        final double worst = _maxAbs(<double>[
          for (int i = 0; i < maps.cellCount; i++)
            maps.predicted[i] - maps.truth[i],
        ]);
        expect(worst, lessThan(1e-6), reason: p.label);
      }
    });

    test('"update model" changes tested walls only', () {
      final PmModel m = PmModel.fromScenario(kPmOffice);
      final PmSurvey s = runPmSurvey(m, <List<HmPoint>>[
        const <HmPoint>[(x: 11, y: 4), (x: 7, y: 4)],
      ]);
      final List<PmWall> u = pmUpdateModel(m.walls, s);
      for (int i = 0; i < m.walls.length; i++) {
        if (i == 1) {
          expect(u[i].predictedLossDb, closeTo(m.walls[i].trueLossDb, 1e-6));
        } else {
          expect(u[i].predictedLossDb, m.walls[i].predictedLossDb);
        }
      }
    });

    test('with noise on, estimates scatter but stay honest on average', () {
      final PmModel m = PmModel.fromScenario(kPmSchool);
      final PmSurvey s = runPmSurvey(
        m,
        pmBothSidesWalk(m),
        noise: const HmNoise(sigmaDb: 4, seed: 3),
      );
      double err = 0;
      for (final PmWallTest t in s.tests.values) {
        err += t.estimateDb - m.walls[t.wallIndex].trueLossDb;
      }
      expect((err / s.tests.length).abs(), lessThan(4));
      expect(
        s.tests.values.any(
          (PmWallTest t) =>
              (t.estimateDb - m.walls[t.wallIndex].trueLossDb).abs() > 0.1,
        ),
        isTrue,
      );
    });
  });

  group('maps and readouts', () {
    test('no walk: measured and difference are all no data', () {
      final PmModel m = PmModel.fromScenario(kPmOffice);
      final PmMaps maps = buildPmMaps(m, PmSurvey.empty);
      expect(maps.measured.every((double v) => v.isNaN), isTrue);
      expect(maps.difference.every((double v) => v.isNaN), isTrue);
      expect(maps.largestDiffDb, isNull);
      expect(maps.measuredShare, 0);
      expect(maps.diffOverShareOfMeasured, isNull);
    });

    test('a walk across a worse wall shows a difference over 5 dB', () {
      final PmModel m = PmModel.fromScenario(kPmOffice);
      final PmMaps maps = buildPmMaps(m, runPmSurvey(m, pmBothSidesWalk(m)));
      expect(maps.largestDiffDb, lessThan(-kPmDiffThresholdDb));
      expect(maps.diffOverShare, greaterThan(0));
      expect(maps.measuredShare, inExclusiveRange(0, 1));
    });

    test('the help entry\'s worked example matches the model', () {
      final double fspl1 = FsplMath.fsplDb(1, kPmFreqMHz);
      double pl(double d) => fspl1 + 10 * 2.8 * math.log(d) / math.ln10;
      final double near = kPmEirpDbm - pl(7.5);
      final double far = kPmEirpDbm - pl(8.5) - 16;
      expect(near, closeTo(-51.8, 0.05));
      expect(far, closeTo(-69.3, 0.05));
      expect(pl(8.5) - pl(7.5), closeTo(1.5, 0.05));
      expect(near - far - (pl(8.5) - pl(7.5)), closeTo(16, 1e-9));
      final String help = File('assets/help/tool_help.json').readAsStringSync();
      expect(help, contains('-51.8 dBm and the far one -69.3 dBm'));
    });
  });
}
