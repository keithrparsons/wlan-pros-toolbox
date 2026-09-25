// Medium Access Simulator engine (Wi-Fi Lab, 2026-09-25).
//
// A deterministic, pure-Dart model of 802.11 contention: DCF and EDCA channel
// access (IEEE 802.11 clause 10) over legacy OFDM timing (clause 17). Built
// clean-room from the standard's rules as written in the Wi-Fi Lab spec
// (myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 02-medium-access-simulator.md). No Flutter imports: the screen drives this
// with a Ticker and renders it with a CustomPainter, and the tests drive it
// directly.
//
// TIME. The engine keeps exact integer microseconds internally, because SIFS
// (16 us), frame durations (244 us) and EIFS (94 us) are not multiples of the
// 9 us slot. The public clock only moves in whole slots: [stepSlot] advances
// 9 us, [advanceSlots] advances n slots. Each slot is processed as nine 1 us
// ticks, so every boundary lands on its exact microsecond.
//
// MODEL (the rules the spec lists, in the order they fire):
//  1. A station with a frame waits for its own view of the medium to be idle
//     for AIFS (DIFS in legacy mode; EIFS-based after a frame it could not
//     decode), then counts its backoff down one slot per idle slot boundary.
//  2. Backoff is uniform in [0, CW], drawn when a frame reaches the head of the
//     queue or after a failed attempt.
//  3. Busy medium (physical carrier sense or NAV) FREEZES the count. After the
//     medium is idle for AIFS again the count resumes where it stopped.
//  4. At zero the station transmits (a data frame, or an RTS when RTS/CTS is
//     on).
//  5. A frame the AP receives clean is answered after SIFS (ACK for data, CTS
//     for RTS). ACK received: CW resets to CWmin.
//  6. No response: CW = min(2(CW + 1) - 1, CWmax) and a fresh backoff. After
//     [MediumAccessConfig.retryLimit] failed attempts the frame is dropped and
//     CW resets.
//  7. A station that heard a frame it could not decode waits
//     EIFS - DIFS + AIFS before resuming (EIFS = SIFS + DIFS + ACK at 6 Mbps).
//
// A frame is corrupt at a receiver when any other audible transmission
// overlaps it at that receiver, or when the receiver was itself transmitting
// (half duplex). The AP hears every station; every station hears the AP. With
// the hidden-node toggle on, stations split into two groups by index parity
// (A, C, E ... and B, D, F ...) that cannot hear each other.

import 'dart:math' as math;

// ── Timing (clause 17 OFDM, 5 GHz) ─────────────────────────────────────────

/// Legacy OFDM (802.11a/g, 5 GHz) timing constants and the airtime formula.
class OfdmTiming {
  OfdmTiming._();

  /// aSlotTime.
  static const int slotUs = 9;

  /// aSIFSTime.
  static const int sifsUs = 16;

  /// DIFS = SIFS + 2 x slot = 34 us.
  static const int difsUs = sifsUs + 2 * slotUs;

  /// PLCP preamble + SIGNAL field.
  static const int preambleUs = 20;

  /// One OFDM symbol.
  static const int symbolUs = 4;

  /// SERVICE field bits added ahead of the PSDU.
  static const int serviceBits = 16;

  /// Tail bits added after the PSDU.
  static const int tailBits = 6;

  /// ACK and CTS are 14 bytes; RTS is 20 bytes.
  static const int ackBytes = 14;
  static const int ctsBytes = 14;
  static const int rtsBytes = 20;

  /// Control responses (ACK, CTS) and RTS go out at this basic rate.
  static const int controlRateMbps = 24;

  /// The lowest mandatory basic rate, used by the EIFS definition.
  static const int lowestBasicRateMbps = 6;

  /// The legacy OFDM data rates, Mbps.
  static const List<int> phyRatesMbps = <int>[6, 9, 12, 18, 24, 36, 48, 54];

  /// AIFS[AC] = SIFS + AIFSN x slot.
  static int aifsUs(int aifsn) => sifsUs + aifsn * slotUs;

  /// Data bits per OFDM symbol: rate (Mbps) x 4 us.
  static int dataBitsPerSymbol(int rateMbps) => rateMbps * 4;

