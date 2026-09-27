// Repeaters and Mesh Backhaul: the pure model for the Wi-Fi Classroom tool
// (repeater-mesh).
//
// CLEAN-ROOM BUILD (2026-09-26) per myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/36-repeater-mesh.md. The
// relay formula comes from Deliverables/2026-09-26-wifi-classroom-wave4-
// research/brief.md row J, where it is tagged INF: derived from airtime, not
// from a published multihop measurement.
//
// THE LESSON. A relay with one radio on one channel must receive a frame and
// then send it again on the same channel, so its hops take turns on the same
// air. If hop i alone would carry T_i, one unit of data costs 1/T_i of air
// time on that hop, and the chain costs the sum:
//
//   same channel, one radio:        1/T = 1/T_1 + 1/T_2 + ... + 1/T_n
//   dedicated backhaul radio:       T = min(T_i)   (every hop on its own
//                                                   channel, all at once)
//   wired backhaul:                 T = T_n        (only the last hop is
//                                                   on the air)
//
// Two equal hops give half; a slow hop drags the total toward itself.
//
// REUSED, NOT RE-DERIVED:
//   - path loss: Roaming Walk's RoamWalkConfig.meanRssiAtDistance
//     (roaming_walk_engine.dart), PL(d) = FSPL(1 m) + 10 n log10(d), with its
//     RoamBand frequencies (2437, 5500, 6525 MHz).
//   - MCS from received level: RateVsRangeMath.mcsFor, the Rate vs Range
//     tool's receiver-sensitivity table (rate_vs_range_math.dart).
//   - PHY rate of that MCS: Airtime Anatomy's computeAirtime
//     (airtime_anatomy.dart), an 802.11ax (HE) single-user frame, 2 spatial
//     streams, 0.8 us guard interval. HE stops at MCS 11, so a level good
//     enough for MCS 12 or 13 is held at 11.
//
// ILLUSTRATIVE (spec 36, and the screen says so): the efficiency factor
// (0.4 to 0.8, default 0.6) that turns a PHY rate into a hop throughput, the
// forwarding delay (default 1 ms per hop), the 20 dBm EIRP of every radio,
// the path-loss exponent 3.0 and the channel widths (20 MHz on 2.4 GHz,
// 80 MHz on 5 and 6 GHz).
//
// Pure Dart, no Flutter imports, deterministic: every input is explicit and
// nothing is random. Pinned by test/services/wifi_lab/repeater_mesh_model_
// test.dart.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'airtime_anatomy.dart';
import 'rate_vs_range_math.dart';
import 'roaming_walk_engine.dart';
import '../../units/length_format.dart';
import '../../units/unit_system.dart';

/// Stable catalog tool id: backs the route, the help entry and the tests.
const String kRepeaterMeshToolId = 'repeater-mesh';

/// Corridor length, meters. The root AP sits at 0.
const double kRmCorridorM = 60;

/// Relay count limits (spec 36: 1 to 3).
const int kRmMinRelays = 1;
const int kRmMaxRelays = 3;

/// Closest two nodes may stand, meters. Keeps every hop at or above the
/// 1 m the path-loss model is defined from, with room to grab each node.
const double kRmMinGapM = 2;

/// Efficiency factor limits and default (spec 36; illustrative).
const double kRmMinEfficiency = 0.4;
const double kRmMaxEfficiency = 0.8;
const double kRmDefaultEfficiency = 0.6;

/// Forwarding delay per hop, ms: limits and default (spec 36; illustrative).
const double kRmMinDelayMs = 0;
const double kRmMaxDelayMs = 10;
const double kRmDefaultDelayMs = 1;

/// Every radio's EIRP, dBm (illustrative).
const double kRmEirpDbm = 20;

/// Path-loss exponent (illustrative; Roaming Walk's default).
const double kRmExponent = 3;

/// Spatial streams on every link (illustrative).
const int kRmStreams = 2;

/// Highest MCS the 802.11ax rate table carries.
const int kRmMaxHeMcs = 11;

/// The band sets the path loss (through Roaming Walk's band) and the channel
/// width the rates are taken at.
enum RmBand {
  ghz24('2.4 GHz', RoamBand.b24, AirtimeBand.ghz24, 20),
  ghz5('5 GHz', RoamBand.b5, AirtimeBand.ghz5, 80),
  ghz6('6 GHz', RoamBand.b6, AirtimeBand.ghz6, 80);

