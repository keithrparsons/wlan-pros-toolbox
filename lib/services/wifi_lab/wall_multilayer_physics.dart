// Multilayer walls for "Wi-Fi Through a Wall" (wifi-through-a-wall): a real
// wall as a stack of layers (plasterboard, air, plasterboard), and the
// named real-wall presets the tool offers.
//
// Keith, 2026-09-27: "what people want to see for the wall thickness
// simulator are REAL WALLS - like a drywall with two plasterboards and an
// air gap. Or a concrete wall around an elevator shaft, or a solid wood
// door".
//
// CLEAN-ROOM BUILD (2026-09-27) from ITU-R P.2040-4 (09/2025) §2.2.2.1,
// "General method for a multi-layer slab", Eqs. 39-42 (printed p.15), read
// from the Recommendation itself. Material constants are P.2040 Table 3
// (Eqs. 57-59), shared with wall_slab_physics.dart.
//
// The slab sits in air, which P.2040 numbers layer 0 and layer N + 1
// (permittivity 1, width 0). For the interface between layer n and n + 1:
//
//   u_n     = sqrt(e_n - sin^2 theta0)        (sqrt(e_n)·cos theta_n)
//   gamma_n = k0·u_n                          (Eq. 41a)
//   r_TE(n) = (u_n - u_n+1) / (u_n + u_n+1)                     (Eq. 40a)
//   r_TM(n) = (e_n+1·u_n - e_n·u_n+1) / (e_n+1·u_n + e_n·u_n+1) (Eq. 40b)
//   R(N+1)  = 0
//   R(n)    = (r(n) + R(n+1)·E(n+1)) / (1 + r(n)·R(n+1)·E(n+1)),
//             E(n+1) = exp(-2j·gamma_n+1·d_n+1), for n = N down to 0 (39)
//   R       = R(0)                                              (Eq. 42a)
//   T       = product over n = 0..N of
//             exp(-j·gamma_n·d_n)·(1 + r(n)) / (1 + r(n)·R(n+1)·E(n+1)) (42b)
//
// Eq. 40b is multiplied through by sqrt(e_n)·sqrt(e_n+1) so no square root
// of a complex permittivity is taken on its own. Eq. 41a as printed shows
// e_rcn SQUARED under the root; with Eqs. 41b and 41c, k0·sqrt(e)·cos theta_n
// is k0·sqrt(e - sin^2 theta0), so the square is a typo and is not used.
//
// With N = 1 this is exactly the single-slab Eqs. 43a-44 (P.2040 §2.2.2.2);
// the unit tests hold the two within 0.1 dB, and test a stud wall against
// P.2040 Attachment 1's ABCD-matrix form, computed independently in the test.
//
// THE LOSS SPLIT. Eq. 42b is a product, so its log is a sum:
//   absorption = sum over layers of 8.686·(-Im gamma_n)·d_n, the decay
//                along the path inside every layer (air layers add 0);
//   reflection = sum over interfaces of
//                -20·log10|1 + r(n)| + 20·log10|1 + r(n)·R(n+1)·E(n+1)|,
//                what the faces send back, including the resonance between
//                them.
// For one layer these are the single-slab split exactly. Summing logs keeps
// a metal layer finite where |T|^2 underflows.
//
// No Flutter imports: the screen drives this, the tests pin it.

import 'dart:math' as math;

import 'complex.dart';
import 'wall_slab_physics.dart';

/// 20·log10(e): nepers of field decay to dB.
const double _kDbPerNeper = 8.685889638065037;

/// One layer of a wall: a P.2040 Table 3 material, or air (the "Vacuum
/// (~ air)" row: permittivity 1, conductivity 0).
class WallLayer {
  const WallLayer(WallMaterial this.material, this.thicknessMm);

  /// An air gap, such as the cavity between two plasterboard sheets.
  const WallLayer.air(this.thicknessMm) : material = null;

  /// Null for air.
  final WallMaterial? material;

  /// Thickness, mm.
  final double thicknessMm;

  double get thicknessM => thicknessMm / 1000;

  bool get isAir => material == null;

  String get label => material?.label ?? 'Air';

  /// Complex relative permittivity at [fGhz] (P.2040 Eq. 59).
  Complex epsAt(double fGhz) {
    final WallMaterial? m = material;
    if (m == null) return Complex.one;
    return MaterialProperties.of(m, fGhz).epsComplex;
  }

  @override
  bool operator ==(Object other) =>
      other is WallLayer &&
      other.material == material &&
      other.thicknessMm == thicknessMm;

  @override
  int get hashCode => Object.hash(material, thicknessMm);
}

/// The P.2040 multilayer result for one wall, frequency, angle and
/// polarization.
class MultilayerResult implements WallTransmission {
  MultilayerResult._({
    required this.layers,
    required this.fGhz,
    required this.angleDeg,
    required this.polarization,
    required this.r,
    required this.t,
    required this.absorptionDb,
    required this.reflectionPartDb,
    required this.layerAbsorptionDb,
  });

