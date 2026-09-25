// Wall slab physics for the Wi-Fi Lab "Wi-Fi Through a Wall" simulator
// (wifi-through-a-wall).
//
// CLEAN-ROOM BUILD (2026-09-25) from ITU-R P.2040-4 (09/2025) as set out in
// myPKA Deliverables/2026-09-25-wifi-lab-research/brief.md §6.3 (equations and
// Table 3 constants) and §6.4 (measured comparison data), per the spec
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/12-wall-slab.md. Nothing
// here is derived from any other simulator's code.
//
// What it computes, for one homogeneous wall in air:
//   - Material properties (P.2040 Table 3, Eqs. 57-58): e' = a·f^b, and
//     sigma = c·f^d, f in GHz, sigma in S/m.
//   - Complex relative permittivity (Eq. 59): e_rc = e' - j·17.98·sigma/f.
//   - Attenuation rate inside the material (Eq. 27a): A = 1636·sigma/sqrt(e')
//     dB/m, valid for tan(delta) < 0.5.
//   - Interface reflection R' for TE and TM (Eqs. 37a/37b), and the slab's
//     reflection R and transmission T (Eqs. 43a-44):
//       q = (2·pi·d/lambda)·sqrt(e_rc - sin^2 theta)
//       R = R'(1 - e^(-j2q)) / (1 - R'^2·e^(-j2q))
//       T = (1 - R'^2)·e^(-jq) / (1 - R'^2·e^(-j2q))
//
// The loss is split into two parts that add exactly to the total:
//   - absorption = -20·log10|e^(-jq)|, the decay along the path inside;
//   - reflection = -20·log10|(1 - R'^2) / (1 - R'^2·e^(-j2q))|, what the two
//     faces send back, including the thin-slab interference ripple.
// Computing the total as that sum (not as -10·log10|T|^2) keeps a metal wall
// finite: |T|^2 underflows to zero there, the two logs do not.
//
// No Flutter imports: the screen drives this, the tests pin it.

import 'dart:math' as math;

import 'complex.dart';

/// Speed of light in vacuum, m/s.
const double kSpeedOfLight = 299792458.0;

/// 20·log10(e): converts nepers of field decay to dB.
const double _kDbPerNeper = 8.685889638065037;

/// Polarization of the incident wave relative to the plane of incidence.
enum Polarization {
  /// Transverse electric: E perpendicular to the plane of incidence, so
  /// parallel to the wall face.
  te,

  /// Transverse magnetic: E in the plane of incidence.
  tm,
}

/// The ten ITU-R P.2040-4 Table 3 materials, with their Eq. 57-58
/// coefficients and valid frequency ranges, as transcribed in brief §6.3.
enum WallMaterial {
  concrete('Concrete', 5.24, 0, 0.0462, 0.7822, 1, 100),
  brick('Brick', 3.91, 0, 0.0238, 0.16, 1, 40),
  plasterboard('Plasterboard', 2.73, 0, 0.0085, 0.9395, 1, 100),
  wood('Wood', 1.99, 0, 0.0047, 1.0718, 0.001, 100),
  glass('Glass', 6.31, 0, 0.0036, 1.3394, 0.1, 100),
  ceilingBoard('Ceiling board', 1.48, 0, 0.0011, 1.0750, 1, 100),
  chipboard('Chipboard', 2.58, 0, 0.0217, 0.7800, 1, 100),
  plywood('Plywood', 2.71, 0, 0.33, 0, 1, 40),
  marble('Marble', 7.074, 0, 0.0055, 0.9262, 1, 60),
  metal('Metal', 1, 0, 1e7, 0, 1, 100);

  const WallMaterial(
    this.label,
    this.a,
    this.b,
    this.c,
    this.d,
    this.minGhz,
    this.maxGhz,
  );

  final String label;

  /// e' = a·f^b.
  final double a;
  final double b;

  /// sigma = c·f^d (S/m).
  final double c;
  final double d;

  /// P.2040 Table 3 valid range, GHz.
  final double minGhz;
  final double maxGhz;

  bool isValidAt(double fGhz) => fGhz >= minGhz && fGhz <= maxGhz;
}

/// A material's electrical properties at one frequency.
class MaterialProperties {
  const MaterialProperties({
    required this.material,
    required this.fGhz,
    required this.epsReal,
    required this.sigma,
  });

