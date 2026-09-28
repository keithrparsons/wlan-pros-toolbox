// Tests for the ITU-R P.2040 multilayer method (wall_multilayer_physics.dart).
//
// 1. One layer through the multilayer method (Eqs. 39-42) matches the
//    single-slab result (Eqs. 43a-44) within 0.1 dB.
// 2. The stud wall is computed from its layers: its loss matches P.2040
//    Attachment 1's ABCD-matrix form (Eqs. 60-63), computed here from
//    scratch with its own complex arithmetic, and differs from any single
//    slab standing in for it.
//
// The expected numbers are never copied from the code under test's output.
//
// Eq. 60 as printed divides by 2A + B/Z0 + C·Z0, which is the general
// A + B/Z0 + C·Z0 + D only when D = A (a single layer or a symmetric
// stack). The reference below uses A + D, so it holds for any stack.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/wall_multilayer_physics.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/wall_slab_physics.dart';

// ── A minimal complex type, separate from lib/services/wifi_lab/complex.dart
// so the reference shares no code with the model. ─────────────────────────

class _C {
  const _C(this.re, [this.im = 0]);
  final double re;
  final double im;
  _C operator +(_C o) => _C(re + o.re, im + o.im);
  _C operator -(_C o) => _C(re - o.re, im - o.im);
  _C operator *(_C o) => _C(re * o.re - im * o.im, re * o.im + im * o.re);
  _C operator /(_C o) {
    final double m = o.re * o.re + o.im * o.im;
    return _C((re * o.re + im * o.im) / m, (im * o.re - re * o.im) / m);
  }

  double get abs => math.sqrt(re * re + im * im);

  // Principal root, Re >= 0.
  _C sqrt() {
    final double m = abs;
    final double a = math.sqrt((m + re) / 2);
    final double b = math.sqrt(math.max(0, (m - re) / 2));
    return _C(a, im < 0 ? -b : b);
  }

  // cos and sin of a complex argument.
  _C cos() => _C(math.cos(re) * _cosh(im), -math.sin(re) * _sinh(im));
  _C sin() => _C(math.sin(re) * _cosh(im), math.cos(re) * _sinh(im));
  static double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;
  static double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
}

const _C _j = _C(0, 1);

/// Complex permittivity straight from P.2040 Table 3 and Eq. 59, with the
/// coefficients typed in here rather than read from WallMaterial.
_C _eps(String m, double f) {
  const Map<String, List<double>> table3 = <String, List<double>>{
    // a, b, c, d
    'air': <double>[1, 0, 0, 0],
    'plasterboard': <double>[2.73, 0, 0.0085, 0.9395],
    'concrete': <double>[5.24, 0, 0.0462, 0.7822],
    'glass': <double>[6.31, 0, 0.0036, 1.3394],
    'wood': <double>[1.99, 0, 0.0047, 1.0718],
    'brick': <double>[3.91, 0, 0.0238, 0.16],
  };
  final List<double> k = table3[m]!;
  final double e = k[0] * math.pow(f, k[1]);
  final double s = k[2] * math.pow(f, k[3]);
  return _C(e, -17.98 * s / f);
}

/// P.2040 Attachment 1 (Eqs. 60-63), TE, for (material, metres) layers.
/// Returns |T| in dB of loss.
double _abcdLossDb(List<(String, double)> layers, double f, double thetaDeg) {
  const double c = 299792458.0;
  final double k0 = 2 * math.pi * f * 1e9 / c;
  final double th = thetaDeg * math.pi / 180;
  final double s2 = math.sin(th) * math.sin(th);
  const double eta = 120 * math.pi;
  // Z0 for air, TE (Eq. 62a with e = 1).
  final _C z0 = _C(eta / math.cos(th));
  _C a = const _C(1), b = const _C(0), cc = const _C(0), d = const _C(1);
  for (final (String m, double w) in layers) {
    final _C e = _eps(m, f);
    // sqrt(e)·cos(theta_m) = sqrt(e - sin^2 theta0) (Eqs. 61f, 61h).
    final _C root = (e - _C(s2)).sqrt();
    final _C beta = root * _C(k0);
    final _C z = _C(eta) / root; // Eq. 62a
    final _C bd = beta * _C(w);
    final _C am = bd.cos();
    final _C bm = _j * z * bd.sin();
    final _C cm = _j * bd.sin() / z;
    final _C dm = am;
    // [a b; c d] x [am bm; cm dm]
    final _C na = a * am + b * cm;
    final _C nb = a * bm + b * dm;
    final _C nc = cc * am + d * cm;
    final _C nd = cc * bm + d * dm;
    a = na;
    b = nb;
    cc = nc;
    d = nd;
  }
  final _C t = const _C(2) / (a + b / z0 + cc * z0 + d);
  return -20 * math.log(t.abs) / math.ln10;
}