  /// Front to back.
  final List<WallLayer> layers;

  @override
  final double fGhz;
  @override
  final double angleDeg;
  @override
  final Polarization polarization;

  /// R = R(0), Eq. 42a.
  @override
  final Complex r;

  /// T, Eq. 42b.
  @override
  final Complex t;

  @override
  final double absorptionDb;
  @override
  final double reflectionPartDb;

  /// Absorption in each layer, dB, front to back (0 for air).
  final List<double> layerAbsorptionDb;

  @override
  double get lambdaAir => kSpeedOfLight / (fGhz * 1e9);

  @override
  double get thicknessM =>
      layers.fold(0.0, (double s, WallLayer l) => s + l.thicknessM);

  @override
  double get transmissionLossDb => absorptionDb + reflectionPartDb;

  @override
  double get reflectedPower => r.abs2;

  @override
  double get reflectionDb => 10 * math.log(reflectedPower) / math.ln10;

  @override
  double get standingWaveRippleDb {
    final double g = r.abs;
    if (g >= 1) return double.infinity;
    return 20 * math.log((1 + g) / (1 - g)) / math.ln10;
  }

  /// Outside the wall only (see [WallTransmission.fieldAt]); throws inside.
  /// As in SlabResult.fieldAt, Eq. 40b's TM coefficient is the ratio whose
  /// sign is opposite to the tangential E field's, so TM flips R here.
  @override
  Complex fieldAt(double x) {
    final double k0z =
        2 * math.pi / lambdaAir * math.cos(angleDeg * math.pi / 180);
    final double d = thicknessM;
    if (x <= 0) {
      final Complex rE = polarization == Polarization.tm ? -r : r;
      return Complex.polar(1, -k0z * x) + rE * Complex.polar(1, k0z * x);
    }
    if (x >= d) return t * Complex.polar(1, -k0z * (x - d));
    throw ArgumentError.value(
      x,
      'x',
      'a layered wall answers outside the wall only (0 < x < $d)',
    );
  }
}

/// ITU-R P.2040 §2.2.2.1 multilayer method.
class MultilayerWall {
  const MultilayerWall._();

  /// Computes [layers] (front to back, at least one, each thicker than 0)
  /// at [fGhz], [angleDeg] in [0, 90).
  static MultilayerResult compute({
    required List<WallLayer> layers,
    required double fGhz,
    double angleDeg = 0,
    Polarization polarization = Polarization.te,
  }) {
    if (layers.isEmpty) {
      throw ArgumentError.value(layers, 'layers', 'needs at least one layer');
    }
    for (final WallLayer l in layers) {
      if (!(l.thicknessMm > 0) || !l.thicknessMm.isFinite) {
        throw ArgumentError.value(l.thicknessMm, 'thicknessMm', 'must be > 0');
      }
    }
    if (!(fGhz > 0)) throw ArgumentError.value(fGhz, 'fGhz', 'must be > 0');
    if (angleDeg < 0 || angleDeg >= 90) {
      throw ArgumentError.value(angleDeg, 'angleDeg', 'must be in [0, 90)');
    }

    final int n = layers.length; // N
    final double lambda = kSpeedOfLight / (fGhz * 1e9);
    final double k0 = 2 * math.pi / lambda;
    final double th = angleDeg * math.pi / 180;
    final double sin2 = math.sin(th) * math.sin(th);
    final double cos0 = math.cos(th);

    // Index 0 and N + 1 are the air on either side, width 0.
    final List<Complex> eps = <Complex>[
      Complex.one,
      for (final WallLayer l in layers) l.epsAt(fGhz),
      Complex.one,
    ];
    final List<double> d = <double>[
      0,
      for (final WallLayer l in layers) l.thicknessM,
      0,
    ];
    // u = sqrt(e - sin^2 theta0); in air exactly cos theta0.
    final List<Complex> u = <Complex>[
      for (int i = 0; i <= n + 1; i++)
        i == 0 || i == n + 1 ? Complex(cos0) : (eps[i] - Complex(sin2)).sqrt(),
    ];
    // gamma·d, the complex phase through each layer.
    final List<Complex> gd = <Complex>[
      for (int i = 0; i <= n + 1; i++) u[i].scale(k0 * d[i]),
    ];

    Complex fresnel(int i) {
      switch (polarization) {
        case Polarization.te:
          return (u[i] - u[i + 1]) / (u[i] + u[i + 1]);
        case Polarization.tm:
          final Complex a = eps[i + 1] * u[i];
          final Complex b = eps[i] * u[i + 1];
          return (a - b) / (a + b);
      }
    }

    final List<Complex> rr = <Complex>[for (int i = 0; i <= n; i++) fresnel(i)];

    // Eq. 39, from the back: big[i] = R(i), big[n + 1] = 0.
    final List<Complex> big = List<Complex>.filled(n + 2, Complex.zero);
    final List<Complex> den = List<Complex>.filled(n + 1, Complex.one);
    for (int i = n; i >= 0; i--) {
      final Complex e = (-Complex.j * gd[i + 1].scale(2)).exp();
      final Complex tail = big[i + 1] * e;
      den[i] = Complex.one + rr[i] * tail;
      big[i] = (rr[i] + tail) / den[i];
    }

    // Eq. 42b, as a product and as a sum of logs.
    Complex t = Complex.one;
    double absorption = 0;
    double reflection = 0;
    final List<double> perLayer = <double>[];
    for (int i = 0; i <= n; i++) {
      final Complex onePlusR = Complex.one + rr[i];
      t = t * (-Complex.j * gd[i]).exp() * onePlusR / den[i];
      // |exp(-j·g)| = exp(Im g); Im g <= 0 in a lossy layer.
      final double a = _kDbPerNeper * (-gd[i].im);
      absorption += a;
      if (i >= 1) perLayer.add(a);
      reflection +=
          -20 * math.log(onePlusR.abs) / math.ln10 +
          20 * math.log(den[i].abs) / math.ln10;
    }

    return MultilayerResult._(
      layers: List<WallLayer>.unmodifiable(layers),
      fGhz: fGhz,
      angleDeg: angleDeg,
      polarization: polarization,
      r: big[0],
      t: t,
      absorptionDb: absorption,
      reflectionPartDb: reflection,
      layerAbsorptionDb: List<double>.unmodifiable(perLayer),
    );
  }
}