  factory MaterialProperties.of(WallMaterial m, double fGhz) {
    if (!(fGhz > 0)) throw ArgumentError.value(fGhz, 'fGhz', 'must be > 0');
    return MaterialProperties(
      material: m,
      fGhz: fGhz,
      epsReal: m.a * math.pow(fGhz, m.b),
      sigma: m.c * math.pow(fGhz, m.d),
    );
  }

  final WallMaterial material;
  final double fGhz;

  /// Real relative permittivity e'.
  final double epsReal;

  /// Conductivity sigma, S/m.
  final double sigma;

  /// Imaginary part magnitude, e'' = 17.98·sigma/f (Eq. 59).
  double get epsImag => 17.98 * sigma / fGhz;

  /// e_rc = e' - j·e'' (Eq. 59).
  Complex get epsComplex => Complex(epsReal, -epsImag);

  /// Loss tangent e''/e'. Eq. 27a is valid below 0.5.
  double get lossTangent => epsImag / epsReal;

  /// Whether Eq. 27a's low-loss condition (tan delta < 0.5) holds.
  bool get eq27aValid => lossTangent < 0.5;

  /// Free-space wavelength, m.
  double get lambdaAir => kSpeedOfLight / (fGhz * 1e9);

  /// Wavelength inside the material, lambda / sqrt(e') (brief §6.3, Eq. 41c).
  double get lambdaInMaterial => lambdaAir / math.sqrt(epsReal);

  /// Wavelength inside the material from the exact complex index,
  /// lambda / Re(sqrt(e_rc)). Differs from [lambdaInMaterial] only when the
  /// material is lossy enough that tan delta is not small.
  double get lambdaInMaterialExact => lambdaAir / epsComplex.sqrt().re;

  /// Attenuation rate, dB/m, by P.2040 Eq. 27a: 1636·sigma/sqrt(e').
  double get attenuationEq27a => 1636 * sigma / math.sqrt(epsReal);

  /// Attenuation rate, dB/m, from the exact complex index at normal
  /// incidence: 8.686·(2·pi/lambda)·|Im sqrt(e_rc)|. Eq. 27a is the low-loss
  /// approximation of this.
  double get attenuationExact =>
      _kDbPerNeper * (2 * math.pi / lambdaAir) * epsComplex.sqrt().im.abs();

  /// Skin depth, m: the distance over which the field falls to 1/e.
  double get skinDepth =>
      lambdaAir / (2 * math.pi * epsComplex.sqrt().im.abs());
}

/// One wall, one frequency, one angle, one polarization: the P.2040 result.
class SlabResult {
  SlabResult._({
    required this.props,
    required this.thicknessM,
    required this.angleDeg,
    required this.polarization,
    required this.interfaceR,
    required this.q,
    required this.r,
    required this.t,
    required this.absorptionDb,
    required this.reflectionPartDb,
  });

  final MaterialProperties props;
  final double thicknessM;
  final double angleDeg;
  final Polarization polarization;

  /// Single-face reflection coefficient R' (Eq. 37a or 37b).
  final Complex interfaceR;

  /// Electrical thickness q.
  final Complex q;

  /// Slab reflection coefficient R (Eq. 43a).
  final Complex r;

  /// Slab transmission coefficient T (Eq. 43b).
  final Complex t;

  /// Loss from absorption along the path inside, dB (>= 0).
  final double absorptionDb;

  /// Loss from reflection at the two faces and the interference between
  /// them, dB. Usually >= 0; a lossy slab near resonance can make it a
  /// fraction of a dB negative.
  final double reflectionPartDb;

  /// Total transmission loss, dB = absorption + reflection part.
  double get transmissionLossDb => absorptionDb + reflectionPartDb;

  /// Reflected power |R|^2.
  double get reflectedPower => r.abs2;

  /// Transmitted power |T|^2 (may underflow to 0 for metal).
  double get transmittedPower => t.abs2;

  /// Reflected power relative to incident, dB (<= 0). -infinity when R = 0.
  double get reflectionDb => 10 * math.log(reflectedPower) / math.ln10;

  /// Standing-wave ripple in front of the wall, dB: 20·log10((1+|R|)/(1-|R|)).
  /// Infinite when |R| reaches 1 (full nulls).
  double get standingWaveRippleDb {
    final double g = r.abs;
    if (g >= 1) return double.infinity;
    return 20 * math.log((1 + g) / (1 - g)) / math.ln10;
  }

  // Wavenumbers along the wall normal, rad/m.
  double get _k0 => 2 * math.pi / props.lambdaAir;
  double get _cosTheta => math.cos(angleDeg * math.pi / 180);