  /// Frame duration = 20 + 4 x ceil((16 + 8 x bytes + 6) / N_DBPS) us.
  static int frameDurationUs(int bytes, int rateMbps) {
    if (bytes < 0) throw ArgumentError.value(bytes, 'bytes', 'negative');
    if (rateMbps <= 0) {
      throw ArgumentError.value(rateMbps, 'rateMbps', 'must be positive');
    }
    final int ndbps = dataBitsPerSymbol(rateMbps);
    final int bits = serviceBits + 8 * bytes + tailBits;
    final int symbols = (bits + ndbps - 1) ~/ ndbps;
    return preambleUs + symbolUs * symbols;
  }

  /// ACK airtime at the control rate: 28 us.
  static int get ackUs => frameDurationUs(ackBytes, controlRateMbps);

  /// CTS airtime at the control rate: 28 us.
  static int get ctsUs => frameDurationUs(ctsBytes, controlRateMbps);

  /// RTS airtime at the control rate: 28 us.
  static int get rtsUs => frameDurationUs(rtsBytes, controlRateMbps);

  /// EIFS = SIFS + DIFS + ACK at the lowest basic rate = 16 + 34 + 44 = 94 us.
  static int get eifsUs =>
      sifsUs + difsUs + frameDurationUs(ackBytes, lowestBasicRateMbps);
}

// ── Access parameters ──────────────────────────────────────────────────────

/// DCF (everyone the same) or EDCA (per access category).
enum AccessMode { dcf, edca }

/// One set of contention parameters.
class EdcaParams {
  const EdcaParams({
    required this.aifsn,
    required this.cwMin,
    required this.cwMax,
  });

  final int aifsn;
  final int cwMin;
  final int cwMax;

  /// AIFS for these parameters, us.
  int get aifsUs => OfdmTiming.aifsUs(aifsn);

  @override
  bool operator ==(Object other) =>
      other is EdcaParams &&
      other.aifsn == aifsn &&
      other.cwMin == cwMin &&
      other.cwMax == cwMax;

  @override
  int get hashCode => Object.hash(aifsn, cwMin, cwMax);
}

/// Legacy DCF: DIFS (AIFSN 2), CWmin 15, CWmax 1023 for every station.
const EdcaParams kLegacyDcfParams = EdcaParams(
  aifsn: 2,
  cwMin: 15,
  cwMax: 1023,
);

/// The four EDCA access categories, with the 802.11 default non-AP station
/// parameters (aCWmin 15, aCWmax 1023).
enum AccessCategory {
  voice('VO', 'Voice', EdcaParams(aifsn: 2, cwMin: 3, cwMax: 7)),
  video('VI', 'Video', EdcaParams(aifsn: 2, cwMin: 7, cwMax: 15)),
  bestEffort('BE', 'Best effort', EdcaParams(aifsn: 3, cwMin: 15, cwMax: 1023)),
  background('BK', 'Background', EdcaParams(aifsn: 7, cwMin: 15, cwMax: 1023));

  const AccessCategory(this.shortLabel, this.label, this.params);

  final String shortLabel;
  final String label;
  final EdcaParams params;
}

/// The CW step after a failed attempt: min(2(CW + 1) - 1, CWmax).
/// 15 -> 31 -> 63 -> ... -> 1023, and 3 -> 7 -> 7 for voice.
int nextContentionWindow(int cw, int cwMax) =>
    math.min(2 * (cw + 1) - 1, cwMax);

// ── Configuration ──────────────────────────────────────────────────────────

/// One station's traffic: its access category and offered load.
class StationConfig {
  const StationConfig({
    this.accessCategory = AccessCategory.bestEffort,
    this.framesPerSecond,
  });

  final AccessCategory accessCategory;

  /// Poisson arrival rate, frames per second. Null means the station always
  /// has a frame waiting (saturated).
  final double? framesPerSecond;

  bool get saturated => framesPerSecond == null;

  StationConfig copyWith({
    AccessCategory? accessCategory,
    double? Function()? framesPerSecond,
  }) => StationConfig(
    accessCategory: accessCategory ?? this.accessCategory,
    framesPerSecond: framesPerSecond == null
        ? this.framesPerSecond
        : framesPerSecond(),
  );
}

/// Everything that defines one simulation run.
class MediumAccessConfig {
  const MediumAccessConfig({
    required this.stations,
    this.mode = AccessMode.edca,
    this.hiddenNode = false,
    this.rtsCts = false,
    this.frameBytes = 1500,
    this.phyRateMbps = 54,
    this.seed = 1,
    this.retryLimit = 7,
    this.queueLimit = 64,
    this.paramsOverride,
  });

  /// Smallest and largest station counts the simulator accepts.
  static const int minStations = 1;
  static const int maxStations = 10;

