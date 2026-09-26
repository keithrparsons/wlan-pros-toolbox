// Tests for the Channel Utilization Meter model (spec 37, "Done means").
//
// The spec's worked case is the acceptance test: one sender at 54 Mb/s with
// 1500-byte frames, a 393.5 us cycle, 73% busy by physical carrier sense,
// 76% counting the reservation, 56% payload. The byte is
// floor(255 x busy / (window x beacon period x 1024)).

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/airtime_anatomy.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/channel_utilization_model.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/medium_access_engine.dart';

int _byteOfInterval(CuTotals t, {required bool reserved}) =>
    channelUtilizationByte(
      busyTenths: t.busyTenths(countReserved: reserved),
      windowIntervals: 1,
    );

void main() {
  group('timing is Airtime Anatomy\'s', () {
    final CuTiming t = CuTiming(54, 1500);

    test('the data frame is 57 symbols = 254 us with preamble and signal '
        'extension', () {
      final AirtimeResult a = computeAirtime(cuScenario(54, 1500));
      expect(t.dataTenths, a.ppduTenths);
      expect(a.dataSymbols, 57);
      expect(t.dataTenths, 2540);
      expect(t.preambleTenths, 200);
    });

    test('slot 9, SIFS 10, DIFS 28, mean backoff 67.5, ACK 34 at 24 Mb/s', () {
      expect(t.slotTenths, 90);
      expect(t.sifsTenths, 100);
      expect(t.difsTenths, 280);
      expect(t.meanBackoffTenths, 675);
      expect(t.ackTenths, 340);
      expect(cuControlRateFor(54), 24);
      expect(cuControlRateFor(9), 6);
      expect(cuControlRateFor(18), 12);
    });

    test(
      'contention parameters are the Medium Access engine\'s legacy DCF',
      () {
        expect(t.params, kLegacyDcfParams);
        expect(t.params.cwMin, 15);
        expect(t.params.cwMax, 1023);
      },
    );
  });

  group('the worked single-sender case (spec 37)', () {
    final CuCycle c = CuCycle(CuTiming(54, 1500));

    test('the cycle is 393.5 us (+/- 0.5)', () {
      expect(c.cycleUs, closeTo(393.5, 0.5));
      expect(c.cycleTenths, 3935);
    });

    test('physical carrier sense only: 73% (+/- 1), 73.2% to one decimal', () {
      expect(c.physicalBusyTenths, 2880);
      expect(c.physicalShare, closeTo(0.73, 0.01));
      expect((c.physicalShare * 1000).round() / 10, 73.2);
    });

    test('physical or virtual: 76% (+/- 1), 75.7% to one decimal', () {
      expect(c.virtualBusyTenths, 2980);
      expect(c.virtualShare, closeTo(0.76, 0.01));
      expect((c.virtualShare * 1000).round() / 10, 75.7);
    });

    test('payload share is 56% (+/- 1): 222.2 us of 393.5', () {
      expect(c.timing.payloadUs, closeTo(222.22, 0.01));
      expect(c.payloadShare, closeTo(0.56, 0.01));
      // 222.22 / 393.5 = 0.56473, which rounds to 56.5% (truncates to 56.4).
      expect((c.payloadShare * 1000).round() / 10, 56.5);
    });

    test('the rest is waiting the protocol requires, not spare', () {
      expect(
        c.physicalShare +
            c.requiredIdleShare +
            (c.timing.sifsTenths / c.cycleTenths),
        closeTo(1, 1e-12),
      );
    });
  });

  group('the formula', () {
    test('a hand-computed case: 3,747,840 us busy over 50 x 100 TU', () {
      // 255 x 3,747,840 / (50 x 100 x 1024) = 255 x 3,747,840 / 5,120,000
      // = 186.66..., so the byte is 186.
      expect(
        channelUtilizationByte(busyTenths: 37478400, windowIntervals: 50),
        186,
      );
    });

    test('a whole interval busy is 255; none is 0', () {
      expect(
        channelUtilizationByte(
          busyTenths: kCuIntervalTenths,
          windowIntervals: 1,
        ),
        255,
      );
      expect(channelUtilizationByte(busyTenths: 0, windowIntervals: 1), 0);
    });

    test('the byte never exceeds 255, whatever it is given', () {
      for (final int busy in <int>[
        kCuIntervalTenths + 1,
        kCuIntervalTenths * 10,
        1 << 40,
      ]) {
        expect(
          channelUtilizationByte(busyTenths: busy, windowIntervals: 1),
          lessThanOrEqualTo(255),
        );
      }
    });

    test('the byte is the floor: one step is 1/255', () {
      // 1/255 of an interval, less one tenth of a microsecond, is still 0.
      final int step = kCuIntervalTenths ~/ 255;
      expect(
        channelUtilizationByte(busyTenths: step - 1, windowIntervals: 1),
        0,
      );
      expect(
        channelUtilizationByte(busyTenths: step + 1, windowIntervals: 1),
        1,
      );
    });
  });

  group('the run', () {
    test('is deterministic with a seed', () {
      final CuSim a = CuSim(const CuConfig(senders: 5), seed: 7)
        ..runIntervals(5);
      final CuSim b = CuSim(const CuConfig(senders: 5), seed: 7)
        ..runIntervals(5);
      final CuSim c = CuSim(const CuConfig(senders: 5), seed: 8)
        ..runIntervals(5);
      List<int> busy(CuSim s) => <int>[
        for (final CuTotals t in s.intervals) t.busyTenths(countReserved: true),
      ];
      expect(busy(a), busy(b));
      expect(busy(a), isNot(busy(c)));
    });

    test('every interval accounts for exactly 102.4 ms', () {
      final CuSim s = CuSim(
        const CuConfig(
          senders: 8,
          loadPercent: 30,
          neighbor: true,
          nonWifi: true,
        ),
      )..runIntervals(20);
      expect(s.intervals, hasLength(20));
      for (final CuTotals t in s.intervals) {
        expect(t.totalTenths, kCuIntervalTenths);
      }
    });

    test('one saturated sender reads 73% (physical) and 76% (virtual) over a '
        'window, and the meter never reaches 100%', () {
      final CuSim s = CuSim(const CuConfig())..runIntervals(100);
      final CuReading phys = s.reading(window: 50, countReserved: false)!;
      final CuReading virt = s.reading(window: 50, countReserved: true)!;
      expect(phys.exactShare, closeTo(0.732, 0.01));
      expect(virt.exactShare, closeTo(0.757, 0.01));
      expect(phys.byte, lessThan(255));
      expect(virt.byte, lessThan(255));
      // No single interval reaches 100% either, even counting reservations.
      for (final CuTotals t in s.intervals) {
        expect(_byteOfInterval(t, reserved: true), lessThan(255));
      }
      // Nothing is truly spare: the idle time is all required waiting.
      expect(phys.totals[CuSpan.spare], 0);
      expect(phys.totals.share(CuSpan.payload), closeTo(0.565, 0.01));
    });

    test('the reading uses the spec formula on the recorded busy time', () {
      final CuSim s = CuSim(const CuConfig(senders: 3))..runIntervals(12);
      final CuReading r = s.reading(window: 10, countReserved: false)!;
      int busy = 0;
      for (final CuTotals t in s.intervals.sublist(2)) {
        busy += t.busyTenths(countReserved: false);
      }
      expect(r.busyTenths, busy);
      expect(r.byte, (255 * busy) ~/ (10 * 100 * 1024 * 10));
    });

    test('the byte never exceeds 255 with everything on the channel', () {
      final CuSim s = CuSim(
        const CuConfig(
          senders: kCuMaxSenders,
          neighbor: true,
          neighborPercent: kCuMaxNeighborPercent,
          nonWifi: true,
        ),
      )..runIntervals(10);
      s.injectBurst();
      s.runIntervals(15);
      for (final CuTotals t in s.intervals) {
        expect(_byteOfInterval(t, reserved: true), lessThanOrEqualTo(255));
      }
      for (int w = 1; w <= 25; w++) {
        expect(
          s.reading(window: w, countReserved: true)!.byte,
          lessThanOrEqualTo(255),
        );
      }
    });

    test(
      'a neighbor raises utilization and leaves the station count alone',
      () {
        const CuConfig alone = CuConfig(senders: 2, loadPercent: 30);
        final CuConfig withNeighbor = alone.copyWith(neighbor: true);
        final CuSim a = CuSim(alone)..runIntervals(50);
        final CuSim b = CuSim(withNeighbor)..runIntervals(50);
        final CuReading ra = a.reading(window: 50, countReserved: false)!;
        final CuReading rb = b.reading(window: 50, countReserved: false)!;
        expect(rb.byte, greaterThan(ra.byte));
        expect(rb.totals.share(CuSpan.neighbor), greaterThan(0.1));
        expect(withNeighbor.stationCount, alone.stationCount);

        // Even beside a saturated sender.
        final CuSim c = CuSim(const CuConfig())..runIntervals(50);
        final CuSim d = CuSim(const CuConfig(neighbor: true))..runIntervals(50);
        expect(
          d.reading(window: 50, countReserved: false)!.byte,
          greaterThan(c.reading(window: 50, countReserved: false)!.byte),
        );
      },
    );

    test('idle associated stations raise the count, not the meter', () {
      final CuSim a = CuSim(const CuConfig())..runIntervals(10);
      final CuSim b = CuSim(const CuConfig(idleStations: 40))..runIntervals(10);
      expect(const CuConfig(idleStations: 40).stationCount, 41);
      expect(
        b.reading(window: 10, countReserved: false)!.byte,
        a.reading(window: 10, countReserved: false)!.byte,
      );
    });

    test('a single 1-second burst in a 5.12 s window moves the reading by at '
        'most about 20%', () {
      for (final CuConfig cfg in const <CuConfig>[
        CuConfig(),
        CuConfig(loadPercent: 5),
      ]) {
        final CuSim s = CuSim(cfg)..runIntervals(kCuDefaultWindow);
        final int before = s
            .reading(window: kCuDefaultWindow, countReserved: false)!
            .byte;
        s.injectBurst();
        int highest = before;
        for (int i = 0; i < kCuDefaultWindow + 5; i++) {
          s.runIntervals(1);
          final int b = s
              .reading(window: kCuDefaultWindow, countReserved: false)!
              .byte;
          if (b > highest) highest = b;
        }
        // 1 s of 5.12 s is 19.5%; allow the byte's rounding.
        expect(highest - before, greaterThan(0));
        expect((highest - before) / 255, lessThanOrEqualTo(0.2 + 1 / 255));
      }
    });

    test('offered load below saturation leaves time truly spare', () {
      final CuSim s = CuSim(const CuConfig(loadPercent: 50))..runIntervals(50);
      final CuReading r = s.reading(window: 50, countReserved: false)!;
      expect(r.totals.share(CuSpan.spare), greaterThan(0.3));
      expect(r.exactShare, closeTo(0.732 / 2, 0.05));
    });

    test('non-Wi-Fi bursts are busy time with no frames', () {
      final CuSim s = CuSim(const CuConfig(loadPercent: 5, nonWifi: true))
        ..runIntervals(50);
      final CuReading r = s.reading(window: 50, countReserved: false)!;
      expect(r.totals.share(CuSpan.nonWifi), closeTo(0.2, 0.05));
    });

    test('while the window fills, the meter averages the intervals there '
        'are', () {
      final CuSim s = CuSim(const CuConfig());
      expect(s.reading(window: 50, countReserved: false), isNull);
      s.runIntervals(3);
      final CuReading r = s.reading(window: 50, countReserved: false)!;
      expect(r.filling, isTrue);
      expect(r.intervalsUsed, 3);
      expect(r.exactShare, closeTo(0.732, 0.03));
    });

    test('collisions happen with several senders and are busy time', () {
      final CuSim s = CuSim(const CuConfig(senders: 10))..runIntervals(10);
      expect(s.collidedAttempts, greaterThan(0));
      final CuReading r = s.reading(window: 10, countReserved: false)!;
      expect(r.totals.share(CuSpan.collision), greaterThan(0.05));
    });
  });

  group('many senders', () {
    test('the simulated throughput share falls as saturated stations rise '
        'from 5 to 50', () {
      final CuCurvePoint p5 = saturationPoint(5);
      final CuCurvePoint p20 = saturationPoint(20);
      final CuCurvePoint p50 = saturationPoint(50);
      expect(p5.payloadShare, greaterThan(p20.payloadShare));
      expect(p20.payloadShare, greaterThan(p50.payloadShare));
      // Busy stays high while the data share falls: collisions are busy.
      expect(p50.busyShare, greaterThan(p50.payloadShare + 0.3));
      expect(p50.collisionShare, greaterThan(p5.collisionShare));
    });

    test('the curve covers the spec range, 1 to 50 stations', () {
      final List<CuCurvePoint> c = saturationCurve();
      expect(c.first.stations, 1);
      expect(c.last.stations, kCuMaxSenders);
    });

    test('the published reference points are the brief\'s, and only those', () {
      expect(kCuBianchiBasic, <(int, double)>[(5, 0.80), (50, 0.55)]);
      expect(kCuBianchiRtsCts, 0.83);
    });
  });
}
