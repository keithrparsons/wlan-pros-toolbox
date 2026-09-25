// Multi-Link Operation teaching model (Wi-Fi Lab, mlo-simulator).
//
// A Wi-Fi 7 client holds links on up to three bands. Each link carries other
// networks' traffic (busy periods, random, seeded). A stream of frames for
// the client arrives at a chosen rate, and each MLO mode decides where and
// when each frame is sent:
//
//   Single link  one link, first in, first out.
//   STR          every link is its own sender: a frame goes on whichever
//                link is free first (the client can send on one link while
//                it receives on another).
//   NSTR         links must send together or receive together, so frames on
//                two links start together and end together (the shorter one
//                is padded out); nothing starts on a link while the others
//                are mid-exchange.
//   EMLSR        the client listens on every link but exchanges frames on
//                one at a time. Each exchange opens with an initial control
//                frame on the chosen link plus the padding delay, and after
//                it the client needs the transition delay before it can
//                listen on every link again.
//
// All modes see THE SAME random traffic (the same frame arrivals and the same
// busy periods on each band), so their latencies can be compared.
//
// CLEAN-ROOM (2026-09-25). Values from the Wi-Fi Lab research briefs, not
// from any other tool: myPKA Deliverables/2026-09-25-wifi-lab-wave3-research/
// brief.md section 7 (mode definitions; EMLSR padding delay 0/32/64/128/256
// us and transition delay 0/16/32/64/128/256 us, as listed in the Linux
// header include/linux/ieee80211-eht.h, values only) and wave5-research/
// brief.md section 10 (Intel's driver leaves EMLSR often). Spec: myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/22-mlo.md.
//
// A TEACHING MODEL. Choices a reader should know:
//   1. Other networks send the same planned traffic in every mode. A frame
//      starts the moment its link is idle; anyone due to start while it is on
//      the air waits and goes right after it (they defer). No collisions.
//   2. Airtime is either one fixed number on every link, or one TXOP from the
//      Airtime Anatomy service (AIFS, average backoff, preamble, data, SIFS,
//      Block Ack) at the band's width: 20 MHz on 2.4 GHz, 80 on 5, 160 on 6,
//      HE, 2 streams, 1500-byte frames. HE timing stands in for EHT.
//   3. The initial control frame is sized like an RTS answered by a CTS at
//      24 Mbps; a real MU-RTS trigger is longer, so this is a lower bound.
//   4. With EMLSR switched off by the driver, the client keeps ONE link: here
//      the enabled link with the lowest busy fraction. A real driver picks by
//      its own rules.
//   5. With only one link, every mode is the single link: there is nothing
//      to choose between and nothing to switch.
//
// Pure Dart, no Flutter imports. Times are in microseconds.

import 'dart:math' as math;

import 'airtime_anatomy.dart';

// ── Inputs ──────────────────────────────────────────────────────────────────

/// The three Wi-Fi 7 bands. Each band is at most one link here.
enum MloBand {
  ghz24('2.4 GHz', AirtimeBand.ghz24, 20),
  ghz5('5 GHz', AirtimeBand.ghz5, 80),
  ghz6('6 GHz', AirtimeBand.ghz6, 160);

  const MloBand(this.label, this.airtimeBand, this.widthMhz);

  final String label;
  final AirtimeBand airtimeBand;

  /// Channel width used for the Airtime Anatomy airtime.
  final int widthMhz;
}

/// The modes compared. [single] is always run, once per enabled link.
enum MloMode {
  single('Single link', 'Single'),
  str('STR', 'STR'),
  nstr('NSTR', 'NSTR'),
  emlsr('EMLSR', 'EMLSR');

  const MloMode(this.label, this.shortLabel);

  final String label;
  final String shortLabel;
}

/// Where each frame's airtime comes from.
enum MloAirtimeSource {
  fixed('Fixed'),
  anatomy('Airtime Anatomy');

  const MloAirtimeSource(this.label);

  final String label;
}

