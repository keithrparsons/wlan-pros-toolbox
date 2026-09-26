// DFS and Radar model (Wi-Fi Classroom, 2026-09-25).
//
// Pure Dart. Built clean-room from the Wi-Fi Classroom wave 3 research brief §2
// (FCC 47 CFR §15.407(h)(2) and ETSI EN 301 893 V2.1.1 Table D.1, read from
// the primary text) per myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/
// specs/25-dfs.md. Channel numbers, bonding groups and band edges come from
// lib/data/channel_frequency_data.dart; nothing here re-derives them.
//
// THE RULES (brief §2):
//                              FCC                     ETSI
//   Channel availability check 60 s                    60 s; 600 s for any
//                                                      channel partly or fully
//                                                      in 5600-5650 MHz
//   Channel closing            200 ms of normal        1 s of transmissions in
//   transmission time          traffic, plus 60 ms     aggregate
//                              aggregate of control
//                              signals (SINGLE SOURCE:
//                              a 2018 test-lab
//                              transcription of KDB
//                              905462 D02)
//   Channel move time          10 s                    10 s
//   Non-occupancy period       30 min                  30 min
//   Detection threshold        -64 dBm at EIRP >=      -62 + 10 - PSD + G dBm,
//                              200 mW; -62 dBm below   floor -64 dBm (G = 0 dBi
//                              200 mW and 10 dBm/MHz   here)
//
// THE MODEL (a teaching model, and the screen says so):
//   One AP on a simulated clock of one hour. It starts on a chosen channel:
//   a DFS channel costs a CAC first, a non-DFS channel serves at once. Radar
//   comes from the "Radar now" button (manual times in the config) and from
//   an optional seeded Poisson rate. Radar is acted on only while the AP sits
//   on a DFS channel (listening in a CAC, or serving); on a non-DFS channel
//   the AP is not required to detect it, so it is ignored.
//
//   Radar while serving: the AP stops normal traffic within the closing time
//   (drawn at the limit), announces the switch, and leaves the channel
//   kApSwitchS after the radar (ILLUSTRATIVE, inside the 10 s move time).
//   Radar during a CAC: the AP never transmitted, so it leaves at once.
//   Either way every 20 MHz channel the AP occupied is blocked for 30 min
//   (a model choice: some APs block only the sub-channel that saw the radar).
//
//   The new channel follows the policy: prefer a non-DFS channel, or take
//   the next DFS channel up the band (wrapping) and pay its CAC. If no free
//   channel exists at the width, the AP narrows until one does.
//
//   Clients: if the AP lands on a non-DFS channel they follow its channel
//   switch announcement and are back when it is. If the AP must run a CAC
//   first, it is silent for a minute or more, so they drop and rejoin after
//   it returns, each after an ILLUSTRATIVE scan-and-join delay.
//
// Same config, same run: deterministic.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../data/channel_frequency_data.dart';

// ─── Regions and their rules ────────────────────────────────────────────────

enum DfsRegion {
  us('US (FCC)', 'US'),
  eu('EU (ETSI)', 'EU');

  const DfsRegion(this.label, this.short);

  final String label;
  final String short;

  DfsRules get rules => this == DfsRegion.us ? DfsRules.fcc : DfsRules.etsi;
}

/// The regulatory timings of one region (brief §2).
@immutable
class DfsRules {
  const DfsRules._({
    required this.cacS,
    required this.weatherCacS,
    required this.closingS,
    required this.controlSignalsS,
    required this.moveS,
    required this.nonOccupancyS,
  });

  /// FCC 47 CFR §15.407(h)(2) (primary) and KDB 905462 D02 (secondhand).
  static const DfsRules fcc = DfsRules._(
    cacS: 60,
    weatherCacS: 60,
    closingS: 0.2,
    controlSignalsS: 0.06,
    moveS: 10,
    nonOccupancyS: 30 * 60,
  );

  /// ETSI EN 301 893 V2.1.1 Table D.1 (primary).
  static const DfsRules etsi = DfsRules._(
    cacS: 60,
    weatherCacS: 600,
    closingS: 1.0,
    controlSignalsS: null,
    moveS: 10,
    nonOccupancyS: 30 * 60,
  );

