// Channel planning model for the Wi-Fi Classroom Channel Planner (channel-planner).
//
// CLEAN-ROOM BUILD (2026-09-25) per myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/16-channel-planner.md, with
// every number from the wave-3 research brief (same Deliverables date,
// wifi-lab-wave3-research/brief.md §2 and §4) or from this app's own channel
// data (lib/data/channel_frequency_data.dart). No Flutter widgets; every
// number the screen shows is pinned by
// test/services/wifi_lab/channel_planner_model_test.dart.
//
// WHAT IT MODELS
//   - Which channels a region allows at each width (US, EU; DFS and U-NII-4
//     toggles), counted from the app's channel sets and bonding groups. EU
//     5 GHz is the two EN 301 893 sub-bands, 5150-5350 and 5470-5725 MHz;
//     a channel is in only if its edges are, which drops 144 (5710-5730).
//   - Received power between two APs: EIRP minus log-distance path loss
//     (FSPL at 1 m plus 10 n log10 d) minus a flat loss per wall crossed.
//   - Whether one AP defers to another (clear channel assessment):
//       preamble on the primary 20 MHz at or above -82 dBm,
//       signal on a secondary 20 MHz at or above -72 dBm (5 GHz, VHT and
//       later; 2.4 GHz 40 MHz is HT, where secondaries use energy only),
//       energy anywhere in the overlap at or above -62 dBm.
//     Levels are per 20 MHz: a wide transmission spreads its power, so each
//     20 MHz piece carries total - 10 log10(width / 20). Channels that do not
//     overlap in frequency never contend.
//   - 2.4 GHz adjacent-channel energy from the transmit masks (OFDM and
//     DSSS), interpolated linearly in dB between breakpoints and then
//     integrated over the victim's 20 MHz. The mask is a ceiling on the
//     transmitter, so the result is the worst case the mask allows, not what
//     a real radio emits.
//   - Contention domains: the largest set of APs in which every pair defers
//     to each other (a clique of mutual deferral). Each member gets 1/N of
//     the airtime in the even-split teaching approximation.
//   - Auto-plan: a greedy assignment that minimizes the largest contention
//     domain. A teaching heuristic, not a vendor RRM algorithm.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import '../../data/channel_frequency_data.dart';
import 'fspl_math.dart';

// ── Enums ─────────────────────────────────────────────────────────────────

/// The two bands this planner covers. 6 GHz channel planning is not in
/// scope (spec 17 covers 6 GHz power).
enum PlannerBand {
  band24('2.4 GHz', WifiBand.band24, 2437),
  band5('5 GHz', WifiBand.band5, 5500);

  const PlannerBand(this.label, this.wifiBand, this.pathLossFreqMHz);
  final String label;
  final WifiBand wifiBand;

  /// One reference frequency per band for path loss, so the loss from A to B
  /// equals the loss from B to A (channel 6 and channel 100).
  final double pathLossFreqMHz;

  List<int> get widths => this == PlannerBand.band24
      ? const <int>[20, 40]
      : const <int>[20, 40, 80, 160];
}

enum PlannerRegion {
  us('US'),
  eu('EU');

  const PlannerRegion(this.label);
  final String label;
}

/// The 2.4 GHz transmit mask used for adjacent-channel energy.
enum TxMask {
  ofdm('OFDM (g/n/ax)'),
  dsss('DSSS (802.11b)');

  const TxMask(this.label);
  final String label;
}

/// Which clear-channel-assessment rule made an AP defer.
enum CcaRule {
  preambleDetect(-82, 'PD', 'Preamble on the primary 20 MHz'),
  secondarySignal(-72, 'SD', 'Signal on a secondary 20 MHz'),
  energyDetect(-62, 'ED', 'Energy in the overlap');

  const CcaRule(this.thresholdDbm, this.short, this.label);

  /// Level at or above which the rule fires, dBm per 20 MHz.
  final double thresholdDbm;
  final String short;
  final String label;
}

// ── Regulatory data ───────────────────────────────────────────────────────

/// EU 5 GHz sub-bands, ETSI EN 301 893 Table 2 (brief §4): 5150-5350 and
/// 5470-5725 MHz.
const List<(int, int)> kEu5GhzSubBandsMHz = <(int, int)>[
  (5150, 5350),
  (5470, 5725),
];