/// EMLSR padding delay values, microseconds (wave 3 brief section 7).
const List<int> kEmlsrPaddingDelaysUs = <int>[0, 32, 64, 128, 256];

/// EMLSR transition delay values, microseconds (wave 3 brief section 7).
const List<int> kEmlsrTransitionDelaysUs = <int>[0, 16, 32, 64, 128, 256];

/// Largest busy fraction the model accepts: at 1.0 a link never frees up.
const double kMloMaxBusyFraction = 0.95;

/// Frames per run.
const int kMloDefaultFrameCount = 2000;

/// Frames per A-MPDU offered in Airtime Anatomy mode.
const List<int> kMloAggregationChoices = <int>[1, 8, 32];

/// Size of each frame in Airtime Anatomy mode, bytes.
const int kMloFrameBytes = 1500;

/// Spatial streams in Airtime Anatomy mode.
const int kMloStreams = 2;

/// Control rate for the initial control frame and its answer, Mbps.
const int kMloControlRateMbps = 24;

/// One link: its band and how busy other networks keep it.
class MloLinkConfig {
  const MloLinkConfig({
    required this.band,
    this.busyFraction = 0.5,
    this.meanBusyUs = 1000,
  }) : assert(busyFraction >= 0 && busyFraction <= kMloMaxBusyFraction),
       assert(meanBusyUs > 0);

  final MloBand band;

  /// Share of time other traffic holds the channel, 0 to 0.95.
  final double busyFraction;

  /// Mean length of one busy period, microseconds.
  final double meanBusyUs;

  /// Mean idle gap that gives [busyFraction] with [meanBusyUs].
  double get meanIdleUs => busyFraction <= 0
      ? double.infinity
      : meanBusyUs * (1 - busyFraction) / busyFraction;

  MloLinkConfig copyWith({
    MloBand? band,
    double? busyFraction,
    double? meanBusyUs,
  }) => MloLinkConfig(
    band: band ?? this.band,
    busyFraction: busyFraction ?? this.busyFraction,
    meanBusyUs: meanBusyUs ?? this.meanBusyUs,
  );

  @override
  bool operator ==(Object other) =>
      other is MloLinkConfig &&
      other.band == band &&
      other.busyFraction == busyFraction &&
      other.meanBusyUs == meanBusyUs;

  @override
  int get hashCode => Object.hash(band, busyFraction, meanBusyUs);
}

/// Every input of one run.
class MloConfig {
  const MloConfig({
    this.links = const <MloLinkConfig>[
      MloLinkConfig(band: MloBand.ghz5),
      MloLinkConfig(band: MloBand.ghz6),
    ],
    this.arrivalsPerSecond = 1000,
    this.frameCount = kMloDefaultFrameCount,
    this.airtimeSource = MloAirtimeSource.fixed,
    this.fixedAirtimeUs = 300,
    this.mcs = 7,
    this.aggregation = 1,
    this.paddingDelayUs = 64,
    this.transitionDelayUs = 64,
    this.emlsrDisabledByDriver = false,
    this.seed = 1,
  }) : assert(arrivalsPerSecond > 0),
       assert(frameCount > 0),
       assert(fixedAirtimeUs > 0),
       assert(mcs >= 0 && mcs <= 11);

  /// One to three links, one per band, in band order.
  final List<MloLinkConfig> links;

  /// Mean frame arrival rate (random arrivals), frames per second.
  final double arrivalsPerSecond;

  final int frameCount;
  final MloAirtimeSource airtimeSource;

  /// Airtime of one frame on any link, when [airtimeSource] is fixed.
  final double fixedAirtimeUs;

  /// HE MCS, when [airtimeSource] is Airtime Anatomy.
  final int mcs;

  /// Frames per A-MPDU, when [airtimeSource] is Airtime Anatomy.
  final int aggregation;

  /// EMLSR padding delay, one of [kEmlsrPaddingDelaysUs].
  final int paddingDelayUs;

  /// EMLSR transition delay, one of [kEmlsrTransitionDelaysUs].
  final int transitionDelayUs;

