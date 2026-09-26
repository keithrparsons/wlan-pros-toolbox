// Antenna pattern math for the Wi-Fi Classroom "Antenna Pattern" tool
// (antenna-pattern). Pure Dart: no Flutter import, so every number the screen
// shows is unit-testable.
//
// CLEAN-ROOM BUILD (2026-09-25) from myPKA
// Deliverables/2026-09-25-antenna-simulator-research/brief.md (§2
// reconstruction, §3 parametric models) per
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/14-antenna-pattern.md. No
// vendor's or planning tool's pattern-viewer code was read.
//
// ANGLES. Every pattern here is a function of
//   theta  zenith angle in degrees: 0 = straight up, 90 = horizon,
//          180 = straight down;
//   phi    azimuth in degrees, in the MSI sense: 0 = boresight, increasing
//          clockwise seen from above (brief §1a).
// The MSI vertical-cut angle v (0 = front horizon, 90 = down, 180 = back
// horizon, 270 = up) maps onto (theta, phi) with [msiVerticalDirection].
//
// POWER IS CONSERVED. A parametric model is scaled so its gain averaged over
// the whole sphere is exactly 1 (0 dBi): a lossless antenna radiates what it
// is fed, so a higher gain can only move energy, never add it (brief §5.1).
// The peak gain shown is the integrated directivity of the shape.
//
// NOT IMPLEMENTED, on purpose: the front/back "hybrid" reconstruction
// (US7535425, brief §2c). Summing and cross-weighted only.

import 'dart:math' as math;
import 'dart:typed_data';

// ── Units and closed-form relations ────────────────────────────────────────

/// A half-wave dipole's gain over isotropic: 0 dBd = 2.15 dBi (brief §3d).
const double kDipoleGainDbi = 2.15;

double dbdToDbi(double dbd) => dbd + kDipoleGainDbi;
double dbiToDbd(double dbi) => dbi - kDipoleGainDbi;

double _log10(double x) => math.log(x) / math.ln10;
double _rad(double deg) => deg * math.pi / 180;
double _deg(double rad) => rad * 180 / math.pi;

/// ITU-R F.1336-5 recommends 2.1, omni: θ3 = 107.6 × 10^(−0.1·G0), the
/// vertical 3 dB beamwidth in degrees for a peak gain G0 in dBi (brief §3b).
double f1336OmniBeamwidthDeg(double g0Dbi) =>
    107.6 * math.pow(10, -0.1 * g0Dbi).toDouble();

/// The practical gain-beamwidth constant, ITU-R F.1336-5 eq. 3a (brief §3c).
const double kItuPracticalConstant = 31000;

/// A second practical constant, better for planar arrays (brief §3c,
/// secondary source).
const double kPlanarArrayConstant = 32400;

/// The ideal constant: square degrees in a sphere, 4π(180/π)² (Kraus).
const double kKrausIdealConstant = 41253;

/// Gain in dBi from two beamwidths in degrees: 10·log10(constant / (θ·φ)).
double gainFromBeamwidthsDbi(
  double hDeg,
  double vDeg, {
  double constant = kItuPracticalConstant,
}) => 10 * _log10(constant / (hDeg * vDeg));

/// Polarization mismatch loss, −20·log10|cos Δ| dB, for an angle Δ between
/// two linear polarizations. Returns [double.infinity] at 90° (crossed), where
/// the theory says nothing is received; the screen caps it for display.
double polarizationMismatchLossDb(double deltaDeg) {
  final double c = math.cos(_rad(deltaDeg)).abs();
  if (c < 1e-9) return double.infinity;
  return -20 * _log10(c);
}

// ── The MSI vertical cut on the sphere ─────────────────────────────────────

/// Direction of the MSI vertical-cut angle [v] (brief §1a): front half
/// v in [0, 90] gives theta = 90 + v, v in [270, 360) gives theta = v − 270,
/// both at phi = 0; back half v in (90, 270) gives theta = 270 − v at
/// phi = 180.
({int theta, int phi}) msiVerticalDirection(int v) {
  final int a = ((v % 360) + 360) % 360;
  if (a <= 90) return (theta: 90 + a, phi: 0);
  if (a >= 270) return (theta: a - 270, phi: 0);
  return (theta: 270 - a, phi: 180);
}