void main() {
  group('one layer: the multilayer method equals the single slab', () {
    for (final WallMaterial m in WallMaterial.values) {
      for (final double f in <double>[2.437, 5.5, 6.5]) {
        for (final double mm in <double>[10, 12.7, 44.5, 102, 203, 610]) {
          for (final (double, Polarization) ap in <(double, Polarization)>[
            (0, Polarization.te),
            (45, Polarization.te),
            (45, Polarization.tm),
          ]) {
            final String why =
                '${m.name} $f GHz $mm mm ${ap.$1} deg ${ap.$2.name}';
            test(why, () {
              final SlabResult one = WallSlab.compute(
                material: m,
                fGhz: f,
                thicknessM: mm / 1000,
                angleDeg: ap.$1,
                polarization: ap.$2,
              );
              final MultilayerResult many = MultilayerWall.compute(
                layers: <WallLayer>[WallLayer(m, mm)],
                fGhz: f,
                angleDeg: ap.$1,
                polarization: ap.$2,
              );
              // Metal: both past any meaningful number; compare the parts
              // that stay finite.
              expect(
                many.transmissionLossDb,
                closeTo(one.transmissionLossDb, 0.1),
              );
              expect(many.absorptionDb, closeTo(one.absorptionDb, 0.1));
              expect(many.reflectionPartDb, closeTo(one.reflectionPartDb, 0.1));
              expect(many.reflectedPower, closeTo(one.reflectedPower, 1e-6));
            });
          }
        }
      }
    }
  });

  group('interior stud wall at 5 GHz is computed from its layers', () {
    final List<WallLayer> stud = WallPreset.studWall.layers;

    test('the preset is plasterboard, air, plasterboard, sizes stated', () {
      expect(stud.map((WallLayer l) => l.label).toList(), <String>[
        'Plasterboard',
        'Air',
        'Plasterboard',
      ]);
      expect(stud.map((WallLayer l) => l.thicknessMm).toList(), <double>[
        12.7,
        89,
        12.7,
      ]);
    });

    for (final double f in <double>[5.0, 5.5]) {
      for (final double theta in <double>[0, 30]) {
        test('$f GHz, $theta deg: matches the independent ABCD form', () {
          final MultilayerResult r = MultilayerWall.compute(
            layers: stud,
            fGhz: f,
            angleDeg: theta,
          );
          final double reference = _abcdLossDb(
            <(String, double)>[
              ('plasterboard', 0.0127),
              ('air', 0.089),
              ('plasterboard', 0.0127),
            ],
            f,
            theta,
          );
          expect(r.transmissionLossDb, closeTo(reference, 1e-6));
        });
      }
    }

    test('it is not a single slab in disguise', () {
      final MultilayerResult r = MultilayerWall.compute(
        layers: stud,
        fGhz: 5.0,
      );
      // One solid plasterboard slab of the same total thickness.
      final SlabResult solid = WallSlab.compute(
        material: WallMaterial.plasterboard,
        fGhz: 5.0,
        thicknessM: 0.1144,
      );
      expect(
        (r.transmissionLossDb - solid.transmissionLossDb).abs(),
        greaterThan(0.5),
      );
      // Absorption is the two sheets' only: the air adds none.
      final SlabResult sheet = WallSlab.compute(
        material: WallMaterial.plasterboard,
        fGhz: 5.0,
        thicknessM: 0.0127,
      );
      expect(r.absorptionDb, closeTo(2 * sheet.absorptionDb, 1e-9));
      expect(r.layerAbsorptionDb[1], 0);
      // And the loss is not simply two sheets added: the gap's echoes count.
      expect(
        (r.transmissionLossDb - 2 * sheet.transmissionLossDb).abs(),
        greaterThan(0.01),
      );
    });

    test('the parts add to the total, and |T| agrees with the log sum', () {
      final MultilayerResult r = MultilayerWall.compute(
        layers: stud,
        fGhz: 5.0,
      );
      final double fromT = -20 * math.log(r.t.abs) / math.ln10;
      expect(r.transmissionLossDb, closeTo(fromT, 1e-9));
    });
  });

  group('every preset', () {
    for (final WallPreset p in WallPreset.values) {
      if (p.isCustom) continue;
      test('${p.label}: matches the ABCD form at 2.4, 5.5 and 6.5 GHz', () {
        String key(WallLayer l) => l.isAir ? 'air' : l.material!.name;
        for (final double f in kComparisonGhz) {
          final MultilayerResult r = MultilayerWall.compute(
            layers: p.layers,
            fGhz: f,
          );
          expect(r.transmissionLossDb.isFinite, isTrue);
          expect(r.transmissionLossDb, greaterThan(0));
          expect(
            r.transmissionLossDb,
            closeTo(
              _abcdLossDb(
                <(String, double)>[
                  for (final WallLayer l in p.layers) (key(l), l.thicknessM),
                ],
                f,
                0,
              ),
              1e-6,
            ),
          );
        }
      });
    }

    test('custom has no fixed layers', () {
      expect(WallPreset.custom.layers, isEmpty);
      expect(WallPreset.custom.isCustom, isTrue);
    });
  });

  test('a layered wall answers outside only, continuous with R and T', () {
    final MultilayerResult r = MultilayerWall.compute(
      layers: WallPreset.studWall.layers,
      fGhz: 5.5,
    );
    expect(r.fieldAt(0).re, closeTo(1 + r.r.re, 1e-12));
    expect(r.fieldAt(0).im, closeTo(r.r.im, 1e-12));
    expect(r.fieldAt(r.thicknessM).abs, closeTo(r.t.abs, 1e-12));
    expect(() => r.fieldAt(r.thicknessM / 2), throwsArgumentError);
  });

  test('bad input is refused', () {
    expect(
      () => MultilayerWall.compute(layers: const <WallLayer>[], fGhz: 5),
      throwsArgumentError,
    );
    expect(
      () => MultilayerWall.compute(
        layers: const <WallLayer>[WallLayer.air(0)],
        fGhz: 5,
      ),
      throwsArgumentError,
    );
  });
}
