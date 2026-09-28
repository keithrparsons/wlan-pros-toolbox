// Model for the Wi-Fi Classroom tool "How to Measure Wall Attenuation"
// (measure-wall).
//
// Keith's method (2026-09-27): lock a measuring device to one channel, place
// something that makes RF (a hotspot or a small AP) 4 m or more from the wall
// under test, average a series of readings close to the near side of the wall,
// then average a series close to the far side. The difference of the two
// averages is the wall attenuation.
//
// WHAT THE TOOL TEACHES: the difference of the two averages is NOT only the
// wall. The far reading is also farther from the source, so it carries more
// free-space path loss (FSPL). With the source at D from the near face of a
// wall t thick, a near reading a_n in front of the wall and a far reading
// a_f behind it:
//
//   near distance  = D - a_n
//   far distance   = D + t + a_f
//   measured       = wall loss + 20 log10(far / near)  (+ the fading residual)
//
// The middle term is the geometry error. It is independent of frequency (the
// frequency term of FSPL is the same at both spots and cancels), and it
// shrinks when the source is far from the wall and the readings hug it. With
// a wall of no thickness and equal gaps it is the brief's
// 20 log10((D + a) / (D - a)).
//
// REUSE, NO NEW TABLES:
//   - free-space loss: FsplMath.fsplDb (the FSPL Simulator's exact Friis form)
//   - the wall: WallSlab.compute from Wi-Fi Through a Wall (ITU-R P.2040-4
//     Table 3 materials), head on (0 degrees), TE
//
// ILLUSTRATIVE: the fading spread. Each reading is the model level plus a
// seeded Gaussian draw with a standard deviation the user sets (default 2
// dB). No measured fading figure stands behind it. The same seed always
// gives the same series; "Take new readings" moves to the next seed.
//
// The free-space formula has no meaning at the source itself, so the near
// reading is kept at least [MwConfig.minFromSourceM] (0.1 m) from it.
//
// Pure Dart, no Flutter imports. ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import '../../data/channel_frequency_data.dart';
import 'fspl_math.dart';
import 'wall_slab_physics.dart';

/// Stable catalog tool id: backs the route, the help entry and the tests.
const String kMeasureWallToolId = 'measure-wall';

/// Which side of the wall the laptop is on.
enum MwSide {
  /// The source's side.
  near,

  /// Behind the wall.
  far,
}

/// The pure geometry-error formulas, pinned by the tests.
abstract final class MwMath {
  static double log10(double x) => math.log(x) / math.ln10;

  /// The free-space part of a two-spot wall measurement, dB: the extra FSPL
  /// the far reading carries because it is farther from the source,
  /// 20 log10(far / near). Distances from the source, metres.
  static double errorTermDb(double nearDistM, double farDistM) =>
      20 * log10(farDistM / nearDistM);

  /// The same term for a source [sourceToWallM] from the near face of a wall
  /// [thicknessM] thick, with the readings [nearGapM] in front of the wall and
  /// [farGapM] behind it.
  static double geometryErrorDb({
    required double sourceToWallM,
    required double nearGapM,
    required double farGapM,
    double thicknessM = 0,
  }) => errorTermDb(
    sourceToWallM - nearGapM,
    sourceToWallM + thicknessM + farGapM,
  );

  /// The symmetric form: readings [gapM] either side of a wall of no
  /// thickness, source [sourceToWallM] from it. 20 log10((D + a) / (D - a)).
  static double symmetricErrorDb(double sourceToWallM, double gapM) =>
      errorTermDb(sourceToWallM - gapM, sourceToWallM + gapM);

  /// Slope of the free-space curve at [distanceM] from the source, dB per
  /// metre: d/dd of 20 log10(d) = 20 / (ln 10 x d). 8.7 dB/m at 1 m, 2.2 at
  /// 4 m. Why a reading near the source moves so much for a small step.
  static double fsplSlopeDbPerM(double distanceM) =>
      20 / (math.ln10 * distanceM);
}

/// One series of readings at one spot.
class MwSeries {
  const MwSeries({
    required this.side,
    required this.gapM,
    required this.distanceM,
    required this.modelDbm,
    required this.samplesDbm,
  });

  final MwSide side;

  /// Distance from the wall face on this side, metres.
  final double gapM;

  /// Distance from the source, metres.
  final double distanceM;

  /// The level the model gives here, before fading, dBm.
  final double modelDbm;

  /// The readings, dBm, in the order taken.
  final List<double> samplesDbm;

  double get averageDbm {
    double s = 0;
    for (final double v in samplesDbm) {
      s += v;
    }
    return s / samplesDbm.length;
  }

  double get minDbm => samplesDbm.reduce(math.min);
  double get maxDbm => samplesDbm.reduce(math.max);

  /// What the fading left in the average: average - model, dB.
  double get residualDb => averageDbm - modelDbm;

  /// Whether the average sits below the noise floor, where the laptop
  /// reports nothing.
  bool get belowFloor => averageDbm < MwConfig.noiseFloorDbm;
}

