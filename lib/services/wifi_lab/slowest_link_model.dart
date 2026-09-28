// The Slowest Link Wins: the pure model behind the interactive control on
// two field plates, How Your Devices Access the Internet and Throughput
// Testing: Where You Test.
//
// CLEAN-ROOM BUILD (2026-09-27) from myPKA Deliverables/2026-09-27-
// classroom-candidates/RESEARCH-BRIEF.md section 3, candidate 15: an
// upgrade to the existing plates, not a new entry. CWNA-109 objective 6.6.1
// names the three causes this control walks through: "LAN port speed/duplex
// misconfigurations, insufficient PoE budget, and insufficient Internet or
// WAN bandwidth" (plus the Wi-Fi link itself).
//
// THE LESSON. Traffic crosses every hop in turn, so the end-to-end rate is
// the SMALLEST hop rate, never more. A faster Wi-Fi router helps only when
// Wi-Fi is the slowest hop, and then only up to the next-slowest.
//
// THE HOPS, device to internet:
//   1. The Wi-Fi link, device to AP. Reused, not re-derived: the PHY rate is
//      Airtime Anatomy's 802.11ax figure (via rmPhyRateMbps from the
//      Repeaters and Mesh Backhaul model) at 5 GHz, 80 MHz, 2 spatial
//      streams (a 2x2 client, the Classroom default), 0.8 us guard interval.
//      Near the AP: MCS 9. Far from it: MCS 1. The best it gets: MCS 11.
//      It carries PHY x 0.6, Repeaters and Mesh Backhaul's default
//      efficiency (illustrative).
//   2. The switch port, AP to switch. 1 Gbps or 100 Mbps Ethernet line rate.
//      It carries the TCP payload share of a full-size frame: 1448 bytes of
//      payload (1500 MTU - 20 IP - 20 TCP - 12 TCP timestamps) per 1538
//      bytes on the wire (1500 + 14 header + 4 FCS + 8 preamble + 12
//      interframe gap), so 94.1 and 941.5 Mb/s. Arithmetic, not a choice.
//   3. The ISP plan, router to internet: 300 Mb/s (illustrative).
//
// THE ONE CONTROL: which hop is slowest. Each choice changes one thing from
// the same house: Wi-Fi link (the device far from the AP), Switch port (a
// 100 Mbps port), ISP plan (everything else fast).
//
// Pure Dart, no Flutter imports, deterministic. Pinned by test/services/
// wifi_lab/slowest_link_model_test.dart.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'repeater_mesh_model.dart'
    show RmBand, kRmDefaultEfficiency, rmPhyRateMbps;

/// MCS of the Wi-Fi link near the AP, far from it, and at its best.
const int kSlMcsNear = 9;
const int kSlMcsFar = 1;
const int kSlMcsBest = 11;

/// Ethernet: TCP payload bytes per full-size frame, and bytes on the wire.
const int kSlTcpPayloadBytes = 1448;
const int kSlWireBytes = 1538;

/// The ISP plan's speed, Mb/s (illustrative).
const double kSlIspPlanMbps = 300;

/// What one Ethernet port at [lineRateMbps] carries as TCP payload.
double slEthernetGoodputMbps(double lineRateMbps) =>
    lineRateMbps * kSlTcpPayloadBytes / kSlWireBytes;

/// What the Wi-Fi link carries at [mcs]: the PHY rate x the efficiency.
double slWifiMbps(int mcs) =>
    rmPhyRateMbps(RmBand.ghz5, mcs) * kRmDefaultEfficiency;

/// The three hops, in order from the device.
enum SlHopKind {
  wifi('Wi-Fi link', 'Wi-Fi link', 'device to AP'),
  switchPort('Switch port', 'switch port', 'AP to switch'),
  isp('ISP plan', 'ISP plan', 'router to the internet');

  const SlHopKind(this.label, this.inSentence, this.span);

  final String label;

  /// The name inside a sentence ("the switch port").
  final String inSentence;

  final String span;
}

/// The one control: which hop is the slowest.
enum SlSlowest {
  wifi('Wi-Fi'),
  switchPort('Switch'),
  isp('ISP plan');

  const SlSlowest(this.label);

  /// The toggle's label, short enough for three segments in a 360 px panel.
  final String label;
}

/// One hop with what it carries.
class SlHop {
  const SlHop({required this.kind, required this.detail, required this.mbps});

  final SlHopKind kind;

  /// What sets this hop's rate, in words.
  final String detail;

  /// What the hop carries, Mb/s.
  final double mbps;
}

/// The chain for one setting of the control.
class SlChain {
  SlChain._(this.slowest, this.hops);

  factory SlChain(SlSlowest slowest, {int? wifiMcs}) {
    final int mcs =
        wifiMcs ?? (slowest == SlSlowest.wifi ? kSlMcsFar : kSlMcsNear);
    final bool slowPort = slowest == SlSlowest.switchPort;
    final double port = slowPort ? 100 : 1000;
    return SlChain._(slowest, <SlHop>[
      SlHop(
        kind: SlHopKind.wifi,
        detail:
            '5 GHz, 80 MHz, 2x2, MCS $mcs'
            '${mcs == kSlMcsFar
                ? ', far from the AP'
                : mcs == kSlMcsNear
                ? ', near the AP'
                : ''}',
        mbps: slWifiMbps(mcs),
      ),
      SlHop(
        kind: SlHopKind.switchPort,
        detail: slowPort ? '100 Mbps Ethernet' : '1 Gbps Ethernet',
        mbps: slEthernetGoodputMbps(port),
      ),
      const SlHop(
        kind: SlHopKind.isp,
        detail: '300 Mb/s plan',
        mbps: kSlIspPlanMbps,
      ),
    ]);
  }

  final SlSlowest slowest;
  final List<SlHop> hops;

  /// End to end: the smallest hop.
  double get endToEndMbps => hops.map((SlHop h) => h.mbps).reduce(math.min);

  /// Index of the slowest hop.
  int get bottleneck {
    int best = 0;
    for (int i = 1; i < hops.length; i++) {
      if (hops[i].mbps < hops[best].mbps) best = i;
    }
    return best;
  }

  /// The same house with the Wi-Fi link at its best here (MCS 11): what a
  /// faster Wi-Fi router could at most change.
  SlChain get withBestWifi => SlChain(slowest, wifiMcs: kSlMcsBest);
}

/// "94.1 Mb/s".
String slMbps(double v) => '${v.toStringAsFixed(1)} Mb/s';
