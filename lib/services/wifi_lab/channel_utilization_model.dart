// Channel Utilization Meter: the pure model behind the Wi-Fi Classroom tool
// (channel-utilization).
//
// CLEAN-ROOM BUILD (2026-09-26) from myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/37-channel-utilization.md, with values from the wave 4
// research brief, section G (brief-GKL.md). No other teaching simulator was
// studied.
//
// WHAT IT COMPUTES
//   - The BSS Load element's Channel Utilization byte:
//       floor(255 x busy us / (window x beacon period in TU x 1024))
//     where busy is physical carrier sense, or physical OR virtual carrier
//     sense (the reservation a frame's Duration field sets) when the student
//     counts reserved time.
//   - The worked single-sender cycle (spec 37): DIFS + mean backoff + data +
//     SIFS + ACK, and the busy and payload shares of it.
//   - A seeded, event-driven contention run: 1 to 50 senders, a neighbor
//     network, non-Wi-Fi bursts, recorded per beacon interval so the meter
//     can average any window from 1 to 255 intervals.
//
// REUSE (spec 37: "reusing the Airtime Anatomy and Medium Access engines").
//   - Every duration (slot, SIFS, the data frame with its preamble and 2.4 GHz
//     signal extension, the ACK, the mean backoff) comes from
//     computeAirtime() in airtime_anatomy.dart, unchanged. DIFS is SIFS + 2
//     slots, as the Multicast tool derives it from the same result.
//   - The contention rules come from medium_access_engine.dart: the legacy DCF
//     parameters (kLegacyDcfParams: AIFSN 2, CWmin 15, CWmax 1023), the CW
//     step after a failure (nextContentionWindow), the retry limit, and the
//     slot-boundary countdown (a count reaching zero at the same boundary as
//     another is a collision; a busy medium freezes the count).
//   WHY NOT THE TICK ENGINE ITSELF. MediumAccessEngine is 5 GHz only (SIFS
//   16, no signal extension), holds at most 10 stations, and steps one
//   microsecond at a time. This tool needs 2.4 GHz timing (spec 05's
//   constants), 50 stations, and 5 to 26 seconds of channel per window, so it
//   jumps from event to event with the engine's rules instead.
//
// FRAME SIZE. Airtime Anatomy frames a payload as payload + 26-byte QoS
// header + 4-byte FCS + encryption. With no encryption, 1500 bytes is a
// 1530-octet frame: 57 OFDM symbols at 54 Mb/s, 228 us, the same as the
// research brief's 1536-octet frame (both round up to 57 symbols). So the
// data frame is 254 us, as spec 37 requires. Encryption is left out on
// purpose; with 16 bytes of it the frame is 58 symbols.
//
// SIMPLIFICATIONS (stated in the help):
//   1. 2.4 GHz, 802.11g OFDM rates only (ERP only), short slot, one 20 MHz
//      primary channel. Every station hears every other (no hidden nodes).
//   2. After a collision every station waits the ACK timeout (SIFS + ACK)
//      before DIFS, a simplification of the extended interframe space.
//   3. A new frame always draws a backoff (as the Medium Access engine does).
//   4. The neighbor network sends the same frames at the same rate, and
//      contends like one more station. Its station count is not this AP's.
//   5. Non-Wi-Fi bursts never land on top of a frame: a burst due during an
//      exchange starts when the exchange ends.
//   6. Beacons' own airtime is left out (SSID Airtime shows it).
//
// ARITHMETIC. Time is whole tenths of a microsecond, as in Airtime Anatomy.
//
// ASCII only, no em dashes (GL-004). No Flutter imports.

import 'dart:math' as math;

import 'airtime_anatomy.dart';
import 'medium_access_engine.dart'
    show EdcaParams, kLegacyDcfParams, nextContentionWindow;

// ── Constants ───────────────────────────────────────────────────────────────

/// One TU (time unit), microseconds.
const int kCuTuUs = 1024;

/// Beacon period, TU. Fixed at the common 100 TU.
const int kCuBeaconPeriodTu = 100;

/// One beacon interval in tenths of a microsecond (102.4 ms).
const int kCuIntervalTenths = kCuBeaconPeriodTu * kCuTuUs * 10;

/// Averaging window in beacon intervals. The default of 50 is the
/// standard's default according to one secondary source (the management
/// information base definition was not read): "default chosen by Larry
/// pending Keith", and labeled so in the UI.
const int kCuDefaultWindow = 50;
const int kCuMinWindow = 1;
const int kCuMaxWindow = 255;

const int kCuMinSenders = 1;
const int kCuMaxSenders = 50;

/// Associated stations that send nothing (the "forty idle phones").
const int kCuMaxIdleStations = 60;

