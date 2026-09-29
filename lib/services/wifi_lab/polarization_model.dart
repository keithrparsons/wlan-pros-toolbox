// Polarization (Wi-Fi Classroom, polarization): the field of one plane wave.
//
// Pure Dart, no Flutter. One closed form, written fresh:
//
//   E(z, t) = Ax cos(wt - kz) x^ + Ay cos(wt - kz + delta) y^
//
// with x^ HORIZONTAL and y^ VERTICAL, both at right angles to the direction
// of travel z. Linear when delta is 0 or 180 degrees or either amplitude is 0;
// circular when Ax = Ay and delta = +/-90 degrees; elliptical otherwise.
//
// CLEAN-ROOM BUILD (2026-09-29) per myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/45-polarization.md (Feature 5b of Deliverables/2026-09-29-
// classroom-eight-features/PLAN.md, cut to the polarization-states view by
// Keith's ruling 4). Sources:
//   - Balanis, Antenna Theory: Analysis and Design, the polarization section
//     of chapter 2, for the definitions (linear, circular, elliptical, axial
//     ratio). No page is pinned; nothing here depends on the book's wording,
//     and the test checks every closed form against a brute-force trace.
//   - EMANIM Classic by Andras Szilagyi (public domain; emanim12.py lines
//     4-11, quoted in the spec) for the view this tool follows: field arrows
//     along the axis, with the two component waves. No EMANIM code is ported.
//
// HANDEDNESS IS NOT NAMED. EMANIM uses the optics convention (looking toward
// the source, emanim12.py lines 24-27); the antenna convention (IEEE Std 145)
// is believed to be the opposite and is not pinned. So the model has no
// right/left field and the tool says only "Circular". The sign of delta still
// sets which way the field turns, and the phase slider shows it.
//
// THE POLARIZATION ELLIPSE. Write u = wt - kz. The tip of E traces
// (Ax cos u, Ay cos(u + delta)). Its squared length is
//   |E|^2 = (Ax^2 + Ay^2)/2 + (Ax^2 cos 2u + Ay^2 cos(2u + 2 delta))/2,
// and the second term is a sinusoid in 2u of amplitude
//   R = sqrt(Ax^4 + Ay^4 + 2 Ax^2 Ay^2 cos 2delta) / 2,
// so the half-axes are OA, OB = sqrt((Ax^2 + Ay^2)/2 +/- R). The axial ratio
// is OA / OB (infinite when OB = 0), and the long axis sits at
//   tau = atan2(2 Ax Ay cos delta, Ax^2 - Ay^2) / 2
// from horizontal.
//
// FREQUENCY NEVER CHANGES (Keith, 2026-09-25): positions along z are in
// wavelengths, and nothing here has a frequency to change.

import 'dart:math' as math;

/// How the tip of the field moves, seen looking along the direction of travel.
enum PolarizationKind {
  /// Back and forth on a line.
  linear,

  /// Round a circle, never shrinking.
  circular,

  /// Round an ellipse.
  elliptical,

  /// Both amplitudes are zero: there is no wave.
  none;

  /// What the tip traces, in words.
  String get traces => switch (this) {
    PolarizationKind.linear => 'a line',
    PolarizationKind.circular => 'a circle',
    PolarizationKind.elliptical => 'an ellipse',
    PolarizationKind.none => 'nothing',
  };
}

/// The named starting points. Every preset carries the same power:
/// Ax^2 + Ay^2 = 1.
enum PolarizationPreset {
  vertical('Vertical'),
  horizontal('Horizontal'),
  slant45('Slant 45°'),
  circular('Circular'),
  elliptical('Elliptical'),

  /// Whatever the amplitude and phase sliders set.
  custom('Custom');

  const PolarizationPreset(this.label);

  final String label;

  /// The presets P and the arrow keys step through (Custom is not one).
  static const List<PolarizationPreset> named = <PolarizationPreset>[
    vertical,
    horizontal,
    slant45,
    circular,
    elliptical,
  ];

  /// The field this preset sets. Custom returns [PolarizationState.initial].
  PolarizationState get state {
    const double r2 = math.sqrt1_2;
    switch (this) {
      case PolarizationPreset.vertical:
        return const PolarizationState(ax: 0, ay: 1, deltaDeg: 0);
      case PolarizationPreset.horizontal:
        return const PolarizationState(ax: 1, ay: 0, deltaDeg: 0);
      case PolarizationPreset.slant45:
        return const PolarizationState(ax: r2, ay: r2, deltaDeg: 0);
      case PolarizationPreset.circular:
        return const PolarizationState(ax: r2, ay: r2, deltaDeg: 90);
      case PolarizationPreset.elliptical:
        // 2/sqrt 5 and 1/sqrt 5: axial ratio exactly 2, long axis horizontal.
        return PolarizationState(
          ax: 2 / math.sqrt(5),
          ay: 1 / math.sqrt(5),
          deltaDeg: 90,
        );
      case PolarizationPreset.custom:
        return PolarizationState.initial;
    }
  }
}

/// One field vector: horizontal and vertical parts, in amplitude units.
class FieldVector {
  const FieldVector(this.h, this.v);

  /// Horizontal part (x^).
  final double h;

  /// Vertical part (y^).
  final double v;

  double get magnitude => math.sqrt(h * h + v * v);

  @override
  String toString() => 'FieldVector($h, $v)';
}

