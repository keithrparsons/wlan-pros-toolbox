// Rate Adaptation model for the Wi-Fi Classroom (rate-adaptation).
//
// CLEAN-ROOM BUILD (2026-09-25) per myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/23-rate-adaptation.md, from
// the published Minstrel outline as summarized in
// Deliverables/2026-09-25-wifi-lab-wave3-research/brief.md section 8, and the
// ACK-timeout range in Deliverables/2026-09-25-wifi-lab-wave5-research/
// brief.md section 9. No driver source was read or copied: every rule below
// is the outline's sentence turned into code. Pure Dart, no Flutter imports,
// pinned by test/services/wifi_lab/rate_adaptation_model_test.dart.
//
// REUSED, NOT RE-DERIVED (spec 23):
//   - SNR each MCS needs: sensitivity (RateVsRangeMath.sensitivityTable) minus
//     the noise floor (RateVsRangeMath.noiseFloorDbm, 7 dB noise figure), the
//     way Rate vs Range computes it; the path is RateVsRangeMath.receivedDbm
//   - TXTIME, SIFS, slot, AIFS and the ACK: computeAirtime (airtime_anatomy)
//   - CW doubling: nextContentionWindow (medium_access_engine)
//
// THE LINK IS FIXED so the lesson is rate control, not PHY choice: 5 GHz,
// 802.11ax (HE SU), 20 MHz, one spatial stream, 0.8 us guard interval,
// 1500-byte frames, best effort, ACK at 24 Mbps. MCS 0 to 11, the range the
// airtime service carries for HE.
//
// TEACHING MODEL, labeled as such wherever it shows: the per-attempt success
// curve is a logistic in SNR that passes 90% at the SNR an MCS needs (the
// sensitivity table is defined at 10% packet error) and 10% about 4.4 dB
// lower. It is not a measured PER curve.
//
// Minstrel rules as the brief states them:
//   1. Statistics per rate, updated every 50 ms: the interval's success ratio
//      folds into an EWMA with 75% weight on history (a rate's first sample
//      is taken as is, since it has no history).
//   2. Throughput estimate = P(success) x bits / time for one attempt, with
//      rates under 10% success ignored and P capped at 90%.
//   3. About 10% of frames are sample frames sent at a random other rate.
//   4. Normal frames: best throughput -> second-best throughput -> best
//      probability -> lowest rate. Sample frames: random rate -> best
//      throughput -> best probability -> lowest; a sample rate slower than
//      the best-throughput rate goes second, so it is tried only on failure.
//   5. Retry limit 7 (dot11ShortRetryLimit) or 4 (dot11LongRetryLimit),
//      counted as transmission attempts, as the Medium Access engine does.
//
// TEACHING SIMPLIFICATIONS (stated in the help): attempts are split over the
// four chain stages as evenly as they go, earlier stages first (7 = 2, 2, 2,
// 1; 4 = 1, 1, 1, 1), rather than by a time budget; backoff is the mean
// (CW / 2 slots), not a draw; one station, no contention, no collisions.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'airtime_anatomy.dart';
import 'medium_access_engine.dart' show nextContentionWindow;
import 'rate_vs_range_math.dart';

// ── Fixed link ──────────────────────────────────────────────────────────────

abstract final class RaLink {
  /// Highest MCS offered: the top of the airtime service's HE table.
  static const int maxMcs = 11;

  static const int mcsCount = maxMcs + 1;

  /// The lowest rate, last in every retry chain.
  static const int lowestMcs = 0;

  static const int widthMHz = 20;
  static const int payloadBytes = 1500;
  static const int payloadBits = payloadBytes * 8;

  /// Path model for the presets, the Rate vs Range defaults: 5500 MHz, 20 dBm
  /// EIRP, 0 dBi client, path-loss exponent 3.
  static const double freqMHz = 5500;
  static const double eirpDbm = 20;
  static const double clientGainDbi = 0;
  static const double pathLossExponent = 3;

  /// The airtime scenario every attempt is timed with; only the MCS changes.
  static const AirtimeScenario scenario = AirtimeScenario(
    band: AirtimeBand.ghz5,
    phy: AirtimePhy.he,
    widthMhz: widthMHz,
    mcs: 0,
    streams: 1,
    guardInterval: GuardInterval.gi08,
    payloadBytes: payloadBytes,
    framesAggregated: 1,
    accessCategory: AirtimeAccessCategory.be,
    controlRateMbps: 24,
  );