/// Offered load per sender, percent of what one sender alone can carry.
/// 100 means saturated: a frame is always waiting.
const int kCuMinLoadPercent = 5;
const int kCuMaxLoadPercent = 100;

/// Neighbor network's offered airtime share, percent (illustrative).
const int kCuDefaultNeighborPercent = 20;
const int kCuMinNeighborPercent = 5;
const int kCuMaxNeighborPercent = 60;

/// Payload sizes offered, bytes.
const List<int> kCuPayloadSizes = <int>[100, 500, 1000, 1500, 2304];

/// Failed attempts after which a frame is dropped: the Medium Access
/// engine's default (MediumAccessConfig.retryLimit).
const int kCuRetryLimit = 7;

/// Frames a non-saturated station can hold (the engine's queueLimit).
const int kCuQueueLimit = 64;

/// Illustrative non-Wi-Fi pattern: bursts this long ...
const int kCuNonWifiBurstUs = 4000;

/// ... separated by random gaps averaging this, so about 20% of the time.
const int kCuNonWifiMeanGapUs = 16000;

/// The injected burst's length (spec 37: "a one-second burst").
const int kCuInjectedBurstUs = 1000000;

/// Intervals of history kept: the widest window plus some for drawing.
const int kCuHistoryIntervals = kCuMaxWindow + 45;

/// Recent channel blocks kept for the time strip, tenths (50 ms).
const int kCuBlockRetentionTenths = 500000;

/// The research brief's Bianchi (2000) points, read off the paper's figure
/// for basic access with 1 Mb/s parameters: saturation throughput as a share
/// of the channel. Only these points are published data; nothing between
/// them is.
const List<(int stations, double share)> kCuBianchiBasic = <(int, double)>[
  (5, 0.80),
  (50, 0.55),
];

/// Same figure, RTS/CTS (request to send / clear to send): about 0.83,
/// flat across station counts.
const double kCuBianchiRtsCts = 0.83;

/// Station counts the tool's own many-sender run uses.
const List<int> kCuCurveStations = <int>[1, 2, 5, 10, 20, 30, 40, 50];

// ── Configuration ───────────────────────────────────────────────────────────

/// Everything that shapes the traffic. Changing any of it starts a new run.
/// The window and the carrier-sense definition are measurement settings and
/// live outside this, so changing them re-reads the same history.
class CuConfig {
  const CuConfig({
    this.senders = 1,
    this.loadPercent = kCuMaxLoadPercent,
    this.rateMbps = 54,
    this.payloadBytes = 1500,
    this.idleStations = 0,
    this.neighbor = false,
    this.neighborPercent = kCuDefaultNeighborPercent,
    this.nonWifi = false,
  }) : assert(senders >= kCuMinSenders && senders <= kCuMaxSenders),
       assert(
         loadPercent >= kCuMinLoadPercent && loadPercent <= kCuMaxLoadPercent,
       ),
       assert(idleStations >= 0 && idleStations <= kCuMaxIdleStations),
       assert(
         neighborPercent >= kCuMinNeighborPercent &&
             neighborPercent <= kCuMaxNeighborPercent,
       );

  final int senders;

  /// Percent of one sender's saturated rate, per sender. 100 = saturated.
  final int loadPercent;

  /// 802.11g OFDM data rate, one of AirtimeConstants.legacyRatesMbps.
  final int rateMbps;

  final int payloadBytes;

  /// Associated stations that send nothing.
  final int idleStations;

  /// A neighbor network on the same channel.
  final bool neighbor;

  /// The neighbor's offered airtime share, percent (illustrative).
  final int neighborPercent;

  /// Illustrative non-Wi-Fi bursts, about 20% of the time.
  final bool nonWifi;

  bool get saturated => loadPercent >= kCuMaxLoadPercent;

  /// The Station Count field: associated stations of THIS network. The
  /// neighbor's stations are not counted.
  int get stationCount => senders + idleStations;

  CuConfig copyWith({
    int? senders,
    int? loadPercent,
    int? rateMbps,
    int? payloadBytes,
    int? idleStations,
    bool? neighbor,
    int? neighborPercent,
    bool? nonWifi,
  }) => CuConfig(
    senders: senders ?? this.senders,
    loadPercent: loadPercent ?? this.loadPercent,
    rateMbps: rateMbps ?? this.rateMbps,
    payloadBytes: payloadBytes ?? this.payloadBytes,
    idleStations: idleStations ?? this.idleStations,
    neighbor: neighbor ?? this.neighbor,
    neighborPercent: neighborPercent ?? this.neighborPercent,
    nonWifi: nonWifi ?? this.nonWifi,
  );

