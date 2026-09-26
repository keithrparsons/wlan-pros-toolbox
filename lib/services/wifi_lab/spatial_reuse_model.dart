// Spatial reuse and BSS coloring model for the Wi-Fi Classroom (spatial-reuse).
//
// CLEAN-ROOM BUILD (2026-09-25) per myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/20-spatial-reuse.md, with
// every number from the wave-3 research brief (same Deliverables date,
// wifi-lab-wave3-research/brief.md §5, and §4 for the CCA thresholds). No
// Flutter widgets; every number the screen shows is pinned by
// test/services/wifi_lab/spatial_reuse_model_test.dart.
//
// WHAT IT MODELS
//   - Two BSSs on one channel along a line: AP A with client A, AP B with
//     client B. AP A is already sending a frame to client A; AP B has a frame
//     ready for client B and must decide whether to wait.
//   - Path loss is the log-distance model from fspl_math.dart (free-space
//     loss at 1 m plus 10 n log10 d, n default 3.0), 0 dBi antennas, so the
//     AP transmit power is its EIRP.
//   - Levels are compared per 20 MHz, as in the Channel Planner: a wide
//     frame spreads its power, so each 20 MHz piece carries the total minus
//     10 log10(width / 20). Comparing the per-20 level with a per-20
//     threshold is the same test as comparing the whole frame with a
//     threshold raised 3 dB per doubling of width (brief §5, S1: Wilhelmi).
//   - The deferral decision (brief §4 and §5):
//       energy at or above -62 dBm always defers (energy detect);
//       without BSS coloring, a Wi-Fi preamble at or above -82 dBm defers;
//       with coloring, a frame carrying AP B's OWN color is intra-BSS and
//       keeps -82 dBm; a neighbor's color is inter-BSS, and AP B may ignore
//       it below its OBSS_PD threshold (-82 to -62 dBm) if it then limits its
//       power to TX_PWRmax = TX_PWRref - (OBSS_PD - (-82)) for that
//       transmission (brief §5, S2).
//   - TX_PWRref is 21 dBm for a client or an AP with at most 2 spatial
//     streams and 25 dBm for an AP with more (brief §5, S1: one secondary
//     source). The screen labels it single-source.
//   - SINR at each client with the other AP as interference, against the
//     receiver noise floor per 20 MHz: thermal noise (kT at 290 K, -174
//     dBm/Hz, brief §10) plus a 7 dB noise figure, the Rate vs Range default.
//   - Which MCS a link holds, read the way Rate vs Range reads SNR: the SNR
//     an MCS needs is its minimum sensitivity (brief §10, via
//     rate_vs_range_math.dart, not copied) minus the noise floor at that
//     width with the same 7 dB noise figure. A link holds an MCS when its
//     SINR is at or above that. The sensitivities are conformance floors:
//     real radios beat them, so this is the worst case the standard allows.
//   - OUT OF SCOPE: SRG (spatial reuse group) thresholds and parameterized
//     spatial reuse (PSR). The SRG offset arithmetic is not verified from a
//     primary source (brief §5).
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'channel_planner_model.dart' show CcaRule;
import 'fspl_math.dart';
import 'rate_vs_range_math.dart';

// ── Constants ─────────────────────────────────────────────────────────────

/// Preamble detect and the floor of OBSS_PD: -82 dBm per 20 MHz. Shared with
/// the Channel Planner so the two tools agree.
final double kPreambleDetectDbm = CcaRule.preambleDetect.thresholdDbm;

/// Energy detect and the ceiling of OBSS_PD: -62 dBm per 20 MHz.
final double kEnergyDetectDbm = CcaRule.energyDetect.thresholdDbm;

/// OBSS_PDmin and OBSS_PDmax, dBm per 20 MHz (brief §5, S2).
final double kObssPdMinDbm = kPreambleDetectDbm;
final double kObssPdMaxDbm = kEnergyDetectDbm;

/// BSS color is 6 bits; 0 is not a usable color, so 1 to 63 (brief §5, S2).
const int kMinBssColor = 1;
const int kMaxBssColor = 63;

/// Thermal noise density at 290 K, dBm/Hz (brief §10).
const double kThermalNoiseDbmPerHz = -174;

/// The channel widths the tool offers, MHz.
const List<int> kReuseWidths = <int>[20, 40, 80, 160];

/// Path-loss reference frequency: 5 GHz channel 36.
const double kReuseFreqMHz = 5180;

/// The reference power the OBSS_PD rule subtracts from (brief §5, S1).
enum TxPwrRefClass {
  standard(21, '21 dBm', 'Client, or AP with 1 or 2 streams'),
  apMoreStreams(25, '25 dBm', 'AP with 3 or more streams');

  const TxPwrRefClass(this.dbm, this.short, this.label);

