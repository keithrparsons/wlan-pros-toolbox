// Multipath Simulator model (Wi-Fi Classroom, 2026-09-25).
//
// Pure Dart, no Flutter imports. Built clean-room from wave superposition,
// the two-ray (image) model and Rayleigh fading theory, per the Wi-Fi Classroom spec
// (myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/07-multipath.md).
// Physics background: the Wi-Fi Classroom research brief §6.3 (lambda/2 node
// spacing; thick concrete |Gamma| about 0.39 at normal incidence).
//
// THE ONE EQUATION. The field at a receiver is the sum of every path's copy:
//
//   E = sum_i a_i * exp(-j k r_i) / r_i,    k = 2 pi / lambda
//
// where r_i is the path length and a_i is 1 for the direct path or the
// reflection coefficient (magnitude and phase) for a reflected one. Power is
// reported in dB relative to the direct path alone:
//
//   P_dB = 20 log10(|E| / |E_direct|)
//
// The three scenes the screen shows are three ways of choosing the paths:
//
//  1. [TwoRayScene]: one wall, seen from above. The reflected path is the
//     straight line from the transmitter's mirror image behind the wall
//     (the image method), so its length is exact.
//  2. [StandingWaveScene]: the receiver sits on the line between a distant
//     transmitter and a wall. The reflected copy travels 2d further, so the
//     two copies cancel every lambda/2.
//  3. [ManyPathScene]: 2 to 30 point reflectors at seeded random positions,
//     direct path blocked. Each reflected copy is given equal power at the
//     receiver and a random reflection phase, which is the textbook setup
//     whose sum is Rayleigh distributed in amplitude (exponential in power).
//
// Delay: a copy that travels Delta r further arrives Delta r / c later. The
// 802.11 OFDM long guard interval is 0.8 us, which is 239.8 m of extra path.
//
// ANTENNA DIVERSITY (added 2026-09-29, clean room, spec 41). Two or four
// antennas along the same track, each a branch of the same field. Combining
// works on the branches' normalized powers P_1..P_M (each averages 1):
//
//   selection:  P = max(P_1, ..., P_M)     (use the stronger antenna)
//   MRC:        P = P_1 + ... + P_M        (maximal ratio combining)
//
// MRC adds the branch SNRs, with equal noise in every branch, so its average
// is M, 10 log10(M) dB above one antenna. Neither is divided back down: both
// are read against one antenna's average, the way a receiver sees them.
// With independent Rayleigh branches, each P_i exponential with mean 1, the
// share of the time the combined power is below x is (Jakes, Microwave
// Mobile Communications, 1974, ch. 5; Goldsmith, Wireless Communications,
// 2005, ch. 7):
//
//   selection:  (1 - e^-x)^M
//   MRC:        1 - e^-x * sum_{k=0}^{M-1} x^k / k!
//
// Diversity gain at an outage level p is how much weaker the average can be
// for the same p: the combined level at p minus one antenna's level at p.
// At p = 1%: one antenna -20.0 dB; selection 2 +10.2 dB, 4 +15.8 dB; MRC 2
// +11.7 dB, 4 +19.1 dB.

import 'dart:math' as math;

/// Speed of light in vacuum, m/s.
const double kSpeedOfLight = 299792458.0;

/// The 802.11 OFDM long guard interval, in nanoseconds (0.8 us).
const double kGuardIntervalNs = 800;

/// Fade threshold used by the selection-diversity readout, dB below the mean.
const double kFadeThresholdDb = -10;

/// Floor used when a power is exactly zero, so a perfect null is finite on a
/// plot. Far below anything the screen's axis shows.
const double kPowerFloorDb = -120;

/// A minimal complex number: only what superposition needs.
class Complex {
  const Complex(this.re, this.im);

  /// e^(j theta) scaled by [magnitude].
  factory Complex.polar(double magnitude, double theta) =>
      Complex(magnitude * math.cos(theta), magnitude * math.sin(theta));

  static const Complex zero = Complex(0, 0);
  static const Complex one = Complex(1, 0);

  final double re;
  final double im;

  Complex operator +(Complex o) => Complex(re + o.re, im + o.im);
  Complex operator -(Complex o) => Complex(re - o.re, im - o.im);
  Complex operator *(Complex o) =>
      Complex(re * o.re - im * o.im, re * o.im + im * o.re);
  Complex scale(double s) => Complex(re * s, im * s);