  static final List<AirtimeResult> _airtime = <AirtimeResult>[
    for (int m = 0; m <= maxMcs; m++) computeAirtime(scenario.copyWith(mcs: m)),
  ];

  /// The airtime service's result for [mcs].
  static AirtimeResult airtime(int mcs) => _airtime[mcs];

  /// PHY data rate of [mcs], Mbps.
  static double phyRateMbps(int mcs) => _airtime[mcs].phyRateMbps;

  /// TXTIME of one 1500-byte frame at [mcs], microseconds.
  static double txTimeUs(int mcs) => _airtime[mcs].ppduUs;

  static int get sifsUs => _airtime[0].sifsUs;
  static int get slotUs => _airtime[0].slotUs;
  static int get cwMin => scenario.accessCategory.cwMin;
  static int get cwMax => scenario.accessCategory.cwMax;

  /// AIFS = SIFS + AIFSN x slot (43 us for best effort at 5 GHz).
  static double get aifsUs => (sifsUs + _airtime[0].aifsn * slotUs).toDouble();

  /// ACK duration at the control rate, microseconds.
  static double get ackUs => _airtime[0].ackUs;
}

// ── Rules ───────────────────────────────────────────────────────────────────

/// Retry limit: 7 for frames at or under the RTS threshold, 4 above it.
enum RaRetryLimit {
  short7('7 (short)', 7),
  long4('4 (long)', 4);

  const RaRetryLimit(this.label, this.attempts);

  final String label;

  /// Transmission attempts before the frame is dropped.
  final int attempts;
}

/// The airtime of one attempt, piece by piece, microseconds.
class RaAttemptCost {
  const RaAttemptCost({
    required this.aifsUs,
    required this.backoffUs,
    required this.txUs,
    required this.responseUs,
  });

  final double aifsUs;

  /// Mean backoff: CW / 2 slots.
  final double backoffUs;

  /// TXTIME at the attempt's MCS.
  final double txUs;

  /// SIFS + ACK when delivered, the ACK timeout when not.
  final double responseUs;

  double get waitUs => aifsUs + backoffUs;
  double get totalUs => aifsUs + backoffUs + txUs + responseUs;
}

/// The three rates the statistics pick.
class RaRanking {
  const RaRanking({
    required this.bestThroughput,
    required this.secondThroughput,
    required this.bestProbability,
  });

  final int bestThroughput;
  final int secondThroughput;
  final int bestProbability;

  @override
  bool operator ==(Object other) =>
      other is RaRanking &&
      other.bestThroughput == bestThroughput &&
      other.secondThroughput == secondThroughput &&
      other.bestProbability == bestProbability;

  @override
  int get hashCode =>
      Object.hash(bestThroughput, secondThroughput, bestProbability);
}

abstract final class RateAdaptationMath {
  /// Statistics update interval, microseconds (HZ/20, about 50 ms).
  static const double statsIntervalUs = 50000;

  /// EWMA weight on history (96/128).
  static const double defaultEwmaHistory = 0.75;

  /// Rates under this smoothed success are left out of the throughput
  /// ranking.
  static const double ignoreBelow = 0.10;

  /// Success probability is capped here in the throughput estimate.
  static const double probabilityCap = 0.90;

  /// Share of frames sent as sample frames.
  static const double defaultSamplingShare = 0.10;

  /// ACK timeout range at 5 GHz: SIFS + slot + 20 to 25 us. The standard's
  /// constant is not settled in the sources, so it is a labeled setting.
  static const double ackTimeoutMinUs = 45;
  static const double ackTimeoutMaxUs = 50;

  /// Width of the teaching success curve, dB.
  static const double curveScaleDb = 1.0;

  /// Distance below the needed SNR where the curve crosses 50%:
  /// scale x ln 9, so the curve is 90% at the needed SNR and 10% at twice
  /// this distance below it.
  static final double curveHalfOffsetDb = curveScaleDb * math.log(9);

  /// EWMA with [historyWeight] on [previous]. A rate with no history takes
  /// its first [sample] as is.
  static double ewma(double? previous, double sample, double historyWeight) {
    if (previous == null) return sample;
    return historyWeight * previous + (1 - historyWeight) * sample;
  }

  /// Receiver noise floor at 20 MHz with a 7 dB noise figure, dBm.
  static double noiseFloorDbm() => RateVsRangeMath.noiseFloorDbm(
    RaLink.widthMHz,
    RateVsRangeMath.defaultNoiseFigureDb,
  );