  @override
  bool operator ==(Object other) =>
      other is CuConfig &&
      other.senders == senders &&
      other.loadPercent == loadPercent &&
      other.rateMbps == rateMbps &&
      other.payloadBytes == payloadBytes &&
      other.idleStations == idleStations &&
      other.neighbor == neighbor &&
      other.neighborPercent == neighborPercent &&
      other.nonWifi == nonWifi;

  @override
  int get hashCode => Object.hash(
    senders,
    loadPercent,
    rateMbps,
    payloadBytes,
    idleStations,
    neighbor,
    neighborPercent,
    nonWifi,
  );
}

// ── Timing, from Airtime Anatomy ────────────────────────────────────────────

/// The ACK rate for a data rate: the fastest of Airtime Anatomy's control
/// rates (6, 12, 24 Mb/s) that is not faster than the data rate.
int cuControlRateFor(int rateMbps) {
  int best = AirtimeConstants.controlRatesMbps.first;
  for (final int r in AirtimeConstants.controlRatesMbps) {
    if (r <= rateMbps) best = r;
  }
  return best;
}

/// The Airtime Anatomy scenario for one data frame on this channel.
AirtimeScenario cuScenario(int rateMbps, int payloadBytes) => AirtimeScenario(
  band: AirtimeBand.ghz24,
  phy: AirtimePhy.legacy,
  widthMhz: 20,
  legacyRateMbps: rateMbps,
  streams: 1,
  guardInterval: GuardInterval.gi08,
  payloadBytes: payloadBytes,
  encryptionBytes: 0,
  accessCategory: AirtimeAccessCategory.be,
  controlRateMbps: cuControlRateFor(rateMbps),
);

/// Every duration the channel uses, in tenths of a microsecond.
class CuTiming {
  CuTiming._(this.airtime, this.payloadBytes, this.rateMbps);

  factory CuTiming(int rateMbps, int payloadBytes) => CuTiming._(
    computeAirtime(cuScenario(rateMbps, payloadBytes)),
    payloadBytes,
    rateMbps,
  );

  /// The Airtime Anatomy result this timing reads from.
  final AirtimeResult airtime;
  final int payloadBytes;
  final int rateMbps;

  /// The contention parameters (legacy DCF, from the Medium Access engine).
  EdcaParams get params => kLegacyDcfParams;

  int get slotTenths => airtime.slotUs * 10;
  int get sifsTenths => airtime.sifsUs * 10;

  /// DIFS = SIFS + 2 slots (AIFSN 2).
  int get difsTenths => (airtime.sifsUs + params.aifsn * airtime.slotUs) * 10;

  /// Mean backoff, CWmin / 2 slots: Airtime Anatomy's backoff segment (best
  /// effort shares CWmin 15 with legacy DCF).
  int get meanBackoffTenths => airtime.segment(TxopSegmentKind.backoff).tenths;

  /// The data frame on the air: preamble and SIGNAL, symbols, signal
  /// extension.
  int get dataTenths => airtime.ppduTenths;

  int get preambleTenths => airtime.preambleTenths;

  int get ackTenths => airtime.ackTenths;

  /// The payload's own bits at the data rate, tenths (rounded).
  int get payloadTenths => (payloadBits * 10 / rateMbps).round();

  double get payloadUs => payloadBits / rateMbps;

  int get payloadBits => payloadBytes * 8;

  /// No ACK after a collision: the ACK timeout (SIFS + ACK time) is waited.
  int get ackTimeoutTenths => sifsTenths + ackTenths;

  /// One successful exchange with no waiting: data + SIFS + ACK.
  int get exchangeTenths => dataTenths + sifsTenths + ackTenths;
}

/// The worked single-sender case (spec 37): one saturated sender, mean
/// backoff, no one else on the channel.
class CuCycle {
  CuCycle(this.timing);

  final CuTiming timing;

  int get cycleTenths =>
      timing.difsTenths +
      timing.meanBackoffTenths +
      timing.dataTenths +
      timing.sifsTenths +
      timing.ackTenths;

  double get cycleUs => cycleTenths / 10;

  /// Physical carrier sense: data + ACK.
  int get physicalBusyTenths => timing.dataTenths + timing.ackTenths;

  /// Physical or virtual: the reservation covers the SIFS between them.
  int get virtualBusyTenths => physicalBusyTenths + timing.sifsTenths;

  double get physicalShare => physicalBusyTenths / cycleTenths;
  double get virtualShare => virtualBusyTenths / cycleTenths;

  /// Payload airtime (payload bits / rate) over the cycle.
  double get payloadShare => timing.payloadUs / cycleUs;

  /// The waiting the protocol requires: DIFS + mean backoff.
  double get requiredIdleShare =>
      (timing.difsTenths + timing.meanBackoffTenths) / cycleTenths;

  /// Delivered payload, Mb/s.
  double get throughputMbps => timing.payloadBits / cycleUs;
}

