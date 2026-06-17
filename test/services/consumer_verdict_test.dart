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
// chips therefore depend on the engine's usableWifiMbps / internetAvgMbps, NOT
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
  double? internetAvgMbps,
  double? usableWifiMbps = 150,
}) {
  return WifiVsInternetResult(
    verdict: verdict,
    headline: 'engine headline',
    explanation: 'engine explanation',
    snrContext: '',
    rateBasis: WifiRateBasis.averaged,
    usableWifiMbps: usableWifiMbps,
    internetAvgMbps: internetAvgMbps,
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
          internetAvgMbps: 500,
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
          internetAvgMbps: 40,
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
          internetAvgMbps: 180,
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
          internetAvgMbps: 250,
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
          internetAvgMbps: 180,
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
          internetAvgMbps: 40,
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
          internetAvgMbps: 20,
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
          internetAvgMbps: 300,
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
            internetAvgMbps: 180,
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
          internetAvgMbps: 12,
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
          internetAvgMbps: 320,
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
            internetAvgMbps: null,
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
            internetAvgMbps: null,
          ),
        );
        expect(v.outcome, ConsumerOutcome.online);
        expect(v.headline, 'You are online');
        expect(v.body, contains('reachable'));
        expect(v.body, contains('Try again in a moment'));
        // No measured internet rate → honest Unknown internet chip (GL-005).
        expect(v.internetStatus, AxisStatus.unknown);
        // The body must NOT scold the user to get on Wi-Fi.
        expect(v.body, isNot(contains('Make sure')));
      },
    );
  });

  group('D1 body substitution (bodyForCouldntCheckWifi)', () {
    test('substitutes the rounded figure and "fine" when healthy', () {
      final body = ConsumerVerdictMapper.bodyForCouldntCheckWifi(
        internetAvgMbps: 83.6,
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
        internetAvgMbps: 12.2,
        healthy: false,
      );
      expect(body, contains('about 12 Mbps'));
      expect(body, contains('looks slow'));
    });

    test('falls back to the non-substituted form when figure is null', () {
      final body = ConsumerVerdictMapper.bodyForCouldntCheckWifi(
        internetAvgMbps: null,
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
      // usable = 0.55 × avg(200,200) = 110 (Moderate); internet avg 200
      // (Moderate) → ratio ≈ 1.8 → wifiLimiter.
      final v = mapFromEngine(tx: 200, rx: 200, down: 250, up: 150);
      expect(v.outcome, ConsumerOutcome.wifi);
      expect(v.wifiStatus, AxisStatus.moderate);
      expect(v.internetStatus, AxisStatus.moderate);
    });

    test('link headroom, slow internet → B (Internet), Wi-Fi Strong', () {
      // usable = 0.55 × avg(1000,1000) = 550 (Strong); internet avg 20 (Weak).
      final v = mapFromEngine(tx: 1000, rx: 1000, down: 25, up: 15);
      expect(v.outcome, ConsumerOutcome.internet);
      expect(v.wifiStatus, AxisStatus.strong);
      expect(v.internetStatus, AxisStatus.weak);
    });

    test('mid band → A (Wi-Fi lead)', () {
      // usable = 0.55 × avg(200,200) = 110 (Moderate); internet avg 55 (Weak).
      final v = mapFromEngine(tx: 200, rx: 200, down: 60, up: 50);
      expect(v.outcome, ConsumerOutcome.wifiLead);
      expect(v.wifiStatus, AxisStatus.moderate);
      expect(v.internetStatus, AxisStatus.weak);
    });

    test('good internet grade-gate → C (Both fine), both Strong', () {
      // usable = 0.55 × avg(400,400) = 220 (Moderate); internet avg 225
      // (Moderate). Tiers track the absolute rates even on the bothHealthy row.
      final v = mapFromEngine(
        tx: 400,
        rx: 400,
        down: 300,
        up: 150,
        health: InternetHealth.good,
      );
      expect(v.outcome, ConsumerOutcome.bothFine);
      expect(v.wifiStatus, AxisStatus.moderate);
      expect(v.internetStatus, AxisStatus.moderate);
    });

    test('no link rate but internet measured → D1, Wi-Fi Unknown', () {
      // No Tx/Rx → basis none → wifiUnknown; internet avg 60 (Weak).
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
}