  /// SNR [mcs] needs: its 20 MHz sensitivity minus the noise floor, dB.
  static double requiredSnrDb(int mcs) =>
      RateVsRangeMath.sensitivityDbm(mcs, RaLink.widthMHz) - noiseFloorDbm();

  /// TEACHING MODEL. Chance one attempt at [mcs] is received at [snrDb]: a
  /// logistic that is 90% at [requiredSnrDb] (the sensitivity table is set
  /// at 10% packet error) and 10% about 4.4 dB lower.
  static double successProbability(double snrDb, int mcs) {
    final double mid = requiredSnrDb(mcs) - curveHalfOffsetDb;
    return 1 / (1 + math.exp(-(snrDb - mid) / curveScaleDb));
  }

  /// Highest MCS whose needed SNR is at or below [snrDb], or null.
  static int? supportedMcs(double snrDb) {
    int? best;
    for (int m = 0; m <= RaLink.maxMcs; m++) {
      if (snrDb >= requiredSnrDb(m)) best = m;
    }
    return best;
  }

  /// Contention window for attempt [attemptIndex] (0 = first try): CWmin,
  /// then the next value in the series per failure, up to CWmax.
  static int contentionWindow(int attemptIndex) {
    int cw = RaLink.cwMin;
    for (int i = 0; i < attemptIndex; i++) {
      cw = nextContentionWindow(cw, RaLink.cwMax);
    }
    return cw;
  }

  /// Mean backoff at [cw]: CW / 2 slots, microseconds.
  static double meanBackoffUs(int cw) => cw / 2 * RaLink.slotUs;

  /// Airtime of one attempt at [mcs], the [attemptIndex]th for its frame.
  static RaAttemptCost attemptCost({
    required int mcs,
    required int attemptIndex,
    required bool delivered,
    required double ackTimeoutUs,
  }) => RaAttemptCost(
    aifsUs: RaLink.aifsUs,
    backoffUs: meanBackoffUs(contentionWindow(attemptIndex)),
    txUs: RaLink.txTimeUs(mcs),
    responseUs: delivered ? RaLink.sifsUs + RaLink.ackUs : ackTimeoutUs,
  );

  /// Mean airtime of one attempt when it succeeds with [pSuccess].
  static double meanAttemptUs({
    required int mcs,
    required int attemptIndex,
    required double pSuccess,
    required double ackTimeoutUs,
  }) {
    final double ok = attemptCost(
      mcs: mcs,
      attemptIndex: attemptIndex,
      delivered: true,
      ackTimeoutUs: ackTimeoutUs,
    ).totalUs;
    final double lost = attemptCost(
      mcs: mcs,
      attemptIndex: attemptIndex,
      delivered: false,
      ackTimeoutUs: ackTimeoutUs,
    ).totalUs;
    return pSuccess * ok + (1 - pSuccess) * lost;
  }

  /// Time for one successful first attempt at [mcs], microseconds.
  static double oneAttemptUs(int mcs) => attemptCost(
    mcs: mcs,
    attemptIndex: 0,
    delivered: true,
    ackTimeoutUs: ackTimeoutMinUs,
  ).totalUs;

  /// Throughput estimate, Mbps: min(P, 90%) x bits / one attempt. Zero for
  /// an untried rate or one under 10% success.
  static double throughputEstimateMbps(double? p, int mcs) {
    if (p == null || p < ignoreBelow) return 0;
    return math.min(p, probabilityCap) * RaLink.payloadBits / oneAttemptUs(mcs);
  }

  /// Best throughput, second-best throughput and best probability from the
  /// smoothed success of every rate ([probs], null = untried). Ties go to the
  /// lower MCS for throughput (so an all-untried table starts at MCS 0) and
  /// to the higher throughput estimate for probability.
  static RaRanking rank(List<double?> probs) {
    final List<double> tp = <double>[
      for (int m = 0; m < probs.length; m++)
        throughputEstimateMbps(probs[m], m),
    ];
    int best = 0;
    for (int m = 1; m < tp.length; m++) {
      if (tp[m] > tp[best]) best = m;
    }
    int second = best == 0 ? 1 : 0;
    for (int m = 0; m < tp.length; m++) {
      if (m == best) continue;
      if (tp[m] > tp[second]) second = m;
    }
    int bestP = 0;
    double pOf(int m) => probs[m] ?? -1;
    for (int m = 1; m < probs.length; m++) {
      if (pOf(m) > pOf(bestP) || (pOf(m) == pOf(bestP) && tp[m] > tp[bestP])) {
        bestP = m;
      }
    }
    return RaRanking(
      bestThroughput: best,
      secondThroughput: second,
      bestProbability: bestP,
    );
  }