  /// The driver has left EMLSR: the client uses one link.
  final bool emlsrDisabledByDriver;

  final int seed;

  MloConfig copyWith({
    List<MloLinkConfig>? links,
    double? arrivalsPerSecond,
    int? frameCount,
    MloAirtimeSource? airtimeSource,
    double? fixedAirtimeUs,
    int? mcs,
    int? aggregation,
    int? paddingDelayUs,
    int? transitionDelayUs,
    bool? emlsrDisabledByDriver,
    int? seed,
  }) => MloConfig(
    links: links ?? this.links,
    arrivalsPerSecond: arrivalsPerSecond ?? this.arrivalsPerSecond,
    frameCount: frameCount ?? this.frameCount,
    airtimeSource: airtimeSource ?? this.airtimeSource,
    fixedAirtimeUs: fixedAirtimeUs ?? this.fixedAirtimeUs,
    mcs: mcs ?? this.mcs,
    aggregation: aggregation ?? this.aggregation,
    paddingDelayUs: paddingDelayUs ?? this.paddingDelayUs,
    transitionDelayUs: transitionDelayUs ?? this.transitionDelayUs,
    emlsrDisabledByDriver: emlsrDisabledByDriver ?? this.emlsrDisabledByDriver,
    seed: seed ?? this.seed,
  );

  @override
  bool operator ==(Object other) {
    if (other is! MloConfig) return false;
    if (other.links.length != links.length) return false;
    for (int i = 0; i < links.length; i++) {
      if (other.links[i] != links[i]) return false;
    }
    return other.arrivalsPerSecond == arrivalsPerSecond &&
        other.frameCount == frameCount &&
        other.airtimeSource == airtimeSource &&
        other.fixedAirtimeUs == fixedAirtimeUs &&
        other.mcs == mcs &&
        other.aggregation == aggregation &&
        other.paddingDelayUs == paddingDelayUs &&
        other.transitionDelayUs == transitionDelayUs &&
        other.emlsrDisabledByDriver == emlsrDisabledByDriver &&
        other.seed == seed;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(links),
    arrivalsPerSecond,
    frameCount,
    airtimeSource,
    fixedAirtimeUs,
    mcs,
    aggregation,
    paddingDelayUs,
    transitionDelayUs,
    emlsrDisabledByDriver,
    seed,
  );
}

// ── Airtime ─────────────────────────────────────────────────────────────────

/// The Airtime Anatomy scenario for one frame (or A-MPDU) on [band].
AirtimeScenario mloAirtimeScenario(MloBand band, int mcs, int aggregation) =>
    AirtimeScenario(
      band: band.airtimeBand,
      phy: AirtimePhy.he,
      widthMhz: band.widthMhz,
      mcs: mcs,
      streams: kMloStreams,
      guardInterval: GuardInterval.gi08,
      payloadBytes: kMloFrameBytes,
      framesAggregated: aggregation,
    );

/// Airtime of one frame (or A-MPDU) on [band] under [c], microseconds.
double mloFrameAirtimeUs(MloConfig c, MloBand band) {
  if (c.airtimeSource == MloAirtimeSource.fixed) return c.fixedAirtimeUs;
  return computeAirtime(mloAirtimeScenario(band, c.mcs, c.aggregation)).totalUs;
}

/// What EMLSR adds in front of an exchange on [band]: the initial control
/// frame (sized as an RTS at 24 Mbps), the padding delay, SIFS, the client's
/// answer (sized as a CTS) and SIFS. Microseconds.
double mloEmlsrLeadInUs(MloBand band, int paddingDelayUs) {
  final AirtimeResult probe = computeAirtime(mloAirtimeScenario(band, 0, 1));
  final int se = probe.signalExtensionUs;
  final double icf = controlFrameTenths(20, kMloControlRateMbps, se) / 10;
  final double answer = controlFrameTenths(14, kMloControlRateMbps, se) / 10;
  return icf + paddingDelayUs + probe.sifsUs + answer + probe.sifsUs;
}

// ── Other networks' traffic ─────────────────────────────────────────────────