/// The rules that decide which channels exist on the plan.
class PlanRules {
  const PlanRules({
    this.band = PlannerBand.band5,
    this.region = PlannerRegion.us,
    this.dfs = false,
    this.unii4 = false,
    this.mask = TxMask.ofdm,
  });

  final PlannerBand band;
  final PlannerRegion region;

  /// Include DFS channels (5 GHz 52-64 and 100-144).
  final bool dfs;

  /// Include U-NII-4 (169-177). US only; ignored in the EU.
  final bool unii4;

  /// 2.4 GHz transmit mask. DSSS only exists at 20 MHz.
  final TxMask mask;

  PlanRules copyWith({
    PlannerBand? band,
    PlannerRegion? region,
    bool? dfs,
    bool? unii4,
    TxMask? mask,
  }) => PlanRules(
    band: band ?? this.band,
    region: region ?? this.region,
    dfs: dfs ?? this.dfs,
    unii4: unii4 ?? this.unii4,
    mask: mask ?? this.mask,
  );

  /// Half the occupied width of one 20 MHz channel, MHz. DSSS occupies
  /// 22 MHz, so its edges sit 11 MHz from center.
  double get halfWidth20 =>
      band == PlannerBand.band24 && mask == TxMask.dsss ? 11 : 10;

  /// Widths that exist under these rules.
  List<int> get widths => band == PlannerBand.band24 && mask == TxMask.dsss
      ? const <int>[20]
      : band.widths;
}

/// Center frequency of a 20 MHz channel, MHz.
int centerMHz(PlannerBand band, int channel) =>
    channelToFrequency(band.wifiBand, channel)!;

/// The 20 MHz channels the rules allow, ascending.
List<int> allowed20(PlanRules r) {
  if (r.band == PlannerBand.band24) {
    final int top = r.region == PlannerRegion.us ? 11 : 13;
    return <int>[
      for (final int c in k24Channels)
        if (c <= top) c,
    ];
  }
  final List<int> out = <int>[];
  for (final int c in k5Channels) {
    if (!r.dfs && k5Dfs.contains(c)) continue;
    if (r.region == PlannerRegion.us) {
      if (k5Unii4.contains(c) && !r.unii4) continue;
    } else {
      final int f = centerMHz(r.band, c);
      final bool inside = kEu5GhzSubBandsMHz.any(
        ((int, int) sb) => f - 10 >= sb.$1 && f + 10 <= sb.$2,
      );
      if (!inside) continue;
    }
    out.add(c);
  }
  return out;
}

/// One channel of a given width: its 20 MHz components and occupied edges.
class ChannelGroup {
  ChannelGroup(this.band, this.components, {required double halfWidth20})
    : width = components.length * 20,
      lowMHz = centerMHz(band, components.first) - halfWidth20,
      highMHz = centerMHz(band, components.last) + halfWidth20;

  final PlannerBand band;

  /// Contiguous 20 MHz channels, ascending.
  final List<int> components;
  final int width;
  final double lowMHz;
  final double highMHz;

  double get centerFreqMHz => (lowMHz + highMHz) / 2;
  bool get hasDfs =>
      band == PlannerBand.band5 && components.any(k5Dfs.contains);

  /// `36` at 20 MHz, `36-48` when bonded.
  String get span => components.length == 1
      ? '${components.first}'
      : '${components.first}-${components.last}';

  bool overlaps(ChannelGroup o) => lowMHz < o.highMHz && o.lowMHz < highMHz;

  @override
  bool operator ==(Object other) =>
      other is ChannelGroup &&
      other.band == band &&
      other.lowMHz == lowMHz &&
      other.highMHz == highMHz;

  @override
  int get hashCode => Object.hash(band, lowMHz, highMHz);
}

/// Every channel of [width] the rules allow (in 2.4 GHz these overlap).
List<ChannelGroup> channelGroups(PlanRules r, int width) {
  if (!r.widths.contains(width)) return const <ChannelGroup>[];
  final Set<int> ok = allowed20(r).toSet();
  final List<List<int>> raw = width == 20
      ? <List<int>>[
          for (final int c in ok.toList()..sort()) <int>[c],
        ]
      : bondingGroups(r.band.wifiBand, width);
  return <ChannelGroup>[
    for (final List<int> g in raw)
      if (g.every(ok.contains))
        ChannelGroup(r.band, g, halfWidth20: r.halfWidth20),
  ];
}