  const RmBand(this.label, this.roamBand, this.airtimeBand, this.widthMHz);

  final String label;

  /// Roaming Walk's band: frequency for FSPL(1 m).
  final RoamBand roamBand;

  /// Airtime Anatomy's band, for the PHY rate.
  final AirtimeBand airtimeBand;

  /// Channel width every hop uses, MHz (illustrative).
  final int widthMHz;

  double get freqMHz => roamBand.freqMHz;
}

/// How the relays reach back toward the root AP.
enum RmBackhaul {
  /// One radio on one channel: the hops take turns.
  sameChannel(
    'Same channel, one radio',
    'Same channel',
    'Every hop shares one channel, so the hops take turns: '
        '1/T = 1/T1 + 1/T2 + ...',
  ),

  /// A second radio on another channel for the backhaul.
  dedicated(
    'Dedicated backhaul radio, another channel',
    'Dedicated radio',
    'Every hop has a channel of its own, so all hops send at once and the '
        'slowest hop sets the total.',
  ),

  /// A cable back to the root AP.
  wired(
    'Wired backhaul',
    'Wired',
    'A cable carries the backhaul, so only the last hop, to the client, is on '
        'the air.',
  );

  const RmBackhaul(this.label, this.short, this.rule);

  final String label;
  final String short;

  /// One sentence on the rule, for the controls.
  final String rule;
}

/// Everything the result depends on.
class RmConfig {
  RmConfig({
    List<double>? relaysM,
    this.clientM = 36,
    this.band = RmBand.ghz5,
    this.backhaul = RmBackhaul.sameChannel,
    this.efficiency = kRmDefaultEfficiency,
    this.forwardingDelayMs = kRmDefaultDelayMs,
  }) : relaysM = List<double>.unmodifiable(relaysM ?? const <double>[18]) {
    assert(this.relaysM.length >= kRmMinRelays);
    assert(this.relaysM.length <= kRmMaxRelays);
  }

  /// Relay positions along the corridor, meters from the root AP, in order.
  final List<double> relaysM;

  /// Client position, meters from the root AP, past the last relay.
  final double clientM;

  final RmBand band;
  final RmBackhaul backhaul;

  /// PHY rate to hop throughput, 0.4 to 0.8 (illustrative).
  final double efficiency;

  /// Added at every hop, ms (illustrative).
  final double forwardingDelayMs;

  int get relayCount => relaysM.length;

  /// Every node's position: root AP, relays, client.
  List<double> get nodesM => <double>[0, ...relaysM, clientM];

  RmConfig copyWith({
    List<double>? relaysM,
    double? clientM,
    RmBand? band,
    RmBackhaul? backhaul,
    double? efficiency,
    double? forwardingDelayMs,
  }) => RmConfig(
    relaysM: relaysM ?? this.relaysM,
    clientM: clientM ?? this.clientM,
    band: band ?? this.band,
    backhaul: backhaul ?? this.backhaul,
    efficiency: efficiency ?? this.efficiency,
    forwardingDelayMs: forwardingDelayMs ?? this.forwardingDelayMs,
  );

  /// [count] relays spaced evenly between the root AP and the client.
  RmConfig withRelayCount(int count) {
    final int n = count.clamp(kRmMinRelays, kRmMaxRelays);
    return copyWith(
      relaysM: <double>[
        for (int k = 1; k <= n; k++) _round1(clientM * k / (n + 1)),
      ],
    );
  }

  /// Moves node [index] (1 = the first relay, relayCount + 1 = the client;
  /// the root AP at 0 never moves) to [m], held between its neighbors.
  RmConfig withNodeAt(int index, double m) {
    final List<double> nodes = nodesM;
    if (index < 1 || index >= nodes.length) return this;
    final double lo = nodes[index - 1] + kRmMinGapM;
    final double hi = index == nodes.length - 1
        ? kRmCorridorM
        : nodes[index + 1] - kRmMinGapM;
    if (hi < lo) return this;
    final double v = _round1(m.clamp(lo, hi));
    if (index == nodes.length - 1) return copyWith(clientM: v);
    final List<double> relays = List<double>.of(relaysM);
    relays[index - 1] = v;
    return copyWith(relaysM: relays);
  }

