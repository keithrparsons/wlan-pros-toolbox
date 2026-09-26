// Pins the Adjacent Channels and AP Stacking model (spec 29, "Done means").
//
// Every figure is either from the wave-3 research brief's mask table or
// arithmetic on it: channels 1 and 6 at 25 MHz give -34 dBr at the victim's
// center (-28 at 20 MHz, -40 at 30 MHz, linear in dB), and the integrated
// leakage must lie between the mask at the victim's near and far edges.

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

    test('raising rejection raises SIR by the same dB, and SINR by the same '
        'dB when interference dominates the noise', () {
      const AciConfig close = AciConfig(
        neighborDistanceM: 0.3,
        neighborPowerDbm: 30,
      );
      for (final AciRateGroup g in AciRateGroup.values) {
        final AciGroupReading a = computeAci(close).reading(g);
        final AciGroupReading b = computeAci(
          close.withRejection(g, close.rejectionFor(g) + 7),
        ).reading(g);
        expect(b.sirDb - a.sirDb, closeTo(7, 1e-9), reason: g.label);
        // Even after the raise, interference is 20+ dB over the noise.
        expect(
          b.effectiveInterferenceDbm - computeAci(close).receiverNoiseDbm,
          greaterThan(20),
        );
        expect(b.sinrDb - a.sinrDb, closeTo(7, 0.05), reason: g.label);
      }
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

    test('an MCS is usable only when its SINR meets sensitivity minus the '
        'noise floor', () {
      final AciResult r = computeAci(const AciConfig());
      final int m = r.mcsWith!;
      final double need =
          RateVsRangeMath.sensitivityDbm(m, 20) - r.receiverNoiseDbm;
      expect(r.reading(AciRateGroup.of(m)).sinrDb, greaterThanOrEqualTo(need));
      if (m < RateVsRangeMath.maxMcs) {
        final double next =
            RateVsRangeMath.sensitivityDbm(m + 1, 20) - r.receiverNoiseDbm;
        expect(r.reading(AciRateGroup.of(m + 1)).sinrDb, lessThan(next));
      }
      expect(r.mcsWithout, RateVsRangeMath.mcsFor(r.wantedDbm, 20));
    });
  });

  group('CCA energy detect', () {
    test('the default threshold is Channel Planner energy detect, -62 dBm', () {
      expect(kAciDefaultCcaDbm, CcaRule.energyDetect.thresholdDbm);
    });

    test(
      'the flag trips when the leakage exceeds -62 dBm and not below it',
      () {
        // Find the neighbor power that puts the leakage just either side.
        final AciResult base = computeAci(
          const AciConfig(neighborDistanceM: 0.3, neighborPowerDbm: 20),
        );
        final double offset = base.leakageDbm - 20;
        final AciResult over = computeAci(
          AciConfig(
            neighborDistanceM: 0.3,
            neighborPowerDbm: -62 - offset + 0.1,
          ),
        );
        final AciResult under = computeAci(
          AciConfig(
            neighborDistanceM: 0.3,
            neighborPowerDbm: -62 - offset - 0.1,
          ),
        );
        expect(over.leakageDbm, closeTo(-61.9, 1e-9));
        expect(over.ccaBusy, isTrue);
        expect(under.ccaBusy, isFalse);
        // Its own threshold, not a fixed number.
        expect(
          computeAci(
            AciConfig(
              neighborDistanceM: 0.3,
              neighborPowerDbm: -62 - offset + 0.1,
              ccaThresholdDbm: -52,
            ),
          ).ccaBusy,
          isFalse,
        );
      },
    );
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
            base.withRejection(AciRateGroup.top, 30),
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
    for (final AciRateGroup g in AciRateGroup.values) {
      expect(a.reading(g).sinrDb, b.reading(g).sinrDb);
    }
  });

  test('the opening question scene: 36 and 44 at 30 cm trips energy detect '
      'and loses the link', () {
    final AciResult r = computeAci(
      const AciConfig(neighborDistanceM: 0.3, wantedDistanceM: 15),
    );
    expect(r.plan.neighborChannel, 36);
    expect(r.plan.receiverChannel, 44);
    expect(r.leakageDbm, closeTo(-56.7, 0.05));
    expect(r.ccaBusy, isTrue);
    expect(r.mcsWithout, 7);
    expect(r.mcsWith, isNull);
  });
}