  /// Channel availability check, seconds.
  final double cacS;

  /// CAC for a channel touching 5600-5650 MHz. Equal to [cacS] under the FCC:
  /// the 10-minute check is ETSI only.
  final double weatherCacS;

  /// Channel closing transmission time, seconds. FCC: normal traffic. ETSI:
  /// all transmissions in aggregate.
  final double closingS;

  /// FCC only: the aggregate of control signals allowed over the rest of the
  /// move time. Single secondhand source; the screen labels it so.
  final double? controlSignalsS;

  /// Channel move time, seconds.
  final double moveS;

  /// Non-occupancy period, seconds.
  final double nonOccupancyS;
}

/// The EU band that takes the 10-minute CAC (ETSI Table D.1 Note 1).
const int kWeatherLowMHz = 5600;
const int kWeatherHighMHz = 5650;

/// Length of one run, seconds.
const double kDfsHorizonS = 3600;

/// ILLUSTRATIVE: the AP leaves a channel this long after radar while
/// serving (the rule allows up to 10 s).
const double kApSwitchS = 1.0;

/// ILLUSTRATIVE: scan-and-join delay for each client after a silent AP
/// returns. Three clients.
const List<double> kClientRejoinS = <double>[1.0, 1.5, 2.5];

/// Channel widths offered, MHz.
const List<int> kDfsWidths = <int>[20, 40, 80, 160];

/// Radar rates offered, events per hour.
const List<double> kRadarRates = <double>[0, 2, 6, 12];

/// AP EIRP choices for the threshold readout, dBm.
const List<double> kDfsEirpChoices = <double>[17, 20, 23, 27, 30];

/// The 5 GHz 20 MHz channels a region's plan offers here. US: U-NII-1 to
/// U-NII-3 (36 to 165). U-NII-4 (169 to 177) is left out: its use is limited
/// and it has no DFS. EU: the two EN 301 893 ranges, 36 to 64 and 100 to 140;
/// 144 crosses the 5725 MHz edge and 149 to 165 are not in this plan.
List<int> regionChannels(DfsRegion region) {
  switch (region) {
    case DfsRegion.us:
      return <int>[
        for (final int c in k5Channels)
          if (c <= 165) c,
      ];
    case DfsRegion.eu:
      return <int>[
        for (final int c in k5Channels)
          if (c <= 64 || (c >= 100 && c <= 140)) c,
      ];
  }
}

/// True when [channel] is in the region's plan and needs radar detection.
bool isDfsChannel(DfsRegion region, int channel) =>
    k5Dfs.contains(channel) && regionChannels(region).contains(channel);

/// Every placement of a [widthMHz] channel whose 20 MHz components are all
/// in the region's plan, low to high.
List<BondedChannel> dfsPlacements(DfsRegion region, int widthMHz) {
  final Set<int> plan = regionChannels(region).toSet();
  final List<List<int>> groups = widthMHz == 20
      ? <List<int>>[
          for (final int c in plan) <int>[c],
        ]
      : bondingGroups(WifiBand.band5, widthMHz);
  final List<BondedChannel> out = <BondedChannel>[];
  for (final List<int> g in groups) {
    if (!g.every(plan.contains)) continue;
    final BondedChannel? b = bondedChannel(
      band: WifiBand.band5,
      primaryChannel: g.first,
      widthMHz: widthMHz,
    );
    if (b != null) out.add(b);
  }
  out.sort(
    (BondedChannel a, BondedChannel b) =>
        a.centerFreqMHz.compareTo(b.centerFreqMHz),
  );
  return out;
}

/// True when any 20 MHz component of [p] is a DFS channel.
bool placementIsDfs(DfsRegion region, BondedChannel p) =>
    p.components.any((int c) => isDfsChannel(region, c));

/// True when [p] lies partly or fully in 5600-5650 MHz. A channel that only
/// touches an edge (132 starts at 5650) is outside.
bool touchesWeatherBand(BondedChannel p) =>
    p.lowEdgeMHz < kWeatherHighMHz && p.highEdgeMHz > kWeatherLowMHz;

