// Room propagation model for the Wi-Fi Lab "Room Propagation" simulator
// (room-propagation).
//
// CLEAN-ROOM BUILD (2026-09-25) from the equations in myPKA
// Deliverables/2026-09-25-wifi-lab-research/brief.md §6.3 (ITU-R P.2040 wall
// transmission and reflection, ITU-R P.526 knife-edge diffraction and Fresnel
// zones, half-wavelength nulls) and §6.5 (the analytic image-ray model), per
// the spec Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 10-room-propagation.md. Nothing here is derived from any other simulator's
// code.
//
// THE MODEL, top-down, one AP, walls as line segments:
//
//   U(P) = sum over paths of a_i * e^(-j k r_i) / r_i
//
// with 3D spreading (1/r amplitude), so received power is
//   P_rx = EIRP + 20 log10(lambda / 4 pi) + 10 log10 |U|^2   (0 dBi receiver)
// and with no walls it is exactly EIRP - FSPL. It is a 2D plan of a 3D model
// with no floor or ceiling bounce.
//
// Paths: the direct path, first-order and (optionally) second-order image
// reflections. Every wall's complex T and R come from wall_slab_physics.dart
// (ITU-R P.2040 slab, TE or TM, at the real angle of incidence).
//
// Diffraction. The brief gives P.526's knife-edge loss J(nu) (Eq. 31, an
// approximation) and names the exact form, Eq. 30, built from the Fresnel
// integrals C and S. J(nu) is a loss in dB with no phase, so it cannot be added
// coherently to a wave that also passes THROUGH the wall. The field engine
// therefore uses the exact complex knife-edge function behind Eq. 30:
//
//   K(nu) = ((1 + j) / 2) * integral from nu to infinity of e^(-j pi t^2 / 2) dt
//
// |K(0)| = 1/2 (6.02 dB at grazing) and -20 log10 |K(nu)| is Eq. 30's J(nu).
// Each wall on a path acts as a screen along its own line: open where there is
// no wall, transmission T where there is. By Kirchhoff's construction the
// field factor of one wall line is
//
//   F = 1 - (1 - T) * W,  W = sum over the solid pieces of K(nu_a) - K(nu_b)
//
// where nu_a < nu_b are the Fresnel parameters of the piece's two ends,
// nu = +/- 2 sqrt(delta / lambda), delta = the extra path length via that end.
// A long solid wall gives W -> 1 and F -> T (the plain slab loss); a doorway is
// the gap between two pieces; an opaque half-plane edge on the line of sight
// gives F = K(0), 6.02 dB. A reflection off a finite wall is weighted by the
// same W computed from the image source, so doorways do not reflect and a
// wall's reflection fades out smoothly past its end.
//
// Phase reference: every wall's T and R are referenced to the wall's center
// plane (see _planePhase), because the path lengths run straight through it.
//
// Reflected legs get the same screens, with the Fresnel terms skipped when no
// wall end is within |nu| = 6 of the leg (the plain slab T is then within
// about 0.3 dB).
//
// What it leaves out, said on screen: floor and ceiling, third and higher
// order bounces, and anything a line segment cannot describe (studs,
// cavities, furniture).
//
// No Flutter imports: the screen drives this, the tests pin it.

import 'dart:math' as math;
import 'dart:typed_data';

import 'complex.dart';
import 'fspl_math.dart';
import 'wall_slab_physics.dart';

// ── Geometry ──────────────────────────────────────────────────────────────

/// A point or vector on the plan, meters.
class P2 {
  const P2(this.x, this.y);

  final double x;
  final double y;

  P2 operator +(P2 o) => P2(x + o.x, y + o.y);
  P2 operator -(P2 o) => P2(x - o.x, y - o.y);
  P2 scale(double k) => P2(x * k, y * k);
  double dot(P2 o) => x * o.x + y * o.y;
  double get length => math.sqrt(x * x + y * y);

  double distanceTo(P2 o) {
    final double dx = x - o.x;
    final double dy = y - o.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  bool operator ==(Object other) => other is P2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'P2($x, $y)';
}

/// An opening in a wall, placed by its center's distance from the wall's
/// start point.
class DoorGap {
  const DoorGap({required this.centerM, this.widthM = kDoorWidthM});

  final double centerM;
  final double widthM;

  @override
  bool operator ==(Object other) =>
      other is DoorGap && other.centerM == centerM && other.widthM == widthM;

  @override
  int get hashCode => Object.hash(centerM, widthM);
}

/// Default door opening, meters.
const double kDoorWidthM = 0.9;

/// A wall: a straight segment of one P.2040 material, possibly with doorways.
class RoomWall {
  const RoomWall({
    required this.a,
    required this.b,
    required this.material,
    required this.thicknessMm,
    this.doors = const <DoorGap>[],
  });

  final P2 a;
  final P2 b;
  final WallMaterial material;
  final double thicknessMm;
  final List<DoorGap> doors;

  double get length => a.distanceTo(b);

  /// A point [s] meters from [a] along the wall.
  P2 pointAt(double s) {
    final double l = length;
    if (l == 0) return a;
    return a + (b - a).scale(s / l);
  }

  /// The solid stretches of the wall, as (start, end) meters from [a],
  /// sorted, with every door removed. Overlapping doors merge.
  List<(double, double)> get solidPieces {
    final double l = length;
    final List<(double, double)> gaps = <(double, double)>[
      for (final DoorGap d in doors)
        (
          (d.centerM - d.widthM / 2).clamp(0.0, l),
          (d.centerM + d.widthM / 2).clamp(0.0, l),
        ),
    ]..sort(((double, double) p, (double, double) q) => p.$1.compareTo(q.$1));
    final List<(double, double)> out = <(double, double)>[];
    double cursor = 0;
    for (final (double, double) g in gaps) {
      if (g.$1 > cursor) out.add((cursor, g.$1));
      if (g.$2 > cursor) cursor = g.$2;
    }
    if (cursor < l) out.add((cursor, l));
    return out;
  }