  /// The four-stage retry chain. Normal frames: best throughput, second
  /// best, best probability, lowest. A sample frame puts [sampleMcs] first,
  /// or second when it is slower than the best-throughput rate.
  static List<int> retryChain(RaRanking r, {int? sampleMcs}) {
    if (sampleMcs == null) {
      return <int>[
        r.bestThroughput,
        r.secondThroughput,
        r.bestProbability,
        RaLink.lowestMcs,
      ];
    }
    final bool slower =
        RaLink.phyRateMbps(sampleMcs) < RaLink.phyRateMbps(r.bestThroughput);
    return slower
        ? <int>[
            r.bestThroughput,
            sampleMcs,
            r.bestProbability,
            RaLink.lowestMcs,
          ]
        : <int>[
            sampleMcs,
            r.bestThroughput,
            r.bestProbability,
            RaLink.lowestMcs,
          ];
  }

  /// [limit] attempts over [stages] chain stages, as evenly as they go,
  /// earlier stages first.
  static List<int> attemptsPerStage(int limit, [int stages = 4]) {
    final int base = limit ~/ stages;
    final int extra = limit % stages;
    return <int>[for (int i = 0; i < stages; i++) base + (i < extra ? 1 : 0)];
  }
}

// ── Paths ───────────────────────────────────────────────────────────────────

/// Where the client is over time.
enum RaPath {
  walk('Walk away and back'),
  steady('Steady'),
  fading('Fading');

  const RaPath(this.label);

  final String label;

  /// Length of one walk out and back, seconds.
  static const double walkPeriodS = 20;
  static const double walkNearM = 2;
  static const double walkFarM = 60;
  static const double steadyM = 4;
  static const double fadingM = 12;

  /// Client distance at [tS] seconds.
  double distanceM(double tS) {
    switch (this) {
      case RaPath.walk:
        final double half = walkPeriodS / 2;
        final double ph = tS % walkPeriodS;
        final double f = ph < half ? ph / half : (walkPeriodS - ph) / half;
        return walkNearM + (walkFarM - walkNearM) * f;
      case RaPath.steady:
        return steadyM;
      case RaPath.fading:
        return fadingM;
    }
  }

  /// Illustrative fading, dB: two slow swells, up to about 8 dB either way.
  double fadeDb(double tS) {
    if (this != RaPath.fading) return 0;
    return 5 * math.sin(2 * math.pi * 0.9 * tS) +
        3 * math.sin(2 * math.pi * 2.3 * tS + 1.3);
  }

  /// Received power at [tS], dBm, before fading and offset.
  double receivedDbm(double tS) => RateVsRangeMath.receivedDbm(
    eirpDbm: RaLink.eirpDbm,
    clientGainDbi: RaLink.clientGainDbi,
    distanceM: distanceM(tS),
    freqMHz: RaLink.freqMHz,
    exponent: RaLink.pathLossExponent,
  );

  /// SNR at [tS] with [offsetDb] added, dB.
  double snrDb(double tS, double offsetDb) =>
      receivedDbm(tS) -
      RateAdaptationMath.noiseFloorDbm() +
      fadeDb(tS) +
      offsetDb;
}

// ── Settings ────────────────────────────────────────────────────────────────

class RaSettings {
  const RaSettings({
    this.path = RaPath.walk,
    this.snrOffsetDb = 0,
    this.samplingShare = RateAdaptationMath.defaultSamplingShare,
    this.ewmaHistory = RateAdaptationMath.defaultEwmaHistory,
    this.retryChain = true,
    this.retryLimit = RaRetryLimit.short7,
    this.ackTimeoutUs = RateAdaptationMath.ackTimeoutMinUs,
  });

  final RaPath path;
  final double snrOffsetDb;

  /// 0 to 1.
  final double samplingShare;

  /// 0 to 1: weight on history in the EWMA.
  final double ewmaHistory;

  /// Off: every attempt of a frame stays at its first rate.
  final bool retryChain;
  final RaRetryLimit retryLimit;
  final double ackTimeoutUs;