  final List<StationConfig> stations;
  final AccessMode mode;

  /// Stations split into two groups by index parity that cannot hear each
  /// other. Every station still reaches the AP.
  final bool hiddenNode;

  /// Each access starts with RTS -> SIFS -> CTS -> SIFS -> data -> SIFS -> ACK.
  final bool rtsCts;

  /// Data frame size in bytes (the byte count in the airtime formula).
  final int frameBytes;

  /// Data PHY rate, Mbps (one of [OfdmTiming.phyRatesMbps]).
  final int phyRateMbps;

  /// Seed for every random draw (backoff and arrivals).
  final int seed;

  /// Failed attempts after which a frame is dropped.
  final int retryLimit;

  /// Frames a non-saturated station can hold; arrivals beyond it are lost.
  final int queueLimit;

  /// Test and teaching hook: when set, every station uses these parameters
  /// instead of the DCF or EDCA table.
  final EdcaParams? paramsOverride;

  /// The contention parameters station [index] runs with.
  EdcaParams paramsFor(int index) {
    final EdcaParams? o = paramsOverride;
    if (o != null) return o;
    if (mode == AccessMode.dcf) return kLegacyDcfParams;
    return stations[index].accessCategory.params;
  }

  /// Whether stations [a] and [b] hear each other.
  bool stationsHear(int a, int b) => !hiddenNode || a.isEven == b.isEven;

  /// Data airtime, us.
  int get dataUs => OfdmTiming.frameDurationUs(frameBytes, phyRateMbps);
}

/// Replaces the uniform [0, CW] draw. Receives the station index and the CW
/// the draw is made from. Tests use it to script exact backoffs.
typedef BackoffDraw = int Function(int station, int cw);

// ── Observable records ─────────────────────────────────────────────────────

/// The kinds of frame on the air.
enum FrameKind { data, rts, cts, ack }

/// What a station lane shows at a given microsecond.
enum LaneActivity {
  /// Waiting out AIFS (or DIFS) on an idle medium.
  aifs,

  /// Waiting out the EIFS-based interval after an undecodable frame.
  eifs,

  /// Counting down; [LaneSegment.count] is the current backoff.
  backoff,

  /// Physical carrier sense says busy; the count is held.
  frozen,

  /// NAV says busy; the count is held.
  nav,

  /// This station is transmitting ([LaneSegment.frame]).
  transmit,

  /// Waiting for the CTS or ACK its last frame asked for.
  awaitResponse,
}

/// One contiguous run of a single activity on one station lane.
class LaneSegment {
  LaneSegment({
    required this.lane,
    required this.activity,
    required this.startUs,
    required this.endUs,
    this.count,
    this.frame,
  });

  final int lane;
  final LaneActivity activity;
  final int startUs;

  /// Exclusive end. Grows while the segment is open.
  int endUs;

  /// Backoff count for [LaneActivity.backoff], [LaneActivity.frozen] and
  /// [LaneActivity.nav].
  final int? count;

  /// Frame kind for [LaneActivity.transmit].
  final FrameKind? frame;

  /// For a transmit segment: true once the exchange it started failed.
  bool failed = false;

  int get durationUs => endUs - startUs;
}

/// One frame as the AP (the medium lane) sees it.
class AirFrame {
  AirFrame({
    required this.source,
    required this.kind,
    required this.startUs,
    required this.endUs,
    this.target,
  });

  /// Station index, or [MediumAccessEngine.apIndex] for the AP.
  final int source;
  final FrameKind kind;
  final int startUs;
  final int endUs;

  /// For AP frames, the station they answer.
  final int? target;

  /// True once another transmission overlapped this one at the AP, or the AP
  /// was transmitting during it. Only meaningful for station frames.
  bool corruptedAtAp = false;

  /// True for an AP frame the target could not decode.
  bool corruptedAtTarget = false;

  bool get fromAp => source == MediumAccessEngine.apIndex;
}

/// Where a station is in its access cycle.
enum StationPhase { noFrame, contending, transmitting, awaitResponse }

/// Read-only view of one station.
class StationSnapshot {
  const StationSnapshot({
    required this.index,
    required this.params,
    required this.accessCategory,
    required this.phase,
    required this.cw,
    required this.backoff,
    required this.queued,
    required this.attempts,
    required this.failedAttempts,
    required this.delivered,
    required this.dropped,
    required this.hiddenGroup,
  });

  final int index;
  final EdcaParams params;
  final AccessCategory accessCategory;
  final StationPhase phase;
  final int cw;