/// The channels that fit side by side without overlapping, the ones a plan
/// reuses. In 5 GHz that is every group. In 2.4 GHz it is the most channels
/// whose edges do not overlap, spread as far apart as the band allows: 1, 6
/// and 11 in the US; 1, 5, 9 and 13 in the EU with OFDM.
List<ChannelGroup> planChannels(PlanRules r, int width) {
  final List<ChannelGroup> all = channelGroups(r, width);
  if (r.band == PlannerBand.band5 || all.isEmpty) return all;
  // Greedy packing gives the count; spreading gives the widest spacing.
  int count = 0;
  double edge = double.negativeInfinity;
  for (final ChannelGroup g in all) {
    if (g.lowMHz >= edge) {
      count++;
      edge = g.highMHz;
    }
  }
  if (count == 1) return <ChannelGroup>[all.first];
  final List<ChannelGroup> out = <ChannelGroup>[];
  for (int i = 0; i < count; i++) {
    out.add(all[(i * (all.length - 1) / (count - 1)).round()]);
  }
  // Spreading can only widen gaps, but check rather than trust it.
  for (int i = 1; i < out.length; i++) {
    if (out[i].overlaps(out[i - 1])) {
      return _greedy(all);
    }
  }
  return out;
}

List<ChannelGroup> _greedy(List<ChannelGroup> all) {
  final List<ChannelGroup> out = <ChannelGroup>[];
  for (final ChannelGroup g in all) {
    if (out.isEmpty || g.lowMHz >= out.last.highMHz) out.add(g);
  }
  return out;
}

/// "Channels available at this width": the count a plan can reuse.
int channelsAvailable(PlanRules r, int width) => planChannels(r, width).length;

/// An AP's operating channel: a group plus which component is primary.
class ChannelOption {
  const ChannelOption(this.group, this.primary);
  final ChannelGroup group;
  final int primary;

  int get width => group.width;
  PlannerBand get band => group.band;

  /// The secondary 20 MHz: the other half of the 40 MHz pair that holds the
  /// primary. Null at 20 MHz.
  int? get secondary20 {
    if (group.width == 20) return null;
    if (band == PlannerBand.band24) {
      return group.components.firstWhere((int c) => c != primary);
    }
    for (final List<int> pair in k5Bond40) {
      if (pair.contains(primary)) {
        return pair.firstWhere((int c) => c != primary);
      }
    }
    return null;
  }

  /// `36/80` on the floor; `6` at 20 MHz.
  String get shortLabel => width == 20 ? '$primary' : '$primary/$width';

  /// `Primary 36, spans 36-48, DFS`.
  String get longLabel {
    final String dfs = group.hasDfs ? ', DFS' : '';
    if (width == 20) {
      return '$primary (${centerMHz(band, primary)} MHz)$dfs';
    }
    return 'Primary $primary, spans ${group.span}$dfs';
  }

  @override
  bool operator ==(Object other) =>
      other is ChannelOption &&
      other.group == group &&
      other.primary == primary;

  @override
  int get hashCode => Object.hash(group, primary);
}

/// Every channel an AP can pick at [width], one per group and primary.
List<ChannelOption> channelOptions(PlanRules r, int width) => <ChannelOption>[
  for (final ChannelGroup g in channelGroups(r, width))
    for (final int p in g.components) ChannelOption(g, p),
];

// ── Transmit masks (brief §4) ─────────────────────────────────────────────

/// Mask breakpoints (offset MHz, dBr). Between points the mask is linear in
/// dB; a repeated offset is a step. Past the last point it stays flat.
const Map<TxMask, List<(double, double)>> kMaskBreakpoints =
    <TxMask, List<(double, double)>>{
      // OFDM 20 MHz (802.11a/g): 0 dBr to 9 MHz, -20 at 11, -28 at 20,
      // -40 at 30 and beyond.
      TxMask.ofdm: <(double, double)>[
        (0, 0),
        (9, 0),
        (11, -20),
        (20, -28),
        (30, -40),
      ],
      // DSSS/CCK (802.11b): -30 dBr from 11 to 22 MHz, -50 beyond 22.
      TxMask.dsss: <(double, double)>[
        (0, 0),
        (11, 0),
        (11, -30),
        (22, -30),
        (22, -50),
      ],
    };