  RaSettings copyWith({
    RaPath? path,
    double? snrOffsetDb,
    double? samplingShare,
    double? ewmaHistory,
    bool? retryChain,
    RaRetryLimit? retryLimit,
    double? ackTimeoutUs,
  }) => RaSettings(
    path: path ?? this.path,
    snrOffsetDb: snrOffsetDb ?? this.snrOffsetDb,
    samplingShare: samplingShare ?? this.samplingShare,
    ewmaHistory: ewmaHistory ?? this.ewmaHistory,
    retryChain: retryChain ?? this.retryChain,
    retryLimit: retryLimit ?? this.retryLimit,
    ackTimeoutUs: ackTimeoutUs ?? this.ackTimeoutUs,
  );

  @override
  bool operator ==(Object other) =>
      other is RaSettings &&
      other.path == path &&
      other.snrOffsetDb == snrOffsetDb &&
      other.samplingShare == samplingShare &&
      other.ewmaHistory == ewmaHistory &&
      other.retryChain == retryChain &&
      other.retryLimit == retryLimit &&
      other.ackTimeoutUs == ackTimeoutUs;

  @override
  int get hashCode => Object.hash(
    path,
    snrOffsetDb,
    samplingShare,
    ewmaHistory,
    retryChain,
    retryLimit,
    ackTimeoutUs,
  );
}

// ── Run records ─────────────────────────────────────────────────────────────

/// One transmission attempt.
class RaAttempt {
  const RaAttempt({
    required this.startUs,
    required this.cost,
    required this.mcs,
    required this.delivered,
    required this.attemptIndex,
    required this.cw,
    required this.isSample,
    required this.snrDb,
  });

  final double startUs;
  final RaAttemptCost cost;
  final int mcs;
  final bool delivered;

  /// 0 for the first try, 1 for the first retry, and so on.
  final int attemptIndex;
  final int cw;

  /// True when this attempt is at a sample frame's sample rate.
  final bool isSample;
  final double snrDb;

  double get endUs => startUs + cost.totalUs;
  double get txStartUs => startUs + cost.waitUs;
  double get txEndUs => txStartUs + cost.txUs;
  bool get isRetry => attemptIndex > 0;
}

/// One frame and every attempt it took.
class RaFrame {
  const RaFrame({
    required this.attempts,
    required this.delivered,
    required this.isSample,
    required this.sampleMcs,
    required this.chain,
  });

  final List<RaAttempt> attempts;
  final bool delivered;
  final bool isSample;
  final int? sampleMcs;

  /// The four-stage chain this frame used.
  final List<int> chain;

  double get startUs => attempts.first.startUs;
  double get endUs => attempts.last.endUs;
  double get airtimeUs => endUs - startUs;
  int get retries => attempts.length - 1;

  double get retryAirtimeUs => attempts
      .where((RaAttempt a) => a.isRetry)
      .fold<double>(0, (double s, RaAttempt a) => s + a.cost.totalUs);
}

/// One statistics update: what the rate control chose, and on what evidence.
class RaUpdate {
  const RaUpdate({
    required this.timeUs,
    required this.ranking,
    required this.snrDb,
    required this.supportedMcs,
    required this.attempted,
    required this.sampled,
  });

  final double timeUs;
  final RaRanking ranking;
  final double snrDb;
  final int? supportedMcs;

  /// Rates with at least one attempt in the interval just closed.
  final Set<int> attempted;

  /// Rates tried as the sample rate of a sample frame in that interval.
  final Set<int> sampled;
}

/// Per-rate statistics.
class RaRateStats {
  RaRateStats(this.mcs);

  final int mcs;

  /// Smoothed success probability, null until the rate has been tried.
  double? ewma;

  int intervalAttempts = 0;
  int intervalSuccesses = 0;
  int totalAttempts = 0;
  int totalSuccesses = 0;

  /// Success ratio of the last closed interval with attempts, if any.
  double? lastSample;

  bool get ignored => ewma != null && ewma! < RateAdaptationMath.ignoreBelow;

  double get throughputEstimateMbps =>
      RateAdaptationMath.throughputEstimateMbps(ewma, mcs);
}

/// Rolling figures over the last [RateAdaptationEngine.readoutWindowUs].
class RaWindowStats {
  const RaWindowStats({
    required this.spanUs,
    required this.frames,
    required this.delivered,
    required this.attempts,
    required this.airtimeUs,
    required this.retryAirtimeUs,
  });