  /// Current backoff count, or null when no backoff is drawn.
  final int? backoff;

  /// Frames waiting, including the one in service. -1 for saturated.
  final int queued;
  final int attempts;
  final int failedAttempts;
  final int delivered;
  final int dropped;

  /// 0 or 1 when hidden-node is on, otherwise null.
  final int? hiddenGroup;

  String get letter => stationLetter(index);
}

/// A, B, C ... for station 0, 1, 2 ...
String stationLetter(int index) => String.fromCharCode(65 + index);

/// Running totals for one access category.
class AccessDelayStat {
  const AccessDelayStat({required this.frames, required this.totalUs});

  final int frames;
  final int totalUs;

  /// Mean access delay, us, or null before any delivery.
  double? get meanUs => frames == 0 ? null : totalUs / frames;
}

/// Aggregate statistics since the run started.
class MediumAccessStats {
  const MediumAccessStats({
    required this.elapsedUs,
    required this.busyUs,
    required this.deliveredBits,
    required this.delivered,
    required this.dropped,
    required this.attempts,
    required this.failedAttempts,
    required this.dataFrames,
    required this.dataFramesCorrupted,
    required this.accessDelay,
  });

  final int elapsedUs;

  /// Microseconds with at least one transmission on the air (AP view).
  final int busyUs;
  final int deliveredBits;
  final int delivered;
  final int dropped;

  /// Channel accesses won (each data or RTS a backoff reached zero for).
  final int attempts;

  /// Accesses whose exchange got no CTS or no ACK.
  final int failedAttempts;

  /// Data frames sent.
  final int dataFrames;

  /// Data frames that arrived corrupt at the AP.
  final int dataFramesCorrupted;

  /// Head-of-line to ACK, keyed by access category (DCF runs report under the
  /// station's configured category too; the screen groups them as one).
  final Map<AccessCategory, AccessDelayStat> accessDelay;

  /// Delivered payload, Mbps (bits per us).
  double get throughputMbps => elapsedUs == 0 ? 0 : deliveredBits / elapsedUs;

  /// Percent of elapsed time the medium was busy.
  double get utilizationPercent =>
      elapsedUs == 0 ? 0 : 100 * busyUs / elapsedUs;

  /// Percent of completed accesses that failed.
  double get collisionPercent =>
      attempts == 0 ? 0 : 100 * failedAttempts / attempts;
}

// ── Internal state ─────────────────────────────────────────────────────────

class _Station {
  _Station(this.index, this.config, this.params, this.hiddenGroup)
    : cw = params.cwMin;

  final int index;
  final StationConfig config;
  final EdcaParams params;
  final int? hiddenGroup;

  StationPhase phase = StationPhase.noFrame;
  int cw;
  int backoff = -1;
  int failures = 0;

  /// Arrival times of waiting frames (non-saturated only).
  final List<int> queue = <int>[];
  int nextArrivalUs = 0;

  /// When the frame in service reached the head of the queue.
  int holStartUs = 0;

  // Carrier sense, as this station sees it.
  bool lastBusy = false;
  int idleSinceUs = 0;
  bool useEifs = false;
  int navUntilUs = 0;

  // Exchange bookkeeping.
  int responseTimeoutUs = -1;
  int pendingDataAtUs = -1;
  LaneSegment? exchangeSegment;

  // Totals.
  int attempts = 0;
  int failedAttempts = 0;
  int delivered = 0;
  int dropped = 0;

  bool get hasFrame => config.saturated || queue.isNotEmpty;
}

class _Tx {
  _Tx({
    required this.source,
    required this.kind,
    required this.startUs,
    required this.endUs,
    required this.receivers,
    required this.air,
    this.target,
    this.navUntilUs = 0,
  }) : corruptAt = List<bool>.filled(receivers, false),
       deafAt = List<bool>.filled(receivers, false);

  final int source;
  final FrameKind kind;
  final int startUs;
  final int endUs;
  final int receivers;
  final int? target;
  final int navUntilUs;
  final AirFrame air;

  /// Per receiver (stations then AP): overlap or half-duplex loss.
  final List<bool> corruptAt;

  /// Per receiver: it was transmitting during part of this frame, so it was
  /// not listening and takes no EIFS from it.
  final List<bool> deafAt;
}

class _Pending {
  const _Pending({
    required this.atUs,
    required this.source,
    required this.kind,
    required this.target,
    this.navUntilUs = 0,
  });

