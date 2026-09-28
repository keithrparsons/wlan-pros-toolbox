// The Number on the Box vs the Number in Your Hand: the pure model for the
// Wi-Fi Classroom tool (box-vs-hand).
//
// CLEAN-ROOM BUILD (2026-09-27) per myPKA
// Deliverables/2026-09-27-classroom-candidates/RESEARCH-BRIEF.md, candidate 4
// (section 3) and the section 5 anti-patterns. Pure Dart, no Flutter imports,
// pinned by test/services/wifi_lab/box_vs_hand_model_test.dart.
//
// THE LESSON. A router's speed class adds every radio at its maximum. One
// client uses one link with its own stream count. So the class number shrinks
// twice: first to the client's best case (one link, its streams, everything
// else at the top), then to an estimate at a stated distance and width.
//
// SOURCED NUMBERS (brief candidate 4, both marked two-source in the brief):
//   - the BE19000-class router's datasheet lists 11,520 Mbps (6 GHz) +
//     5,760 Mbps (5 GHz) + 1,376 Mbps (2.4 GHz). Their sum, 18,656 Mbps, is
//     the brief's own arithmetic. The class name rounds that sum up to the
//     next thousand. The UI never names the vendor; the help cites it.
//   - current phones publish 2x2 MIMO (brief candidate 4). Default client
//     is 2x2 (Keith's ruling, BUILDER-RULES.md: no box-number defaults).
//
// REUSED, NOT RE-DERIVED:
//   - PHY rates: WifiPhyRateService.phyRateMbps, the Throughput Calculator's
//     math (Nsd x bits per symbol x streams / symbol time), 802.11be, 0.8 us
//     guard interval. It reproduces the three datasheet figures to within
//     0.1 % (the datasheet rounds each to a round per-stream figure); the
//     test pins that.
//   - throughput estimate: WifiPhyRateService.eff (0.80 for 802.11be), the
//     Throughput Calculator's own real-to-PHY factor, which its header calls
//     a favorable estimate. Labeled so everywhere it shows.
//   - received level and MCS at a distance: RateVsRangeMath (log-distance
//     path loss at the FSPL Simulator's 6 GHz default channel, and the
//     802.11be minimum-sensitivity table), with Rate vs Range's own defaults:
//     20 dBm EIRP, 0 dBi client antenna, path-loss exponent 3, no margin.
//
// ILLUSTRATIVE CHOICES (said on screen and in help): the default distance
// (5 m) and that the client keeps all its streams at that distance. Both
// are favorable to the client, so the estimate is an upper limit.
//
// NOT MODELED: other clients sharing the airtime, interference, walls beyond
// the exponent, whether a given client supports 320 MHz or 4096-QAM (the
// best case assumes it does), and Multi-Link Operation across radios.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import '../../data/channel_frequency_data.dart';
import '../network/wifi_phy_rate_service.dart';
import 'rate_vs_range_math.dart';

/// Stable catalog tool id: backs the route, the help entry and the tests.
const String kBoxVsHandToolId = 'box-vs-hand';

/// One radio in the router, as the datasheet lists it.
class BvhRadio {
  const BvhRadio({
    required this.band,
    required this.widthMHz,
    required this.streams,
    required this.datasheetMbps,
  });

  final WifiBand band;

  /// The widest channel this radio's listed figure assumes.
  final int widthMHz;

  /// Spatial streams behind the listed figure.
  final int streams;

  /// The figure printed on the datasheet, Mbps.
  final double datasheetMbps;

  /// The same figure from the app's PHY math: 802.11be, MCS 13, 0.8 us GI.
  double get computedMbps =>
      BoxVsHand.phyMbps(widthMHz: widthMHz, streams: streams, mcs: 13)!;
}

/// Who holds the device. Never a product name.
enum BvhClient {
  phone2x2('A 2x2 phone', 'Phone', 2),
  laptop2x2('A 2x2 laptop', 'Laptop', 2),
  reference4('A 4-stream reference client', '4-stream', 4);

  const BvhClient(this.label, this.shortLabel, this.streams);

  /// Sentence form ("A 2x2 phone").
  final String label;

  /// Toggle form ("Phone"). The toggle's own label says phone and laptop
  /// are 2x2.
  final String shortLabel;

  /// Spatial streams the client has.
  final int streams;
}

/// The three steps the bar walks through.
enum BvhStep {
  box('On the box'),
  bestCase('Best case for this client'),
  atDistance('At a stated distance and width');

  const BvhStep(this.label);
  final String label;
}

/// The estimate at a distance.
class BvhReading {
  const BvhReading({
    required this.distanceM,
    required this.widthMHz,
    required this.receivedDbm,
    required this.mcs,
    required this.phyMbps,
    required this.estimateMbps,
  });

  final double distanceM;
  final int widthMHz;
  final double receivedDbm;

  /// Highest MCS the level supports at [widthMHz], or null below MCS 0.
  final int? mcs;

