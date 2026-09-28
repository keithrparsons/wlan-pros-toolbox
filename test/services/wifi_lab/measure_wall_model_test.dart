// Pins the teaching claims of How to Measure Wall Attenuation (measure-wall).
//
// The error term: measured = wall + 20 log10(far / near) + fading residual,
// the error shrinks with a far source and close readings, it does not depend
// on frequency, and the predict-then-reveal scene (source 2 m from the wall,
// readings 1 m either side) reads 20 log10(3/1) = 9.54 dB too high.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/fspl_math.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/measure_wall_model.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/wall_slab_physics.dart';

double _log10(double x) => math.log(x) / math.ln10;

void main() {
  group('error term formula', () {
    test('errorTermDb is 20 log10(far / near)', () {
      expect(MwMath.errorTermDb(1, 10), closeTo(20, 1e-12));
      expect(MwMath.errorTermDb(2, 4), closeTo(20 * _log10(2), 1e-12));
      expect(MwMath.errorTermDb(3, 3), 0);
    });

    test('symmetric form is 20 log10((D + a) / (D - a))', () {
      for (final (double d, double a) in <(double, double)>[
        (4, 0.1),
        (4, 1),
        (2, 1),
        (15, 0.05),
        (1, 0.5),
      ]) {
        expect(
          MwMath.symmetricErrorDb(d, a),
          closeTo(20 * _log10((d + a) / (d - a)), 1e-12),
          reason: 'D $d, a $a',
        );
      }
    });

    test('geometry form adds the wall thickness to the far distance', () {
      expect(
        MwMath.geometryErrorDb(
          sourceToWallM: 4,
          nearGapM: 1,
          farGapM: 1,
          thicknessM: 0.102,
        ),
        closeTo(20 * _log10(5.102 / 3), 1e-12),
      );
      expect(
        MwMath.geometryErrorDb(sourceToWallM: 4, nearGapM: 1, farGapM: 1),
        MwMath.symmetricErrorDb(4, 1),
      );
    });

    test('the config computes it from FsplMath and it matches the formula', () {
      final MwConfig c = MwConfig(
        sourceToWallM: 4,
        nearGapM: 0.7,
        farGapM: 1.3,
        thicknessM: 0.2,
      );
      expect(
        c.geometryErrorDb,
        closeTo(
          MwMath.geometryErrorDb(
            sourceToWallM: 4,
            nearGapM: 0.7,
            farGapM: 1.3,
            thicknessM: 0.2,
          ),
          1e-9,
        ),
      );
    });

    test('the error does not depend on frequency', () {
      final List<double> e = <double>[
        for (final WifiBand b in WifiBand.values)
          MwConfig(band: b, nearGapM: 0.5, farGapM: 0.5).geometryErrorDb,
      ];
      expect(e[1], closeTo(e[0], 1e-9));
      expect(e[2], closeTo(e[0], 1e-9));
    });
  });

  group('the brief\'s teaching claims', () {
    test('D = 4 m, readings 0.1 m from the wall: error under 0.5 dB', () {
      final double e = MwMath.symmetricErrorDb(4, 0.1);
      expect(e, lessThan(0.5));
      expect(e, closeTo(20 * _log10(4.1 / 3.9), 1e-12)); // 0.434 dB
      final MwConfig c = MwConfig(
        sourceToWallM: 4,
        nearGapM: 0.1,
        farGapM: 0.1,
        thicknessM: 0,
      );
      expect(c.geometryErrorDb, lessThan(0.5));
    });

    test('a real wall thickness adds to it: 10.2 cm of concrete makes the '
        'same readings 0.64 dB', () {
      final MwConfig c = MwConfig(
        sourceToWallM: 4,
        nearGapM: 0.1,
        farGapM: 0.1,
        thicknessM: 0.102,
      );
      expect(c.geometryErrorDb, closeTo(20 * _log10(4.202 / 3.9), 1e-9));
      expect(c.geometryErrorDb, closeTo(0.647, 0.001));
    });

    test('predict-then-reveal: source 2 m, readings 1 m either side reads '
        'too high by 20 log10(3/1) = 9.54 dB', () {
      expect(MwPredict.thinWallErrorDb, closeTo(20 * _log10(3), 1e-12));
      expect(MwPredict.thinWallErrorDb, closeTo(9.542, 0.001));
      final MwConfig c = MwConfig(
        sourceToWallM: MwPredict.sourceToWallM,
        nearGapM: MwPredict.gapM,
        farGapM: MwPredict.gapM,
        thicknessM: 0,
        spreadDb: 0,
      );
      expect(c.measuredDb! - c.trueWallDb, closeTo(9.542, 0.001));
      expect(c.measuredDb!, greaterThan(c.trueWallDb));
    });

    test('the error shrinks as the source moves away and as the readings '
        'close in', () {
      double prev = double.infinity;
      for (final double d in <double>[1, 2, 4, 8, 15]) {
        final double e = MwMath.symmetricErrorDb(d, 0.5);
        expect(e, lessThan(prev), reason: 'D $d');
        prev = e;
      }
      prev = double.infinity;
      for (final double a in <double>[1, 0.5, 0.25, 0.1, 0.05]) {
        final double e = MwMath.symmetricErrorDb(4, a);
        expect(e, lessThan(prev), reason: 'a $a');
        prev = e;
      }
    });

    test('the free-space curve is steep near the source', () {
      expect(MwMath.fsplSlopeDbPerM(1), closeTo(8.686, 0.001));
      expect(MwMath.fsplSlopeDbPerM(4), closeTo(2.171, 0.001));
    });
  });

  group('measurement', () {
    test('with no spread, measured = true wall + geometry error exactly', () {
      final MwConfig c = MwConfig(spreadDb: 0);
      expect(c.fadingResidualDb, closeTo(0, 1e-9));
      expect(c.measuredDb, closeTo(c.trueWallDb + c.geometryErrorDb, 1e-9));
    });

    test('with spread, measured = true + geometry + fading residual, and the '
        'residual is what the averages left', () {
      final MwConfig c = MwConfig(spreadDb: 3, samplesPerSide: 7);
      expect(
        c.measuredDb,
        closeTo(c.trueWallDb + c.geometryErrorDb + c.fadingResidualDb, 1e-9),
      );
      expect(c.nearSeries.samplesDbm, hasLength(7));
      expect(c.farSeries.samplesDbm, hasLength(7));
      final double avg =
          c.nearSeries.samplesDbm.reduce((double a, double b) => a + b) / 7;
      expect(c.nearSeries.averageDbm, closeTo(avg, 1e-12));
    });

    test('the true wall is Wi-Fi Through a Wall\'s P.2040 result', () {
      final MwConfig c = MwConfig(
        band: WifiBand.band6,
        material: WallMaterial.brick,
        thicknessM: 0.089,
      );
      expect(c.channel, 117);
      expect(
        c.trueWallDb,
        WallSlab.compute(
          material: WallMaterial.brick,
          fGhz: c.freqMHz / 1000,
          thicknessM: 0.089,
        ).transmissionLossDb,
      );
    });

    test('levels are 20 dBm minus FSPL, and minus the wall behind it', () {
      final MwConfig c = MwConfig();
      final double f = c.freqMHz.toDouble();
      expect(c.levelAtDbm(3), closeTo(20 - FsplMath.fsplDb(3, f), 1e-12));
      expect(
        c.levelAtDbm(5.2),
        closeTo(20 - FsplMath.fsplDb(5.2, f) - c.trueWallDb, 1e-12),
      );
    });

    test('same seeds, same readings; a retake changes only that side', () {
      final MwConfig a = MwConfig(spreadDb: 2);
      final MwConfig b = MwConfig(spreadDb: 2);
      expect(a.nearSeries.samplesDbm, b.nearSeries.samplesDbm);
      final MwConfig r = a.retake();
      expect(r.side, MwSide.near);
      expect(r.nearSeries.samplesDbm, isNot(a.nearSeries.samplesDbm));
      expect(r.farSeries.samplesDbm, a.farSeries.samplesDbm);
      expect(r.nearSeed, isNot(r.farSeed));
    });

    test('a far side under the noise floor has no measurement', () {
      final MwConfig c = MwConfig(
        band: WifiBand.band6,
        material: WallMaterial.metal,
        thicknessM: 0.01,
      );
      expect(c.farBelowFloor, isTrue);
      expect(c.measuredDb, isNull);
      expect(c.totalErrorDb, isNull);
    });

    test('more readings pull the average toward the model', () {
      double spreadOfMeans(int n) {
        double s = 0;
        for (int seed = 1; seed <= 200; seed++) {
          final List<double> z = MwConfig.gaussians(seed, n);
          final double m = z.reduce((double a, double b) => a + b) / n;
          s += m * m;
        }
        return math.sqrt(s / 200);
      }

      expect(spreadOfMeans(1), closeTo(1, 0.2));
      expect(spreadOfMeans(25), lessThan(0.3));
    });
  });

  group('geometry bounds', () {
    test('the near reading stays at least 0.1 m from the source', () {
      final MwConfig c = MwConfig(sourceToWallM: 1, nearGapM: 5);
      expect(c.nearDistM, closeTo(0.1, 1e-12));
      expect(c.nearGapM, closeTo(0.9, 1e-12));
      final MwConfig s = MwConfig(sourceToWallM: 0.5, nearGapM: 0.45);
      expect(s.nearDistM, greaterThanOrEqualTo(0.1 - 1e-12));
    });

    test('source distance is held to 0.5 to 15 m', () {
      expect(MwConfig(sourceToWallM: 0.1).sourceToWallM, 0.5);
      expect(MwConfig(sourceToWallM: 40).sourceToWallM, 15);
      expect(MwConfig().sourceToWallM, 4);
    });

    test('moving the laptop crosses the wall at a face', () {
      MwConfig c = MwConfig(nearGapM: 0.15);
      c = c.moveLaptopBy(0.1);
      expect(c.side, MwSide.near);
      expect(c.nearGapM, closeTo(0.05, 1e-9));
      c = c.moveLaptopBy(0.1);
      expect(c.side, MwSide.far);
      expect(c.farGapM, MwConfig.minGapM);
      c = c.moveLaptopBy(0.3);
      expect(c.farGapM, closeTo(0.35, 1e-9));
      c = c.moveLaptopBy(-0.4);
      expect(c.side, MwSide.near);
    });

    test('placing the laptop by distance picks the side', () {
      final MwConfig c = MwConfig(thicknessM: 0.2);
      expect(c.withLaptopAt(3.5).side, MwSide.near);
      expect(c.withLaptopAt(3.5).nearGapM, closeTo(0.5, 1e-9));
      expect(c.withLaptopAt(4.05).side, MwSide.near);
      expect(c.withLaptopAt(4.15).side, MwSide.far);
      expect(c.withLaptopAt(5.2).farGapM, closeTo(1.0, 1e-9));
    });
  });
}