/// Everything the user sets, and everything derived from it. Immutable.
class MwConfig {
  MwConfig({
    this.band = WifiBand.band5,
    this.material = WallMaterial.concrete,
    this.thicknessM = 0.102,
    double sourceToWallM = defaultSourceToWallM,
    double nearGapM = defaultGapM,
    double farGapM = defaultGapM,
    this.side = MwSide.near,
    int samplesPerSide = defaultSamples,
    double spreadDb = defaultSpreadDb,
    this.nearSeed = 1,
    this.farSeed = 2,
  }) : sourceToWallM = sourceToWallM.clamp(minSourceM, maxSourceM),
       samplesPerSide = samplesPerSide.clamp(minSamples, maxSamples),
       spreadDb = spreadDb.clamp(0.0, maxSpreadDb),
       farGapM = farGapM.clamp(minGapM, maxFarGapM),
       nearGapM = nearGapM.clamp(
         minGapM,
         maxNearGap(sourceToWallM.clamp(minSourceM, maxSourceM)),
       ) {
    if (!(thicknessM >= 0) || !thicknessM.isFinite) {
      throw ArgumentError.value(thicknessM, 'thicknessM', 'must be >= 0');
    }
  }

  // ── Bounds and defaults ───────────────────────────────────────────────

  /// Source to wall (brief: default 4 m, 0.5 to 15 m).
  static const double defaultSourceToWallM = 4;
  static const double minSourceM = 0.5;
  static const double maxSourceM = 15;

  /// A reading can sit this close to a wall face.
  static const double minGapM = 0.05;

  /// The far reading can move this far behind the wall.
  static const double maxFarGapM = 5;

  /// The opening gaps: 1 m each side, the loose measurement, so the error is
  /// on screen from the start and the student can close it.
  static const double defaultGapM = 1;

  /// The free-space formula has no meaning at the source, so the near
  /// reading stays at least this far from it.
  static const double minFromSourceM = 0.1;

  static double maxNearGap(double sourceToWallM) =>
      math.max(minGapM, sourceToWallM - minFromSourceM);

  /// Readings per side.
  static const int defaultSamples = 10;
  static const int minSamples = 1;
  static const int maxSamples = 30;

  /// Fading spread, standard deviation in dB (illustrative).
  static const double defaultSpreadDb = 2;
  static const double maxSpreadDb = 6;

  /// The source radiates 20 dBm (the Wi-Fi Through a Wall default Tx power)
  /// with 0 dBi antennas at both ends.
  static const double txPowerDbm = 20;

  /// The floor the laptop cannot read below, dBm: thermal noise in 20 MHz,
  /// -174 + 10 log10(20,000,000) = -101 dBm, plus a 6 dB noise figure. The
  /// Wi-Fi Through a Wall floor.
  static const double noiseFloorDbm = -95;

  /// The locked channel per band: the Wi-Fi Through a Wall defaults.
  static int lockedChannel(WifiBand b) => switch (b) {
    WifiBand.band24 => 6,
    WifiBand.band5 => 100,
    WifiBand.band6 => 117,
  };

  // ── State ─────────────────────────────────────────────────────────────

  final WifiBand band;
  final WallMaterial material;

  /// Wall thickness, metres.
  final double thicknessM;

  /// D: source to the near face of the wall, metres.
  final double sourceToWallM;

  /// a_n: near reading to the near face, metres.
  final double nearGapM;

  /// a_f: far face to the far reading, metres.
  final double farGapM;

  /// Where the laptop is now.
  final MwSide side;

  final int samplesPerSide;
  final double spreadDb;
  final int nearSeed;
  final int farSeed;

  // ── Derived ───────────────────────────────────────────────────────────

  int get channel => lockedChannel(band);
  int get freqMHz => centerFrequencyMHzForBand(band, channel)!;
  double get fGhz => freqMHz / 1000;

  /// The wall, head on, TE, from Wi-Fi Through a Wall's P.2040 model.
  late final SlabResult wall = WallSlab.compute(
    material: material,
    fGhz: fGhz,
    thicknessM: thicknessM,
  );

  /// The true wall loss, dB.
  double get trueWallDb => wall.transmissionLossDb;

  double get nearDistM => sourceToWallM - nearGapM;
  double get farDistM => sourceToWallM + thicknessM + farGapM;

  /// The laptop's distance from the source now.
  double get laptopDistM => side == MwSide.near ? nearDistM : farDistM;
  double get laptopGapM => side == MwSide.near ? nearGapM : farGapM;

  /// The free-space part of the measurement, dB (FsplMath, exact).
  double get geometryErrorDb =>
      FsplMath.fsplDb(farDistM, freqMHz.toDouble()) -
      FsplMath.fsplDb(nearDistM, freqMHz.toDouble());

  /// Model level at [distanceM] from the source, dBm, before fading. Inside
  /// the wall there is no reading; this returns the far-face level there.
  double levelAtDbm(double distanceM) {
    final double d = math.max(minFromSourceM, distanceM);
    final double fs = txPowerDbm - FsplMath.fsplDb(d, freqMHz.toDouble());
    return d <= sourceToWallM ? fs : fs - trueWallDb;
  }

  late final MwSeries nearSeries = _series(MwSide.near);
  late final MwSeries farSeries = _series(MwSide.far);