  /// Complex field phasor at distance [x] metres along the wall normal,
  /// measured from the front face (x < 0 in front, 0..d inside, > d behind).
  /// The incident wave has amplitude 1 and phase 0 at the front face.
  ///
  /// In front: e^(-jkx) + R·e^(+jkx). Inside: the forward wave
  /// A·e^(-jk'x) plus the wave reflected off the back face,
  /// -A·R'·e^(-jk'(2d - x)), with A = (1 + R')/(1 - R'^2·e^(-j2q)). Behind:
  /// T·e^(-jk(x - d)). The inside form is continuous with both outside forms
  /// for either polarization (1 + R = A(1 - R'e^(-j2q)) and
  /// A(1 - R')e^(-jq) = T), and every exponent it evaluates decays, so metal
  /// underflows to zero instead of overflowing.
  ///
  /// The drawn quantity is the tangential electric field. Eq. 37b (TM) is
  /// the H-field ratio, which for tangential E carries the opposite sign, so
  /// TM flips the sign of R' and R here. T depends only on R'^2 and is the
  /// same either way; at normal incidence TE and TM then draw identically.
  Complex fieldAt(double x) {
    final double k0z = _k0 * _cosTheta;
    final bool flip = polarization == Polarization.tm;
    final Complex rE = flip ? -r : r;
    final Complex rPrimeE = flip ? -interfaceR : interfaceR;
    if (x < 0) {
      return Complex.polar(1, -k0z * x) + rE * Complex.polar(1, k0z * x);
    }
    final double d = thicknessM;
    if (x > d) {
      return t * Complex.polar(1, -k0z * (x - d));
    }
    if (d == 0) return t;
    // k' along the normal = k0·sqrt(e_rc - sin^2 theta) = q/d.
    final Complex kz = q.scale(1 / d);
    final Complex e2q = (-Complex.j * q.scale(2)).exp();
    final Complex a =
        (Complex.one + rPrimeE) / (Complex.one - rPrimeE * rPrimeE * e2q);
    final Complex fwd = (-Complex.j * kz.scale(x)).exp();
    final Complex back = (-Complex.j * kz.scale(2 * d - x)).exp();
    return a * (fwd - rPrimeE * back);
  }
}

/// ITU-R P.2040-4 slab model.
class WallSlab {
  const WallSlab._();

  /// Interface reflection coefficient R' at incidence [angleDeg] from air
  /// onto a half-space of [eps] (Eqs. 37a TE, 37b TM).
  static Complex interfaceReflection(
    Complex eps,
    double angleDeg,
    Polarization pol,
  ) {
    final double th = angleDeg * math.pi / 180;
    final double cosT = math.cos(th);
    final double sin2 = math.sin(th) * math.sin(th);
    final Complex root = (eps - Complex(sin2)).sqrt();
    switch (pol) {
      case Polarization.te:
        final Complex c = Complex(cosT);
        return (c - root) / (c + root);
      case Polarization.tm:
        final Complex ec = eps.scale(cosT);
        return (ec - root) / (ec + root);
    }
  }

  /// Computes the slab result. [thicknessM] in metres (>= 0), [angleDeg] in
  /// [0, 90).
  static SlabResult compute({
    required WallMaterial material,
    required double fGhz,
    required double thicknessM,
    double angleDeg = 0,
    Polarization polarization = Polarization.te,
  }) {
    return computeFor(
      props: MaterialProperties.of(material, fGhz),
      thicknessM: thicknessM,
      angleDeg: angleDeg,
      polarization: polarization,
    );
  }