/// Other networks' traffic on one band, as they would send it if our client
/// were silent: busy periods with random lengths and random idle gaps,
/// generated on demand from a seeded stream. A band's traffic never depends
/// on which other links are enabled, on the mode, or on how far anything
/// looked ahead.
class MloBusyTrace {
  MloBusyTrace(this.link, int seed)
    : _rng = math.Random(seed * 7919 + link.band.index * 104729 + 13) {
    if (link.busyFraction > 0) {
      // Start in the steady state: busy with probability busyFraction.
      _cursorUs = _rng.nextDouble() < link.busyFraction
          ? 0
          : _exp(link.meanIdleUs);
    }
  }

  final MloLinkConfig link;
  final math.Random _rng;
  final List<double> _starts = <double>[];
  final List<double> _lengths = <double>[];
  double _cursorUs = 0;

  double _exp(double mean) => -mean * math.log(1 - _rng.nextDouble());

  bool get isQuiet => link.busyFraction <= 0;

  void _ensure(int j) {
    while (_starts.length <= j) {
      final double len = _exp(link.meanBusyUs);
      _starts.add(_cursorUs);
      _lengths.add(len);
      _cursorUs += len + _exp(link.meanIdleUs);
    }
  }

  /// Planned start of busy period [j], microseconds.
  double startOf(int j) {
    _ensure(j);
    return _starts[j];
  }

  /// Length of busy period [j], microseconds.
  double lengthOf(int j) {
    _ensure(j);
    return _lengths[j];
  }
}

/// One link as one mode uses it. Other networks send their planned traffic,
/// except that a busy period due to start while our frame is on the air
/// waits and starts right after it (they defer, as CSMA/CA stations do), and
/// a busy period that is pushed late pushes the next one if they would
/// overlap. Queries and holds must move forward in time.
class MloLinkTimeline {
  MloLinkTimeline(this.trace);

  final MloBusyTrace trace;

  /// Busy periods that have happened, real time.
  final List<(double, double)> busy = <(double, double)>[];

  /// Our holds on this link, real time.
  final List<(double, double)> holds = <(double, double)>[];

  int _next = 0;
  double _bgFree = 0;

  /// When the next planned busy period would start, given what has happened.
  double _nextStart() => math.max(trace.startOf(_next), _bgFree);

  /// Lets every busy period that would start at or before [t] happen.
  void _advanceTo(double t) {
    if (trace.isQuiet) return;
    while (_nextStart() <= t) {
      final double s = _nextStart();
      final double e = s + trace.lengthOf(_next);
      busy.add((s, e));
      _bgFree = e;
      _next++;
    }
  }

  /// The earliest time at or after [t] when the link is idle.
  double earliestIdle(double t) {
    if (trace.isQuiet) return t;
    double at = t;
    _advanceTo(at);
    while (busy.isNotEmpty && busy.last.$2 > at) {
      at = busy.last.$2;
      _advanceTo(at);
    }
    return at;
  }

  /// True when the link is idle at [t].
  bool idleAt(double t) => earliestIdle(t) == t;

  /// Our frame holds the link for [t, t + d). [t] must be an idle instant.
  void hold(double t, double d) {
    holds.add((t, t + d));
    _bgFree = math.max(_bgFree, t + d);
  }

  /// Busy periods overlapping [t0, t1). Call after the run: it lets the rest
  /// of the planned traffic happen.
  List<(double, double)> busyIn(double t0, double t1) {
    _advanceTo(t1);
    return <(double, double)>[
      for (final (double, double) b in busy)
        if (b.$2 > t0 && b.$1 < t1) b,
    ];
  }

  /// Share of [t0, t1) that other networks were on the air.
  double busyShare(double t0, double t1) {
    double sum = 0;
    for (final (double s, double e) in busyIn(t0, t1)) {
      sum += math.min(e, t1) - math.max(s, t0);
    }
    return sum / (t1 - t0);
  }
}