  final double dbm;
  final String short;
  final String label;
}

/// Which rule decided what AP B does.
enum ReuseRule {
  energyDetect(defers: true, short: 'ED', label: 'Energy at or above -62 dBm'),
  preambleDetect(
    defers: true,
    short: 'PD',
    label: 'Wi-Fi preamble at or above -82 dBm (no BSS color)',
  ),
  intraBss(
    defers: true,
    short: 'Own color',
    label: 'Same BSS color: treated as its own BSS, so -82 dBm applies',
  ),
  obssPd(
    defers: true,
    short: 'OBSS_PD',
    label: 'Neighbor color at or above the OBSS_PD threshold',
  ),
  spatialReuse(
    defers: false,
    short: 'Reuse',
    label: 'Neighbor color below OBSS_PD: ignored, with a power limit',
  ),
  notDetected(
    defers: false,
    short: 'Below -82',
    label: 'Below -82 dBm: not detected, so nothing to wait for',
  );

  const ReuseRule({
    required this.defers,
    required this.short,
    required this.label,
  });

  final bool defers;
  final String short;
  final String label;
}

// ── Pure rules ────────────────────────────────────────────────────────────

/// 10 log10(width / 20): how far a per-20 MHz threshold rises for a whole
/// frame of [widthMHz]. About 3 dB per doubling (brief §5, S1).
double widthOffsetDb(int widthMHz) => 10 * FsplMath.log10(widthMHz / 20);

/// A per-20 MHz threshold expressed for a whole frame of [widthMHz].
double thresholdForWidth(double per20Dbm, int widthMHz) =>
    per20Dbm + widthOffsetDb(widthMHz);

/// The part of a whole-frame level that lands in each 20 MHz piece.
double per20Level(double totalDbm, int widthMHz) =>
    totalDbm - widthOffsetDb(widthMHz);

/// OBSS_PD held inside its legal range, -82 to -62 dBm.
double clampObssPd(double obssPdDbm) =>
    obssPdDbm.clamp(kObssPdMinDbm, kObssPdMaxDbm).toDouble();

/// TX_PWRmax = TX_PWRref - (OBSS_PD - OBSS_PDmin) (brief §5, S2). Every 1 dB
/// the threshold rises above -82 costs 1 dB of transmit power.
double txPowerLimitDbm({
  required double obssPdDbm,
  required double txPwrRefDbm,
}) => txPwrRefDbm - (clampObssPd(obssPdDbm) - kObssPdMinDbm);

/// What AP B does, and why.
class ReuseDecision {
  const ReuseDecision({required this.rule, required this.txPowerLimitDbm});

  final ReuseRule rule;

  /// The power cap for this transmission, or null when none applies (AP B
  /// waits, or the frame was below -82 dBm and never detected).
  final double? txPowerLimitDbm;

  bool get defers => rule.defers;
}

/// Does a radio defer to a frame it hears at [levelDbm] per 20 MHz?
///
/// [coloring] off is legacy behavior: every Wi-Fi preamble counts at -82.
/// [sameColor] means the frame carries the listener's own BSS color, so it
/// is intra-BSS and keeps -82 however high OBSS_PD is set. A level exactly on
/// a threshold fires it, as in the Channel Planner.
ReuseDecision decideDeferral({
  required double levelDbm,
  required bool coloring,
  required bool sameColor,
  required double obssPdDbm,
  required double txPwrRefDbm,
}) {
  if (levelDbm >= kEnergyDetectDbm) {
    return const ReuseDecision(
      rule: ReuseRule.energyDetect,
      txPowerLimitDbm: null,
    );
  }
  if (levelDbm < kPreambleDetectDbm) {
    return const ReuseDecision(
      rule: ReuseRule.notDetected,
      txPowerLimitDbm: null,
    );
  }
  if (!coloring) {
    return const ReuseDecision(
      rule: ReuseRule.preambleDetect,
      txPowerLimitDbm: null,
    );
  }
  if (sameColor) {
    return const ReuseDecision(rule: ReuseRule.intraBss, txPowerLimitDbm: null);
  }
  final double pd = clampObssPd(obssPdDbm);
  if (levelDbm >= pd) {
    return const ReuseDecision(rule: ReuseRule.obssPd, txPowerLimitDbm: null);
  }
  return ReuseDecision(
    rule: ReuseRule.spatialReuse,
    txPowerLimitDbm: txPowerLimitDbm(obssPdDbm: pd, txPwrRefDbm: txPwrRefDbm),
  );
}

/// Thermal noise in [bandwidthMHz], dBm: -174 + 10 log10(B in Hz). About
/// -101.0 dBm in 20 MHz.
double thermalNoiseDbm(double bandwidthMHz) =>
    kThermalNoiseDbmPerHz + 10 * FsplMath.log10(bandwidthMHz * 1e6);