  MwSeries seriesFor(MwSide s) => s == MwSide.near ? nearSeries : farSeries;

  MwSeries _series(MwSide s) {
    final bool n = s == MwSide.near;
    final double dist = n ? nearDistM : farDistM;
    final double model = levelAtDbm(dist);
    final List<double> z = gaussians(n ? nearSeed : farSeed, samplesPerSide);
    return MwSeries(
      side: s,
      gapM: n ? nearGapM : farGapM,
      distanceM: dist,
      modelDbm: model,
      samplesDbm: <double>[for (final double v in z) model + spreadDb * v],
    );
  }

  /// Whether the far average is under the noise floor: no measurement.
  bool get farBelowFloor => farSeries.belowFloor;

  /// What the student measures: near average - far average, dB. Null when
  /// the far side is below the noise floor.
  double? get measuredDb =>
      farBelowFloor ? null : nearSeries.averageDbm - farSeries.averageDbm;

  /// What the averaging left over, dB: measured - true wall - geometry.
  double get fadingResidualDb => nearSeries.residualDb - farSeries.residualDb;

  /// Measured - true, dB: geometry plus fading.
  double? get totalErrorDb {
    final double? m = measuredDb;
    return m == null ? null : m - trueWallDb;
  }

  // ── Seeded fading ─────────────────────────────────────────────────────

  /// [n] standard normal draws from [seed] (Box-Muller over math.Random).
  static List<double> gaussians(int seed, int n) {
    final math.Random rng = math.Random(seed);
    final List<double> out = <double>[];
    while (out.length < n) {
      final double u1 = 1 - rng.nextDouble(); // (0, 1]
      final double u2 = rng.nextDouble();
      final double r = math.sqrt(-2 * math.log(u1));
      out.add(r * math.cos(2 * math.pi * u2));
      if (out.length < n) out.add(r * math.sin(2 * math.pi * u2));
    }
    return out;
  }

  // ── Changes ───────────────────────────────────────────────────────────

  MwConfig copyWith({
    WifiBand? band,
    WallMaterial? material,
    double? thicknessM,
    double? sourceToWallM,
    double? nearGapM,
    double? farGapM,
    MwSide? side,
    int? samplesPerSide,
    double? spreadDb,
    int? nearSeed,
    int? farSeed,
  }) => MwConfig(
    band: band ?? this.band,
    material: material ?? this.material,
    thicknessM: thicknessM ?? this.thicknessM,
    sourceToWallM: sourceToWallM ?? this.sourceToWallM,
    nearGapM: nearGapM ?? this.nearGapM,
    farGapM: farGapM ?? this.farGapM,
    side: side ?? this.side,
    samplesPerSide: samplesPerSide ?? this.samplesPerSide,
    spreadDb: spreadDb ?? this.spreadDb,
    nearSeed: nearSeed ?? this.nearSeed,
    farSeed: farSeed ?? this.farSeed,
  );

  /// Places the laptop [distanceM] from the source, on whichever side that
  /// is. A spot inside the wall goes to the nearer face.
  MwConfig withLaptopAt(double distanceM) {
    final double wallFar = sourceToWallM + thicknessM;
    final double mid = sourceToWallM + thicknessM / 2;
    if (distanceM < mid) {
      return copyWith(
        side: MwSide.near,
        nearGapM: sourceToWallM - math.min(distanceM, sourceToWallM),
      );
    }
    return copyWith(
      side: MwSide.far,
      farGapM: math.max(distanceM, wallFar) - wallFar,
    );
  }

  /// Moves the laptop [deltaM] away from the source (negative: toward it),
  /// crossing the wall when it passes a face.
  MwConfig moveLaptopBy(double deltaM) {
    if (side == MwSide.near) {
      final double g = nearGapM - deltaM;
      if (g < minGapM - 1e-9) {
        return copyWith(side: MwSide.far, farGapM: minGapM);
      }
      return copyWith(nearGapM: g);
    }
    final double g = farGapM + deltaM;
    if (g < minGapM - 1e-9) {
      return copyWith(side: MwSide.near, nearGapM: minGapM);
    }
    return copyWith(farGapM: g);
  }

  /// A fresh series on the side the laptop is on.
  MwConfig retake() => side == MwSide.near
      ? copyWith(nearSeed: nextSeed(nearSeed, farSeed))
      : copyWith(farSeed: nextSeed(farSeed, nearSeed));

  /// The next unused seed: seeds climb, and the two sides never share one.
  static int nextSeed(int mine, int other) {
    int s = math.max(mine, other) + 1;
    if (s == other) s++;
    return s;
  }
}

/// The predict-then-reveal scene (Larry's correction, 2026-09-27): source
/// 2 m from the wall, readings 1 m either side.
abstract final class MwPredict {
  static const double sourceToWallM = 2;
  static const double gapM = 1;

  /// The free-space error for a wall of no thickness: 20 log10(3 / 1) =
  /// 9.54 dB. The on-screen answer adds the chosen wall's thickness.
  static double get thinWallErrorDb =>
      MwMath.symmetricErrorDb(sourceToWallM, gapM);
}
