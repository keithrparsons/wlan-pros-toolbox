// ConsumerVerdictMapper — pure translator unit tests.
//
// One test per mapping row in the build spec's "Verdict translation" table,
// INCLUDING the D1/D2 split (wifiUnknown with vs without a measured internet
// figure). No Flutter, no network, no radio — an engine result in, a consumer
// verdict out. Each test asserts the exact headline + body copy is carried
// verbatim from the spec, so a future copy edit is a single deliberate change.
//
// Two halves:
//   1. Direct mapping rows — a constructed WifiVsInternetResult per verdict, so
//      each branch is asserted in isolation regardless of engine internals.
//   2. End-to-end — the SAME shared WifiVsInternetEngine the pro tool drives,
//      fed plain numbers, to prove the consumer layer maps the engine's REAL
//      output (not just hand-built results).

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/consumer_verdict.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_vs_internet.dart';

/// Builds a WifiVsInternetResult for a given verdict with just the fields the
/// mapper reads (verdict + internetAvgMbps). The other fields are filler the
/// consumer layer ignores.
WifiVsInternetResult result(
  WifiVsInternetVerdict verdict, {
  double? internetAvgMbps,
}) {
  return WifiVsInternetResult(
    verdict: verdict,
    headline: 'engine headline',
    explanation: 'engine explanation',
    snrContext: '',
    rateBasis: WifiRateBasis.averaged,
    usableWifiMbps: 100,
    internetAvgMbps: internetAvgMbps,
    linkRateMbps: 200,
    ratio: 0.5,
  );
}

void main() {
  group('verdict translation — one row per mapping', () {
    test('wifiLimiter → A (Wi-Fi)', () {
      final v = ConsumerVerdictMapper.map(
        result(WifiVsInternetVerdict.wifiLimiter, internetAvgMbps: 84),
      );
      expect(v.outcome, ConsumerOutcome.wifi);
      expect(v.headline, 'Looks like your Wi-Fi');
      expect(
        v.body,
        'Your internet can go faster than your Wi-Fi is carrying right now. '
        'The slow part is between your device and the router.',
      );
      expect(v.selfHelp, SelfHelpTopic.wifi);
    });

    test('bothContributing → A (Wi-Fi lead)', () {
      final v = ConsumerVerdictMapper.map(
        result(WifiVsInternetVerdict.bothContributing, internetAvgMbps: 40),
      );
      expect(v.outcome, ConsumerOutcome.wifiLead);
      expect(v.headline, 'Mostly your Wi-Fi');
      expect(
        v.body,
        'Both your Wi-Fi and your internet are a little slow. Start with the '
        "Wi-Fi fixes below, they're the easiest.",
      );
      expect(v.selfHelp, SelfHelpTopic.wifi);
    });

    test('upstream → B (Internet)', () {
      final v = ConsumerVerdictMapper.map(
        result(WifiVsInternetVerdict.upstream, internetAvgMbps: 20),
      );
      expect(v.outcome, ConsumerOutcome.internet);
      expect(v.headline, 'Looks like your Internet');
      expect(
        v.body,
        'Your Wi-Fi has room to spare, but the internet coming into your home '
        'is the slow part.',
      );
      expect(v.selfHelp, SelfHelpTopic.internet);
    });

    test('bothHealthy → C (Both fine)', () {
      final v = ConsumerVerdictMapper.map(
        result(WifiVsInternetVerdict.bothHealthy, internetAvgMbps: 300),
      );
      expect(v.outcome, ConsumerOutcome.bothFine);
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
      'wifiUnknown WITH internet measured → D1 (Couldn’t check everything)',
      () {
        final v = ConsumerVerdictMapper.map(
          result(WifiVsInternetVerdict.wifiUnknown, internetAvgMbps: 84),
        );
        expect(v.outcome, ConsumerOutcome.couldntCheckWifi);
        expect(v.headline, 'Couldn’t check everything');
        expect(v.body, contains('[X] Mbps'));
        expect(v.body, contains('[fine/slow]'));
        expect(v.selfHelp, SelfHelpTopic.reconnect);
      },
    );

    test(
      'wifiUnknown WITHOUT internet measured → D2 (Couldn’t complete)',
      () {
        final v = ConsumerVerdictMapper.map(
          result(WifiVsInternetVerdict.wifiUnknown, internetAvgMbps: null),
        );
        expect(v.outcome, ConsumerOutcome.couldntComplete);
        expect(v.headline, 'Couldn’t complete the check');
        expect(v.body, "Make sure you're connected to Wi-Fi and try again.");
        expect(v.selfHelp, SelfHelpTopic.reconnect);
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
    // consumer mapping is proven against the engine's real output.
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
      // usable = 0.55 × avg(200,200) = 110; internet avg 200 → ratio ≈ 1.8.
      final v = mapFromEngine(tx: 200, rx: 200, down: 250, up: 150);
      expect(v.outcome, ConsumerOutcome.wifi);
    });

    test('link headroom, slow internet → B (Internet)', () {
      // usable = 0.55 × avg(1000,1000) = 550; internet avg 20 → ratio ≈ 0.036.
      final v = mapFromEngine(tx: 1000, rx: 1000, down: 25, up: 15);
      expect(v.outcome, ConsumerOutcome.internet);
    });

    test('mid band → A (Wi-Fi lead)', () {
      // usable = 0.55 × avg(200,200) = 110; internet avg 55 → ratio 0.5.
      final v = mapFromEngine(tx: 200, rx: 200, down: 60, up: 50);
      expect(v.outcome, ConsumerOutcome.wifiLead);
    });

    test('good internet grade-gate → C (Both fine)', () {
      final v = mapFromEngine(
        tx: 400,
        rx: 400,
        down: 300,
        up: 150,
        health: InternetHealth.good,
      );
      expect(v.outcome, ConsumerOutcome.bothFine);
    });

    test('no link rate but internet measured → D1', () {
      // No Tx/Rx → basis none → wifiUnknown, with a measured internet figure.
      final v = mapFromEngine(tx: null, rx: null, down: 80, up: 40);
      expect(v.outcome, ConsumerOutcome.couldntCheckWifi);
    });

    test('neither link nor internet → D2', () {
      final v = mapFromEngine(tx: null, rx: null, down: null, up: null);
      expect(v.outcome, ConsumerOutcome.couldntComplete);
    });
  });
}
