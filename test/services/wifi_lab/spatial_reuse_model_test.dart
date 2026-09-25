// Pins every number the Spatial Reuse screen shows. The first group is the
// "Done means" list of myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/20-spatial-reuse.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/channel_planner_model.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/fspl_math.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/spatial_reuse_model.dart';

ReuseDecision _decide(
  double level, {
  bool coloring = true,
  bool sameColor = false,
  double obssPd = -82,
  double ref = 21,
}) => decideDeferral(
  levelDbm: level,
  coloring: coloring,
  sameColor: sameColor,
  obssPdDbm: obssPd,
  txPwrRefDbm: ref,
);

void main() {
  group('spec 20 Done means', () {
    test('a neighbor frame at -78 dBm defers under legacy rules', () {
      final ReuseDecision d = _decide(-78, coloring: false);
      expect(d.defers, isTrue);
      expect(d.rule, ReuseRule.preambleDetect);
    });

    test('the same frame does not defer with OBSS_PD at -72', () {
      final ReuseDecision d = _decide(-78, obssPd: -72);
      expect(d.defers, isFalse);
      expect(d.rule, ReuseRule.spatialReuse);
    });

    test('raising OBSS_PD from -82 to -72 limits power to TX_PWRref - 10', () {
      for (final TxPwrRefClass c in TxPwrRefClass.values) {
        expect(txPowerLimitDbm(obssPdDbm: -82, txPwrRefDbm: c.dbm), c.dbm);
        expect(txPowerLimitDbm(obssPdDbm: -72, txPwrRefDbm: c.dbm), c.dbm - 10);
      }
      expect(_decide(-78, obssPd: -72).txPowerLimitDbm, 11);
      expect(_decide(-78, obssPd: -72, ref: 25).txPowerLimitDbm, 15);
    });

    test('an intra-BSS frame at -78 dBm always defers', () {
      for (double pd = -82; pd <= -62; pd += 1) {
        final ReuseDecision d = _decide(-78, sameColor: true, obssPd: pd);
        expect(d.defers, isTrue, reason: 'OBSS_PD $pd');
        expect(d.rule, ReuseRule.intraBss);
      }
      expect(_decide(-78, coloring: false, sameColor: true).defers, isTrue);
    });

    test('energy at or above -62 dBm always defers', () {
      for (final double level in <double>[-62, -61.9, -50, -30]) {
        for (final bool coloring in <bool>[false, true]) {
          for (final bool same in <bool>[false, true]) {
            final ReuseDecision d = _decide(
              level,
              coloring: coloring,
              sameColor: same,
              obssPd: -62,
            );
            expect(d.rule, ReuseRule.energyDetect, reason: '$level dBm');
          }
        }
      }
    });

    test('the per-width threshold rises 3 dB per doubling', () {
      expect(widthOffsetDb(20), 0);
      for (final int w in <int>[20, 40, 80]) {
        expect(
          thresholdForWidth(-72, w * 2) - thresholdForWidth(-72, w),
          closeTo(3.0, 0.011),
        );
      }
      expect(thresholdForWidth(-82, 40), closeTo(-79, 0.02));
      expect(thresholdForWidth(-82, 80), closeTo(-76, 0.03));
      expect(thresholdForWidth(-82, 160), closeTo(-73, 0.04));
    });
  });

  group('rules', () {
    test('thresholds are the Channel Planner values', () {
      expect(kPreambleDetectDbm, CcaRule.preambleDetect.thresholdDbm);
      expect(kPreambleDetectDbm, -82);
      expect(kEnergyDetectDbm, -62);
      expect(kObssPdMinDbm, -82);
      expect(kObssPdMaxDbm, -62);
    });

    test('a level exactly on a threshold fires it', () {
      expect(_decide(-82, coloring: false).rule, ReuseRule.preambleDetect);
      expect(_decide(-72, obssPd: -72).rule, ReuseRule.obssPd);
      expect(_decide(-72.1, obssPd: -72).rule, ReuseRule.spatialReuse);
    });

    test('below -82 nothing is detected and no power limit applies', () {
      for (final bool coloring in <bool>[false, true]) {
        final ReuseDecision d = _decide(-85, coloring: coloring, obssPd: -62);
        expect(d.rule, ReuseRule.notDetected);
        expect(d.txPowerLimitDbm, isNull);
      }
    });

    test('OBSS_PD at -82 behaves like legacy for a neighbor', () {
      expect(_decide(-80, obssPd: -82).rule, ReuseRule.obssPd);
    });

    test('OBSS_PD is held between -82 and -62', () {
      expect(clampObssPd(-90), -82);
      expect(clampObssPd(-50), -62);
      expect(txPowerLimitDbm(obssPdDbm: -50, txPwrRefDbm: 21), 1);
    });

    test('BSS color is 1 to 63', () {
      expect(kMinBssColor, 1);
      expect(kMaxBssColor, 63);
    });

    test('thermal noise is about -101 dBm in 20 MHz', () {
      expect(thermalNoiseDbm(20), closeTo(-100.99, 0.01));
      expect(thermalNoiseDbm(40) - thermalNoiseDbm(20), closeTo(3.01, 0.01));
    });

    test('power sum of two equal levels is 3 dB up', () {
      expect(powerSumDbm(-80, -80), closeTo(-76.99, 0.01));
    });
  });

  group('scenario', () {
    test('default: AP B hears AP A at about -77.7 dBm and waits', () {
      final ReuseAnalysis a = ReuseAnalysis.of(const ReuseScenario());
      final double expected =
          20 - FsplMath.logDistanceDb(50, kReuseFreqMHz, 3.0);
      expect(a.heardByBDbm, closeTo(expected, 1e-9));
      expect(a.heardByBDbm, closeTo(-77.7, 0.05));
      expect(a.decision.rule, ReuseRule.obssPd);
      expect(a.together, isFalse);
      expect(a.frameTimes, 2);
      expect(a.txPowerBDbm, 20);
      expect(a.linkA.interferenceDbm, isNull);
      expect(a.linkA.sinrDb, a.linkA.snrDb);
    });

    test('OBSS_PD -72: both send, AP B drops to 11 dBm', () {
      final ReuseAnalysis a = ReuseAnalysis.of(
        const ReuseScenario(obssPdDbm: -72),
      );
      expect(a.together, isTrue);
      expect(a.frameTimes, 1);
      expect(a.txPowerBDbm, 11);
      expect(a.powerCut, isTrue);
      // AP B's own client hears it 9 dB weaker than at 20 dBm.
      final ReuseAnalysis full = ReuseAnalysis.of(const ReuseScenario());
      expect(a.linkB.signalDbm, closeTo(full.linkB.signalDbm - 9, 1e-9));
      expect(a.linkA.interferenceDbm, isNotNull);
      expect(a.linkA.sinrDb, lessThan(a.linkA.snrDb));
      expect(a.linkA.costDb, greaterThan(0));
    });

    test('a limit above the configured power does not raise it', () {
      final ReuseAnalysis a = ReuseAnalysis.of(
        const ReuseScenario(
          obssPdDbm: -76,
          apPowerDbm: 10,
          txPwrRef: TxPwrRefClass.apMoreStreams,
        ),
      );
      // AP B hears 10 dB less (-87.7): below -82, not detected.
      expect(a.decision.rule, ReuseRule.notDetected);
      expect(a.txPowerBDbm, 10);
      expect(a.powerCut, isFalse);
    });

    test('coloring off: legacy preamble detect decides', () {
      final ReuseAnalysis a = ReuseAnalysis.of(
        const ReuseScenario(coloring: false, obssPdDbm: -62),
      );
      expect(a.decision.rule, ReuseRule.preambleDetect);
    });

    test('the same color number on both BSSs is intra-BSS', () {
      final ReuseAnalysis a = ReuseAnalysis.of(
        const ReuseScenario(colorA: 9, colorB: 9, obssPdDbm: -62),
      );
      expect(a.decision.rule, ReuseRule.intraBss);
    });

    test('a wider channel lowers the per-20 level by 3 dB per doubling', () {
      final ReuseAnalysis a20 = ReuseAnalysis.of(const ReuseScenario());
      final ReuseAnalysis a80 = ReuseAnalysis.of(
        const ReuseScenario(widthMHz: 80),
      );
      expect(a20.heardByBDbm - a80.heardByBDbm, closeTo(6.02, 0.01));
      expect(a80.obssPdAtWidthDbm, closeTo(-82 + 6.02, 0.01));
    });

    test('APs closer than 1 m use the 1 m loss', () {
      expect(reusePathLossDb(0, 3), reusePathLossDb(1, 3));
    });
  });
}