  final int atUs;
  final int source;
  final FrameKind kind;
  final int? target;
  final int navUntilUs;
}

// ── Engine ─────────────────────────────────────────────────────────────────

/// Deterministic DCF/EDCA contention simulator. Same config and seed, same
/// run, every time.
class MediumAccessEngine {
  MediumAccessEngine(this.config, {this.backoffDraw, this.retentionUs = 20000})
    : _random = math.Random(config.seed) {
    final int n = config.stations.length;
    if (n < MediumAccessConfig.minStations ||
        n > MediumAccessConfig.maxStations) {
      throw ArgumentError.value(
        n,
        'stations',
        'must hold ${MediumAccessConfig.minStations} to '
            '${MediumAccessConfig.maxStations} stations',
      );
    }
    for (int i = 0; i < n; i++) {
      _stations.add(
        _Station(
          i,
          config.stations[i],
          config.paramsFor(i),
          config.hiddenNode ? i % 2 : null,
        ),
      );
    }
    for (final _Station s in _stations) {
      if (s.config.saturated) {
        _beginFrame(s, 0);
      } else {
        s.nextArrivalUs = _interArrivalUs(s);
      }
    }
  }

  /// The AP's index in [AirFrame.source].
  static const int apIndex = -1;

  final MediumAccessConfig config;

  /// How much history the timeline keeps, us.
  final int retentionUs;

  final math.Random _random;

  /// Optional scripted backoff source (tests); null draws uniformly.
  final BackoffDraw? backoffDraw;
  final List<_Station> _stations = <_Station>[];
  final List<_Tx> _active = <_Tx>[];
  final List<_Pending> _pending = <_Pending>[];
  final List<LaneSegment> _segments = <LaneSegment>[];
  final List<AirFrame> _air = <AirFrame>[];
  late final List<LaneSegment?> _open = List<LaneSegment?>.filled(
    config.stations.length,
    null,
  );

  int _now = 0;
  int _busyUs = 0;
  int _deliveredBits = 0;
  int _dataFrames = 0;
  int _dataCorrupted = 0;
  final Map<AccessCategory, AccessDelayStat> _delay =
      <AccessCategory, AccessDelayStat>{};

  int get _n => _stations.length;
  int get _ap => _n; // receiver index of the AP

  // ── Public surface ───────────────────────────────────────────────────────

  /// Simulated time, us. Always a whole number of slots.
  int get nowUs => _now;

  /// Advance one 9 us slot.
  void stepSlot() => advanceSlots(1);

  /// Advance [slots] whole slots.
  void advanceSlots(int slots) {
    for (int s = 0; s < slots; s++) {
      for (int t = 0; t < OfdmTiming.slotUs; t++) {
        _tick();
        _now++;
      }
    }
    _prune();
  }

  /// Station lane history, oldest first, within [retentionUs].
  List<LaneSegment> get segments => List<LaneSegment>.unmodifiable(_segments);

  /// Medium lane history, oldest first, within [retentionUs].
  List<AirFrame> get airFrames => List<AirFrame>.unmodifiable(_air);

  /// Every station, in index order.
  List<StationSnapshot> get stations => <StationSnapshot>[
    for (final _Station s in _stations)
      StationSnapshot(
        index: s.index,
        params: s.params,
        accessCategory: s.config.accessCategory,
        phase: s.phase,
        cw: s.cw,
        backoff: s.backoff < 0 ? null : s.backoff,
        queued: s.config.saturated ? -1 : s.queue.length,
        attempts: s.attempts,
        failedAttempts: s.failedAttempts,
        delivered: s.delivered,
        dropped: s.dropped,
        hiddenGroup: s.hiddenGroup,
      ),
  ];

  /// Totals since the run started.
  MediumAccessStats get stats {
    int attempts = 0, failed = 0, delivered = 0, dropped = 0;
    for (final _Station s in _stations) {
      attempts += s.attempts;
      failed += s.failedAttempts;
      delivered += s.delivered;
      dropped += s.dropped;
    }
    return MediumAccessStats(
      elapsedUs: _now,
      busyUs: _busyUs,
      deliveredBits: _deliveredBits,
      delivered: delivered,
      dropped: dropped,
      attempts: attempts,
      failedAttempts: failed,
      dataFrames: _dataFrames,
      dataFramesCorrupted: _dataCorrupted,
      accessDelay: Map<AccessCategory, AccessDelayStat>.unmodifiable(_delay),
    );
  }

