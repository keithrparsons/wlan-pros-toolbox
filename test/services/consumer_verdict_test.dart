// ConsumerVerdictMapper — pure translator unit tests.
//
// One test per mapping row in the build spec's "Verdict translation" table,
// INCLUDING the D1/D2 split (wifiUnknown with vs without a measured internet
// figure). No Flutter, no network, no radio — an engine result in, a consumer
// verdict out. Each test asserts the exact headline + body copy is carried
// verbatim from the spec, so a future copy edit is a single deliberate change.
//
// REVISION 2 (2026-06-07, Keith family-dinner feedback): the two axis chips are
// now an ABSOLUTE 3-tier scale — Strong / Moderate / Weak — bucketed from each
// axis's data rate in Mbps via AxisStatusThresholds (same thresholds both axes:
// >250 Strong, 100-250 inclusive Moderate, <100 Weak, unmeasured Unknown). The
// chips therefore depend on the engine's usableWifiMbps / internetMbps, NOT
// on the comparative verdict. These tests assert (a) the threshold boundaries
// directly, and (b) that each verdict row still carries the right outcome/copy
// AND surfaces the correct rate-driven tiers.
//
// Three halves:
//   1. Threshold boundaries — AxisStatusThresholds.tierFor at every cut point.
//   2. Direct mapping rows — a constructed WifiVsInternetResult per verdict, so
//      each branch is asserted in isolation regardless of engine internals.
//   3. End-to-end — the SAME shared WifiVsInternetEngine the pro tool drives,
//      fed plain numbers, to prove the consumer layer maps the engine's REAL
//      output (not just hand-built results).

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/consumer_verdict.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_vs_internet.dart';

/// Builds a WifiVsInternetResult for a given verdict with the fields the mapper
/// reads (verdict + the two rate figures that now drive the chips). Defaults put
/// both axes mid-band (Moderate) so a test that only cares about the outcome/copy
/// does not have to spell out rates; tests that assert tiers pass them in.
WifiVsInternetResult result(
  WifiVsInternetVerdict verdict, {
  double? internetMbps,
  double? usableWifiMbps = 150,
}) {
  return WifiVsInternetResult(
    verdict: verdict,
    headline: 'engine headline',
    explanation: 'engine explanation',
    snrContext: '',
    rateBasis: WifiRateBasis.averaged,
    usableWifiMbps: usableWifiMbps,
    internetMbps: internetMbps,
    linkRateMbps: usableWifiMbps == null ? null : usableWifiMbps / 0.55,
    ratio: 0.5,
  );
}