// ── The formula ─────────────────────────────────────────────────────────────

/// The Channel Utilization byte: floor(255 x busy / (window x beacon period
/// x 1024)), with [busyTenths] in tenths of a microsecond. Never above 255.
int channelUtilizationByte({
  required int busyTenths,
  required int windowIntervals,
  int beaconPeriodTu = kCuBeaconPeriodTu,
}) {
  if (windowIntervals <= 0) {
    throw ArgumentError.value(windowIntervals, 'windowIntervals', 'must be >0');
  }
  final int denominator = windowIntervals * beaconPeriodTu * kCuTuUs * 10;
  final int busy = busyTenths.clamp(0, denominator);
  return (255 * busy) ~/ denominator;
}

/// What a client decodes from the byte: byte / 255.
double utilizationShareOfByte(int byte) => byte / 255;

// ── Recorded time ───────────────────────────────────────────────────────────

/// What one span of channel time was. Physical busy: the frames and bursts.
/// Virtual busy adds the SIFS a frame's Duration field reserves.
enum CuSpan {
  /// This network's payload bits.
  payload,

  /// This network's preambles, headers, signal extension and ACKs.
  overhead,

  /// The SIFS inside this network's exchange, reserved by the Duration field.
  reservedGap,

  /// Two or more frames at once; neither is received.
  collision,

  /// The neighbor network's frames and ACKs.
  neighbor,

  /// The SIFS inside the neighbor's exchange (the AP decodes its reservation).
  neighborGap,

  /// Energy from something that is not Wi-Fi.
  nonWifi,

  /// Idle while a station waits as the protocol requires: DIFS, backoff,
  /// the ACK timeout after a collision.
  requiredIdle,

  /// Idle with nobody waiting to send.
  spare;

  bool get physicalBusy =>
      this == payload ||
      this == overhead ||
      this == collision ||
      this == neighbor ||
      this == nonWifi;

  bool get virtualBusy =>
      physicalBusy || this == reservedGap || this == neighborGap;
}

/// Time per span, tenths, over one beacon interval or a sum of them.
class CuTotals {
  CuTotals() : _t = List<int>.filled(CuSpan.values.length, 0);

  CuTotals._copy(List<int> t) : _t = List<int>.of(t);

  final List<int> _t;

  int operator [](CuSpan s) => _t[s.index];

  void add(CuSpan s, int tenths) => _t[s.index] += tenths;

  void addAll(CuTotals o) {
    for (int i = 0; i < _t.length; i++) {
      _t[i] += o._t[i];
    }
  }

  CuTotals copy() => CuTotals._copy(_t);

  int get totalTenths => _t.fold<int>(0, (int a, int b) => a + b);

  int busyTenths({required bool countReserved}) {
    int b = 0;
    for (final CuSpan s in CuSpan.values) {
      if (countReserved ? s.virtualBusy : s.physicalBusy) b += _t[s.index];
    }
    return b;
  }

  double share(CuSpan s) => totalTenths == 0 ? 0 : _t[s.index] / totalTenths;
}

/// The kinds of block the time strip draws.
enum CuBlockKind {
  data,
  ack,
  gap,
  collision,
  neighborData,
  neighborAck,
  neighborGap,
  nonWifi,
  wait,
}

/// One contiguous block of recent channel time.
class CuBlock {
  const CuBlock(this.kind, this.startTenths, this.endTenths, {this.station});

  final CuBlockKind kind;
  final int startTenths;
  final int endTenths;

  /// Sending station index for data and collisions (the neighbor is -1).
  final int? station;

  int get durationTenths => endTenths - startTenths;
}

/// The meter over a window.
class CuReading {
  const CuReading({
    required this.byte,
    required this.busyTenths,
    required this.intervalsUsed,
    required this.windowIntervals,
    required this.totals,
  });

  /// The Channel Utilization field, 0 to 255.
  final int byte;

  /// Busy time summed over the intervals used.
  final int busyTenths;

  /// Completed intervals averaged (fewer than the window while it fills).
  final int intervalsUsed;

  /// The window the student set.
  final int windowIntervals;

  /// Every span summed over the intervals used.
  final CuTotals totals;

  bool get filling => intervalsUsed < windowIntervals;

  /// byte / 255, what a client decodes.
  double get share => utilizationShareOfByte(byte);

  /// Busy over the intervals used, exactly (before the byte's rounding).
  double get exactShare =>
      intervalsUsed == 0 ? 0 : busyTenths / (intervalsUsed * kCuIntervalTenths);
}

// ── The run ─────────────────────────────────────────────────────────────────

class _Sta {
  _Sta({
    required this.neighbor,
    required this.framesPerSecond,
    required this.cw,
  });

  final bool neighbor;