/// The wave: horizontal amplitude, vertical amplitude and the phase of the
/// vertical part relative to the horizontal. Immutable.
class PolarizationState {
  const PolarizationState({
    required this.ax,
    required this.ay,
    required this.deltaDeg,
  });

  /// The tool opens on Vertical.
  static const PolarizationState initial = PolarizationState(
    ax: 0,
    ay: 1,
    deltaDeg: 0,
  );

  /// Below this, a half-axis counts as zero (the shape is a line).
  static const double eps = 1e-9;

  /// Horizontal amplitude, 0 to 1.
  final double ax;

  /// Vertical amplitude, 0 to 1.
  final double ay;

  /// Phase of the vertical part ahead of the horizontal, -180 to 180 degrees.
  final double deltaDeg;

  double get _delta => deltaDeg * math.pi / 180;

  /// False when both amplitudes are zero.
  bool get hasField => ax > eps || ay > eps;

  /// The field at [zLambda] wavelengths along the axis, at wave phase
  /// [phaseRad] (wt). Horizontal is Ax cos(wt - kz); vertical is
  /// Ay cos(wt - kz + delta).
  FieldVector fieldAt(double zLambda, double phaseRad) {
    final double u = phaseRad - 2 * math.pi * zLambda;
    return FieldVector(ax * math.cos(u), ay * math.cos(u + _delta));
  }

  /// [n] field vectors from z = 0 to z = [lengthLambda] wavelengths, both
  /// ends included.
  List<FieldVector> sampleAlongZ(
    int n,
    double phaseRad, {
    double lengthLambda = 2,
  }) => <FieldVector>[
    for (int i = 0; i < n; i++)
      fieldAt(n == 1 ? 0 : lengthLambda * i / (n - 1), phaseRad),
  ];

  double get _r {
    final double a2 = ax * ax, b2 = ay * ay;
    final double inner = a2 * a2 + b2 * b2 + 2 * a2 * b2 * math.cos(2 * _delta);
    return math.sqrt(math.max(0, inner)) / 2;
  }

  /// The long half-axis of the traced shape.
  double get majorAxis => math.sqrt(math.max(0, (ax * ax + ay * ay) / 2 + _r));

  /// The short half-axis of the traced shape (0 for a line).
  double get minorAxis => math.sqrt(math.max(0, (ax * ax + ay * ay) / 2 - _r));

  /// Long axis over short axis: 1 for circular, infinite for linear.
  double get axialRatio {
    if (!hasField) return double.nan;
    final double b = minorAxis;
    if (b <= majorAxis * 1e-6) return double.infinity;
    return majorAxis / b;
  }

  /// Angle of the long axis from horizontal, -90 to 90 degrees (positive
  /// toward vertical-up). Meaningless for a circle; returns 0 there.
  double get tiltDeg {
    if (!hasField) return 0;
    final double y = 2 * ax * ay * math.cos(_delta);
    final double x = ax * ax - ay * ay;
    if (y.abs() < eps && x.abs() < eps) return 0; // a circle
    double t = 0.5 * math.atan2(y, x) * 180 / math.pi;
    // atan2/2 is in (-90, 90]; fold 90 to -90 so vertical reads 90.
    if (t <= -90 + 1e-9) t += 180;
    return t;
  }

  PolarizationKind get kind {
    if (!hasField) return PolarizationKind.none;
    final double ar = axialRatio;
    if (ar.isInfinite) return PolarizationKind.linear;
    if ((ar - 1).abs() < 1e-6) return PolarizationKind.circular;
    return PolarizationKind.elliptical;
  }

  /// The named preset this state equals, or custom.
  PolarizationPreset get matchingPreset {
    for (final PolarizationPreset p in PolarizationPreset.named) {
      final PolarizationState s = p.state;
      if ((s.ax - ax).abs() < 1e-6 &&
          (s.ay - ay).abs() < 1e-6 &&
          (s.deltaDeg - deltaDeg).abs() < 1e-6) {
        return p;
      }
    }
    return PolarizationPreset.custom;
  }

  PolarizationState copyWith({double? ax, double? ay, double? deltaDeg}) =>
      PolarizationState(
        ax: (ax ?? this.ax).clamp(0.0, 1.0),
        ay: (ay ?? this.ay).clamp(0.0, 1.0),
        deltaDeg: (deltaDeg ?? this.deltaDeg).clamp(-180.0, 180.0),
      );

  @override
  bool operator ==(Object other) =>
      other is PolarizationState &&
      other.ax == ax &&
      other.ay == ay &&
      other.deltaDeg == deltaDeg;

  @override
  int get hashCode => Object.hash(ax, ay, deltaDeg);
}

/// The polarization in words for a readout: the preset name when it is one,
/// else the kind (a linear state names its angle).
String polarizationName(PolarizationState s) {
  final PolarizationPreset p = s.matchingPreset;
  if (p != PolarizationPreset.custom) return p.label;
  switch (s.kind) {
    case PolarizationKind.none:
      return 'No field';
    case PolarizationKind.circular:
      return 'Circular';
    case PolarizationKind.elliptical:
      return 'Elliptical';
    case PolarizationKind.linear:
      final double t = s.tiltDeg;
      if ((t.abs() - 90).abs() < 0.5) return 'Vertical';
      if (t.abs() < 0.5) return 'Horizontal';
      return 'Linear at ${t.round()}°';
  }
}
