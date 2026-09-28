// Heat Map Builder engine (Wi-Fi Classroom, 2026-09-26).
//
// Pure Dart, no Flutter imports. CLEAN-ROOM BUILD from the Wi-Fi Classroom
// wave 4 research brief §4 (interpolation, extrapolation, sample spacing) and
// §5 (averaging), per myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 27-heat-map-builder.md. Built from the spec and the math only. No survey
// vendor publishes its heat-map algorithm, so nothing here claims to be any
// product's method: each is "one documented method".
//
// Same floor, same sample points, same seed: same map.
//
// THE TRUTH (a teaching model):
//   Signal from AP a at a point p:
//     S_a(p) = EIRP - PL(d) - sum of the losses of the walls crossed
//     PL(d)  = FSPL(1 m) + 10 n log10(d),  d = max(|p - AP|, 1 m)
//   PL(d) is FsplMath.logDistanceDb, the path-loss code the FSPL Simulator
//   and Roaming Walk use (spec 15's model). The map shows the strongest AP.
//   Hidden walls are in the truth from the start; only their drawing waits
//   for the reveal.
//
// A SAMPLE reads every AP at its spot, plus optional illustrative noise:
// each reading is the mean of `averaging` Gaussian draws of standard
// deviation sigma (so the noise left after averaging is sigma / sqrt(count)).
// Noise is seeded per sample index, so adding a sample never re-rolls the
// others.
//
// THE ESTIMATE at a cell q (the documented methods; every method sits behind
// the HmInterpolator interface below, so it can be swapped or extended):
//   IDW (Shepard 1968): z = sum(w_i z_i) / sum(w_i), w_i = 1 / d_i^p, over the
//   kHmIdwNeighbors nearest samples that lie within the guess range. A cell
//   on a sample takes that sample's value. In the milliwatt domain each z_i
//   is converted to mW, averaged with the same weights, and converted back.
//   Nearest neighbor: the nearest sample within the guess range (p -> inf).
//   A cell with no sample within the guess range is:
//     off       -> no data (drawn white: no data, not no coverage)
//     flat IDW  -> IDW over the kHmIdwNeighbors nearest samples, any distance
//     path loss -> the strongest of the per-AP log-distance fits
//
// WHY EIGHT NEIGHBORS. Global IDW over every sample drifts back toward the
// average of all samples far from the data, so past the last sample it rises
// toward the AP side instead of staying flat (measured on the spec's 10 m to
// 15 m case: 1.3 to 2.0 dB of rise). Limiting IDW to the nearest few samples
// is the common practice for local interpolation, and with eight the flat-IDW
// change over those 5 m stays under 0.5 dB at 1 to 5 m grid spacing.
//
// THE PATH-LOSS FIT per AP (AP positions are known, as on a survey plan):
// least squares of reading = A - 10 n log10(d) over every sample. With fewer
// than two distinct distances the exponent stays at the floor's n and only A
// is fitted. The fitted n is held to 1.6..6. A fit sees distance, never a
// wall no one measured across.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;
import 'dart:typed_data';

import 'fspl_math.dart';

/// A point on the floor, meters from the top-left corner.
typedef HmPoint = ({double x, double y});

/// Default floor, meters (spec: 40 m x 25 m).
const double kHmFloorWidthM = 40;
const double kHmFloorDepthM = 25;

/// Map cell size, meters.
const double kHmCellM = 0.5;

/// IDW uses at most this many nearest samples (see the header).
const int kHmIdwNeighbors = 8;

/// AP transmit EIRP, dBm. Illustrative.
const double kHmEirpDbm = 17;

/// Channel frequency for FSPL(1 m), MHz (a 5 GHz channel).
const double kHmFreqMHz = 5500;

/// AP count limits (spec: 1 to 4).
const int kHmMinAps = 1;
const int kHmMaxAps = 4;

/// Power (p) limits (spec: 1 to 6).
const double kHmMinPower = 1;
const double kHmMaxPower = 6;

/// Guess range limits, meters (spec: 1 to 20, default 5).
const double kHmMinGuessRangeM = 1;
const double kHmMaxGuessRangeM = 20;
const double kHmDefaultGuessRangeM = 5;