  /// Null = saturated.
  final double? framesPerSecond;

  int cw;

  /// Remaining backoff slots; -1 = no frame in service.
  int backoff = -1;

  /// When this station started counting in the current idle period.
  int readyTenths = 0;

  int queued = 0;
  int nextArrivalTenths = 0;
  int failures = 0;

  int attempts = 0;
  int delivered = 0;
  int collided = 0;
  int dropped = 0;

  bool get saturated => framesPerSecond == null;
  bool get hasFrame => saturated || queued > 0;
}

/// A seeded, event-driven run of the channel. Same config and seed, same
/// run, every time.
class CuSim {
  CuSim(this.config, {this.seed = 1, this.keepBlocks = true})
    : timing = CuTiming(config.rateMbps, config.payloadBytes),
      _random = math.Random(seed) {
    final CuCycle cycle = CuCycle(timing);
    // One sender alone completes one frame per cycle: the 100% load.
    final double fullRate = 1e6 / cycle.cycleUs;
    for (int i = 0; i < config.senders; i++) {
      _stations.add(
        _Sta(
          neighbor: false,
          framesPerSecond: config.saturated
              ? null
              : fullRate * config.loadPercent / 100,
          cw: timing.params.cwMin,
        ),
      );
    }
    if (config.neighbor) {
      // Frames per second so the neighbor's data + ACK fill its share.
      final double busyUs = (timing.dataTenths + timing.ackTenths) / 10;
      _stations.add(
        _Sta(
          neighbor: true,
          framesPerSecond: 1e6 * config.neighborPercent / 100 / busyUs,
          cw: timing.params.cwMin,
        ),
      );
    }
    for (final _Sta s in _stations) {
      if (s.saturated) {
        s.backoff = _draw(s);
      } else {
        s.nextArrivalTenths = _interArrival(s);
      }
    }
    if (config.nonWifi) _scheduleNextRandomBurst(0);
  }

  final CuConfig config;
  final int seed;
  final CuTiming timing;
  final math.Random _random;

  /// False for headless runs (the many-sender curve): no blocks kept.
  final bool keepBlocks;
  final List<_Sta> _stations = <_Sta>[];

  /// Generated up to here, tenths. Always at an idle moment.
  int _t = 0;

  /// When the medium last went idle, tenths.
  int _idleStart = 0;

  /// Extra required wait before DIFS (the ACK timeout after a collision).
  int _extraWait = 0;

  /// Channel time accounted up to here, tenths.
  int _accounted = 0;

  /// Pending non-Wi-Fi bursts, sorted, non-overlapping: (start, end).
  final List<(int, int)> _bursts = <(int, int)>[];

  /// End of the random pattern's last scheduled burst.
  int _randomBurstEnd = 0;

  final List<CuTotals> _intervals = <CuTotals>[];
  int _intervalsDropped = 0;
  CuTotals _current = CuTotals();
  int _currentIndex = 0;

  final List<CuBlock> _blocks = <CuBlock>[];

  // ── Public surface ───────────────────────────────────────────────────────

  /// How far the run has been generated, tenths of a microsecond.
  int get nowTenths => _t;

  double get nowUs => _t / 10;

  /// Beacon intervals completed since the start.
  int get completedIntervals => _intervalsDropped + _intervals.length;

  /// The most recent completed intervals, oldest first (up to
  /// [kCuHistoryIntervals]).
  List<CuTotals> get intervals => List<CuTotals>.unmodifiable(_intervals);

  /// The interval in progress.
  CuTotals get currentInterval => _current;

  /// How far into the current interval the run is, 0 to 1.
  double get currentIntervalProgress =>
      (_t - _currentIndex * kCuIntervalTenths) / kCuIntervalTenths;

  /// Recent blocks, oldest first, within [kCuBlockRetentionTenths].
  List<CuBlock> get blocks => List<CuBlock>.unmodifiable(_blocks);

  int get attempts => _sum((_Sta s) => s.attempts, neighbor: false);
  int get delivered => _sum((_Sta s) => s.delivered, neighbor: false);
  int get collidedAttempts => _sum((_Sta s) => s.collided, neighbor: false);
  int get dropped => _sum((_Sta s) => s.dropped, neighbor: false);
  int get neighborDelivered => _sum((_Sta s) => s.delivered, neighbor: true);

  int _sum(int Function(_Sta s) f, {required bool neighbor}) {
    int n = 0;
    for (final _Sta s in _stations) {
      if (s.neighbor == neighbor) n += f(s);
    }
    return n;
  }