  /// As [compute], from explicit material properties. The tests use this for
  /// an idealized lossless slab (sigma = 0) that no Table 3 row describes.
  static SlabResult computeFor({
    required MaterialProperties props,
    required double thicknessM,
    double angleDeg = 0,
    Polarization polarization = Polarization.te,
  }) {
    if (thicknessM < 0 || !thicknessM.isFinite) {
      throw ArgumentError.value(thicknessM, 'thicknessM', 'must be >= 0');
    }
    if (angleDeg < 0 || angleDeg >= 90) {
      throw ArgumentError.value(angleDeg, 'angleDeg', 'must be in [0, 90)');
    }
    final MaterialProperties p = props;
    final Complex eps = p.epsComplex;
    final Complex rPrime = interfaceReflection(eps, angleDeg, polarization);

    // Zero thickness: no wall. The general formula gives the same answer
    // (R = 0, T = 1) but short-circuits here so a near-(-1) metal R' cannot
    // turn 0/0 into noise.
    if (thicknessM == 0) {
      return SlabResult._(
        props: p,
        thicknessM: 0,
        angleDeg: angleDeg,
        polarization: polarization,
        interfaceR: rPrime,
        q: Complex.zero,
        r: Complex.zero,
        t: Complex.one,
        absorptionDb: 0,
        reflectionPartDb: 0,
      );
    }

    final double th = angleDeg * math.pi / 180;
    final double sin2 = math.sin(th) * math.sin(th);
    final Complex root = (eps - Complex(sin2)).sqrt();
    final Complex q = root.scale(2 * math.pi * thicknessM / p.lambdaAir);

    final Complex eJq = (-Complex.j * q).exp(); // e^(-jq)
    final Complex eJ2q = (-Complex.j * q.scale(2)).exp(); // e^(-j2q)
    final Complex r2 = rPrime * rPrime;
    final Complex den = Complex.one - r2 * eJ2q;
    final Complex oneMinusR2 = Complex.one - r2;

    final Complex r = rPrime * (Complex.one - eJ2q) / den;
    final Complex t = oneMinusR2 * eJq / den;

    // |e^(-jq)| = e^(Im q), Im q <= 0 for a lossy medium.
    final double absorptionDb = _kDbPerNeper * (-q.im);
    final double reflectionPartDb =
        -20 * math.log(oneMinusR2.abs / den.abs) / math.ln10;

    return SlabResult._(
      props: p,
      thicknessM: thicknessM,
      angleDeg: angleDeg,
      polarization: polarization,
      interfaceR: rPrime,
      q: q,
      r: r,
      t: t,
      absorptionDb: absorptionDb,
      reflectionPartDb: reflectionPartDb,
    );
  }
}

// ── Measured comparison data (brief §6.4) ──────────────────────────────────

/// Who measured or tabulated a value.
enum MeasurementSource {
  nist6055('NIST 6055'),
  nyu2024('NYU 2024'),
  threeGpp38901('3GPP TR 38.901');

  const MeasurementSource(this.label);
  final String label;
}

/// How a measured number should be read.
enum MeasuredQualifier {
  /// Read off a published plot: "about".
  approx,

  /// Printed as a bound: "under".
  upperBound,

  /// Printed in a table.
  exact,
}

/// One measured loss at one frequency.
class MeasuredPoint {
  const MeasuredPoint(this.fGhz, this.lossDb, this.qualifier);
  final double fGhz;
  final double lossDb;
  final MeasuredQualifier qualifier;
}

/// One measured specimen (or one formula-based material class).
class MeasuredSpecimen {
  const MeasuredSpecimen({
    required this.source,
    required this.material,
    required this.specimen,
    required this.points,
    this.thicknessM,
    this.modelComparable = true,
    this.note,
    this.formulaA,
    this.formulaB,
  });

  final MeasurementSource source;
  final WallMaterial material;

  /// What was measured, in words, e.g. "Concrete, 102 mm, plain mix".
  final String specimen;

  /// Specimen thickness, m. Null when the source gives none (3GPP).
  final double? thicknessM;

  /// Whether a single homogeneous P.2040 slab of this material and
  /// thickness is a like-for-like model of the specimen.
  final bool modelComparable;

  /// Brief §6.4 context for the row, stated as the brief states it.
  final String? note;

  final List<MeasuredPoint> points;

  /// 3GPP TR 38.901 penetration-loss form L = A + B·f (f in GHz).
  final double? formulaA;
  final double? formulaB;
}

/// The frequencies of the "All three bands" comparison (spec).
const List<double> kComparisonGhz = <double>[2.4, 5.5, 6.5];

List<MeasuredPoint> _threeGpp(double a, double b) => <MeasuredPoint>[
  for (final double f in kComparisonGhz)
    MeasuredPoint(f, a + b * f, MeasuredQualifier.exact),
];