  @override
  bool operator ==(Object other) =>
      other is RmConfig &&
      _listEq(other.relaysM, relaysM) &&
      other.clientM == clientM &&
      other.band == band &&
      other.backhaul == backhaul &&
      other.efficiency == efficiency &&
      other.forwardingDelayMs == forwardingDelayMs;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(relaysM),
    clientM,
    band,
    backhaul,
    efficiency,
    forwardingDelayMs,
  );
}

/// One radio link at one distance.
class RmLink {
  const RmLink({
    required this.distanceM,
    required this.rxDbm,
    required this.mcs,
    required this.phyMbps,
    required this.throughputMbps,
  });

  final double distanceM;

  /// Received level, dBm.
  final double rxDbm;

  /// MCS used, or null when even MCS 0 cannot be decoded (no link).
  final int? mcs;

  /// PHY rate, Mb/s (0 with no link).
  final double phyMbps;

  /// PHY rate x efficiency, Mb/s (0 with no link).
  final double throughputMbps;

  bool get hasLink => mcs != null;
}

/// One hop of the chain, from node [from] to node [from] + 1.
class RmHop {
  const RmHop({
    required this.from,
    required this.link,
    required this.wired,
    required this.airShare,
  });

  /// Index of the sending node toward the client (0 = root AP).
  final int from;
  final RmLink link;

  /// True when a cable carries this hop (wired backhaul, not the last hop).
  final bool wired;

  /// Share of the time this hop's channel is busy while the chain runs at
  /// its end-to-end throughput, 0 to 1. Zero for a wired hop.
  final double airShare;

  int get to => from + 1;
  double get throughputMbps => link.throughputMbps;
}

/// Everything the screen shows.
class RmResult {
  const RmResult({
    required this.config,
    required this.hops,
    required this.endToEndMbps,
    required this.delayMs,
    required this.direct,
    required this.directDelayMs,
    required this.bottleneck,
  });

  final RmConfig config;
  final List<RmHop> hops;

  /// What the client gets through the chain, Mb/s.
  final double endToEndMbps;

  /// Forwarding delay summed over the hops, ms.
  final double delayMs;

  /// The client connected straight to the root AP at the same spot.
  final RmLink direct;

  /// One hop's forwarding delay, ms.
  final double directDelayMs;

  /// Index into [hops] of the hop that limits the total (the slowest radio
  /// hop), or null when no hop has a link.
  final int? bottleneck;

  /// End-to-end over the straight-to-AP throughput, or null when the client
  /// cannot reach the AP directly.
  double? get versusDirect =>
      direct.hasLink ? endToEndMbps / direct.throughputMbps : null;

  /// True when exactly one radio hop is the slowest. Equal hops have no
  /// single slowest one, and the screen does not mark one.
  bool get slowestIsUnique {
    final int? b = bottleneck;
    if (b == null) return false;
    final double t = hops[b].throughputMbps;
    return hops.where((RmHop h) => !h.wired && h.throughputMbps == t).length ==
        1;
  }

  /// True when some radio hop the chain needs has no link.
  bool get broken => hops.any((RmHop h) => !h.wired && !h.link.hasLink);
}

/// The PHY rate at [mcs], Mb/s: Airtime Anatomy's 802.11ax single-user
/// frame on [band] at its width, [kRmStreams] streams, 0.8 us guard interval.
double rmPhyRateMbps(RmBand band, int mcs) => computeAirtime(
  AirtimeScenario(
    band: band.airtimeBand,
    phy: AirtimePhy.he,
    widthMhz: band.widthMHz,
    mcs: mcs.clamp(0, kRmMaxHeMcs),
    streams: kRmStreams,
    guardInterval: GuardInterval.gi08,
  ),
).phyRateMbps;

/// Received level at [distanceM] on [band], dBm: Roaming Walk's log-distance
/// path loss from a [kRmEirpDbm] transmitter to a 0 dBi receiver.
double rmRxDbm(RmBand band, double distanceM) => RoamWalkConfig(
  band: band.roamBand,
  eirpDbm: kRmEirpDbm,
  pathLossExponent: kRmExponent,
).meanRssiAtDistance(distanceM);

