// Adjacent Channels and AP Stacking model for the Wi-Fi Classroom
// (adjacent-channel).
//
// CLEAN-ROOM BUILD (2026-09-26) per myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/29-adjacent-channel.md.
// Mask breakpoints from Deliverables/2026-09-25-wifi-lab-wave3-research/
// brief.md §4 (mask table); the row-B framing from
// Deliverables/2026-09-26-wifi-classroom-wave4-research/brief.md. Pure Dart,
// no Flutter widgets; every number the screen shows is pinned by
// test/services/wifi_lab/adjacent_channel_model_test.dart.
//
// WHAT IT MODELS
//   - Two transmitters and one receiver. The wanted transmitter (your AP or
//     your client) and a neighbor transmitter on another channel; the
//     receiver listens on a 20 MHz channel.
//   - Received power: log-distance path loss, FSPL(1 m) + 10 n log10(d),
//     with FSPL(1 m) from Roaming Walk (RoamBand.fspl1mDb). Below 1 m the
//     path is taken as free space (n = 2), so two radios 30 cm apart can be
//     modeled; the caveat is shown to the student.
//   - Leakage: the neighbor's power at the receiver times the fraction of its
//     transmit mask that falls inside the receiver's 20 MHz, the mask
//     interpolated linearly in dB between breakpoints and integrated in
//     linear power, relative to the mask integrated over the neighbor's own
//     channel. The mask is a ceiling on the transmitter, so this is the worst
//     case the rule allows, not what a real radio emits.
//   - Receiver selectivity S: how far the receiver's filter pushes down the
//     neighbor's IN-CHANNEL power. One ILLUSTRATIVE value per separation
//     (35 dB next channel, 51 dB one gap or more), never per MCS.
//   - Effective interference (spec 29 CORRECTION 2026-09-27, Pax,
//     Deliverables/2026-09-26-wifi-classroom-wave4-research/
//     adjacent-channel-rejection-check.md, formula c):
//       I = P_neighbor + 10 log10(10^(L/10) + 10^(-S/10))
//     Leakage L is already inside the receiver's channel, so no filter
//     removes it; S acts only on the neighbor's own channel. The two add in
//     linear power. The first version subtracted a per-MCS rejection from
//     the leakage, which counted protection twice.
//   - SINR, SIR, and the highest MCS the SINR supports: an MCS is supported
//     when SINR >= its minimum sensitivity minus the noise floor (Rate vs
//     Range's table, 20 MHz column). That per-MCS threshold is the ONLY
//     place the rate enters: the receiver's rejection does not change with
//     rate.
//   - Clear channel assessment (CCA) energy detect: busy when the effective
//     interference (what gets past the filter) is at or above the threshold
//     (default -62 dBm, Channel Planner's CcaRule.energyDetect).
//   - Reference only: the standard's minimum adjacent-channel rejection
//     (ACR) per MCS, via a 2024 802.11be test white paper (Table 6-5).
//     ACR + minimum sensitivity = -66 dBm at every MCS; a test holds that.
//
// THE STANDING DRAWING RULE (README, Keith 2026-09-25): power changes change
// heights only. Channel centers come from the channel choice alone (band,
// width, separation) and never from distance, power, selectivity or the CCA
// threshold; a test holds that.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import '../../data/channel_frequency_data.dart';
import 'channel_planner_model.dart' show TxMask, kMaskBreakpoints;
import 'fspl_math.dart';
import 'rate_vs_range_math.dart';
import 'roaming_walk_engine.dart' show RoamBand;

// ── Transmit masks ──────────────────────────────────────────────────────────

/// Which transmit mask the neighbor obeys.
enum AciMaskFamily {
  /// 802.11a/g OFDM, 20 MHz only (brief §4, S2; the ETSI regulatory mask
  /// uses the same -20/-28/-40 points).
  ofdm('OFDM (802.11a/g)'),

  /// 802.11ax/be, 20 to 320 MHz (brief §4, S1).
  heEht('HE/EHT (802.11ax/be)');