  /// The meter over the last [window] completed beacon intervals (fewer
  /// while the run is younger than the window). Null before the first
  /// interval completes.
  CuReading? reading({required int window, required bool countReserved}) {
    final int used = math.min(window, _intervals.length);
    if (used == 0) return null;
    final CuTotals sum = CuTotals();
    for (int i = _intervals.length - used; i < _intervals.length; i++) {
      sum.addAll(_intervals[i]);
    }
    final int busy = sum.busyTenths(countReserved: countReserved);
    return CuReading(
      byte: channelUtilizationByte(busyTenths: busy, windowIntervals: used),
      busyTenths: busy,
      intervalsUsed: used,
      windowIntervals: window,
      totals: sum,
    );
  }

  /// Runs the channel until at least [targetTenths].
  void runUntil(int targetTenths) {
    while (_t < targetTenths) {
      _stepEvent();
    }
    _settle();
    _pruneBlocks();
  }

  void runForUs(double us) => runUntil(_t + (us * 10).round());

  /// Runs whole beacon intervals.
  void runIntervals(int n) =>
      runUntil((completedIntervals + n) * kCuIntervalTenths);

  /// Adds one non-Wi-Fi burst of [us] starting now (the "1-second burst").
  void injectBurst([int us = kCuInjectedBurstUs]) {
    _addBurst(_t, _t + us * 10);
  }

  // ── Events ──────────────────────────────────────────────────────────────

  void _stepEvent() {
    _pullArrivals(_t);
    final int base = _idleStart + _extraWait + timing.difsTenths;
    final int slot = timing.slotTenths;

    // Earliest transmit boundary among stations with a frame.
    int? txAt;
    for (final _Sta s in _stations) {
      if (!s.hasFrame || s.backoff < 0) continue;
      final int at = base + _txIndex(s, base) * slot;
      if (txAt == null || at < txAt) txAt = at;
    }

    // Earliest arrival at a station with nothing to send.
    int? arrival;
    for (final _Sta s in _stations) {
      if (s.saturated || s.hasFrame) continue;
      if (arrival == null || s.nextArrivalTenths < arrival) {
        arrival = s.nextArrivalTenths;
      }
    }

    final int? burst = _bursts.isEmpty ? null : math.max(_bursts.first.$1, _t);

    // A burst wins a tie with a transmission: the medium is busy at that
    // microsecond, so nobody starts.
    final int next = <int?>[
      txAt,
      arrival,
      burst,
    ].whereType<int>().fold<int>(1 << 52, math.min);
    if (next == 1 << 52) {
      // Nothing will ever happen: jump to the next interval boundary.
      final int to = (_t ~/ kCuIntervalTenths + 1) * kCuIntervalTenths;
      _t = to;
      return;
    }

    if (burst != null && burst == next) {
      _runBurst(burst, base);
      return;
    }
    if (arrival != null && arrival == next) {
      // An arrival joins the contention at that moment, before anyone
      // transmits at the same microsecond (the engine's tick order).
      _t = arrival;
      return;
    }
    _runTransmission(txAt!, base);
  }

  /// The boundary index at which [s] transmits if nothing interrupts.
  /// Boundary 0 is the end of DIFS; the count drops at boundaries 1, 2 ...
  /// and a zero count sends at the first boundary it sees (the Medium
  /// Access engine's rule).
  int _txIndex(_Sta s, int base) {
    final int from = _countFrom(s, base);
    return s.backoff == 0 ? from : math.max(from, 1) + s.backoff - 1;
  }

  int _countFrom(_Sta s, int base) {
    if (s.readyTenths <= base) return 0;
    final int slot = timing.slotTenths;
    return (s.readyTenths - base + slot - 1) ~/ slot;
  }

  /// Counts [s] down by the boundaries it saw up to [lastIndex] inclusive.
  void _countDown(_Sta s, int base, int lastIndex) {
    if (s.backoff <= 0) return;
    final int first = math.max(_countFrom(s, base), 1);
    if (lastIndex < first) return;
    s.backoff = math.max(0, s.backoff - (lastIndex - first + 1));
  }

  /// Accounts the idle time from [_accounted] to [to].
  void _recordIdleTo(int to) {
    final int from = _accounted;
    if (to <= from) return;
    _accounted = to;
    // Required from the moment someone has a frame to send.
    int contendFrom = to;
    for (final _Sta s in _stations) {
      if (!s.hasFrame || s.backoff < 0) continue;
      final int r = math.max(from, s.readyTenths);
      if (r < contendFrom) contendFrom = r;
    }
    if (_extraWait > 0) contendFrom = from;
    contendFrom = contendFrom.clamp(from, to);
    _account(CuSpan.spare, from, contendFrom);
    _account(CuSpan.requiredIdle, contendFrom, to);
    if (contendFrom < to) _block(CuBlockKind.wait, contendFrom, to);
  }