/// The MSI vertical angle of the FRONT-half direction at zenith [theta].
int msiVerticalOfFrontTheta(int theta) =>
    theta >= 90 ? theta - 90 : theta + 270;

// ── Parametric models ──────────────────────────────────────────────────────

/// A pattern shape: relative power (linear, any scale, >= 0) in a direction.
abstract class PatternShape {
  const PatternShape();

  double relativePower(double thetaDeg, double phiDeg);

  /// True when the shape does not depend on phi, so a grid can be filled one
  /// row at a time.
  bool get axisymmetric => false;
}

/// Half-wave dipole field, F(θ) = cos((π/2)·cos θ) / sin θ (brief §3b).
double dipoleField(double thetaRad) {
  final double s = math.sin(thetaRad);
  if (s.abs() < 1e-9) return 0;
  return math.cos(math.pi / 2 * math.cos(thetaRad)) / s;
}

/// Uniform N-element array factor along z, |sin(Nψ/2) / (N·sin(ψ/2))| with
/// ψ = k·d·cos θ + α (brief §3b). Electrical downtilt by progressive phase:
/// α = k·d·sin(tilt), which puts the ψ = 0 beam at tilt degrees below the
/// horizon. [spacingWl] is the element spacing in wavelengths.
double arrayFactor(double thetaRad, int n, double spacingWl, double tiltDeg) {
  if (n <= 1) return 1;
  final double kd = 2 * math.pi * spacingWl;
  final double psi = kd * math.cos(thetaRad) + kd * math.sin(_rad(tiltDeg));
  final double half = psi / 2;
  final double den = n * math.sin(half);
  if (den.abs() < 1e-9) return 1; // the limit at ψ = 2πm is magnitude 1
  return (math.sin(n * half) / den).abs();
}

class DipoleShape extends PatternShape {
  const DipoleShape();

  @override
  double relativePower(double thetaDeg, double phiDeg) {
    final double f = dipoleField(_rad(thetaDeg));
    return f * f;
  }

  @override
  bool get axisymmetric => true;
}

/// Collinear omni: a vertical stack of [elements] dipoles, element pattern
/// times array factor (pattern multiplication, brief §3b).
class CollinearShape extends PatternShape {
  const CollinearShape({
    required this.elements,
    required this.spacingWl,
    required this.tiltDeg,
  });

  final int elements;
  final double spacingWl;
  final double tiltDeg;

  @override
  double relativePower(double thetaDeg, double phiDeg) {
    final double t = _rad(thetaDeg);
    final double f =
        dipoleField(t) * arrayFactor(t, elements, spacingWl, tiltDeg);
    return f * f;
  }

  @override
  bool get axisymmetric => true;
}

/// ITU-R F.1336-5 omni envelope set by its peak gain (brief §3b):
/// G(θ) = G0 − 12·(θe/θ3)², θ3 = 107.6 × 10^(−0.1·G0), with the electrical
/// tilt mapping of recommends 2.5 (eq. 1e). F.1336 gives only the near-peak
/// form, so the envelope stops at [floorDb] below the peak.
class OmniF1336Shape extends PatternShape {
  const OmniF1336Shape({
    required this.gainDbi,
    required this.tiltDeg,
    this.floorDb = 30,
  });

  final double gainDbi;

  /// Downtilt, positive down.
  final double tiltDeg;
  final double floorDb;

  double get beamwidthDeg => f1336OmniBeamwidthDeg(gainDbi);

  @override
  double relativePower(double thetaDeg, double phiDeg) {
    final double elevation = 90 - thetaDeg; // positive up
    final double beta = tiltDeg;
    final double x = elevation + beta;
    final double thetaE = x >= 0 ? 90 * x / (90 + beta) : 90 * x / (90 - beta);
    final double r = thetaE / beamwidthDeg;
    final double loss = math.min(12 * r * r, floorDb);
    return math.pow(10, -loss / 10).toDouble();
  }

  @override
  bool get axisymmetric => true;
}