/// Frame arrival times: random (exponential gaps), seeded, microseconds.
List<double> mloArrivals(MloConfig c) {
  final math.Random rng = math.Random(c.seed * 31 + 7);
  final double meanGapUs = 1e6 / c.arrivalsPerSecond;
  final List<double> out = <double>[];
  double t = 0;
  for (int i = 0; i < c.frameCount; i++) {
    t += -meanGapUs * math.log(1 - rng.nextDouble());
    out.add(t);
  }
  return out;
}

// ── Results ─────────────────────────────────────────────────────────────────

/// One frame as sent.
class MloTx {
  const MloTx({
    required this.frame,
    required this.link,
    required this.arrivalUs,
    required this.startUs,
    required this.leadInUs,
    required this.airtimeUs,
    required this.endUs,
  });

  /// Frame number, 0-based, in arrival order.
  final int frame;

  /// Index into the run's links.
  final int link;

  final double arrivalUs;

  /// When the link was taken (the EMLSR lead-in starts here).
  final double startUs;

  /// EMLSR lead-in before the data (0 in other modes).
  final double leadInUs;

  /// The frame's own airtime.
  final double airtimeUs;

  /// When the link is released. Later than start + lead-in + airtime only
  /// for NSTR padding (aligned ends).
  final double endUs;

  double get dataStartUs => startUs + leadInUs;
  double get dataEndUs => dataStartUs + airtimeUs;

  /// NSTR padding after the data.
  double get paddingUs => endUs - dataEndUs;

  /// Arrival to the end of its own airtime.
  double get latencyUs => dataEndUs - arrivalUs;
}

/// One mode's run.
class MloModeResult {
  MloModeResult({
    required this.mode,
    required this.txs,
    required this.timelines,
    required this.lastArrivalUs,
    this.singleLink,
    this.fellBackToSingle = false,
  }) : sortedLatenciesUs = <double>[for (final MloTx t in txs) t.latencyUs]
         ..sort();

  final MloMode mode;

  /// Every frame, in frame order.
  final List<MloTx> txs;

  /// Each link as this mode saw it (its own deferrals), in config order.
  final List<MloLinkTimeline> timelines;

  final double lastArrivalUs;

  /// For a single-link run (or a fallback), the link it used.
  final int? singleLink;

  /// True when EMLSR was switched off by the driver, or there is one link.
  final bool fellBackToSingle;

  final List<double> sortedLatenciesUs;

  int get linkCount => timelines.length;

  double get meanUs =>
      sortedLatenciesUs.fold<double>(0, (double a, double b) => a + b) /
      sortedLatenciesUs.length;

  /// Nearest-rank percentile, 0 < p <= 100.
  double percentileUs(double p) {
    final int n = sortedLatenciesUs.length;
    final int rank = (p / 100 * n).ceil().clamp(1, n);
    return sortedLatenciesUs[rank - 1];
  }

  double get p99Us => percentileUs(99);

  /// Frames each link carried.
  List<int> get linkCounts {
    final List<int> out = List<int>.filled(linkCount, 0);
    for (final MloTx t in txs) {
      out[t.link]++;
    }
    return out;
  }

  /// More than 5 % of frames had not even started when the last frame
  /// arrived: the load is more than this mode can carry, and its latency
  /// grows with the length of the run.
  bool get overloaded {
    final int waiting = txs
        .where((MloTx t) => t.startUs > lastArrivalUs)
        .length;
    return waiting > txs.length * 0.05;
  }

  /// The frames that overlap [t0, t1).
  Iterable<MloTx> txsIn(double t0, double t1) =>
      txs.where((MloTx t) => t.endUs > t0 && t.startUs < t1);
}

/// A run of every mode over the same traffic.
class MloRun {
  MloRun._({
    required this.config,
    required this.arrivalsUs,
    required this.airtimeUs,
    required this.leadInUs,
    required this.singles,
    required this.modes,
  });

  final MloConfig config;
  final List<double> arrivalsUs;

  /// Frame airtime per link.
  final List<double> airtimeUs;

  /// EMLSR lead-in per link.
  final List<double> leadInUs;