  /// The frames on the air right now.
  List<AirFrame> get onAir => <AirFrame>[for (final _Tx t in _active) t.air];

  // ── Tick ─────────────────────────────────────────────────────────────────

  void _tick() {
    final int t = _now;
    _arrivals(t);
    _endTransmissions(t);
    _timeouts(t);
    _startPending(t);
    _contend(t);
    _markOverlaps();
    if (_active.isNotEmpty) _busyUs++;
    _record(t);
  }

  void _arrivals(int t) {
    for (final _Station s in _stations) {
      final double? rate = s.config.framesPerSecond;
      if (rate == null || rate <= 0) continue;
      while (s.nextArrivalUs <= t) {
        if (s.queue.length < config.queueLimit) {
          s.queue.add(s.nextArrivalUs);
          if (s.queue.length == 1 && s.phase == StationPhase.noFrame) {
            _beginFrame(s, t);
          }
        }
        s.nextArrivalUs += _interArrivalUs(s);
      }
    }
  }

  int _interArrivalUs(_Station s) {
    final double rate = s.config.framesPerSecond!;
    // Exponential inter-arrival; 1 - u keeps log away from zero.
    final double u = 1 - _random.nextDouble();
    return math.max(1, (-math.log(u) * 1e6 / rate).round());
  }

  void _endTransmissions(int t) {
    final List<_Tx> ending = <_Tx>[
      for (final _Tx tx in _active)
        if (tx.endUs == t) tx,
    ];
    if (ending.isEmpty) return;
    _active.removeWhere((_Tx tx) => tx.endUs == t);

    for (final _Tx tx in ending) {
      // What every listening station learns from this frame.
      for (final _Station r in _stations) {
        if (!_audible(r.index, tx)) continue;
        if (tx.corruptAt[r.index]) {
          if (!tx.deafAt[r.index]) r.useEifs = true;
          continue;
        }
        r.useEifs = false;
        final bool addressed = tx.kind == FrameKind.cts && tx.target == r.index;
        if ((tx.kind == FrameKind.rts || tx.kind == FrameKind.cts) &&
            !addressed &&
            tx.navUntilUs > r.navUntilUs) {
          r.navUntilUs = tx.navUntilUs;
        }
      }

      if (tx.source == apIndex) {
        _endApFrame(tx, t);
      } else {
        _endStationFrame(tx, t);
      }
    }
  }

  void _endStationFrame(_Tx tx, int t) {
    final _Station s = _stations[tx.source];
    final bool clean = !tx.corruptAt[_ap];
    if (tx.kind == FrameKind.data) {
      _dataFrames++;
      if (!clean) _dataCorrupted++;
    }
    s.phase = StationPhase.awaitResponse;
    const int sifs = OfdmTiming.sifsUs;
    if (tx.kind == FrameKind.rts) {
      s.responseTimeoutUs = t + sifs + OfdmTiming.ctsUs;
      if (clean) {
        final int ctsEnd = t + sifs + OfdmTiming.ctsUs;
        final int nav = ctsEnd + sifs + config.dataUs + sifs + OfdmTiming.ackUs;
        _pending.add(
          _Pending(
            atUs: t + sifs,
            source: apIndex,
            kind: FrameKind.cts,
            target: s.index,
            navUntilUs: nav,
          ),
        );
      }
    } else {
      s.responseTimeoutUs = t + sifs + OfdmTiming.ackUs;
      if (clean) {
        _pending.add(
          _Pending(
            atUs: t + sifs,
            source: apIndex,
            kind: FrameKind.ack,
            target: s.index,
          ),
        );
      }
    }
  }

  void _endApFrame(_Tx tx, int t) {
    final int? target = tx.target;
    if (target == null) return;
    final _Station s = _stations[target];
    if (tx.corruptAt[target]) return; // the target's timeout handles it
    if (s.phase != StationPhase.awaitResponse) return;
    if (tx.kind == FrameKind.cts) {
      s.responseTimeoutUs = -1;
      s.pendingDataAtUs = t + OfdmTiming.sifsUs;
      _pending.add(
        _Pending(
          atUs: t + OfdmTiming.sifsUs,
          source: s.index,
          kind: FrameKind.data,
          target: null,
        ),
      );
    } else if (tx.kind == FrameKind.ack) {
      _success(s, t);
    }
  }

  void _timeouts(int t) {
    for (final _Station s in _stations) {
      if (s.phase == StationPhase.awaitResponse && s.responseTimeoutUs == t) {
        _failure(s, t);
      }
    }
  }