  /// The door jambs: the wall points at each opening's two edges.
  List<P2> get doorJambs => <P2>[
    for (final DoorGap d in doors) ...<P2>[
      pointAt((d.centerM - d.widthM / 2).clamp(0.0, length)),
      pointAt((d.centerM + d.widthM / 2).clamp(0.0, length)),
    ],
  ];

  RoomWall copyWith({
    P2? a,
    P2? b,
    WallMaterial? material,
    double? thicknessMm,
    List<DoorGap>? doors,
  }) => RoomWall(
    a: a ?? this.a,
    b: b ?? this.b,
    material: material ?? this.material,
    thicknessMm: thicknessMm ?? this.thicknessMm,
    doors: doors ?? this.doors,
  );

  @override
  bool operator ==(Object other) {
    if (other is! RoomWall) return false;
    if (other.a != a ||
        other.b != b ||
        other.material != material ||
        other.thicknessMm != thicknessMm ||
        other.doors.length != doors.length) {
      return false;
    }
    for (int i = 0; i < doors.length; i++) {
      if (other.doors[i] != doors[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(a, b, material, thicknessMm, Object.hashAll(doors));
}

/// The radio side of a run: frequency, polarization and which mechanisms are
/// on.
class RoomRadio {
  const RoomRadio({
    required this.freqMHz,
    this.polarization = Polarization.te,
    this.reflectionOrder = 1,
    this.diffraction = true,
  });

  final double freqMHz;

  /// TE: E parallel to the wall face, which is what an upright (vertical)
  /// antenna gives against vertical walls seen from above. TM: a horizontal
  /// antenna.
  final Polarization polarization;

  /// 0, 1 or 2.
  final int reflectionOrder;

  final bool diffraction;

  double get lambda => FsplMath.wavelengthM(freqMHz);
  double get k => 2 * math.pi / lambda;
  double get fGhz => freqMHz / 1000;

  /// 20 log10(lambda / 4 pi): the isotropic-antenna term that turns |U|^2
  /// (units 1/m^2) into a path gain in dB.
  double get apertureGainDb => 20 * FsplMath.log10(lambda / (4 * math.pi));
}

// ── ITU-R P.526 knife edge and Fresnel zone ───────────────────────────────

/// P.526 knife-edge and Fresnel-zone formulas, as the brief gives them.
abstract final class KnifeEdge {
  /// Fresnel-Kirchhoff parameter (P.526 Eq. 26):
  /// nu = h * sqrt((2 / lambda) * (1 / d1 + 1 / d2)). [h] > 0 when the edge
  /// is into the path (blocking), < 0 when it is clear of it.
  static double nu({
    required double h,
    required double d1,
    required double d2,
    required double lambda,
  }) => h * math.sqrt((2 / lambda) * (1 / d1 + 1 / d2));

  /// Knife-edge loss J(nu), dB (P.526 Eq. 31). The approximation holds for
  /// nu > -0.78; below that the edge is well clear and the loss is taken as
  /// zero.
  static double lossDb(double nu) {
    if (nu <= -0.78) return 0;
    final double v = nu - 0.1;
    return 6.9 + 20 * FsplMath.log10(math.sqrt(v * v + 1) + v);
  }

  /// The exact complex knife-edge field factor K(nu) behind P.526 Eq. 30:
  /// ((1 + j) / 2) * integral from nu to infinity of e^(-j pi t^2 / 2) dt.
  /// K(-infinity) = 1 (nothing in the way), K(0) = 1/2, K(+infinity) = 0.
  static Complex coefficient(double nu) {
    final (double c, double s) = Fresnel.cs(nu);
    final double a = 0.5 - c;
    final double b = 0.5 - s;
    // ((1 + j) / 2) * (a - j b) = ((a + b) + j (a - b)) / 2
    return Complex((a + b) / 2, (a - b) / 2);
  }

  /// Exact knife-edge loss, dB (P.526 Eq. 30): -20 log10 |K(nu)|.
  static double exactLossDb(double nu) {
    final double m = coefficient(nu).abs;
    if (m <= 0) return double.infinity;
    return -20 * FsplMath.log10(m);
  }

  /// Radius of the n-th Fresnel zone (P.526 Eq. 2):
  /// R_n = sqrt(n * lambda * d1 * d2 / (d1 + d2)).
  static double fresnelRadius({
    required double lambda,
    required double d1,
    required double d2,
    int n = 1,
  }) => math.sqrt(n * lambda * d1 * d2 / (d1 + d2));
}

/// K(nu) tabulated for the field grids: [-8, 8] in 0.001 steps, linear
/// interpolation (relative error about 1e-4, far under 0.01 dB), the exact
/// function outside. Built once per isolate on first use.
abstract final class _KTable {
  static const double _lo = -8;
  static const double _hi = 8;
  static const double _step = 0.001;
  static const int _n = 16000;

  static final Float64List _re = Float64List(_n + 1);
  static final Float64List _im = Float64List(_n + 1);
  static bool _built = false;

  static void _build() {
    for (int i = 0; i <= _n; i++) {
      final Complex k = KnifeEdge.coefficient(_lo + i * _step);
      _re[i] = k.re;
      _im[i] = k.im;
    }
    _built = true;
  }

  static Complex at(double nu) {
    if (nu <= _lo || nu >= _hi) return KnifeEdge.coefficient(nu);
    if (!_built) _build();
    final double x = (nu - _lo) / _step;
    final int i = x.floor();
    final double f = x - i;
    return Complex(
      _re[i] + (_re[i + 1] - _re[i]) * f,
      _im[i] + (_im[i + 1] - _im[i]) * f,
    );
  }
}

/// The Fresnel integrals C(x) = integral 0..x of cos(pi t^2 / 2) dt and
/// S(x) = integral 0..x of sin(pi t^2 / 2) dt, computed from their power
/// series below |x| = 3 and from the asymptotic auxiliary functions above.
/// Accurate to about 1e-9, far past what a dB readout needs.
abstract final class Fresnel {
  static (double, double) cs(double x) {
    final double ax = x.abs();
    final (double c, double s) = ax < 3 ? _series(ax) : _asymptotic(ax);
    return x < 0 ? (-c, -s) : (c, s);
  }

  // integral 0..x of e^(j pi t^2 / 2) dt
  //   = sum over k of (j pi / 2)^k x^(2k + 1) / (k! (2k + 1)).
  static (double, double) _series(double x) {
    final double z = math.pi * x * x / 2;
    // term_k = (j z)^k / k!, kept as a complex number; multiplied by
    // x / (2k + 1) when summed.
    double tr = 1;
    double ti = 0;
    double c = x;
    double s = 0;
    for (int k = 1; k < 200; k++) {
      // (tr + j ti) * (j z / k)
      final double nr = -ti * z / k;
      final double ni = tr * z / k;
      tr = nr;
      ti = ni;
      final double w = x / (2 * k + 1);
      c += tr * w;
      s += ti * w;
      if ((tr.abs() + ti.abs()) * w < 1e-17) break;
    }
    return (c, s);
  }

  static (double, double) _asymptotic(double x) {
    final double px2 = math.pi * x * x;
    final double u = 1 / (px2 * px2);
    // f ~ (1 / (pi x)) * sum (-1)^m (4m - 1)!! u^m
    // g ~ (1 / (pi^2 x^3)) * sum (-1)^m (4m + 1)!! u^m
    double f = 1;
    double g = 1;
    double tf = 1;
    double tg = 1;
    for (int m = 1; m < 12; m++) {
      final double nf = -tf * (4 * m - 3) * (4 * m - 1) * u;
      final double ng = -tg * (4 * m - 1) * (4 * m + 1) * u;
      if (nf.abs() > tf.abs() || ng.abs() > tg.abs()) break;
      tf = nf;
      tg = ng;
      f += tf;
      g += tg;
      if (tf.abs() < 1e-17 && tg.abs() < 1e-17) break;
    }
    f /= math.pi * x;
    g /= math.pi * math.pi * x * x * x;
    final double z = px2 / 2;
    final double sz = math.sin(z);
    final double cz = math.cos(z);
    return (0.5 + f * sz - g * cz, 0.5 - f * cz - g * sz);
  }
}

// ── Wall coefficients ─────────────────────────────────────────────────────

/// P.2040 T and R for one wall at one frequency, as a function of the cosine
/// of the angle of incidence.
abstract class _Coefficients {
  Complex t(double cosTheta);
  Complex r(double cosTheta);
}

/// Moves the slab coefficients' phase reference to the wall's center plane.
///
/// P.2040's T relates the field behind the back face to the field at the
/// front face, so its phase includes the trip through the thickness. The path
/// sum here measures every path as a straight line through the wall plane,
/// which already counts that thickness as air (k0 d cos theta along the
/// normal). Multiplying by e^(+j k0 d cos theta) removes the double count, so
/// a slab of air gives T = 1 exactly. The same factor moves R from the front
/// face to the center plane the image source is mirrored across. Magnitudes
/// are unchanged, so every loss in dB is still exactly the slab's.
Complex _planePhase(MaterialProperties props, double thicknessM, double c) =>
    Complex.polar(
      1,
      2 * math.pi / props.lambdaAir * thicknessM * c.clamp(0.0, 1.0),
    );

/// Largest angle handed to the slab model (it requires < 90 degrees).
const double _kMaxAngleDeg = 89.9;

double _angleDegFromCos(double c) {
  final double deg = math.acos(c.clamp(0.0, 1.0)) * 180 / math.pi;
  return deg > _kMaxAngleDeg ? _kMaxAngleDeg : deg;
}

/// Computes every coefficient directly from the slab formulas. Used for the
/// point readouts and the tests.
class _ExactCoefficients implements _Coefficients {
  _ExactCoefficients(this.props, this.thicknessM, this.pol);

  final MaterialProperties props;
  final double thicknessM;
  final Polarization pol;

  SlabResult _at(double c) => WallSlab.computeFor(
    props: props,
    thicknessM: thicknessM,
    angleDeg: _angleDegFromCos(c),
    polarization: pol,
  );

  @override
  Complex t(double cosTheta) =>
      _at(cosTheta).t * _planePhase(props, thicknessM, cosTheta);

  @override
  Complex r(double cosTheta) =>
      _at(cosTheta).r * _planePhase(props, thicknessM, cosTheta);
}

/// Tabulates T and R on a uniform grid in cos(theta) and interpolates
/// linearly. Used for the field grids, where the same wall is hit millions of
/// times. [kTableSize] steps keep the interpolation error far under 0.01 dB
/// away from grazing incidence.
class _TableCoefficients implements _Coefficients {
  _TableCoefficients(
    MaterialProperties props,
    double thicknessM,
    Polarization pol,
  ) : _tr = Float64List(kTableSize + 1),
      _ti = Float64List(kTableSize + 1),
      _rr = Float64List(kTableSize + 1),
      _ri = Float64List(kTableSize + 1) {
    for (int i = 0; i <= kTableSize; i++) {
      final double c = i / kTableSize;
      final SlabResult s = WallSlab.computeFor(
        props: props,
        thicknessM: thicknessM,
        angleDeg: _angleDegFromCos(c),
        polarization: pol,
      );
      final Complex ph = _planePhase(props, thicknessM, c);
      final Complex t = s.t * ph;
      final Complex r = s.r * ph;
      _tr[i] = t.re;
      _ti[i] = t.im;
      _rr[i] = r.re;
      _ri[i] = r.im;
    }
  }

  static const int kTableSize = 1024;

  final Float64List _tr;
  final Float64List _ti;
  final Float64List _rr;
  final Float64List _ri;

  static Complex _lerp(Float64List re, Float64List im, double c) {
    final double x = c.clamp(0.0, 1.0) * kTableSize;
    final int i = x.floor().clamp(0, kTableSize - 1);
    final double f = x - i;
    return Complex(
      re[i] + (re[i + 1] - re[i]) * f,
      im[i] + (im[i + 1] - im[i]) * f,
    );
  }

  @override
  Complex t(double cosTheta) => _lerp(_tr, _ti, cosTheta);

  @override
  Complex r(double cosTheta) => _lerp(_rr, _ri, cosTheta);
}

/// One wall prepared for the engine: its line, its solid pieces and its
/// coefficients.
class _Line {
  _Line(this.index, RoomWall w, _Coefficients coeffs)
    : a = w.a,
      length = w.length,
      u = (w.b - w.a).scale(1 / w.length),
      n = P2(-(w.b.y - w.a.y) / w.length, (w.b.x - w.a.x) / w.length),
      pieces = w.solidPieces,
      co = coeffs;

  final int index;
  final P2 a;
  final double length;

  /// Unit vector along the wall.
  final P2 u;

  /// Unit normal.
  final P2 n;

  final List<(double, double)> pieces;
  final _Coefficients co;

  /// Signed distance of [p] from the wall's line.
  double side(P2 p) => n.dot(p - a);

  /// Position of [p] along the line, meters from [a].
  double along(P2 p) => u.dot(p - a);

  /// Mirror image of [p] across the line.
  P2 mirror(P2 p) => p - n.scale(2 * side(p));

  bool solidAt(double s) {
    for (final (double, double) pc in pieces) {
      if (s >= pc.$1 && s <= pc.$2) return true;
    }
    return false;
  }
}

// ── Per-point result ─────────────────────────────────────────────────────

/// A wall the straight line from the AP to a point crosses.
class CrossedWall {
  const CrossedWall({
    required this.wallIndex,
    required this.angleDeg,
    required this.lossDb,
  });

  final int wallIndex;
  final double angleDeg;

  /// P.2040 transmission loss at this angle, dB.
  final double lossDb;
}

/// Everything the readouts need at one point, at one frequency.
class PointReport {
  const PointReport({
    required this.freqMHz,
    required this.distanceM,
    required this.fsplDb,
    required this.crossed,
    required this.straightAmp2,
    required this.directAmp2,
    required this.coherentAmp2,
    required this.averageAmp2,
    required this.pathCount,
    required this.apertureGainDb,
  });

  final double freqMHz;

  /// Straight-line distance from the AP, m.
  final double distanceM;

  /// Free-space path loss over [distanceM], dB (exact form, fspl_math).
  final double fsplDb;

  /// Walls on the straight line, in order from the AP.
  final List<CrossedWall> crossed;

  /// |amplitude|^2 of the direct path with the plain slab loss of every wall
  /// on the straight line and no diffraction, relative to free space.
  final double straightAmp2;

  /// |amplitude|^2 of the direct path as the model uses it (with the
  /// diffraction screens when diffraction is on), relative to free space.
  final double directAmp2;

  /// |U|^2 of every path added with its phase, in 1/m^2.
  final double coherentAmp2;

  /// Sum of every path's |a|^2: the local average, in 1/m^2.
  final double averageAmp2;

  /// Paths that reached the point (direct plus reflections).
  final int pathCount;

  final double apertureGainDb;

  static double _db(double x) =>
      x > 0 ? 10 * FsplMath.log10(x) : double.negativeInfinity;

  /// Plain slab loss of the walls on the straight line, dB (may be infinite
  /// for metal).
  double get wallLossDb => -_db(straightAmp2);

  /// What diffraction changes on the direct path, dB. Positive: the edges
  /// cost signal. Negative: they bring signal around a wall. Null when the
  /// straight line is fully blocked, so there is no finite reference.
  double? get diffractionDb {
    if (straightAmp2 <= 0) return null;
    return _db(straightAmp2) - _db(directAmp2);
  }

  /// Path gain of the direct path alone, dB.
  double get directGainDb =>
      apertureGainDb + _db(directAmp2) - 20 * FsplMath.log10(distanceM);

  /// Path gain, every path with its phase, dB.
  double get coherentGainDb => apertureGainDb + _db(coherentAmp2);

  /// Path gain, the local average, dB.
  double get averageGainDb => apertureGainDb + _db(averageAmp2);

  /// What the reflections add (positive) or cancel (negative) at this exact
  /// spot, dB. Null when the direct path carries nothing.
  double? get reflectionsDb {
    if (directAmp2 <= 0) return null;
    return coherentGainDb - directGainDb;
  }
}

/// A computed received-power grid.
class FieldGrid {
  const FieldGrid({
    required this.origin,
    required this.cellM,
    required this.cols,
    required this.rows,
    required this.values,
  });

  /// Corner of cell (0, 0), meters.
  final P2 origin;
  final double cellM;
  final int cols;
  final int rows;

  /// Row-major, cols x rows, dB.
  final Float32List values;

  double at(int col, int row) => values[row * cols + col];

  /// Center of cell ([col], [row]).
  P2 centerOf(int col, int row) =>
      P2(origin.x + (col + 0.5) * cellM, origin.y + (row + 0.5) * cellM);
}

/// Points per cell side in the average map (2 x 2 = 4 per cell).
const int kAverageSamples = 2;

/// Floor for a dB value that would be minus infinity.
const double kGainFloorDb = -250;

/// Closest a point may be to the AP, m. Below this the far-field 1/r model
/// means nothing; the cell holding the AP is evaluated at this distance.
const double kMinDistanceM = 0.1;

// ── The engine ────────────────────────────────────────────────────────────

class RoomEngine {
  RoomEngine({
    required this.walls,
    required this.ap,
    required this.radio,
    bool exactCoefficients = false,
  }) {
    final double lambda = radio.lambda;
    _lambda = lambda;
    _k = radio.k;
    for (int i = 0; i < walls.length; i++) {
      final RoomWall w = walls[i];
      if (w.length <= 1e-6) continue;
      final MaterialProperties props = MaterialProperties.of(
        w.material,
        radio.fGhz,
      );
      final double t = w.thicknessMm / 1000;
      final _Coefficients co = exactCoefficients
          ? _ExactCoefficients(props, t, radio.polarization)
          : _TableCoefficients(props, t, radio.polarization);
      _lines.add(_Line(i, w, co));
    }
    int most = 1;
    for (final _Line l in _lines) {
      if (l.pieces.length > most) most = l.pieces.length;
    }
    _nuA = Float64List(most);
    _nuB = Float64List(most);
    _buildImages();
  }

  final List<RoomWall> walls;
  final P2 ap;
  final RoomRadio radio;

  // Scratch for [_legT]: Fresnel parameters of each piece's two ends, sized
  // to the wall with the most pieces.
  late final Float64List _nuA;
  late final Float64List _nuB;

  late final double _lambda;
  late final double _k;
  final List<_Line> _lines = <_Line>[];
  final List<_Image1> _images1 = <_Image1>[];
  final List<_Image2> _images2 = <_Image2>[];

  /// Skip a finite-wall reflection when both ends of the wall sit this far
  /// past the reflection point in Fresnel terms: |K(4)| is about 0.056, so
  /// the skipped bounce is at least 25 dB below the same bounce off a long
  /// wall.
  static const double _pruneNu = 4;

  void _buildImages() {
    if (radio.reflectionOrder < 1) return;
    for (final _Line l in _lines) {
      final double s = l.side(ap);
      if (s.abs() < 1e-9) continue;
      _images1.add(_Image1(l, l.mirror(ap), s > 0));
    }
    if (radio.reflectionOrder < 2) return;
    for (final _Image1 i1 in _images1) {
      for (final _Line l2 in _lines) {
        if (identical(l2, i1.line)) continue;
        final double s = l2.side(i1.image);
        if (s.abs() < 1e-9) continue;
        _images2.add(_Image2(i1, l2, l2.mirror(i1.image), s > 0));
      }
    }
  }

  /// The slab transmission coefficient as the path sum uses it.
  /// See [_planePhase]: T times e^(+j k0 d cos theta).
  static Complex insertionT(
    MaterialProperties props,
    double thicknessM,
    double cosTheta,
    Polarization pol,
  ) =>
      WallSlab.computeFor(
        props: props,
        thicknessM: thicknessM,
        angleDeg: _angleDegFromCos(cosTheta),
        polarization: pol,
      ).t *
      _planePhase(props, thicknessM, cosTheta);

  /// Number of image sources (first plus second order).
  int get imageCount => _images1.length + _images2.length;

  // ── Building blocks ──

  /// Plain slab transmission along the segment [p] -> [q], skipping the
  /// lines in [skipA] and [skipB]. A line counts when the segment crosses it
  /// inside a solid piece.
  Complex _hardT(P2 p, P2 q, [_Line? skipA, _Line? skipB]) {
    Complex acc = Complex.one;
    final P2 d = q - p;
    final double len = d.length;
    if (len <= 0) return acc;
    for (final _Line l in _lines) {
      if (identical(l, skipA) || identical(l, skipB)) continue;
      final double s1 = l.side(p);
      final double s2 = l.side(q);
      if (s1 == 0 || s2 == 0 || (s1 > 0) == (s2 > 0)) continue;
      final double f = s1 / (s1 - s2);
      final P2 x = p + d.scale(f);
      if (!l.solidAt(l.along(x))) continue;
      final double c = (l.n.dot(d) / len).abs();
      acc = acc * l.co.t(c);
      if (acc.re == 0 && acc.im == 0) return acc;
    }
    return acc;
  }

  /// The Fresnel parameter of the wall point [s] meters along [l] for a ray
  /// from [src] to [dst] that crosses the line at [s0].
  double _nuAt(_Line l, P2 src, P2 dst, double direct, double s, double s0) {
    final P2 e = l.a + l.u.scale(s);
    final double delta = src.distanceTo(e) + e.distanceTo(dst) - direct;
    final double v = 2 * math.sqrt((delta > 0 ? delta : 0) / _lambda);
    return s < s0 ? -v : v;
  }

  /// W for line [l] and the ray [src] -> [dst] crossing it at [s0]: the
  /// share of the wavefront that meets the solid pieces (1 for an endless
  /// wall, 0 for an open line). Null when the whole wall is so far off the
  /// ray that it is skipped (only asked for when [prune] is set).
  Complex? _screenWeight(
    _Line l,
    P2 src,
    P2 dst,
    double direct,
    double s0, {
    bool prune = false,
  }) {
    if (prune) {
      final double nu0 = _nuAt(l, src, dst, direct, 0, s0);
      final double nu1 = _nuAt(l, src, dst, direct, l.length, s0);
      if ((nu0 > _pruneNu && nu1 > _pruneNu) ||
          (nu0 < -_pruneNu && nu1 < -_pruneNu)) {
        return null;
      }
    }
    Complex w = Complex.zero;
    for (final (double, double) pc in l.pieces) {
      final double na = _nuAt(l, src, dst, direct, pc.$1, s0);
      final double nb = _nuAt(l, src, dst, direct, pc.$2, s0);
      w = w + _KTable.at(na) - _KTable.at(nb);
    }
    return w;
  }

  /// Skip the Fresnel terms on a reflected leg when every wall end is this
  /// far from the leg in Fresnel terms: |K(6)| is about 0.037, so the plain
  /// slab answer is within about 0.3 dB of the screened one.
  static const double _legNu = 6;

  /// Transmission along one leg of a reflected path, skipping the bounce
  /// walls [skipA] and [skipB]. With diffraction on, each wall line the leg
  /// crosses is a screen, as on the direct path, but the Fresnel terms are
  /// only computed when a wall end is near the leg; otherwise the plain slab
  /// T (or nothing) is used. Without this, a bounced path vanishes at a hard
  /// line behind every wall end.
  Complex _legT(P2 p, P2 q, [_Line? skipA, _Line? skipB]) {
    if (!radio.diffraction) return _hardT(p, q, skipA, skipB);
    Complex acc = Complex.one;
    final P2 d = q - p;
    final double len = d.length;
    if (len <= 0) return acc;
    for (final _Line l in _lines) {
      if (identical(l, skipA) || identical(l, skipB)) continue;
      final double s1 = l.side(p);
      final double s2 = l.side(q);
      if (s1 == 0 || s2 == 0 || (s1 > 0) == (s2 > 0)) continue;
      final double f = s1 / (s1 - s2);
      final double s0 = l.along(p + d.scale(f));
      final double c = (l.n.dot(d) / len).abs();
      final Complex t = l.co.t(c);
      // One Fresnel parameter per piece end, reused for W when any is near.
      final int np = l.pieces.length;
      bool near = false;
      for (int i = 0; i < np; i++) {
        final (double, double) pc = l.pieces[i];
        final double na = _nuAt(l, p, q, len, pc.$1, s0);
        final double nb = _nuAt(l, p, q, len, pc.$2, s0);
        _nuA[i] = na;
        _nuB[i] = nb;
        if (na.abs() < _legNu || nb.abs() < _legNu) near = true;
      }
      if (!near) {
        if (l.solidAt(s0)) acc = acc * t;
      } else {
        Complex w = Complex.zero;
        for (int i = 0; i < np; i++) {
          w = w + _KTable.at(_nuA[i]) - _KTable.at(_nuB[i]);
        }
        acc = acc * (Complex.one - (Complex.one - t) * w);
      }
      if (acc.re == 0 && acc.im == 0) return acc;
    }
    return acc;
  }

  /// Direct-path amplitude factor (relative to free space) with diffraction:
  /// the product of 1 - (1 - T) W over every wall line the ray crosses.
  Complex _screenedDirect(P2 p, double r) {
    Complex acc = Complex.one;
    final P2 d = p - ap;
    for (final _Line l in _lines) {
      final double s1 = l.side(ap);
      final double s2 = l.side(p);
      if (s1 == 0 || s2 == 0 || (s1 > 0) == (s2 > 0)) continue;
      final double f = s1 / (s1 - s2);
      final P2 x = ap + d.scale(f);
      final double s0 = l.along(x);
      final double c = (l.n.dot(d) / r).abs();
      final Complex t = l.co.t(c);
      final Complex w = _screenWeight(l, ap, p, r, s0)!;
      acc = acc * (Complex.one - (Complex.one - t) * w);
    }
    return acc;
  }

  // ── Paths ──

  /// Calls [emit] with (amplitude a_i including 1/r, path length r_i) for
  /// every path that reaches [p]. Returns the direct path's factors via
  /// [onDirect] (straight, used).
  void _paths(
    P2 p,
    void Function(Complex a, double r) emit, {
    void Function(double r, Complex straight, Complex used)? onDirect,
  }) {
    double r = ap.distanceTo(p);
    if (r < kMinDistanceM) r = kMinDistanceM;
    final Complex straight = _hardT(ap, p);
    final Complex used = radio.diffraction ? _screenedDirect(p, r) : straight;
    onDirect?.call(r, straight, used);
    emit(used.scale(1 / r), r);

    for (final _Image1 im in _images1) {
      final _Line l = im.line;
      final double sp = l.side(p);
      if (sp == 0 || (sp > 0) != im.sourcePositive) continue;
      final double ri = im.image.distanceTo(p);
      if (ri <= 0) continue;
      final double si = l.side(im.image);
      final P2 q = im.image + (p - im.image).scale(si / (si - sp));
      final double s0 = l.along(q);
      Complex w;
      if (radio.diffraction) {
        final Complex? ww = _screenWeight(l, im.image, p, ri, s0, prune: true);
        if (ww == null) continue;
        w = ww;
      } else {
        if (!l.solidAt(s0)) continue;
        w = Complex.one;
      }
      final double c = (l.n.dot(p - im.image) / ri).abs();
      Complex a = l.co.r(c) * w;
      a = a * _legT(ap, q, l) * _legT(q, p, l);
      if (a.re == 0 && a.im == 0) continue;
      emit(a.scale(1 / ri), ri);
    }

    for (final _Image2 im in _images2) {
      final _Line l1 = im.first.line;
      final _Line l2 = im.line;
      // P must be on the first image's side of the second wall.
      final double sp2 = l2.side(p);
      if (sp2 == 0 || (sp2 > 0) != im.firstImagePositive) continue;
      // Unfold across the second wall: the first bounce is the straight line
      // from the first image to the mirrored receiver.
      final P2 pm = l2.mirror(p);
      final double spm = l1.side(pm);
      if (spm == 0 || (spm > 0) != im.first.sourcePositive) continue;
      final double ri = im.image.distanceTo(p);
      if (ri <= 0) continue;
      final P2 i1 = im.first.image;
      final double si1 = l1.side(i1);
      final P2 q1 = i1 + (pm - i1).scale(si1 / (si1 - spm));
      // The first bounce must happen before the second wall.
      final double sq1 = l2.side(q1);
      if (sq1 == 0 || (sq1 > 0) != im.firstImagePositive) continue;
      final double si2 = l2.side(im.image);
      final P2 q2 = im.image + (p - im.image).scale(si2 / (si2 - sp2));
      final double s01 = l1.along(q1);
      final double s02 = l2.along(q2);
      Complex w1;
      Complex w2;
      if (radio.diffraction) {
        final Complex? a2 = _screenWeight(
          l2,
          im.image,
          p,
          ri,
          s02,
          prune: true,
        );
        if (a2 == null) continue;
        final Complex? a1 = _screenWeight(l1, i1, pm, ri, s01, prune: true);
        if (a1 == null) continue;
        w1 = a1;
        w2 = a2;
      } else {
        if (!l2.solidAt(s02) || !l1.solidAt(s01)) continue;
        w1 = Complex.one;
        w2 = Complex.one;
      }
      final double c1 = (l1.n.dot(pm - i1) / ri).abs();
      final double c2 = (l2.n.dot(p - im.image) / ri).abs();
      Complex a = l1.co.r(c1) * l2.co.r(c2) * w1 * w2;
      if (a.re == 0 && a.im == 0) continue;
      a = a * _legT(ap, q1, l1) * _legT(q1, q2, l1, l2) * _legT(q2, p, l2);
      if (a.re == 0 && a.im == 0) continue;
      emit(a.scale(1 / ri), ri);
    }
  }

  /// |U|^2 (coherent) and sum |a_i|^2 (average) at [p], in 1/m^2.
  (double coherent, double average) powerAt(P2 p) {
    double ur = 0;
    double ui = 0;
    double avg = 0;
    final double k = _k;
    _paths(p, (Complex a, double r) {
      final double ph = -k * r;
      final double c = math.cos(ph);
      final double s = math.sin(ph);
      ur += a.re * c - a.im * s;
      ui += a.re * s + a.im * c;
      avg += a.abs2;
    });
    return (ur * ur + ui * ui, avg);
  }

  /// The local-average path loss sum only (cheaper: no phase).
  double averageAt(P2 p) {
    double avg = 0;
    _paths(p, (Complex a, double r) => avg += a.abs2);
    return avg;
  }

  /// Full readout at [p].
  PointReport report(P2 p) {
    double ur = 0;
    double ui = 0;
    double avg = 0;
    int count = 0;
    double dist = 0;
    Complex straight = Complex.one;
    Complex used = Complex.one;
    final double k = _k;
    _paths(
      p,
      (Complex a, double r) {
        final double ph = -k * r;
        final double c = math.cos(ph);
        final double s = math.sin(ph);
        ur += a.re * c - a.im * s;
        ui += a.re * s + a.im * c;
        avg += a.abs2;
        if (a.abs2 > 0) count++;
      },
      onDirect: (double r, Complex st, Complex us) {
        dist = r;
        straight = st;
        used = us;
      },
    );
    return PointReport(
      freqMHz: radio.freqMHz,
      distanceM: dist,
      fsplDb: FsplMath.fsplDb(dist, radio.freqMHz),
      crossed: _crossedWalls(p),
      straightAmp2: straight.abs2,
      directAmp2: used.abs2,
      coherentAmp2: ur * ur + ui * ui,
      averageAmp2: avg,
      pathCount: count,
      apertureGainDb: radio.apertureGainDb,
    );
  }

  List<CrossedWall> _crossedWalls(P2 p) {
    final P2 d = p - ap;
    final double len = d.length;
    final List<(double, CrossedWall)> hits = <(double, CrossedWall)>[];
    if (len <= 0) return const <CrossedWall>[];
    for (final _Line l in _lines) {
      final double s1 = l.side(ap);
      final double s2 = l.side(p);
      if (s1 == 0 || s2 == 0 || (s1 > 0) == (s2 > 0)) continue;
      final double f = s1 / (s1 - s2);
      final P2 x = ap + d.scale(f);
      if (!l.solidAt(l.along(x))) continue;
      final double c = (l.n.dot(d) / len).abs();
      final double deg = _angleDegFromCos(c);
      final RoomWall w = walls[l.index];
      final SlabResult s = WallSlab.compute(
        material: w.material,
        fGhz: radio.fGhz,
        thicknessM: w.thicknessMm / 1000,
        angleDeg: deg,
        polarization: radio.polarization,
      );
      hits.add((
        f,
        CrossedWall(
          wallIndex: l.index,
          angleDeg: deg,
          lossDb: s.transmissionLossDb,
        ),
      ));
    }
    hits.sort(
      ((double, CrossedWall) a, (double, CrossedWall) b) =>
          a.$1.compareTo(b.$1),
    );
    return <CrossedWall>[for (final (double, CrossedWall) h in hits) h.$2];
  }

  /// Path-gain grid of the local average, dB (add EIRP for dBm). Each cell
  /// averages [samples] x [samples] points spread evenly across it, in linear
  /// power, so the Fresnel fringes behind a doorway (finer than a cell) are
  /// averaged instead of aliasing into speckle.
  FieldGrid averageGrid({
    required P2 origin,
    required double cellM,
    required int cols,
    required int rows,
    int samples = kAverageSamples,
  }) {
    final Float32List out = Float32List(cols * rows);
    final double g0 = radio.apertureGainDb;
    final int n = samples < 1 ? 1 : samples;
    final double sub = cellM / n;
    for (int row = 0; row < rows; row++) {
      final double y0 = origin.y + row * cellM;
      for (int col = 0; col < cols; col++) {
        final double x0 = origin.x + col * cellM;
        double sum = 0;
        for (int j = 0; j < n; j++) {
          for (int i = 0; i < n; i++) {
            sum += averageAt(P2(x0 + (i + 0.5) * sub, y0 + (j + 0.5) * sub));
          }
        }
        final double avg = sum / (n * n);
        out[row * cols + col] = avg > 0
            ? g0 + 10 * math.log(avg) / math.ln10
            : kGainFloorDb;
      }
    }
    return FieldGrid(
      origin: origin,
      cellM: cellM,
      cols: cols,
      rows: rows,
      values: out,
    );
  }

  /// Close-up grid of the fine ripple: coherent power relative to the local
  /// average at each point, dB. 0 dB is the average; the nulls go deeply
  /// negative.
  FieldGrid rippleGrid({
    required P2 center,
    required double sizeM,
    required int n,
  }) {
    final double cell = sizeM / n;
    final P2 origin = P2(center.x - sizeM / 2, center.y - sizeM / 2);
    final Float32List out = Float32List(n * n);
    for (int row = 0; row < n; row++) {
      final double y = origin.y + (row + 0.5) * cell;
      for (int col = 0; col < n; col++) {
        final double x = origin.x + (col + 0.5) * cell;
        final (double coh, double avg) = powerAt(P2(x, y));
        out[row * n + col] = (coh > 0 && avg > 0)
            ? 10 * math.log(coh / avg) / math.ln10
            : (avg > 0 ? kGainFloorDb : 0);
      }
    }
    return FieldGrid(
      origin: origin,
      cellM: cell,
      cols: n,
      rows: n,
      values: out,
    );
  }
}

class _Image1 {
  _Image1(this.line, this.image, this.sourcePositive);

  final _Line line;
  final P2 image;

  /// Which side of [line] the AP is on.
  final bool sourcePositive;
}

class _Image2 {
  _Image2(this.first, this.line, this.image, this.firstImagePositive);

  final _Image1 first;
  final _Line line;
  final P2 image;

  /// Which side of [line] the first image is on.
  final bool firstImagePositive;
}

// ── Off-thread job ────────────────────────────────────────────────────────

/// Everything one computation needs. Plain data, so it can cross to a
/// background isolate.
class RoomFieldJob {
  const RoomFieldJob({
    required this.walls,
    required this.ap,
    required this.radio,
    required this.widthM,
    required this.heightM,
    required this.cellM,
    this.rippleCenter,
    this.rippleSizeM = kRippleWindowM,
    this.rippleCells = kRippleCells,
    this.includeAverage = true,
  });

  final List<RoomWall> walls;
  final P2 ap;
  final RoomRadio radio;
  final double widthM;
  final double heightM;
  final double cellM;

  /// Center of the close-up, or null for none.
  final P2? rippleCenter;
  final double rippleSizeM;
  final int rippleCells;

  /// False when only the close-up changed (the client moved).
  final bool includeAverage;
}

/// Side of the close-up window, m.
const double kRippleWindowM = 0.5;

/// Close-up cells per side: 4 mm cells, about six per half wavelength at
/// 6.5 GHz.
const int kRippleCells = 125;

/// What one job produced, with how long each part took.
class RoomFieldResult {
  const RoomFieldResult({
    this.average,
    this.ripple,
    required this.averageMs,
    required this.rippleMs,
  });

  final FieldGrid? average;
  final FieldGrid? ripple;
  final int averageMs;
  final int rippleMs;
}

/// Runs [job]. Top-level so `compute` can send it to another isolate.
RoomFieldResult computeRoomField(RoomFieldJob job) {
  final Stopwatch sw = Stopwatch()..start();
  final RoomEngine e = RoomEngine(
    walls: job.walls,
    ap: job.ap,
    radio: job.radio,
  );
  FieldGrid? avg;
  int avgMs = 0;
  if (job.includeAverage) {
    final int cols = (job.widthM / job.cellM).ceil();
    final int rows = (job.heightM / job.cellM).ceil();
    avg = e.averageGrid(
      origin: const P2(0, 0),
      cellM: job.cellM,
      cols: cols,
      rows: rows,
    );
    avgMs = sw.elapsedMilliseconds;
  }
  FieldGrid? ripple;
  int rippleMs = 0;
  final P2? c = job.rippleCenter;
  if (c != null) {
    final int t0 = sw.elapsedMilliseconds;
    ripple = e.rippleGrid(
      center: c,
      sizeM: job.rippleSizeM,
      n: job.rippleCells,
    );
    rippleMs = sw.elapsedMilliseconds - t0;
  }
  return RoomFieldResult(
    average: avg,
    ripple: ripple,
    averageMs: avgMs,
    rippleMs: rippleMs,
  );
}