/// Mask ceiling in dBr at [offsetMHz] from the transmitter's center.
double maskDbr(TxMask mask, double offsetMHz) {
  final double f = offsetMHz.abs();
  final List<(double, double)> pts = kMaskBreakpoints[mask]!;
  for (int i = 1; i < pts.length; i++) {
    final (double x0, double y0) = pts[i - 1];
    final (double x1, double y1) = pts[i];
    if (f > x1) continue;
    if (x1 == x0) return f < x1 ? y0 : y1;
    if (f == x1 && i + 1 < pts.length && pts[i + 1].$1 == x1) return y1;
    return y0 + (y1 - y0) * (f - x0) / (x1 - x0);
  }
  return pts.last.$2;
}

final Map<(TxMask, double), double> _aciCache = <(TxMask, double), double>{};

/// Adjacent-channel energy, dB relative to the transmitter's in-channel
/// power: the mask integrated over the victim's 20 MHz, centered
/// [offsetMHz] away, divided by the mask integrated over the transmitter's
/// own occupied width. The worst case the mask allows.
double adjacentChannelDb(TxMask mask, double offsetMHz) {
  final double off = offsetMHz.abs();
  return _aciCache.putIfAbsent((mask, off), () {
    final double own = mask == TxMask.dsss ? 11 : 10;
    return 10 *
        FsplMath.log10(
          _integrate(mask, off - 10, off + 10) / _integrate(mask, -own, own),
        );
  });
}

double _integrate(TxMask mask, double a, double b) {
  const double step = 0.01;
  final int n = ((b - a) / step).round();
  double sum = 0;
  for (int i = 0; i < n; i++) {
    final double f = a + (i + 0.5) * step;
    sum += math.pow(10, maskDbr(mask, f) / 10) * step;
  }
  return sum;
}

// ── Deferral between two APs ──────────────────────────────────────────────

/// What an observing AP does when another AP transmits.
class Deferral {
  const Deferral({
    required this.overlaps,
    required this.rule,
    required this.levelDbm,
  });

  /// The two channels share spectrum.
  final bool overlaps;

  /// The rule that fired, or null when the observer does not defer.
  final CcaRule? rule;

  /// The level compared against the rule's threshold (dBm per 20 MHz). When
  /// no rule fired, the strongest level the observer saw; null when the
  /// channels do not overlap.
  final double? levelDbm;

  bool get defers => rule != null;

  static const Deferral none = Deferral(
    overlaps: false,
    rule: null,
    levelDbm: null,
  );
}

/// Does [observer] defer when [transmitter] sends at [rxTotalDbm] total
/// received power? Channels that do not overlap never cause deferral.
Deferral evaluateDeferral({
  required ChannelOption observer,
  required ChannelOption transmitter,
  required double rxTotalDbm,
  TxMask mask = TxMask.ofdm,
}) {
  if (!observer.group.overlaps(transmitter.group)) return Deferral.none;
  final PlannerBand band = observer.band;
  final double per20 =
      rxTotalDbm -
      10 * FsplMath.log10(transmitter.group.components.length.toDouble());
  final Set<int> txComps = transmitter.group.components.toSet();

  // A wide PPDU repeats its legacy preamble in every 20 MHz piece, so the
  // observer can decode it on its primary if the primary is one of them.
  if (txComps.contains(observer.primary)) {
    if (per20 >= CcaRule.preambleDetect.thresholdDbm) {
      return Deferral(
        overlaps: true,
        rule: CcaRule.preambleDetect,
        levelDbm: per20,
      );
    }
    return Deferral(overlaps: true, rule: null, levelDbm: per20);
  }

  final int? sec = observer.secondary20;
  if (band == PlannerBand.band5 && sec != null && txComps.contains(sec)) {
    if (per20 >= CcaRule.secondarySignal.thresholdDbm) {
      return Deferral(
        overlaps: true,
        rule: CcaRule.secondarySignal,
        levelDbm: per20,
      );
    }
  }

  // Energy: sum what lands in each of the observer's 20 MHz pieces that the
  // transmission overlaps. In 5 GHz only co-channel pieces count; in 2.4 GHz
  // the mask spreads energy across neighbors.
  double best = double.negativeInfinity;
  for (final int oc in observer.group.components) {
    final double fo = centerMHz(band, oc).toDouble();
    if (fo + 10 <= transmitter.group.lowMHz ||
        fo - 10 >= transmitter.group.highMHz) {
      continue;
    }
    double linear = 0;
    for (final int tc in transmitter.group.components) {
      final double d = (centerMHz(band, tc) - fo).abs();
      if (band == PlannerBand.band5) {
        if (d == 0) linear += math.pow(10, per20 / 10);
      } else {
        linear += math.pow(10, (per20 + adjacentChannelDb(mask, d)) / 10);
      }
    }
    if (linear > 0) best = math.max(best, 10 * FsplMath.log10(linear));
  }
  if (best >= CcaRule.energyDetect.thresholdDbm) {
    return Deferral(overlaps: true, rule: CcaRule.energyDetect, levelDbm: best);
  }
  return Deferral(
    overlaps: true,
    rule: null,
    levelDbm: best.isFinite ? best : per20,
  );
}

