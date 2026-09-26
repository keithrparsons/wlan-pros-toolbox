// Band Steering engine (Wi-Fi Classroom, 2026-09-27).
//
// Pure Dart, no Flutter imports. Built clean-room per myPKA Deliverables/
// 2026-09-25-wifi-lab-cleanroom/specs/38-band-steering.md, values from the
// wave 4 research brief (brief-GKL.md, section K). Same config, same walk:
// nothing here is random.
//
// THE LESSON. The client chooses the band. The AP can only hide (stop
// answering broadcast probe requests on 2.4 GHz), refuse (reject
// authentication on 2.4 GHz) or suggest (send a BSS Transition Management
// request naming the 5 GHz network). None of the three stops the 2.4 GHz
// beacons.
//
// SIGNAL. Roaming Walk's log-distance model (roaming_walk_engine.dart,
// RoamWalkConfig.meanRssiAtDistance), through FsplMath.logDistanceDb:
//   RSSI(band, d) = EIRP - [FSPL(1 m, f) + 10 n log10(d)] - extra(band)
// with the same illustrative EIRP (14 dBm) and exponent (3.0) Roaming Walk
// defaults to, on both bands. The frequency term alone makes 5 GHz (5500 MHz)
// 20 log10(5500 / 2437) = 7.07 dB weaker than 2.4 GHz (2437 MHz) at every
// distance; the extra 5 GHz wall loss (illustrative, default 3 dB) adds to it.
// No shadow fading: the walk is deterministic.
//
// CLIENT RULES (sources are named here, in code comments only; the UI says
// Client A, B and C, Keith's rule of 2026-09-26):
//   Client A: Apple, "Wi-Fi roaming support in Apple devices" (updated
//     2024-09-25). Looks for another AP only below -70 dBm; a candidate must
//     be 8 dB stronger while transmitting (12 dB idle; this tool uses 8). No
//     band rule; ranks by generation, width, utilization and client count.
//     MODEL CHOICE (illustrative): at join it takes 5 GHz, the wider channel,
//     when 5 GHz is at or above -70 dBm, else the stronger band; it accepts a
//     transition request when the named 5 GHz network is at or above -70 dBm.
//   Client B: AOSP, "Wi-Fi network selection". Entry -80 dBm on 2.4 GHz,
//     -77 dBm on 5 GHz; no re-selection while the link is above -73 dBm
//     (2.4) or -70 dBm (5); scores by a throughput estimate plus a bonus for
//     the current network. MODEL CHOICE (illustrative): the estimate is the
//     Shannon limit of the channel (20 MHz on 2.4, 80 MHz on 5) at the RSSI
//     capped at -73 / -70 dBm, over thermal noise plus a 7 dB noise figure;
//     the current network's score is multiplied by 1.2. It accepts a
//     transition request when 5 GHz passes its -77 dBm entry threshold.
//   Client C: Microsoft Learn, fast roaming with 802.11k/v/r (2025), which
//     publishes BSS Transition Management support and no band rule. Band
//     choice modeled as strongest signal at join; no leaving rule; accepts a
//     transition request when it can hear 5 GHz, if its driver supports it.
//
// AP MECHANISMS (hostapd.conf, P-impl in the brief; UI says "one open-source
// implementation"): dual-band tracking by the same MAC address seen in probe
// requests on both radios (track_sta_max_num); no_probe_resp_if_seen_on
// (broadcast probes only; directed probes still answered); no_auth_if_seen_on
// (authentication, not association). How many refusals a client tolerates is
// not published: an illustrative slider, after which the AP lets it in.
// Transition request answers: status 0 accept, 7 "no suitable candidates"
// (hostapd enum bss_trans_mgmt_status_code; Microsoft WDI enum).
//
// NOT MODELED: forcing a client off with a deauthentication. No primary
// source describing it was found (spec 38; default by Larry pending Keith).
//
// SIMPLIFICATIONS (each also stated in the UI or help):
//   - The client walks a straight line, one sample per meter.
//   - The link is symmetric: the AP hears the client on a band exactly when
//     the client hears the AP there (at or above the -82 dBm hearing floor,
//     illustrative).
//   - A scan sends one broadcast probe per band, 5 GHz first, and the AP's
//     tracker remembers a 5 GHz sighting for the rest of the walk. Only
//     probe requests feed the tracker, and with the random-address toggle on
//     every probe comes from a random address, so the tracker never matches
//     the client.
//   - A refused client tries its next acceptable band in the same moment;
//     with none, it tries 2.4 GHz again at the next sample.
//   - The AP sends a transition request right after the client associates on
//     2.4 GHz and again every 5 samples while it stays there (illustrative).
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'fspl_math.dart';

