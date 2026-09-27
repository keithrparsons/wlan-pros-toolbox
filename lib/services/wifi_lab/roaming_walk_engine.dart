// Roaming Walk engine (Wi-Fi Classroom, 2026-09-25).
//
// Pure Dart, no Flutter imports. Built clean-room from the Wi-Fi Classroom wave 3
// research brief §3 (roaming) per myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/15-roaming-walk.md. Same config and seed, same walk.
//
// THE MODEL (a teaching model, and the screen says so):
//
//   Received signal from AP a at a point p:
//     RSSI = EIRP - PL(d) + S_a(s)
//     PL(d) = FSPL(1 m) + 10 n log10(d),   d = max(|p - AP|, 1 m)
//   FSPL(1 m) is the exact free-space loss at 1 m for the band's frequency.
//   S_a(s) is seeded shadow fading along the walked distance s: Gaussian with
//   standard deviation sigma, correlated over a few meters. It is a first-
//   order autoregressive sequence (each value leans on the one before with
//   correlation exp(-step / decorrelation distance)), so it is smooth along
//   the path and keeps exactly sigma at every point.
//
//   The client walks the path at walking speed and samples every 100 ms.
//
//   Roam rule (Apple's published model, brief §3): while the serving RSSI is
//   at or above the trigger the client stays. Below the trigger it scans, and
//   it roams to the strongest other AP only when that AP is at least delta
//   stronger than the serving one. A check that finds no such candidate costs
//   nothing here.
//
//   Roam gap = scan time + authentication time. The client has no AP for the
//   gap and joins the target when it ends.
//     scan: full scan = dwell x channel count; with 802.11k the client scans
//           only the neighbor channels, at most 6 (Apple uses the first six
//           Neighbor Report entries). Each other AP is taken to be on its own
//           channel, so the neighbor list has (AP count - 1) channels.
//     auth: frames x per-frame time, plus the authentication server's time
//           for full 802.1X. FT over the air (802.11r) is 4 frames. PMK
//           caching skips EAP, and only for an AP the client already joined
//           on this walk. FT wins when both are on.
//   Every timing default is illustrative. The only measurements in the brief
//   (Mishra et al. 2003; one FT capture) are shown as context, not used.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;
import 'dart:typed_data';

/// Sampling interval, seconds (spec: every 100 ms).
const double kRoamSampleSeconds = 0.1;

/// Walking speed, m/s. Illustrative.
const double kRoamWalkSpeedMps = 1.4;

/// A roam back to the previous AP within this many seconds is a ping-pong.
const double kPingPongWindowSeconds = 5;

/// The "time below" readout threshold, dBm (Apple's iPhone trigger).
const double kWeakSignalDbm = -70;

/// The common design-overlap target, dBm.
const double kDesignOverlapDbm = -67;

/// Apple uses the first six Neighbor Report entries to pick scan channels.
const int kMaxNeighborChannels = 6;

/// Floor size, meters.
const double kFloorWidthM = 60;
const double kFloorDepthM = 20;

/// AP count limits.
const int kMinAps = 2;
const int kMaxAps = 6;

/// Speed of light, m/s.
const double _c = 299792458.0;

double _log10(double x) => math.log(x) / math.ln10;

/// A point on the floor, meters from the top-left corner.
typedef FloorPoint = ({double x, double y});

/// The band sets FSPL(1 m).
enum RoamBand {
  b24('2.4 GHz', 2437),
  b5('5 GHz', 5500),
  b6('6 GHz', 6525);

  const RoamBand(this.label, this.freqMHz);

  final String label;

  /// Frequency used for FSPL(1 m).
  final double freqMHz;

  /// Exact free-space loss at 1 m: 20 log10(4 pi / lambda).
  double get fspl1mDb => 20 * _log10(4 * math.pi * freqMHz * 1e6 / _c);
}

/// Client roam behavior presets (brief §3).
///
/// The labels are generic device types (Keith, 2026-09-27: no product,
/// vendor or operating-system names anywhere a user sees). The published
/// values are Apple's, "Wi-Fi roaming support in Apple devices": [phoneTx]
/// and [phoneIdle] are its iPhone numbers, [laptop] its Mac numbers. The
/// screen credits that source as a citation (Keith, 2026-09-27: citations
/// stay) but never names the device.
enum ClientPreset {
  phoneTx('Phone, transmitting', -70, 8, published: true),
  phoneIdle('Phone, idle', -70, 12, published: true),
  laptop('Laptop', -75, 12, published: true),
  sticky('Illustrative sticky', -85, 12, published: false),
  jumpy('Illustrative jumpy', -65, 2, published: false);