/// Seconds of channel availability check before [p] may be used; 0 for a
/// non-DFS channel.
double cacSecondsFor(DfsRegion region, BondedChannel p) {
  if (!placementIsDfs(region, p)) return 0;
  final DfsRules r = region.rules;
  return touchesWeatherBand(p) ? r.weatherCacS : r.cacS;
}

/// "100", or "100-112" for a wide channel.
String placementLabel(BondedChannel p) => p.components.length == 1
    ? '${p.components.first}'
    : '${p.components.first}-${p.components.last}';

/// Radar detection threshold, dBm, for an AP at [eirpDbm] over [widthMHz]
/// (brief §2). ETSI assumes a 0 dBi receive antenna (G = 0).
double detectionThresholdDbm(DfsRegion region, double eirpDbm, int widthMHz) {
  switch (region) {
    case DfsRegion.us:
      // -64 dBm at EIRP >= 200 mW (23 dBm); -62 dBm below 200 mW with PSD
      // under 10 dBm/MHz. A device below 200 mW with PSD at or above
      // 10 dBm/MHz cannot occur at 20 MHz or wider.
      return eirpDbm >= 23 - 1e-9 ? -64 : -62;
    case DfsRegion.eu:
      final double psd = eirpDbm - 10 * math.log(widthMHz) / math.ln10;
      return math.max(-64, -62 + 10 - psd);
  }
}

/// EIRP spectral density, dBm/MHz.
double eirpPsdDbmPerMHz(double eirpDbm, int widthMHz) =>
    eirpDbm - 10 * math.log(widthMHz) / math.ln10;

// ─── Config ─────────────────────────────────────────────────────────────────

enum NewChannelPolicy {
  preferNonDfs('Prefer non-DFS', 'Move to a non-DFS channel: no CAC'),
  anotherDfs('Another DFS', 'Move to the next DFS channel and pay its CAC');

  const NewChannelPolicy(this.label, this.description);

  final String label;
  final String description;
}

@immutable
class DfsConfig {
  const DfsConfig({
    this.region = DfsRegion.us,
    this.widthMHz = 20,
    this.startChannel = 100,
    this.policy = NewChannelPolicy.preferNonDfs,
    this.radarPerHour = 0,
    this.seed = 1,
    this.manualRadarS = const <double>[],
    this.eirpDbm = 23,
  });

  final DfsRegion region;
  final int widthMHz;

  /// A 20 MHz channel inside the starting placement.
  final int startChannel;
  final NewChannelPolicy policy;

  /// Mean random radar events per hour (Poisson), 0 for none.
  final double radarPerHour;
  final int seed;

  /// Radar the student triggered, run seconds.
  final List<double> manualRadarS;

  /// For the detection-threshold readout only.
  final double eirpDbm;

  DfsConfig copyWith({
    DfsRegion? region,
    int? widthMHz,
    int? startChannel,
    NewChannelPolicy? policy,
    double? radarPerHour,
    int? seed,
    List<double>? manualRadarS,
    double? eirpDbm,
  }) => DfsConfig(
    region: region ?? this.region,
    widthMHz: widthMHz ?? this.widthMHz,
    startChannel: startChannel ?? this.startChannel,
    policy: policy ?? this.policy,
    radarPerHour: radarPerHour ?? this.radarPerHour,
    seed: seed ?? this.seed,
    manualRadarS: manualRadarS ?? this.manualRadarS,
    eirpDbm: eirpDbm ?? this.eirpDbm,
  );

  /// The placement the AP starts on: the one at [widthMHz] that holds
  /// [startChannel], or the first DFS placement, or the first placement.
  BondedChannel get startPlacement {
    final List<BondedChannel> all = dfsPlacements(region, widthMHz);
    for (final BondedChannel p in all) {
      if (p.components.contains(startChannel)) return p;
    }
    for (final BondedChannel p in all) {
      if (placementIsDfs(region, p)) return p;
    }
    return all.first;
  }