  const AciMaskFamily(this.label);

  /// Short label for toggles.
  final String label;

  /// Widths this mask family has a table for, MHz.
  List<int> get widthsMHz => this == AciMaskFamily.ofdm
      ? const <int>[20]
      : const <int>[20, 40, 80, 160, 320];
}

/// Mask breakpoints (offset from center, MHz; dBr) for [family] at
/// [widthMHz]. Linear in dB between points; flat past the last point.
///
/// OFDM 20 MHz is Channel Planner's own table ([kMaskBreakpoints]), so the
/// two tools agree. HE/EHT: brief §4, 20: 9.75 / 10.5 / 20 / 30; 40: 19.5 /
/// 20.5 / 40 / 60; 80: 39.5 / 40.5 / 80 / 120; 160: 79.5 / 80.5 / 160 / 240;
/// 320: 159.5 / 160.5 / 320 / 480, at 0 / -20 / -28 / -40 dBr.
List<(double, double)> aciMaskBreakpoints(AciMaskFamily family, int widthMHz) {
  if (family == AciMaskFamily.ofdm) {
    if (widthMHz != 20) throw ArgumentError.value(widthMHz, 'widthMHz');
    return kMaskBreakpoints[TxMask.ofdm]!;
  }
  final (double, double, double, double) p = switch (widthMHz) {
    20 => (9.75, 10.5, 20, 30),
    40 => (19.5, 20.5, 40, 60),
    80 => (39.5, 40.5, 80, 120),
    160 => (79.5, 80.5, 160, 240),
    320 => (159.5, 160.5, 320, 480),
    _ => throw ArgumentError.value(widthMHz, 'widthMHz'),
  };
  return <(double, double)>[
    (0, 0),
    (p.$1, 0),
    (p.$2, -20),
    (p.$3, -28),
    (p.$4, -40),
  ];
}

/// Mask ceiling in dBr at [offsetMHz] from the transmitter's center.
double aciMaskDbr(AciMaskFamily family, int widthMHz, double offsetMHz) {
  final double f = offsetMHz.abs();
  final List<(double, double)> pts = aciMaskBreakpoints(family, widthMHz);
  for (int i = 1; i < pts.length; i++) {
    final (double x0, double y0) = pts[i - 1];
    final (double x1, double y1) = pts[i];
    if (f > x1) continue;
    if (x1 == x0) return f < x1 ? y0 : y1;
    return y0 + (y1 - y0) * (f - x0) / (x1 - x0);
  }
  return pts.last.$2;
}

/// Integration step, MHz. Fine enough that the result is stable to well
/// under 0.01 dB; fixed, so the model is deterministic.
const double _kStepMHz = 0.01;

double _integrate(AciMaskFamily family, int widthMHz, double a, double b) {
  final int n = ((b - a) / _kStepMHz).round();
  double sum = 0;
  for (int i = 0; i < n; i++) {
    final double f = a + (i + 0.5) * _kStepMHz;
    sum += math.pow(10, aciMaskDbr(family, widthMHz, f) / 10) * _kStepMHz;
  }
  return sum;
}

final Map<(AciMaskFamily, int, double), double> _leakCache =
    <(AciMaskFamily, int, double), double>{};

/// The share of the neighbor's in-channel power that lands in a 20 MHz
/// receiver channel centered [offsetMHz] away, in dB: the mask integrated
/// over the receiver's 20 MHz divided by the mask integrated over the
/// neighbor's own [widthMHz]. The worst case the mask allows.
double integratedLeakageDbr(
  AciMaskFamily family,
  int widthMHz,
  double offsetMHz,
) {
  final double off = offsetMHz.abs();
  return _leakCache.putIfAbsent((family, widthMHz, off), () {
    final double half = widthMHz / 2;
    final double victim = _integrate(family, widthMHz, off - 10, off + 10);
    final double own = _integrate(family, widthMHz, -half, half);
    return 10 * FsplMath.log10(victim / own);
  });
}

