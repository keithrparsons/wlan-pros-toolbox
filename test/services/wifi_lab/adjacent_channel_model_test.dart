// Pins the Adjacent Channels and AP Stacking model (spec 29, "Done means").
//
// Every figure is either from the wave-3 research brief's mask table or
// arithmetic on it: channels 1 and 6 at 25 MHz give -34 dBr at the victim's
// center (-28 at 20 MHz, -40 at 30 MHz, linear in dB), and the integrated
// leakage must lie between the mask at the victim's near and far edges.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/adjacent_channel_model.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/channel_planner_model.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/fspl_math.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/rate_vs_range_math.dart';

void main() {
  group('transmit mask', () {
    test('OFDM 20 MHz at 25 MHz (channels 1 and 6) is -34 dBr at the '
        'victim center, and the integrated leakage lies between the near '
        'and far band-edge mask values', () {
      final AciResult r = computeAci(
        const AciConfig(
          band: WifiBand.band24,
          family: AciMaskFamily.ofdm,
          separation: AciSeparation.ch1and6,
        ),
      );
      expect(r.plan.receiverChannel, 6);
      expect(r.plan.neighborChannel, 1);
      expect(r.plan.spacingMHz, 25);
      expect(r.maskAtReceiverCenterDbr, closeTo(-34, 1e-9));
      // Near edge at 15 MHz: -20 + (-8) x 4/9 = -23.56; far edge at 35: -40.
      expect(r.maskAtNearEdgeDbr, closeTo(-23.556, 1e-3));
      expect(r.maskAtFarEdgeDbr, -40);
      expect(r.leakageDbr, lessThan(r.maskAtNearEdgeDbr));
      expect(r.leakageDbr, greaterThan(r.maskAtFarEdgeDbr));
      // Recomputed independently (Python, 0.01 MHz midpoint rule): -29.80.
      expect(r.leakageDbr, closeTo(-29.80, 0.01));
    });

    test(
      'OFDM leakage agrees with Channel Planner at every 2.4 GHz spacing',
      () {
        for (final AciSeparation s in AciSeparation.forBand(WifiBand.band24)) {
          final AciResult r = computeAci(
            AciConfig(
              band: WifiBand.band24,
              family: AciMaskFamily.ofdm,
              separation: s,
            ),
          );
          expect(
            r.leakageDbr,
            closeTo(adjacentChannelDb(TxMask.ofdm, r.plan.spacingMHz), 1e-9),
            reason: s.label,
          );
        }
      },
    );

    test('HE/EHT breakpoints follow the brief table for every width', () {
      expect(aciMaskDbr(AciMaskFamily.heEht, 20, 9.75), 0);
      expect(aciMaskDbr(AciMaskFamily.heEht, 20, 10.5), -20);
      expect(aciMaskDbr(AciMaskFamily.heEht, 40, 40), -28);
      expect(aciMaskDbr(AciMaskFamily.heEht, 80, 120), -40);
      expect(aciMaskDbr(AciMaskFamily.heEht, 160, 80.5), -20);
      expect(aciMaskDbr(AciMaskFamily.heEht, 320, 480), -40);
      expect(aciMaskDbr(AciMaskFamily.heEht, 320, 900), -40);
      expect(
        () => aciMaskBreakpoints(AciMaskFamily.ofdm, 40),
        throwsArgumentError,
      );
    });
  });

  group('channel separation', () {
    test('leakage falls as channel separation grows in 2.4 GHz '
        '(15, 20, 25 MHz)', () {
      for (final AciMaskFamily f in AciMaskFamily.values) {
        final List<double> leak = <double>[
          for (final AciSeparation s in <AciSeparation>[
            AciSeparation.ch1and4,
            AciSeparation.ch4and8,
            AciSeparation.ch1and6,
          ])
            computeAci(
              AciConfig(band: WifiBand.band24, family: f, separation: s),
            ).leakageDbm,
        ];
        expect(leak[1], lessThan(leak[0]), reason: f.label);
        expect(leak[2], lessThan(leak[1]), reason: f.label);
      }
    });

    test('leakage falls as separation grows in 5 and 6 GHz at every width, '
        'strictly while the mask still slopes; a 20 MHz mask is flat at -40 '
        'dBr past 30 MHz, so one gap and two gaps tie there', () {
      for (final WifiBand b in <WifiBand>[WifiBand.band5, WifiBand.band6]) {
        for (final int w in b.widthsMHz) {
          final List<double> leak = <double>[
            for (final AciSeparation s in AciSeparation.forBand(b))
              computeAci(
                AciConfig(band: b, neighborWidthMHz: w, separation: s),
              ).leakageDbm,
          ];
          final String why = '${b.label} $w MHz';
          expect(leak[1], lessThan(leak[0]), reason: why);
          if (w == 20) {
            expect(leak[2], closeTo(leak[1], 1e-9), reason: why);
          } else {
            expect(leak[2], lessThan(leak[1]), reason: why);
          }
        }
      }
    });

    test('channel pairs come from the app channel data: 36/40/44/48, 38 to '
        '44, 42 to 52, 114 to 132, 6 GHz 31 to 65', () {
      AciChannelPlan plan(WifiBand b, int w, AciSeparation s) =>
          resolveAciPlan(b, w, s);
      expect(
        plan(WifiBand.band5, 20, AciSeparation.oneGap).receiverChannel,
        44,
      );
      expect(
        plan(WifiBand.band5, 20, AciSeparation.oneGap).neighborChannel,
        36,
      );
      expect(
        plan(WifiBand.band5, 20, AciSeparation.adjacent).receiverChannel,
        40,
      );
      expect(
        plan(WifiBand.band5, 20, AciSeparation.twoGaps).receiverChannel,
        48,
      );
      expect(
        plan(WifiBand.band5, 40, AciSeparation.adjacent).receiverChannel,
        44,
      );
      expect(
        plan(WifiBand.band5, 80, AciSeparation.adjacent).receiverChannel,
        52,
      );
      final AciChannelPlan p160 = plan(
        WifiBand.band5,
        160,
        AciSeparation.adjacent,
      );
      expect(p160.neighborComponents.first, 100);
      expect(p160.receiverChannel, 132);
      final AciChannelPlan p320 = plan(
        WifiBand.band6,
        320,
        AciSeparation.adjacent,
      );
      expect(p320.neighborChannel, 31);
      expect(p320.receiverChannel, 65);
      for (final WifiBand b in <WifiBand>[WifiBand.band5, WifiBand.band6]) {
        for (final int w in b.widthsMHz) {
          for (final AciSeparation s in AciSeparation.forBand(b)) {
            final AciChannelPlan p = plan(b, w, s);
            expect(p.edgeGapMHz, 20.0 * s.gaps!, reason: '${b.label} $w $s');
            expect(isValid20MhzPrimary(b, p.receiverChannel), isTrue);
          }
        }
      }
    });

    test('a wider neighbor keeps lowering leakage until 1.5 x its width from '
        'its center, then goes flat', () {
      // 80 MHz neighbor: flat point at 120 MHz. Receiver centers at 50, 70,
      // 90 and 110 MHz sit on the slope; at 130 and 150 the whole 20 MHz is
      // past 120 and the leakage ties.
      final List<double> slope = <double>[
        for (final double off in <double>[50, 70, 90, 110])
          integratedLeakageDbr(AciMaskFamily.heEht, 80, off),
      ];
      for (int i = 1; i < slope.length; i++) {
        expect(slope[i], lessThan(slope[i - 1]));
      }
      expect(
        integratedLeakageDbr(AciMaskFamily.heEht, 80, 150),
        closeTo(integratedLeakageDbr(AciMaskFamily.heEht, 80, 130), 1e-9),
      );
    });
  });

  group('distance and power', () {
    test('leakage falls with neighbor distance at the log-distance slope', () {
      for (final double n in <double>[2, 3, 3.5]) {
        final double at2 = computeAci(
          AciConfig(neighborDistanceM: 2, pathLossExponent: n),
        ).leakageDbm;
        final double at4 = computeAci(
          AciConfig(neighborDistanceM: 4, pathLossExponent: n),
        ).leakageDbm;
        final double at20 = computeAci(
          AciConfig(neighborDistanceM: 20, pathLossExponent: n),
        ).leakageDbm;
        expect(at2 - at4, closeTo(10 * n * FsplMath.log10(2), 1e-9));
        expect(at2 - at20, closeTo(10 * n, 1e-9));
        // The interference follows the same slope: both terms scale with
        // the neighbor's power.
        final double i2 = computeAci(
          AciConfig(neighborDistanceM: 2, pathLossExponent: n),
        ).effectiveInterferenceDbm;
        final double i4 = computeAci(
          AciConfig(neighborDistanceM: 4, pathLossExponent: n),
        ).effectiveInterferenceDbm;
        expect(i2 - i4, closeTo(10 * n * FsplMath.log10(2), 1e-9));
      }
    });

    test('below 1 m the path is free space: 30 cm is 20 log10(1/0.3) '
        'stronger than 1 m whatever the exponent', () {
      final double at1 = computeAci(
        const AciConfig(neighborDistanceM: 1, pathLossExponent: 4),
      ).neighborDbm;
      final double at03 = computeAci(
        const AciConfig(neighborDistanceM: 0.3, pathLossExponent: 4),
      ).neighborDbm;
      expect(at03 - at1, closeTo(20 * FsplMath.log10(1 / 0.3), 1e-9));
    });

    test('formula (c): interference = neighbor + 10 log10(10^(L/10) + '
        '10^(-S/10)); raising selectivity never lowers SINR, and as it grows '
        'the interference converges to the leakage', () {
      const AciConfig close = AciConfig(neighborDistanceM: 0.3);
      final AciResult r = computeAci(close);
      final double expected =
          r.neighborDbm +
          10 *
              FsplMath.log10(
                math.pow(10, r.leakageDbr / 10).toDouble() +
                    math.pow(10, -r.selectivityDb / 10).toDouble(),
              );
      expect(r.effectiveInterferenceDbm, closeTo(expected, 1e-9));
      expect(r.filteredDbm, closeTo(r.neighborDbm - r.selectivityDb, 1e-9));
      expect(r.sirDb, closeTo(r.wantedDbm - r.effectiveInterferenceDbm, 1e-9));
      double last = double.negativeInfinity;
      for (double sel = 20; sel <= 200; sel += 5) {
        final AciResult x = computeAci(close.withSelectivity(sel));
        expect(x.sinrDb, greaterThanOrEqualTo(last - 1e-12));
        last = x.sinrDb;
      }
      final AciResult ideal = computeAci(close.withSelectivity(200));
      expect(ideal.effectiveInterferenceDbm, closeTo(ideal.leakageDbm, 1e-6));
      // Leakage is in-channel: no selectivity pushes interference below it.
      expect(r.effectiveInterferenceDbm, greaterThan(r.leakageDbm));
    });

    test('selectivity is one value per separation, never per MCS: 35 dB '
        'next channel, 51 dB one gap or more, each set on its own', () {
      expect(
        const AciConfig(separation: AciSeparation.adjacent).selectivityDb,
        35,
      );
      expect(
        const AciConfig(separation: AciSeparation.oneGap).selectivityDb,
        51,
      );
      expect(
        const AciConfig(separation: AciSeparation.twoGaps).selectivityDb,
        51,
      );
      for (final AciSeparation s in AciSeparation.forBand(WifiBand.band24)) {
        expect(
          AciConfig(band: WifiBand.band24, separation: s).selectivityDb,
          35,
        );
      }
      final AciConfig c = const AciConfig(
        separation: AciSeparation.adjacent,
      ).withSelectivity(44);
      expect(c.selectivityAdjacentDb, 44);
      expect(c.selectivityNonAdjacentDb, 51);
      expect(c.copyWith(separation: AciSeparation.oneGap).selectivityDb, 51);
    });

    test('adjacent OFDM 20 MHz leakage is -23.4 dBr and one gap is -39.7 '
        'dBr (Pax, closed-form)', () {
      expect(
        integratedLeakageDbr(AciMaskFamily.ofdm, 20, 20),
        closeTo(-23.4, 0.1),
      );
      expect(
        integratedLeakageDbr(AciMaskFamily.ofdm, 20, 40),
        closeTo(-39.7, 0.1),
      );
      expect(
        integratedLeakageDbr(AciMaskFamily.heEht, 20, 20),
        closeTo(-23.8, 0.1),
      );
    });

    test('the standard reference table: ACR + minimum sensitivity = -66 dBm '
        'at every MCS, and non-adjacent is ACR + 16', () {
      expect(kAciStandardAcrDb, hasLength(RateVsRangeMath.maxMcs + 1));
      for (int m = 0; m <= RateVsRangeMath.maxMcs; m++) {
        expect(
          kAciStandardAcrDb[m] + RateVsRangeMath.sensitivityDbm(m, 20),
          -66,
          reason: 'MCS $m',
        );
      }
      expect(aciStandardNonAdjacentDb(0), 32);
      expect(aciStandardNonAdjacentDb(13), -4);
    });

    test('the highest MCS drops when the neighbor moves close', () {
      final AciResult far = computeAci(const AciConfig(neighborDistanceM: 30));
      final AciResult near = computeAci(
        const AciConfig(neighborDistanceM: 0.5),
      );
      expect(far.mcsWith, far.mcsWithout);
      expect(near.mcsWithout, far.mcsWithout);
      expect(near.mcsWith ?? -1, lessThan(far.mcsWith!));
    });

    test('an MCS is usable only when the one SINR meets its sensitivity '
        'minus the noise floor', () {
      final AciResult r = computeAci(const AciConfig());
      final int m = r.mcsWith!;
      expect(r.sinrDb, greaterThanOrEqualTo(r.requiredSinrDb(m)));
      if (m < RateVsRangeMath.maxMcs) {
        expect(r.sinrDb, lessThan(r.requiredSinrDb(m + 1)));
      }
      expect(r.mcsWithout, RateVsRangeMath.mcsFor(r.wantedDbm, 20));
    });
  });

  group('CCA energy detect', () {
    test('the default threshold is Channel Planner energy detect, -62 dBm', () {
      expect(kAciDefaultCcaDbm, CcaRule.energyDetect.thresholdDbm);
    });

    test('the flag tests the effective interference, not raw leakage: it '
        'trips just above -62 dBm and not just below', () {
      // Interference scales dB for dB with neighbor power.
      final AciResult base = computeAci(
        const AciConfig(neighborDistanceM: 0.3, neighborPowerDbm: 20),
      );
      final double offset = base.effectiveInterferenceDbm - 20;
      AciConfig at(double p, {double? cca}) => AciConfig(
        neighborDistanceM: 0.3,
        neighborPowerDbm: p,
        ccaThresholdDbm: cca ?? kAciDefaultCcaDbm,
      );
      final AciResult over = computeAci(at(-62 - offset + 0.1));
      final AciResult under = computeAci(at(-62 - offset - 0.1));
      expect(over.effectiveInterferenceDbm, closeTo(-61.9, 1e-9));
      expect(over.ccaBusy, isTrue);
      expect(under.ccaBusy, isFalse);
      // Raw leakage would not trip it; a poor filter lifts the interference
      // over the threshold.
      final AciResult poor = computeAci(
        at(-62 - offset - 0.1).copyWith(selectivityNonAdjacentDb: 20),
      );
      expect(poor.leakageDbm, lessThan(-62));
      expect(poor.ccaBusy, isTrue);
      // Its own threshold, not a fixed number.
      expect(computeAci(at(-62 - offset + 0.1, cca: -52)).ccaBusy, isFalse);
    });
  });

  group('the drawing never implies a frequency change', () {
    test('center frequencies are constant across every non-channel change', () {
      for (final WifiBand b in WifiBand.values) {
        for (final AciSeparation s in AciSeparation.forBand(b)) {
          final AciConfig base = AciConfig(band: b, separation: s);
          final AciResult r0 = computeAci(base);
          final List<AciConfig> variants = <AciConfig>[
            base.copyWith(neighborDistanceM: 0.3),
            base.copyWith(neighborDistanceM: 30),
            base.copyWith(neighborPowerDbm: 0),
            base.copyWith(wantedDistanceM: 60),
            base.copyWith(wantedPowerDbm: 5),
            base.copyWith(pathLossExponent: 2),
            base.copyWith(listener: AciListener.client),
            base.copyWith(ccaThresholdDbm: -82),
            base.withSelectivity(20),
            if (b != WifiBand.band6) base.copyWith(family: AciMaskFamily.ofdm),
          ];
          for (final AciConfig v in variants) {
            final AciResult r = computeAci(v);
            expect(r.plan.neighborCenterMHz, r0.plan.neighborCenterMHz);
            expect(r.plan.receiverCenterMHz, r0.plan.receiverCenterMHz);
          }
        }
      }
    });
  });

  test('deterministic: the same inputs give identical outputs', () {
    const AciConfig c = AciConfig(
      band: WifiBand.band6,
      neighborWidthMHz: 160,
      separation: AciSeparation.adjacent,
      neighborDistanceM: 1.7,
    );
    final AciResult a = computeAci(c);
    final AciResult b = computeAci(c);
    expect(a.leakageDbm, b.leakageDbm);
    expect(a.mcsWith, b.mcsWith);
    expect(a.sinrDb, b.sinrDb);
    expect(a.effectiveInterferenceDbm, b.effectiveInterferenceDbm);
  });

  test('the opening question scene: 36 and 44 at 30 cm, client 10 m away, '
      'trips energy detect and loses the link (Pax formula c)', () {
    final AciResult r = computeAci(
      const AciConfig(neighborDistanceM: 0.3, wantedDistanceM: 10),
    );
    expect(r.plan.neighborChannel, 36);
    expect(r.plan.receiverChannel, 44);
    expect(r.wantedDbm, closeTo(-57.3, 0.05));
    expect(r.neighborDbm, closeTo(-16.8, 0.05));
    expect(r.leakageDbm, closeTo(-56.7, 0.05));
    expect(r.filteredDbm, closeTo(-67.8, 0.05));
    expect(r.effectiveInterferenceDbm, closeTo(-56.4, 0.05));
    expect(r.sinrDb, closeTo(-0.84, 0.01));
    expect(r.ccaBusy, isTrue);
    expect(r.mcsWithout, 8);
    expect(r.mcsWith, isNull);
    // Pax's worked example uses the OFDM mask: leakage -56.5, S = 51 gives
    // -56.2 dBm and SINR -1.0 dB, no MCS.
    final AciResult ofdm = computeAci(
      const AciConfig(
        family: AciMaskFamily.ofdm,
        neighborDistanceM: 0.3,
        wantedDistanceM: 10,
      ),
    );
    expect(ofdm.leakageDbm, closeTo(-56.5, 0.05));
    expect(ofdm.effectiveInterferenceDbm, closeTo(-56.2, 0.05));
    expect(ofdm.sinrDb, closeTo(-1.0, 0.1));
    expect(ofdm.mcsWith, isNull);
  });
}