  /// Squared magnitude (power).
  double get abs2 => re * re + im * im;
  double get abs => math.sqrt(abs2);
  double get arg => math.atan2(im, re);

  /// Rotates counterclockwise by [theta] radians.
  Complex rotate(double theta) => this * Complex.polar(1, theta);

  @override
  String toString() => 'Complex($re, $im)';
}

/// The three bands, each at the frequency the spec quotes its node spacing
/// for (6.2 cm at 2.4 GHz, 2.7 cm at 5.5 GHz, 2.3 cm at 6.5 GHz).
enum MultipathBand {
  b24(2.4e9, '2.4 GHz'),
  b55(5.5e9, '5.5 GHz'),
  b65(6.5e9, '6.5 GHz');

  const MultipathBand(this.hz, this.label);

  final double hz;
  final String label;

  /// Wavelength in meters.
  double get wavelength => kSpeedOfLight / hz;

  /// Wave number k = 2 pi / lambda, rad/m.
  double get k => 2 * math.pi / wavelength;
}

/// Reflecting-surface presets. Every preset reflects with phase pi: metal is
/// a near-perfect conductor, and a dielectric at normal incidence has a
/// negative real reflection coefficient, (1 - sqrt(eps)) / (1 + sqrt(eps)).
enum WallMaterial {
  metal(1.0, 'Metal'),
  concrete(0.39, 'Thick concrete'),
  drywall(0.1, 'Drywall'),
  custom(null, 'Custom');

  const WallMaterial(this.gammaMagnitude, this.label);

  /// |Gamma| for a preset; null for [custom], where the slider sets it.
  final double? gammaMagnitude;
  final String label;
}

/// Reflection coefficient with magnitude [magnitude] and phase pi.
Complex reflectionCoefficient(double magnitude) =>
    Complex.polar(magnitude.clamp(0.0, 1.0), math.pi);

/// One propagation path: its total length and its complex coefficient.
class MultipathPath {
  const MultipathPath({
    required this.length,
    required this.coefficient,
    this.isDirect = false,
  });

  /// Total path length, meters.
  final double length;

  /// a_i: 1 for the direct path, Gamma for a reflection.
  final Complex coefficient;
  final bool isDirect;
}

/// The pure functions every scene shares.
abstract final class MultipathMath {
  /// One path's contribution a * exp(-j k r) / r.
  static Complex contribution(MultipathPath p, double k) =>
      p.coefficient * Complex.polar(1 / p.length, -k * p.length);

  /// The received field: the sum of every path's contribution.
  static Complex field(List<MultipathPath> paths, double k) {
    Complex sum = Complex.zero;
    for (final MultipathPath p in paths) {
      sum = sum + contribution(p, k);
    }
    return sum;
  }

  /// Power in dB relative to a direct path of length [directLength] alone:
  /// 20 log10(|E| / |E_direct|), with |E_direct| = 1 / r_direct.
  static double relativePowerDb(
    List<MultipathPath> paths,
    double k,
    double directLength,
  ) {
    final double ratio = field(paths, k).abs * directLength;
    return amplitudeRatioToDb(ratio);
  }

  /// 20 log10(ratio), floored at [kPowerFloorDb] for an exact null.
  static double amplitudeRatioToDb(double ratio) {
    if (ratio <= 0) return kPowerFloorDb;
    return math.max(kPowerFloorDb, 20 * math.log(ratio) / math.ln10);
  }

  /// 10 log10(power ratio), floored at [kPowerFloorDb].
  static double powerRatioToDb(double ratio) {
    if (ratio <= 0) return kPowerFloorDb;
    return math.max(kPowerFloorDb, 10 * math.log(ratio) / math.ln10);
  }

  /// Extra delay of a path [extraMeters] longer than the reference, in ns.
  static double delayNs(double extraMeters) =>
      extraMeters / kSpeedOfLight * 1e9;

  /// Extra path that equals the 0.8 us guard interval, meters (239.8 m).
  static double get guardIntervalMeters =>
      kGuardIntervalNs * 1e-9 * kSpeedOfLight;

