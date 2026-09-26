// Where Am I? engine (Wi-Fi Classroom, 2026-09-26): signal strength vs
// round-trip timing, and trilateration.
//
// Pure Dart, no Flutter imports. Built clean-room from the Wi-Fi Classroom
// wave 4 research brief, row F, per myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/33-location-rssi-vs-ftm.md. Same inputs and seed, same
// answer.
//
// THE MODEL (a teaching model, and the screen says so):
//
//   Signal strength. The received level from AP i at true distance d is
//     RSSI = P - PL(d) + sigma x g
//     PL(d) = FSPL(1 m) + 10 n log10(d)   (FsplMath.logDistanceDb, the same
//                                          log-distance model the Roaming Walk
//                                          and Heat Map Builder use)
//   where P is the power each AP radiates (illustrative), sigma is the
//   shadowing in dB (illustrative) and g is a seeded standard normal draw.
//   The device inverts the same model with the nominal exponent (no
//   shadowing term, because it cannot know it):
//     d_est = 10^((P - FSPL(1 m) - RSSI) / (10 n))
//   So with matching n, d_est = d x 10^(-sigma g / (10 n)): a one-sigma
//   shadowing error multiplies the distance by 10^(sigma / (10 n)). With
//   sigma = 6 dB and n = 3 that factor is 10^0.2 = 1.585.
//
//   Timing (fine timing measurement, FTM, from 802.11mc). The device times a
//   frame's round trip; distance = c x RTT / 2. The model adds a seeded
//   Gaussian ranging error of the chosen standard deviation (a vendor
//   developer document gives 1 to 2 m), and, when an AP's direct path is
//   blocked, a positive bias: the first path to arrive is a reflection, which
//   travelled farther. A distance never reads below zero.
//
//   Trilateration. The position that best fits all the distances in the
//   least-squares sense: minimize sum (|p - AP_i| - r_i)^2. A linear solve
//   (each circle's equation minus the first one's) gives the start, then
//   damped Gauss-Newton (Levenberg-Marquardt) refines it, inside the box no
//   farther from the APs than the longest distance. With exact distances the answer is the true
//   position. With bad ones the circles may not meet at all: two circles
//   whose APs are farther apart than the two radii added up (or one inside
//   the other) share no point, and the fit is a compromise.
//
//   Spread. The whole measurement is repeated [kLocTrials] times with fresh
//   draws (trial 0 is the one drawn on the floor), and the spread radius is
//   the root mean square distance of those estimates from their average.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'fspl_math.dart';

/// A point on the floor, meters from the top-left corner.
typedef LocPoint = ({double x, double y});

/// Floor size, meters.
const double kLocFloorWidthM = 30;
const double kLocFloorDepthM = 20;

/// Band center used for the path loss at 1 m (5 GHz).
const double kLocFreqMHz = 5500;

/// What each AP radiates, dBm (illustrative).
const double kLocApPowerDbm = 17;

/// Path-loss exponent range and default.
const double kLocMinExponent = 2;
const double kLocMaxExponent = 4;
const double kLocDefaultExponent = 3;

/// Shadowing sigma range and default, dB (illustrative).
const double kLocMaxSigmaDb = 10;
const double kLocDefaultSigmaDb = 6;

/// Timing error range and default, meters (one standard deviation). The
/// vendor-documented figure is 1 to 2 m.
const double kLocMinFtmErrorM = 0.5;
const double kLocMaxFtmErrorM = 3;
const double kLocDefaultFtmErrorM = 1.5;

/// Blocked-direct-path bias range and default, meters (illustrative).
const double kLocMaxBlockedBiasM = 10;
const double kLocDefaultBlockedBiasM = 4;

/// AP count range and default.
const int kLocMinAps = 3;
const int kLocMaxAps = 6;
const int kLocDefaultAps = 4;

/// Repeated estimates behind the scatter and the spread radius.
const int kLocTrials = 50;

/// Speed of light, m/s.
const double kLocSpeedOfLight = FsplMath.speedOfLight;

/// Where the device starts.
const LocPoint kLocDefaultDevice = (x: 11, y: 8);