// ── Channel choice ──────────────────────────────────────────────────────────

/// How far the neighbor's channel sits from the receiver's.
enum AciSeparation {
  /// 5 and 6 GHz: the channels touch edge to edge.
  adjacent('Next channel', 0),

  /// 5 and 6 GHz: one empty 20 MHz channel between them.
  oneGap('One channel gap', 1),

  /// 5 and 6 GHz: two empty 20 MHz channels between them.
  twoGaps('Two channel gaps', 2),

  /// 2.4 GHz, the 1/6/11 plan: 25 MHz apart.
  ch1and6('1 and 6 (25 MHz)', null, 1, 6),

  /// 2.4 GHz, the 1/4/8/11 plan's 20 MHz pair.
  ch4and8('4 and 8 (20 MHz)', null, 4, 8),

  /// 2.4 GHz, the 1/4/8/11 plan's 15 MHz pair.
  ch1and4('1 and 4 (15 MHz)', null, 1, 4);

  const AciSeparation(
    this.label,
    this.gaps, [
    this.neighbor24Channel,
    this.receiver24Channel,
  ]);

  final String label;

  /// Empty 20 MHz channels between the two (5 and 6 GHz), or null for a 2.4
  /// GHz channel pair.
  final int? gaps;

  /// 2.4 GHz only: the neighbor's channel.
  final int? neighbor24Channel;

  /// 2.4 GHz only: the receiver's channel.
  final int? receiver24Channel;

  /// True for the next channel. Every 2.4 GHz pair counts as next-channel:
  /// their centers are 15 to 25 MHz apart, about one channel width.
  bool get isAdjacent => gaps == null || gaps == 0;

  /// The separations offered in [band], in order of growing distance for 5
  /// and 6 GHz and of the plans for 2.4 GHz.
  static List<AciSeparation> forBand(WifiBand band) => band == WifiBand.band24
      ? const <AciSeparation>[
          AciSeparation.ch1and6,
          AciSeparation.ch4and8,
          AciSeparation.ch1and4,
        ]
      : const <AciSeparation>[
          AciSeparation.adjacent,
          AciSeparation.oneGap,
          AciSeparation.twoGaps,
        ];
}

/// The two channels, resolved from band, width and separation only.
class AciChannelPlan {
  const AciChannelPlan({
    required this.band,
    required this.neighborWidthMHz,
    required this.neighborChannel,
    required this.neighborComponents,
    required this.neighborCenterMHz,
    required this.receiverChannel,
    required this.receiverCenterMHz,
  });

  final WifiBand band;
  final int neighborWidthMHz;

  /// The neighbor's channel number: its 20 MHz channel, or the center
  /// designator of a wider channel.
  final int neighborChannel;

  /// The 20 MHz channels the neighbor occupies.
  final List<int> neighborComponents;
  final double neighborCenterMHz;

  /// The receiver's 20 MHz channel.
  final int receiverChannel;
  final double receiverCenterMHz;

  double get neighborLowMHz => neighborCenterMHz - neighborWidthMHz / 2;
  double get neighborHighMHz => neighborCenterMHz + neighborWidthMHz / 2;
  double get receiverLowMHz => receiverCenterMHz - 10;
  double get receiverHighMHz => receiverCenterMHz + 10;

  /// Center to center, MHz.
  double get spacingMHz => receiverCenterMHz - neighborCenterMHz;

  /// Empty spectrum between the two channels' edges, MHz (negative when the
  /// 2.4 GHz channels overlap on paper).
  double get edgeGapMHz => receiverLowMHz - neighborHighMHz;

  /// "ch 36" or "ch 42 (36 to 48)".
  String get neighborLabel => neighborComponents.length == 1
      ? 'ch $neighborChannel'
      : 'ch $neighborChannel (${neighborComponents.first} to '
            '${neighborComponents.last})';

