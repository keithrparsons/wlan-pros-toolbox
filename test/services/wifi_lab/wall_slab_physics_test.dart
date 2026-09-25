// Tests for the Wi-Fi Lab wall slab physics (ITU-R P.2040-4, clean-room).
//
// Spec 12 "Done means": Eq. 27a attenuation for concrete within 2 dB/m of
// Pax's hand figures (65/125/143 dB/m at 2.4/5.5/6.5 GHz); zero thickness
// gives T = 1, R = 0; a lossless half-wave slab gives R ~ 0 at normal
// incidence; metal gives |R| ~ 1 with no NaN; TE = TM at normal incidence;
// |R|^2 + |T|^2 <= 1 for lossy and = 1 for lossless.
//
// Pax's slab-loss table (concrete 102 mm 8.1/14.2/16.0 dB; plasterboard
// 12.7 mm 1.1/1.0/0.7 dB) is a hand calculation, so it is REPORTED against
// the computed values below, not asserted. The computed values are pinned
// here once measured, so a later edit to the engine cannot move them
// silently.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/complex.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/wall_slab_physics.dart';

SlabResult _slab(
  WallMaterial m,
  double fGhz,
  double mm, {
  double angle = 0,
  Polarization pol = Polarization.te,
}) => WallSlab.compute(
  material: m,
  fGhz: fGhz,
  thicknessM: mm / 1000,
  angleDeg: angle,
  polarization: pol,
);