  void _runBurst(int start, int base) {
    final (int, int) b = _bursts.removeAt(0);
    final int end = b.$2;
    final int slot = timing.slotTenths;
    // Boundaries strictly before the burst count; one at its first
    // microsecond sees a busy medium.
    final int lastIndex = start > base ? (start - 1 - base) ~/ slot : -1;
    for (final _Sta s in _stations) {
      if (s.hasFrame && s.backoff >= 0) _countDown(s, base, lastIndex);
    }
    _recordIdleTo(start);
    _account(CuSpan.nonWifi, start, end);
    _block(CuBlockKind.nonWifi, start, end);
    _afterBusy(end);
    if (config.nonWifi && _bursts.isEmpty) _scheduleNextRandomBurst(end);
  }

  void _runTransmission(int at, int base) {
    final int slot = timing.slotTenths;
    final int index = (at - base) ~/ slot;
    final List<_Sta> senders = <_Sta>[];
    for (final _Sta s in _stations) {
      if (!s.hasFrame || s.backoff < 0) continue;
      if (_txIndex(s, base) == index) {
        senders.add(s);
      } else {
        _countDown(s, base, index);
      }
    }
    _recordIdleTo(at);
    for (final _Sta s in senders) {
      s.attempts++;
      s.backoff = -1;
    }

    final int d = timing.dataTenths;
    if (senders.length == 1) {
      final _Sta s = senders.single;
      final int dataEnd = at + d;
      final int ackStart = dataEnd + timing.sifsTenths;
      final int end = ackStart + timing.ackTenths;
      final int who = s.neighbor ? -1 : _stations.indexOf(s);
      if (s.neighbor) {
        _account(CuSpan.neighbor, at, dataEnd);
        _account(CuSpan.neighborGap, dataEnd, ackStart);
        _account(CuSpan.neighbor, ackStart, end);
        _block(CuBlockKind.neighborData, at, dataEnd, station: who);
        _block(CuBlockKind.neighborGap, dataEnd, ackStart);
        _block(CuBlockKind.neighborAck, ackStart, end);
      } else {
        // The payload's own bits sit at the end of the frame's airtime; the
        // rest (preamble, header, checksum, service and tail bits, signal
        // extension) is overhead.
        final int payload = math.min(timing.payloadTenths, d);
        _account(CuSpan.overhead, at, dataEnd - payload);
        _account(CuSpan.payload, dataEnd - payload, dataEnd);
        _account(CuSpan.reservedGap, dataEnd, ackStart);
        _account(CuSpan.overhead, ackStart, end);
        _block(CuBlockKind.data, at, dataEnd, station: who);
        _block(CuBlockKind.gap, dataEnd, ackStart);
        _block(CuBlockKind.ack, ackStart, end);
      }
      s.delivered++;
      s.failures = 0;
      s.cw = timing.params.cwMin;
      _finishFrame(s, end);
      _afterBusy(end);
      return;
    }

    // Collision: every frame is lost, nobody answers.
    final int end = at + d;
    _account(CuSpan.collision, at, end);
    _block(CuBlockKind.collision, at, end);
    for (final _Sta s in senders) {
      s.collided++;
      s.failures++;
      if (s.failures >= kCuRetryLimit) {
        s.dropped++;
        s.failures = 0;
        s.cw = timing.params.cwMin;
        _finishFrame(s, end);
      } else {
        s.cw = nextContentionWindow(s.cw, timing.params.cwMax);
        s.backoff = _draw(s);
        s.readyTenths = end;
      }
    }
    _afterBusy(end, extraWait: timing.ackTimeoutTenths);
  }

  /// The frame in service is done (delivered or dropped).
  void _finishFrame(_Sta s, int at) {
    if (!s.saturated && s.queued > 0) s.queued--;
    s.backoff = -1;
    if (s.hasFrame) {
      s.backoff = _draw(s);
      s.readyTenths = at;
    }
  }

  void _afterBusy(int end, {int extraWait = 0}) {
    _t = end;
    _idleStart = end;
    _accounted = end;
    _extraWait = extraWait;
    for (final _Sta s in _stations) {
      if (s.readyTenths < end) s.readyTenths = end;
    }
    // A burst due during the busy time starts when it ends.
    if (_bursts.isNotEmpty && _bursts.first.$1 < end) {
      final (int, int) b = _bursts.removeAt(0);
      final int len = b.$2 - b.$1;
      _addBurst(end, end + len);
    }
  }

  void _pullArrivals(int upTo) {
    for (final _Sta s in _stations) {
      if (s.saturated) continue;
      while (s.nextArrivalTenths <= upTo) {
        final bool wasEmpty = s.queued == 0 && s.backoff < 0;
        if (s.queued < kCuQueueLimit) s.queued++;
        if (wasEmpty) {
          s.backoff = _draw(s);
          s.readyTenths = math.max(s.nextArrivalTenths, _idleStart);
        }
        s.nextArrivalTenths += _interArrival(s);
      }
    }
  }