  final double spanUs;
  final int frames;
  final int delivered;
  final int attempts;
  final double airtimeUs;
  final double retryAirtimeUs;

  /// Delivered payload over the span, Mbps.
  double get deliveredMbps =>
      spanUs <= 0 ? 0 : delivered * RaLink.payloadBits / spanUs;

  /// Retries per frame.
  double get retriesPerFrame => frames == 0 ? 0 : (attempts - frames) / frames;

  /// Share of airtime spent on retries, 0 to 1.
  double get retryAirtimeShare =>
      airtimeUs <= 0 ? 0 : retryAirtimeUs / airtimeUs;

  /// Frames dropped at the retry limit.
  int get dropped => frames - delivered;
}

// ── Engine ──────────────────────────────────────────────────────────────────

/// Deterministic, frame-by-frame Minstrel-style rate control over one link.
/// Same settings, same seed, same run.
class RateAdaptationEngine {
  RateAdaptationEngine({
    this.settings = const RaSettings(),
    this.seed = 1,
    this.snrOverride,
  }) : _random = math.Random(seed) {
    _ranking = RateAdaptationMath.rank(_probs);
  }

  final int seed;

  /// Test seam: SNR in dB as a function of time in microseconds, in place of
  /// the path.
  final double Function(double tUs)? snrOverride;
  final math.Random _random;

  /// Applies to the running link from the next frame on.
  RaSettings settings;

  /// How long attempts are kept for the stage strip, microseconds.
  static const double attemptKeepUs = 200000;

  /// Readout window, microseconds.
  static const double readoutWindowUs = 1000000;

  /// Rate history kept, microseconds (one walk out and back).
  static const double historyKeepUs = RaPath.walkPeriodS * 1e6;

  /// Frames processed per [advanceBy] call at most, so a large jump cannot
  /// stall a frame.
  static const int maxFramesPerAdvance = 200000;

  final List<RaRateStats> stats = <RaRateStats>[
    for (int m = 0; m <= RaLink.maxMcs; m++) RaRateStats(m),
  ];

  double _nowUs = 0;
  double _nextUpdateUs = RateAdaptationMath.statsIntervalUs;
  late RaRanking _ranking;
  final Set<int> _intervalSampled = <int>{};

  final List<RaAttempt> _attempts = <RaAttempt>[];
  final List<RaFrame> _frames = <RaFrame>[];
  final List<RaUpdate> _history = <RaUpdate>[];
  RaFrame? _lastFrame;

  int totalFrames = 0;
  int totalDelivered = 0;
  int totalAttempts = 0;

  double get nowUs => _nowUs;
  RaRanking get ranking => _ranking;
  RaFrame? get lastFrame => _lastFrame;

  /// Attempts from the last [attemptKeepUs], oldest first.
  List<RaAttempt> get attempts => List<RaAttempt>.unmodifiable(_attempts);

  /// Statistics updates from the last [historyKeepUs], oldest first.
  List<RaUpdate> get history => List<RaUpdate>.unmodifiable(_history);

  List<double?> get _probs => <double?>[
    for (final RaRateStats s in stats) s.ewma,
  ];

  /// SNR at [tUs].
  double snrAt(double tUs) =>
      snrOverride?.call(tUs) ??
      settings.path.snrDb(tUs / 1e6, settings.snrOffsetDb);

  double get snrNowDb => snrAt(_nowUs);

  double get distanceNowM => settings.path.distanceM(_nowUs / 1e6);

  /// Figures over the last second (or since the start, if shorter).
  RaWindowStats get window {
    final double from = _nowUs - readoutWindowUs;
    int frames = 0, delivered = 0, attempts = 0;
    double air = 0, retryAir = 0;
    for (final RaFrame f in _frames) {
      if (f.endUs <= from) continue;
      frames++;
      if (f.delivered) delivered++;
      attempts += f.attempts.length;
      air += f.airtimeUs;
      retryAir += f.retryAirtimeUs;
    }
    return RaWindowStats(
      spanUs: math.min(_nowUs, readoutWindowUs),
      frames: frames,
      delivered: delivered,
      attempts: attempts,
      airtimeUs: air,
      retryAirtimeUs: retryAir,
    );
  }

  /// Run whole frames until the clock has moved at least [us].
  void advanceBy(double us) {
    final double target = _nowUs + us;
    int n = 0;
    while (_nowUs < target && n < maxFramesPerAdvance) {
      stepFrame();
      n++;
    }
  }

