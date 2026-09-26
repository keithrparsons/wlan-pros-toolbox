// Unit tests for the Wi-Fi Classroom Multicast at the Basic Rate model
// (multicast-basic-rate). The "Done means" list of myPKA Deliverables/
// 2026-09-25-wifi-lab-cleanroom/specs/30-multicast-basic-rate.md, one test
// per line, plus the arithmetic that pins the 802.11b path.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/airtime_anatomy.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/multicast_basic_rate_model.dart';

void main() {
  group('multicast airtime per packet', () {
    test('1 Mb/s takes more than 10x the airtime of 24 Mb/s, same packet', () {
      for (final int bytes in kMcPacketSizes) {
        final MulticastTiming slow = multicastTiming(
          BasicRate.r1,
          McBand.ghz24,
          bytes,
        );
        final MulticastTiming fast = multicastTiming(
          BasicRate.r24,
          McBand.ghz24,
          bytes,
        );
        expect(
          slow.totalTenths,
          greaterThan(10 * fast.totalTenths),
          reason: '$bytes bytes',
        );
      }
    });

    test('multicast frames carry no ACK time', () {
      for (final McBand band in McBand.values) {
        for (final BasicRate r in BasicRate.on(band)) {
          final MulticastTiming t = multicastTiming(r, band, 1316);
          expect(t.ackTenths, 0);
          expect(
            t.totalTenths,
            t.difsTenths + t.backoffTenths + t.preambleTenths + t.dataTenths,
            reason: '${band.label} ${r.label}',
          );
        }
      }
    });

    test('the 802.11b path: 192 us preamble, DIFS 50 us, backoff 310 us', () {
      final MulticastTiming t = multicastTiming(
        BasicRate.r1,
        McBand.ghz24,
        1316,
      );
      // MPDU = 1316 + 26 + 4 + 16 = 1362 bytes; 8 x 1362 / 1 = 10896 us.
      expect(t.mpduBytes, 1362);
      expect(t.preambleTenths, 1920);
      expect(t.dataTenths, 108960);
      expect(t.difsTenths, 500);
      expect(t.backoffTenths, 3100);
      expect(t.totalUs, 11448);
      // 5.5 Mb/s: ceil(8 x 1362 / 5.5) = ceil(1981.09) = 1982 us.
      expect(
        multicastTiming(BasicRate.r5_5, McBand.ghz24, 1316).dataTenths,
        19820,
      );
    });

    test('the 802.11a/g path reuses Airtime Anatomy exactly', () {
      final AirtimeResult r = computeAirtime(
        const AirtimeScenario(
          band: AirtimeBand.ghz5,
          phy: AirtimePhy.legacy,
          widthMhz: 20,
          legacyRateMbps: 6,
          streams: 1,
          guardInterval: GuardInterval.gi08,
          payloadBytes: 1316,
        ),
      );
      final MulticastTiming t = multicastTiming(
        BasicRate.r6,
        McBand.ghz5,
        1316,
      );
      expect(t.preambleTenths, r.preambleTenths);
      expect(t.dataTenths, r.dataTenths);
      // DIFS = SIFS 16 + 2 x 9; backoff = 15 / 2 x 9 = 67.5 us.
      expect(t.difsTenths, 340);
      expect(t.backoffTenths, 675);
    });

    test('802.11b rates are refused on 5 GHz', () {
      expect(
        () => multicastTiming(BasicRate.r1, McBand.ghz5, 1316),
        throwsArgumentError,
      );
      expect(BasicRate.on(McBand.ghz5), <BasicRate>[
        BasicRate.r6,
        BasicRate.r12,
        BasicRate.r24,
      ]);
      // Moving to 5 GHz snaps an 802.11b rate to 6 Mb/s.
      const McConfig c = McConfig(band: McBand.ghz24, basicRate: BasicRate.r2);
      expect(c.copyWith(band: McBand.ghz5).basicRate, BasicRate.r6);
    });
  });

  group('unicast conversion', () {
    test('airtime grows linearly with the listener count', () {
      for (final ListenerRates rates in <ListenerRates>[
        ListenerRates.near,
        ListenerRates.far,
      ]) {
        final int one = computeMulticast(
          McConfig(listeners: 1, rates: rates),
        ).unicastPerPacketTenths;
        for (int n = 1; n <= kMcMaxListeners; n++) {
          final McResult r = computeMulticast(
            McConfig(listeners: n, rates: rates),
          );
          expect(r.unicastPerPacketTenths, n * one, reason: '$rates n=$n');
        }
      }
    });

    test('with the spread, each listener adds its own copy and nobody '
        'else changes', () {
      for (int n = 2; n <= kMcMaxListeners; n++) {
        final McResult a = computeMulticast(McConfig(listeners: n - 1));
        final McResult b = computeMulticast(McConfig(listeners: n));
        expect(
          b.unicastPerPacketTenths - a.unicastPerPacketTenths,
          b.copies.last.totalTenths,
        );
        for (int k = 0; k < n - 1; k++) {
          expect(b.copies[k].mcs, a.copies[k].mcs);
        }
      }
    });

    test('every copy carries SIFS and an ACK', () {
      final McResult r = computeMulticast(const McConfig());
      for (final UnicastCopy c in r.copies) {
        expect(c.sifsTenths, greaterThan(0));
        expect(c.ackTenths, greaterThan(0));
        expect(c.result.usesBlockAck, isFalse);
        expect(c.result.check.isOk, isTrue);
      }
    });

    test('a break-even listener count exists for the default stream and is '
        'reported', () {
      final McResult r = computeMulticast(const McConfig());
      expect(r.breakEven, isNotNull);
      final int n = r.breakEven!;
      int sum(int k) =>
          computeMulticast(McConfig(listeners: k)).unicastPerPacketTenths;
      expect(sum(n), greaterThanOrEqualTo(r.multicast.totalTenths));
      if (n > 1) expect(sum(n - 1), lessThan(r.multicast.totalTenths));
      // The default numbers, pinned: 6 Mb/s multicast, five listeners.
      expect(r.multicast.totalUs, 1941.5);
      expect(n, 8);
    });

    test('at 1 Mb/s, unicast stays cheaper all the way to 30 listeners', () {
      final McResult r = computeMulticast(
        const McConfig(band: McBand.ghz24, basicRate: BasicRate.r1),
      );
      expect(r.breakEven, isNull);
      expect(r.multicastShare, greaterThan(1));
    });
  });

  group('airtime share', () {
    test('share = airtime per packet x packets per second / 1 s', () {
      final McResult r = computeMulticast(const McConfig());
      expect(r.packetsPerSecond, closeTo(4e6 / (8 * 1316), 1e-9));
      expect(
        r.multicastShare,
        closeTo(r.multicast.totalTenths * r.packetsPerSecond / 1e7, 1e-12),
      );
      expect(
        r.unicastShare,
        closeTo(r.unicastPerPacketTenths * r.packetsPerSecond / 1e7, 1e-12),
      );
    });
  });

  group('DTIM buffering', () {
    test('with power save on, multicast release times align to DTIM '
        'beacons', () {
      for (int d = kMcMinDtim; d <= kMcMaxDtim; d++) {
        for (final double mbps in <double>[0.064, 0.5, 4]) {
          final McResult r = computeMulticast(
            McConfig(dtimPeriod: d, powerSave: true, streamMbps: mbps),
          );
          final double dtimUs = d * kMcBeaconIntervalUs;
          expect(r.multicastBlocks, isNotEmpty);
          for (final McBlock b in r.multicastBlocks) {
            final double k = b.releaseUs / dtimUs;
            expect(
              k,
              closeTo(k.roundToDouble(), 1e-9),
              reason: 'DTIM $d, $mbps Mb/s: released at ${b.releaseUs}',
            );
            // And that instant is a DTIM beacon on the timeline, or at 1.024 s
            // and later, off the window.
            final bool onTimeline = r.beacons.any(
              (McBeacon x) => x.dtim && (x.atUs - b.releaseUs).abs() < 1e-6,
            );
            expect(onTimeline, isTrue);
          }
        }
      }
    });

    test('with power save off, multicast goes on arrival', () {
      final McResult r = computeMulticast(const McConfig());
      for (final McBlock b in r.multicastBlocks) {
        expect(b.holdUs, 0);
      }
      expect(r.maxDtimDelayUs, 0);
    });

    test('DTIM delay never exceeds DTIM period x 102.4 ms', () {
      for (int d = kMcMinDtim; d <= kMcMaxDtim; d++) {
        for (final double mbps in kMcStreamRatesMbps) {
          final McResult r = computeMulticast(
            McConfig(dtimPeriod: d, powerSave: true, streamMbps: mbps),
          );
          final double bound = d * 102.4 * 1000;
          expect(r.maxDtimDelayUs, lessThanOrEqualTo(bound));
          for (final McBlock b in r.multicastBlocks) {
            expect(b.holdUs, greaterThanOrEqualTo(0));
            expect(b.holdUs, lessThanOrEqualTo(bound));
          }
        }
      }
    });

    test('beacons every 102.4 ms, every Nth a DTIM', () {
      final McResult r = computeMulticast(const McConfig(dtimPeriod: 3));
      expect(r.beacons, hasLength(10));
      expect(r.beacons[1].atUs, 102400);
      expect(
        <bool>[for (final McBeacon b in r.beacons) b.dtim],
        <bool>[
          true,
          false,
          false,
          true,
          false,
          false,
          true,
          false,
          false,
          true,
        ],
      );
    });
  });

  group('determinism and timeline', () {
    test('same config, same result', () {
      const McConfig c = McConfig(powerSave: true, dtimPeriod: 4);
      final McResult a = computeMulticast(c);
      final McResult b = computeMulticast(c);
      expect(a.multicastBlocks.length, b.multicastBlocks.length);
      for (int i = 0; i < a.multicastBlocks.length; i++) {
        expect(a.multicastBlocks[i].startUs, b.multicastBlocks[i].startUs);
      }
      expect(a.breakEven, b.breakEven);
    });

    test('frames never overlap and stay inside the second', () {
      for (final McConfig c in const <McConfig>[
        McConfig(),
        McConfig(powerSave: true, dtimPeriod: 10),
        McConfig(band: McBand.ghz24, basicRate: BasicRate.r1),
        McConfig(streamMbps: 20, packetBytes: 200, listeners: 30),
      ]) {
        final McResult r = computeMulticast(c);
        for (final List<McBlock> lane in <List<McBlock>>[
          r.multicastBlocks,
          r.unicastBlocks,
        ]) {
          for (int i = 0; i < lane.length; i++) {
            expect(lane[i].startUs, lessThan(kMcWindowUs));
            expect(lane[i].startUs, greaterThanOrEqualTo(lane[i].releaseUs));
            if (i > 0) {
              expect(
                lane[i].startUs,
                greaterThanOrEqualTo(lane[i - 1].endUs - 1e-6),
              );
            }
          }
        }
      }
    });
  });
}