  /// True when a copy arrives later than the guard interval and spills into
  /// the next OFDM symbol.
  static bool exceedsGuardInterval(double delayNs) =>
      delayNs > kGuardIntervalNs;

  /// The phasors of [paths], scaled and rotated so the reference phasor
  /// [reference] becomes the unit arrow pointing right (1 + 0j). The screen
  /// draws these head to tail; their sum is the received field on the same
  /// scale.
  static List<Complex> normalizedPhasors(
    List<MultipathPath> paths,
    double k,
    Complex reference,
  ) {
    final double mag = reference.abs;
    if (mag == 0) return <Complex>[for (final _ in paths) Complex.zero];
    final double theta = -reference.arg;
    return <Complex>[
      for (final MultipathPath p in paths)
        contribution(p, k).rotate(theta).scale(1 / mag),
    ];
  }

  /// Sum of a list of complex numbers.
  static Complex sum(Iterable<Complex> xs) {
    Complex s = Complex.zero;
    for (final Complex x in xs) {
      s = s + x;
    }
    return s;
  }

  /// Rayleigh (exponential-power) CDF: the probability that normalized power
  /// is below [db] dB, 1 - exp(-10^(db/10)). At -10 dB: 1 - e^(-0.1) = 9.5%.
  static double rayleighCdf(double db) =>
      1 - math.exp(-math.pow(10, db / 10).toDouble());

  /// Rayleigh probability that normalized power falls in [loDb, hiDb).
  /// A [loDb] of negative infinity means "everything below [hiDb]".
  static double rayleighBinProbability(double loDb, double hiDb) {
    final double lo = loDb.isFinite ? rayleighCdf(loDb) : 0;
    return rayleighCdf(hiDb) - lo;
  }

  /// Local minima of power in [lo, hi] meters for the sampled function
  /// [powerAt] (linear power, not dB). Grid search at [step] meters, then
  /// golden-section refinement to about a micrometer.
  static List<double> findMinima(
    double Function(double x) powerAt,
    double lo,
    double hi,
    double step,
  ) {
    final List<double> out = <double>[];
    final int n = ((hi - lo) / step).floor();
    if (n < 2) return out;
    double prev = powerAt(lo);
    double cur = powerAt(lo + step);
    for (int i = 2; i <= n; i++) {
      final double x = lo + i * step;
      final double next = powerAt(x);
      if (cur < prev && cur <= next) {
        out.add(_golden(powerAt, x - 2 * step, x));
      }
      prev = cur;
      cur = next;
    }
    return out;
  }

  static double _golden(double Function(double) f, double a, double b) {
    const double g = 0.6180339887498949;
    double c = b - g * (b - a);
    double d = a + g * (b - a);
    double fc = f(c);
    double fd = f(d);
    while ((b - a).abs() > 1e-7) {
      if (fc < fd) {
        b = d;
        d = c;
        fd = fc;
        c = b - g * (b - a);
        fc = f(c);
      } else {
        a = c;
        c = d;
        fc = fd;
        d = a + g * (b - a);
        fd = f(d);
      }
    }
    return (a + b) / 2;
  }
}

// ── Mode 1: one wall (two-ray) ──────────────────────────────────────────────

/// One wall seen from above. The wall is the line y = 0; the transmitter and
/// the receiver's 1 m track sit in front of it (y > 0). All lengths meters.
class TwoRayScene {
  const TwoRayScene({
    this.txX = 0,
    this.txY = 1.0,
    this.rxY = 0.6,
    this.trackStart = 2.0,
    this.trackLength = 1.0,
  });

  /// Transmitter position.
  final double txX;

  /// Transmitter distance from the wall.
  final double txY;

  /// The receiver track's distance from the wall.
  final double rxY;

  /// Where the receiver track starts, along the wall.
  final double trackStart;

  /// Track length (the spec's 1 m).
  final double trackLength;

  /// Receiver x for a track offset [t] in [0, trackLength].
  double rxX(double t) => trackStart + t.clamp(0.0, trackLength);