  /// Single link on each link, in config order.
  final List<MloModeResult> singles;

  /// STR, NSTR and EMLSR.
  final Map<MloMode, MloModeResult> modes;

  int get linkCount => config.links.length;

  /// The single-link run with the lowest mean latency.
  MloModeResult get bestSingle => singles.reduce(
    (MloModeResult a, MloModeResult b) => b.meanUs < a.meanUs ? b : a,
  );

  MloModeResult result(MloMode m) =>
      m == MloMode.single ? bestSingle : modes[m]!;

  /// Mean latency of [m] over the best single link's. Below 1 is a win.
  double ratioToBestSingle(MloMode m) => result(m).meanUs / bestSingle.meanUs;

  /// True when [m]'s mean latency is higher than the best single link's.
  bool worseThanBestSingle(MloMode m) =>
      m != MloMode.single && result(m).meanUs > bestSingle.meanUs * (1 + 1e-9);

  /// True when [m]'s 99th percentile is higher than the best single link's.
  bool tailWorseThanBestSingle(MloMode m) =>
      m != MloMode.single && result(m).p99Us > bestSingle.p99Us * (1 + 1e-9);
}

// ── The engines ─────────────────────────────────────────────────────────────

class _Ctx {
  _Ctx(this.arrivals, this.traces, this.airtime, this.leadIn);

  final List<double> arrivals;
  final List<MloBusyTrace> traces;
  final List<double> airtime;
  final List<double> leadIn;

  int get n => traces.length;

  List<MloLinkTimeline> freshTimelines() => <MloLinkTimeline>[
    for (final MloBusyTrace t in traces) MloLinkTimeline(t),
  ];
}

MloModeResult _runSingle(
  _Ctx x,
  MloMode mode,
  int link, {
  bool fellBack = false,
}) {
  final List<MloLinkTimeline> tl = x.freshTimelines();
  final List<MloTx> txs = <MloTx>[];
  final double a = x.airtime[link];
  double free = 0;
  for (int i = 0; i < x.arrivals.length; i++) {
    final double s = tl[link].earliestIdle(math.max(x.arrivals[i], free));
    tl[link].hold(s, a);
    txs.add(
      MloTx(
        frame: i,
        link: link,
        arrivalUs: x.arrivals[i],
        startUs: s,
        leadInUs: 0,
        airtimeUs: a,
        endUs: s + a,
      ),
    );
    free = s + a;
  }
  return MloModeResult(
    mode: mode,
    txs: txs,
    timelines: tl,
    lastArrivalUs: x.arrivals.last,
    singleLink: link,
    fellBackToSingle: fellBack,
  );
}

/// STR: each link sends on its own; a frame takes whichever link is free
/// first (a tie goes to the shorter airtime, then the lower band).
MloModeResult _runStr(_Ctx x) {
  final List<MloLinkTimeline> tl = x.freshTimelines();
  final List<double> free = List<double>.filled(x.n, 0);
  final List<MloTx> txs = <MloTx>[];
  for (int i = 0; i < x.arrivals.length; i++) {
    int best = 0;
    double bestStart = double.infinity;
    for (int k = 0; k < x.n; k++) {
      final double s = tl[k].earliestIdle(math.max(x.arrivals[i], free[k]));
      if (s < bestStart || (s == bestStart && x.airtime[k] < x.airtime[best])) {
        best = k;
        bestStart = s;
      }
    }
    final double end = bestStart + x.airtime[best];
    tl[best].hold(bestStart, x.airtime[best]);
    txs.add(
      MloTx(
        frame: i,
        link: best,
        arrivalUs: x.arrivals[i],
        startUs: bestStart,
        leadInUs: 0,
        airtimeUs: x.airtime[best],
        endUs: end,
      ),
    );
    free[best] = end;
  }
  return MloModeResult(
    mode: MloMode.str,
    txs: txs,
    timelines: tl,
    lastArrivalUs: x.arrivals.last,
  );
}