/// Directional element of 3GPP TR 38.901 Table 7.3-1 (brief §3a), with
/// mechanical downtilt by the rotation of 38.901 eqs. 7.1-18 and 7.1-19:
///   A_V(θ) = −min{12·((θ − 90)/θ3)², SLA_V}
///   A_H(φ) = −min{12·(φ/φ3)², A_max}
///   A(θ,φ) = −min{−(A_V + A_H), A_max}
class SectorShape extends PatternShape {
  const SectorShape({
    required this.hBeamwidthDeg,
    required this.vBeamwidthDeg,
    required this.frontToBackDb,
    required this.sideLobeDb,
    required this.tiltDeg,
  });

  final double hBeamwidthDeg;
  final double vBeamwidthDeg;

  /// A_max: the floor of the whole pattern, which sets front-to-back.
  final double frontToBackDb;

  /// SLA_V: the floor of the vertical cut.
  final double sideLobeDb;

  /// Mechanical downtilt, positive down.
  final double tiltDeg;

  /// 38.901 attenuation in dB (<= 0) in the antenna's own (untilted) frame.
  double attenuationDb(double thetaLocalDeg, double phiLocalDeg) {
    final double rv = (thetaLocalDeg - 90) / vBeamwidthDeg;
    final double av = -math.min(12 * rv * rv, sideLobeDb);
    double p = phiLocalDeg % 360;
    if (p > 180) p -= 360;
    final double rh = p / hBeamwidthDeg;
    final double ah = -math.min(12 * rh * rh, frontToBackDb);
    return -math.min(-(av + ah), frontToBackDb);
  }

  @override
  double relativePower(double thetaDeg, double phiDeg) {
    double tl = thetaDeg;
    double pl = phiDeg;
    if (tiltDeg != 0) {
      final double t = _rad(thetaDeg);
      final double p = _rad(phiDeg);
      final double b = _rad(tiltDeg);
      final double c =
          math.cos(p) * math.sin(t) * math.sin(b) + math.cos(t) * math.cos(b);
      tl = _deg(math.acos(c.clamp(-1.0, 1.0)));
      pl = _deg(
        math.atan2(
          math.sin(p) * math.sin(t),
          math.cos(p) * math.sin(t) * math.cos(b) - math.cos(t) * math.sin(b),
        ),
      );
    }
    return math.pow(10, attenuationDb(tl, pl) / 10).toDouble();
  }
}

// ── The analysis grid ──────────────────────────────────────────────────────

/// Rows of the analysis grid: theta 0..180 in 1° steps.
const int kThetaRows = 181;

/// Columns: phi 0..359 in 1° steps.
const int kPhiCols = 360;

/// Lowest value any grid holds, in dB below its peak (log of zero).
const double kGridFloorDb = 60;

/// Trapezoid weights for a sphere average over the 1° grid (sin θ).
final Float64List _sinWeights = Float64List.fromList(<double>[
  for (int i = 0; i < kThetaRows; i++) math.sin(_rad(i.toDouble())),
]);
final double _sinWeightSum = _sinWeights.fold(0, (double a, double b) => a + b);

/// Average of [linear] (row-major, kThetaRows × kPhiCols) over the sphere.
double sphereMean(Float64List linear) {
  double total = 0;
  for (int i = 0; i < kThetaRows; i++) {
    final double w = _sinWeights[i];
    if (w == 0) continue;
    double row = 0;
    final int base = i * kPhiCols;
    for (int j = 0; j < kPhiCols; j++) {
      row += linear[base + j];
    }
    total += w * row;
  }
  return total / (_sinWeightSum * kPhiCols);
}

/// Gain in dBi on a 1° zenith × azimuth grid.
class GainGrid {
  GainGrid._(this.dbi, this.directivityDbi) {
    double best = -double.infinity;
    int bestK = 0;
    for (int k = 0; k < dbi.length; k++) {
      if (dbi[k] > best) {
        best = dbi[k];
        bestK = k;
      }
    }
    peakDbi = best;
    peakTheta = bestK ~/ kPhiCols;
    peakPhi = bestK % kPhiCols;
  }

  /// Row-major [theta * kPhiCols + phi].
  final Float64List dbi;

  /// Directivity of the shape, integrated over the sphere.
  final double directivityDbi;

  late final double peakDbi;
  late final int peakTheta;
  late final int peakPhi;

  double at(int theta, int phi) =>
      dbi[theta.clamp(0, 180) * kPhiCols +
          ((phi % kPhiCols) + kPhiCols) % kPhiCols];

