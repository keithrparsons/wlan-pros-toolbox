// Pins the Room Propagation model (lib/services/wifi_lab/
// room_propagation_model.dart) to the spec's "Done means" list and to the
// numbers in the research brief §6.3.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/complex.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/fspl_math.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/room_propagation_model.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/wall_slab_physics.dart';

const double _eirp = 20;

double _rxDbm(RoomEngine e, P2 p) => _eirp + e.report(p).coherentGainDb;

RoomEngine _engine(
  List<RoomWall> walls, {
  P2 ap = const P2(0, 0),
  double freqMHz = 2437,
  int order = 0,
  bool diffraction = false,
  Polarization pol = Polarization.te,
  bool exact = true,
}) => RoomEngine(
  walls: walls,
  ap: ap,
  radio: RoomRadio(
    freqMHz: freqMHz,
    reflectionOrder: order,
    diffraction: diffraction,
    polarization: pol,
  ),
  exactCoefficients: exact,
);

void main() {
  group('free space', () {
    for (final double f in <double>[2437, 5500, 6535]) {
      test('no walls: received = EIRP - FSPL within 0.1 dB at $f MHz', () {
        for (final int order in <int>[0, 1, 2]) {
          final RoomEngine e = _engine(
            const <RoomWall>[],
            freqMHz: f,
            order: order,
            diffraction: true,
          );
          for (final P2 p in const <P2>[P2(1, 0), P2(3, 4), P2(12, -7)]) {
            final double want = _eirp - FsplMath.fsplDb(p.length, f);
            expect(_rxDbm(e, p), closeTo(want, 0.1));
            expect(
              e.report(p).fsplDb,
              closeTo(FsplMath.fsplDb(p.length, f), 1e-9),
            );
          }
        }
      });
    }

    test('3D spreading: doubling the distance costs 6.02 dB', () {
      final RoomEngine e = _engine(const <RoomWall>[]);
      final double d = _rxDbm(e, const P2(4, 0)) - _rxDbm(e, const P2(8, 0));
      expect(d, closeTo(20 * math.log(2) / math.ln10, 1e-9));
    });
  });

  group('one wall between AP and client', () {
    for (final WallMaterial m in <WallMaterial>[
      WallMaterial.concrete,
      WallMaterial.plasterboard,
      WallMaterial.glass,
      WallMaterial.brick,
    ]) {
      for (final double f in <double>[2437, 6535]) {
        test('adds exactly the slab loss: ${m.label} at $f MHz', () {
          // A long wall on x = 3 between AP (0, 0) and client (6, 2.5).
          final RoomWall w = RoomWall(
            a: const P2(3, -500),
            b: const P2(3, 500),
            material: m,
            thicknessMm: m == WallMaterial.glass ? 6 : 102,
          );
          const P2 client = P2(6, 2.5);
          final double angle =
              math.atan2(client.y, client.x) * 180 / math.pi; // from normal
          final SlabResult slab = WallSlab.compute(
            material: m,
            fGhz: f / 1000,
            thicknessM: w.thicknessMm / 1000,
            angleDeg: angle,
          );
          // Reflections on: the only reflection returns to the AP's side,
          // so it cannot reach the client.
          final RoomEngine e = _engine(<RoomWall>[w], freqMHz: f, order: 2);
          final double free = _eirp - FsplMath.fsplDb(client.length, f);
          expect(
            free - _rxDbm(e, client),
            closeTo(slab.transmissionLossDb, 1e-9),
          );
          final PointReport r = e.report(client);
          expect(r.crossed, hasLength(1));
          expect(r.crossed.single.angleDeg, closeTo(angle, 1e-9));
          expect(
            r.crossed.single.lossDb,
            closeTo(slab.transmissionLossDb, 1e-9),
          );
          expect(r.wallLossDb, closeTo(slab.transmissionLossDb, 1e-9));
        });
      }
    }

    test(
      'the tabulated coefficients used by the grid agree within 0.01 dB',
      () {
        final RoomWall w = RoomWall(
          a: const P2(3, -500),
          b: const P2(3, 500),
          material: WallMaterial.concrete,
          thicknessMm: 102,
        );
        for (final P2 c in const <P2>[P2(6, 0), P2(6, 2.5), P2(5, 6)]) {
          final double exact = _rxDbm(_engine(<RoomWall>[w], exact: true), c);
          final double table = _rxDbm(_engine(<RoomWall>[w], exact: false), c);
          expect(table, closeTo(exact, 0.01));
        }
      },
    );

    test('with diffraction on, a long wall still costs its slab loss', () {
      final RoomWall w = RoomWall(
        a: const P2(3, -500),
        b: const P2(3, 500),
        material: WallMaterial.concrete,
        thicknessMm: 102,
      );
      final SlabResult slab = WallSlab.compute(
        material: WallMaterial.concrete,
        fGhz: 2.437,
        thicknessM: 0.102,
      );
      final RoomEngine e = _engine(<RoomWall>[w], diffraction: true);
      final double free = _eirp - FsplMath.fsplDb(6, 2437);
      expect(
        free - _rxDbm(e, const P2(6, 0)),
        closeTo(slab.transmissionLossDb, 0.05),
      );
    });
  });

  group('wall phase reference', () {
    test('a thin wall ending on the line of sight: (1 + T) / 2 exactly', () {
      // Regression (2026-09-25 render): the slab T carries the phase through
      // the wall's thickness, and the path length already counts that
      // thickness as air. Counted twice, 1 - T came out large even for
      // |T| near 1, and 13 mm of drywall cost 2.0 dB at 2.4 GHz. With the
      // phase referenced to the wall plane, half the wavefront passes open
      // and half through the wall, so the field is (1 + T) / 2 (Kirchhoff,
      // K(0) = 1/2). What remains at 6.5 GHz is real: the drywall still
      // delays its half by about 1.2 rad, and a phase step diffracts.
      final RoomWall w = RoomWall(
        a: const P2(5, -1000),
        b: const P2(5, 0),
        material: WallMaterial.plasterboard,
        thicknessMm: 13,
      );
      for (final double f in <double>[2437, 6535]) {
        final RoomEngine e = _engine(
          <RoomWall>[w],
          freqMHz: f,
          diffraction: true,
        );
        final double loss =
            _eirp - FsplMath.fsplDb(10, f) - _rxDbm(e, const P2(10, 0));
        final Complex t = RoomEngine.insertionT(
          MaterialProperties.of(WallMaterial.plasterboard, f / 1000),
          0.013,
          1,
          Polarization.te,
        );
        final double want =
            -20 * math.log((Complex.one + t).abs / 2) / math.ln10;
        expect(loss, closeTo(want, 0.05), reason: '$f MHz');
        if (f < 3000) expect(loss, lessThan(1.0));
      }
    });

    test('a lossless slab of air thickness has no effect at all', () {
      // e' = 1, sigma = 0: the wall is air, so T must be exactly 1 in phase
      // too, at any angle.
      final MaterialProperties air = MaterialProperties(
        material: WallMaterial.wood,
        fGhz: 2.437,
        epsReal: 1,
        sigma: 0,
      );
      final Complex t = RoomEngine.insertionT(air, 0.3, 0.6, Polarization.te);
      expect(t.re, closeTo(1, 1e-9));
      expect(t.im, closeTo(0, 1e-9));
    });
  });

  group('ITU-R P.526 knife edge', () {
    test('grazing (h = 0) gives 6.0 dB, Eq. 31 and exact Eq. 30', () {
      expect(KnifeEdge.lossDb(0), closeTo(6.0, 0.05));
      expect(KnifeEdge.exactLossDb(0), closeTo(6.02, 0.01));
      expect(KnifeEdge.coefficient(0).abs, closeTo(0.5, 1e-9));
    });

    test('brief example: edge 0.5 m into a 10 m path at the middle', () {
      double j(double fMHz) => KnifeEdge.lossDb(
        KnifeEdge.nu(h: 0.5, d1: 5, d2: 5, lambda: FsplMath.wavelengthM(fMHz)),
      );
      expect(j(2400), closeTo(15.5, 0.3));
      expect(j(6500), closeTo(19.4, 0.3));
    });

    test('Eq. 31 tracks the exact Eq. 30 within 0.5 dB for nu > -0.7', () {
      for (double nu = -0.7; nu <= 5; nu += 0.1) {
        expect(
          KnifeEdge.lossDb(nu),
          closeTo(KnifeEdge.exactLossDb(nu), 0.5),
          reason: 'nu = $nu',
        );
      }
    });

    test('Fresnel integrals match tabulated values', () {
      void check(double x, double c, double s) {
        final (double cc, double ss) = Fresnel.cs(x);
        expect(cc, closeTo(c, 1e-6), reason: 'C($x)');
        expect(ss, closeTo(s, 1e-6), reason: 'S($x)');
      }

      check(0, 0, 0);
      check(0.5, 0.4923442, 0.0647324);
      check(1, 0.7798934, 0.4382591);
      check(2, 0.4882534, 0.3434157);
      check(3, 0.6057208, 0.4963130);
      check(5, 0.5636312, 0.4991914);
      check(-1, -0.7798934, -0.4382591);
      // Continuity across the series / asymptotic switch at x = 3.
      final (double c1, double s1) = Fresnel.cs(2.9999999);
      final (double c2, double s2) = Fresnel.cs(3.0000001);
      expect((c1 - c2).abs(), lessThan(1e-6));
      expect((s1 - s2).abs(), lessThan(1e-6));
    });

    test('the room engine reproduces the knife edge through a metal edge', () {
      // A metal wall across the path at the midpoint of 10 m, reaching
      // [h] meters past the line of sight.
      double loss(double h, double fMHz) {
        final RoomWall w = RoomWall(
          a: P2(5, -1000),
          b: P2(5, h),
          material: WallMaterial.metal,
          thicknessMm: 2,
        );
        final RoomEngine e = _engine(
          <RoomWall>[w],
          freqMHz: fMHz,
          diffraction: true,
        );
        return _eirp - FsplMath.fsplDb(10, fMHz) - _rxDbm(e, const P2(10, 0));
      }

      expect(loss(0, 2400), closeTo(6.0, 0.1));
      expect(loss(0, 6500), closeTo(6.0, 0.1));
      expect(loss(0.5, 2400), closeTo(15.5, 0.3));
      expect(loss(0.5, 6500), closeTo(19.4, 0.3));
      // Clear of the path the edge costs next to nothing.
      expect(loss(-2, 2400).abs(), lessThan(0.5));
    });

    test('a doorway: in line with the opening beats the wall beside it', () {
      final RoomWall w = RoomWall(
        a: const P2(5, -1000),
        b: const P2(5, 1000),
        material: WallMaterial.concrete,
        thicknessMm: 150,
        doors: const <DoorGap>[DoorGap(centerM: 1000)],
      );
      final RoomEngine e = _engine(<RoomWall>[w], diffraction: true);
      final double through = _rxDbm(e, const P2(10, 0));
      final double beside = _rxDbm(e, const P2(10, 4));
      expect(through, greaterThan(beside + 6));
      // Shadow is deeper at 6 GHz than at 2.4 GHz (brief §6.3, point 3):
      // compare the loss deep behind the jamb, free space removed. (Near the
      // opening the slit's fringes make the comparison flip back and forth.)
      double shadow(double fMHz) {
        final RoomEngine ef = _engine(
          <RoomWall>[w.copyWith(material: WallMaterial.metal)],
          freqMHz: fMHz,
          diffraction: true,
        );
        const P2 p = P2(10, 3);
        return _eirp - FsplMath.fsplDb(p.length, fMHz) - _rxDbm(ef, p);
      }

      expect(shadow(6535), greaterThan(shadow(2437) + 5));
    });
  });

  group('Fresnel zone', () {
    test('mid-path radius of 10 m: 0.56 / 0.37 / 0.34 m', () {
      double r(double fMHz) => KnifeEdge.fresnelRadius(
        lambda: FsplMath.wavelengthM(fMHz),
        d1: 5,
        d2: 5,
      );
      expect(r(2400), closeTo(0.56, 0.01));
      expect(r(5500), closeTo(0.37, 0.01));
      expect(r(6500), closeTo(0.34, 0.01));
    });
  });

  group('standing wave near a metal wall', () {
    for (final double f in <double>[2437, 5500, 6535]) {
      test('power nulls repeat every half wavelength at $f MHz', () {
        // AP 5 m in front of a long metal wall at x = 0; walk the client
        // along the normal from 1 cm to 40 cm off the wall.
        final RoomWall w = RoomWall(
          a: const P2(0, -500),
          b: const P2(0, 500),
          material: WallMaterial.metal,
          thicknessMm: 2,
        );
        final RoomEngine e = _engine(
          <RoomWall>[w],
          ap: const P2(5, 0),
          freqMHz: f,
          order: 1,
        );
        final double lambda = FsplMath.wavelengthM(f);
        const double step = 0.0002;
        final List<double> xs = <double>[];
        final List<double> ps = <double>[];
        for (double x = 0.01; x <= 0.40; x += step) {
          xs.add(x);
          ps.add(e.powerAt(P2(x, 0)).$1);
        }
        final List<double> nulls = <double>[];
        for (int i = 1; i < ps.length - 1; i++) {
          if (ps[i] < ps[i - 1] && ps[i] <= ps[i + 1]) nulls.add(xs[i]);
        }
        expect(nulls.length, greaterThanOrEqualTo(3));
        for (int i = 1; i < nulls.length; i++) {
          expect(nulls[i] - nulls[i - 1], closeTo(lambda / 2, 2 * step));
        }
        // Metal gives near-full nulls: at least 25 dB below the peaks.
        final double peak = ps.reduce(math.max);
        final double floor = ps.reduce(math.min);
        expect(10 * math.log(peak / floor) / math.ln10, greaterThan(25));
      });
    }

    test('the average map has no ripple: it sums path powers', () {
      final RoomWall w = RoomWall(
        a: const P2(0, -500),
        b: const P2(0, 500),
        material: WallMaterial.metal,
        thicknessMm: 2,
      );
      final RoomEngine e = _engine(<RoomWall>[w], ap: const P2(5, 0), order: 1);
      final double a1 = e.averageAt(const P2(0.30, 0));
      final double a2 = e.averageAt(const P2(0.33, 0));
      expect(10 * math.log(a1 / a2) / math.ln10, lessThan(0.2));
    });
  });

  group('reflections', () {
    test('a first-order bounce off a long wall has the image-path length', () {
      final RoomWall w = RoomWall(
        a: const P2(-500, 3),
        b: const P2(500, 3),
        material: WallMaterial.metal,
        thicknessMm: 2,
      );
      final RoomEngine e = _engine(<RoomWall>[w], order: 1);
      final PointReport r = e.report(const P2(8, 0));
      expect(r.pathCount, 2);
      // Direct 1/64 plus |R|^2 / (8^2 + 6^2), R ~ -1 for metal.
      expect(r.averageAmp2, closeTo(1 / 64 + 1 / 100, 1e-4));
    });

    test('second order adds bounces between two parallel walls', () {
      final List<RoomWall> ws = <RoomWall>[
        const RoomWall(
          a: P2(-500, 3),
          b: P2(500, 3),
          material: WallMaterial.concrete,
          thicknessMm: 200,
        ),
        const RoomWall(
          a: P2(-500, -3),
          b: P2(500, -3),
          material: WallMaterial.concrete,
          thicknessMm: 200,
        ),
      ];
      final int c1 = _engine(ws, order: 1).report(const P2(8, 1)).pathCount;
      final int c2 = _engine(ws, order: 2).report(const P2(8, 1)).pathCount;
      expect(c1, 3);
      expect(c2, 5);
    });

    test('a doorway does not reflect', () {
      final RoomWall w = RoomWall(
        a: const P2(-500, 3),
        b: const P2(500, 3),
        material: WallMaterial.metal,
        thicknessMm: 2,
        doors: const <DoorGap>[DoorGap(centerM: 504, widthM: 2)],
      );
      // Reflection point for AP (0,0) -> P (8,0) is x = 4: inside the gap.
      final RoomEngine e = _engine(<RoomWall>[w], order: 1);
      expect(e.report(const P2(8, 0)).pathCount, 1);
    });
  });

  group('walls', () {
    test('solid pieces remove doors and merge overlaps', () {
      const RoomWall w = RoomWall(
        a: P2(0, 0),
        b: P2(10, 0),
        material: WallMaterial.plasterboard,
        thicknessMm: 13,
        doors: <DoorGap>[
          DoorGap(centerM: 2),
          DoorGap(centerM: 2.5),
          DoorGap(centerM: 9.9),
        ],
      );
      final List<(double, double)> p = w.solidPieces;
      expect(p, hasLength(2));
      expect(p[0].$1, 0);
      expect(p[0].$2, closeTo(1.55, 1e-9));
      expect(p[1].$1, closeTo(2.95, 1e-9));
      expect(p[1].$2, closeTo(9.45, 1e-9));
      expect(w.doorJambs, hasLength(6));
    });
  });

  group('grid job', () {
    test('computeRoomField fills every cell and times itself', () {
      final RoomFieldResult r = computeRoomField(
        RoomFieldJob(
          walls: const <RoomWall>[
            RoomWall(
              a: P2(5, 0),
              b: P2(5, 6),
              material: WallMaterial.concrete,
              thicknessMm: 150,
              doors: <DoorGap>[DoorGap(centerM: 3)],
            ),
          ],
          ap: const P2(2, 3),
          radio: const RoomRadio(freqMHz: 5500),
          widthM: 10,
          heightM: 6,
          cellM: 0.25,
          rippleCenter: const P2(4.7, 1),
          rippleCells: 40,
        ),
      );
      expect(r.average!.cols, 40);
      expect(r.average!.rows, 24);
      expect(r.average!.values.every((double v) => v.isFinite), isTrue);
      expect(r.ripple!.cols, 40);
      expect(r.averageMs, greaterThanOrEqualTo(0));
    });
  });
}