/// NSTR: frames start together and end together. The first waiting frame
/// goes on whichever link is free first; at that same instant, frames
/// already waiting go on the other links that are idle, and every frame is
/// padded to the longest airtime. The next exchange starts after they end.
MloModeResult _runNstr(_Ctx x) {
  final List<MloLinkTimeline> tl = x.freshTimelines();
  final List<MloTx> txs = <MloTx>[];
  double free = 0;
  int i = 0;
  while (i < x.arrivals.length) {
    final double t0 = math.max(x.arrivals[i], free);
    int lead = 0;
    double t = double.infinity;
    for (int k = 0; k < x.n; k++) {
      final double s = tl[k].earliestIdle(t0);
      if (s < t || (s == t && x.airtime[k] < x.airtime[lead])) {
        lead = k;
        t = s;
      }
    }
    final List<int> used = <int>[lead];
    double len = x.airtime[lead];
    // Other links, shortest airtime first.
    final List<int> others = <int>[
      for (int k = 0; k < x.n; k++)
        if (k != lead) k,
    ]..sort((int a, int b) => x.airtime[a].compareTo(x.airtime[b]));
    int next = i + 1;
    for (final int k in others) {
      if (next >= x.arrivals.length || x.arrivals[next] > t) break;
      if (!tl[k].idleAt(t)) continue;
      used.add(k);
      len = math.max(len, x.airtime[k]);
      next++;
    }
    for (int j = 0; j < used.length; j++) {
      final int k = used[j];
      tl[k].hold(t, len);
      txs.add(
        MloTx(
          frame: i + j,
          link: k,
          arrivalUs: x.arrivals[i + j],
          startUs: t,
          leadInUs: 0,
          airtimeUs: x.airtime[k],
          endUs: t + len,
        ),
      );
    }
    free = t + len;
    i = next;
  }
  return MloModeResult(
    mode: MloMode.nstr,
    txs: txs,
    timelines: tl,
    lastArrivalUs: x.arrivals.last,
  );
}

/// EMLSR: one exchange at a time, on whichever link is free first; each
/// opens with the lead-in, and the next can start only after the
/// transition delay.
MloModeResult _runEmlsr(_Ctx x, double transitionUs) {
  final List<MloLinkTimeline> tl = x.freshTimelines();
  final List<MloTx> txs = <MloTx>[];
  double free = 0;
  for (int i = 0; i < x.arrivals.length; i++) {
    final double t0 = math.max(x.arrivals[i], free);
    int best = 0;
    double bestStart = double.infinity;
    for (int k = 0; k < x.n; k++) {
      final double s = tl[k].earliestIdle(t0);
      if (s < bestStart ||
          (s == bestStart &&
              x.leadIn[k] + x.airtime[k] < x.leadIn[best] + x.airtime[best])) {
        best = k;
        bestStart = s;
      }
    }
    final double block = x.leadIn[best] + x.airtime[best];
    tl[best].hold(bestStart, block);
    txs.add(
      MloTx(
        frame: i,
        link: best,
        arrivalUs: x.arrivals[i],
        startUs: bestStart,
        leadInUs: x.leadIn[best],
        airtimeUs: x.airtime[best],
        endUs: bestStart + block,
      ),
    );
    free = bestStart + block + transitionUs;
  }
  return MloModeResult(
    mode: MloMode.emlsr,
    txs: txs,
    timelines: tl,
    lastArrivalUs: x.arrivals.last,
  );
}

/// The link EMLSR falls back to when the driver switches it off: the
/// enabled link with the lowest busy fraction (the first on a tie).
int mloFallbackLink(MloConfig c) {
  int best = 0;
  for (int k = 1; k < c.links.length; k++) {
    if (c.links[k].busyFraction < c.links[best].busyFraction) best = k;
  }
  return best;
}