  /// Run one frame, retries included.
  RaFrame stepFrame() {
    _runUpdates();
    final RaSettings s = settings;

    int? sampleMcs;
    if (s.samplingShare > 0 && _random.nextDouble() < s.samplingShare) {
      final List<int> others = <int>[
        for (int m = 0; m <= RaLink.maxMcs; m++)
          if (m != _ranking.bestThroughput) m,
      ];
      sampleMcs = others[_random.nextInt(others.length)];
      _intervalSampled.add(sampleMcs);
    }

    final List<int> chain = RateAdaptationMath.retryChain(
      _ranking,
      sampleMcs: sampleMcs,
    );
    final List<int> perStage = s.retryChain
        ? RateAdaptationMath.attemptsPerStage(s.retryLimit.attempts)
        : <int>[s.retryLimit.attempts, 0, 0, 0];

    final List<RaAttempt> tries = <RaAttempt>[];
    bool delivered = false;
    int k = 0;
    outer:
    for (int stage = 0; stage < chain.length; stage++) {
      for (int j = 0; j < perStage[stage]; j++) {
        final int mcs = chain[stage];
        final double snr = snrAt(_nowUs);
        final double p = RateAdaptationMath.successProbability(snr, mcs);
        final bool ok = _random.nextDouble() < p;
        final RaAttemptCost cost = RateAdaptationMath.attemptCost(
          mcs: mcs,
          attemptIndex: k,
          delivered: ok,
          ackTimeoutUs: s.ackTimeoutUs,
        );
        final RaAttempt a = RaAttempt(
          startUs: _nowUs,
          cost: cost,
          mcs: mcs,
          delivered: ok,
          attemptIndex: k,
          cw: RateAdaptationMath.contentionWindow(k),
          isSample: sampleMcs != null && mcs == sampleMcs,
          snrDb: snr,
        );
        tries.add(a);
        _attempts.add(a);
        final RaRateStats st = stats[mcs];
        st.intervalAttempts++;
        st.totalAttempts++;
        if (ok) {
          st.intervalSuccesses++;
          st.totalSuccesses++;
        }
        _nowUs = a.endUs;
        k++;
        if (ok) {
          delivered = true;
          break outer;
        }
      }
    }

    final RaFrame f = RaFrame(
      attempts: tries,
      delivered: delivered,
      isSample: sampleMcs != null,
      sampleMcs: sampleMcs,
      chain: chain,
    );
    _frames.add(f);
    _lastFrame = f;
    totalFrames++;
    totalAttempts += tries.length;
    if (delivered) totalDelivered++;
    _trim();
    return f;
  }

  void _runUpdates() {
    while (_nowUs >= _nextUpdateUs) {
      final Set<int> attempted = <int>{};
      for (final RaRateStats st in stats) {
        if (st.intervalAttempts == 0) continue;
        attempted.add(st.mcs);
        final double sample = st.intervalSuccesses / st.intervalAttempts;
        st.lastSample = sample;
        st.ewma = RateAdaptationMath.ewma(
          st.ewma,
          sample,
          settings.ewmaHistory,
        );
        st.intervalAttempts = 0;
        st.intervalSuccesses = 0;
      }
      _ranking = RateAdaptationMath.rank(_probs);
      final double snr = snrAt(_nextUpdateUs);
      _history.add(
        RaUpdate(
          timeUs: _nextUpdateUs,
          ranking: _ranking,
          snrDb: snr,
          supportedMcs: RateAdaptationMath.supportedMcs(snr),
          attempted: attempted,
          sampled: Set<int>.of(_intervalSampled),
        ),
      );
      _intervalSampled.clear();
      _nextUpdateUs += RateAdaptationMath.statsIntervalUs;
    }
  }

  void _trim() {
    final double a = _nowUs - attemptKeepUs;
    int i = 0;
    while (i < _attempts.length && _attempts[i].endUs < a) {
      i++;
    }
    if (i > 0) _attempts.removeRange(0, i);
    final double f = _nowUs - readoutWindowUs;
    i = 0;
    while (i < _frames.length && _frames[i].endUs < f) {
      i++;
    }
    if (i > 0) _frames.removeRange(0, i);
    final double h = _nowUs - historyKeepUs;
    i = 0;
    while (i < _history.length && _history[i].timeUs < h) {
      i++;
    }
    if (i > 0) _history.removeRange(0, i);
  }
}