  const ClientPreset(
    this.label,
    this.triggerDbm,
    this.deltaDb, {
    required this.published,
  });

  final String label;
  final double triggerDbm;
  final double deltaDb;

  /// True for Apple's published values; false for the illustrative two
  /// (Android and Windows publish no numbers).
  final bool published;

  /// The preset these values match, or null (custom).
  static ClientPreset? matching(double triggerDbm, double deltaDb) {
    for (final ClientPreset p in values) {
      if (p.triggerDbm == triggerDbm && p.deltaDb == deltaDb) return p;
    }
    return null;
  }
}

/// How the client authenticates to the new AP.
enum AuthMethod {
  full8021x('Full 802.1X'),
  pmkCaching('PMK caching'),
  ftOverTheAir('FT over the air (802.11r)');

  const AuthMethod(this.label);

  final String label;
}

/// Frame sequence for [method] (brief §3). [eapMethodFrames] is the number
/// of frames in the EAP method exchange, which depends on the EAP type.
List<String> authFrames(AuthMethod method, {int eapMethodFrames = 6}) {
  switch (method) {
    case AuthMethod.full8021x:
      return <String>[
        'Authentication (Open), client',
        'Authentication (Open), AP',
        'Reassociation Request',
        'Reassociation Response',
        'EAP-Request/Identity',
        'EAP-Response/Identity',
        for (int i = 1; i <= eapMethodFrames; i++)
          'EAP method exchange $i of $eapMethodFrames',
        'EAP-Success',
        'EAPOL-Key 1 of 4',
        'EAPOL-Key 2 of 4',
        'EAPOL-Key 3 of 4',
        'EAPOL-Key 4 of 4',
      ];
    case AuthMethod.pmkCaching:
      return const <String>[
        'Authentication (Open), client',
        'Authentication (Open), AP',
        'Reassociation Request (PMKID)',
        'Reassociation Response',
        'EAPOL-Key 1 of 4',
        'EAPOL-Key 2 of 4',
        'EAPOL-Key 3 of 4',
        'EAPOL-Key 4 of 4',
      ];
    case AuthMethod.ftOverTheAir:
      return const <String>[
        'FT Authentication Request (SNonce)',
        'FT Authentication Response (ANonce)',
        'Reassociation Request (MIC)',
        'Reassociation Response (GTK)',
      ];
  }
}

/// Illustrative roam-timing parameters. None of these is a measurement.
class RoamTiming {
  const RoamTiming({
    this.dwellMs = 10,
    this.channelCount = 25,
    this.frameMs = 3,
    this.serverMs = 50,
    this.eapMethodFrames = 6,
  });

  /// Time spent listening on each scanned channel.
  final double dwellMs;

  /// Channels in a full scan.
  final int channelCount;

  /// Time per authentication frame exchange step.
  final double frameMs;

  /// Extra time the authentication server takes, full 802.1X only.
  final double serverMs;

  /// Frames in the EAP method exchange.
  final int eapMethodFrames;

  RoamTiming copyWith({
    double? dwellMs,
    int? channelCount,
    double? frameMs,
    double? serverMs,
    int? eapMethodFrames,
  }) => RoamTiming(
    dwellMs: dwellMs ?? this.dwellMs,
    channelCount: channelCount ?? this.channelCount,
    frameMs: frameMs ?? this.frameMs,
    serverMs: serverMs ?? this.serverMs,
    eapMethodFrames: eapMethodFrames ?? this.eapMethodFrames,
  );

  @override
  bool operator ==(Object other) =>
      other is RoamTiming &&
      other.dwellMs == dwellMs &&
      other.channelCount == channelCount &&
      other.frameMs == frameMs &&
      other.serverMs == serverMs &&
      other.eapMethodFrames == eapMethodFrames;

  @override
  int get hashCode =>
      Object.hash(dwellMs, channelCount, frameMs, serverMs, eapMethodFrames);
}