  /// Samples [shape] and scales it to dBi.
  ///
  /// With [peakDbi] null the shape is normalized so its sphere average is
  /// 1 (lossless): the peak comes out as the integrated directivity. With
  /// [peakDbi] given (an imported file's stated gain), the shape must already
  /// be relative to its peak (<= 1) and is placed at that gain unchanged.
  factory GainGrid.fromShape(PatternShape shape, {double? peakDbi}) {
    final Float64List lin = Float64List(kThetaRows * kPhiCols);
    for (int i = 0; i < kThetaRows; i++) {
      final int base = i * kPhiCols;
      if (shape.axisymmetric) {
        final double v = shape.relativePower(i.toDouble(), 0);
        for (int j = 0; j < kPhiCols; j++) {
          lin[base + j] = v;
        }
      } else {
        for (int j = 0; j < kPhiCols; j++) {
          lin[base + j] = shape.relativePower(i.toDouble(), j.toDouble());
        }
      }
    }
    return GainGrid.fromLinear(lin, peakDbi: peakDbi);
  }

  factory GainGrid.fromLinear(Float64List lin, {double? peakDbi}) {
    double max = 0;
    for (final double v in lin) {
      if (v > max) max = v;
    }
    if (max <= 0) {
      throw ArgumentError('A pattern needs some power in some direction.');
    }
    final double mean = sphereMean(lin);
    final double directivity = 10 * _log10(max / mean);
    final double top = peakDbi ?? directivity;
    final double ref = peakDbi == null ? max : 1.0;
    final Float64List dbi = Float64List(lin.length);
    final double floor = top - kGridFloorDb;
    for (int k = 0; k < lin.length; k++) {
      final double v = lin[k];
      dbi[k] = v <= 0 ? floor : math.max(floor, top + 10 * _log10(v / ref));
    }
    return GainGrid._(dbi, directivity);
  }

  /// Sphere average of the linear gain: 1.0 for a lossless parametric model.
  double get meanLinearGain {
    final Float64List lin = Float64List(dbi.length);
    for (int k = 0; k < dbi.length; k++) {
      lin[k] = math.pow(10, dbi[k] / 10).toDouble();
    }
    return sphereMean(lin);
  }

  /// The two cuts a pattern file carries, taken from this grid.
  PatternCuts toCuts() {
    final List<double> h = <double>[
      for (int a = 0; a < 360; a++) peakDbi - at(90, a),
    ];
    final List<double> v = <double>[
      for (int a = 0; a < 360; a++)
        () {
          final ({int theta, int phi}) d = msiVerticalDirection(a);
          return peakDbi - at(d.theta, d.phi);
        }(),
    ];
    return PatternCuts(
      horizontalLossDb: h,
      verticalLossDb: v,
      peakGainDbi: peakDbi,
    );
  }

  /// Highest gain in the rear 120° (phi 120..240, every theta): the worst
  /// case front-to-back is measured against, since the back lobe need not
  /// point straight back (NSMA FRTOBA, brief §5.4).
  ({double dbi, int theta, int phi}) worstRear() {
    double best = -double.infinity;
    int bt = 0, bp = 180;
    for (int i = 0; i < kThetaRows; i++) {
      for (int j = 120; j <= 240; j++) {
        final double g = at(i, j);
        if (g > best) {
          best = g;
          bt = i;
          bp = j;
        }
      }
    }
    return (dbi: best, theta: bt, phi: bp);
  }

  /// Gain in the direction exactly opposite the peak.
  double oppositePeakDbi() => at(180 - peakTheta, peakPhi + 180);
}

// ── Cuts ───────────────────────────────────────────────────────────────────

/// The two 2D cuts of a pattern file, in MSI form: loss in dB below the peak
/// (>= 0), 360 values at 1° steps each.
class PatternCuts {
  PatternCuts({
    required List<double> horizontalLossDb,
    required List<double> verticalLossDb,
    required this.peakGainDbi,
  }) : horizontalLossDb = List<double>.unmodifiable(horizontalLossDb),
       verticalLossDb = List<double>.unmodifiable(verticalLossDb) {
    if (horizontalLossDb.length != 360 || verticalLossDb.length != 360) {
      throw ArgumentError('Cuts hold 360 values each.');
    }
  }

  /// Index = MSI azimuth (0 = boresight, clockwise from above).
  final List<double> horizontalLossDb;

