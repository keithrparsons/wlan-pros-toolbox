// Pins the teaching claims of The Number on the Box vs the Number in Your
// Hand (box-vs-hand), from the research brief's candidate 4:
//   - the class number is every radio added at its maximum (18,656 Mbps)
//   - one client uses one link with its own streams, so a 2x2 client's best
//     case is half the fastest radio's 4-stream figure
//   - the stream count sets the ceiling, not the kind of device
//   - distance takes the estimate lower again
// and that the numbers come from the app's existing math, not a new table.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_phy_rate_service.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/box_vs_hand_model.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/rate_vs_range_math.dart';

void main() {
  group('the number on the box', () {
    test('is the three datasheet radios added: 18,656 Mbps', () {
      expect(BoxVsHand.radios.map((BvhRadio r) => r.datasheetMbps), <double>[
        11520,
        5760,
        1376,
      ]);
      expect(BoxVsHand.boxMbps, 18656);
    });

    test('the class name rounds the sum up to BE19000', () {
      expect(BoxVsHand.className, 'BE19000');
    });

    test('the app PHY math reproduces each datasheet figure within 0.1%', () {
      for (final BvhRadio r in BoxVsHand.radios) {
        expect(
          (r.computedMbps - r.datasheetMbps).abs() / r.datasheetMbps,
          lessThan(0.001),
          reason: '${r.band.label}: ${r.computedMbps}',
        );
      }
    });

    test('every radio is 4 streams at its widest channel', () {
      expect(BoxVsHand.radios.map((BvhRadio r) => r.streams).toSet(), <int>{4});
      expect(BoxVsHand.radios.map((BvhRadio r) => r.widthMHz), <int>[
        320,
        160,
        40,
      ]);
      expect(BoxVsHand.radios.first.band, WifiBand.band6);
    });
  });

  group('the best case for one client', () {
    test('a 2x2 phone gets half the 6 GHz radio, about 31% of the box', () {
      final double phone = BoxVsHand.bestCaseMbps(BvhClient.phone2x2);
      expect(phone, closeTo(BoxVsHand.radios.first.computedMbps / 2, 1e-9));
      expect(phone, closeTo(5764.7, 0.1));
      expect(BvhFormat.pct(phone, BoxVsHand.boxMbps), '31%');
    });

    test('a 2x2 laptop reaches exactly the same ceiling as a 2x2 phone', () {
      expect(
        BoxVsHand.bestCaseMbps(BvhClient.laptop2x2),
        BoxVsHand.bestCaseMbps(BvhClient.phone2x2),
      );
    });

    test('even a 4-stream client is held to one link, below the box', () {
      final double ref = BoxVsHand.bestCaseMbps(BvhClient.reference4);
      expect(ref, closeTo(BoxVsHand.radios.first.computedMbps, 1e-9));
      expect(ref, lessThan(BoxVsHand.boxMbps));
      expect(BvhFormat.pct(ref, BoxVsHand.boxMbps), '62%');
    });

    test('the default client is the 2x2 phone', () {
      expect(BvhClient.values.first, BvhClient.phone2x2);
      expect(BvhClient.phone2x2.streams, 2);
    });

    test('no client label names a product', () {
      for (final BvhClient c in BvhClient.values) {
        expect(
          c.label,
          isNot(matches(RegExp('iPhone|Pixel|Galaxy|MacBook|TP-Link|Archer'))),
        );
      }
    });
  });

  group('at a stated distance and width', () {
    test('defaults: 5 m on a 320 MHz 6 GHz channel, MCS 7 for a 2x2 phone', () {
      final BvhReading r = BoxVsHand.reading(
        client: BvhClient.phone2x2,
        distanceM: BoxVsHand.defaultDistanceM,
        widthMHz: BoxVsHand.defaultWidthMHz,
      );
      expect(r.widthMHz, 320);
      expect(r.receivedDbm, closeTo(-49.2, 0.05));
      expect(r.mcs, 7);
      expect(r.phyMbps, closeTo(2882.4, 0.1));
      expect(r.estimateMbps, closeTo(2305.9, 0.1));
    });

    test('the level and MCS are Rate vs Range at its own defaults', () {
      for (final double d in <double>[1, 3, 10, 25, 60]) {
        final BvhReading r = BoxVsHand.reading(
          client: BvhClient.phone2x2,
          distanceM: d,
          widthMHz: 160,
        );
        final double rx = RateVsRangeMath.receivedDbm(
          eirpDbm: 20,
          clientGainDbi: 0,
          distanceM: d,
          freqMHz: 6135,
          exponent: 3,
        );
        expect(r.receivedDbm, rx);
        expect(r.mcs, RateVsRangeMath.mcsFor(rx, 160));
      }
    });

    test('the estimate is the PHY rate times the Throughput Calculator '
        '802.11be factor', () {
      expect(BoxVsHand.efficiency, WifiPhyRateService.eff[WifiStd.eht]);
      final BvhReading r = BoxVsHand.reading(
        client: BvhClient.laptop2x2,
        distanceM: 8,
        widthMHz: 80,
      );
      expect(r.estimateMbps, closeTo(r.phyMbps * 0.80, 1e-9));
    });

    test('the estimate never beats the best case and falls with distance', () {
      for (final BvhClient c in BvhClient.values) {
        for (final int w in BoxVsHand.widthsMHz) {
          double last = double.infinity;
          for (double d = 1; d <= 60; d += 0.5) {
            final BvhReading r = BoxVsHand.reading(
              client: c,
              distanceM: d,
              widthMHz: w,
            );
            expect(r.estimateMbps, lessThan(BoxVsHand.bestCaseMbps(c)));
            expect(r.estimateMbps, lessThanOrEqualTo(last));
            last = r.estimateMbps;
          }
        }
      }
    });

    test('out of range reads no MCS and zero, never a negative', () {
      final BvhReading r = BoxVsHand.reading(
        client: BvhClient.phone2x2,
        distanceM: 60,
        widthMHz: 320,
      );
      expect(r.mcs, isNull);
      expect(r.phyMbps, 0);
      expect(r.estimateMbps, 0);
    });

    test('distance is clamped to the slider range', () {
      expect(
        BoxVsHand.reading(
          client: BvhClient.phone2x2,
          distanceM: 0.1,
          widthMHz: 320,
        ).distanceM,
        BoxVsHand.minDistanceM,
      );
    });
  });

  test('grouped formatting', () {
    expect(BvhFormat.mbps(18656), '18,656 Mbps');
    expect(BvhFormat.mbps(5764.7), '5,765 Mbps');
    expect(BvhFormat.mbps(922), '922 Mbps');
  });
}