// ── Constants ───────────────────────────────────────────────────────────────

/// AP EIRP on both bands, dBm. Illustrative, Roaming Walk's default.
const double kBsEirpDbm = 14;

/// Log-distance path-loss exponent. Illustrative, Roaming Walk's default.
const double kBsExponent = 3.0;

/// Below this a client cannot hear the AP (and the AP cannot hear it), dBm.
/// Illustrative.
const double kBsHearFloorDbm = -82;

/// The edge of the walk, meters from the AP.
const double kBsEdgeM = 55;

/// The near end of the walk, meters from the AP.
const double kBsNearM = 2;

/// One sample per meter walked.
const double kBsStepM = 1;

/// Extra 5 GHz wall loss slider, dB.
const double kBsMinExtraLossDb = 0;
const double kBsMaxExtraLossDb = 10;
const double kBsDefaultExtraLossDb = 3;

/// Refusal tolerance slider (not published anywhere: illustrative).
const int kBsMinTolerance = 1;
const int kBsMaxTolerance = 10;
const int kBsDefaultTolerance = 3;

/// The AP repeats a transition request every this many samples while the
/// client stays on 2.4 GHz. Illustrative.
const int kBsBtmRepeatSteps = 5;

/// Client A (published): looks for another AP below this, dBm.
const double kClientALookDbm = -70;

/// Client A (published): a roam candidate must be this much stronger while
/// transmitting, dB.
const double kClientADeltaDb = 8;

/// Client A (published): the same margin when idle, dB. Shown, not used.
const double kClientAIdleDeltaDb = 12;

/// Client B's current-network bonus, as a score multiplier. Illustrative:
/// the published rule has a bonus, not this size.
const double kClientBCurrentBonus = 1.2;

/// Receiver noise figure for the throughput estimate, dB. Illustrative.
const double kBsNoiseFigureDb = 7;

/// BSS Transition Management status codes the tool uses.
const int kBtmStatusAccept = 0;
const int kBtmStatusNoSuitableCandidates = 7;

// ── Enums ───────────────────────────────────────────────────────────────────

enum BsBand {
  ghz24('2.4 GHz', 2437, 20),
  ghz5('5 GHz', 5500, 80);

  const BsBand(this.label, this.freqMHz, this.widthMHz);

  final String label;

  /// Center frequency used for the path loss.
  final double freqMHz;

  /// Channel width in this model (illustrative: 20 MHz on 2.4, 80 on 5).
  final int widthMHz;

  BsBand get other => this == ghz24 ? ghz5 : ghz24;
}

/// What the AP does to push a dual-band client toward 5 GHz.
enum SteeringMode {
  off('Off'),
  probeSuppression('Probe suppression on 2.4 GHz'),
  authRefusal('Authentication refusal on 2.4 GHz'),
  transitionRequest('Transition request (802.11v amendment)');

  const SteeringMode(this.label);

  final String label;
}

enum ClientProfile {
  a('Client A'),
  b('Client B'),
  c('Client C');

  const ClientProfile(this.label);

  final String label;

  /// The letter drawn on the client dot.
  String get letter => label.substring(label.length - 1);
}

enum WalkPath {
  edgeToAp('Edge to AP'),
  apToEdge('AP to edge');

  const WalkPath(this.label);

  final String label;
}

// ── Signal ──────────────────────────────────────────────────────────────────

/// Received level at [distanceM] on [band], dBm. [extra5LossDb] applies to
/// 5 GHz only. Distances under 1 m are taken as 1 m.
double bsRssiDbm(BsBand band, double distanceM, {double extra5LossDb = 0}) {
  final double d = math.max(distanceM, 1.0);
  return FsplMath.receivedPowerDbm(
    txPowerDbm: kBsEirpDbm,
    txGainDbi: 0,
    rxGainDbi: 0,
    pathLossDb: FsplMath.logDistanceDb(d, band.freqMHz, kBsExponent),
    otherLossesDb: band == BsBand.ghz5 ? extra5LossDb : 0,
  );
}