  double directLength(double t) {
    final double dx = rxX(t) - txX;
    final double dy = txY - rxY;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Image method: the reflected path is as long as the straight line from
  /// the transmitter's mirror image (txX, -txY) to the receiver.
  double reflectedLength(double t) {
    final double dx = rxX(t) - txX;
    final double dy = txY + rxY;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Where the reflected ray meets the wall (y = 0), for drawing.
  double reflectionPointX(double t) {
    // Similar triangles between the image and the receiver.
    final double f = txY / (txY + rxY);
    return txX + (rxX(t) - txX) * f;
  }

  List<MultipathPath> paths(double t, Complex gamma) => <MultipathPath>[
    MultipathPath(
      length: directLength(t),
      coefficient: Complex.one,
      isDirect: true,
    ),
    MultipathPath(length: reflectedLength(t), coefficient: gamma),
  ];

  double powerDb(double t, Complex gamma, MultipathBand band) =>
      MultipathMath.relativePowerDb(paths(t, gamma), band.k, directLength(t));

  /// Power in dB at [samples] evenly spaced track offsets, 0 to trackLength.
  List<double> sweepDb(Complex gamma, MultipathBand band, int samples) =>
      <double>[
        for (int i = 0; i < samples; i++)
          powerDb(trackLength * i / (samples - 1), gamma, band),
      ];
}

// ── Mode 2: standing wave in front of a wall ────────────────────────────────

/// A receiver on the line between a transmitter [txDistance] meters from a
/// wall and the wall itself. At distance d from the wall the direct copy
/// travels txDistance - d and the reflected copy txDistance + d.
class StandingWaveScene {
  const StandingWaveScene({this.txDistance = 10.0, this.range = 0.4});

  /// Transmitter distance from the wall, meters.
  final double txDistance;

  /// Longest receiver distance from the wall the screen shows, meters.
  final double range;

  double directLength(double d) => txDistance - d;
  double reflectedLength(double d) => txDistance + d;

  List<MultipathPath> paths(double d, Complex gamma) => <MultipathPath>[
    MultipathPath(
      length: directLength(d),
      coefficient: Complex.one,
      isDirect: true,
    ),
    MultipathPath(length: reflectedLength(d), coefficient: gamma),
  ];

  double powerDb(double d, Complex gamma, MultipathBand band) =>
      MultipathMath.relativePowerDb(paths(d, gamma), band.k, directLength(d));

  /// Linear power relative to the direct path alone.
  double powerRatio(double d, Complex gamma, MultipathBand band) {
    final double a = MultipathMath.field(paths(d, gamma), band.k).abs;
    final double r = a * directLength(d);
    return r * r;
  }

  List<double> sweepDb(Complex gamma, MultipathBand band, int samples) =>
      <double>[
        for (int i = 0; i < samples; i++)
          powerDb(range * i / (samples - 1), gamma, band),
      ];

  /// Distances from the wall (meters) where power is at a local minimum,
  /// from just off the wall out to [range]. The wall itself (d = 0) is a
  /// null for metal but is an endpoint, not a local minimum, so it is not
  /// listed.
  List<double> nulls(Complex gamma, MultipathBand band) =>
      MultipathMath.findMinima(
        (double d) => powerRatio(d, gamma, band),
        0,
        range,
        band.wavelength / 200,
      );

  /// Peak-to-null ripple for a reflector of magnitude [g], in dB:
  /// 20 log10((1 + g) / (1 - g)). Infinite for a perfect reflector.
  static double rippleDb(double g) {
    if (g >= 1) return double.infinity;
    return 20 * math.log((1 + g) / (1 - g)) / math.ln10;
  }
}

// ── Mode 3: many paths ──────────────────────────────────────────────────────

/// How far away the reflectors are. Only the delay readout changes much: the
/// fading pattern along a 2 m track looks the same at any scale.
enum ScatterEnvironment {
  room('Room', 1.0, 10.0, 6.0),
  hall('Large hall', 5.0, 60.0, 30.0),
  outdoors('Outdoors', 20.0, 300.0, 120.0);

  const ScatterEnvironment(
    this.label,
    this.minRadius,
    this.maxRadius,
    this.txDistance,
  );

  final String label;

  /// Reflectors sit between these distances from the track center, meters.
  final double minRadius;
  final double maxRadius;

  /// Blocked direct-path length, transmitter to track center, meters.
  final double txDistance;
}

/// One point reflector.
class Scatterer {
  const Scatterer({
    required this.x,
    required this.y,
    required this.txLeg,
    required this.coefficient,
  });

  /// Position, meters, with the receiver track on y = 0 from x = 0.
  final double x;
  final double y;

  /// Transmitter-to-reflector distance, meters.
  final double txLeg;

  /// Complex coefficient: equal-power magnitude and a random phase.
  final Complex coefficient;
}

/// 2 to 30 reflectors around a 2 m receiver track, direct path blocked.
class ManyPathScene {
  ManyPathScene._({
    required this.scatterers,
    required this.environment,
    required this.txX,
    required this.txY,
    required this.trackLength,
  });

  /// Places [count] reflectors from a seeded RNG. Every reflector is given
  /// the same power at the track center, so none dominates, and a uniform
  /// random reflection phase: the equal-power random-phase sum that the
  /// Rayleigh model describes.
  factory ManyPathScene.generate({
    required int seed,
    required int count,
    ScatterEnvironment environment = ScatterEnvironment.room,
    double trackLength = 2.0,
  }) {
    final math.Random rng = math.Random(seed);
    final double cx = trackLength / 2;
    // Transmitter off to one side at the environment's distance.
    final double txAngle = 2 * math.pi * rng.nextDouble();
    final double txX = cx + environment.txDistance * math.cos(txAngle);
    final double txY = environment.txDistance * math.sin(txAngle);
    final double perPath = 1 / math.sqrt(count);
    final List<Scatterer> list = <Scatterer>[];
    for (int i = 0; i < count; i++) {
      final double angle = 2 * math.pi * rng.nextDouble();
      final double radius =
          environment.minRadius +
          (environment.maxRadius - environment.minRadius) * rng.nextDouble();
      final double x = cx + radius * math.cos(angle);
      final double y = radius * math.sin(angle);
      final double txLeg = math.sqrt(
        (x - txX) * (x - txX) + (y - txY) * (y - txY),
      );
      final double rxLeg = radius; // distance to the track center
      // a_i / r_i = perPath at the track center, so |a_i| = perPath * r_i.
      final double mag = perPath * (txLeg + rxLeg);
      final double phase = 2 * math.pi * rng.nextDouble();
      list.add(
        Scatterer(
          x: x,
          y: y,
          txLeg: txLeg,
          coefficient: Complex.polar(mag, phase),
        ),
      );
    }
    return ManyPathScene._(
      scatterers: list,
      environment: environment,
      txX: txX,
      txY: txY,
      trackLength: trackLength,
    );
  }

  final List<Scatterer> scatterers;
  final ScatterEnvironment environment;
  final double txX;
  final double txY;
  final double trackLength;

  /// Straight-line transmitter-to-receiver distance at track position [x]
  /// (the blocked direct path, the reference for extra delay).
  double directLength(double x) => math.sqrt((x - txX) * (x - txX) + txY * txY);

  List<MultipathPath> pathsAt(double x) => <MultipathPath>[
    for (final Scatterer s in scatterers)
      MultipathPath(
        length: s.txLeg + math.sqrt((s.x - x) * (s.x - x) + s.y * s.y),
        coefficient: s.coefficient,
      ),
  ];

  /// Received power at track position [x], normalized to the local mean
  /// power sum_i |a_i / r_i|^2. For random phases its average is 1.
  double normalizedPower(double x, MultipathBand band) {
    final List<MultipathPath> ps = pathsAt(x);
    double mean = 0;
    for (final MultipathPath p in ps) {
      mean += p.coefficient.abs2 / (p.length * p.length);
    }
    if (mean == 0) return 0;
    return MultipathMath.field(ps, band.k).abs2 / mean;
  }

  double normalizedPowerDb(double x, MultipathBand band) =>
      MultipathMath.powerRatioToDb(normalizedPower(x, band));

  /// Normalized power in dB at [samples] track positions from 0 to
  /// trackLength, shifted by [offset] meters (the second antenna). Positions
  /// past the track end are still computed; the field is defined everywhere.
  List<double> sweepDb(MultipathBand band, int samples, {double offset = 0}) =>
      <double>[
        for (int i = 0; i < samples; i++)
          normalizedPowerDb(trackLength * i / (samples - 1) + offset, band),
      ];

  /// Each reflected path's extra length over the blocked direct path at
  /// track position [x], meters.
  List<double> extraLengths(double x) {
    final double direct = directLength(x);
    return <double>[
      for (final MultipathPath p in pathsAt(x)) p.length - direct,
    ];
  }
}

// ── Statistics ──────────────────────────────────────────────────────────────

/// How often two antennas are faded, alone and together.
class FadeStats {
  const FadeStats({
    required this.samples,
    required this.fadedA,
    required this.fadedB,
    required this.fadedBoth,
  });

  /// Computes the share of samples below [thresholdDb] for trace [a], trace
  /// [b], and both at once. The traces must be the same length.
  factory FadeStats.from(
    List<double> a,
    List<double> b, {
    double thresholdDb = kFadeThresholdDb,
  }) {
    assert(a.length == b.length);
    int fa = 0;
    int fb = 0;
    int both = 0;
    for (int i = 0; i < a.length; i++) {
      final bool xa = a[i] < thresholdDb;
      final bool xb = b[i] < thresholdDb;
      if (xa) fa++;
      if (xb) fb++;
      if (xa && xb) both++;
    }
    return FadeStats(
      samples: a.length,
      fadedA: fa,
      fadedB: fb,
      fadedBoth: both,
    );
  }

  final int samples;
  final int fadedA;
  final int fadedB;
  final int fadedBoth;

  double get fractionA => samples == 0 ? 0 : fadedA / samples;
  double get fractionB => samples == 0 ? 0 : fadedB / samples;

  /// Both faded at once: the only time selection diversity (pick the
  /// stronger antenna) is faded too.
  double get fractionBoth => samples == 0 ? 0 : fadedBoth / samples;
}

// ── Antenna diversity ───────────────────────────────────────────────────────

/// How a receiver with several antennas turns their signals into one.
enum CombineMethod {
  aOnly('A only'),
  selection('Selection'),
  mrc('MRC');

  const CombineMethod(this.label);

  /// Label on the Combine toggle.
  final String label;

  /// The one longer name the readouts use.
  String get longName => switch (this) {
    CombineMethod.aOnly => 'Antenna A only',
    CombineMethod.selection => 'Selection (the stronger antenna)',
    CombineMethod.mrc => 'MRC (maximal ratio combining)',
  };
}

/// Closed forms and combining rules for antenna diversity over independent
/// Rayleigh branches. Powers here are linear and normalized, so one antenna
/// averages 1.
abstract final class DiversityMath {
  /// The outage level the gain readout uses, 1%.
  static const double gainOutage = 0.01;

  /// Combines the branch powers [p] (linear) by [method]. [CombineMethod.aOnly]
  /// returns the first branch.
  static double combine(CombineMethod method, List<double> p) {
    switch (method) {
      case CombineMethod.aOnly:
        return p.first;
      case CombineMethod.selection:
        double best = p.first;
        for (final double v in p) {
          if (v > best) best = v;
        }
        return best;
      case CombineMethod.mrc:
        double sum = 0;
        for (final double v in p) {
          sum += v;
        }
        return sum;
    }
  }

  /// Combines per-branch traces in dB, sample by sample, and returns the
  /// combined trace in dB. Every trace must be the same length.
  static List<double> combineDb(
    CombineMethod method,
    List<List<double>> branchesDb,
  ) {
    final int n = branchesDb.first.length;
    for (final List<double> b in branchesDb) {
      assert(b.length == n);
    }
    return <double>[
      for (int i = 0; i < n; i++)
        MultipathMath.powerRatioToDb(
          combine(method, <double>[
            for (final List<double> b in branchesDb) dbToPower(b[i]),
          ]),
        ),
    ];
  }

  /// 10^(db/10); the power floor maps to 0.
  static double dbToPower(double db) =>
      db <= kPowerFloorDb ? 0 : math.pow(10, db / 10).toDouble();

  /// Share of the time the combined power of [m] independent Rayleigh
  /// branches is below [x] (linear, against one branch's average).
  static double outage(CombineMethod method, double x, int m) {
    if (x <= 0) return 0;
    switch (method) {
      case CombineMethod.aOnly:
        return 1 - math.exp(-x);
      case CombineMethod.selection:
        return math.pow(1 - math.exp(-x), m).toDouble();
      case CombineMethod.mrc:
        // 1 - e^-x sum_{k<m} x^k / k!, the Erlang (gamma, shape m) CDF.
        double term = 1;
        double sum = 1;
        for (int k = 1; k < m; k++) {
          term *= x / k;
          sum += term;
        }
        return 1 - math.exp(-x) * sum;
    }
  }

  /// [outage] with the level in dB.
  static double outageAtDb(CombineMethod method, double db, int m) =>
      outage(method, math.pow(10, db / 10).toDouble(), m);

  /// The level, dB against one branch's average, that the combined power of
  /// [m] branches is below a share [p] of the time. Bisection on the
  /// monotone outage function, to well under 0.001 dB.
  static double levelAtOutageDb(CombineMethod method, int m, double p) {
    double lo = -80;
    double hi = 30;
    for (int i = 0; i < 100; i++) {
      final double mid = (lo + hi) / 2;
      if (outageAtDb(method, mid, m) < p) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }

  /// Diversity gain at outage level [p], dB: the combined level at [p] minus
  /// one antenna's level at [p]. Zero for [CombineMethod.aOnly].
  static double gainDb(CombineMethod method, int m, [double p = gainOutage]) =>
      levelAtOutageDb(method, m, p) -
      levelAtOutageDb(CombineMethod.aOnly, 1, p);

  /// The empirical level a share [p] of [db] falls below: the sample at rank
  /// floor(p * n) of the sorted trace.
  static double percentileDb(List<double> db, double p) {
    if (db.isEmpty) return kPowerFloorDb;
    final List<double> s = List<double>.of(db)..sort();
    final int i = (p * s.length).floor().clamp(0, s.length - 1);
    return s[i];
  }

  /// Share of [db] below [thresholdDb].
  static double fractionBelow(List<double> db, double thresholdDb) {
    if (db.isEmpty) return 0;
    int n = 0;
    for (final double v in db) {
      if (v < thresholdDb) n++;
    }
    return n / db.length;
  }
}

/// Diversity over a [ManyPathScene]: [antennas] antennas along the track,
/// antenna A at each track position and the others [spacing] meters apart
/// behind it (B at +spacing, C at +2 spacing, D at +3 spacing).
extension ManyPathDiversity on ManyPathScene {
  /// Each antenna's trace in dB, A first.
  List<List<double>> branchSweepsDb(
    MultipathBand band,
    int samples, {
    required int antennas,
    required double spacing,
  }) => <List<double>>[
    for (int j = 0; j < antennas; j++)
      sweepDb(band, samples, offset: j * spacing),
  ];

  /// The combined trace in dB, against one antenna's average.
  List<double> combinedSweep(
    CombineMethod method,
    MultipathBand band,
    int samples, {
    int antennas = 2,
    required double spacing,
  }) => DiversityMath.combineDb(
    method,
    branchSweepsDb(band, samples, antennas: antennas, spacing: spacing),
  );
}

/// A dB histogram with fixed bins from [lo] to [hi]. Samples below [lo] land
/// in the first bin and samples at or above [hi] in the last, so no sample is
/// dropped.
class PowerHistogram {
  PowerHistogram._(this.lo, this.hi, this.binWidth, this.counts, this.total);

  factory PowerHistogram.of(
    List<double> db, {
    double lo = -30,
    double hi = 10,
    double binWidth = 2.5,
  }) {
    final int bins = ((hi - lo) / binWidth).round();
    final List<int> counts = List<int>.filled(bins, 0);
    for (final double v in db) {
      int i = ((v - lo) / binWidth).floor();
      if (i < 0) i = 0;
      if (i >= bins) i = bins - 1;
      counts[i]++;
    }
    return PowerHistogram._(lo, hi, binWidth, counts, db.length);
  }

  final double lo;
  final double hi;
  final double binWidth;
  final List<int> counts;
  final int total;

  int get bins => counts.length;

  /// Share of samples in bin [i].
  double fraction(int i) => total == 0 ? 0 : counts[i] / total;

  /// The Rayleigh prediction for bin [i], with the same open ends as the
  /// counts (first bin takes everything below, last everything above).
  double rayleighFraction(int i) {
    final double a = i == 0 ? double.negativeInfinity : lo + i * binWidth;
    if (i == bins - 1) return 1 - MultipathMath.rayleighCdf(a);
    return MultipathMath.rayleighBinProbability(a, lo + (i + 1) * binWidth);
  }
}