/// The cost of one roam.
class RoamCost {
  const RoamCost({
    required this.scanChannels,
    required this.scanMs,
    required this.method,
    required this.frames,
    required this.authMs,
  });

  final int scanChannels;
  final double scanMs;
  final AuthMethod method;
  final int frames;
  final double authMs;

  double get totalMs => scanMs + authMs;
}

/// Channels the client scans: all of them, or with 802.11k the neighbor
/// channels (one per other AP), at most six and never more than a full scan.
int scanChannels({
  required bool use11k,
  required int apCount,
  required int channelCount,
}) {
  final int full = math.max(1, channelCount);
  if (!use11k) return full;
  final int neighbors = math.max(1, apCount - 1);
  return math.min(full, math.min(kMaxNeighborChannels, neighbors));
}

/// Scan time in ms.
double scanTimeMs({
  required bool use11k,
  required int apCount,
  required RoamTiming timing,
}) =>
    timing.dwellMs *
    scanChannels(
      use11k: use11k,
      apCount: apCount,
      channelCount: timing.channelCount,
    );

/// Authentication time in ms for [method].
double authTimeMs(AuthMethod method, RoamTiming timing) {
  final int frames = authFrames(
    method,
    eapMethodFrames: timing.eapMethodFrames,
  ).length;
  return frames * timing.frameMs +
      (method == AuthMethod.full8021x ? timing.serverMs : 0);
}

/// Everything the walk depends on.
class RoamWalkConfig {
  RoamWalkConfig({
    List<FloorPoint>? aps,
    List<FloorPoint>? path,
    this.band = RoamBand.b5,
    this.eirpDbm = 14,
    this.pathLossExponent = 3.0,
    this.shadowSigmaDb = 2,
    this.decorrelationM = 5,
    this.seed = 1,
    this.triggerDbm = -70,
    this.deltaDb = 8,
    this.use11k = false,
    this.usePmkCaching = false,
    this.useFt = false,
    this.timing = const RoamTiming(),
    this.walkSpeedMps = kRoamWalkSpeedMps,
  }) : aps = List<FloorPoint>.unmodifiable(aps ?? defaultApLayout(3)),
       path = List<FloorPoint>.unmodifiable(path ?? kCorridorPath) {
    assert(this.aps.length >= kMinAps && this.aps.length <= kMaxAps);
    assert(this.path.length >= 2);
  }

  final List<FloorPoint> aps;
  final List<FloorPoint> path;
  final RoamBand band;
  final double eirpDbm;
  final double pathLossExponent;
  final double shadowSigmaDb;
  final double decorrelationM;
  final int seed;
  final double triggerDbm;
  final double deltaDb;
  final bool use11k;
  final bool usePmkCaching;
  final bool useFt;
  final RoamTiming timing;
  final double walkSpeedMps;

  RoamWalkConfig copyWith({
    List<FloorPoint>? aps,
    List<FloorPoint>? path,
    RoamBand? band,
    double? eirpDbm,
    double? pathLossExponent,
    double? shadowSigmaDb,
    int? seed,
    double? triggerDbm,
    double? deltaDb,
    bool? use11k,
    bool? usePmkCaching,
    bool? useFt,
    RoamTiming? timing,
  }) => RoamWalkConfig(
    aps: aps ?? this.aps,
    path: path ?? this.path,
    band: band ?? this.band,
    eirpDbm: eirpDbm ?? this.eirpDbm,
    pathLossExponent: pathLossExponent ?? this.pathLossExponent,
    shadowSigmaDb: shadowSigmaDb ?? this.shadowSigmaDb,
    decorrelationM: decorrelationM,
    seed: seed ?? this.seed,
    triggerDbm: triggerDbm ?? this.triggerDbm,
    deltaDb: deltaDb ?? this.deltaDb,
    use11k: use11k ?? this.use11k,
    usePmkCaching: usePmkCaching ?? this.usePmkCaching,
    useFt: useFt ?? this.useFt,
    timing: timing ?? this.timing,
    walkSpeedMps: walkSpeedMps,
  );

  /// Mean RSSI (no shadowing) from AP [a] at [p].
  double meanRssiDbm(int a, FloorPoint p) =>
      meanRssiAtDistance(_distance(aps[a], p));