  @override
  bool operator ==(Object other) =>
      other is DfsConfig &&
      other.region == region &&
      other.widthMHz == widthMHz &&
      other.startChannel == startChannel &&
      other.policy == policy &&
      other.radarPerHour == radarPerHour &&
      other.seed == seed &&
      listEquals(other.manualRadarS, manualRadarS) &&
      other.eirpDbm == eirpDbm;

  @override
  int get hashCode => Object.hash(
    region,
    widthMHz,
    startChannel,
    policy,
    radarPerHour,
    seed,
    Object.hashAll(manualRadarS),
    eirpDbm,
  );
}

// ─── Result ─────────────────────────────────────────────────────────────────

enum ApPhase {
  /// Listening for radar before first use of a DFS channel.
  cac,

  /// Serving clients.
  service,

  /// After radar while serving: closing traffic and leaving the channel.
  moving,
}

@immutable
class ApSegment {
  const ApSegment(this.phase, this.startS, this.endS, this.channel);

  final ApPhase phase;
  final double startS;
  final double endS;
  final BondedChannel channel;

  bool covers(double t) => t >= startS && t < endS;
}

enum RadarSource { manual, random }

@immutable
class RadarHit {
  const RadarHit({
    required this.timeS,
    required this.source,
    required this.channel,
    required this.duringCac,
    required this.stopTrafficS,
    required this.leaveS,
    required this.next,
    required this.nextCacS,
    required this.resumeS,
    required this.narrowedFromMHz,
    required this.noNonDfsAtWidth,
  });

  final double timeS;
  final RadarSource source;

  /// The channel the radar was detected on.
  final BondedChannel channel;

  /// Detected while the AP was still in its CAC (never transmitted).
  final bool duringCac;

  /// When normal traffic must have stopped (radar + closing time); equals
  /// [timeS] for a hit during a CAC.
  final double stopTrafficS;

  /// When the AP left the channel.
  final double leaveS;

  /// The channel it moved to.
  final BondedChannel next;

  /// CAC paid on [next], seconds (0 for a non-DFS channel).
  final double nextCacS;

  /// When service resumed, or null if not within the run.
  final double? resumeS;

  /// The width the AP had to give up, when no channel was free at it.
  final int? narrowedFromMHz;

  /// Policy was "prefer non-DFS" but no non-DFS channel exists at the width.
  final bool noNonDfsAtWidth;

  double get moveS => leaveS - timeS;

  /// Radar to resumed service, or null if not within the run.
  double? get outageS => resumeS == null ? null : resumeS! - timeS;

  /// Clients dropped (the AP went silent for a CAC) rather than following
  /// its channel switch announcement.
  bool get clientsDropped => nextCacS > 0;
}

@immutable
class ChannelBlock {
  const ChannelBlock(this.channels, this.fromS, this.untilS);

  final List<int> channels;
  final double fromS;
  final double untilS;

  bool activeAt(double t) => t >= fromS && t < untilS;
}

@immutable
class ClientSpan {
  const ClientSpan(this.startS, this.endS);

  final double startS;
  final double endS;
}

/// What a 20 MHz channel is doing at a moment.
enum ChannelUse { notInPlan, available, cac, inUse, leaving, blocked }

@immutable
class ChannelStatus {
  const ChannelStatus(this.use, {this.isDfs = false, this.untilS});

  final ChannelUse use;
  final bool isDfs;

  /// End of the CAC or of the non-occupancy period, when relevant.
  final double? untilS;
}

@immutable
class DfsRun {
  const DfsRun({
    required this.config,
    required this.start,
    required this.segments,
    required this.hits,
    required this.blocks,
    required this.clients,
    required this.firstTxS,
  });

  final DfsConfig config;
  final BondedChannel start;
  final List<ApSegment> segments;

  /// Radar the AP acted on, in time order.
  final List<RadarHit> hits;
  final List<ChannelBlock> blocks;

  /// Connected spans per client.
  final List<List<ClientSpan>> clients;

  /// First transmission, or null if the CAC outlasts the run.
  final double? firstTxS;