  String get receiverLabel => 'ch $receiverChannel';
}

/// The 20 MHz channel the neighbor's wide channel is built from in each band:
/// the lowest channel of a block that has room for the receiver's channels
/// above it (5 GHz 160 MHz uses 100 to 128, since 64 has no neighbor above
/// in the 5 GHz plan until 100).
int _neighborPrimary(WifiBand band, int widthMHz) => switch (band) {
  WifiBand.band24 => 1,
  WifiBand.band5 => widthMHz == 160 ? 100 : 36,
  WifiBand.band6 => 1,
};

/// Resolves the two channels. Throws on a combination the band does not
/// allow (the controller never asks for one).
AciChannelPlan resolveAciPlan(
  WifiBand band,
  int neighborWidthMHz,
  AciSeparation separation,
) {
  if (band == WifiBand.band24) {
    final int? n = separation.neighbor24Channel;
    final int? r = separation.receiver24Channel;
    if (n == null || r == null || neighborWidthMHz != 20) {
      throw ArgumentError('2.4 GHz takes a channel pair at 20 MHz');
    }
    return AciChannelPlan(
      band: band,
      neighborWidthMHz: 20,
      neighborChannel: n,
      neighborComponents: <int>[n],
      neighborCenterMHz: channelToFrequency(band, n)!.toDouble(),
      receiverChannel: r,
      receiverCenterMHz: channelToFrequency(band, r)!.toDouble(),
    );
  }
  final int? gaps = separation.gaps;
  if (gaps == null) throw ArgumentError('$separation is a 2.4 GHz pair');
  final BondedChannel? b = bondedChannel(
    band: band,
    primaryChannel: _neighborPrimary(band, neighborWidthMHz),
    widthMHz: neighborWidthMHz,
  );
  if (b == null) throw ArgumentError.value(neighborWidthMHz, 'width');
  final int rxCenter = b.highEdgeMHz + 10 + 20 * gaps;
  final int rxChannel = (rxCenter - band.startFreqMHz) ~/ 5;
  if (!isValid20MhzPrimary(band, rxChannel)) {
    throw StateError('receiver channel $rxChannel is not on the plan');
  }
  return AciChannelPlan(
    band: band,
    neighborWidthMHz: neighborWidthMHz,
    neighborChannel: b.centerChannel,
    neighborComponents: b.components,
    neighborCenterMHz: b.centerFreqMHz.toDouble(),
    receiverChannel: rxChannel,
    receiverCenterMHz: channelToFrequency(band, rxChannel)!.toDouble(),
  );
}

// ── Receiver selectivity and the standard's reference table ───────────────

/// ILLUSTRATIVE selectivity defaults, dB (Pax's inference, 2026-09-27: the
/// non-adjacent value is the adjacent one + 16 dB, mirroring the standard's
/// constant 16 dB gap between adjacent and non-adjacent rejection).
const double kAciDefaultSelectivityAdjacentDb = 35;
const double kAciDefaultSelectivityNonAdjacentDb = 51;

/// The standard's minimum adjacent-channel rejection (ACR), dB, MCS 0 to 13,
/// same-width interferer one channel width away. Via a 2024 802.11be test
/// white paper, Table 6-5 (the standard itself was not read). REFERENCE ONLY:
/// it is a pass/fail ratio measured with each MCS's signal requirement
/// already folded in, so it is shown, never fed into the SINR.
const List<double> kAciStandardAcrDb = <double>[
  16, 13, 11, 8, 4, 0, -1, -2, -7, -9, -12, -14, -17, -20, //
];

/// The standard's non-adjacent rejection is ACR + 16 dB at every MCS.
double aciStandardNonAdjacentDb(int mcs) => kAciStandardAcrDb[mcs] + 16;

/// Who is listening: sets the labels only; the math is the same.
enum AciListener {
  client('Your client (downlink)', 'Your client', 'Your AP'),
  ap('Your AP (uplink)', 'Your AP', 'Your client');