  int _interArrival(_Sta s) {
    final double rate = s.framesPerSecond!;
    final double u = 1 - _random.nextDouble();
    return math.max(1, (-math.log(u) * 1e7 / rate).round());
  }

  int _draw(_Sta s) => _random.nextInt(s.cw + 1);

  // ── Non-Wi-Fi bursts ────────────────────────────────────────────────────

  void _scheduleNextRandomBurst(int after) {
    final double u = 1 - _random.nextDouble();
    final int gap = math.max(
      10,
      (-math.log(u) * kCuNonWifiMeanGapUs * 10).round(),
    );
    final int start = math.max(after, _randomBurstEnd) + gap;
    _randomBurstEnd = start + kCuNonWifiBurstUs * 10;
    _addBurst(start, _randomBurstEnd);
  }

  /// Inserts a burst, merging any it overlaps.
  void _addBurst(int start, int end) {
    int s = start, e = end;
    final List<(int, int)> keep = <(int, int)>[];
    for (final (int, int) b in _bursts) {
      if (b.$2 < s || b.$1 > e) {
        keep.add(b);
      } else {
        s = math.min(s, b.$1);
        e = math.max(e, b.$2);
      }
    }
    keep
      ..add((s, e))
      ..sort(((int, int) a, (int, int) b) => a.$1.compareTo(b.$1));
    _bursts
      ..clear()
      ..addAll(keep);
  }

  // ── Accounting ──────────────────────────────────────────────────────────

  /// Adds [from, to) to [span], split across beacon intervals.
  void _account(CuSpan span, int from, int to) {
    int a = from;
    while (a < to) {
      final int idx = a ~/ kCuIntervalTenths;
      while (idx > _currentIndex) {
        _pushInterval();
      }
      final int boundary = (idx + 1) * kCuIntervalTenths;
      final int b = math.min(to, boundary);
      _current.add(span, b - a);
      a = b;
    }
  }

  void _pushInterval() {
    _intervals.add(_current);
    if (_intervals.length > kCuHistoryIntervals) {
      _intervals.removeAt(0);
      _intervalsDropped++;
    }
    _current = CuTotals();
    _currentIndex++;
  }

  /// Accounts idle time up to now and completes every interval passed.
  void _settle() {
    _recordIdleTo(_t);
    while ((_currentIndex + 1) * kCuIntervalTenths <= _accounted) {
      _pushInterval();
    }
  }

  void _block(CuBlockKind kind, int start, int end, {int? station}) {
    if (!keepBlocks || end <= start) return;
    _blocks.add(CuBlock(kind, start, end, station: station));
  }

  void _pruneBlocks() {
    final int cutoff = _t - kCuBlockRetentionTenths;
    int drop = 0;
    while (drop < _blocks.length && _blocks[drop].endTenths < cutoff) {
      drop++;
    }
    if (drop > 0) _blocks.removeRange(0, drop);
  }
}

// ── Many senders ────────────────────────────────────────────────────────────

/// One point of the tool's own many-sender run.
class CuCurvePoint {
  const CuCurvePoint(
    this.stations,
    this.payloadShare,
    this.collisionShare,
    this.busyShare,
  );

  final int stations;

  /// Payload airtime over channel time: the throughput share.
  final double payloadShare;

  final double collisionShare;

  /// Busy by physical carrier sense: what the meter sees.
  final double busyShare;
}

/// Saturated senders at [rateMbps] and [payloadBytes]: the payload share of
/// channel time over [intervals] beacon intervals, seeded.
CuCurvePoint saturationPoint(
  int stations, {
  int rateMbps = 54,
  int payloadBytes = 1500,
  int intervals = 10,
  int seed = 1,
}) {
  final CuSim sim = CuSim(
    CuConfig(senders: stations, rateMbps: rateMbps, payloadBytes: payloadBytes),
    seed: seed,
    keepBlocks: false,
  )..runIntervals(intervals);
  final CuReading r = sim.reading(window: intervals, countReserved: false)!;
  return CuCurvePoint(
    stations,
    r.totals.share(CuSpan.payload),
    r.totals.share(CuSpan.collision),
    r.exactShare,
  );
}

/// The tool's own curve at [kCuCurveStations].
List<CuCurvePoint> saturationCurve({
  int rateMbps = 54,
  int payloadBytes = 1500,
  int intervals = 10,
  int seed = 1,
}) => <CuCurvePoint>[
  for (final int n in kCuCurveStations)
    saturationPoint(
      n,
      rateMbps: rateMbps,
      payloadBytes: payloadBytes,
      intervals: intervals,
      seed: seed,
    ),
];