/// Noise and averaging limits (spec: sigma 0 to 8 dB, 1 to 36 samples).
const double kHmMaxSigmaDb = 8;
const int kHmMaxAveraging = 36;

/// Grid and walk spacing limits, meters (spec: 1 to 10).
const double kHmMinSpacingM = 1;
const double kHmMaxSpacingM = 10;

/// The spacing experiment's spacings, meters (spec).
const List<double> kHmExperimentSpacings = <double>[1, 2, 3, 5, 7, 10];

/// The same experiment in feet, for the imperial display: round spacings
/// inside the 1 to 10 m slider range (4 ft is 1.2 m, 30 ft is 9.1 m).
const List<double> kHmExperimentSpacingsFt = <double>[4, 6, 10, 15, 20, 30];

/// The corridor the walk preset follows, meters from the top.
const double kHmCorridorY = 12.5;

/// Fitted path-loss exponent limits.
const double _kFitMinN = 1.6;
const double _kFitMaxN = 6;

double _log10(double x) => math.log(x) / math.ln10;

double _dist(HmPoint a, HmPoint b) {
  final double dx = a.x - b.x;
  final double dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// dBm to milliwatts.
double dbmToMw(double dbm) => math.pow(10, dbm / 10).toDouble();

/// Milliwatts to dBm.
double mwToDbm(double mw) => 10 * _log10(mw);

// ── The floor ───────────────────────────────────────────────────────────────

/// A wall: a straight segment with a loss. A [hidden] wall is part of the
/// truth but is not drawn until revealed.
class HmWall {
  const HmWall({
    required this.a,
    required this.b,
    required this.lossDb,
    this.hidden = false,
  });

  final HmPoint a;
  final HmPoint b;
  final double lossDb;
  final bool hidden;

  /// True when the segment p-q crosses this wall (touching an end does not
  /// count, so a path along the wall's own line is not charged).
  bool crosses(HmPoint p, HmPoint q) {
    double orient(HmPoint o, HmPoint s, HmPoint t) =>
        (s.x - o.x) * (t.y - o.y) - (s.y - o.y) * (t.x - o.x);
    final double d1 = orient(a, b, p);
    final double d2 = orient(a, b, q);
    final double d3 = orient(p, q, a);
    final double d4 = orient(p, q, b);
    return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
  }

  @override
  bool operator ==(Object other) =>
      other is HmWall &&
      other.a == a &&
      other.b == b &&
      other.lossDb == lossDb &&
      other.hidden == hidden;

  @override
  int get hashCode => Object.hash(a, b, lossDb, hidden);
}

/// AP positions for [count] APs on the default floor.
List<HmPoint> defaultHmAps(int count) {
  switch (count.clamp(kHmMinAps, kHmMaxAps)) {
    case 1:
      return const <HmPoint>[(x: 12, y: 12.5)];
    case 2:
      return const <HmPoint>[(x: 10, y: 12.5), (x: 30, y: 12.5)];
    case 3:
      return const <HmPoint>[(x: 7, y: 8), (x: 20, y: 17), (x: 33, y: 8)];
    default:
      return const <HmPoint>[
        (x: 10, y: 6),
        (x: 30, y: 6),
        (x: 10, y: 19),
        (x: 30, y: 19),
      ];
  }
}

/// The default walls: a partition at x = 20 with a corridor gap, a light
/// wall in the lower left, and one hidden 12 dB wall closing off the lower
/// right rooms, which the corridor walk never crosses.
const List<HmWall> kHmDefaultWalls = <HmWall>[
  HmWall(a: (x: 20, y: 0), b: (x: 20, y: 9), lossDb: 8),
  HmWall(a: (x: 20, y: 16), b: (x: 20, y: 25), lossDb: 8),
  HmWall(a: (x: 0, y: 18), b: (x: 9, y: 18), lossDb: 4),
  HmWall(a: (x: 22, y: 19), b: (x: 40, y: 19), lossDb: 12, hidden: true),
];

/// The floor: its size, APs, walls and propagation.
class HmFloor {
  HmFloor({
    this.widthM = kHmFloorWidthM,
    this.depthM = kHmFloorDepthM,
    List<HmPoint>? aps,
    this.walls = kHmDefaultWalls,
    this.pathLossExponent = 3.0,
    this.eirpDbm = kHmEirpDbm,
    this.freqMHz = kHmFreqMHz,
  }) : aps = List<HmPoint>.unmodifiable(aps ?? defaultHmAps(2));

  final double widthM;
  final double depthM;
  final List<HmPoint> aps;
  final List<HmWall> walls;
  final double pathLossExponent;
  final double eirpDbm;
  final double freqMHz;

  bool get hasHiddenWall => walls.any((HmWall w) => w.hidden);

  HmFloor copyWith({
    List<HmPoint>? aps,
    List<HmWall>? walls,
    double? pathLossExponent,
  }) => HmFloor(
    widthM: widthM,
    depthM: depthM,
    aps: aps ?? this.aps,
    walls: walls ?? this.walls,
    pathLossExponent: pathLossExponent ?? this.pathLossExponent,
    eirpDbm: eirpDbm,
    freqMHz: freqMHz,
  );

  /// Path loss at [d] meters (distance held to at least 1 m).
  double pathLossDb(double d) =>
      FsplMath.logDistanceDb(math.max(d, 1), freqMHz, pathLossExponent);

  /// True signal from AP [ap] at [p], dBm.
  double apDbm(int ap, HmPoint p) {
    final HmPoint a = aps[ap];
    double loss = pathLossDb(_dist(a, p));
    for (final HmWall w in walls) {
      if (w.crosses(a, p)) loss += w.lossDb;
    }
    return eirpDbm - loss;
  }

  /// True signal of the strongest AP at [p], dBm.
  double truthDbm(HmPoint p) {
    double best = double.negativeInfinity;
    for (int i = 0; i < aps.length; i++) {
      best = math.max(best, apDbm(i, p));
    }
    return best;
  }

  /// True when [p] lies on the floor.
  bool contains(HmPoint p) =>
      p.x >= 0 && p.x <= widthM && p.y >= 0 && p.y <= depthM;
}

// ── Samples ─────────────────────────────────────────────────────────────────

/// Illustrative measurement noise.
class HmNoise {
  const HmNoise({this.sigmaDb = 0, this.averaging = 1, this.seed = 1});

  /// Standard deviation of one raw reading, dB.
  final double sigmaDb;

  /// Readings averaged per sample point.
  final int averaging;

  final int seed;

  /// Noise left after averaging, dB: sigma / sqrt(count).
  double get effectiveSigmaDb => sigmaDb / math.sqrt(averaging);

  HmNoise copyWith({double? sigmaDb, int? averaging, int? seed}) => HmNoise(
    sigmaDb: sigmaDb ?? this.sigmaDb,
    averaging: averaging ?? this.averaging,
    seed: seed ?? this.seed,
  );

  @override
  bool operator ==(Object other) =>
      other is HmNoise &&
      other.sigmaDb == sigmaDb &&
      other.averaging == averaging &&
      other.seed == seed;

  @override
  int get hashCode => Object.hash(sigmaDb, averaging, seed);
}

/// One measured point.
class HmSample {
  const HmSample({
    required this.p,
    required this.apDbm,
    required this.dbm,
    required this.truthDbm,
  });

  final HmPoint p;

  /// The reading of every AP, dBm (truth plus noise).
  final List<double> apDbm;

  /// The strongest reading, dBm: the value the dot shows and IDW uses.
  final double dbm;

  /// The noise-free strongest signal at this spot, dBm.
  final double truthDbm;
}

double _gaussian(math.Random r) {
  // Box-Muller; 1 - nextDouble() keeps the log argument above zero.
  final double u1 = 1 - r.nextDouble();
  final double u2 = r.nextDouble();
  return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
}

/// Reads the floor at every point of [points].
List<HmSample> takeHmSamples(
  HmFloor floor,
  List<HmPoint> points, [
  HmNoise noise = const HmNoise(),
]) {
  final List<HmSample> out = <HmSample>[];
  for (int i = 0; i < points.length; i++) {
    final HmPoint p = points[i];
    final math.Random r = math.Random(
      (noise.seed * 1000003 + i * 7919) & 0x7fffffff,
    );
    final List<double> readings = <double>[];
    double truth = double.negativeInfinity;
    double best = double.negativeInfinity;
    for (int a = 0; a < floor.aps.length; a++) {
      final double t = floor.apDbm(a, p);
      double n = 0;
      if (noise.sigmaDb > 0) {
        for (int k = 0; k < noise.averaging; k++) {
          n += _gaussian(r);
        }
        n = n / noise.averaging * noise.sigmaDb;
      }
      readings.add(t + n);
      truth = math.max(truth, t);
      best = math.max(best, t + n);
    }
    out.add(
      HmSample(
        p: p,
        apDbm: List<double>.unmodifiable(readings),
        dbm: best,
        truthDbm: truth,
      ),
    );
  }
  return out;
}

// ── Sample layouts ──────────────────────────────────────────────────────────

/// A grid at [spacingM], centered on the floor.
List<HmPoint> hmGridPoints(HmFloor floor, double spacingM) {
  List<double> axis(double length) {
    final int n = math.max(1, (length / spacingM).floor());
    final double start = (length - (n - 1) * spacingM) / 2;
    return <double>[for (int i = 0; i < n; i++) start + i * spacingM];
  }

  return <HmPoint>[
    for (final double y in axis(floor.depthM))
      for (final double x in axis(floor.widthM)) (x: x, y: y),
  ];
}

/// A walk along the corridor with a sample every [spacingM].
List<HmPoint> hmWalkPoints(HmFloor floor, double spacingM) {
  final int n = math.max(1, (floor.widthM / spacingM).floor());
  final double start = (floor.widthM - (n - 1) * spacingM) / 2;
  return <HmPoint>[
    for (int i = 0; i < n; i++) (x: start + i * spacingM, y: kHmCorridorY),
  ];
}

/// Three samples close to the first AP ("Three dots can paint the whole
/// floor green. Should they?").
List<HmPoint> hmThreeDotPoints(HmFloor floor) {
  final HmPoint a = floor.aps.first;
  HmPoint clamp(double x, double y) => (
    x: x.clamp(0.5, floor.widthM - 0.5),
    y: y.clamp(0.5, floor.depthM - 0.5),
  );
  return <HmPoint>[
    clamp(a.x - 3, a.y - 2),
    clamp(a.x + 3, a.y - 1),
    clamp(a.x, a.y + 3),
  ];
}

// ── Estimation settings ─────────────────────────────────────────────────────

enum HmMethod {
  idw('IDW'),
  nearest('Nearest neighbor');

  const HmMethod(this.label);

  final String label;
}

enum HmDomain {
  db('dB'),
  mw('Milliwatts');

  const HmDomain(this.label);

  final String label;
}

enum HmExtrapolation {
  off('Off'),
  flatIdw('Flat IDW'),
  pathLoss('Path-loss fill');

  const HmExtrapolation(this.label);

  final String label;
}

/// How a cell got its value.
enum HmFill {
  /// Interpolated from samples within the guess range.
  interpolated,

  /// Beyond the guess range, filled with flat IDW.
  flat,

  /// Beyond the guess range, filled from the path-loss fits.
  model,

  /// Beyond the guess range with extrapolation off: white.
  none,
}

class HmSettings {
  const HmSettings({
    this.method = HmMethod.idw,
    this.power = 2,
    this.domain = HmDomain.db,
    this.guessRangeM = kHmDefaultGuessRangeM,
    this.extrapolation = HmExtrapolation.off,
  });

  final HmMethod method;
  final double power;
  final HmDomain domain;
  final double guessRangeM;
  final HmExtrapolation extrapolation;

  HmSettings copyWith({
    HmMethod? method,
    double? power,
    HmDomain? domain,
    double? guessRangeM,
    HmExtrapolation? extrapolation,
  }) => HmSettings(
    method: method ?? this.method,
    power: power ?? this.power,
    domain: domain ?? this.domain,
    guessRangeM: guessRangeM ?? this.guessRangeM,
    extrapolation: extrapolation ?? this.extrapolation,
  );

  @override
  bool operator ==(Object other) =>
      other is HmSettings &&
      other.method == method &&
      other.power == power &&
      other.domain == domain &&
      other.guessRangeM == guessRangeM &&
      other.extrapolation == extrapolation;

  @override
  int get hashCode =>
      Object.hash(method, power, domain, guessRangeM, extrapolation);
}

// ── IDW core ────────────────────────────────────────────────────────────────

/// Inverse-distance weights 1 / d^p (unnormalized).
List<double> idwWeights(List<double> distances, double p) => <double>[
  for (final double d in distances) 1 / math.pow(d, p),
];

/// The IDW estimate from samples at [distances] with [valuesDbm], dBm. A zero
/// distance returns that sample's value. In [HmDomain.mw] the values are
/// averaged as milliwatts and converted back.
double idwCombine(
  List<double> distances,
  List<double> valuesDbm,
  double p,
  HmDomain domain,
) {
  assert(distances.length == valuesDbm.length && distances.isNotEmpty);
  for (int i = 0; i < distances.length; i++) {
    if (distances[i] <= 1e-9) return valuesDbm[i];
  }
  double sw = 0;
  double swz = 0;
  for (int i = 0; i < distances.length; i++) {
    final double w = 1 / math.pow(distances[i], p);
    sw += w;
    swz += w * (domain == HmDomain.mw ? dbmToMw(valuesDbm[i]) : valuesDbm[i]);
  }
  final double z = swz / sw;
  return domain == HmDomain.mw ? mwToDbm(z) : z;
}

/// One sample's part in a cell's estimate.
class HmContribution {
  const HmContribution({
    required this.sampleIndex,
    required this.distanceM,
    required this.weightShare,
  });

  final int sampleIndex;
  final double distanceM;

  /// Normalized weight, 0 to 1; the shares of one cell sum to 1.
  final double weightShare;
}

/// A log-distance fit for one AP: reading = A - 10 n log10(d).
class HmPathLossFit {
  const HmPathLossFit({
    required this.ap,
    required this.interceptDbm,
    required this.exponent,
    required this.sampleCount,
  });

  final HmPoint ap;

  /// A: the fitted level at 1 m, dBm.
  final double interceptDbm;

  /// The fitted n.
  final double exponent;
  final int sampleCount;

  double predictDbm(HmPoint p) =>
      interceptDbm - 10 * exponent * _log10(math.max(_dist(ap, p), 1));
}

/// Fits one log-distance model per AP from [samples] (see the header).
List<HmPathLossFit> fitHmPathLoss(HmFloor floor, List<HmSample> samples) {
  final List<HmPathLossFit> fits = <HmPathLossFit>[];
  for (int a = 0; a < floor.aps.length; a++) {
    final HmPoint ap = floor.aps[a];
    final int m = samples.length;
    if (m == 0) continue;
    double sx = 0;
    double sy = 0;
    double sxx = 0;
    double sxy = 0;
    for (final HmSample s in samples) {
      final double x = 10 * _log10(math.max(_dist(ap, s.p), 1));
      final double y = s.apDbm[a];
      sx += x;
      sy += y;
      sxx += x * x;
      sxy += x * y;
    }
    final double varX = sxx / m - (sx / m) * (sx / m);
    double n;
    if (m >= 2 && varX > 1e-6) {
      // Slope of y on x is -n.
      n = -((sxy / m - (sx / m) * (sy / m)) / varX);
      n = n.clamp(_kFitMinN, _kFitMaxN);
    } else {
      n = floor.pathLossExponent;
    }
    final double intercept = (sy + n * sx) / m;
    fits.add(
      HmPathLossFit(
        ap: ap,
        interceptDbm: intercept,
        exponent: n,
        sampleCount: m,
      ),
    );
  }
  return fits;
}

/// The estimate at one cell.
class HmCellEstimate {
  const HmCellEstimate({
    required this.dbm,
    required this.fill,
    this.contributions = const <HmContribution>[],
  });

  /// dBm, or null for no data.
  final double? dbm;
  final HmFill fill;

  /// The samples that made this value, largest share first. Empty for a
  /// path-loss fill or no data.
  final List<HmContribution> contributions;
}

// ── The interpolation interface ─────────────────────────────────────────────
//
// Keith, 2026-09-26: he will write up exactly how he teaches heat-map
// generation, and his description becomes the primary model. Everything that
// turns samples into cell values sits behind this one interface, so a new or
// replacement method is a new [HmInterpolator] (and, if the student picks it,
// a new [HmMethod] value), with no change to the map builder, the spacing
// experiment, the controller, the stage or the controls.

/// Turns one set of samples into a value per cell.
abstract interface class HmInterpolator {
  /// The estimate at [q], with how it was made.
  HmCellEstimate estimateAt(HmPoint q);
}

/// Builds the interpolator for a floor, its samples and the settings.
typedef HmInterpolatorFactory =
    HmInterpolator Function(
      HmFloor floor,
      List<HmSample> samples,
      HmSettings settings,
    );

/// The documented methods this tool teaches today: IDW and nearest neighbor
/// with the guess range and the three extrapolation modes ([HmEstimator]).
HmInterpolator documentedHmInterpolator(
  HmFloor floor,
  List<HmSample> samples,
  HmSettings settings,
) => HmEstimator(floor, samples, settings);

/// IDW or nearest neighbor within the guess range, with the chosen
/// extrapolation beyond it (see the header).
class HmEstimator implements HmInterpolator {
  HmEstimator(this.floor, this.samples, this.settings)
    : fits = settings.extrapolation == HmExtrapolation.pathLoss
          ? fitHmPathLoss(floor, samples)
          : const <HmPathLossFit>[];

  final HmFloor floor;
  final List<HmSample> samples;
  final HmSettings settings;
  final List<HmPathLossFit> fits;

  /// The [k] nearest samples to [q] within [radius] (null: any distance),
  /// nearest first, as (distance, index).
  List<(double, int)> _nearest(HmPoint q, int k, double? radius) {
    final List<(double, int)> best = <(double, int)>[];
    for (int i = 0; i < samples.length; i++) {
      final double d = _dist(q, samples[i].p);
      if (radius != null && d > radius) continue;
      if (best.length == k && d >= best.last.$1) continue;
      int at = best.length;
      while (at > 0 && best[at - 1].$1 > d) {
        at--;
      }
      best.insert(at, (d, i));
      if (best.length > k) best.removeLast();
    }
    return best;
  }

  HmCellEstimate _fromNeighbors(List<(double, int)> nb, HmFill fill) {
    if (settings.method == HmMethod.nearest || nb.first.$1 <= 1e-9) {
      final (double d, int i) = nb.first;
      return HmCellEstimate(
        dbm: samples[i].dbm,
        fill: fill,
        contributions: <HmContribution>[
          HmContribution(sampleIndex: i, distanceM: d, weightShare: 1),
        ],
      );
    }
    final List<double> ds = <double>[for (final (double, int) n in nb) n.$1];
    final List<double> zs = <double>[
      for (final (double, int) n in nb) samples[n.$2].dbm,
    ];
    final List<double> w = idwWeights(ds, settings.power);
    final double sw = w.fold(0, (double a, double b) => a + b);
    return HmCellEstimate(
      dbm: idwCombine(ds, zs, settings.power, settings.domain),
      fill: fill,
      contributions: <HmContribution>[
        for (int j = 0; j < nb.length; j++)
          HmContribution(
            sampleIndex: nb[j].$2,
            distanceM: nb[j].$1,
            weightShare: w[j] / sw,
          ),
      ],
    );
  }

  @override
  HmCellEstimate estimateAt(HmPoint q) {
    if (samples.isEmpty) {
      return const HmCellEstimate(dbm: null, fill: HmFill.none);
    }
    final int k = settings.method == HmMethod.nearest ? 1 : kHmIdwNeighbors;
    final List<(double, int)> near = _nearest(q, k, settings.guessRangeM);
    if (near.isNotEmpty) return _fromNeighbors(near, HmFill.interpolated);
    switch (settings.extrapolation) {
      case HmExtrapolation.off:
        return const HmCellEstimate(dbm: null, fill: HmFill.none);
      case HmExtrapolation.flatIdw:
        return _fromNeighbors(_nearest(q, k, null), HmFill.flat);
      case HmExtrapolation.pathLoss:
        double best = double.negativeInfinity;
        for (final HmPathLossFit f in fits) {
          best = math.max(best, f.predictDbm(q));
        }
        return HmCellEstimate(dbm: best, fill: HmFill.model);
    }
  }
}

// ── The map ─────────────────────────────────────────────────────────────────

/// A computed map: estimate and truth for every cell, and the scores.
class HmMap {
  HmMap._({
    required this.cols,
    required this.rows,
    required this.cellM,
    required this.estimate,
    required this.truth,
    required this.fill,
    required this.rmseDb,
    required this.maxErrorDb,
    required this.maxErrorCell,
    required this.noDataShare,
    required this.dataCells,
  });

  final int cols;
  final int rows;
  final double cellM;

  /// Estimate per cell, dBm; NaN where there is no data. Row-major.
  final Float64List estimate;

  /// Truth per cell, dBm. Row-major.
  final Float64List truth;

  /// [HmFill] index per cell.
  final Uint8List fill;

  /// Root-mean-square of estimate minus truth over cells with data, or null
  /// when no cell has data.
  final double? rmseDb;

  /// The largest estimate-minus-truth by size (signed), or null.
  final double? maxErrorDb;

  /// Where [maxErrorDb] is, or null.
  final HmPoint? maxErrorCell;

  /// Share of the floor with no data (white), 0 to 1.
  final double noDataShare;
  final int dataCells;

  int get cellCount => cols * rows;

  HmPoint center(int col, int row) =>
      (x: (col + 0.5) * cellM, y: (row + 0.5) * cellM);

  double estimateAt(int col, int row) => estimate[row * cols + col];
  double truthAt(int col, int row) => truth[row * cols + col];

  /// Estimate minus truth, or NaN.
  double errorAt(int col, int row) => estimateAt(col, row) - truthAt(col, row);

  HmFill fillAt(int col, int row) => HmFill.values[fill[row * cols + col]];

  /// The cell containing [p], held to the floor.
  (int, int) cellOf(HmPoint p) => (
    (p.x / cellM).floor().clamp(0, cols - 1),
    (p.y / cellM).floor().clamp(0, rows - 1),
  );
}

/// The truth grid for [floor] at [cellM]; reusable across maps of one floor.
Float64List hmTruthGrid(HmFloor floor, [double cellM = kHmCellM]) {
  final int cols = (floor.widthM / cellM).round();
  final int rows = (floor.depthM / cellM).round();
  final Float64List t = Float64List(cols * rows);
  for (int r = 0; r < rows; r++) {
    for (int c = 0; c < cols; c++) {
      t[r * cols + c] = floor.truthDbm((
        x: (c + 0.5) * cellM,
        y: (r + 0.5) * cellM,
      ));
    }
  }
  return t;
}

/// Builds the map of [samples] under [settings] with [interpolator]. Pass
/// [truth] from [hmTruthGrid] to skip recomputing it.
HmMap buildHmMap(
  HmFloor floor,
  List<HmSample> samples,
  HmSettings settings, {
  Float64List? truth,
  double cellM = kHmCellM,
  HmInterpolatorFactory interpolator = documentedHmInterpolator,
}) {
  final int cols = (floor.widthM / cellM).round();
  final int rows = (floor.depthM / cellM).round();
  final Float64List t = truth ?? hmTruthGrid(floor, cellM);
  assert(t.length == cols * rows);
  final Float64List est = Float64List(cols * rows);
  final Uint8List fill = Uint8List(cols * rows);
  final HmInterpolator e = interpolator(floor, samples, settings);
  double sse = 0;
  int n = 0;
  double worst = 0;
  HmPoint? worstAt;
  for (int r = 0; r < rows; r++) {
    for (int c = 0; c < cols; c++) {
      final int i = r * cols + c;
      final HmPoint q = (x: (c + 0.5) * cellM, y: (r + 0.5) * cellM);
      final HmCellEstimate ce = e.estimateAt(q);
      fill[i] = ce.fill.index;
      final double? v = ce.dbm;
      if (v == null) {
        est[i] = double.nan;
        continue;
      }
      est[i] = v;
      final double err = v - t[i];
      sse += err * err;
      n++;
      if (worstAt == null || err.abs() > worst.abs()) {
        worst = err;
        worstAt = q;
      }
    }
  }
  return HmMap._(
    cols: cols,
    rows: rows,
    cellM: cellM,
    estimate: est,
    truth: t,
    fill: fill,
    rmseDb: n == 0 ? null : math.sqrt(sse / n),
    maxErrorDb: worstAt == null ? null : worst,
    maxErrorCell: worstAt,
    noDataShare: 1 - n / (cols * rows),
    dataCells: n,
  );
}

// ── Spacing experiment ──────────────────────────────────────────────────────

/// One line of the spacing experiment.
class HmSpacingSeries {
  const HmSpacingSeries({required this.label, required this.rmseDb});

  final String label;

  /// RMSE per spacing in [kHmExperimentSpacings] order, dB.
  final List<double> rmseDb;
}

/// Re-runs the grid preset at each of [kHmExperimentSpacings] and scores it.
/// Every cell is estimated (a cell beyond the guess range uses flat IDW when
/// extrapolation is off), so every spacing is scored on the same floor.
/// Series: no noise; then, when [noise] has sigma above 0, one raw reading
/// per point; and, when it also averages more than one, the averaged
/// readings.
List<HmSpacingSeries> runHmSpacingExperiment(
  HmFloor floor,
  HmSettings settings,
  HmNoise noise, {
  double cellM = kHmCellM,
  HmInterpolatorFactory interpolator = documentedHmInterpolator,
  List<double> spacingsM = kHmExperimentSpacings,
}) {
  final HmSettings s = settings.extrapolation == HmExtrapolation.off
      ? settings.copyWith(extrapolation: HmExtrapolation.flatIdw)
      : settings;
  final Float64List truth = hmTruthGrid(floor, cellM);
  List<double> run(HmNoise n) => <double>[
    for (final double sp in spacingsM)
      buildHmMap(
            floor,
            takeHmSamples(floor, hmGridPoints(floor, sp), n),
            s,
            truth: truth,
            cellM: cellM,
            interpolator: interpolator,
          ).rmseDb ??
          0,
  ];
  final List<HmSpacingSeries> out = <HmSpacingSeries>[
    HmSpacingSeries(
      label: 'No noise',
      rmseDb: run(noise.copyWith(sigmaDb: 0, averaging: 1)),
    ),
  ];
  if (noise.sigmaDb > 0) {
    out.add(
      HmSpacingSeries(
        label: 'Noise ${noise.sigmaDb.toStringAsFixed(1)} dB, 1 reading',
        rmseDb: run(noise.copyWith(averaging: 1)),
      ),
    );
    if (noise.averaging > 1) {
      out.add(
        HmSpacingSeries(
          label: 'Noise, ${noise.averaging} readings averaged',
          rmseDb: run(noise),
        ),
      );
    }
  }
  return out;
}

// ── Worked example (spec, must match) ───────────────────────────────────────

/// A cell 2 m, 4 m and 6 m from three samples of -55, -65 and -70 dBm.
abstract final class HmWorkedExample {
  static const List<double> distancesM = <double>[2, 4, 6];
  static const List<double> valuesDbm = <double>[-55, -65, -70];

  /// Raw weights 1 / d^p.
  static List<double> weights(double p) => idwWeights(distancesM, p);

  /// The cell's estimate, dBm. Nearest neighbor gives the nearest sample.
  static double result(double p, HmDomain domain, {bool nearest = false}) =>
      nearest ? valuesDbm.first : idwCombine(distancesM, valuesDbm, p, domain);
}

// ── Extrapolation arithmetic (spec) ─────────────────────────────────────────

/// Extra path loss from [fromM] to [toM] at exponent [n]: 10 n log10(to/from).
double hmDistanceLossDb(double fromM, double toM, double n) =>
    10 * n * _log10(toM / fromM);