  void _startPending(int t) {
    final List<_Pending> due = <_Pending>[
      for (final _Pending p in _pending)
        if (p.atUs == t) p,
    ];
    if (due.isEmpty) return;
    _pending.removeWhere((_Pending p) => p.atUs == t);
    for (final _Pending p in due) {
      if (p.source == apIndex) {
        final int dur = p.kind == FrameKind.cts
            ? OfdmTiming.ctsUs
            : OfdmTiming.ackUs;
        _startTx(apIndex, p.kind, t, dur, target: p.target, nav: p.navUntilUs);
      } else {
        final _Station s = _stations[p.source];
        s.pendingDataAtUs = -1;
        s.phase = StationPhase.transmitting;
        _startTx(s.index, FrameKind.data, t, config.dataUs);
      }
    }
  }

  void _contend(int t) {
    // Every station reads the medium as it stands at the start of this us,
    // decides, and only then does anyone start. Two counts that reach zero on
    // the same boundary both transmit: that is the collision.
    final List<_Station> starters = <_Station>[];
    for (final _Station s in _stations) {
      final bool busy = _senseBusy(s, t);
      if (busy) {
        s.lastBusy = true;
        continue;
      }
      if (s.lastBusy) {
        s.lastBusy = false;
        s.idleSinceUs = t;
      }
      if (s.phase != StationPhase.contending) continue;
      final int wait = _waitUs(s);
      final int elapsed = t - s.idleSinceUs;
      if (elapsed < wait) continue;
      final int since = elapsed - wait;
      if (since % OfdmTiming.slotUs != 0) continue;
      final int boundary = since ~/ OfdmTiming.slotUs;
      if (s.backoff == 0) {
        starters.add(s);
      } else if (boundary >= 1) {
        s.backoff--;
        if (s.backoff == 0) starters.add(s);
      }
    }
    for (final _Station s in starters) {
      s.phase = StationPhase.transmitting;
      s.backoff = -1;
      s.useEifs = false;
      s.attempts++;
      final bool rts = config.rtsCts;
      _startTx(
        s.index,
        rts ? FrameKind.rts : FrameKind.data,
        t,
        rts ? OfdmTiming.rtsUs : config.dataUs,
        nav: rts
            ? t +
                  OfdmTiming.rtsUs +
                  3 * OfdmTiming.sifsUs +
                  OfdmTiming.ctsUs +
                  config.dataUs +
                  OfdmTiming.ackUs
            : 0,
      );
    }
  }

  /// AIFS normally; EIFS - DIFS + AIFS after an undecodable frame.
  int _waitUs(_Station s) {
    final int aifs = s.params.aifsUs;
    return s.useEifs ? OfdmTiming.eifsUs - OfdmTiming.difsUs + aifs : aifs;
  }

  bool _senseBusy(_Station s, int t) {
    if (s.navUntilUs > t) return true;
    for (final _Tx tx in _active) {
      if (tx.source == s.index || _audible(s.index, tx)) return true;
    }
    return false;
  }

  /// Whether receiver [r] (a station index, or [_ap]) hears [tx].
  bool _audible(int r, _Tx tx) {
    if (tx.source == r) return false;
    if (r == _ap) return tx.source != apIndex;
    if (tx.source == apIndex) return true;
    return config.stationsHear(r, tx.source);
  }

  void _startTx(
    int source,
    FrameKind kind,
    int t,
    int durationUs, {
    int? target,
    int nav = 0,
  }) {
    final AirFrame air = AirFrame(
      source: source,
      kind: kind,
      startUs: t,
      endUs: t + durationUs,
      target: target,
    );
    _air.add(air);
    _active.add(
      _Tx(
        source: source,
        kind: kind,
        startUs: t,
        endUs: t + durationUs,
        receivers: _n + 1,
        air: air,
        target: target,
        navUntilUs: nav,
      ),
    );
  }

  void _markOverlaps() {
    if (_active.isEmpty) return;
    for (int r = 0; r <= _n; r++) {
      final int receiverSource = r == _ap ? apIndex : r;
      final bool transmitting = _active.any(
        (_Tx tx) => tx.source == receiverSource,
      );
      int audible = 0;
      for (final _Tx tx in _active) {
        if (_audible(r, tx)) audible++;
      }
      if (audible == 0) continue;
      if (!transmitting && audible < 2) continue;
      for (final _Tx tx in _active) {
        if (!_audible(r, tx)) continue;
        tx.corruptAt[r] = true;
        if (transmitting) tx.deafAt[r] = true;
        if (r == _ap) tx.air.corruptedAtAp = true;
        if (tx.target == r) tx.air.corruptedAtTarget = true;
      }
    }
  }