  const AciListener(this.label, this.receiverName, this.wantedName);
  final String label;

  /// The radio that receives.
  final String receiverName;

  /// The radio that sends the wanted signal.
  final String wantedName;
}

// ── Configuration ───────────────────────────────────────────────────────────

/// Every input. Immutable; the controller swaps in a new one per change.
class AciConfig {
  const AciConfig({
    this.band = WifiBand.band5,
    this.family = AciMaskFamily.heEht,
    this.neighborWidthMHz = 20,
    this.separation = AciSeparation.oneGap,
    this.listener = AciListener.ap,
    this.neighborDistanceM = 3,
    this.neighborPowerDbm = 20,
    this.wantedDistanceM = 10,
    this.wantedPowerDbm = 20,
    this.pathLossExponent = 3,
    this.selectivityAdjacentDb = kAciDefaultSelectivityAdjacentDb,
    this.selectivityNonAdjacentDb = kAciDefaultSelectivityNonAdjacentDb,
    this.ccaThresholdDbm = kAciDefaultCcaDbm,
  });

  final WifiBand band;
  final AciMaskFamily family;
  final int neighborWidthMHz;
  final AciSeparation separation;
  final AciListener listener;

  /// Receiver to neighbor, m.
  final double neighborDistanceM;

  /// Neighbor transmit power, dBm, antenna gain included.
  final double neighborPowerDbm;

  /// Receiver to wanted transmitter, m.
  final double wantedDistanceM;

  /// Wanted transmitter power, dBm, antenna gain included.
  final double wantedPowerDbm;
  final double pathLossExponent;

  /// ILLUSTRATIVE receiver selectivity for the next channel, dB.
  final double selectivityAdjacentDb;

  /// ILLUSTRATIVE receiver selectivity for one gap or more, dB.
  final double selectivityNonAdjacentDb;

  /// Energy-detect threshold, dBm per 20 MHz.
  final double ccaThresholdDbm;

  /// The selectivity that applies at this separation.
  double get selectivityDb =>
      separation.isAdjacent ? selectivityAdjacentDb : selectivityNonAdjacentDb;

  AciConfig copyWith({
    WifiBand? band,
    AciMaskFamily? family,
    int? neighborWidthMHz,
    AciSeparation? separation,
    AciListener? listener,
    double? neighborDistanceM,
    double? neighborPowerDbm,
    double? wantedDistanceM,
    double? wantedPowerDbm,
    double? pathLossExponent,
    double? selectivityAdjacentDb,
    double? selectivityNonAdjacentDb,
    double? ccaThresholdDbm,
  }) => AciConfig(
    band: band ?? this.band,
    family: family ?? this.family,
    neighborWidthMHz: neighborWidthMHz ?? this.neighborWidthMHz,
    separation: separation ?? this.separation,
    listener: listener ?? this.listener,
    neighborDistanceM: neighborDistanceM ?? this.neighborDistanceM,
    neighborPowerDbm: neighborPowerDbm ?? this.neighborPowerDbm,
    wantedDistanceM: wantedDistanceM ?? this.wantedDistanceM,
    wantedPowerDbm: wantedPowerDbm ?? this.wantedPowerDbm,
    pathLossExponent: pathLossExponent ?? this.pathLossExponent,
    selectivityAdjacentDb: selectivityAdjacentDb ?? this.selectivityAdjacentDb,
    selectivityNonAdjacentDb:
        selectivityNonAdjacentDb ?? this.selectivityNonAdjacentDb,
    ccaThresholdDbm: ccaThresholdDbm ?? this.ccaThresholdDbm,
  );

  /// The same settings with the selectivity for the current separation
  /// replaced.
  AciConfig withSelectivity(double db) => separation.isAdjacent
      ? copyWith(selectivityAdjacentDb: db)
      : copyWith(selectivityNonAdjacentDb: db);
}

/// Energy-detect threshold, dBm per 20 MHz (brief §4). The same value as
/// Channel Planner's CcaRule.energyDetect; a test holds the two together.
const double kAciDefaultCcaDbm = -62;