/// Distance at which [band] falls to [levelDbm]: a ring's radius, meters.
double bsRangeM(BsBand band, double levelDbm, {double extra5LossDb = 0}) {
  final double atOneM = bsRssiDbm(band, 1, extra5LossDb: extra5LossDb);
  return math.pow(10, (atOneM - levelDbm) / (10 * kBsExponent)).toDouble();
}

/// How much weaker 5 GHz is than 2.4 GHz in free space at any distance, dB:
/// 20 log10(5500 / 2437).
double get bsFreeSpaceGapDb =>
    FsplMath.bandDifferenceDb(BsBand.ghz24.freqMHz, BsBand.ghz5.freqMHz);

bool bsHears(double rssiDbm) => rssiDbm >= kBsHearFloorDbm;

// ── Client rules ────────────────────────────────────────────────────────────

/// Client B's published entry threshold on [band], dBm.
double clientBEntryDbm(BsBand band) => band == BsBand.ghz24 ? -80 : -77;

/// Client B's published "sufficient" level on [band], dBm: no re-selection
/// while the current link is above it.
double clientBSufficientDbm(BsBand band) => band == BsBand.ghz24 ? -73 : -70;

/// The level on [band] below which [p] looks for another network, or null
/// when it publishes none.
double? lookThresholdDbm(ClientProfile p, BsBand band) => switch (p) {
  ClientProfile.a => kClientALookDbm,
  ClientProfile.b => clientBSufficientDbm(band),
  ClientProfile.c => null,
};

/// The level on [band] a network must reach before [p] will join it, or null
/// when it publishes none (then only the hearing floor applies).
double? entryThresholdDbm(ClientProfile p, BsBand band) =>
    p == ClientProfile.b ? clientBEntryDbm(band) : null;

/// True when [p], associated on [band] at [rssiDbm], looks for (or
/// re-selects) another network. Client A scans below -70 dBm; Client B
/// re-runs selection at or below -73 dBm on 2.4 GHz and -70 dBm on 5 GHz;
/// Client C publishes no rule, and this model never has it look.
bool looksForAnother(ClientProfile p, BsBand band, double rssiDbm) {
  switch (p) {
    case ClientProfile.a:
      return rssiDbm < kClientALookDbm;
    case ClientProfile.b:
      return !(rssiDbm > clientBSufficientDbm(band));
    case ClientProfile.c:
      return false;
  }
}

/// True when [p] will consider joining [band] at [rssiDbm].
bool passesEntry(ClientProfile p, BsBand band, double rssiDbm) {
  if (!bsHears(rssiDbm)) return false;
  final double? entry = entryThresholdDbm(p, band);
  return entry == null || rssiDbm >= entry;
}

/// Client B's throughput estimate, Mb/s (illustrative model): the Shannon
/// limit of the band's channel width at the RSSI capped at the "sufficient"
/// level, over thermal noise (-174 dBm/Hz) plus [kBsNoiseFigureDb].
double throughputEstimateMbps(BsBand band, double rssiDbm) {
  final double capped = math.min(rssiDbm, clientBSufficientDbm(band));
  final double bwHz = band.widthMHz * 1e6;
  final double noiseDbm = -174 + 10 * FsplMath.log10(bwHz) + kBsNoiseFigureDb;
  final double snr = math.pow(10, (capped - noiseDbm) / 10).toDouble();
  return bwHz * (math.log(1 + snr) / math.ln2) / 1e6;
}