  DfsRegion get region => config.region;

  ApSegment segmentAt(double t) {
    for (final ApSegment s in segments) {
      if (s.covers(t)) return s;
    }
    return segments.last;
  }

  List<RadarHit> hitsUpTo(double t) => <RadarHit>[
    for (final RadarHit h in hits)
      if (h.timeS <= t) h,
  ];

  List<ChannelBlock> blocksAt(double t) => <ChannelBlock>[
    for (final ChannelBlock b in blocks)
      if (b.activeAt(t)) b,
  ];

  /// True when radar at [t] would be acted on.
  bool radarActionableAt(double t) {
    if (t < 0 || t >= kDfsHorizonS) return false;
    final ApSegment s = segmentAt(t);
    return s.phase != ApPhase.moving && placementIsDfs(region, s.channel);
  }

  ChannelStatus statusOf(int channel, double t) {
    if (!regionChannels(region).contains(channel)) {
      return const ChannelStatus(ChannelUse.notInPlan);
    }
    final bool dfs = isDfsChannel(region, channel);
    final ApSegment s = segmentAt(t);
    double? blockedUntil;
    for (final ChannelBlock b in blocks) {
      if (b.activeAt(t) && b.channels.contains(channel)) {
        blockedUntil = math.max(blockedUntil ?? 0, b.untilS);
      }
    }
    if (s.channel.components.contains(channel)) {
      switch (s.phase) {
        case ApPhase.cac:
          return ChannelStatus(ChannelUse.cac, isDfs: dfs, untilS: s.endS);
        case ApPhase.service:
          return ChannelStatus(ChannelUse.inUse, isDfs: dfs);
        case ApPhase.moving:
          return ChannelStatus(
            ChannelUse.leaving,
            isDfs: dfs,
            untilS: blockedUntil,
          );
      }
    }
    if (blockedUntil != null) {
      return ChannelStatus(
        ChannelUse.blocked,
        isDfs: dfs,
        untilS: blockedUntil,
      );
    }
    return ChannelStatus(ChannelUse.available, isDfs: dfs);
  }

  /// Is client [i] connected at [t]?
  bool clientConnectedAt(int i, double t) =>
      clients[i].any((ClientSpan s) => t >= s.startS && t < s.endS);
}

// ─── Simulation ─────────────────────────────────────────────────────────────

/// Radar times from a seeded Poisson process over the run.
List<double> randomRadarTimes(double perHour, int seed) {
  if (perHour <= 0) return const <double>[];
  final math.Random rng = math.Random(seed);
  final List<double> out = <double>[];
  double t = 0;
  while (true) {
    final double u = rng.nextDouble();
    t += -math.log(1 - u) * 3600 / perHour;
    if (t >= kDfsHorizonS) break;
    out.add(t);
  }
  return out;
}

typedef _Pick = ({BondedChannel ch, int? narrowedFrom, bool noNonDfs});