// ── Geometry and propagation ──────────────────────────────────────────────

/// A wall segment on the floor, metres.
class Wall {
  const Wall(this.x1, this.y1, this.x2, this.y2);
  final double x1, y1, x2, y2;

  double get length => math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
}

/// A point on the floor, metres from the top-left corner.
class FloorPoint {
  const FloorPoint(this.x, this.y);
  final double x, y;

  double distanceTo(FloorPoint o) =>
      math.sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y));
}

double _cross(double ax, double ay, double bx, double by) => ax * by - ay * bx;

/// True when segment p-q crosses [w] (touching an end counts).
bool crossesWall(FloorPoint p, FloorPoint q, Wall w) {
  final double rx = q.x - p.x, ry = q.y - p.y;
  final double sx = w.x2 - w.x1, sy = w.y2 - w.y1;
  final double denom = _cross(rx, ry, sx, sy);
  if (denom == 0) return false; // parallel or collinear: slides along it
  final double t = _cross(w.x1 - p.x, w.y1 - p.y, sx, sy) / denom;
  final double u = _cross(w.x1 - p.x, w.y1 - p.y, rx, ry) / denom;
  return t >= 0 && t <= 1 && u >= 0 && u <= 1;
}

/// Propagation settings shared by every AP.
class PropagationSettings {
  const PropagationSettings({
    this.eirpDbm = 20,
    this.exponent = 3.0,
    this.wallLossDb = 10,
  });
  final double eirpDbm;
  final double exponent;
  final double wallLossDb;
}

/// Received power between two points: EIRP - (FSPL at 1 m + 10 n log10 d) -
/// walls x wall loss, with a 0 dBi receive antenna. Distances under 1 m are
/// treated as 1 m.
double receivedDbm({
  required PropagationSettings p,
  required PlannerBand band,
  required double distanceM,
  required int wallsCrossed,
}) =>
    p.eirpDbm -
    FsplMath.logDistanceDb(
      math.max(1, distanceM),
      band.pathLossFreqMHz,
      p.exponent,
    ) -
    wallsCrossed * p.wallLossDb;

// ── Whole-floor analysis ──────────────────────────────────────────────────

/// One AP on the floor. [channel] is null when no channel of its width
/// exists under the current rules.
class PlannerAp {
  const PlannerAp(this.position, this.channel);
  final FloorPoint position;
  final ChannelOption? channel;
}

/// The relationship between two APs.
class ApLink {
  const ApLink({
    required this.a,
    required this.b,
    required this.rxDbm,
    required this.walls,
    required this.aDefersToB,
    required this.bDefersToA,
  });

  final int a, b;

  /// Total received power between them (symmetric), dBm.
  final double rxDbm;
  final int walls;
  final Deferral aDefersToB;
  final Deferral bDefersToA;

  bool get mutual => aDefersToB.defers && bDefersToA.defers;
  bool get oneWay => aDefersToB.defers != bDefersToA.defers;
  bool get overlaps => aDefersToB.overlaps;