/// Every brief §6.4 row that is a measurement or a 3GPP class, keyed to the
/// nearest P.2040 material. Never averaged: each row stands on its own.
///
/// NIST's "2.4 GHz" column is its 2.0 GHz value (NIST has no data between
/// 2.0 and 3.0 GHz), so those points are stored at 2.0 GHz. NYU's are at
/// 6.75 GHz. 3GPP rows are the stated formula evaluated at 2.4/5.5/6.5 GHz.
final List<MeasuredSpecimen> kMeasuredSpecimens = <MeasuredSpecimen>[
  const MeasuredSpecimen(
    source: MeasurementSource.nist6055,
    material: WallMaterial.concrete,
    specimen: 'Concrete, 102 mm (plain mix 1, lab-cast)',
    thicknessM: 0.102,
    note:
        'Fresh lab-cast specimens likely held more moisture than cured '
        'concrete (the research brief marks this as inferred).',
    points: <MeasuredPoint>[
      MeasuredPoint(2.0, 15, MeasuredQualifier.approx),
      MeasuredPoint(5.5, 24, MeasuredQualifier.approx),
      MeasuredPoint(6.5, 25, MeasuredQualifier.approx),
    ],
  ),
  const MeasuredSpecimen(
    source: MeasurementSource.nist6055,
    material: WallMaterial.concrete,
    specimen: 'Concrete, 203 mm',
    thicknessM: 0.203,
    points: <MeasuredPoint>[
      MeasuredPoint(2.0, 29, MeasuredQualifier.approx),
      MeasuredPoint(5.5, 49, MeasuredQualifier.approx),
      MeasuredPoint(6.5, 52, MeasuredQualifier.approx),
    ],
  ),
  MeasuredSpecimen(
    source: MeasurementSource.threeGpp38901,
    material: WallMaterial.concrete,
    specimen: 'Concrete exterior wall, L = 5 + 4f (thickness not stated)',
    formulaA: 5,
    formulaB: 4,
    points: _threeGpp(5, 4),
  ),
  const MeasuredSpecimen(
    source: MeasurementSource.nyu2024,
    material: WallMaterial.concrete,
    specimen: 'Cinder block, 220 mm, painted',
    thicknessM: 0.220,
    modelComparable: false,
    note:
        'Hollow block, not a solid slab, so a single P.2040 concrete slab '
        'is not like-for-like.',
    points: <MeasuredPoint>[MeasuredPoint(6.75, 13.4, MeasuredQualifier.exact)],
  ),
  const MeasuredSpecimen(
    source: MeasurementSource.nist6055,
    material: WallMaterial.brick,
    specimen: 'Brick, 89 mm',
    thicknessM: 0.089,
    note:
        'NIST shows a suspicious step of about 10 dB between its 2.0 and '
        '3.0 GHz bands. Flagged, not resolved.',
    points: <MeasuredPoint>[
      MeasuredPoint(2.0, 5.4, MeasuredQualifier.approx),
      MeasuredPoint(5.5, 15, MeasuredQualifier.approx),
      MeasuredPoint(6.5, 15.5, MeasuredQualifier.approx),
    ],
  ),
  const MeasuredSpecimen(
    source: MeasurementSource.nist6055,
    material: WallMaterial.plasterboard,
    specimen: 'Drywall, 13 mm',
    thicknessM: 0.013,
    points: <MeasuredPoint>[
      MeasuredPoint(2.0, 0.6, MeasuredQualifier.approx),
      MeasuredPoint(5.5, 0.5, MeasuredQualifier.upperBound),
      MeasuredPoint(6.5, 0.5, MeasuredQualifier.upperBound),
    ],
  ),
  const MeasuredSpecimen(
    source: MeasurementSource.nyu2024,
    material: WallMaterial.plasterboard,
    specimen: 'Drywall panel, 30 mm',
    thicknessM: 0.030,
    points: <MeasuredPoint>[MeasuredPoint(6.75, 0.6, MeasuredQualifier.exact)],
  ),
  const MeasuredSpecimen(
    source: MeasurementSource.nyu2024,
    material: WallMaterial.plasterboard,
    specimen: 'Plasterboard wall on metal studs, 137 mm',
    thicknessM: 0.137,
    modelComparable: false,
    note:
        'Two sheets, an air gap and metal studs: a single solid 137 mm '
        'plasterboard slab is not like-for-like.',
    points: <MeasuredPoint>[MeasuredPoint(6.75, 2.1, MeasuredQualifier.exact)],
  ),
  const MeasuredSpecimen(
    source: MeasurementSource.nist6055,
    material: WallMaterial.glass,
    specimen: 'Clear glass, 6 mm',
    thicknessM: 0.006,
    note:
        'The dips and peaks sit where the slab formula puts them; the size '
        'differs by about 2 dB near 5.5 GHz.',
    points: <MeasuredPoint>[
      MeasuredPoint(2.0, 1.45, MeasuredQualifier.approx),
      MeasuredPoint(5.5, 1.0, MeasuredQualifier.approx),
      MeasuredPoint(6.5, 1.1, MeasuredQualifier.approx),
    ],
  ),
  const MeasuredSpecimen(
    source: MeasurementSource.nist6055,
    material: WallMaterial.glass,
    specimen: 'Glass, 13 mm',
    thicknessM: 0.013,
    note:
        'At about 4.6 GHz the glass is half a wavelength thick inside, and '
        'the reflections from its two faces cancel.',
    points: <MeasuredPoint>[MeasuredPoint(4.6, 0, MeasuredQualifier.approx)],
  ),
  const MeasuredSpecimen(
    source: MeasurementSource.nyu2024,
    material: WallMaterial.glass,
    specimen: 'Clear glass, 10 mm',
    thicknessM: 0.010,
    points: <MeasuredPoint>[MeasuredPoint(6.75, 3.6, MeasuredQualifier.exact)],
  ),
  MeasuredSpecimen(
    source: MeasurementSource.threeGpp38901,
    material: WallMaterial.glass,
    specimen: 'Standard multi-pane glass, L = 2 + 0.2f',
    formulaA: 2,
    formulaB: 0.2,
    points: _threeGpp(2, 0.2),
  ),
  MeasuredSpecimen(
    source: MeasurementSource.threeGpp38901,
    material: WallMaterial.glass,
    specimen: 'Low-E (IRR) glass, L = 23 + 0.3f',
    modelComparable: false,
    formulaA: 23,
    formulaB: 0.3,
    note: 'Coated glass. P.2040 has no coated-glass class.',
    points: _threeGpp(23, 0.3),
  ),
  const MeasuredSpecimen(
    source: MeasurementSource.nyu2024,
    material: WallMaterial.glass,
    specimen: 'Low-E double-pane window, 20 mm',
    thicknessM: 0.020,
    modelComparable: false,
    note:
        'Coated glass. P.2040 has no coated-glass class, and NYU reports '
        'that 3GPP under-predicts it.',
    points: <MeasuredPoint>[MeasuredPoint(6.75, 29.7, MeasuredQualifier.exact)],
  ),
  const MeasuredSpecimen(
    source: MeasurementSource.nyu2024,
    material: WallMaterial.glass,
    specimen: 'Tinted curtain wall, 30 mm',
    thicknessM: 0.030,
    modelComparable: false,
    note: 'Coated glass. P.2040 has no coated-glass class.',
    points: <MeasuredPoint>[MeasuredPoint(6.75, 33.7, MeasuredQualifier.exact)],
  ),
  const MeasuredSpecimen(
    source: MeasurementSource.nyu2024,
    material: WallMaterial.wood,
    specimen: 'Wooden fire door, solid core, 45 mm',
    thicknessM: 0.045,
    points: <MeasuredPoint>[MeasuredPoint(6.75, 5.8, MeasuredQualifier.exact)],
  ),
  MeasuredSpecimen(
    source: MeasurementSource.threeGpp38901,
    material: WallMaterial.wood,
    specimen: 'Wood, L = 4.85 + 0.12f (thickness not stated)',
    formulaA: 4.85,
    formulaB: 0.12,
    points: _threeGpp(4.85, 0.12),
  ),
  const MeasuredSpecimen(
    source: MeasurementSource.nyu2024,
    material: WallMaterial.plywood,
    specimen: 'Birch plywood, 20 mm',
    thicknessM: 0.020,
    points: <MeasuredPoint>[MeasuredPoint(6.75, 2.4, MeasuredQualifier.exact)],
  ),
  const MeasuredSpecimen(
    source: MeasurementSource.nyu2024,
    material: WallMaterial.metal,
    specimen: 'Steel door, 47 mm',
    thicknessM: 0.047,
    modelComparable: false,
    note:
        'A real door leaks around its frame and gaps. The P.2040 metal slab '
        'models a seamless sheet, which reflects effectively everything.',
    points: <MeasuredPoint>[MeasuredPoint(6.75, 43.2, MeasuredQualifier.exact)],
  ),
];

/// Measured specimens for [m], in source order.
List<MeasuredSpecimen> measuredFor(WallMaterial m) => <MeasuredSpecimen>[
  for (final MeasuredSpecimen s in kMeasuredSpecimens)
    if (s.material == m) s,
];