/// Receiver noise figure, dB: the Rate vs Range default, so the two tools
/// read SNR the same way.
const double kReuseNoiseFigureDb = RateVsRangeMath.defaultNoiseFigureDb;

/// Receiver noise floor per 20 MHz, dBm: thermal noise plus the noise
/// figure. About -94.0 dBm.
double reuseNoiseFloorDbm() =>
    RateVsRangeMath.noiseFloorDbm(20, kReuseNoiseFigureDb);

/// Highest MCS in the sensitivity table.
const int kReuseMaxMcs = RateVsRangeMath.maxMcs;

/// SNR [mcs] needs at [widthMHz], dB: its minimum sensitivity minus the
/// noise floor at that width (7 dB noise figure). Width-independent to
/// within 0.03 dB, since both rise about 3 dB per doubling.
double mcsRequiredSnrDb(int mcs, int widthMHz) =>
    RateVsRangeMath.sensitivityDbm(mcs, widthMHz) -
    RateVsRangeMath.noiseFloorDbm(widthMHz, kReuseNoiseFigureDb);

/// Highest MCS whose required SNR [sinrDb] meets, or null when even MCS 0
/// is out of reach.
int? highestMcsForSinr(double sinrDb, int widthMHz) {
  int? best;
  for (int m = 0; m <= kReuseMaxMcs; m++) {
    if (sinrDb >= mcsRequiredSnrDb(m, widthMHz)) best = m;
  }
  return best;
}

/// `MCS 7 (64-QAM 5/6)`.
String mcsLabel(int mcs) {
  final RvrMcsInfo i = RateVsRangeMath.mcsInfo[mcs];
  return 'MCS $mcs (${i.modulation} ${i.codeRate})';
}

/// Power sum of two levels in dBm.
double powerSumDbm(double aDbm, double bDbm) =>
    10 *
    FsplMath.log10(
      math.pow(10, aDbm / 10).toDouble() + math.pow(10, bDbm / 10).toDouble(),
    );

// ── Scenario ──────────────────────────────────────────────────────────────

/// The four radios on the line, metres from the left end.
class ReuseLayout {
  const ReuseLayout({
    this.apA = 5,
    this.clientA = 15,
    this.clientB = 45,
    this.apB = 55,
  });

  final double apA;
  final double clientA;
  final double clientB;
  final double apB;

  ReuseLayout copyWith({
    double? apA,
    double? clientA,
    double? clientB,
    double? apB,
  }) => ReuseLayout(
    apA: apA ?? this.apA,
    clientA: clientA ?? this.clientA,
    clientB: clientB ?? this.clientB,
    apB: apB ?? this.apB,
  );
}

/// Everything the student can set.
class ReuseScenario {
  const ReuseScenario({
    this.layout = const ReuseLayout(),
    this.exponent = 3.0,
    this.apPowerDbm = 20,
    this.widthMHz = 20,
    this.txPwrRef = TxPwrRefClass.standard,
    this.coloring = true,
    this.colorA = 6,
    this.colorB = 26,
    this.obssPdDbm = -82,
    this.mcsA = 7,
    this.mcsB = 7,
  });

  final ReuseLayout layout;

  /// Log-distance path-loss exponent.
  final double exponent;

  /// Configured transmit power of each AP (EIRP, 0 dBi antennas), dBm.
  final double apPowerDbm;

  final int widthMHz;
  final TxPwrRefClass txPwrRef;

  /// BSS coloring on (802.11ax) or off (legacy).
  final bool coloring;

  final int colorA;
  final int colorB;

  /// AP B's OBSS_PD threshold, dBm per 20 MHz.
  final double obssPdDbm;

  /// The MCS each link must hold, 0 to 13.
  final int mcsA;
  final int mcsB;

  ReuseScenario copyWith({
    ReuseLayout? layout,
    double? exponent,
    double? apPowerDbm,
    int? widthMHz,
    TxPwrRefClass? txPwrRef,
    bool? coloring,
    int? colorA,
    int? colorB,
    double? obssPdDbm,
    int? mcsA,
    int? mcsB,
  }) => ReuseScenario(
    layout: layout ?? this.layout,
    exponent: exponent ?? this.exponent,
    apPowerDbm: apPowerDbm ?? this.apPowerDbm,
    widthMHz: widthMHz ?? this.widthMHz,
    txPwrRef: txPwrRef ?? this.txPwrRef,
    coloring: coloring ?? this.coloring,
    colorA: colorA ?? this.colorA,
    colorB: colorB ?? this.colorB,
    obssPdDbm: obssPdDbm ?? this.obssPdDbm,
    mcsA: mcsA ?? this.mcsA,
    mcsB: mcsB ?? this.mcsB,
  );
}