  // ── Outcomes ─────────────────────────────────────────────────────────────

  void _success(_Station s, int t) {
    s.phase = StationPhase.noFrame;
    s.responseTimeoutUs = -1;
    s.delivered++;
    _deliveredBits += 8 * config.frameBytes;
    final AccessCategory ac = s.config.accessCategory;
    final AccessDelayStat prev =
        _delay[ac] ?? const AccessDelayStat(frames: 0, totalUs: 0);
    _delay[ac] = AccessDelayStat(
      frames: prev.frames + 1,
      totalUs: prev.totalUs + (t - s.holStartUs),
    );
    s.cw = s.params.cwMin;
    s.failures = 0;
    s.exchangeSegment = null;
    _finishFrame(s, t);
  }

  void _failure(_Station s, int t) {
    s.responseTimeoutUs = -1;
    s.failedAttempts++;
    s.failures++;
    s.exchangeSegment?.failed = true;
    s.exchangeSegment = null;
    if (s.failures >= config.retryLimit) {
      s.dropped++;
      s.failures = 0;
      s.cw = s.params.cwMin;
      s.phase = StationPhase.noFrame;
      _finishFrame(s, t);
      return;
    }
    s.cw = nextContentionWindow(s.cw, s.params.cwMax);
    s.phase = StationPhase.contending;
    s.backoff = _draw(s);
  }

  /// The frame in service is done (delivered or dropped).
  void _finishFrame(_Station s, int t) {
    if (!s.config.saturated && s.queue.isNotEmpty) s.queue.removeAt(0);
    s.backoff = -1;
    if (s.hasFrame) _beginFrame(s, t);
  }

  void _beginFrame(_Station s, int t) {
    s.phase = StationPhase.contending;
    s.holStartUs = t;
    s.failures = 0;
    s.backoff = _draw(s);
  }

  int _draw(_Station s) {
    final BackoffDraw? d = backoffDraw;
    final int v = d != null ? d(s.index, s.cw) : _random.nextInt(s.cw + 1);
    return v.clamp(0, s.cw);
  }

  // ── Timeline recording ───────────────────────────────────────────────────

  void _record(int t) {
    for (final _Station s in _stations) {
      LaneActivity? act;
      int? count;
      FrameKind? frame;
      switch (s.phase) {
        case StationPhase.noFrame:
          act = null;
        case StationPhase.transmitting:
          act = LaneActivity.transmit;
          for (final _Tx tx in _active) {
            if (tx.source == s.index) frame = tx.kind;
          }
        case StationPhase.awaitResponse:
          act = LaneActivity.awaitResponse;
        case StationPhase.contending:
          count = s.backoff;
          if (s.navUntilUs > t) {
            act = LaneActivity.nav;
          } else if (s.lastBusy) {
            act = LaneActivity.frozen;
          } else if (t - s.idleSinceUs < _waitUs(s)) {
            act = s.useEifs ? LaneActivity.eifs : LaneActivity.aifs;
            count = null;
          } else {
            act = LaneActivity.backoff;
          }
      }
      final LaneSegment? open = _open[s.index];
      if (open != null &&
          open.activity == act &&
          open.count == count &&
          open.frame == frame &&
          open.endUs == t) {
        open.endUs = t + 1;
        continue;
      }
      if (act == null) {
        _open[s.index] = null;
        continue;
      }
      final LaneSegment seg = LaneSegment(
        lane: s.index,
        activity: act,
        startUs: t,
        endUs: t + 1,
        count: count,
        frame: frame,
      );
      _segments.add(seg);
      _open[s.index] = seg;
      // A failure marks the frame that got no response: the RTS when no CTS
      // came back, the data frame when no ACK did.
      if (act == LaneActivity.transmit) s.exchangeSegment = seg;
    }
  }

  void _prune() {
    final int cutoff = _now - retentionUs;
    int drop = 0;
    while (drop < _segments.length && _segments[drop].endUs < cutoff) {
      drop++;
    }
    if (drop > 0) _segments.removeRange(0, drop);
    int dropAir = 0;
    while (dropAir < _air.length && _air[dropAir].endUs < cutoff) {
      dropAir++;
    }
    if (dropAir > 0) _air.removeRange(0, dropAir);
  }
}
