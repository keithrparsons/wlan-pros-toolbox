// Pins the teaching claims of What an Interferer Costs (interferer-cost)
// against Pax's brief (Deliverables/2026-09-27-classroom-interferer-and-ds-
// sources/RESEARCH-BRIEF.md Part 1): the thresholds per preset and width,
// the 20 dB gap and the distances it buys, the microwave's duty timing, the
// Bluetooth hop share, the corruption anchors from Airshark, and the answer
// to the predict-then-reveal question.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/fspl_math.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/interferer_cost_model.dart';

IcSourceResult _eval(IcConfig c, IcSource s) =>
    computeInterfererCost(c).sources[s]!;

void main() {
  group('thresholds', () {
    test('preamble detect -82 and energy detect -62 dBm, 20 dB = 100x', () {
      final IcResult r = computeInterfererCost(const IcConfig());
      expect(r.preambleDetectDbm, -82);
      expect(r.energyDetectDbm, -62);
      expect(r.gapDb, 20);
      expect(r.gapPowerRatio, closeTo(100, 1e-9));
    });

    test('primary preamble detect rises 3 dB per doubling: -82/-79/-76/-73; '
        'no 320 MHz value is offered', () {
      expect(kIcWidthsMHz, <int>[20, 40, 80, 160]);
      expect(
        <double>[for (final int w in kIcWidthsMHz) icPreambleDetectDbm(w)],
        <double>[-82, -79, -76, -73],
      );
      expect(() => icPreambleDetectDbm(320), throwsArgumentError);
    });

    test('energy detect does not move with width', () {
      for (final int w in kIcWidthsMHz) {
        final IcConfig c = IcConfig(channel: IcChannel.ch36, widthMHz: w);
        expect(_eval(c, IcSource.videoSender).thresholdDbm, -62);
        expect(
          _eval(c, IcSource.wifiNeighbor).thresholdDbm,
          icPreambleDetectDbm(w),
        );
      }
    });
  });

  group('each preset against its threshold', () {
    test('Wi-Fi neighbor at -78: above -82, your radio waits its whole '
        '30% airtime and nothing is corrupted', () {
      final IcSourceResult n = _eval(const IcConfig(), IcSource.wifiNeighbor);
      expect(n.heard, IcHeard.preamble);
      expect(n.marginDb, 4);
      expect(n.deferralShare, 0.30);
      expect(n.corruptionShare, 0);
    });

    test('the same -78 dBm neighbor at 80 MHz is under -76: not heard, so '
        'its frames land on yours instead', () {
      final IcSourceResult n = _eval(
        const IcConfig(channel: IcChannel.ch36, widthMHz: 80),
        IcSource.wifiNeighbor,
      );
      expect(n.heard, IcHeard.notHeard);
      expect(n.deferralShare, 0);
      expect(n.overlapShare, 0.30);
      expect(n.corruptionShare, greaterThan(0));
    });

    test('a Wi-Fi neighbor is heard at -82 exactly and not at -82.5', () {
      expect(
        _eval(const IcConfig(wifiLevelDbm: -82), IcSource.wifiNeighbor).heard,
        IcHeard.preamble,
      );
      expect(
        _eval(const IcConfig(wifiLevelDbm: -82.5), IcSource.wifiNeighbor).heard,
        IcHeard.notHeard,
      );
    });

    test('non-Wi-Fi energy at -70 is not heard; at -62 it is', () {
      for (final IcSource s in <IcSource>[
        IcSource.microwave,
        IcSource.bluetooth,
        IcSource.videoSender,
      ]) {
        expect(
          _eval(const IcConfig().withLevel(s, -70), s).heard,
          IcHeard.notHeard,
          reason: s.name,
        );
        expect(
          _eval(const IcConfig().withLevel(s, -62), s).heard,
          IcHeard.energy,
          reason: s.name,
        );
      }
    });

    test('microwave at -50 on channel 11: above -62, your radio waits in '
        'the ON half, 50%', () {
      final IcSourceResult m = _eval(const IcConfig(), IcSource.microwave);
      expect(m.levelInChannelDbm, -50);
      expect(m.heard, IcHeard.energy);
      expect(m.deferralShare, 0.5);
      expect(m.corruptionShare, 0);
    });

    test('the same oven on channel 1 is 30 dB down (illustrative), under '
        'energy detect, and costs almost nothing', () {
      final IcSourceResult m = _eval(
        const IcConfig(channel: IcChannel.ch1),
        IcSource.microwave,
      );
      expect(m.levelInChannelDbm, -80);
      expect(icMicrowaveOffsetIsIllustrative(IcChannel.ch1), isTrue);
      expect(icMicrowaveOffsetIsIllustrative(IcChannel.ch11), isFalse);
      expect(m.heard, IcHeard.notHeard);
      expect(m.totalShare, lessThan(0.01));
    });

    test('no oven and no Bluetooth on 5 GHz; the neighbor and the video '
        'sender are still on your channel', () {
      const IcConfig c = IcConfig(channel: IcChannel.ch36);
      expect(_eval(c, IcSource.microwave).heard, IcHeard.absent);
      expect(_eval(c, IcSource.bluetooth).heard, IcHeard.absent);
      expect(_eval(c, IcSource.microwave).totalShare, 0);
      expect(icTimeline(c, IcSource.microwave), isEmpty);
      expect(_eval(c, IcSource.wifiNeighbor).heard, IcHeard.preamble);
      expect(_eval(c, IcSource.videoSender).heard, IcHeard.notHeard);
    });

    test('Bluetooth at -42: above -62 only while a hop is in your channel, '
        'so it costs 2/6 x 20/79 = 8.4% waiting', () {
      final IcSourceResult b = _eval(const IcConfig(), IcSource.bluetooth);
      expect(b.heard, IcHeard.energy);
      expect(b.onAirShare, closeTo(2 / 6 * 20 / 79, 1e-12));
      expect(b.deferralShare, closeTo(0.0844, 1e-4));
    });

    test('video sender at -70: nobody waits, and 80% or more of your '
        'airtime goes to ruined frames (Airshark anchor)', () {
      final IcSourceResult v = _eval(const IcConfig(), IcSource.videoSender);
      expect(v.heard, IcHeard.notHeard);
      expect(v.deferralShare, 0);
      expect(v.onAirShare, 1);
      expect(v.corruptionShare, greaterThanOrEqualTo(0.8));
    });

    test('a stronger video sender, above -62, holds the channel busy all '
        'the time', () {
      final IcSourceResult v = _eval(
        const IcConfig(videoLevelDbm: -55),
        IcSource.videoSender,
      );
      expect(v.heard, IcHeard.energy);
      expect(v.deferralShare, 1);
    });
  });

  group('corruption anchors (illustrative curve, Airshark shape)', () {
    test('the oven costs almost nothing below -60 dBm and plateaus at 0.5 '
        'above energy detect', () {
      for (double l = -100; l <= -63; l += 1) {
        expect(
          _eval(IcConfig(microwavePeakDbm: l), IcSource.microwave).totalShare,
          lessThan(0.05),
          reason: '$l dBm',
        );
      }
      for (double l = -62; l <= -30; l += 1) {
        expect(
          _eval(IcConfig(microwavePeakDbm: l), IcSource.microwave).totalShare,
          0.5,
          reason: '$l dBm',
        );
      }
    });

    test('Bluetooth never costs more than 10% at any level', () {
      for (double l = -100; l <= -30; l += 1) {
        expect(
          _eval(IcConfig(bluetoothLevelDbm: l), IcSource.bluetooth).totalShare,
          lessThanOrEqualTo(0.1),
          reason: '$l dBm',
        );
      }
    });

    test('fail probability rises with level for every source', () {
      for (final IcSource s in IcSource.values) {
        double prev = -1;
        for (double l = -100; l <= -30; l += 5) {
          final double p = icFailProbability(s, l);
          expect(p, greaterThan(prev));
          expect(p, inInclusiveRange(0, 1));
          prev = p;
        }
      }
    });
  });

  group('the distance each is heard at', () {
    test('FSPL at 1 m and 2.45 GHz is 40.2 dB (Pax)', () {
      expect(FsplMath.fsplDb(1, 2450), closeTo(40.2, 0.05));
    });

    test('at 20 MHz a Wi-Fi neighbor defers you 10x, 4.6x, 3.7x farther '
        '(100x, 21.5x, 13.9x the area) at n = 2, 3, 3.5', () {
      for (final (double n, double d, double a) in <(double, double, double)>[
        (2.0, 10, 100),
        (3.0, 4.64, 21.5),
        (3.5, 3.73, 13.9),
      ]) {
        final IcResult r = computeInterfererCost(IcConfig(exponent: n));
        expect(r.distanceRatio, closeTo(d, 0.01), reason: 'n = $n');
        expect(r.areaRatio, closeTo(a, 0.1), reason: 'n = $n');
      }
    });

    test('the ratio is independent of the reference power and channel', () {
      for (final IcChannel ch in IcChannel.values) {
        final IcResult r = computeInterfererCost(IcConfig(channel: ch));
        expect(r.distanceRatio, closeTo(math.pow(10, 20 / 30), 1e-9));
      }
    });

    test('a 20 dBm transmitter on channel 11 at n = 3 reaches -82 at about '
        '114 m and -62 at about 25 m', () {
      final IcResult r = computeInterfererCost(const IcConfig());
      final double l1 = FsplMath.fsplDb(1, 2462);
      expect(
        r.wifiHeardAtM,
        closeTo(math.pow(10, (20 + 82 - l1) / 30).toDouble(), 1e-9),
      );
      expect(r.wifiHeardAtM, closeTo(113, 2));
      expect(r.energyHeardAtM, closeTo(24.4, 1));
    });

    test('wider PPDUs shrink the gap by 3 dB per doubling', () {
      expect(
        <double>[
          for (final int w in kIcWidthsMHz)
            computeInterfererCost(
              IcConfig(channel: IcChannel.ch36, widthMHz: w),
            ).gapDb,
        ],
        <double>[20, 17, 14, 11],
      );
    });
  });

  group('microwave duty timing', () {
    test('60 Hz: 16.67 ms cycle, 8.33 ms ON; 50 Hz: 20 ms, 10 ms ON', () {
      expect(icMicrowavePeriodMs(IcMains.hz60), closeTo(16.667, 1e-3));
      expect(icMicrowaveOnMs(IcMains.hz60), closeTo(8.333, 1e-3));
      expect(icMicrowavePeriodMs(IcMains.hz50), 20);
      expect(icMicrowaveOnMs(IcMains.hz50), 10);
      expect(kIcMicrowaveDuty, 0.5);
    });

    test('the timeline has one ON burst per mains cycle, starting on the '
        'cycle, and the axis does not change with mains', () {
      for (final IcMains m in IcMains.values) {
        final List<IcSpan> s = icTimeline(
          IcConfig(mains: m),
          IcSource.microwave,
        );
        final double t = icMicrowavePeriodMs(m);
        expect(s, hasLength((kIcTimelineMs / t).ceil()), reason: m.label);
        for (int k = 0; k < s.length; k++) {
          expect(s[k].startMs, closeTo(k * t, 1e-9));
          final double len = s[k].endMs - s[k].startMs;
          expect(len, closeTo(math.min(t / 2, kIcTimelineMs - k * t), 1e-9));
        }
      }
      // 50 Hz fits exactly three cycles: exactly half ON.
      expect(
        icSpanShare(
          icTimeline(const IcConfig(mains: IcMains.hz50), IcSource.microwave),
        ),
        closeTo(0.5, 1e-12),
      );
      expect(kIcTimelineMs, 60);
    });

    test('in the ON half your radio waits only when the oven is above '
        '-62 dBm in your channel', () {
      expect(
        _eval(
          const IcConfig(microwavePeakDbm: -61),
          IcSource.microwave,
        ).deferralShare,
        0.5,
      );
      expect(
        _eval(
          const IcConfig(microwavePeakDbm: -63),
          IcSource.microwave,
        ).deferralShare,
        0,
      );
    });
  });

  group('Bluetooth and neighbor timelines', () {
    test('20 of 79 hop channels land inside each 2.4 GHz channel', () {
      for (final IcChannel c in <IcChannel>[
        IcChannel.ch1,
        IcChannel.ch6,
        IcChannel.ch11,
      ]) {
        int n = 0;
        for (int k = 0; k < kIcBtChannels; k++) {
          if (icBtHopInChannel(k, c)) n++;
        }
        expect(n, 20, reason: c.label);
      }
      expect(kIcBtInChannelShare, closeTo(0.2532, 1e-4));
    });

    test('the Bluetooth sample uses whole 625 us slots, in-channel only', () {
      final List<IcSpan> s = icTimeline(const IcConfig(), IcSource.bluetooth);
      expect(s, isNotEmpty);
      for (final IcSpan x in s) {
        expect(x.endMs - x.startMs, closeTo(0.625, 1e-9));
      }
      expect(icSpanShare(s), inInclusiveRange(0.02, 0.16));
    });

    test('the neighbor sample is about its airtime', () {
      for (final double a in <double>[0.1, 0.3, 0.5, 0.8]) {
        final List<IcSpan> s = icTimeline(
          IcConfig(neighborAirtime: a),
          IcSource.wifiNeighbor,
        );
        expect(icSpanShare(s), closeTo(a, 0.06), reason: '$a');
      }
    });

    test('the timeline is deterministic', () {
      expect(
        icTimeline(const IcConfig(), IcSource.bluetooth),
        icTimeline(const IcConfig(), IcSource.bluetooth),
      );
    });
  });

  group('predict, then reveal', () {
    test('both at -70: the neighbor costs more; it is above -82 and the '
        'oven is below -62', () {
      final IcResult r = computeInterfererCost(kIcQuestionScene);
      final IcSourceResult n = r.sources[IcSource.wifiNeighbor]!;
      final IcSourceResult m = r.sources[IcSource.microwave]!;
      expect(n.levelInChannelDbm, -70);
      expect(m.levelInChannelDbm, -70);
      expect(n.heard, IcHeard.preamble);
      expect(m.heard, IcHeard.notHeard);
      expect(n.deferralShare, 0.30);
      expect(m.deferralShare, 0);
      expect(m.totalShare, lessThan(0.01));
      expect(icCostlier(kIcQuestionScene), IcSource.wifiNeighbor);
    });

    test('the answer holds at every width and neighbor airtime', () {
      for (final int w in kIcWidthsMHz) {
        for (final double a in <double>[0.1, 0.3, 0.8]) {
          // The oven needs 2.4 GHz; widths above 20 are a 5 GHz setting,
          // where there is no oven, so the neighbor wins by default there.
          final IcConfig c = kIcQuestionScene.copyWith(
            neighborAirtime: a,
            widthMHz: w,
            channel: w == 20 ? IcChannel.ch11 : IcChannel.ch36,
          );
          expect(icCostlier(c), IcSource.wifiNeighbor, reason: '$w $a');
        }
      }
    });
  });
}
