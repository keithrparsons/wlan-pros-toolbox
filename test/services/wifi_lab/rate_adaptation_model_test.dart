// Pins the Rate Adaptation model (spec 23, "Done means").
//
// Numbers typed here come from the wave-3 brief section 8 (EWMA 75% history,
// ignore under 10%, cap at 90%, retry chain order, CW series) and the
// wave-5 brief section 9 (ACK timeout 45 to 50 us), so a slip in
// rate_adaptation_model.dart fails here instead of passing against itself.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/rate_adaptation_model.dart';

List<double?> _untried() => List<double?>.filled(RaLink.mcsCount, null);

void main() {
  group('EWMA', () {
    test('75% weight on history updates exactly', () {
      expect(RateAdaptationMath.defaultEwmaHistory, 0.75);
      // 0.75 x 0.8 + 0.25 x 0.4 = 0.7
      expect(RateAdaptationMath.ewma(0.8, 0.4, 0.75), closeTo(0.7, 1e-12));
      // 0.75 x 1.0 + 0.25 x 0.0 = 0.75, then 0.75 x 0.75 + 0 = 0.5625
      final double a = RateAdaptationMath.ewma(1.0, 0.0, 0.75);
      expect(a, 0.75);
      expect(RateAdaptationMath.ewma(a, 0.0, 0.75), 0.5625);
    });

    test('a rate with no history takes its first sample as is', () {
      expect(RateAdaptationMath.ewma(null, 0.3, 0.75), 0.3);
    });

    test('the engine applies it once per 50 ms interval', () {
      // Always 100% success at MCS 0: the only rate tried with sampling off.
      final RateAdaptationEngine e = RateAdaptationEngine(
        settings: const RaSettings(samplingShare: 0),
        snrOverride: (double t) => 60,
      );
      expect(RateAdaptationMath.statsIntervalUs, 50000);
      e.advanceBy(49000);
      expect(e.history, isEmpty);
      expect(e.stats[0].ewma, isNull);
      e.advanceBy(3000);
      e.stepFrame();
      expect(e.history, hasLength(1));
      expect(e.history.single.timeUs, 50000);
      expect(e.stats[0].ewma, 1.0);
    });
  });

  group('throughput ranking', () {
    test('rates under 10% success are excluded', () {
      expect(RateAdaptationMath.throughputEstimateMbps(0.09, 11), 0);
      expect(
        RateAdaptationMath.throughputEstimateMbps(0.10, 11),
        greaterThan(0),
      );
      final List<double?> p = _untried()
        ..[0] = 0.95
        ..[11] = 0.09; // would win on raw rate x P: 0.09 x 143 > 0.9 x 8.6
      final RaRanking r = RateAdaptationMath.rank(p);
      expect(r.bestThroughput, 0);
      expect(r.secondThroughput, isNot(11));
    });

    test('probability is capped at 90% in the estimate', () {
      final double at90 = RateAdaptationMath.throughputEstimateMbps(0.9, 5);
      expect(RateAdaptationMath.throughputEstimateMbps(1.0, 5), at90);
      expect(
        at90,
        closeTo(
          0.9 * RaLink.payloadBits / RateAdaptationMath.oneAttemptUs(5),
          1e-9,
        ),
      );
    });
  });

  group('retry chain', () {
    const RaRanking r = RaRanking(
      bestThroughput: 7,
      secondThroughput: 6,
      bestProbability: 4,
    );

    test('normal frame: best throughput, second best, best probability, '
        'lowest', () {
      expect(RateAdaptationMath.retryChain(r), <int>[7, 6, 4, 0]);
    });

    test('the ranking picks those three from the statistics', () {
      final List<double?> p = _untried()
        ..[2] = 1.0
        ..[4] = 0.99
        ..[6] = 0.85
        ..[7] = 0.9;
      final RaRanking got = RateAdaptationMath.rank(p);
      // Estimates (Mbps): MCS 7 31.1, MCS 6 28.3, MCS 4 24.4 (0.99 capped
      // to 0.9), MCS 2 15.7.
      expect(got.bestThroughput, 7);
      expect(got.secondThroughput, 6);
      expect(got.bestProbability, 2);
      expect(RateAdaptationMath.retryChain(got), <int>[7, 6, 2, 0]);
    });

    test('a faster sample rate goes first, a slower one second', () {
      expect(RateAdaptationMath.retryChain(r, sampleMcs: 10), <int>[
        10,
        7,
        4,
        0,
      ]);
      expect(RateAdaptationMath.retryChain(r, sampleMcs: 3), <int>[7, 3, 4, 0]);
    });

    test('attempts split over the chain: 7 = 2,2,2,1 and 4 = 1,1,1,1', () {
      expect(RaRetryLimit.short7.attempts, 7);
      expect(RaRetryLimit.long4.attempts, 4);
      expect(RateAdaptationMath.attemptsPerStage(7), <int>[2, 2, 2, 1]);
      expect(RateAdaptationMath.attemptsPerStage(4), <int>[1, 1, 1, 1]);
    });

    test('the engine walks the chain in order when every attempt fails', () {
      final RateAdaptationEngine e = RateAdaptationEngine(
        settings: const RaSettings(samplingShare: 0),
        snrOverride: (double t) => -50,
      );
      final RaFrame f = e.stepFrame();
      expect(f.delivered, isFalse);
      expect(f.attempts, hasLength(7));
      final List<int> c = f.chain;
      expect(f.attempts.map((RaAttempt a) => a.mcs).toList(), <int>[
        c[0],
        c[0],
        c[1],
        c[1],
        c[2],
        c[2],
        c[3],
      ]);
    });

    test('with the chain off every attempt stays at the first rate', () {
      final RateAdaptationEngine e = RateAdaptationEngine(
        settings: const RaSettings(
          samplingShare: 0,
          retryChain: false,
          retryLimit: RaRetryLimit.long4,
        ),
        snrOverride: (double t) => -50,
      );
      final RaFrame f = e.stepFrame();
      expect(f.attempts, hasLength(4));
      expect(f.attempts.map((RaAttempt a) => a.mcs).toSet(), <int>{f.chain[0]});
    });
  });

  group('what a retry costs', () {
    test('CW doubles per retry up to CWmax (best effort 15 to 1023)', () {
      expect(
        <int>[
          for (int k = 0; k < 9; k++) RateAdaptationMath.contentionWindow(k),
        ],
        <int>[15, 31, 63, 127, 255, 511, 1023, 1023, 1023],
      );
    });

    test('the brief worked example: mean backoff 67.5, 139.5, 283.5 us', () {
      expect(RaLink.aifsUs, 43);
      expect(RateAdaptationMath.meanBackoffUs(15), 67.5);
      expect(RateAdaptationMath.meanBackoffUs(31), 139.5);
      expect(RateAdaptationMath.meanBackoffUs(63), 283.5);
    });

    test('a retry costs more mean airtime than the first attempt', () {
      for (int m = 0; m <= RaLink.maxMcs; m++) {
        final double first = RateAdaptationMath.meanAttemptUs(
          mcs: m,
          attemptIndex: 0,
          pSuccess: 0.5,
          ackTimeoutUs: 45,
        );
        final double retrySame = RateAdaptationMath.meanAttemptUs(
          mcs: m,
          attemptIndex: 1,
          pSuccess: 0.5,
          ackTimeoutUs: 45,
        );
        expect(retrySame, greaterThan(first), reason: 'MCS $m');
        if (m > 0) {
          final double retryLower = RateAdaptationMath.meanAttemptUs(
            mcs: m - 1,
            attemptIndex: 1,
            pSuccess: 0.5,
            ackTimeoutUs: 45,
          );
          expect(retryLower, greaterThan(first), reason: 'MCS $m to ${m - 1}');
        }
      }
    });

    test('an attempt is AIFS + mean backoff + TXTIME + ACK or ACK timeout', () {
      final RaAttemptCost ok = RateAdaptationMath.attemptCost(
        mcs: 7,
        attemptIndex: 0,
        delivered: true,
        ackTimeoutUs: 45,
      );
      expect(ok.totalUs, 43 + 67.5 + RaLink.txTimeUs(7) + 16 + RaLink.ackUs);
      final RaAttemptCost lost = RateAdaptationMath.attemptCost(
        mcs: 7,
        attemptIndex: 2,
        delivered: false,
        ackTimeoutUs: 50,
      );
      expect(lost.totalUs, 43 + 283.5 + RaLink.txTimeUs(7) + 50);
    });

    test('ACK timeout is offered as the 45 to 50 us range', () {
      expect(RateAdaptationMath.ackTimeoutMinUs, 45);
      expect(RateAdaptationMath.ackTimeoutMaxUs, 50);
      // SIFS + slot + 20 us at 5 GHz.
      expect(RaLink.sifsUs + RaLink.slotUs + 20, 45);
    });
  });

  group('teaching success curve', () {
    test('90% at the SNR each MCS needs (sensitivity minus noise floor)', () {
      expect(RateAdaptationMath.noiseFloorDbm(), closeTo(-93.99, 0.01));
      expect(RateAdaptationMath.requiredSnrDb(0), closeTo(11.99, 0.01));
      expect(RateAdaptationMath.requiredSnrDb(11), closeTo(41.99, 0.01));
      for (int m = 0; m <= RaLink.maxMcs; m++) {
        final double need = RateAdaptationMath.requiredSnrDb(m);
        expect(
          RateAdaptationMath.successProbability(need, m),
          closeTo(0.9, 1e-9),
        );
        expect(
          RateAdaptationMath.successProbability(
            need - 2 * RateAdaptationMath.curveHalfOffsetDb,
            m,
          ),
          closeTo(0.1, 1e-9),
        );
      }
    });

    test('rates come from the airtime service: MCS 11 is 143.4 Mbps', () {
      expect(RaLink.phyRateMbps(0), closeTo(8.6, 0.05));
      expect(RaLink.phyRateMbps(11), closeTo(143.4, 0.05));
    });
  });

  group('rate control over a run (seeded)', () {
    // Spec 23: "the chosen rate never rises by more than sampling allows".
    // As built from the outline, a rise needs fresh evidence for the higher
    // rate from the interval just closed: a sample frame, or a retry at the
    // second-best rate in the chain. Most rises are sampling's; a few are the
    // chain's. None may come from stale statistics.
    test('with SNR falling steadily, the chosen rate rises only on fresh '
        'evidence from sampling or the retry chain', () {
      for (final int seed in <int>[1, 2, 3, 4, 5]) {
        // 50 dB falling to 5 dB over 10 s.
        final RateAdaptationEngine e = RateAdaptationEngine(
          seed: seed,
          snrOverride: (double t) => 50 - 4.5 * t / 1e6,
        );
        e.advanceBy(10e6);
        final List<RaUpdate> h = e.history;
        int rises = 0;
        int bySampling = 0;
        for (int i = 1; i < h.length; i++) {
          final int before = h[i - 1].ranking.bestThroughput;
          final int after = h[i].ranking.bestThroughput;
          if (after > before) {
            rises++;
            if (h[i].sampled.contains(after)) bySampling++;
            expect(
              h[i].attempted,
              contains(after),
              reason:
                  'seed $seed at ${h[i].timeUs / 1e6} s: rose $before to '
                  '$after with no attempt at $after in that interval',
            );
          }
        }
        expect(h.last.ranking.bestThroughput, lessThanOrEqualTo(1));
        expect(rises, lessThan(h.length ~/ 10));
        expect(bySampling, greaterThan(rises ~/ 2), reason: 'seed $seed');
      }
    });

    test('with SNR high and steady the rate converges to MCS 11', () {
      for (final int seed in <int>[1, 2, 3]) {
        final RateAdaptationEngine e = RateAdaptationEngine(
          seed: seed,
          settings: const RaSettings(path: RaPath.steady),
        );
        e.advanceBy(2e6);
        expect(e.ranking.bestThroughput, RaLink.maxMcs, reason: 'seed $seed');
        // And it stays there.
        e.advanceBy(3e6);
        expect(
          e.history
              .where((RaUpdate u) => u.timeUs > 2e6)
              .every((RaUpdate u) => u.ranking.bestThroughput == 11),
          isTrue,
        );
      }
    });

    test('without sampling a fresh link never finds the higher rates', () {
      final RateAdaptationEngine e = RateAdaptationEngine(
        settings: const RaSettings(path: RaPath.steady, samplingShare: 0),
      );
      e.advanceBy(2e6);
      expect(e.ranking.bestThroughput, 0);
    });

    test('same seed, same run', () {
      final RateAdaptationEngine a = RateAdaptationEngine(seed: 9);
      final RateAdaptationEngine b = RateAdaptationEngine(seed: 9);
      a.advanceBy(3e6);
      b.advanceBy(3e6);
      expect(a.totalAttempts, b.totalAttempts);
      expect(a.ranking, b.ranking);
    });

    test('walk away and back: the rate steps down, then climbs again', () {
      final RateAdaptationEngine e = RateAdaptationEngine();
      e.advanceBy(1e6);
      final int near = e.ranking.bestThroughput;
      e.advanceBy(9e6); // at 10 s, 60 m away
      final int far = e.ranking.bestThroughput;
      e.advanceBy(9.8e6); // back near the AP
      final int back = e.ranking.bestThroughput;
      expect(near, greaterThanOrEqualTo(9));
      expect(far, lessThanOrEqualTo(2));
      expect(back, greaterThanOrEqualTo(9));
    });

    test('window readouts count retries and their airtime', () {
      final RateAdaptationEngine e = RateAdaptationEngine(
        settings: const RaSettings(path: RaPath.fading),
      );
      e.advanceBy(2e6);
      final RaWindowStats w = e.window;
      expect(w.frames, greaterThan(0));
      expect(w.retriesPerFrame, greaterThan(0));
      expect(w.retryAirtimeShare, inExclusiveRange(0, 1));
      expect(w.deliveredMbps, greaterThan(0));
    });
  });

  group('help entry example', () {
    test('the numbers the help example quotes', () {
      expect(RaPath.steady.snrDb(0, 0), closeTo(48.7, 0.05));
      expect(RaLink.phyRateMbps(11), closeTo(143.4, 0.05));
      expect(RateAdaptationMath.oneAttemptUs(11), closeTo(292.9, 1e-9));
      expect(
        RateAdaptationMath.throughputEstimateMbps(1.0, 11),
        closeTo(36.9, 0.05),
      );
      expect(RateAdaptationMath.oneAttemptUs(7), closeTo(347.3, 1e-9));
      expect(
        RateAdaptationMath.attemptCost(
          mcs: 7,
          attemptIndex: 0,
          delivered: false,
          ackTimeoutUs: 45,
        ).totalUs,
        closeTo(348.3, 1e-9),
      );
      expect(
        RateAdaptationMath.attemptCost(
          mcs: 6,
          attemptIndex: 1,
          delivered: true,
          ackTimeoutUs: 45,
        ).totalUs,
        closeTo(432.9, 1e-9),
      );
    });
  });
}