void main() {
  group('Table 3 transcription', () {
    test('ten materials, each valid across 2.4 to 7.125 GHz', () {
      expect(WallMaterial.values, hasLength(10));
      for (final WallMaterial m in WallMaterial.values) {
        expect(m.isValidAt(2.4), isTrue, reason: m.label);
        expect(m.isValidAt(7.125), isTrue, reason: m.label);
      }
    });

    test('concrete e\' and sigma at 2.4 GHz', () {
      final MaterialProperties p = MaterialProperties.of(
        WallMaterial.concrete,
        2.4,
      );
      expect(p.epsReal, 5.24);
      expect(p.sigma, closeTo(0.0462 * math.pow(2.4, 0.7822), 1e-12));
      expect(p.epsComplex.im, closeTo(-17.98 * p.sigma / 2.4, 1e-12));
    });
  });

  group('Eq. 27a attenuation rate, concrete (Pax: 65/125/143 dB/m)', () {
    final Map<double, double> pax = <double, double>{
      2.4: 65,
      5.5: 125,
      6.5: 143,
    };
    for (final MapEntry<double, double> e in pax.entries) {
      test('${e.key} GHz within 2 dB/m of ${e.value}', () {
        final double a = MaterialProperties.of(
          WallMaterial.concrete,
          e.key,
        ).attenuationEq27a;
        expect(a, closeTo(e.value, 2));
      });
    }

    test('Eq. 27a tracks the exact complex-index rate when tan d < 0.5', () {
      final MaterialProperties p = MaterialProperties.of(
        WallMaterial.concrete,
        5.5,
      );
      expect(p.eq27aValid, isTrue);
      expect(p.attenuationEq27a, closeTo(p.attenuationExact, 0.01 * 125));
    });

    test('plywood at 2.4 GHz is OUTSIDE Eq. 27a (tan d > 0.5)', () {
      // Brief §6.3 says the tan d < 0.5 condition holds for every Table 3
      // dielectric. Plywood's frequency-flat sigma = 0.33 breaks it at 2.4.
      final MaterialProperties p = MaterialProperties.of(
        WallMaterial.plywood,
        2.4,
      );
      expect(p.lossTangent, greaterThan(0.5));
      expect(p.eq27aValid, isFalse);
      expect(
        MaterialProperties.of(WallMaterial.plywood, 6.5).eq27aValid,
        isTrue,
      );
    });
  });

  group('wavelength', () {
    test('brief §6.3: concrete at 6.5 GHz has lambda about 2.0 cm inside', () {
      final MaterialProperties p = MaterialProperties.of(
        WallMaterial.concrete,
        6.5,
      );
      expect(p.lambdaAir * 100, closeTo(4.61, 0.01));
      expect(p.lambdaInMaterial * 100, closeTo(2.0, 0.05));
    });
  });

  group('zero thickness: T = 1, R = 0', () {
    for (final WallMaterial m in WallMaterial.values) {
      test(m.label, () {
        for (final Polarization pol in Polarization.values) {
          final SlabResult s = _slab(m, 5.5, 0, angle: 30, pol: pol);
          expect(s.r.abs, 0);
          expect(s.t.re, 1);
          expect(s.t.im, 0);
          expect(s.transmissionLossDb, 0);
        }
      });
    }

    test('a vanishingly thin wall approaches the same limit', () {
      final SlabResult s = _slab(WallMaterial.concrete, 2.4, 1e-6);
      expect(s.r.abs, lessThan(1e-3));
      expect(s.t.abs, closeTo(1, 1e-3));
    });
  });

  group('lossless half-wave slab: R ~ 0 at normal incidence', () {
    for (final double eps in <double>[2.73, 6.31, 7.074]) {
      test('e\' = $eps at 5.5 GHz', () {
        final MaterialProperties p = MaterialProperties(
          material: WallMaterial.glass,
          fGhz: 5.5,
          epsReal: eps,
          sigma: 0,
        );
        final double d = p.lambdaAir / (2 * math.sqrt(eps));
        final SlabResult s = WallSlab.computeFor(props: p, thicknessM: d);
        expect(s.interfaceR.abs, greaterThan(0.2), reason: 'faces do reflect');
        expect(s.r.abs, lessThan(1e-9));
        expect(s.t.abs, closeTo(1, 1e-9));
      });
    }
  });

  group('metal: |R| ~ 1, no NaN, no overflow', () {
    for (final double f in <double>[2.4, 5.5, 6.5]) {
      for (final double mm in <double>[0.1, 1, 47, 500]) {
        for (final Polarization pol in Polarization.values) {
          test('$f GHz, $mm mm, ${pol.name}, 0 and 80 deg', () {
            for (final double ang in <double>[0, 80]) {
              final SlabResult s = _slab(
                WallMaterial.metal,
                f,
                mm,
                angle: ang,
                pol: pol,
              );
              expect(s.r.isFinite, isTrue);
              expect(s.t.isFinite, isTrue);
              // TM at 80 degrees loses a little to the metal's surface
              // resistance (|R| ~ 0.9985); still total reflection in dB.
              expect(s.r.abs, closeTo(1, 2e-3));
              expect(s.reflectionDb, greaterThan(-0.02));
              expect(s.transmissionLossDb.isFinite, isTrue);
              expect(s.transmissionLossDb, greaterThan(150));
              for (final double x in <double>[-0.05, 0, mm / 2000, 1]) {
                expect(s.fieldAt(x).isFinite, isTrue, reason: 'x = $x');
              }
            }
          });
        }
      }
    }
  });

  group('TE equals TM at normal incidence', () {
    for (final WallMaterial m in WallMaterial.values) {
      test(m.label, () {
        final SlabResult te = _slab(m, 6.5, 102, pol: Polarization.te);
        final SlabResult tm = _slab(m, 6.5, 102, pol: Polarization.tm);
        // Eq. 37b is written for the H-field ratio, so at 0 degrees
        // R'_TM = -R'_TE: the same wave with the opposite sign convention.
        // Everything physical agrees: |R|, T (which depends on R'^2 only),
        // the loss, and the drawn tangential E field.
        expect(tm.interfaceR.re, closeTo(-te.interfaceR.re, 1e-12));
        expect(tm.interfaceR.im, closeTo(-te.interfaceR.im, 1e-12));
        expect(tm.r.abs, closeTo(te.r.abs, 1e-12));
        expect(tm.t.re, closeTo(te.t.re, 1e-12));
        expect(tm.t.im, closeTo(te.t.im, 1e-12));
        expect(tm.transmissionLossDb, closeTo(te.transmissionLossDb, 1e-9));
        for (final double x in <double>[-0.03, 0.05, 0.2]) {
          final Complex a = te.fieldAt(x);
          final Complex b = tm.fieldAt(x);
          expect((a - b).abs, lessThan(1e-12), reason: 'x = $x');
        }
      });
    }

    test('and they differ at 60 degrees', () {
      final SlabResult te = _slab(WallMaterial.concrete, 5.5, 102, angle: 60);
      final SlabResult tm = _slab(
        WallMaterial.concrete,
        5.5,
        102,
        angle: 60,
        pol: Polarization.tm,
      );
      expect((te.reflectedPower - tm.reflectedPower).abs(), greaterThan(0.05));
    });
  });

  group('power balance', () {
    test('lossy: |R|^2 + |T|^2 <= 1 everywhere', () {
      for (final WallMaterial m in WallMaterial.values) {
        for (final double f in <double>[2.412, 5.5, 7.115]) {
          for (final double mm in <double>[1, 6, 12.7, 102, 500]) {
            for (final double ang in <double>[0, 45, 80]) {
              for (final Polarization pol in Polarization.values) {
                final SlabResult s = _slab(m, f, mm, angle: ang, pol: pol);
                expect(
                  s.reflectedPower + s.transmittedPower,
                  lessThanOrEqualTo(1 + 1e-12),
                  reason: '${m.label} $f GHz $mm mm $ang deg ${pol.name}',
                );
              }
            }
          }
        }
      }
    });

    test('lossless: |R|^2 + |T|^2 = 1', () {
      for (final double eps in <double>[1.48, 2.73, 6.31]) {
        for (final double mm in <double>[1, 6, 13, 102]) {
          for (final double ang in <double>[0, 30, 70]) {
            for (final Polarization pol in Polarization.values) {
              final SlabResult s = WallSlab.computeFor(
                props: MaterialProperties(
                  material: WallMaterial.glass,
                  fGhz: 5.5,
                  epsReal: eps,
                  sigma: 0,
                ),
                thicknessM: mm / 1000,
                angleDeg: ang,
                polarization: pol,
              );
              expect(
                s.reflectedPower + s.transmittedPower,
                closeTo(1, 1e-9),
                reason: 'eps $eps $mm mm $ang deg ${pol.name}',
              );
              expect(s.absorptionDb, closeTo(0, 1e-9));
            }
          }
        }
      }
    });

    test('total loss equals -10 log10 |T|^2 where |T|^2 is representable', () {
      for (final WallMaterial m in <WallMaterial>[
        WallMaterial.concrete,
        WallMaterial.glass,
        WallMaterial.plywood,
      ]) {
        final SlabResult s = _slab(m, 5.5, 102, angle: 20);
        final double direct = -10 * math.log(s.transmittedPower) / math.ln10;
        expect(s.transmissionLossDb, closeTo(direct, 1e-9));
      }
    });
  });

  group('field profile is continuous at both faces', () {
    for (final Polarization pol in Polarization.values) {
      test('concrete 102 mm, 5.5 GHz, 40 deg, ${pol.name}', () {
        final SlabResult s = _slab(
          WallMaterial.concrete,
          5.5,
          102,
          angle: 40,
          pol: pol,
        );
        const double h = 1e-9;
        final Complex f0a = s.fieldAt(-h);
        final Complex f0b = s.fieldAt(h);
        final Complex fda = s.fieldAt(0.102 - h);
        final Complex fdb = s.fieldAt(0.102 + h);
        expect((f0a - f0b).abs, lessThan(1e-6));
        expect((fda - fdb).abs, lessThan(1e-6));
        // At the face: 1 + R (tangential E, so R flips sign for TM). Just
        // behind: T.
        final Complex rE = pol == Polarization.tm ? -s.r : s.r;
        expect((s.fieldAt(-1e-15) - (Complex.one + rE)).abs, lessThan(1e-9));
        expect((fdb - s.t).abs, lessThan(1e-6));
      });
    }
  });

  group('the per-band story', () {
    test('concrete loses more at 6.5 than at 2.4 GHz', () {
      expect(
        _slab(WallMaterial.concrete, 6.5, 102).transmissionLossDb,
        greaterThan(_slab(WallMaterial.concrete, 2.4, 102).transmissionLossDb),
      );
    });

    test('13 mm glass passes 4.6 GHz better than 2.4 GHz (resonance)', () {
      expect(
        _slab(WallMaterial.glass, 4.6, 13).transmissionLossDb,
        lessThan(_slab(WallMaterial.glass, 2.4, 13).transmissionLossDb),
      );
    });

    test('plasterboard 12.7 mm loses LESS at 6.5 than at 2.4 GHz', () {
      expect(
        _slab(WallMaterial.plasterboard, 6.5, 12.7).transmissionLossDb,
        lessThan(
          _slab(WallMaterial.plasterboard, 2.4, 12.7).transmissionLossDb,
        ),
      );
    });
  });

  group('computed slab losses (pinned; Pax hand figures REPORTED only)', () {
    // Filled from the engine's own output on 2026-09-25 and pinned to
    // 0.05 dB. Pax's hand figures are in the trailing comments for the
    // report; they are not what this asserts.
    const Map<String, double> pinned = <String, double>{
      'concrete 102 @2.4': _c24, // Pax 8.1
      'concrete 102 @5.5': _c55, // Pax 14.2
      'concrete 102 @6.5': _c65, // Pax 16.0
      'plasterboard 12.7 @2.4': _p24, // Pax 1.1
      'plasterboard 12.7 @5.5': _p55, // Pax 1.0
      'plasterboard 12.7 @6.5': _p65, // Pax 0.7
    };
    for (final MapEntry<String, double> e in pinned.entries) {
      test(e.key, () {
        final List<String> parts = e.key.split(' ');
        final WallMaterial m = parts[0] == 'concrete'
            ? WallMaterial.concrete
            : WallMaterial.plasterboard;
        final double mm = double.parse(parts[1]);
        final double f = double.parse(parts[2].substring(1));
        final SlabResult s = _slab(m, f, mm);
        expect(s.transmissionLossDb, closeTo(e.value, 0.05));
      });
    }
  });

  group('measured data (brief §6.4)', () {
    test('3GPP rows reproduce the brief\'s printed values', () {
      final MeasuredSpecimen c = measuredFor(WallMaterial.concrete).firstWhere(
        (MeasuredSpecimen s) => s.source == MeasurementSource.threeGpp38901,
      );
      expect(c.points.map((MeasuredPoint p) => p.lossDb).toList(), <Matcher>[
        closeTo(14.6, 1e-9),
        closeTo(27.0, 1e-9),
        closeTo(31.0, 1e-9),
      ]);
    });

    test('no material without data claims any; the rest have some', () {
      expect(measuredFor(WallMaterial.ceilingBoard), isEmpty);
      expect(measuredFor(WallMaterial.chipboard), isEmpty);
      expect(measuredFor(WallMaterial.marble), isEmpty);
      for (final WallMaterial m in <WallMaterial>[
        WallMaterial.concrete,
        WallMaterial.brick,
        WallMaterial.plasterboard,
        WallMaterial.glass,
        WallMaterial.wood,
        WallMaterial.plywood,
        WallMaterial.metal,
      ]) {
        expect(measuredFor(m), isNotEmpty, reason: m.label);
      }
    });

    test('every NIST point sits outside NIST\'s 2.0-3.0 GHz gap', () {
      for (final MeasuredSpecimen s in kMeasuredSpecimens) {
        if (s.source != MeasurementSource.nist6055) continue;
        for (final MeasuredPoint p in s.points) {
          expect(p.fGhz <= 2.0 || p.fGhz >= 3.0, isTrue, reason: s.specimen);
        }
      }
    });
  });
}

// Pinned computed values (see the group above), measured 2026-09-25.
// Beside Pax's hand figures: concrete 8.09/14.27/15.97 vs 8.1/14.2/16.0;
// plasterboard 1.09/0.98/0.75 vs 1.1/1.0/0.7. Largest gap 0.07 dB.
const double _c24 = 8.09;
const double _c55 = 14.27;
const double _c65 = 15.97;
const double _p24 = 1.09;
const double _p55 = 0.98;
const double _p65 = 0.75;