  /// Mean RSSI at [distanceM] from any AP.
  double meanRssiAtDistance(double distanceM) {
    final double d = math.max(distanceM, 1.0);
    return eirpDbm - band.fspl1mDb - 10 * pathLossExponent * _log10(d);
  }

  /// Distance at which the mean RSSI equals [levelDbm]: the radius of that
  /// contour. At least 1 m is not enforced here; the painter clips.
  double contourRadiusM(double levelDbm) => math
      .pow(10, (eirpDbm - band.fspl1mDb - levelDbm) / (10 * pathLossExponent))
      .toDouble();

  /// The authentication method a roam to an AP uses.
  AuthMethod authMethodFor({required bool joinedBefore}) {
    if (useFt) return AuthMethod.ftOverTheAir;
    if (usePmkCaching && joinedBefore) return AuthMethod.pmkCaching;
    return AuthMethod.full8021x;
  }

  /// Cost of one roam with [method].
  RoamCost costFor(AuthMethod method) {
    final int ch = scanChannels(
      use11k: use11k,
      apCount: aps.length,
      channelCount: timing.channelCount,
    );
    return RoamCost(
      scanChannels: ch,
      scanMs: ch * timing.dwellMs,
      method: method,
      frames: authFrames(
        method,
        eapMethodFrames: timing.eapMethodFrames,
      ).length,
      authMs: authTimeMs(method, timing),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RoamWalkConfig &&
      _listEq(other.aps, aps) &&
      _listEq(other.path, path) &&
      other.band == band &&
      other.eirpDbm == eirpDbm &&
      other.pathLossExponent == pathLossExponent &&
      other.shadowSigmaDb == shadowSigmaDb &&
      other.decorrelationM == decorrelationM &&
      other.seed == seed &&
      other.triggerDbm == triggerDbm &&
      other.deltaDb == deltaDb &&
      other.use11k == use11k &&
      other.usePmkCaching == usePmkCaching &&
      other.useFt == useFt &&
      other.timing == timing &&
      other.walkSpeedMps == walkSpeedMps;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(aps),
    Object.hashAll(path),
    band,
    eirpDbm,
    pathLossExponent,
    shadowSigmaDb,
    decorrelationM,
    seed,
    triggerDbm,
    deltaDb,
    use11k,
    usePmkCaching,
    useFt,
    timing,
    walkSpeedMps,
  );
}

bool _listEq(List<FloorPoint> a, List<FloorPoint> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

double _distance(FloorPoint a, FloorPoint b) {
  final double dx = a.x - b.x;
  final double dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// [count] APs evenly spaced along the middle of the floor.
List<FloorPoint> defaultApLayout(int count) => <FloorPoint>[
  for (int i = 0; i < count; i++)
    (x: kFloorWidthM * (i + 0.5) / count, y: kFloorDepthM / 2),
];

/// Built-in paths.
const List<FloorPoint> kCorridorPath = <FloorPoint>[
  (x: 1, y: 16),
  (x: 59, y: 16),
];
const List<FloorPoint> kMiddlePath = <FloorPoint>[
  (x: 1, y: 10),
  (x: 59, y: 10),
];
const List<FloorPoint> kDiagonalPath = <FloorPoint>[
  (x: 1, y: 19),
  (x: 59, y: 1),
];

/// Straight across the floor at x = 20 m: midway between AP 1 and AP 2 in
/// the default three-AP layout, so the two are equally strong on average.
const List<FloorPoint> kAcrossPath = <FloorPoint>[
  (x: 20, y: 1),
  (x: 20, y: 19),
];
const List<FloorPoint> kThereAndBackPath = <FloorPoint>[
  (x: 1, y: 16),
  (x: 59, y: 16),
  (x: 59, y: 4),
  (x: 1, y: 4),
];

/// The path choices the screen offers. [custom] is a drawn path.
enum WalkPathPreset {
  corridor('Along the corridor', kCorridorPath),
  middle('Under the APs', kMiddlePath),
  diagonal('Corner to corner', kDiagonalPath),
  across('Across at 20 m', kAcrossPath),
  loop('Down and back', kThereAndBackPath),
  custom('Drawn by you', null);

  const WalkPathPreset(this.label, this.points);

  final String label;
  final List<FloorPoint>? points;

  static WalkPathPreset matching(List<FloorPoint> path) {
    for (final WalkPathPreset p in values) {
      final List<FloorPoint>? pts = p.points;
      if (pts != null && _listEq(pts, path)) return p;
    }
    return custom;
  }
}

/// Total polyline length, meters.
double pathLengthM(List<FloorPoint> path) {
  double s = 0;
  for (int i = 1; i < path.length; i++) {
    s += _distance(path[i - 1], path[i]);
  }
  return s;
}

/// The point [s] meters along [path] (clamped to its ends).
FloorPoint pointAlong(List<FloorPoint> path, double s) {
  if (s <= 0) return path.first;
  double left = s;
  for (int i = 1; i < path.length; i++) {
    final double seg = _distance(path[i - 1], path[i]);
    if (left <= seg && seg > 0) {
      final double t = left / seg;
      return (
        x: path[i - 1].x + (path[i].x - path[i - 1].x) * t,
        y: path[i - 1].y + (path[i].y - path[i - 1].y) * t,
      );
    }
    left -= seg;
  }
  return path.last;
}

/// One roam.
class RoamEvent {
  const RoamEvent({
    required this.sample,
    required this.timeS,
    required this.fromAp,
    required this.toAp,
    required this.fromRssiDbm,
    required this.toRssiDbm,
    required this.cost,
    required this.pingPong,
  });

  /// Sample index at which the client decided to roam.
  final int sample;
  final double timeS;
  final int fromAp;
  final int toAp;
  final double fromRssiDbm;
  final double toRssiDbm;
  final RoamCost cost;

  /// A roam back to the AP the client left within the last 5 s.
  final bool pingPong;

  double get gapMs => cost.totalMs;
}

/// Running totals up to a time.
class RoamTotals {
  const RoamTotals({
    required this.roams,
    required this.pingPongs,
    required this.secondsBelowWeak,
    required this.gapMs,
  });

  final int roams;
  final int pingPongs;

  /// Seconds associated with RSSI below -70 dBm.
  final double secondsBelowWeak;

  /// Total time spent between APs, ms.
  final double gapMs;
}

/// The whole walk, computed once per config.
class RoamWalkResult {
  RoamWalkResult._({
    required this.config,
    required this.positions,
    required this.rssi,
    required this.serving,
    required this.events,
    required this.belowWeakPrefix,
  });

  final RoamWalkConfig config;

  /// Client position at every sample.
  final List<FloorPoint> positions;

  /// rssi[a][k]: RSSI from AP a at sample k, dBm (with shadowing).
  final List<Float64List> rssi;

  /// Serving AP at each sample, or -1 while between APs.
  final Int8List serving;

  final List<RoamEvent> events;

  /// belowWeakPrefix[k]: seconds associated below -70 dBm before sample k.
  final List<double> belowWeakPrefix;

  int get sampleCount => positions.length;

  /// Walk duration, seconds.
  double get durationS => (sampleCount - 1) * kRoamSampleSeconds;

  double timeOf(int k) => k * kRoamSampleSeconds;

  /// The serving AP at sample [k], or null between APs.
  int? servingAt(int k) {
    final int s = serving[k.clamp(0, sampleCount - 1)];
    return s < 0 ? null : s;
  }

  /// Serving RSSI at [k], or null between APs.
  double? servingRssiAt(int k) {
    final int? s = servingAt(k);
    return s == null ? null : rssi[s][k.clamp(0, sampleCount - 1)];
  }

  /// A roam in progress at [k] (the client is between APs), or null.
  RoamEvent? gapAt(int k) {
    final double t = timeOf(k);
    for (final RoamEvent e in events) {
      if (e.timeS < t && t < e.timeS + e.gapMs / 1000) return e;
      if (e.timeS > t) break;
    }
    return null;
  }

  /// Totals from the start of the walk up to sample [k] (inclusive).
  RoamTotals totalsAt(int k) {
    final int kk = k.clamp(0, sampleCount - 1);
    final double t = timeOf(kk);
    int roams = 0;
    int pp = 0;
    double gap = 0;
    for (final RoamEvent e in events) {
      if (e.sample > kk) break;
      roams++;
      if (e.pingPong) pp++;
      gap += math.min(e.gapMs, (t - e.timeS) * 1000);
    }
    return RoamTotals(
      roams: roams,
      pingPongs: pp,
      secondsBelowWeak: belowWeakPrefix[kk],
      gapMs: gap,
    );
  }

  /// Totals for the whole walk.
  RoamTotals get totals => totalsAt(sampleCount - 1);
}

/// Runs the walk. Deterministic for a given [config] (including its seed).
RoamWalkResult simulateRoamWalk(RoamWalkConfig config) {
  final double length = pathLengthM(config.path);
  final double step = config.walkSpeedMps * kRoamSampleSeconds;
  final int n = math.max(2, (length / step).floor() + 1);
  final int apCount = config.aps.length;

  final List<FloorPoint> positions = <FloorPoint>[
    for (int k = 0; k < n; k++)
      pointAlong(config.path, math.min(k * step, length)),
  ];

  // Shadow fading: one correlated sequence per AP along the walk.
  final math.Random rng = math.Random(config.seed);
  final double rho = math.exp(-step / math.max(config.decorrelationM, 1e-6));
  final double innov = math.sqrt(math.max(0, 1 - rho * rho));
  final List<Float64List> rssi = <Float64List>[];
  for (int a = 0; a < apCount; a++) {
    final Float64List row = Float64List(n);
    double x = _gaussian(rng);
    for (int k = 0; k < n; k++) {
      if (k > 0) x = rho * x + innov * _gaussian(rng);
      row[k] = config.meanRssiDbm(a, positions[k]) + config.shadowSigmaDb * x;
    }
    rssi.add(row);
  }

  final Int8List serving = Int8List(n);
  final List<RoamEvent> events = <RoamEvent>[];
  final List<double> below = List<double>.filled(n, 0);

  // Initial association: strongest AP at the start (lowest index on a tie).
  int current = 0;
  for (int a = 1; a < apCount; a++) {
    if (rssi[a][0] > rssi[current][0]) current = a;
  }
  final Set<int> joined = <int>{current};
  int? target;
  double gapEndS = -1;

  for (int k = 0; k < n; k++) {
    final double t = k * kRoamSampleSeconds;
    if (target != null) {
      if (t + 1e-9 >= gapEndS) {
        current = target;
        target = null;
      } else {
        serving[k] = -1;
        if (k + 1 < n) below[k + 1] = below[k];
        continue;
      }
    }
    serving[k] = current;
    final double cur = rssi[current][k];
    if (k + 1 < n) {
      below[k + 1] = below[k] + (cur < kWeakSignalDbm ? kRoamSampleSeconds : 0);
    }
    if (cur >= config.triggerDbm) continue;

    // Below the trigger: scan and look for a candidate delta stronger.
    int? best;
    for (int a = 0; a < apCount; a++) {
      if (a == current) continue;
      if (best == null || rssi[a][k] > rssi[best][k]) best = a;
    }
    if (best == null || rssi[best][k] < cur + config.deltaDb) continue;

    final AuthMethod method = config.authMethodFor(
      joinedBefore: joined.contains(best),
    );
    final RoamCost cost = config.costFor(method);
    final RoamEvent? prev = events.isEmpty ? null : events.last;
    final bool pingPong =
        prev != null &&
        prev.fromAp == best &&
        prev.toAp == current &&
        t - prev.timeS <= kPingPongWindowSeconds + 1e-9;
    events.add(
      RoamEvent(
        sample: k,
        timeS: t,
        fromAp: current,
        toAp: best,
        fromRssiDbm: cur,
        toRssiDbm: rssi[best][k],
        cost: cost,
        pingPong: pingPong,
      ),
    );
    joined.add(best);
    target = best;
    gapEndS = t + cost.totalMs / 1000;
  }

  return RoamWalkResult._(
    config: config,
    positions: List<FloorPoint>.unmodifiable(positions),
    rssi: List<Float64List>.unmodifiable(rssi),
    serving: serving,
    events: List<RoamEvent>.unmodifiable(events),
    belowWeakPrefix: below,
  );
}

/// Standard normal draw (Box-Muller).
double _gaussian(math.Random rng) {
  double u = 0;
  while (u <= 1e-12) {
    u = rng.nextDouble();
  }
  final double v = rng.nextDouble();
  return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
}
