// Unit tests for The Slowest Link Wins (research brief candidate 15): the
// end-to-end rate is the smallest hop, whichever hop that is; each choice of
// the control makes that hop the slowest; the Ethernet goodput is the TCP
// payload share of a full-size frame; the Wi-Fi rate is Airtime Anatomy's
// via the Repeaters and Mesh Backhaul model; and a faster Wi-Fi link helps
// only when Wi-Fi is the slowest hop.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/repeater_mesh_model.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/slowest_link_model.dart';

void main() {
  test('end to end is the smallest hop, for every choice', () {
    for (final SlSlowest s in SlSlowest.values) {
      final SlChain c = SlChain(s);
      final double min = c.hops
          .map((SlHop h) => h.mbps)
          .reduce((double a, double b) => a < b ? a : b);
      expect(c.endToEndMbps, min, reason: '$s');
      expect(c.hops[c.bottleneck].mbps, min, reason: '$s');
    }
  });

  test('each choice makes that hop the slowest', () {
    expect(
      SlChain(SlSlowest.wifi).hops[SlChain(SlSlowest.wifi).bottleneck].kind,
      SlHopKind.wifi,
    );
    final SlChain port = SlChain(SlSlowest.switchPort);
    expect(port.hops[port.bottleneck].kind, SlHopKind.switchPort);
    final SlChain isp = SlChain(SlSlowest.isp);
    expect(isp.hops[isp.bottleneck].kind, SlHopKind.isp);
  });

  test('Ethernet carries 1448 of every 1538 bytes: 94.1 and 941.5 Mb/s', () {
    expect(slMbps(slEthernetGoodputMbps(100)), '94.1 Mb/s');
    expect(slMbps(slEthernetGoodputMbps(1000)), '941.5 Mb/s');
  });

  test('the Wi-Fi rate reuses the repeater model at 5 GHz, 2 streams, 0.6', () {
    for (final int mcs in <int>[kSlMcsFar, kSlMcsNear, kSlMcsBest]) {
      expect(
        slWifiMbps(mcs),
        rmPhyRateMbps(RmBand.ghz5, mcs) * kRmDefaultEfficiency,
      );
    }
    // 802.11ax, 80 MHz, 2 streams, 0.8 us GI: MCS 11 is 1201 Mb/s PHY.
    expect(slWifiMbps(kSlMcsBest), closeTo(1201 * 0.6, 0.5));
  });

  test('the worked numbers: 86.5, 94.1 and 300 Mb/s end to end', () {
    expect(slMbps(SlChain(SlSlowest.wifi).endToEndMbps), '86.5 Mb/s');
    expect(slMbps(SlChain(SlSlowest.switchPort).endToEndMbps), '94.1 Mb/s');
    expect(slMbps(SlChain(SlSlowest.isp).endToEndMbps), '300.0 Mb/s');
  });

  test('a faster Wi-Fi link helps only when Wi-Fi is the slowest hop, and '
      'then only up to the next-slowest', () {
    for (final SlSlowest s in <SlSlowest>[
      SlSlowest.switchPort,
      SlSlowest.isp,
    ]) {
      final SlChain c = SlChain(s);
      expect(c.withBestWifi.endToEndMbps, c.endToEndMbps, reason: '$s');
    }
    final SlChain w = SlChain(SlSlowest.wifi);
    expect(w.withBestWifi.endToEndMbps, greaterThan(w.endToEndMbps));
    expect(w.withBestWifi.endToEndMbps, kSlIspPlanMbps);
    expect(w.withBestWifi.hops[w.withBestWifi.bottleneck].kind, SlHopKind.isp);
  });
}