/// The bands [p] would try, best first, given what it hears. [current] is
/// the band it is on, if any (Client B's bonus).
List<BsBand> joinPreference(
  ClientProfile p, {
  required double rssi24,
  required double rssi5,
  BsBand? current,
}) {
  double rssi(BsBand b) => b == BsBand.ghz24 ? rssi24 : rssi5;
  final List<BsBand> ok = <BsBand>[
    for (final BsBand b in BsBand.values)
      if (passesEntry(p, b, rssi(b))) b,
  ];
  switch (p) {
    case ClientProfile.a:
      // Wider 5 GHz channel wins when it is at or above -70 dBm (model
      // choice); otherwise the stronger band.
      ok.sort((BsBand x, BsBand y) {
        final bool x5 = x == BsBand.ghz5 && rssi(x) >= kClientALookDbm;
        final bool y5 = y == BsBand.ghz5 && rssi(y) >= kClientALookDbm;
        if (x5 != y5) return x5 ? -1 : 1;
        return rssi(y).compareTo(rssi(x));
      });
    case ClientProfile.b:
      double score(BsBand b) =>
          throughputEstimateMbps(b, rssi(b)) *
          (b == current ? kClientBCurrentBonus : 1);
      ok.sort((BsBand x, BsBand y) => score(y).compareTo(score(x)));
    case ClientProfile.c:
      ok.sort((BsBand x, BsBand y) => rssi(y).compareTo(rssi(x)));
  }
  return ok;
}

/// The AP's answer rule for a probe request (spec 38). Under probe
/// suppression the AP stays silent only to a BROADCAST probe on 2.4 GHz from
/// a client its tracker has seen on 5 GHz. Directed probes are answered.
bool apAnswersProbe({
  required SteeringMode mode,
  required BsBand band,
  required bool directed,
  required bool trackedOn5,
}) {
  if (mode != SteeringMode.probeSuppression) return true;
  if (band != BsBand.ghz24) return true;
  if (directed) return true;
  return !trackedOn5;
}

/// Beacons go out on both bands in every mode. Kept as a function so the
/// test states it against the mode list.
bool apSendsBeacon(SteeringMode mode, BsBand band) => true;

/// How a client answers a transition request naming 5 GHz.
class BtmAnswer {
  const BtmAnswer({required this.status, required this.answered});

  /// No answer at all: the client's driver does not support the request.
  const BtmAnswer.none() : status = null, answered = false;

  /// 0 accept; 7 no suitable candidates.
  final int? status;
  final bool answered;

  bool get accepted => status == kBtmStatusAccept;

  String get label => !answered
      ? 'No answer: the driver does not support it'
      : accepted
      ? 'Accepted (status 0)'
      : 'Declined: no suitable candidates (status 7)';
}

/// [p]'s answer to a transition request naming 5 GHz at [rssi5].
BtmAnswer answerTransitionRequest(
  ClientProfile p,
  double rssi5, {
  bool driverSupportsBtm = true,
}) {
  final bool ok = switch (p) {
    ClientProfile.a => rssi5 >= kClientALookDbm,
    ClientProfile.b => rssi5 >= clientBEntryDbm(BsBand.ghz5),
    ClientProfile.c => bsHears(rssi5),
  };
  if (p == ClientProfile.c && !driverSupportsBtm) return const BtmAnswer.none();
  return BtmAnswer(
    status: ok ? kBtmStatusAccept : kBtmStatusNoSuitableCandidates,
    answered: true,
  );
}

// ── Frames ──────────────────────────────────────────────────────────────────

enum BsFrameKind {
  probeBroadcast,
  probeDirected,
  authentication,
  association,
  transitionRequest,
  transitionResponse,
}

/// What happened to a frame (drives the arrow style and the words).
enum BsOutcome {
  /// The AP answered, or the exchange succeeded.
  answered,

  /// The AP stayed silent.
  ignored,

  /// The AP refused.
  refused,

  /// The client declined (a transition request).
  declined,

  /// A one-way frame with nothing to answer (a response itself).
  sent,
}

/// One exchange at one sample: a request and what came of it.
class BsFrame {
  const BsFrame({
    required this.kind,
    required this.band,
    required this.outcome,
    required this.text,
    this.fromAp = false,
    this.randomAddress = false,
  });

  final BsFrameKind kind;
  final BsBand band;
  final BsOutcome outcome;

  /// Plain words for the frame list.
  final String text;

  /// True when the AP sent it (a transition request).
  final bool fromAp;

  /// True when the client sent it from a random address.
  final bool randomAddress;
}

// ── Config ──────────────────────────────────────────────────────────────────

class BsConfig {
  const BsConfig({
    this.profile = ClientProfile.a,
    this.mode = SteeringMode.off,
    this.randomScanAddress = false,
    this.extra5LossDb = kBsDefaultExtraLossDb,
    this.refusalTolerance = kBsDefaultTolerance,
    this.path = WalkPath.edgeToAp,
    this.driverSupportsBtm = true,
  });