void main() {
  group('AxisStatusThresholds.tierFor — absolute 3-tier boundaries', () {
    // The exact cut points Keith specified: >250 Strong, 100-250 inclusive
    // Moderate, <100 Weak, null/unmeasured Unknown (GL-005).
    test('251 Mbps → Strong (just above the 250 ceiling)', () {
      expect(AxisStatusThresholds.tierFor(251), AxisStatus.strong);
    });

    test('250 Mbps → Moderate (top of the band is inclusive)', () {
      expect(AxisStatusThresholds.tierFor(250), AxisStatus.moderate);
    });

    test('100 Mbps → Moderate (bottom of the band is inclusive)', () {
      expect(AxisStatusThresholds.tierFor(100), AxisStatus.moderate);
    });

    test('99 Mbps → Weak (just below the 100 floor)', () {
      expect(AxisStatusThresholds.tierFor(99), AxisStatus.weak);
    });

    test('null → Unknown (unmeasured, never forced to a tier)', () {
      expect(AxisStatusThresholds.tierFor(null), AxisStatus.unknown);
    });

    test('0 and negative → Unknown (≤0 treated as absent, not a real Weak)', () {
      expect(AxisStatusThresholds.tierFor(0), AxisStatus.unknown);
      expect(AxisStatusThresholds.tierFor(-5), AxisStatus.unknown);
    });

    test('representative values land in the right tiers', () {
      expect(AxisStatusThresholds.tierFor(800), AxisStatus.strong);
      expect(AxisStatusThresholds.tierFor(300), AxisStatus.strong);
      expect(AxisStatusThresholds.tierFor(175), AxisStatus.moderate);
      expect(AxisStatusThresholds.tierFor(40), AxisStatus.weak);
      expect(AxisStatusThresholds.tierFor(1), AxisStatus.weak);
    });

    test('the named threshold constants match the spec', () {
      expect(AxisStatusThresholds.strongAboveMbps, 250);
      expect(AxisStatusThresholds.moderateAtOrAboveMbps, 100);
    });
  });

  group('axis chips are rate-driven, same thresholds on both axes', () {
    // Both chips derive from the absolute rates regardless of the verdict; prove
    // every tier combination flows through map() onto the right chip.
    test('high Wi-Fi rate, high internet rate → both Strong', () {
      final v = ConsumerVerdictMapper.map(
        result(
          WifiVsInternetVerdict.bothHealthy,
          usableWifiMbps: 600,
          internetMbps: 500,
        ),
      );
      expect(v.wifiStatus, AxisStatus.strong);
      expect(v.internetStatus, AxisStatus.strong);
    });

    test('mid Wi-Fi rate, low internet rate → Moderate / Weak', () {
      final v = ConsumerVerdictMapper.map(
        result(
          WifiVsInternetVerdict.upstream,
          usableWifiMbps: 150,
          internetMbps: 40,
        ),
      );
      expect(v.wifiStatus, AxisStatus.moderate);
      expect(v.internetStatus, AxisStatus.weak);
    });

    test('low Wi-Fi rate, mid internet rate → Weak / Moderate', () {
      final v = ConsumerVerdictMapper.map(
        result(
          WifiVsInternetVerdict.wifiLimiter,
          usableWifiMbps: 60,
          internetMbps: 180,
        ),
      );
      expect(v.wifiStatus, AxisStatus.weak);
      expect(v.internetStatus, AxisStatus.moderate);
    });

    test('250 on both → both Moderate (inclusive top boundary on each axis)', () {
      final v = ConsumerVerdictMapper.map(
        result(
          WifiVsInternetVerdict.bothContributing,
          usableWifiMbps: 250,
          internetMbps: 250,
        ),
      );
      expect(v.wifiStatus, AxisStatus.moderate);
      expect(v.internetStatus, AxisStatus.moderate);
    });
  });

  group('verdict translation — one row per mapping', () {
    test('wifiLimiter → A (Wi-Fi): outcome + copy, tiers from rates', () {
      // Wi-Fi the limiter: low usable Wi-Fi (Weak), faster internet (Moderate).
      final v = ConsumerVerdictMapper.map(
        result(
          WifiVsInternetVerdict.wifiLimiter,
          usableWifiMbps: 60,
          internetMbps: 180,
        ),
      );
      expect(v.outcome, ConsumerOutcome.wifi);
      expect(v.wifiStatus, AxisStatus.weak);
      expect(v.internetStatus, AxisStatus.moderate);
      expect(v.headline, 'Looks like your Wi-Fi');
      expect(
        v.body,
        'Your internet can go faster than your Wi-Fi is carrying right now. '
        'The slow part is between your device and the router.',
      );
      expect(v.selfHelp, SelfHelpTopic.wifi);
    });

    test('bothContributing → A (Wi-Fi lead): outcome + copy', () {
      final v = ConsumerVerdictMapper.map(
        result(
          WifiVsInternetVerdict.bothContributing,
          usableWifiMbps: 80,
          internetMbps: 40,
        ),
      );
      expect(v.outcome, ConsumerOutcome.wifiLead);
      expect(v.wifiStatus, AxisStatus.weak);
      expect(v.internetStatus, AxisStatus.weak);
      expect(v.headline, 'Mostly your Wi-Fi');
      expect(
        v.body,
        'Both your Wi-Fi and your internet are a little slow. Start with the '
        "Wi-Fi fixes below, they're the easiest.",
      );
      expect(v.selfHelp, SelfHelpTopic.wifi);
    });

    test('upstream → B (Internet): outcome + copy, tiers from rates', () {
      // Internet the limiter: ample usable Wi-Fi (Strong), slow internet (Weak).
      final v = ConsumerVerdictMapper.map(
        result(
          WifiVsInternetVerdict.upstream,
          usableWifiMbps: 400,
          internetMbps: 20,
        ),
      );
      expect(v.outcome, ConsumerOutcome.internet);
      expect(v.wifiStatus, AxisStatus.strong);
      expect(v.internetStatus, AxisStatus.weak);
      expect(v.headline, 'Looks like your Internet');
      expect(
        v.body,
        'Your Wi-Fi has room to spare, but the internet coming into your home '
        'is the slow part.',
      );
      expect(v.selfHelp, SelfHelpTopic.internet);
    });

    test('bothHealthy → C (Both fine): outcome + copy, both Strong', () {
      final v = ConsumerVerdictMapper.map(
        result(
          WifiVsInternetVerdict.bothHealthy,
          usableWifiMbps: 500,
          internetMbps: 300,
        ),
      );
      expect(v.outcome, ConsumerOutcome.bothFine);
      expect(v.wifiStatus, AxisStatus.strong);
      expect(v.internetStatus, AxisStatus.strong);
      expect(v.headline, 'Both look fine');
      expect(
        v.body,
        'Your Wi-Fi and internet are both working well. If something still '
        "feels slow, it's probably the website or app you're using, not your "
        'connection.',
      );
      expect(v.selfHelp, SelfHelpTopic.differentApp);
    });

    test(
      'wifiUnknown WITH internet measured → D1: '
      'Wi-Fi Couldn’t check, Internet tier from its rate',
      () {
        final v = ConsumerVerdictMapper.map(
          result(
            WifiVsInternetVerdict.wifiUnknown,
            usableWifiMbps: null,
            internetMbps: 180,
          ),
          internetHealthy: true,
        );
        expect(v.outcome, ConsumerOutcome.couldntCheckWifi);
        // Wi-Fi rate is null on this path → honest Unknown chip (GL-005).
        expect(v.wifiStatus, AxisStatus.unknown);
        // Internet chip is the absolute tier of the measured internet rate.
        expect(v.internetStatus, AxisStatus.moderate);
        expect(v.headline, 'Couldn’t check everything');
        expect(v.body, contains('[X] Mbps'));
        expect(v.body, contains('[fine/slow]'));
        expect(v.selfHelp, SelfHelpTopic.reconnect);
      },
    );

    test('D1 internet chip is Weak when the measured internet rate is low', () {
      final v = ConsumerVerdictMapper.map(
        result(
          WifiVsInternetVerdict.wifiUnknown,
          usableWifiMbps: null,
          internetMbps: 12,
        ),
      );
      expect(v.outcome, ConsumerOutcome.couldntCheckWifi);
      expect(v.wifiStatus, AxisStatus.unknown);
      expect(v.internetStatus, AxisStatus.weak);
    });

    test('D1 internet chip is Strong when the measured internet rate is high', () {
      final v = ConsumerVerdictMapper.map(
        result(
          WifiVsInternetVerdict.wifiUnknown,
          usableWifiMbps: null,
          internetMbps: 320,
        ),
      );
      expect(v.internetStatus, AxisStatus.strong);
    });

    test(
      'wifiUnknown WITHOUT internet measured → D2: both Couldn’t check',
      () {
        final v = ConsumerVerdictMapper.map(
          result(
            WifiVsInternetVerdict.wifiUnknown,
            usableWifiMbps: null,
            internetMbps: null,
          ),
          internetHealthy: true,
        );
        expect(v.outcome, ConsumerOutcome.couldntComplete);
        expect(v.wifiStatus, AxisStatus.unknown);
        expect(v.internetStatus, AxisStatus.unknown);
        expect(v.headline, 'Couldn’t complete the check');
        expect(v.body, "Make sure you're connected to Wi-Fi and try again.");
        expect(v.selfHelp, SelfHelpTopic.reconnect);
      },
    );

    test(
      'onlineUnmeasured → E: leads with "You are online", NOT "make sure you '
      'are on Wi-Fi"',
      () {
        // The speed test stalled (no internet rate) but reachability is strong;
        // macOS Tx-only keeps a usable Wi-Fi figure, internet stays unmeasured.
        final v = ConsumerVerdictMapper.map(
          result(
            WifiVsInternetVerdict.onlineUnmeasured,
            usableWifiMbps: 300,
            internetMbps: null,
          ),
        );
        expect(v.outcome, ConsumerOutcome.online);
        expect(v.headline, 'You are online');
        expect(v.body, contains('reachable'));
        expect(v.body, contains('Try again in a moment'));
        // No measured internet rate — but the internet is DEMONSTRABLY REACHABLE
        // (this verdict is only emitted when DNS, the public IP and the cloud-app
        // probe all succeeded). "Couldn't check" would claim a failed read about a
        // read that SUCCEEDED, and it sat one line above "Your internet is
        // reachable" on Keith's phone (2026-07-14). Name the thing we actually do
        // not know: the speed. See [AxisStatus.reachableUnmeasured].
        expect(v.internetStatus, AxisStatus.reachableUnmeasured);
        expect(v.internetStatus, isNot(AxisStatus.unknown));
        // The body must NOT scold the user to get on Wi-Fi.
        expect(v.body, isNot(contains('Make sure')));
      },
    );
  });

  group('D1 body substitution (bodyForCouldntCheckWifi)', () {
    test('substitutes the rounded figure and "fine" when healthy', () {
      final body = ConsumerVerdictMapper.bodyForCouldntCheckWifi(
        internetMbps: 83.6,
        healthy: true,
      );
      expect(
        body,
        'Your internet measured about 84 Mbps, which looks fine. We couldn’t '
        'read your Wi-Fi details on this device.',
      );
    });

    test('substitutes "slow" when not healthy', () {
      final body = ConsumerVerdictMapper.bodyForCouldntCheckWifi(
        internetMbps: 12.2,
        healthy: false,
      );
      expect(body, contains('about 12 Mbps'));
      expect(body, contains('looks slow'));
    });

    test('falls back to the non-substituted form when figure is null', () {
      final body = ConsumerVerdictMapper.bodyForCouldntCheckWifi(
        internetMbps: null,
        healthy: true,
      );
      expect(body, isNot(contains('[X]')));
      expect(body, contains('couldn’t read your Wi-Fi details'));
    });
  });

  group('end-to-end — the real shared engine drives the consumer layer', () {
    // Reuses the SAME WifiVsInternetEngine.evaluate the pro tool drives, so the
    // consumer mapping is proven against the engine's real output — including
    // the rate-driven chip tiers off the engine's own usable/internet figures.
    ConsumerVerdict mapFromEngine({
      double? tx,
      double? rx,
      bool rxAvailable = true,
      double? down,
      double? up,
      InternetHealth health = InternetHealth.marginal,
    }) {
      final engine = WifiVsInternetEngine.evaluate(
        txRateMbps: tx,
        rxRateMbps: rx,
        rxRateAvailable: rxAvailable,
        internetDownMbps: down,
        internetUpMbps: up,
        internetHealth: health,
      );
      return ConsumerVerdictMapper.map(engine);
    }

    test('low link vs faster internet → A (Wi-Fi)', () {
      // usable = 0.55 × avg(200,200) = 110 (Moderate); internet download 250
      // (Moderate) → ratio ≈ 2.3 → wifiLimiter.
      final v = mapFromEngine(tx: 200, rx: 200, down: 250, up: 150);
      expect(v.outcome, ConsumerOutcome.wifi);
      expect(v.wifiStatus, AxisStatus.moderate);
      expect(v.internetStatus, AxisStatus.moderate);
    });

    test('link headroom, slow internet → B (Internet), Wi-Fi Strong', () {
      // usable = 0.55 × avg(1000,1000) = 550 (Strong); internet download 25 (Weak).
      final v = mapFromEngine(tx: 1000, rx: 1000, down: 25, up: 15);
      expect(v.outcome, ConsumerOutcome.internet);
      expect(v.wifiStatus, AxisStatus.strong);
      expect(v.internetStatus, AxisStatus.weak);
    });

    test('mid band → A (Wi-Fi lead)', () {
      // usable = 0.55 × avg(200,200) = 110 (Moderate); internet download 60 (Weak).
      final v = mapFromEngine(tx: 200, rx: 200, down: 60, up: 50);
      expect(v.outcome, ConsumerOutcome.wifiLead);
      expect(v.wifiStatus, AxisStatus.moderate);
      expect(v.internetStatus, AxisStatus.weak);
    });

    test('good internet grade-gate → C (Both fine), tiers track the rates', () {
      // usable = 0.55 × avg(400,400) = 220 (Moderate); internet download 300
      // (Strong). Tiers track the absolute rates even on the bothHealthy row.
      final v = mapFromEngine(
        tx: 400,
        rx: 400,
        down: 300,
        up: 150,
        health: InternetHealth.good,
      );
      expect(v.outcome, ConsumerOutcome.bothFine);
      expect(v.wifiStatus, AxisStatus.moderate);
      expect(v.internetStatus, AxisStatus.strong);
    });

    test('no link rate but internet measured → D1, Wi-Fi Unknown', () {
      // No Tx/Rx → basis none → wifiUnknown; internet download 80 (Weak).
      final v = mapFromEngine(tx: null, rx: null, down: 80, up: 40);
      expect(v.outcome, ConsumerOutcome.couldntCheckWifi);
      expect(v.wifiStatus, AxisStatus.unknown);
      expect(v.internetStatus, AxisStatus.weak);
    });

    test('neither link nor internet → D2, both Unknown', () {
      final v = mapFromEngine(tx: null, rx: null, down: null, up: null);
      expect(v.outcome, ConsumerOutcome.couldntComplete);
      expect(v.wifiStatus, AxisStatus.unknown);
      expect(v.internetStatus, AxisStatus.unknown);
    });
  });

  // ==========================================================================
  // ConsumerVerdict.sameRealTier — the ONE "both sides are X" guard (round 4).
  //
  // Test My Connection has TWO same-tier sentences (the hero and the verdict
  // line). Each used to carry its own hand-rolled copy of this guard, and they had
  // ALREADY DRIFTED: the hero excluded AxisStatus.notApplicable, the verdict line
  // did not, and NEITHER excluded notMeasured.
  //
  // Nothing could actually misfire — ConsumerVerdictMapper can only ever set
  // wifiStatus to notApplicable (never notMeasured) and internetStatus to
  // notMeasured (never notApplicable), so the two axes can never be EQUAL on a
  // non-tier value. That made the drift harmless AND invisible: a mutation of the
  // dead clause survived, because the clause is unreachable from the screen.
  //
  // The resolution is not to delete the defense, it is to make it REACHABLE — one
  // shared function, called directly, with every AxisStatus pair driven through it.
  // A guard that cannot be exercised is a guard nobody can trust, and it is exactly
  // the shape that invites a later "cleanup" to remove the wrong half.
  // ==========================================================================
  group('ConsumerVerdict.sameRealTier', () {
    ConsumerVerdict verdictWith(AxisStatus wifi, AxisStatus internet) =>
        ConsumerVerdict(
          outcome: ConsumerOutcome.bothFine,
          wifiStatus: wifi,
          internetStatus: internet,
          headline: 'h',
          body: 'b',
          selfHelp: SelfHelpTopic.wifi,
        );

    const List<AxisStatus> realTiers = <AxisStatus>[
      AxisStatus.strong,
      AxisStatus.moderate,
      AxisStatus.weak,
    ];
    const List<AxisStatus> nonTiers = <AxisStatus>[
      AxisStatus.unknown,
      AxisStatus.notApplicable,
      AxisStatus.notMeasured,
      // Reachable, but the speed test failed: there is no measured RATE behind
      // it, so it is not a real tier — the internet is up, we just cannot say
      // how fast. (2026-07-14.)
      AxisStatus.reachableUnmeasured,
    ];

    test('equal REAL tiers return that tier', () {
      for (final AxisStatus t in realTiers) {
        expect(verdictWith(t, t).sameRealTier(), t,
            reason: '$t on both axes is a genuine same-tier result');
      }
    });

    test('EVERY equal NON-tier pair returns null (the whitelist)', () {
      // THE MUTATION TARGET. Flip any of these three to `return wifiStatus` and a
      // cellular-only phone can read "Both sides are Not connected."
      for (final AxisStatus t in nonTiers) {
        expect(verdictWith(t, t).sameRealTier(), isNull,
            reason: '$t is not a measured tier. Two axes agreeing that they have '
                'NOTHING is not "both sides are the same" — it is two absences, '
                'and "Both sides are $t" is gibberish.');
      }
    });

    test('the cellular-only shape never produces a same-tier sentence', () {
      // Keith's device, stated as the pair it actually produces: the Wi-Fi axis is
      // notApplicable (no link) while the internet axis carries a real measured
      // tier. Unequal, so null — but pin it explicitly, because THIS is the pair
      // the guard exists to stop.
      for (final AxisStatus t in realTiers) {
        expect(verdictWith(AxisStatus.notApplicable, t).sameRealTier(), isNull);
        expect(verdictWith(t, AxisStatus.notMeasured).sameRealTier(), isNull);
      }
    });

    test('UNEQUAL axes always return null, across the whole matrix', () {
      for (final AxisStatus w in AxisStatus.values) {
        for (final AxisStatus i in AxisStatus.values) {
          if (w == i) continue;
          expect(verdictWith(w, i).sameRealTier(), isNull,
              reason: 'wifi=$w internet=$i are not the same tier');
        }
      }
    });

    test('the matrix is exhaustive — every AxisStatus member is covered', () {
      // If a member is added to AxisStatus, it lands in neither list and this
      // fails, forcing a deliberate decision about which side it belongs on
      // rather than silently defaulting into the "both sides are X" sentence.
      expect(
        <AxisStatus>{...realTiers, ...nonTiers},
        AxisStatus.values.toSet(),
        reason: 'a new AxisStatus must be explicitly classified as a real tier '
            'or a non-tier — never left to fall through',
      );
    });
  });
}