  /// PHY rate at [mcs], or 0 below MCS 0.
  final double phyMbps;

  /// [phyMbps] x the Throughput Calculator's 802.11be factor.
  final double estimateMbps;
}

abstract final class BoxVsHand {
  /// The router's three radios, fastest first. Datasheet figures (brief
  /// candidate 4).
  static const List<BvhRadio> radios = <BvhRadio>[
    BvhRadio(
      band: WifiBand.band6,
      widthMHz: 320,
      streams: 4,
      datasheetMbps: 11520,
    ),
    BvhRadio(
      band: WifiBand.band5,
      widthMHz: 160,
      streams: 4,
      datasheetMbps: 5760,
    ),
    BvhRadio(
      band: WifiBand.band24,
      widthMHz: 40,
      streams: 4,
      datasheetMbps: 1376,
    ),
  ];

  /// The class number's source: every radio added, 18,656 Mbps.
  static double get boxMbps =>
      radios.fold<double>(0, (double s, BvhRadio r) => s + r.datasheetMbps);

  /// The class name: the sum rounded up to the next thousand ("BE19000").
  static String get className =>
      'BE${((boxMbps / 1000).ceil() * 1000).toString()}';

  /// The link a best case uses: the fastest radio.
  static BvhRadio get bestRadio => radios.first;

  /// Guard interval for every rate here, us (the Throughput Calculator key).
  static const String giKey = '0.8';

  /// Top MCS for 802.11be.
  static int get topMcs => WifiPhyRateService.maxMcs[WifiStd.eht]!;

  /// The Throughput Calculator's real-to-PHY factor for 802.11be.
  static double get efficiency => WifiPhyRateService.eff[WifiStd.eht]!;

  /// 802.11be PHY rate, Mbps, from the Throughput Calculator's math.
  static double? phyMbps({
    required int widthMHz,
    required int streams,
    required int mcs,
  }) => WifiPhyRateService.phyRateMbps(
    std: WifiStd.eht,
    bandwidthMHz: widthMHz,
    mcs: mcs,
    streams: streams,
    giKey: giKey,
  );

  /// The client's best case: one link (the fastest radio), the client's own
  /// streams (never more than the router's), top MCS, widest channel.
  static double bestCaseMbps(BvhClient c) => phyMbps(
    widthMHz: bestRadio.widthMHz,
    streams: math.min(c.streams, bestRadio.streams),
    mcs: topMcs,
  )!;

  // ── The distance step ─────────────────────────────────────────────────

  /// Widths the distance step offers (6 GHz, narrow to wide).
  static const List<int> widthsMHz = <int>[20, 40, 80, 160, 320];

  /// Rate vs Range's defaults, reused.
  static const double eirpDbm = 20;
  static const double clientGainDbi = 0;
  static const double exponent = 3;

  /// Illustrative default distance, m.
  static const double defaultDistanceM = 5;
  static const double minDistanceM = 1;
  static const double maxDistanceM = 60;

  /// Default width for the distance step: the best case's own width, so
  /// only distance changes between the second and third bars.
  static const int defaultWidthMHz = 320;

  /// The 6 GHz channel path loss is computed at (FSPL Simulator default).
  static const int channel = 37;

  static double get freqMHz =>
      channelToFrequency(WifiBand.band6, channel)!.toDouble();

  /// The estimate for [client] at [distanceM] on a [widthMHz] 6 GHz channel.
  static BvhReading reading({
    required BvhClient client,
    required double distanceM,
    required int widthMHz,
  }) {
    final double d = distanceM.clamp(minDistanceM, maxDistanceM);
    final double rx = RateVsRangeMath.receivedDbm(
      eirpDbm: eirpDbm,
      clientGainDbi: clientGainDbi,
      distanceM: d,
      freqMHz: freqMHz,
      exponent: exponent,
    );
    final int? mcs = RateVsRangeMath.mcsFor(rx, widthMHz);
    final int streams = math.min(client.streams, bestRadio.streams);
    final double phy = mcs == null
        ? 0
        : phyMbps(widthMHz: widthMHz, streams: streams, mcs: mcs)!;
    return BvhReading(
      distanceM: d,
      widthMHz: widthMHz,
      receivedDbm: rx,
      mcs: mcs,
      phyMbps: phy,
      estimateMbps: phy * efficiency,
    );
  }
}

/// Number formatting shared by stage, controls and copy text.
abstract final class BvhFormat {
  /// "18,656 Mbps" style, whole numbers with thousands separators.
  static String mbps(double v) => '${grouped(v.round())} Mbps';

  static String grouped(int v) {
    final String s = v.abs().toString();
    final StringBuffer b = StringBuffer(v < 0 ? '-' : '');
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  /// Share of the box number, whole percent ("31%").
  static String pct(double part, double whole) =>
      '${(100 * part / whole).round()}%';

  static String dbm(double v) => '${v.toStringAsFixed(1)} dBm';
}
