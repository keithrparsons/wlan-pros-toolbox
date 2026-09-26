// Unit tests for the Wi-Fi Classroom Power Save model (power-save).
//
// The field values come from the Wi-Fi Classroom wave 3 brief §9 and the wave 5
// brief §9 (TWT mantissa 16 bits, exponent 5 bits, wake duration in 256 µs
// or 1 TU; U-APSD QoS Info B0-B3 and Max SP Length B5-B6), per spec 24's
// "Done means".

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/power_save_model.dart';

/// Regular traffic so every run is deterministic and dense enough that a
/// worst case is reached.
const TrafficSettings _steady = TrafficSettings(
  dlBurstsPerS: 5,
  dlBurstSize: 2,
  ulPerS: 1,
  groupPerS: 20,
  regular: true,
);

void main() {
  group('units', () {
    test('1 TU = 1024 µs and 100 TU = 102.4 ms', () {
      expect(kTuUs, 1024);
      expect(tuToUs(1), 1024);
      expect(tuToUs(100), 102400);
      expect(tuToMs(100), closeTo(102.4, 1e-12));
    });
  });

  group('TWT fields', () {
    test('wake interval = mantissa x 2^exponent µs', () {
      expect(twtWakeIntervalUs(62500, 4), 1000000);
      expect(twtWakeIntervalUs(1, 0), 1);
      expect(twtWakeIntervalUs(3, 10), 3072);
      expect(twtWakeIntervalUs(58594, 9), 58594 * 512);
    });

    test('the mantissa is 16 bits and the exponent 5 bits', () {
      expect(kTwtMantissaMax, 65535);
      expect(kTwtExponentMax, 31);
      expect(twtWakeIntervalUs(65535, 0), 65535);
      expect(twtWakeIntervalUs(65536, 0), isNull);
      expect(twtWakeIntervalUs(-1, 0), isNull);
      expect(twtWakeIntervalUs(1, 32), isNull);
      // The largest value both fields allow, exact (no 32-bit shift).
      expect(twtWakeIntervalUs(65535, 31), 65535 * 2147483648);
    });

    test('minimum wake duration is one octet of 256 µs or 1 TU', () {
      expect(twtWakeDurationUs(16, TwtDurationUnit.us256), 4096);
      expect(twtWakeDurationUs(4, TwtDurationUnit.tu), 4096);
      expect(twtWakeDurationUs(255, TwtDurationUnit.tu), 255 * 1024);
      expect(twtWakeDurationUs(256, TwtDurationUnit.us256), isNull);
    });

    test('invalid TWT values are refused in words', () {
      expect(const TwtSettings().error, isNull);
      expect(const TwtSettings(mantissa: 0).error, contains('no wake'));
      expect(const TwtSettings(mantissa: 70000).error, contains('16 bits'));
      expect(
        const TwtSettings(mantissa: 65535, exponent: 13).error,
        contains('5 minutes'),
      );
      expect(
        const TwtSettings(
          mantissa: 1000,
          exponent: 0,
          duration: 4,
          durationUnit: TwtDurationUnit.tu,
        ).error,
        contains('never doze'),
      );
    });
  });

  group('U-APSD fields', () {
    test('Max SP Length codes map 0 = all, 1 = 2, 2 = 4, 3 = 6', () {
      expect(maxSpFromCode(0).frames, isNull);
      expect(maxSpFromCode(1).frames, 2);
      expect(maxSpFromCode(2).frames, 4);
      expect(maxSpFromCode(3).frames, 6);
    });

    test('QoS Info: VO B0, VI B1, BK B2, BE B3, Max SP B5-B6', () {
      expect(
        qosInfoByte(<AccessCategory>{AccessCategory.vo}, MaxSpLength.all),
        0x01,
      );
      expect(
        qosInfoByte(<AccessCategory>{AccessCategory.vi}, MaxSpLength.all),
        0x02,
      );
      expect(
        qosInfoByte(<AccessCategory>{AccessCategory.bk}, MaxSpLength.all),
        0x04,
      );
      expect(
        qosInfoByte(<AccessCategory>{AccessCategory.be}, MaxSpLength.all),
        0x08,
      );
      expect(
        qosInfoByte(AccessCategory.values.toSet(), MaxSpLength.six),
        0x0F | (3 << 5),
      );
      expect(qosInfoByte(<AccessCategory>{}, MaxSpLength.two), 0x20);
    });

    test('a service period carries at most Max SP Length frames', () {
      // One burst of 7 frames, the client wakes every beacon.
      for (final MaxSpLength sp in MaxSpLength.values) {
        final PsRun run = simulatePowerSave(
          PsConfig(
            mode: PsMode.uapsd,
            listenInterval: 1,
            dtimPeriod: 1,
            uapsd: UapsdSettings(maxSp: sp),
            traffic: const TrafficSettings(
              dlBurstsPerS: 1 / 60,
              dlBurstSize: 7,
              ulPerS: 0,
              groupPerS: 0,
              regular: true,
            ),
          ),
        );
        final int triggers = run.spans
            .where((AwakeSpan s) => s.kind == AwakeKind.send)
            .length;
        final int per = sp.frames ?? 7;
        expect(triggers, (7 / per).ceil(), reason: sp.label);
        expect(run.downlink.count, 7);
      }
    });

    test('an AC without its U-APSD flag falls back to PS-Poll', () {
      const TrafficSettings t = TrafficSettings(
        dlBurstsPerS: 1 / 60,
        dlBurstSize: 3,
        ulPerS: 0,
        groupPerS: 0,
        ac: AccessCategory.bk,
        regular: true,
      );
      final PsRun on = simulatePowerSave(
        const PsConfig(mode: PsMode.uapsd, traffic: t),
      );
      final PsRun off = simulatePowerSave(
        const PsConfig(
          mode: PsMode.uapsd,
          traffic: t,
          uapsd: UapsdSettings(acs: <AccessCategory>{AccessCategory.vo}),
        ),
      );
      expect(on.spans.where((s) => s.kind == AwakeKind.send), hasLength(1));
      expect(off.spans.where((s) => s.kind == AwakeKind.send), isEmpty);
      // Three PS-Polls cost more than one trigger and three deliveries.
      expect(off.awakeUs, greaterThan(on.awakeUs));
    });

    test('an uplink frame on a trigger-enabled AC retrieves the downlink', () {
      // Voice: 50 frames/s each way on AC_VO.
      const TrafficSettings voice = TrafficSettings(
        dlBurstsPerS: 50,
        ulPerS: 50,
        groupPerS: 0,
        ac: AccessCategory.vo,
        regular: true,
      );
      final PsRun legacy = simulatePowerSave(
        const PsConfig(mode: PsMode.legacy, traffic: voice),
      );
      final PsRun uapsd = simulatePowerSave(
        const PsConfig(mode: PsMode.uapsd, traffic: voice),
      );
      // Legacy waits for a TIM every third beacon (307.2 ms); U-APSD gets
      // each frame on the next uplink, within 20 ms.
      expect(uapsd.downlink.worstUs!, lessThan(20000 + 2000));
      expect(legacy.downlink.worstUs!, greaterThan(300000));
    });
  });

  group('DTIM and the listen interval', () {
    test('with DTIM period N the client wakes for group traffic every N '
        'beacons', () {
      for (int n = 1; n <= 10; n++) {
        for (final PsMode m in <PsMode>[PsMode.legacy, PsMode.uapsd]) {
          final PsRun run = simulatePowerSave(
            PsConfig(
              mode: m,
              dtimPeriod: n,
              listenInterval: 10,
              traffic: _steady,
            ),
          );
          final List<int> groupWakes = <int>[
            for (final BeaconMark b in run.beacons)
              if (b.listened && b.groupFrames > 0) b.index,
          ];
          expect(groupWakes, isNotEmpty);
          for (final int k in groupWakes) {
            expect(k % n, 0, reason: 'DTIM $n, beacon $k');
          }
          for (final BeaconMark b in run.beacons) {
            expect(b.dtim, b.index % n == 0);
            if (b.dtim) expect(b.listened, isTrue);
          }
          expect(run.groupMissed, 0);
        }
      }
    });

    test('longer DTIM never increases awake time (listen interval 1, and '
        'DTIM stepping through multiples of the listen interval)', () {
      // Compared over the same whole DTIM cycles: up to beacon 10080, a
      // DTIM beacon for every period 1 to 10 (a multiple of 2520). A cut
      // anywhere else lets one period's last DTIM fall later inside the
      // run than another's, which moves a few group frames in or out of
      // the window and says nothing about the DTIM period. The TWT values
      // only stretch the run to 20 minutes.
      //
      // Uplink is off here on purpose. An uplink frame that happens to land
      // while the radio is awake for a DTIM's group frames rides that wake
      // for free; with a longer DTIM the burst is not there and it needs a
      // wake of its own. That is a coincidence of timing, not a cost of the
      // DTIM period (9 wakes, 2.2 ms in 17 minutes at 1 frame/s).
      const TrafficSettings noUplink = TrafficSettings(
        dlBurstsPerS: 5,
        dlBurstSize: 2,
        ulPerS: 0,
        groupPerS: 20,
        regular: true,
      );
      const TwtSettings longRun = TwtSettings(mantissa: 36621, exponent: 13);
      final double cut = 10080.0 * tuToUs(100);
      for (final PsMode m in <PsMode>[
        PsMode.awake,
        PsMode.legacy,
        PsMode.uapsd,
      ]) {
        double last = double.infinity;
        for (int d = 1; d <= 10; d++) {
          final PsRun run = simulatePowerSave(
            PsConfig(
              mode: m,
              dtimPeriod: d,
              listenInterval: 1,
              traffic: noUplink,
              twt: longRun,
            ),
          );
          expect(run.horizonUs, greaterThan(cut));
          final double awake = run.awakeUsBetween(0, cut);
          expect(awake, lessThanOrEqualTo(last + 1e-6), reason: '$m DTIM $d');
          last = awake;
        }
        // Listen interval 3: DTIM 3, 6, 9.
        last = double.infinity;
        for (final int d in <int>[3, 6, 9]) {
          final PsRun run = simulatePowerSave(
            PsConfig(
              mode: m,
              dtimPeriod: d,
              listenInterval: 3,
              traffic: noUplink,
              twt: longRun,
            ),
          );
          final double awake = run.awakeUsBetween(0, cut);
          expect(
            awake,
            lessThanOrEqualTo(last + 1e-6),
            reason: '$m DTIM $d, LI 3',
          );
          last = awake;
        }
      }
    });

    test('SPEC LIMIT, pinned: when DTIM and listen interval do not line up, '
        'a longer DTIM can add wakes', () {
      // The client wakes on listen-interval beacons AND DTIM beacons. With
      // LI 3: DTIM 3 = every 3rd beacon; DTIM 4 = beacons 0, 3, 4, 6, 8, 9,
      // 12, ... = half of them.
      const TrafficSettings quiet = TrafficSettings(
        dlBurstsPerS: 0,
        ulPerS: 0,
        groupPerS: 0,
      );
      final PsRun d3 = simulatePowerSave(
        const PsConfig(dtimPeriod: 3, listenInterval: 3, traffic: quiet),
      );
      final PsRun d4 = simulatePowerSave(
        const PsConfig(dtimPeriod: 4, listenInterval: 3, traffic: quiet),
      );
      expect(d4.beaconsHeard, greaterThan(d3.beaconsHeard));
      expect(d4.awakeUs, greaterThan(d3.awakeUs));
    });

    test('longer DTIM never decreases worst group-traffic latency', () {
      double lastBound = 0;
      double lastMeasured = 0;
      for (int d = 1; d <= 10; d++) {
        final double bound = groupLatencyBoundUs(100, d);
        expect(bound, greaterThanOrEqualTo(lastBound));
        lastBound = bound;
        for (final PsMode m in <PsMode>[PsMode.awake, PsMode.legacy]) {
          final PsRun run = simulatePowerSave(
            PsConfig(
              mode: m,
              dtimPeriod: d,
              listenInterval: 1,
              traffic: _steady,
            ),
          );
          final double worst = run.group.worstUs!;
          expect(worst, lessThanOrEqualTo(bound + 1e-6));
          if (m == PsMode.legacy) {
            expect(
              worst,
              greaterThanOrEqualTo(lastMeasured),
              reason: 'DTIM $d',
            );
            lastMeasured = worst;
          }
        }
      }
    });
  });

  group('TWT', () {
    test('individual TWT sleeps through beacons and wakes per interval', () {
      final PsRun run = simulatePowerSave(
        const PsConfig(mode: PsMode.twt, traffic: TrafficSettings(ulPerS: 0)),
      );
      expect(run.beaconsHeard, 0);
      // 60 s run, 1 s interval, first SP at 25 ms.
      expect(run.serviceStarts, hasLength(60));
      expect(run.serviceStarts[1] - run.serviceStarts[0], 1000000);
      // Group frames go out after DTIMs while it dozes.
      expect(run.groupMissed, greaterThan(0));
      expect(run.group.count, 0);
      // Every downlink frame waits at most one interval plus its delivery.
      expect(run.downlink.worstUs!, lessThanOrEqualTo(1000000 + kSpFrameUs));
    });

    test('waking for DTIMs hears the group traffic', () {
      final PsRun run = simulatePowerSave(
        const PsConfig(mode: PsMode.twt, twt: TwtSettings(wakeForDtim: true)),
      );
      expect(run.groupMissed, 0);
      expect(run.group.count, greaterThan(0));
    });

    test('broadcast TWT starts each service period after a beacon', () {
      final PsRun run = simulatePowerSave(
        const PsConfig(
          mode: PsMode.twt,
          twt: TwtSettings(kind: TwtKind.broadcast),
        ),
      );
      // 1 s over 102.4 ms beacons: every 10th beacon.
      expect(run.beaconsHeard, run.serviceStarts.length);
      for (final BeaconMark b in run.beacons.where((b) => b.listened)) {
        expect(b.index % 10, 0);
      }
    });

    test('the run covers four TWT cycles, 60 s to 20 minutes', () {
      expect(const PsConfig().horizonUs, 60000000);
      expect(
        const PsConfig(
          twt: TwtSettings(mantissa: 58594, exponent: 9),
        ).horizonUs,
        4 * 58594 * 512,
      );
    });

    test('TWT at 30 s is awake far less than legacy PS at DTIM 3', () {
      const TrafficSettings sensor = TrafficSettings(
        dlBurstsPerS: 0.02,
        ulPerS: 0,
        groupPerS: 0,
      );
      final PsRun legacy = simulatePowerSave(const PsConfig(traffic: sensor));
      final PsRun twt = simulatePowerSave(
        const PsConfig(
          mode: PsMode.twt,
          traffic: sensor,
          twt: TwtSettings(mantissa: 58594, exponent: 9),
        ),
      );
      expect(twt.awakeFraction, lessThan(legacy.awakeFraction / 10));
      // And the cost: downlink waits up to the interval.
      expect(twt.downlink.worstUs!, greaterThan(legacy.downlink.worstUs!));
    });
  });

  group('energy', () {
    test('average current from awake fraction and currents is exact', () {
      expect(averageCurrentMa(0.25, 40, 0), 10);
      expect(averageCurrentMa(0, 50, 0.02), 0.02);
      expect(averageCurrentMa(1, 50, 0.02), 50);
      expect(averageCurrentMa(0.5, 100, 2), 51);
      expect(batteryHours(1000, 10), 100);
      expect(batteryHours(1000, 0), double.infinity);
    });

    test('a run applies the same arithmetic to its own awake fraction', () {
      final PsRun run = simulatePowerSave(
        const PsConfig(awakeMa: 80, dozeMa: 0.01, batteryMah: 2000),
      );
      final double f = run.awakeUs / run.horizonUs;
      expect(run.awakeFraction, f);
      expect(run.averageMa, f * 80 + (1 - f) * 0.01);
      expect(run.batteryLifeHours, 2000 / run.averageMa);
    });

    test('always awake is awake the whole run at the awake current', () {
      final PsRun run = simulatePowerSave(const PsConfig(mode: PsMode.awake));
      expect(run.awakeFraction, 1);
      expect(run.averageMa, 50);
      expect(run.wakeCount, 1);
    });
  });

  group('legacy PS', () {
    test('one PS-Poll per buffered frame, after a TIM', () {
      final PsRun run = simulatePowerSave(
        const PsConfig(
          listenInterval: 1,
          dtimPeriod: 1,
          traffic: TrafficSettings(
            dlBurstsPerS: 1 / 60,
            dlBurstSize: 4,
            ulPerS: 0,
            groupPerS: 0,
            regular: true,
          ),
        ),
      );
      final List<AwakeSpan> polls = run.spans
          .where(
            (AwakeSpan s) =>
                s.kind == AwakeKind.frames &&
                (s.endUs - s.startUs - kPsPollUs).abs() < 1e-6,
          )
          .toList();
      expect(polls, hasLength(4));
      expect(run.beacons.where((BeaconMark b) => b.tim), hasLength(1));
      expect(run.downlinkWaiting, 0);
    });

    test('no traffic: the client only hears beacons', () {
      final PsRun run = simulatePowerSave(
        const PsConfig(
          traffic: TrafficSettings(dlBurstsPerS: 0, ulPerS: 0, groupPerS: 0),
        ),
      );
      expect(run.downlink.count, 0);
      expect(run.downlink.meanUs, isNull);
      // Every third beacon over 60 s: ceil(586 / 3) wakes of 1.5 ms.
      final int beacons = (60000000 / 102400).ceil();
      expect(run.wakeCount, (beacons / 3).ceil());
      expect(
        run.awakeUs,
        closeTo(
          run.wakeCount * (kWakeRampUs + kBeaconRxUs) - kWakeRampUs,
          1e-6,
        ),
      );
    });
  });

  test('random traffic is repeatable per seed', () {
    final PsRun a = simulatePowerSave(const PsConfig());
    final PsRun b = simulatePowerSave(const PsConfig());
    final PsRun c = simulatePowerSave(
      const PsConfig(traffic: TrafficSettings(seed: 2)),
    );
    expect(a.awakeUs, b.awakeUs);
    expect(a.frames.length, b.frames.length);
    expect(c.awakeUs, isNot(a.awakeUs));
  });
}