/// One radio link of [distanceM] on [band] at [efficiency].
RmLink rmLink(RmBand band, double distanceM, double efficiency) {
  final double rx = rmRxDbm(band, distanceM);
  final int? found = RateVsRangeMath.mcsFor(rx, band.widthMHz);
  final int? mcs = found == null ? null : math.min(found, kRmMaxHeMcs);
  final double phy = mcs == null ? 0 : rmPhyRateMbps(band, mcs);
  return RmLink(
    distanceM: distanceM,
    rxDbm: rx,
    mcs: mcs,
    phyMbps: phy,
    throughputMbps: phy * efficiency,
  );
}

/// End-to-end throughput of hops that alone carry [hopMbps], Mb/s, under
/// [backhaul]. Any zero on a hop the chain needs gives zero.
///   same channel: 1/T = sum of 1/T_i
///   dedicated:    T = min T_i
///   wired:        T = the last hop
double rmCombine(List<double> hopMbps, RmBackhaul backhaul) {
  if (hopMbps.isEmpty) return 0;
  switch (backhaul) {
    case RmBackhaul.wired:
      return math.max(0, hopMbps.last);
    case RmBackhaul.dedicated:
      return math.max(0, hopMbps.reduce(math.min));
    case RmBackhaul.sameChannel:
      double sum = 0;
      for (final double t in hopMbps) {
        if (t <= 0) return 0;
        sum += 1 / t;
      }
      return 1 / sum;
  }
}

/// Runs the model.
RmResult computeRepeaterMesh(RmConfig c) {
  final List<double> nodes = c.nodesM;
  final int hopCount = nodes.length - 1;
  final List<RmLink> links = <RmLink>[
    for (int i = 0; i < hopCount; i++)
      rmLink(c.band, (nodes[i + 1] - nodes[i]).abs(), c.efficiency),
  ];
  bool isWired(int i) => c.backhaul == RmBackhaul.wired && i < hopCount - 1;

  final double total = rmCombine(<double>[
    for (final RmLink l in links) l.throughputMbps,
  ], c.backhaul);

  // Each radio hop is busy for total / T_i of the time: on one shared
  // channel these add to 1; on channels of their own the slowest is 1.
  double share(int i) {
    if (isWired(i)) return 0;
    final double t = links[i].throughputMbps;
    if (t <= 0 || total <= 0) return 0;
    return (total / t).clamp(0.0, 1.0);
  }

  int? slowest;
  for (int i = 0; i < hopCount; i++) {
    if (isWired(i)) continue;
    if (slowest == null ||
        links[i].throughputMbps < links[slowest].throughputMbps) {
      slowest = i;
    }
  }

  return RmResult(
    config: c,
    hops: <RmHop>[
      for (int i = 0; i < hopCount; i++)
        RmHop(from: i, link: links[i], wired: isWired(i), airShare: share(i)),
    ],
    endToEndMbps: total,
    delayMs: c.forwardingDelayMs * hopCount,
    direct: rmLink(c.band, c.clientM, c.efficiency),
    directDelayMs: c.forwardingDelayMs,
    bottleneck: slowest,
  );
}

/// Formats Mb/s: 86.47 -> "86.5 Mb/s", 1201.04 -> "1201 Mb/s".
String rmMbps(double v) {
  if (v <= 0) return '0 Mb/s';
  if (v >= 1000) return '${v.round()} Mb/s';
  return '${v.toStringAsFixed(1)} Mb/s';
}

/// Formats a distance along the corridor: 18 -> "18 m", 18.5 -> "18.5 m".
String rmMeters(double m, [UnitSystem u = UnitSystem.metric]) {
  if (!u.isMetric) return '${LengthUnits.metresToFeet(m).round()} ft';
  return m == m.roundToDouble()
      ? '${m.round()} m'
      : '${m.toStringAsFixed(1)} m';
}

/// Formats a delay: 1 -> "1 ms", 0.5 -> "0.5 ms".
String rmMs(double ms) => ms == ms.roundToDouble()
    ? '${ms.round()} ms'
    : '${ms.toStringAsFixed(1)} ms';

/// The name of node [index] in a chain with [relayCount] relays.
String rmNodeName(int index, int relayCount) {
  if (index == 0) return 'AP';
  if (index == relayCount + 1) return 'Client';
  return relayCount == 1 ? 'Relay' : 'Relay $index';
}

double _round1(double v) => (v * 10).roundToDouble() / 10;

bool _listEq(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