_Pick _chooseNext(
  DfsConfig cfg,
  BondedChannel from,
  double t,
  List<ChannelBlock> blocks,
) {
  bool blocked(BondedChannel p) => blocks.any(
    (ChannelBlock b) =>
        b.activeAt(t) && p.components.any((int c) => b.channels.contains(c)),
  );
  final DfsRegion region = cfg.region;
  final List<int> widths = <int>[
    for (final int w in kDfsWidths.reversed)
      if (w <= from.widthMHz) w,
  ];
  for (final int w in widths) {
    final List<BondedChannel> free = <BondedChannel>[
      for (final BondedChannel p in dfsPlacements(region, w))
        if (!blocked(p)) p,
    ];
    final List<BondedChannel> nonDfs = <BondedChannel>[
      for (final BondedChannel p in free)
        if (!placementIsDfs(region, p)) p,
    ];
    // DFS candidates: next one above the old channel, wrapping.
    final List<BondedChannel> dfsAll = <BondedChannel>[
      for (final BondedChannel p in free)
        if (placementIsDfs(region, p)) p,
    ];
    final List<BondedChannel> dfs = <BondedChannel>[
      ...dfsAll.where(
        (BondedChannel p) => p.centerFreqMHz > from.centerFreqMHz,
      ),
      ...dfsAll.where(
        (BondedChannel p) => p.centerFreqMHz <= from.centerFreqMHz,
      ),
    ];
    final int? narrowed = w == from.widthMHz ? null : from.widthMHz;
    if (cfg.policy == NewChannelPolicy.preferNonDfs) {
      if (nonDfs.isNotEmpty) {
        return (ch: nonDfs.first, narrowedFrom: narrowed, noNonDfs: false);
      }
      if (dfs.isNotEmpty) {
        return (ch: dfs.first, narrowedFrom: narrowed, noNonDfs: true);
      }
    } else {
      if (dfs.isNotEmpty) {
        return (ch: dfs.first, narrowedFrom: narrowed, noNonDfs: false);
      }
      if (nonDfs.isNotEmpty) {
        return (ch: nonDfs.first, narrowedFrom: narrowed, noNonDfs: false);
      }
    }
  }
  // Unreachable in both plans: 36 to 48 at 20 MHz are never DFS and never
  // blocked. Stay put rather than invent a channel.
  return (ch: from, narrowedFrom: null, noNonDfs: false);
}