/// The walls the tool offers. Each is a stack of P.2040 layers with its
/// thicknesses stated; [custom] is one Table 3 material at any thickness,
/// set with the material and thickness controls.
///
/// THICKNESSES are common construction sizes, not measurements of a
/// particular wall: 1/2 in (12.7 mm) plasterboard, a 2x4 stud's 3 1/2 in
/// (89 mm) depth, an 8 in (203 mm) concrete wall, a 1 3/4 in (44.5 mm)
/// door, 1/8 in (3.2 mm) glass with a 1/2 in (12.7 mm) gap in a double-pane
/// unit, a 1/4 in (6 mm) single pane, and a 3 5/8 in (92 mm) modular brick.
/// The losses are whatever P.2040 gives for them; nothing is tuned.
enum WallPreset {
  studWall(
    'Interior stud wall',
    <WallLayer>[
      WallLayer(WallMaterial.plasterboard, 12.7),
      WallLayer.air(89),
      WallLayer(WallMaterial.plasterboard, 12.7),
    ],
    WallMaterial.plasterboard,
    'Two plasterboard sheets with the air gap a stud makes between them. '
        'The studs, insulation and wiring are not modeled.',
  ),
  elevatorShaft(
    'Concrete elevator-shaft wall',
    <WallLayer>[WallLayer(WallMaterial.concrete, 203)],
    WallMaterial.concrete,
    'Solid concrete. The steel reinforcing bars inside a real shaft wall '
        'are not modeled.',
  ),
  woodDoor(
    'Solid wood door',
    <WallLayer>[WallLayer(WallMaterial.wood, 44.5)],
    WallMaterial.wood,
    'Solid wood. Gaps around the frame and any hardware are not modeled.',
  ),
  doublePaneWindow(
    'Double-pane window',
    <WallLayer>[
      WallLayer(WallMaterial.glass, 3.2),
      WallLayer.air(12.7),
      WallLayer(WallMaterial.glass, 3.2),
    ],
    WallMaterial.glass,
    'Two panes of clear glass with a gap between them. A low emissivity '
        '(low-E) coating, which can add far more loss, is not modeled: '
        'P.2040 has no class for it.',
  ),
  singlePaneWindow(
    'Single-pane window',
    <WallLayer>[WallLayer(WallMaterial.glass, 6)],
    WallMaterial.glass,
    'One pane of clear, uncoated glass.',
  ),
  brickWall(
    'Brick wall, one brick thick',
    <WallLayer>[WallLayer(WallMaterial.brick, 92)],
    WallMaterial.brick,
    'Solid brick. Mortar joints and hollow cores are not modeled.',
  ),
  custom(
    'One material, any thickness',
    <WallLayer>[],
    null,
    'One solid layer of the material you pick, as thick as you set it.',
  );

  const WallPreset(this.label, this.layers, this.measuredMaterial, this.note);

  final String label;

  /// Front to back. Empty for [custom], whose one layer the user sets.
  final List<WallLayer> layers;

  /// The Table 3 material whose published measurements sit beside this wall.
  /// Null for [custom], which uses the material picked.
  final WallMaterial? measuredMaterial;

  /// What the preset is, and what it leaves out.
  final String note;

  bool get isCustom => this == WallPreset.custom;

  /// Total thickness, mm (0 for [custom]).
  double get totalMm =>
      layers.fold(0.0, (double s, WallLayer l) => s + l.thicknessMm);
}