  final ClientProfile profile;
  final SteeringMode mode;
  final bool randomScanAddress;
  final double extra5LossDb;
  final int refusalTolerance;
  final WalkPath path;

  /// Client C only: whether its driver supports transition requests.
  final bool driverSupportsBtm;

  BsConfig copyWith({
    ClientProfile? profile,
    SteeringMode? mode,
    bool? randomScanAddress,
    double? extra5LossDb,
    int? refusalTolerance,
    WalkPath? path,
    bool? driverSupportsBtm,
  }) => BsConfig(
    profile: profile ?? this.profile,
    mode: mode ?? this.mode,
    randomScanAddress: randomScanAddress ?? this.randomScanAddress,
    extra5LossDb: extra5LossDb ?? this.extra5LossDb,
    refusalTolerance: refusalTolerance ?? this.refusalTolerance,
    path: path ?? this.path,
    driverSupportsBtm: driverSupportsBtm ?? this.driverSupportsBtm,
  );

  /// Distances along the walk, meters from the AP, one per sample.
  List<double> get positionsM {
    final int n = ((kBsEdgeM - kBsNearM) / kBsStepM).round() + 1;
    return <double>[
      for (int i = 0; i < n; i++)
        path == WalkPath.edgeToAp
            ? kBsEdgeM - i * kBsStepM
            : kBsNearM + i * kBsStepM,
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is BsConfig &&
      other.profile == profile &&
      other.mode == mode &&
      other.randomScanAddress == randomScanAddress &&
      other.extra5LossDb == extra5LossDb &&
      other.refusalTolerance == refusalTolerance &&
      other.path == path &&
      other.driverSupportsBtm == driverSupportsBtm;

  @override
  int get hashCode => Object.hash(
    profile,
    mode,
    randomScanAddress,
    extra5LossDb,
    refusalTolerance,
    path,
    driverSupportsBtm,
  );
}

// ── Walk ────────────────────────────────────────────────────────────────────

/// The state after one sample of the walk.
class BsStep {
  const BsStep({
    required this.index,
    required this.distanceM,
    required this.rssi24,
    required this.rssi5,
    required this.band,
    required this.frames,
    required this.why,
    required this.trackedOn5,
    required this.refusalsTotal,
    required this.refusalsInRow,
    required this.btm,
    required this.scanned,
  });

  final int index;
  final double distanceM;
  final double rssi24;
  final double rssi5;

  /// The band the client is on after this sample, or null (not connected).
  final BsBand? band;

  /// The exchanges at this sample, in order.
  final List<BsFrame> frames;

  /// One plain sentence: why the client did what it did.
  final String why;

  /// True once the AP's tracker has matched this client on 5 GHz.
  final bool trackedOn5;

  /// Authentication refusals so far on the walk.
  final int refusalsTotal;

  /// Refusals since the client last got in (the AP's tolerance counter).
  final int refusalsInRow;

  /// The latest transition-request answer on the walk, if any.
  final BtmAnswer? btm;

  /// True when the client scanned (sent probe requests) at this sample.
  final bool scanned;

  double rssi(BsBand b) => b == BsBand.ghz24 ? rssi24 : rssi5;
}

class BsWalk {
  const BsWalk({required this.config, required this.steps});

  final BsConfig config;
  final List<BsStep> steps;

  BsStep get last => steps.last;

  /// Distance at which each band falls to the hearing floor: the rings.
  double ringM(BsBand band) =>
      bsRangeM(band, kBsHearFloorDbm, extra5LossDb: config.extra5LossDb);

  /// True if the client was ever on 5 GHz during the walk.
  bool get everOn5 => steps.any((BsStep s) => s.band == BsBand.ghz5);
}

/// -70 -> "-70 dBm", -78.43 -> "-78.4 dBm".
String bsDbm(double v) {
  final double r = (v * 10).roundToDouble() / 10;
  return r == r.roundToDouble()
      ? '${r.toStringAsFixed(0)} dBm'
      : '${r.toStringAsFixed(1)} dBm';
}

String _dbm(double v) => bsDbm(v);

/// Runs the whole walk for [config]. Deterministic.
BsWalk simulateWalk(BsConfig config) {
  final ClientProfile p = config.profile;
  final SteeringMode mode = config.mode;
  final bool random = config.randomScanAddress;
  final List<BsStep> steps = <BsStep>[];

  BsBand? band;
  bool tracked = false;
  int refusalsTotal = 0;
  int refusalsInRow = 0;
  BtmAnswer? btm;
  int stepsOn24 = 0;

  final List<double> positions = config.positionsM;
  for (int k = 0; k < positions.length; k++) {
    final double d = positions[k];
    final double r24 = bsRssiDbm(BsBand.ghz24, d);
    final double r5 = bsRssiDbm(
      BsBand.ghz5,
      d,
      extra5LossDb: config.extra5LossDb,
    );
    double rssi(BsBand b) => b == BsBand.ghz24 ? r24 : r5;
    final List<BsFrame> frames = <BsFrame>[];
    String why;
    bool scanned = false;

    // One scan: broadcast probes on 5 GHz then 2.4 GHz. Beacons are always
    // heard on any band above the floor.
    void scan() {
      scanned = true;
      final String from = random ? ' from a random address' : '';
      if (bsHears(r5)) {
        if (!random) tracked = true;
        frames.add(
          BsFrame(
            kind: BsFrameKind.probeBroadcast,
            band: BsBand.ghz5,
            outcome: BsOutcome.answered,
            randomAddress: random,
            text: 'Probe request (broadcast)$from, 5 GHz: answered',
          ),
        );
      } else {
        frames.add(
          BsFrame(
            kind: BsFrameKind.probeBroadcast,
            band: BsBand.ghz5,
            outcome: BsOutcome.ignored,
            randomAddress: random,
            text:
                'Probe request (broadcast)$from, 5 GHz: no answer, out of '
                'range on 5 GHz',
          ),
        );
      }
      if (bsHears(r24)) {
        final bool answered = apAnswersProbe(
          mode: mode,
          band: BsBand.ghz24,
          directed: false,
          trackedOn5: tracked && !random,
        );
        frames.add(
          BsFrame(
            kind: BsFrameKind.probeBroadcast,
            band: BsBand.ghz24,
            outcome: answered ? BsOutcome.answered : BsOutcome.ignored,
            randomAddress: random,
            text: answered
                ? 'Probe request (broadcast)$from, 2.4 GHz: answered'
                : 'Probe request (broadcast)$from, 2.4 GHz: no answer, '
                      'probe suppression (the 2.4 GHz beacon is still heard)',
          ),
        );
        if (!answered) {
          frames.add(
            const BsFrame(
              kind: BsFrameKind.probeDirected,
              band: BsBand.ghz24,
              outcome: BsOutcome.answered,
              text:
                  'Probe request naming the network (directed), 2.4 GHz: '
                  'answered',
            ),
          );
        }
      }
    }

    // Authentication on [b]. Returns true when the client gets in.
    bool authenticate(BsBand b, {required bool roam}) {
      final bool refuse =
          mode == SteeringMode.authRefusal &&
          b == BsBand.ghz24 &&
          tracked &&
          !random &&
          refusalsInRow < config.refusalTolerance;
      if (refuse) {
        refusalsInRow++;
        refusalsTotal++;
        frames.add(
          BsFrame(
            kind: BsFrameKind.authentication,
            band: b,
            outcome: BsOutcome.refused,
            text:
                'Authentication, 2.4 GHz: refused ($refusalsInRow of '
                '${config.refusalTolerance} before the AP gives in)',
          ),
        );
        return false;
      }
      frames.add(
        BsFrame(
          kind: BsFrameKind.authentication,
          band: b,
          outcome: BsOutcome.answered,
          text: 'Authentication, ${b.label}: accepted',
        ),
      );
      frames.add(
        BsFrame(
          kind: BsFrameKind.association,
          band: b,
          outcome: BsOutcome.answered,
          text: roam
              ? 'Reassociation, ${b.label}: accepted'
              : 'Association, ${b.label}: accepted',
        ),
      );
      refusalsInRow = 0;
      return true;
    }

    String refusedWhy(BsBand? stayedOn) {
      final String tail = stayedOn == null
          ? 'it will try again'
          : 'it stays on ${stayedOn.label} and will try again';
      return 'The AP has heard this client on 5 GHz, so it refused '
          'authentication on 2.4 GHz ($refusalsInRow of '
          '${config.refusalTolerance}); $tail.';
    }

    // A connected client whose band has faded below the floor loses it.
    String? lostNote;
    if (band != null && !bsHears(rssi(band))) {
      lostNote = 'Lost ${band.label} at ${_dbm(rssi(band))}';
      band = null;
    }

    if (band == null) {
      // Join: scan, then try the bands in the profile's order.
      scan();
      final List<BsBand> order = joinPreference(p, rssi24: r24, rssi5: r5);
      if (order.isEmpty) {
        why =
            'The client cannot hear the AP well enough to join on either '
            'band.';
      } else {
        BsBand? joined;
        bool anyRefused = false;
        final bool wasLetIn =
            mode == SteeringMode.authRefusal &&
            tracked &&
            !random &&
            refusalsInRow >= config.refusalTolerance;
        for (final BsBand b in order) {
          if (authenticate(b, roam: false)) {
            joined = b;
            break;
          }
          anyRefused = true;
        }
        band = joined;
        if (joined == null) {
          why = refusedWhy(null);
        } else if (anyRefused) {
          why =
              'The AP refused it on 2.4 GHz, so ${p.label} joined '
              '${joined.label} at ${_dbm(rssi(joined))} instead.';
        } else if (wasLetIn && joined == BsBand.ghz24) {
          why =
              'The AP refused ${config.refusalTolerance} times, its '
              'tolerance, and then let the client in on 2.4 GHz.';
        } else {
          why = _joinWhy(p, joined, r24, r5, config);
        }
      }
      if (lostNote != null) why = '$lostNote. $why';
    } else {
      final BsBand on = band;
      final double here = rssi(on);
      final double? look = lookThresholdDbm(p, on);
      if (looksForAnother(p, on, here)) {
        scan();
        final BsBand alt = on.other;
        final double there = rssi(alt);
        bool move;
        String reason;
        switch (p) {
          case ClientProfile.a:
            move = bsHears(there) && there >= here + kClientADeltaDb;
            reason =
                'Signal on ${on.label} is ${_dbm(here)}, below '
                '${_dbm(kClientALookDbm)}, so ${p.label} looked. '
                '${alt.label} at ${_dbm(there)} is '
                '${move ? 'at least' : 'not'} '
                '${kClientADeltaDb.toStringAsFixed(0)} dB stronger, so it '
                '${move ? 'moves' : 'stays'}.';
          case ClientProfile.b:
            final List<BsBand> pref = joinPreference(
              p,
              rssi24: r24,
              rssi5: r5,
              current: on,
            );
            move = pref.isNotEmpty && pref.first == alt;
            final String cmp = passesEntry(p, alt, there)
                ? '${alt.label} at ${_dbm(there)} '
                      '${move ? 'scores higher' : 'does not score higher'}'
                : '${alt.label} at ${_dbm(there)} is below its '
                      '${_dbm(clientBEntryDbm(alt))} entry threshold';
            reason =
                'Signal on ${on.label} is ${_dbm(here)}, not above '
                '${_dbm(look!)}, so ${p.label} re-ran selection; $cmp, so it '
                '${move ? 'moves' : 'stays'}.';
          case ClientProfile.c:
            move = false;
            reason = '';
        }
        if (move) {
          final bool letIn =
              mode == SteeringMode.authRefusal &&
              alt == BsBand.ghz24 &&
              tracked &&
              !random &&
              refusalsInRow >= config.refusalTolerance;
          if (authenticate(alt, roam: true)) {
            band = alt;
            why = letIn
                ? 'The AP refused ${config.refusalTolerance} times, its '
                      'tolerance, and then let the client in on 2.4 GHz.'
                : reason;
          } else {
            why = refusedWhy(on);
          }
        } else {
          why = reason;
        }
      } else {
        why = switch (p) {
          ClientProfile.c =>
            '${p.label} publishes no rule for leaving a network; this model '
                'keeps it on ${on.label} (${_dbm(here)}) until it loses the '
                'signal.',
          _ =>
            'Signal on ${on.label} is ${_dbm(here)}, above ${_dbm(look!)}, '
                'so this client does not look for another network.',
        };
      }
    }

    // Transition request: after association on 2.4 GHz, then every
    // [kBsBtmRepeatSteps] samples while the client stays there.
    if (band == BsBand.ghz24) {
      stepsOn24++;
    } else {
      stepsOn24 = 0;
    }
    if (mode == SteeringMode.transitionRequest &&
        band == BsBand.ghz24 &&
        (stepsOn24 - 1) % kBsBtmRepeatSteps == 0) {
      final BtmAnswer a = answerTransitionRequest(
        p,
        r5,
        driverSupportsBtm: config.driverSupportsBtm,
      );
      btm = a;
      frames.add(
        const BsFrame(
          kind: BsFrameKind.transitionRequest,
          band: BsBand.ghz24,
          outcome: BsOutcome.sent,
          fromAp: true,
          text:
              'Transition request from the AP, 2.4 GHz: please move to '
              '5 GHz',
        ),
      );
      if (a.answered) {
        frames.add(
          BsFrame(
            kind: BsFrameKind.transitionResponse,
            band: BsBand.ghz24,
            outcome: a.accepted ? BsOutcome.answered : BsOutcome.declined,
            text: 'Transition response, 2.4 GHz: ${a.label.toLowerCase()}',
          ),
        );
      }
      final String rule = switch (p) {
        ClientProfile.a => 'its ${_dbm(kClientALookDbm)} level (model choice)',
        ClientProfile.b =>
          'its ${_dbm(clientBEntryDbm(BsBand.ghz5))} entry threshold',
        ClientProfile.c => 'the ${_dbm(kBsHearFloorDbm)} hearing floor',
      };
      if (!a.answered) {
        why =
            'The AP asked the client to move to 5 GHz; its driver does not '
            'support the request, so it did not answer and stays on 2.4 GHz.';
      } else if (a.accepted) {
        frames.add(
          const BsFrame(
            kind: BsFrameKind.association,
            band: BsBand.ghz5,
            outcome: BsOutcome.answered,
            text: 'Reassociation, 5 GHz: accepted',
          ),
        );
        band = BsBand.ghz5;
        stepsOn24 = 0;
        why =
            'The AP asked the client to move; 5 GHz at ${_dbm(r5)} meets '
            '$rule, so it accepted and moved to 5 GHz.';
      } else {
        why =
            'The AP asked the client to move to 5 GHz; 5 GHz at '
            '${_dbm(r5)} is below $rule, so it declined: no suitable '
            'candidates.';
      }
    }

    steps.add(
      BsStep(
        index: k,
        distanceM: d,
        rssi24: r24,
        rssi5: r5,
        band: band,
        frames: List<BsFrame>.unmodifiable(frames),
        why: why,
        trackedOn5: tracked && !random,
        refusalsTotal: refusalsTotal,
        refusalsInRow: refusalsInRow,
        btm: btm,
        scanned: scanned,
      ),
    );
  }
  return BsWalk(config: config, steps: List<BsStep>.unmodifiable(steps));
}

String _joinWhy(
  ClientProfile p,
  BsBand joined,
  double r24,
  double r5,
  BsConfig c,
) {
  final String at =
      '${joined.label} at ${_dbm(joined == BsBand.ghz24 ? r24 : r5)}';
  if (!bsHears(r5)) {
    return '${p.label} can hear only 2.4 GHz (5 GHz is below the '
        '${_dbm(kBsHearFloorDbm)} hearing floor), so it joined $at.';
  }
  switch (p) {
    case ClientProfile.a:
      return joined == BsBand.ghz5
          ? '5 GHz is at or above ${_dbm(kClientALookDbm)} and has the wider '
                'channel, so ${p.label} joined $at.'
          : '5 GHz at ${_dbm(r5)} is below ${_dbm(kClientALookDbm)}, so '
                '${p.label} joined the stronger band, $at.';
    case ClientProfile.b:
      return joined == BsBand.ghz5
          ? '5 GHz passes its ${_dbm(clientBEntryDbm(BsBand.ghz5))} entry '
                'threshold and has the higher throughput estimate, so '
                '${p.label} joined $at.'
          : '5 GHz at ${_dbm(r5)} is below its '
                '${_dbm(clientBEntryDbm(BsBand.ghz5))} entry threshold, so '
                '${p.label} joined $at.';
    case ClientProfile.c:
      return '${p.label} joins the strongest signal, so it joined $at.';
  }
}