/// Runs one hour of the AP's life under [cfg].
DfsRun simulateDfs(DfsConfig cfg) {
  final DfsRegion region = cfg.region;
  final DfsRules rules = region.rules;
  final List<({double t, RadarSource src})> radars =
      <({double t, RadarSource src})>[
        for (final double t in cfg.manualRadarS)
          if (t >= 0 && t < kDfsHorizonS) (t: t, src: RadarSource.manual),
        for (final double t in randomRadarTimes(cfg.radarPerHour, cfg.seed))
          (t: t, src: RadarSource.random),
      ]..sort(
        (({double t, RadarSource src}) a, ({double t, RadarSource src}) b) =>
            a.t.compareTo(b.t),
      );

  final BondedChannel start = cfg.startPlacement;
  final List<ApSegment> segs = <ApSegment>[];
  final List<ChannelBlock> blocks = <ChannelBlock>[];
  final List<
    ({
      double t,
      RadarSource src,
      BondedChannel ch,
      bool cac,
      double stop,
      double leave,
      _Pick pick,
    })
  >
  raw =
      <
        ({
          double t,
          RadarSource src,
          BondedChannel ch,
          bool cac,
          double stop,
          double leave,
          _Pick pick,
        })
      >[];

  int ri = 0;
  double t = 0;
  BondedChannel ch = start;
  double? firstTx;

  // Next radar at or after [from] (earlier ones fell in a move and are
  // ignored), or null.
  ({double t, RadarSource src})? nextRadar(double from) {
    while (ri < radars.length && radars[ri].t < from) {
      ri++;
    }
    return ri < radars.length ? radars[ri] : null;
  }

  void onRadar(({double t, RadarSource src}) r, {required bool duringCac}) {
    ri++;
    final double stop = duringCac ? r.t : r.t + rules.closingS;
    final double leave = duringCac
        ? r.t
        : r.t + math.max(rules.closingS, kApSwitchS);
    blocks.add(
      ChannelBlock(
        List<int>.unmodifiable(ch.components),
        r.t,
        r.t + rules.nonOccupancyS,
      ),
    );
    if (!duringCac) {
      segs.add(
        ApSegment(ApPhase.moving, r.t, math.min(leave, kDfsHorizonS), ch),
      );
    }
    final _Pick pick = _chooseNext(cfg, ch, leave, blocks);
    raw.add((
      t: r.t,
      src: r.src,
      ch: ch,
      cac: duringCac,
      stop: stop,
      leave: leave,
      pick: pick,
    ));
    ch = pick.ch;
    t = leave;
  }

  while (t < kDfsHorizonS) {
    final double cac = cacSecondsFor(region, ch);
    if (cac > 0) {
      final double end = math.min(t + cac, kDfsHorizonS);
      final ({double t, RadarSource src})? r = nextRadar(t);
      if (r != null && r.t < end) {
        segs.add(ApSegment(ApPhase.cac, t, r.t, ch));
        onRadar(r, duringCac: true);
        continue;
      }
      segs.add(ApSegment(ApPhase.cac, t, end, ch));
      t = end;
      if (t >= kDfsHorizonS) break;
    }
    firstTx ??= t;
    if (!placementIsDfs(region, ch)) {
      // No radar detection is required here; the AP serves to the end.
      segs.add(ApSegment(ApPhase.service, t, kDfsHorizonS, ch));
      break;
    }
    final ({double t, RadarSource src})? r = nextRadar(t);
    if (r == null) {
      segs.add(ApSegment(ApPhase.service, t, kDfsHorizonS, ch));
      break;
    }
    segs.add(ApSegment(ApPhase.service, t, r.t, ch));
    onRadar(r, duringCac: false);
  }

  // Drop zero-length segments (radar at the very instant a CAC began).
  final List<ApSegment> segments = <ApSegment>[
    for (final ApSegment s in segs)
      if (s.endS > s.startS) s,
  ];
  if (segments.isEmpty) {
    segments.add(ApSegment(ApPhase.cac, 0, kDfsHorizonS, start));
  }

  double? resumeAfter(double time) {
    for (final ApSegment s in segments) {
      if (s.phase == ApPhase.service && s.startS >= time) return s.startS;
    }
    return null;
  }

  final List<RadarHit> hits = <RadarHit>[
    for (final r in raw)
      RadarHit(
        timeS: r.t,
        source: r.src,
        channel: r.ch,
        duringCac: r.cac,
        stopTrafficS: r.stop,
        leaveS: r.leave,
        next: r.pick.ch,
        nextCacS: cacSecondsFor(region, r.pick.ch),
        resumeS: resumeAfter(r.t),
        narrowedFromMHz: r.pick.narrowedFrom,
        noNonDfsAtWidth: r.pick.noNonDfs,
      ),
  ];

  // Clients: follow a channel switch straight onto a non-DFS channel;
  // otherwise join fresh after the AP starts serving.
  final List<List<ClientSpan>> clients = <List<ClientSpan>>[];
  for (final double delay in kClientRejoinS) {
    final List<ClientSpan> spans = <ClientSpan>[];
    for (int i = 0; i < segments.length; i++) {
      final ApSegment s = segments[i];
      if (s.phase != ApPhase.service) continue;
      final bool followed = i > 0 && segments[i - 1].phase == ApPhase.moving;
      final double from = followed ? s.startS : s.startS + delay;
      if (from < s.endS) spans.add(ClientSpan(from, s.endS));
    }
    clients.add(List<ClientSpan>.unmodifiable(spans));
  }

  return DfsRun(
    config: cfg,
    start: start,
    segments: List<ApSegment>.unmodifiable(segments),
    hits: List<RadarHit>.unmodifiable(hits),
    blocks: List<ChannelBlock>.unmodifiable(blocks),
    clients: clients,
    firstTxS: firstTx,
  );
}

// ─── Formatting ─────────────────────────────────────────────────────────────

/// "12:05" (minutes:seconds of run time).
String fmtClock(double s) {
  final int whole = s.floor().clamp(0, 1 << 30);
  final int m = whole ~/ 60;
  final int sec = whole % 60;
  return '$m:${sec.toString().padLeft(2, '0')}';
}

/// "200 ms", "61.0 s", "10 min", "10 min 30 s".
String fmtSpan(double s) {
  if (s < 1) return '${(s * 1000).round()} ms';
  if (s < 120) return '${s.toStringAsFixed(1)} s';
  final int whole = s.round();
  final int m = whole ~/ 60;
  final int sec = whole % 60;
  return sec == 0 ? '$m min' : '$m min $sec s';
}

/// A rule value: "200 ms", "60 s", "10 min" (no decimals on whole seconds).
String fmtRule(double s) {
  if (s < 1) return '${(s * 1000).round()} ms';
  if (s < 120 && s == s.roundToDouble()) return '${s.round()} s';
  return fmtSpan(s);
}