/// One downlink, AP to its client, per 20 MHz.
class ReuseLink {
  const ReuseLink({
    required this.signalDbm,
    required this.interferenceDbm,
    required this.noiseDbm,
    required this.widthMHz,
    required this.targetMcs,
  });

  /// Wanted signal at the client, dBm per 20 MHz.
  final double signalDbm;

  /// The other AP at this client, dBm per 20 MHz; null when it is silent.
  final double? interferenceDbm;

  /// Receiver noise floor per 20 MHz (thermal plus the noise figure).
  final double noiseDbm;

  /// Channel width, for the MCS table column.
  final int widthMHz;

  /// The MCS the student asked this link to hold.
  final int targetMcs;

  /// Signal over noise alone.
  double get snrDb => signalDbm - noiseDbm;

  /// Signal over interference plus noise; equals [snrDb] when alone.
  double get sinrDb => interferenceDbm == null
      ? snrDb
      : signalDbm - powerSumDbm(interferenceDbm!, noiseDbm);

  /// dB the neighbor costs this link.
  double get costDb => snrDb - sinrDb;

  /// Highest MCS the SINR supports; null when not even MCS 0.
  int? get bestMcs => highestMcsForSinr(sinrDb, widthMHz);

  /// Highest MCS the link would support with the neighbor silent.
  int? get bestMcsAlone => highestMcsForSinr(snrDb, widthMHz);

  /// SNR [targetMcs] needs at this width.
  double get requiredSnrDb => mcsRequiredSnrDb(targetMcs, widthMHz);

  /// The link still holds [targetMcs].
  bool get holds => sinrDb >= requiredSnrDb;
}

/// Path loss over [distanceM] metres (at least 1 m) at 5180 MHz.
double reusePathLossDb(double distanceM, double exponent) =>
    FsplMath.logDistanceDb(math.max(1, distanceM), kReuseFreqMHz, exponent);

/// The whole outcome for one scenario.
class ReuseAnalysis {
  ReuseAnalysis._({
    required this.scenario,
    required this.heardByBDbm,
    required this.decision,
    required this.txPowerBDbm,
    required this.linkA,
    required this.linkB,
  });

  factory ReuseAnalysis.of(ReuseScenario s) {
    final ReuseLayout l = s.layout;
    final int w = s.widthMHz;
    final double noise = reuseNoiseFloorDbm();
    double rx(double txDbm, double a, double b) =>
        per20Level(txDbm - reusePathLossDb((a - b).abs(), s.exponent), w);

    final double heard = rx(s.apPowerDbm, l.apA, l.apB);
    final ReuseDecision d = decideDeferral(
      levelDbm: heard,
      coloring: s.coloring,
      sameColor: s.colorA == s.colorB,
      obssPdDbm: s.obssPdDbm,
      txPwrRefDbm: s.txPwrRef.dbm,
    );
    final double txB = d.txPowerLimitDbm == null
        ? s.apPowerDbm
        : math.min(s.apPowerDbm, d.txPowerLimitDbm!);
    final bool together = !d.defers;
    return ReuseAnalysis._(
      scenario: s,
      heardByBDbm: heard,
      decision: d,
      txPowerBDbm: txB,
      linkA: ReuseLink(
        signalDbm: rx(s.apPowerDbm, l.apA, l.clientA),
        interferenceDbm: together ? rx(txB, l.apB, l.clientA) : null,
        noiseDbm: noise,
        widthMHz: w,
        targetMcs: s.mcsA,
      ),
      linkB: ReuseLink(
        signalDbm: rx(txB, l.apB, l.clientB),
        interferenceDbm: together ? rx(s.apPowerDbm, l.apA, l.clientB) : null,
        noiseDbm: noise,
        widthMHz: w,
        targetMcs: s.mcsB,
      ),
    );
  }

  final ReuseScenario scenario;

  /// What AP B hears from AP A, dBm per 20 MHz.
  final double heardByBDbm;

  final ReuseDecision decision;

  /// AP B's actual transmit power: its setting, or less under the limit.
  final double txPowerBDbm;

  final ReuseLink linkA;
  final ReuseLink linkB;

  /// Both frames on the air at once.
  bool get together => !decision.defers;

  /// True when the limit actually cut AP B below its configured power.
  bool get powerCut => txPowerBDbm < scenario.apPowerDbm;

  /// Frame-times the pair needs to send one frame each: 1 together, 2 in
  /// turn. A teaching approximation that ignores backoff and ACKs.
  int get frameTimes => together ? 1 : 2;

  /// OBSS_PD for the whole frame at this width.
  double get obssPdAtWidthDbm =>
      thresholdForWidth(clampObssPd(scenario.obssPdDbm), scenario.widthMHz);
}