  /// Index = MSI vertical angle (0 = front horizon, 90 = down, 180 = back
  /// horizon, 270 = up).
  final List<double> verticalLossDb;

  final double peakGainDbi;

  /// Loss on the FRONT half of the vertical cut at zenith [theta].
  double frontVerticalLoss(int theta) =>
      verticalLossDb[msiVerticalOfFrontTheta(theta.clamp(0, 180))];

  /// Spread of the horizontal cut. Under 3 dB the antenna reads as an omni.
  double get horizontalSpreadDb {
    double lo = double.infinity, hi = -double.infinity;
    for (final double v in horizontalLossDb) {
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    return hi - lo;
  }

  bool get looksOmni => horizontalSpreadDb < 3;

  /// Half-power beamwidth of each cut (null when the cut never drops 3 dB,
  /// as an omni's horizontal cut does not).
  double? get horizontalBeamwidthDeg => halfPowerBeamwidthDeg(horizontalLossDb);
  double? get verticalBeamwidthDeg => halfPowerBeamwidthDeg(verticalLossDb);

  /// MSI vertical angle of the vertical cut's peak, folded to −90..+90
  /// (positive = below the horizon). The front half wins a tie.
  int get verticalPeakAngle {
    int best = 0;
    double lo = double.infinity;
    for (final int a in <int>[
      for (int k = 0; k <= 90; k++) k,
      for (int k = 359; k >= 270; k--) k,
      for (int k = 91; k < 270; k++) k,
    ]) {
      if (verticalLossDb[a] < lo - 1e-9) {
        lo = verticalLossDb[a];
        best = a;
      }
    }
    return best > 180 ? best - 360 : best;
  }
}

/// Half-power beamwidth of a circular 1° cut of losses: walk out from its
/// lowest-loss point both ways to where the loss is 3 dB worse, interpolating
/// between samples. Null when either side never gets there within 180°.
double? halfPowerBeamwidthDeg(List<double> lossDb) {
  final int n = lossDb.length;
  int p = 0;
  for (int k = 1; k < n; k++) {
    if (lossDb[k] < lossDb[p]) p = k;
  }
  final double target = lossDb[p] + 3;
  double? side(int dir) {
    double prev = lossDb[p];
    for (int k = 1; k <= n ~/ 2; k++) {
      final double v = lossDb[((p + dir * k) % n + n) % n];
      if (v >= target) {
        final double f = (target - prev) / (v - prev);
        return (k - 1) + f;
      }
      prev = v;
    }
    return null;
  }

  final double? right = side(1);
  final double? left = side(-1);
  if (right == null || left == null) return null;
  return right + left;
}

// ── Reconstruction from two cuts (brief §2) ────────────────────────────────

enum ReconstructionMethod {
  /// G(φ,θ) = G_H(φ) + G_V(θ) in dB, 3GPP TR 38.901 form, with a floor.
  summing('Summing'),

  /// Vasiliadis et al. 2005, k = 2.
  crossWeighted('Cross-weighted');

  const ReconstructionMethod(this.label);
  final String label;
}

/// The summing floor, dB below the peak (spec: 30 dB, as 3GPP's A_max).
const double kSummingFloorDb = 30;

/// A 3D shape estimated from two cuts. Uses the FRONT half of the vertical
/// cut for every azimuth, as the summing method does; the back half of the
/// vertical cut is therefore not reproduced (brief §2, known artifact).
/// Bridging front and back would be the patented hybrid, which is out.
///
/// [shaping] scales every loss (1 = the file as loaded; above 1 narrows the
/// beams, below 1 flattens them): a what-if, labeled as such on screen.
class ReconstructedShape extends PatternShape {
  ReconstructedShape(this.cuts, this.method, {this.shaping = 1, this.k = 2}) {
    final List<double> h = cuts.horizontalLossDb;
    double minH = double.infinity, maxH = 0;
    for (final double v in h) {
      minH = math.min(minH, v);
      maxH = math.max(maxH, v);
    }
    double minV = double.infinity, maxV = 0;
    for (int t = 0; t <= 180; t++) {
      final double v = cuts.frontVerticalLoss(t);
      _vf[t] = v;
      minV = math.min(minV, v);
      maxV = math.max(maxV, v);
    }
    _minH = minH;
    _minV = minV;
    // The shared point of the two cuts is boresight at the horizon: in a
    // consistent file H(0) and V(0) are both the loss there, and subtracting
    // it once keeps both cuts exact. Many files instead normalize each cut to
    // its own peak (H(0) = 0 while V says the horizon is below the tilted
    // peak); taking the smaller of the two then gives classic summing of
    // normalized cuts instead of a double count.
    _c = math.min(cuts.horizontalLossDb[0], cuts.verticalLossDb[0]);
    // Never clip a value the file itself holds, or the loaded cuts would not
    // come back exactly: the floor is 30 dB or the deepest cut value.
    floorDb = math.max(
      kSummingFloorDb,
      math.max(maxH, cuts.verticalLossDb.reduce(math.max)),
    );
  }