/// Runs single link (on every link), STR, NSTR and EMLSR over the same
/// random traffic.
MloRun simulateMlo(MloConfig c) {
  assert(c.links.isNotEmpty && c.links.length <= MloBand.values.length);
  final _Ctx x = _Ctx(
    mloArrivals(c),
    <MloBusyTrace>[
      for (final MloLinkConfig l in c.links) MloBusyTrace(l, c.seed),
    ],
    <double>[
      for (final MloLinkConfig l in c.links) mloFrameAirtimeUs(c, l.band),
    ],
    <double>[
      for (final MloLinkConfig l in c.links)
        mloEmlsrLeadInUs(l.band, c.paddingDelayUs),
    ],
  );
  final List<MloModeResult> singles = <MloModeResult>[
    for (int k = 0; k < x.n; k++) _runSingle(x, MloMode.single, k),
  ];
  final Map<MloMode, MloModeResult> modes = <MloMode, MloModeResult>{};
  if (x.n == 1) {
    for (final MloMode m in <MloMode>[
      MloMode.str,
      MloMode.nstr,
      MloMode.emlsr,
    ]) {
      modes[m] = _runSingle(x, m, 0, fellBack: true);
    }
  } else {
    modes[MloMode.str] = _runStr(x);
    modes[MloMode.nstr] = _runNstr(x);
    modes[MloMode.emlsr] = c.emlsrDisabledByDriver
        ? _runSingle(x, MloMode.emlsr, mloFallbackLink(c), fellBack: true)
        : _runEmlsr(x, c.transitionDelayUs.toDouble());
  }
  return MloRun._(
    config: c,
    arrivalsUs: x.arrivals,
    airtimeUs: x.airtime,
    leadInUs: x.leadIn,
    singles: singles,
    modes: modes,
  );
}

// ── Histogram ───────────────────────────────────────────────────────────────

/// Counts of [values] in [bins] equal bins on a log10 scale from [loUs] to
/// [hiUs]. Values outside the range land in the end bins.
List<int> mloLogHistogram(
  List<double> values,
  double loUs,
  double hiUs,
  int bins,
) {
  assert(loUs > 0 && hiUs > loUs && bins > 0);
  final double l0 = math.log(loUs) / math.ln10;
  final double l1 = math.log(hiUs) / math.ln10;
  final List<int> out = List<int>.filled(bins, 0);
  for (final double v in values) {
    final double lv = math.log(math.max(v, 1e-9)) / math.ln10;
    final int b = ((lv - l0) / (l1 - l0) * bins).floor().clamp(0, bins - 1);
    out[b]++;
  }
  return out;
}

/// A tidy log range that holds every value in [lists]: whole decades.
(double, double) mloHistogramRange(Iterable<List<double>> lists) {
  double lo = double.infinity;
  double hi = 0;
  for (final List<double> l in lists) {
    if (l.isEmpty) continue;
    lo = math.min(lo, l.first);
    hi = math.max(hi, l.last);
  }
  if (hi <= 0) return (10, 1000);
  final double d0 = (math.log(math.max(lo, 1)) / math.ln10).floorToDouble();
  double d1 = (math.log(hi) / math.ln10).ceilToDouble();
  if (d1 <= d0) d1 = d0 + 1;
  return (math.pow(10, d0).toDouble(), math.pow(10, d1).toDouble());
}

// ── Formatting ──────────────────────────────────────────────────────────────

/// A latency or duration: "240 us", "1.35 ms", "12.4 ms", "1.2 s".
String mloFmtUs(double us) {
  if (us < 1000) return '${us.round()} µs';
  final double ms = us / 1000;
  if (ms < 10) return '${ms.toStringAsFixed(2)} ms';
  if (ms < 1000) return '${ms.toStringAsFixed(1)} ms';
  return '${(ms / 1000).toStringAsFixed(2)} s';
}

/// An axis tick: trailing zeros trimmed, "100 µs", "1 ms", "20.5 ms", "1 s".
String mloFmtTick(double us) {
  String trim(double v) {
    String t = v.toStringAsFixed(2);
    t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return t;
  }

  if (us < 1000) return '${trim(us)} µs';
  if (us < 1e6) return '${trim(us / 1000)} ms';
  return '${trim(us / 1e6)} s';
}