double locDistance(LocPoint a, LocPoint b) {
  final double dx = a.x - b.x;
  final double dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// The AP positions for [count] APs (3 to 6), spread around the floor.
List<LocPoint> defaultLocAps(int count) {
  switch (count.clamp(kLocMinAps, kLocMaxAps)) {
    case 3:
      return const <LocPoint>[(x: 3, y: 3), (x: 27, y: 4), (x: 15, y: 17)];
    case 4:
      return const <LocPoint>[
        (x: 3, y: 3),
        (x: 27, y: 3),
        (x: 27, y: 17),
        (x: 3, y: 17),
      ];
    case 5:
      return const <LocPoint>[
        (x: 3, y: 3),
        (x: 27, y: 3),
        (x: 27, y: 17),
        (x: 3, y: 17),
        (x: 15, y: 10),
      ];
    default:
      return const <LocPoint>[
        (x: 3, y: 3),
        (x: 15, y: 2),
        (x: 27, y: 3),
        (x: 27, y: 17),
        (x: 15, y: 18),
        (x: 3, y: 17),
      ];
  }
}

// ── Signal strength ─────────────────────────────────────────────────────────

/// Path loss at [distanceM] (held to at least 0.1 m) with exponent [n].
double locPathLossDb(double distanceM, double n) =>
    FsplMath.logDistanceDb(math.max(distanceM, 0.1), kLocFreqMHz, n);

/// Received level at [distanceM], with [shadowDb] of shadowing added, dBm.
double locRssiDbm(
  double distanceM, {
  required double n,
  double shadowDb = 0,
  double apPowerDbm = kLocApPowerDbm,
}) => apPowerDbm - locPathLossDb(distanceM, n) + shadowDb;

/// The distance a device infers from [rssiDbm] by inverting the log-distance
/// model with exponent [n] and no shadowing.
double locDistanceFromRssi(
  double rssiDbm, {
  required double n,
  double apPowerDbm = kLocApPowerDbm,
}) {
  final double pl = apPowerDbm - rssiDbm;
  return math
      .pow(10, (pl - FsplMath.fsplDb(1, kLocFreqMHz)) / (10 * n))
      .toDouble();
}

/// The one-sigma distance error factor, 10^(sigma / (10 n)).
double locErrorFactor(double sigmaDb, double n) =>
    math.pow(10, sigmaDb / (10 * n)).toDouble();

/// The one-sigma range of a signal-strength distance estimate for a device
/// [distanceM] away: (distance / factor, distance x factor).
(double low, double high) locOneSigmaRange(
  double distanceM,
  double sigmaDb,
  double n,
) {
  final double f = locErrorFactor(sigmaDb, n);
  return (distanceM / f, distanceM * f);
}

// ── Timing ──────────────────────────────────────────────────────────────────

/// Round-trip time for [distanceM], nanoseconds: 2 d / c.
double locRoundTripNs(double distanceM) =>
    2 * distanceM / kLocSpeedOfLight * 1e9;

/// Distance for a round-trip time of [ns] nanoseconds: c x RTT / 2.
double locDistanceFromRoundTripNs(double ns) =>
    kLocSpeedOfLight * ns * 1e-9 / 2;

/// How far light travels in one nanosecond, meters (about 0.30).
const double kLocMetersPerNs = kLocSpeedOfLight * 1e-9;

// ── Trilateration ───────────────────────────────────────────────────────────

/// The least-squares position for [aps] and [distances], and how well it
/// fits. Returns null only when the APs are all on one line or fewer than
/// three are given.
class LocFix {
  const LocFix({required this.position, required this.rmsResidualM});

  final LocPoint position;

  /// Root mean square of (|p - AP_i| - r_i), meters: how far the best point
  /// is from lying on every circle.
  final double rmsResidualM;
}

LocFix? trilaterate(List<LocPoint> aps, List<double> distances) {
  assert(aps.length == distances.length);
  final int k = aps.length;
  if (k < 3) return null;
  // Linear start: circle i minus circle 0.
  //   2 (xi - x0) x + 2 (yi - y0) y = r0^2 - ri^2 + xi^2 - x0^2 + yi^2 - y0^2
  double a11 = 0, a12 = 0, a22 = 0, b1 = 0, b2 = 0;
  final LocPoint p0 = aps[0];
  final double r0 = distances[0];
  for (int i = 1; i < k; i++) {
    final LocPoint pi = aps[i];
    final double ax = 2 * (pi.x - p0.x);
    final double ay = 2 * (pi.y - p0.y);
    final double b =
        r0 * r0 -
        distances[i] * distances[i] +
        pi.x * pi.x -
        p0.x * p0.x +
        pi.y * pi.y -
        p0.y * p0.y;
    a11 += ax * ax;
    a12 += ax * ay;
    a22 += ay * ay;
    b1 += ax * b;
    b2 += ay * b;
  }
  final double det = a11 * a22 - a12 * a12;
  if (det.abs() < 1e-9) return null;
  double x = (a22 * b1 - a12 * b2) / det;
  double y = (a11 * b2 - a12 * b1) / det;

  // The answer cannot sensibly lie farther from the APs than the longest
  // distance: every point of circle i is within r_i of AP i. Holding the
  // search inside that box keeps a badly conditioned start (inconsistent
  // circles, a near-singular linear solve) from running off to infinity.
  double maxR = 0;
  double minX = double.infinity, maxX = double.negativeInfinity;
  double minY = double.infinity, maxY = double.negativeInfinity;
  for (int i = 0; i < k; i++) {
    maxR = math.max(maxR, distances[i]);
    minX = math.min(minX, aps[i].x);
    maxX = math.max(maxX, aps[i].x);
    minY = math.min(minY, aps[i].y);
    maxY = math.max(maxY, aps[i].y);
  }
  minX -= maxR;
  maxX += maxR;
  minY -= maxR;
  maxY += maxR;
  double clampX(double v) =>
      v.isFinite ? v.clamp(minX, maxX) : (minX + maxX) / 2;
  double clampY(double v) =>
      v.isFinite ? v.clamp(minY, maxY) : (minY + maxY) / 2;
  x = clampX(x);
  y = clampY(y);

  double cost(double px, double py) {
    double c = 0;
    for (int i = 0; i < k; i++) {
      final double f = locDistance((x: px, y: py), aps[i]) - distances[i];
      c += f * f;
    }
    return c;
  }

  // Levenberg-Marquardt on f_i = |p - AP_i| - r_i: Gauss-Newton steps,
  // damped when a step would make the fit worse.
  double lambda = 1e-3;
  double current = cost(x, y);
  for (int it = 0; it < 60; it++) {
    double j11 = 0, j12 = 0, j22 = 0, g1 = 0, g2 = 0;
    for (int i = 0; i < k; i++) {
      final double dx = x - aps[i].x;
      final double dy = y - aps[i].y;
      final double d = math.max(math.sqrt(dx * dx + dy * dy), 1e-9);
      final double ux = dx / d;
      final double uy = dy / d;
      final double f = d - distances[i];
      j11 += ux * ux;
      j12 += ux * uy;
      j22 += uy * uy;
      g1 += ux * f;
      g2 += uy * f;
    }
    bool improved = false;
    for (int tries = 0; tries < 12; tries++) {
      final double a = j11 + lambda * math.max(j11, 1e-6);
      final double c = j22 + lambda * math.max(j22, 1e-6);
      final double jd = a * c - j12 * j12;
      if (jd.abs() < 1e-18) {
        lambda *= 10;
        continue;
      }
      final double sx = (c * g1 - j12 * g2) / jd;
      final double sy = (a * g2 - j12 * g1) / jd;
      final double nx = clampX(x - sx);
      final double ny = clampY(y - sy);
      final double next = cost(nx, ny);
      if (next <= current) {
        final double moved = (nx - x) * (nx - x) + (ny - y) * (ny - y);
        x = nx;
        y = ny;
        current = next;
        lambda = math.max(lambda / 10, 1e-9);
        improved = moved > 1e-18;
        break;
      }
      lambda *= 10;
    }
    if (!improved) break;
  }
  if (!x.isFinite || !y.isFinite) return null;
  double ss = 0;
  for (int i = 0; i < k; i++) {
    final double f = locDistance((x: x, y: y), aps[i]) - distances[i];
    ss += f * f;
  }
  return LocFix(position: (x: x, y: y), rmsResidualM: math.sqrt(ss / k));
}

/// Pairs of APs (by index) whose circles share no point: the APs are farther
/// apart than the two radii added up, or one circle sits inside the other.
List<(int, int)> locNonMeetingPairs(List<LocPoint> aps, List<double> r) {
  final List<(int, int)> out = <(int, int)>[];
  for (int i = 0; i < aps.length; i++) {
    for (int j = i + 1; j < aps.length; j++) {
      final double d = locDistance(aps[i], aps[j]);
      if (d > r[i] + r[j] + 1e-9 || d < (r[i] - r[j]).abs() - 1e-9) {
        out.add((i, j));
      }
    }
  }
  return out;
}

// ── Settings and the whole run ─────────────────────────────────────────────

/// Which ranging method.
enum LocMethod {
  signal('Signal strength'),
  ftm('FTM timing');

  const LocMethod(this.label);

  final String label;
}

/// Every input of one run.
class LocSettings {
  const LocSettings({
    this.aps = const <LocPoint>[
      (x: 3, y: 3),
      (x: 27, y: 3),
      (x: 27, y: 17),
      (x: 3, y: 17),
    ],
    this.device = kLocDefaultDevice,
    this.exponent = kLocDefaultExponent,
    this.modelExponent,
    this.sigmaDb = kLocDefaultSigmaDb,
    this.ftmErrorM = kLocDefaultFtmErrorM,
    this.blocked = const <bool>[],
    this.blockedBiasM = kLocDefaultBlockedBiasM,
    this.seed = 1,
  });

  final List<LocPoint> aps;
  final LocPoint device;

  /// The building's path-loss exponent (the truth).
  final double exponent;

  /// The exponent the device assumes when it inverts the model; null means
  /// it matches [exponent].
  final double? modelExponent;

  /// Shadowing, one standard deviation, dB (illustrative).
  final double sigmaDb;

  /// Timing ranging error, one standard deviation, meters.
  final double ftmErrorM;

  /// Per AP: is the direct path blocked? Missing entries mean not blocked.
  final List<bool> blocked;

  /// Extra distance a blocked AP reads, meters (illustrative).
  final double blockedBiasM;

  final int seed;

  double get assumedExponent => modelExponent ?? exponent;

  bool isBlocked(int ap) => ap < blocked.length && blocked[ap];

  LocSettings copyWith({
    List<LocPoint>? aps,
    LocPoint? device,
    double? exponent,
    double? sigmaDb,
    double? ftmErrorM,
    List<bool>? blocked,
    double? blockedBiasM,
    int? seed,
  }) => LocSettings(
    aps: aps ?? this.aps,
    device: device ?? this.device,
    exponent: exponent ?? this.exponent,
    modelExponent: modelExponent,
    sigmaDb: sigmaDb ?? this.sigmaDb,
    ftmErrorM: ftmErrorM ?? this.ftmErrorM,
    blocked: blocked ?? this.blocked,
    blockedBiasM: blockedBiasM ?? this.blockedBiasM,
    seed: seed ?? this.seed,
  );
}

/// One AP's measurement in one trial.
class LocApReading {
  const LocApReading({
    required this.trueDistanceM,
    required this.rssiDbm,
    required this.signalDistanceM,
    required this.ftmDistanceM,
  });

  final double trueDistanceM;

  /// The level the device reads, dBm (with shadowing).
  final double rssiDbm;

  /// The distance inverted from [rssiDbm].
  final double signalDistanceM;

  /// The distance from the round-trip time (error and any blocked bias).
  final double ftmDistanceM;

  double distanceFor(LocMethod m) =>
      m == LocMethod.signal ? signalDistanceM : ftmDistanceM;

  double errorFor(LocMethod m) => distanceFor(m) - trueDistanceM;
}

/// One method's result for the drawn trial plus the scatter.
class LocMethodResult {
  const LocMethodResult({
    required this.method,
    required this.fix,
    required this.scatter,
    required this.spreadRadiusM,
    required this.nonMeetingPairs,
    required this.device,
  });

  final LocMethod method;

  /// Trial 0's position fix (drawn on the floor); null when degenerate.
  final LocFix? fix;

  /// Every trial's estimated position (trial 0 first).
  final List<LocPoint> scatter;

  /// RMS distance of [scatter] from its average, meters.
  final double spreadRadiusM;

  /// Trial 0's circle pairs that share no point.
  final List<(int, int)> nonMeetingPairs;

  final LocPoint device;

  /// Trial 0's position error, meters.
  double? get positionErrorM =>
      fix == null ? null : locDistance(fix!.position, device);

  /// RMS distance of the scatter from the true position, meters.
  double get rmsErrorM {
    if (scatter.isEmpty) return 0;
    double s = 0;
    for (final LocPoint p in scatter) {
      final double d = locDistance(p, device);
      s += d * d;
    }
    return math.sqrt(s / scatter.length);
  }
}

/// A full run: every trial's readings and both methods' fixes.
class LocRun {
  const LocRun({
    required this.settings,
    required this.readings,
    required this.signal,
    required this.ftm,
  });

  final LocSettings settings;

  /// readings[trial][ap].
  final List<List<LocApReading>> readings;

  final LocMethodResult signal;
  final LocMethodResult ftm;

  /// Trial 0, the one drawn on the floor.
  List<LocApReading> get drawn => readings.first;

  LocMethodResult result(LocMethod m) => m == LocMethod.signal ? signal : ftm;
}

/// Standard normal draw (Box-Muller); 1 - nextDouble() keeps the log
/// argument above zero.
double _gaussian(math.Random r) {
  final double u1 = 1 - r.nextDouble();
  final double u2 = r.nextDouble();
  return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
}

/// Draws are seeded per (seed, trial, AP), so moving a slider scales the
/// same draws rather than rolling new ones, and moving the device keeps them.
math.Random _rng(int seed, int trial, int ap) =>
    math.Random((seed * 1000003 + trial * 7919 + ap * 104729) & 0x7fffffff);

/// One trial's readings for every AP.
List<LocApReading> locReadings(LocSettings s, int trial) {
  final List<LocApReading> out = <LocApReading>[];
  for (int i = 0; i < s.aps.length; i++) {
    final math.Random r = _rng(s.seed, trial, i);
    final double gShadow = _gaussian(r);
    final double gTiming = _gaussian(r);
    final double d = locDistance(s.aps[i], s.device);
    final double rssi = locRssiDbm(
      d,
      n: s.exponent,
      shadowDb: s.sigmaDb * gShadow,
    );
    final double ftm = math.max(
      0.0,
      d + s.ftmErrorM * gTiming + (s.isBlocked(i) ? s.blockedBiasM : 0),
    );
    out.add(
      LocApReading(
        trueDistanceM: d,
        rssiDbm: rssi,
        signalDistanceM: locDistanceFromRssi(rssi, n: s.assumedExponent),
        ftmDistanceM: ftm,
      ),
    );
  }
  return List<LocApReading>.unmodifiable(out);
}

LocMethodResult _methodResult(
  LocSettings s,
  List<List<LocApReading>> readings,
  LocMethod m,
) {
  LocFix? first;
  final List<LocPoint> scatter = <LocPoint>[];
  for (int t = 0; t < readings.length; t++) {
    final List<double> r = <double>[
      for (final LocApReading a in readings[t]) a.distanceFor(m),
    ];
    final LocFix? fix = trilaterate(s.aps, r);
    if (t == 0) first = fix;
    if (fix != null) scatter.add(fix.position);
  }
  double spread = 0;
  if (scatter.isNotEmpty) {
    double mx = 0, my = 0;
    for (final LocPoint p in scatter) {
      mx += p.x;
      my += p.y;
    }
    final LocPoint mean = (x: mx / scatter.length, y: my / scatter.length);
    double ss = 0;
    for (final LocPoint p in scatter) {
      final double d = locDistance(p, mean);
      ss += d * d;
    }
    spread = math.sqrt(ss / scatter.length);
  }
  return LocMethodResult(
    method: m,
    fix: first,
    scatter: List<LocPoint>.unmodifiable(scatter),
    spreadRadiusM: spread,
    nonMeetingPairs: locNonMeetingPairs(s.aps, <double>[
      for (final LocApReading a in readings.first) a.distanceFor(m),
    ]),
    device: s.device,
  );
}

/// Runs [trials] repeated measurements (trial 0 is the drawn one) and fixes
/// the position with both methods. Deterministic for given settings.
LocRun runLocation(LocSettings s, {int trials = kLocTrials}) {
  final List<List<LocApReading>> readings = <List<LocApReading>>[
    for (int t = 0; t < trials; t++) locReadings(s, t),
  ];
  return LocRun(
    settings: s,
    readings: List<List<LocApReading>>.unmodifiable(readings),
    signal: _methodResult(s, readings, LocMethod.signal),
    ftm: _methodResult(s, readings, LocMethod.ftm),
  );
}

// ── Predict, then reveal ────────────────────────────────────────────────────

/// The lesson's reading: "Your phone sees an AP at -70 dBm."
const double kLocLessonRssiDbm = -70;
