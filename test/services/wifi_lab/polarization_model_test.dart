// Model tests for Polarization (spec 45, "Done means" 1). Every closed form in
// polarization_model.dart is checked against a brute-force trace of the tip
// of the field, so nothing rests on a formula copied from a book.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/polarization_model.dart';

/// The traced shape sampled at [n] phases: longest and shortest tip length,
/// and the angle of the longest from horizontal (folded to -90..90).
({double major, double minor, double tiltDeg}) _trace(
  PolarizationState s, {
  int n = 3600,
}) {
  double maxL = -1, minL = double.infinity, tilt = 0;
  for (int k = 0; k < n; k++) {
    final FieldVector f = s.fieldAt(0, 2 * math.pi * k / n);
    final double l = f.magnitude;
    if (l > maxL) {
      maxL = l;
      double t = math.atan2(f.v, f.h) * 180 / math.pi;
      if (t > 90) t -= 180;
      if (t <= -90) t += 180;
      tilt = t;
    }
    if (l < minL) minL = l;
  }
  return (major: maxL, minor: minL, tiltDeg: tilt);
}

void main() {
  group('presets', () {
    test('every named preset carries the same power: Ax^2 + Ay^2 = 1', () {
      for (final PolarizationPreset p in PolarizationPreset.named) {
        final PolarizationState s = p.state;
        expect(s.ax * s.ax + s.ay * s.ay, closeTo(1, 1e-12), reason: p.label);
      }
    });

    test('each preset matches itself, and a nudged one is Custom', () {
      for (final PolarizationPreset p in PolarizationPreset.named) {
        expect(p.state.matchingPreset, p);
      }
      expect(
        PolarizationPreset.circular.state.copyWith(deltaDeg: 75).matchingPreset,
        PolarizationPreset.custom,
      );
    });

    test('kinds and names', () {
      expect(PolarizationPreset.vertical.state.kind, PolarizationKind.linear);
      expect(PolarizationPreset.horizontal.state.kind, PolarizationKind.linear);
      expect(PolarizationPreset.slant45.state.kind, PolarizationKind.linear);
      expect(PolarizationPreset.circular.state.kind, PolarizationKind.circular);
      expect(
        PolarizationPreset.elliptical.state.kind,
        PolarizationKind.elliptical,
      );
      expect(polarizationName(PolarizationPreset.slant45.state), 'Slant 45°');
      expect(
        polarizationName(
          const PolarizationState(ax: 1, ay: 0.5, deltaDeg: 180),
        ),
        startsWith('Linear at '),
      );
    });
  });

  group('linear has one axis', () {
    test('vertical: no horizontal field anywhere along z, at any time', () {
      const PolarizationState s = PolarizationState(ax: 0, ay: 1, deltaDeg: 0);
      for (int t = 0; t < 12; t++) {
        for (final FieldVector f in s.sampleAlongZ(65, t * math.pi / 6)) {
          expect(f.h, 0);
        }
      }
      expect(s.tiltDeg, closeTo(90, 1e-9));
    });

    test('horizontal: no vertical field anywhere along z, at any time', () {
      const PolarizationState s = PolarizationState(ax: 1, ay: 0, deltaDeg: 0);
      for (int t = 0; t < 12; t++) {
        for (final FieldVector f in s.sampleAlongZ(65, t * math.pi / 6)) {
          expect(f.v, 0);
        }
      }
      expect(s.tiltDeg, closeTo(0, 1e-9));
    });

    test('slant 45: every field vector lies on the 45 degree line', () {
      final PolarizationState s = PolarizationPreset.slant45.state;
      for (final FieldVector f in s.sampleAlongZ(65, 0.3)) {
        expect(f.h, closeTo(f.v, 1e-12));
      }
      expect(s.tiltDeg, closeTo(45, 1e-9));
    });
  });

  group('axial ratio', () {
    test('1 for circular, infinite for every linear preset, 2 for the '
        'elliptical preset', () {
      expect(PolarizationPreset.circular.state.axialRatio, closeTo(1, 1e-9));
      for (final PolarizationPreset p in <PolarizationPreset>[
        PolarizationPreset.vertical,
        PolarizationPreset.horizontal,
        PolarizationPreset.slant45,
      ]) {
        expect(p.state.axialRatio, double.infinity, reason: p.label);
      }
      expect(PolarizationPreset.elliptical.state.axialRatio, closeTo(2, 1e-9));
      expect(PolarizationPreset.elliptical.state.tiltDeg, closeTo(0, 1e-9));
    });

    test('closed form matches a 3,600-point trace over a grid of Ax, Ay, '
        'delta', () {
      for (final double ax in <double>[0.2, 0.5, 0.7, 1]) {
        for (final double ay in <double>[0.1, 0.5, 0.7, 1]) {
          for (double d = -165; d <= 180; d += 15) {
            final PolarizationState s = PolarizationState(
              ax: ax,
              ay: ay,
              deltaDeg: d,
            );
            final ({double major, double minor, double tiltDeg}) t = _trace(s);
            final String why = 'Ax $ax Ay $ay delta $d';
            expect(s.majorAxis, closeTo(t.major, 1e-5), reason: why);
            expect(s.minorAxis, closeTo(t.minor, 1e-3), reason: why);
            // Tilt is defined only when the shape is not a circle.
            if ((s.majorAxis - s.minorAxis) > 1e-3) {
              double diff = (s.tiltDeg - t.tiltDeg).abs();
              if (diff > 90) diff = 180 - diff; // -90 and 90 are one line
              expect(diff, lessThan(0.2), reason: why);
            }
          }
        }
      }
    });
  });

  group('circular', () {
    test('constant field magnitude along z, at every instant', () {
      final PolarizationState s = PolarizationPreset.circular.state;
      final double a = s.ax;
      for (int t = 0; t < 24; t++) {
        for (final FieldVector f in s.sampleAlongZ(129, t * math.pi / 12)) {
          expect(f.magnitude, closeTo(a, 1e-12));
        }
      }
    });

    test('turns once per wavelength along z', () {
      final PolarizationState s = PolarizationPreset.circular.state;
      double turned = 0;
      FieldVector prev = s.fieldAt(0, 0);
      for (int i = 1; i <= 400; i++) {
        final FieldVector f = s.fieldAt(i / 400, 0);
        double d = math.atan2(f.v, f.h) - math.atan2(prev.v, prev.h);
        if (d > math.pi) d -= 2 * math.pi;
        if (d < -math.pi) d += 2 * math.pi;
        turned += d;
        prev = f;
      }
      expect(turned.abs(), closeTo(2 * math.pi, 1e-9));
    });

    test('-90 degrees turns the other way at a fixed place', () {
      double sense(PolarizationState s) {
        final FieldVector a = s.fieldAt(0, 0);
        final FieldVector b = s.fieldAt(0, 0.01);
        return a.h * b.v - a.v * b.h; // z of the cross product
      }

      final PolarizationState plus = PolarizationPreset.circular.state;
      final PolarizationState minus = plus.copyWith(deltaDeg: -90);
      expect(sense(plus).sign, -sense(minus).sign);
      expect(minus.kind, PolarizationKind.circular);
    });
  });

  group('no field', () {
    test('both amplitudes 0 is none, with no axial ratio', () {
      const PolarizationState s = PolarizationState(ax: 0, ay: 0, deltaDeg: 0);
      expect(s.hasField, isFalse);
      expect(s.kind, PolarizationKind.none);
      expect(s.axialRatio.isNaN, isTrue);
      expect(polarizationName(s), 'No field');
    });

    test('copyWith clamps', () {
      final PolarizationState s = PolarizationState.initial.copyWith(
        ax: 2,
        ay: -1,
        deltaDeg: 400,
      );
      expect(s.ax, 1);
      expect(s.ay, 0);
      expect(s.deltaDeg, 180);
    });
  });

  test('the wave travels toward +z: a crest moves forward as time runs', () {
    const PolarizationState s = PolarizationState(ax: 1, ay: 0, deltaDeg: 0);
    // At t = 0 the crest (h = 1) is at z = 0; a quarter period later it is
    // a quarter wavelength further along.
    expect(s.fieldAt(0, 0).h, closeTo(1, 1e-12));
    expect(s.fieldAt(0.25, math.pi / 2).h, closeTo(1, 1e-12));
  });
}