/// Input ranges.
abstract final class AciLimits {
  static const double neighborDistanceMin = 0.3;
  static const double neighborDistanceMax = 30;
  static const double wantedDistanceMin = 1;
  static const double wantedDistanceMax = 60;
  static const double powerMin = 0;
  static const double powerMax = 30;
  static const double exponentMin = 2;
  static const double exponentMax = 4;
  static const double selectivityMin = 20;
  static const double selectivityMax = 60;
  static const double ccaMin = -82;
  static const double ccaMax = -52;
}

// ── Result ──────────────────────────────────────────────────────────────────

class AciResult {
  const AciResult({
    required this.config,
    required this.plan,
    required this.receiverNoiseDbm,
    required this.wantedDbm,
    required this.neighborDbm,
    required this.maskAtReceiverCenterDbr,
    required this.maskAtNearEdgeDbr,
    required this.maskAtFarEdgeDbr,
    required this.leakageDbr,
    required this.leakageDbm,
    required this.selectivityDb,
    required this.filteredDbm,
    required this.effectiveInterferenceDbm,
    required this.sirDb,
    required this.sinrDb,
    required this.snrDb,
    required this.mcsWithout,
    required this.mcsWith,
    required this.ccaBusy,
  });

  final AciConfig config;
  final AciChannelPlan plan;

  /// Receiver noise floor over 20 MHz, dBm (7 dB noise figure).
  final double receiverNoiseDbm;

  /// Wanted signal at the receiver, dBm.
  final double wantedDbm;

  /// The neighbor's in-channel power at the receiver, dBm.
  final double neighborDbm;

  /// The neighbor's mask at the receiver's center, dBr: NOT the leakage.
  final double maskAtReceiverCenterDbr;

  /// The mask at the receiver channel's edge nearer the neighbor, dBr.
  final double maskAtNearEdgeDbr;

  /// The mask at the receiver channel's far edge, dBr.
  final double maskAtFarEdgeDbr;

  /// Integrated leakage into the receiver's 20 MHz, dBr.
  final double leakageDbr;

  /// Leakage power in the receiver's 20 MHz, dBm.
  final double leakageDbm;

  /// Receiver selectivity at this separation, dB (illustrative).
  final double selectivityDb;

  /// What of the neighbor's own channel gets past the filter, dBm:
  /// neighbor power - selectivity.
  final double filteredDbm;

  /// Leakage + filtered, added in linear power, dBm.
  final double effectiveInterferenceDbm;

  /// Signal to interference ratio, dB.
  final double sirDb;

  /// Signal to interference plus noise ratio, dB.
  final double sinrDb;

  /// Signal to noise with no neighbor, dB.
  final double snrDb;

  /// Highest MCS with no neighbor, or null below MCS 0.
  final int? mcsWithout;

  /// Highest MCS with the neighbor, or null below MCS 0.
  final int? mcsWith;

  /// Energy detect fires on the effective interference.
  final bool ccaBusy;

  /// The SINR MCS [m] needs: its minimum sensitivity minus the noise floor.
  double requiredSinrDb(int m) =>
      RateVsRangeMath.sensitivityDbm(m, 20) - receiverNoiseDbm;

  /// The MCS the reference readout is about: the rate the link runs without
  /// the neighbor, or MCS 0 when even that fails.
  int get referenceMcs => mcsWithout ?? 0;
}

// ── The model ───────────────────────────────────────────────────────────────

/// Receiver noise figure, dB (Rate vs Range's default).
const double kAciNoiseFigureDb = RateVsRangeMath.defaultNoiseFigureDb;

/// RoamBand for the path loss reference frequency (2437, 5500 or 6525 MHz).
RoamBand aciRoamBand(WifiBand band) => switch (band) {
  WifiBand.band24 => RoamBand.b24,
  WifiBand.band5 => RoamBand.b5,
  WifiBand.band6 => RoamBand.b6,
};