  /// The rules that fired, e.g. `PD` or `PD / SD` when the two sides differ.
  String get ruleShort {
    final Set<String> r = <String>{
      if (aDefersToB.rule != null) aDefersToB.rule!.short,
      if (bDefersToA.rule != null) bDefersToA.rule!.short,
    };
    return r.join(' / ');
  }
}

/// Everything the screen reads about a plan.
class PlanAnalysis {
  const PlanAnalysis({
    required this.links,
    required this.largestDomain,
    required this.domainSizeOf,
  });

  /// Every pair whose channels overlap, in index order.
  final List<ApLink> links;

  /// The largest set of APs that all defer to each other, ascending.
  final List<int> largestDomain;

  /// For each AP, the size of the largest domain it belongs to (1 alone).
  final List<int> domainSizeOf;

  List<ApLink> get contending =>
      links.where((ApLink l) => l.mutual).toList(growable: false);
  List<ApLink> get oneWay =>
      links.where((ApLink l) => l.oneWay).toList(growable: false);

  /// Share of airtime per AP in the largest domain, 1/N.
  double get largestShare => 1 / math.max(1, largestDomain.length);
}

PlanAnalysis analyzePlan({
  required List<PlannerAp> aps,
  required List<Wall> walls,
  required PropagationSettings propagation,
  required PlanRules rules,
}) {
  final int n = aps.length;
  final List<ApLink> links = <ApLink>[];
  final List<Set<int>> adj = <Set<int>>[for (int i = 0; i < n; i++) <int>{}];
  for (int i = 0; i < n; i++) {
    for (int j = i + 1; j < n; j++) {
      final ChannelOption? ci = aps[i].channel, cj = aps[j].channel;
      if (ci == null || cj == null || !ci.group.overlaps(cj.group)) continue;
      int wc = 0;
      for (final Wall w in walls) {
        if (crossesWall(aps[i].position, aps[j].position, w)) wc++;
      }
      final double rx = receivedDbm(
        p: propagation,
        band: rules.band,
        distanceM: aps[i].position.distanceTo(aps[j].position),
        wallsCrossed: wc,
      );
      final ApLink link = ApLink(
        a: i,
        b: j,
        rxDbm: rx,
        walls: wc,
        aDefersToB: evaluateDeferral(
          observer: ci,
          transmitter: cj,
          rxTotalDbm: rx,
          mask: rules.mask,
        ),
        bDefersToA: evaluateDeferral(
          observer: cj,
          transmitter: ci,
          rxTotalDbm: rx,
          mask: rules.mask,
        ),
      );
      links.add(link);
      if (link.mutual) {
        adj[i].add(j);
        adj[j].add(i);
      }
    }
  }
  final List<List<int>> cliques = maximalCliques(adj);
  List<int> largest = n == 0 ? const <int>[] : <int>[0];
  final List<int> sizeOf = List<int>.filled(n, 1);
  for (final List<int> c in cliques) {
    if (c.length > largest.length) largest = c;
    for (final int v in c) {
      sizeOf[v] = math.max(sizeOf[v], c.length);
    }
  }
  // Prefer a real shared domain over a lone AP only when one exists.
  if (largest.length == 1 && n > 0) {
    final int first = aps.indexWhere((PlannerAp a) => a.channel != null);
    largest = <int>[first < 0 ? 0 : first];
  }
  return PlanAnalysis(
    links: links,
    largestDomain: largest,
    domainSizeOf: sizeOf,
  );
}

/// Maximal cliques of an undirected graph (Bron-Kerbosch with pivot). Each
/// clique is ascending; cliques are ordered by size descending, then by
/// their members, so the result is deterministic.
List<List<int>> maximalCliques(List<Set<int>> adj) {
  final List<List<int>> out = <List<int>>[];
  void bk(Set<int> r, Set<int> p, Set<int> x) {
    if (p.isEmpty && x.isEmpty) {
      out.add(r.toList()..sort());
      return;
    }
    final int pivot = <int>{
      ...p,
      ...x,
    }.reduce((int a, int b) => adj[a].length >= adj[b].length ? a : b);
    for (final int v in p.difference(adj[pivot]).toList()..sort()) {
      bk(<int>{...r, v}, p.intersection(adj[v]), x.intersection(adj[v]));
      p.remove(v);
      x.add(v);
    }
  }

  bk(<int>{}, <int>{for (int i = 0; i < adj.length; i++) i}, <int>{});
  out.sort((List<int> a, List<int> b) {
    if (a.length != b.length) return b.length.compareTo(a.length);
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return 0;
  });
  return out;
}