  final PatternCuts cuts;
  final ReconstructionMethod method;
  final double shaping;
  final double k;
  late final double floorDb;

  final Float64List _vf = Float64List(181);
  late final double _minH;
  late final double _minV;
  late final double _c;

  static double _lerpCircular(List<double> a, double x) {
    final int n = a.length;
    final double w = ((x % n) + n) % n;
    final int i = w.floor();
    final double f = w - i;
    return a[i] * (1 - f) + a[(i + 1) % n] * f;
  }

  double _vFront(double theta) {
    final double t = theta.clamp(0, 180).toDouble();
    final int i = t.floor();
    if (i >= 180) return _vf[180];
    final double f = t - i;
    return _vf[i] * (1 - f) + _vf[i + 1] * f;
  }

  /// Loss in dB below the file's peak in a direction (before [shaping]).
  double lossDb(double thetaDeg, double phiDeg) {
    final double h = _lerpCircular(cuts.horizontalLossDb, phiDeg);
    final double v = _vFront(thetaDeg);
    switch (method) {
      case ReconstructionMethod.summing:
        return (h + v - _c).clamp(0.0, floorDb);
      case ReconstructionMethod.crossWeighted:
        final double gh = -(h - _minH);
        final double gv = -(v - _minV);
        final double hor = math.pow(10, gh / 10).toDouble();
        final double vert = math.pow(10, gv / 10).toDouble();
        final double w1 = vert * (1 - hor);
        final double w2 = hor * (1 - vert);
        final double den = math
            .pow(math.pow(w1, k) + math.pow(w2, k), 1 / k)
            .toDouble();
        // At the peak hor = vert = 1, so w1 = w2 = 0 and the formula is 0/0.
        // The spec sets it to 0 dB there.
        final double g = den < 1e-12 ? 0 : (w1 * gh + w2 * gv) / den;
        return (-g).clamp(0.0, floorDb);
    }
  }

  @override
  double relativePower(double thetaDeg, double phiDeg) =>
      math.pow(10, -shaping * lossDb(thetaDeg, phiDeg) / 10).toDouble();
}

/// How far an estimate is from the truth, over the directions that matter
/// (truth within [withinDb] of its peak), weighted by solid angle.
class ReconstructionError {
  const ReconstructionError({
    required this.rmsDb,
    required this.worstDb,
    required this.worstTheta,
    required this.worstPhi,
  });

  final double rmsDb;

  /// Signed: positive means the estimate shows more gain than the truth.
  final double worstDb;
  final int worstTheta;
  final int worstPhi;

  static ReconstructionError between(
    GainGrid truth,
    GainGrid estimate, {
    double withinDb = 30,
  }) {
    final double gate = truth.peakDbi - withinDb;
    double sum = 0, wsum = 0, worst = 0;
    int wt = 90, wp = 0;
    for (int i = 0; i < kThetaRows; i++) {
      final double w = _sinWeights[i];
      for (int j = 0; j < kPhiCols; j++) {
        final double t = truth.at(i, j);
        if (t < gate) continue;
        final double e = estimate.at(i, j) - t;
        if (w > 0) {
          sum += w * e * e;
          wsum += w;
        }
        if (e.abs() > worst.abs()) {
          worst = e;
          wt = i;
          wp = j;
        }
      }
    }
    return ReconstructionError(
      rmsDb: wsum == 0 ? 0 : math.sqrt(sum / wsum),
      worstDb: worst,
      worstTheta: wt,
      worstPhi: wp,
    );
  }
}