/// Path loss, dB. At 1 m and beyond: FSPL(1 m) + 10 n log10(d). Below 1 m:
/// free space, FSPL(1 m) + 20 log10(d).
double aciPathLossDb(WifiBand band, double distanceM, double exponent) {
  final double n = distanceM < 1 ? 2 : exponent;
  return aciRoamBand(band).fspl1mDb + 10 * n * FsplMath.log10(distanceM);
}

double _dbSum(double a, double b) =>
    10 *
    FsplMath.log10(
      math.pow(10, a / 10).toDouble() + math.pow(10, b / 10).toDouble(),
    );

/// Computes every reading for [c]. Pure and deterministic.
AciResult computeAci(AciConfig c) {
  final AciChannelPlan plan = resolveAciPlan(
    c.band,
    c.neighborWidthMHz,
    c.separation,
  );
  final double noise = RateVsRangeMath.noiseFloorDbm(20, kAciNoiseFigureDb);
  final double wanted =
      c.wantedPowerDbm -
      aciPathLossDb(c.band, c.wantedDistanceM, c.pathLossExponent);
  final double neighbor =
      c.neighborPowerDbm -
      aciPathLossDb(c.band, c.neighborDistanceM, c.pathLossExponent);
  final double off = plan.spacingMHz;
  final double leakDbr = integratedLeakageDbr(
    c.family,
    c.neighborWidthMHz,
    off,
  );
  final double leakDbm = neighbor + leakDbr;

  final double selectivity = c.selectivityDb;
  final double filtered = neighbor - selectivity;
  // Formula (c): leakage and filtered in-channel power add in linear power.
  final double ieff = _dbSum(leakDbm, filtered);
  final double sinr = wanted - _dbSum(noise, ieff);

  int? mcsWith;
  for (int m = 0; m <= RateVsRangeMath.maxMcs; m++) {
    // SINR >= sensitivity - noise floor: the MCS's own requirement.
    if (sinr >= RateVsRangeMath.sensitivityDbm(m, 20) - noise) mcsWith = m;
  }

  return AciResult(
    config: c,
    plan: plan,
    receiverNoiseDbm: noise,
    wantedDbm: wanted,
    neighborDbm: neighbor,
    maskAtReceiverCenterDbr: aciMaskDbr(c.family, c.neighborWidthMHz, off),
    maskAtNearEdgeDbr: aciMaskDbr(c.family, c.neighborWidthMHz, off - 10),
    maskAtFarEdgeDbr: aciMaskDbr(c.family, c.neighborWidthMHz, off + 10),
    leakageDbr: leakDbr,
    leakageDbm: leakDbm,
    selectivityDb: selectivity,
    filteredDbm: filtered,
    effectiveInterferenceDbm: ieff,
    sirDb: wanted - ieff,
    sinrDb: sinr,
    snrDb: wanted - noise,
    mcsWithout: RateVsRangeMath.mcsFor(wanted, 20),
    mcsWith: mcsWith,
    ccaBusy: ieff >= c.ccaThresholdDbm,
  );
}

/// Spectral density of a transmitter's mask at the receiver, dBm per MHz, at
/// [freqMHz]: its received in-channel power spread over its mask. For the
/// stage's spectrum strip.
double aciPsdDbmPerMHz({
  required AciMaskFamily family,
  required int widthMHz,
  required double centerMHz,
  required double inChannelDbm,
  required double freqMHz,
}) {
  final double half = widthMHz / 2;
  final double own = _ownIntegralMHz.putIfAbsent((
    family,
    widthMHz,
  ), () => _integrate(family, widthMHz, -half, half));
  return inChannelDbm -
      10 * FsplMath.log10(own) +
      aciMaskDbr(family, widthMHz, freqMHz - centerMHz);
}

final Map<(AciMaskFamily, int), double> _ownIntegralMHz =
    <(AciMaskFamily, int), double>{};