// ── Auto-plan ─────────────────────────────────────────────────────────────

/// Greedy channel assignment at [width] that minimizes the largest
/// contention domain. APs that hear the most neighbors go first; each takes
/// the plan channel that keeps (largest domain, its own domain, its number
/// of contenders, the power it hears from them) lowest, lowest frequency on
/// a tie. Then up to three passes let each AP re-pick with every other AP
/// placed. A teaching heuristic, not a vendor RRM algorithm. Returns null
/// for every AP when no channel of [width] exists.
List<ChannelOption?> autoPlan({
  required List<FloorPoint> positions,
  required List<Wall> walls,
  required PropagationSettings propagation,
  required PlanRules rules,
  required int width,
}) {
  final int n = positions.length;
  final List<ChannelOption> candidates = <ChannelOption>[
    for (final ChannelGroup g in planChannels(rules, width))
      ChannelOption(g, g.components.first),
  ];
  final List<ChannelOption?> plan = List<ChannelOption?>.filled(n, null);
  if (candidates.isEmpty || n == 0) return plan;

  // How many neighbors each AP would hear on a shared 20 MHz channel.
  final List<int> heard = List<int>.filled(n, 0);
  for (int i = 0; i < n; i++) {
    for (int j = 0; j < n; j++) {
      if (i == j) continue;
      int wc = 0;
      for (final Wall w in walls) {
        if (crossesWall(positions[i], positions[j], w)) wc++;
      }
      final double rx = receivedDbm(
        p: propagation,
        band: rules.band,
        distanceM: positions[i].distanceTo(positions[j]),
        wallsCrossed: wc,
      );
      if (rx >= CcaRule.preambleDetect.thresholdDbm) heard[i]++;
    }
  }
  final List<int> order = <int>[for (int i = 0; i < n; i++) i]
    ..sort((int a, int b) {
      final int c = heard[b].compareTo(heard[a]);
      return c != 0 ? c : a.compareTo(b);
    });

  List<num> score(int ap, List<ChannelOption?> trial) {
    final List<int> idx = <int>[
      for (int i = 0; i < n; i++)
        if (trial[i] != null) i,
    ];
    final PlanAnalysis a = analyzePlan(
      aps: <PlannerAp>[
        for (final int i in idx) PlannerAp(positions[i], trial[i]),
      ],
      walls: walls,
      propagation: propagation,
      rules: rules,
    );
    final int local = idx.indexOf(ap);
    int contenders = 0;
    double power = 0;
    for (final ApLink l in a.contending) {
      if (l.a == local || l.b == local) {
        contenders++;
        power += math.pow(10, l.rxDbm / 10);
      }
    }
    return <num>[
      a.largestDomain.length,
      a.domainSizeOf[local],
      contenders,
      power,
    ];
  }

  int compare(List<num> x, List<num> y) {
    for (int i = 0; i < x.length; i++) {
      final int c = x[i].compareTo(y[i]);
      if (c != 0) return c;
    }
    return 0;
  }

  void place(int ap) {
    ChannelOption? best;
    List<num>? bestScore;
    for (final ChannelOption c in candidates) {
      final List<ChannelOption?> trial = List<ChannelOption?>.of(plan)
        ..[ap] = c;
      final List<num> s = score(ap, trial);
      if (bestScore == null || compare(s, bestScore) < 0) {
        best = c;
        bestScore = s;
      }
    }
    plan[ap] = best;
  }

  for (final int ap in order) {
    place(ap);
  }
  for (int pass = 0; pass < 3; pass++) {
    final List<ChannelOption?> before = List<ChannelOption?>.of(plan);
    for (final int ap in order) {
      place(ap);
    }
    bool same = true;
    for (int i = 0; i < n; i++) {
      if (before[i] != plan[i]) same = false;
    }
    if (same) break;
  }
  return plan;
}
