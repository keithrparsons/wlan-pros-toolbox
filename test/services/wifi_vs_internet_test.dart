// WifiVsInternetEngine — pure verdict-engine unit tests.
//
// Exhaustive over the spec matrix: the grade gate, all three ratio bands, the
// macOS Tx-only single-rate path, the Rx-only path, the unknown-rate path, the
// unknown-internet path, and the two SNR/RSSI context lines. No Flutter, no
// network, no radio — plain numbers in, a verdict out.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_vs_internet.dart';

void main() {
  // A healthy 5 GHz link: avg(866, 780) = 823 Mbps PHY → 0.55 × 823 = 452.65
  // usable. Used as the baseline link for the ratio-band tests.
  WifiVsInternetResult eval({
    double? tx = 866,
    double? rx = 780,
    bool rxAvailable = true,
    int? snr = 45,
    int? rssi = -50,
    double? down,
    double? up,
    InternetHealth health = InternetHealth.marginal,
    OnlineEvidence onlineEvidence = const OnlineEvidence(),
  }) {
    return WifiVsInternetEngine.evaluate(
      txRateMbps: tx,
      rxRateMbps: rx,
      rxRateAvailable: rxAvailable,
      snrDb: snr,
      rssiDbm: rssi,
      internetDownMbps: down,
      internetUpMbps: up,
      internetHealth: health,
      onlineEvidence: onlineEvidence,
    );
  }

  // All three "you're online" signals present: a stalled speed test should read
  // as reachable-but-unmeasured, not "could not read".
  const fullOnline = OnlineEvidence(
    dnsResolved: true,
    publicIpObtained: true,
    cloudReachable: true,
  );

  group('link-rate math + rate basis', () {
    test('averages Tx and Rx when both present', () {
      final r = eval(tx: 866, rx: 780);
      expect(r.rateBasis, WifiRateBasis.averaged);
      expect(r.linkRateMbps, closeTo(823, 0.001));
      expect(r.usableWifiMbps, closeTo(0.55 * 823, 0.001));
    });

    test('macOS Tx-only path uses Tx alone and records the basis', () {
      // macOS public CoreWLAN exposes Tx but not Rx (rxRateAvailable false).
      final r = eval(tx: 600, rx: null, rxAvailable: false, down: 50, up: 10);
      expect(r.rateBasis, WifiRateBasis.txOnly);
      expect(r.linkRateMbps, 600);
      expect(r.usableWifiMbps, closeTo(0.55 * 600, 0.001));
    });

    test('Rx-only path uses Rx alone', () {
      final r = eval(tx: null, rx: 400, down: 50, up: 10);
      expect(r.rateBasis, WifiRateBasis.rxOnly);
      expect(r.linkRateMbps, 400);
    });
  });

  group('grade gate (good internet → bothHealthy regardless of ratio)', () {
    test('fast link + fast internet → bothHealthy, high-ratio note', () {
      // High internet vs usable capacity (ratio ≥ 0.70) but internet is GOOD,
      // so the gate fires and it is never mislabeled a fault.
      final r = eval(
        tx: 400,
        rx: 400, // usable = 0.55 × 400 = 220
        down: 300,
        up: 150, // avg 225 → ratio ≈ 1.02
        health: InternetHealth.good,
      );
      expect(r.verdict, WifiVsInternetVerdict.bothHealthy);
      expect(r.headline, 'Both healthy');
      expect(r.ratio, greaterThanOrEqualTo(kWifiLimiterRatio));
      expect(r.explanation, contains('most of your Wi-Fi link capacity'));
    });

    test(
      'good internet with link headroom → bothHealthy, spare-capacity note',
      () {
        final r = eval(
          tx: 1200,
          rx: 1200, // usable = 660
          down: 200,
          up: 50, // avg 125 → ratio ≈ 0.19 (would be "upstream" if marginal)
          health: InternetHealth.good,
        );
        expect(r.verdict, WifiVsInternetVerdict.bothHealthy);
        expect(r.explanation, contains('to spare'));
      },
    );
  });

  group('ratio bands (marginal/poor internet)', () {
    test('ratio ≥ 0.70 → wifiLimiter', () {
      // usable = 452.65; internet avg needs ≥ 0.70 × 452.65 ≈ 316.9.
      final r = eval(down: 400, up: 360); // avg 380 → ratio ≈ 0.84
      expect(r.verdict, WifiVsInternetVerdict.wifiLimiter);
      expect(r.headline, "It's your Wi-Fi");
      expect(r.ratio, greaterThanOrEqualTo(0.70));
    });

    test('ratio exactly 0.70 → wifiLimiter (boundary is inclusive)', () {
      // usable = 0.55 × 200 = 110; internet avg 77 → ratio = 0.70 exactly.
      final r = eval(tx: 200, rx: 200, down: 77, up: 77);
      expect(r.ratio, closeTo(0.70, 1e-9));
      expect(r.verdict, WifiVsInternetVerdict.wifiLimiter);
    });

    test('ratio < 0.40 → upstream', () {
      final r = eval(down: 100, up: 60); // avg 80 → ratio ≈ 0.177
      expect(r.verdict, WifiVsInternetVerdict.upstream);
      expect(r.headline, "It's upstream, not your Wi-Fi");
      expect(r.ratio, lessThan(0.40));
    });

    test('ratio just under 0.40 → upstream (boundary exclusive)', () {
      // usable 110; avg 43.9 → ratio ≈ 0.399.
      final r = eval(tx: 200, rx: 200, down: 43.9, up: 43.9);
      expect(r.ratio, lessThan(0.40));
      expect(r.verdict, WifiVsInternetVerdict.upstream);
    });

    test(
      'ratio exactly 0.40 → bothContributing (lower boundary inclusive)',
      () {
        // usable 110; avg 44 → ratio = 0.40 exactly.
        final r = eval(tx: 200, rx: 200, down: 44, up: 44);
        expect(r.ratio, closeTo(0.40, 1e-9));
        expect(r.verdict, WifiVsInternetVerdict.bothContributing);
      },
    );

    test('0.40 ≤ ratio < 0.70 → bothContributing', () {
      final r = eval(down: 280, up: 200); // avg 240 → ratio ≈ 0.53
      expect(r.verdict, WifiVsInternetVerdict.bothContributing);
      expect(r.headline, 'Both contributing');
      expect(r.ratio, inInclusiveRange(0.40, 0.70));
    });
  });

  group('unknown paths', () {
    test('no Tx and no Rx → wifiUnknown (internet-only read)', () {
      final r = eval(tx: null, rx: null, down: 100, up: 40);
      expect(r.verdict, WifiVsInternetVerdict.wifiUnknown);
      expect(r.rateBasis, WifiRateBasis.none);
      expect(r.usableWifiMbps, isNull);
      expect(r.ratio, isNull);
      // The measured internet figure is still surfaced in the caveat.
      expect(r.internetAvgMbps, closeTo(70, 0.001));
      expect(r.explanation, contains('internet-only'));
    });

    test('no rate AND no internet → wifiUnknown, prompts a full read', () {
      final r = eval(tx: null, rx: null, down: null, up: null);
      expect(r.verdict, WifiVsInternetVerdict.wifiUnknown);
      expect(r.internetAvgMbps, isNull);
      expect(r.explanation, contains('cannot localize'));
    });

    test(
      'link known but internet unmeasured → wifiUnknown (internet side)',
      () {
        final r = eval(down: null, up: null, health: InternetHealth.marginal);
        expect(r.verdict, WifiVsInternetVerdict.wifiUnknown);
        expect(r.linkRateMbps, isNotNull);
        expect(r.internetAvgMbps, isNull);
        expect(r.explanation, contains('internet throughput could not be'));
      },
    );

    test('single internet side present still averages (download only)', () {
      final r = eval(down: 80, up: null); // avg = 80 (single-side fallback)
      expect(r.internetAvgMbps, 80);
      expect(r.verdict, isNot(WifiVsInternetVerdict.wifiUnknown));
    });
  });

  group('honest "you are online" path (throughput unmeasurable + online)', () {
    test(
      'throughput unmeasurable BUT online evidence strong → onlineUnmeasured, '
      'never "could not read"',
      () {
        // macOS hotel case: Tx exposed (link rate known), but the speed test
        // stalled (no internet down/up), and DNS + public IP + cloud all OK.
        final r = eval(
          tx: 600,
          rx: null,
          rxAvailable: false,
          down: null,
          up: null,
          onlineEvidence: fullOnline,
        );
        expect(r.verdict, WifiVsInternetVerdict.onlineUnmeasured);
        expect(r.headline, 'You are online');
        expect(r.explanation, contains('reachable'));
        expect(r.explanation, contains('Try again in a moment'));
        // No fabricated number: the speed stays unmeasured (GL-005).
        expect(r.internetAvgMbps, isNull);
        expect(r.ratio, isNull);
        // The known link rate is still carried through.
        expect(r.linkRateMbps, 600);
      },
    );

    test(
      'macOS no-Rx + strong reachability → online verdict, does NOT collapse '
      'to "could not read"',
      () {
        // Rx is never exposed on macOS, so the Wi-Fi-vs-internet comparison can
        // never fully compute; with strong reachability the read must lead with
        // the online truth, not the partial-read caveat.
        final r = eval(
          tx: 540,
          rx: null,
          rxAvailable: false,
          down: null,
          up: null,
          onlineEvidence: fullOnline,
        );
        expect(r.verdict, WifiVsInternetVerdict.onlineUnmeasured);
        expect(r.rateBasis, WifiRateBasis.txOnly);
        // Leads with the online truth, NOT the bleak "could not read your
        // Wi-Fi" partial-read framing. ("could not be measured" for the SPEED
        // is the correct, honest qualifier and is expected.)
        expect(r.headline, 'You are online');
        expect(r.explanation, isNot(contains('could not read')));
        expect(r.explanation, isNot(contains('partial')));
      },
    );

    test('wired (no rate) + strong reachability → online, not wifiUnknown', () {
      final r = eval(
        tx: null,
        rx: null,
        down: null,
        up: null,
        onlineEvidence: fullOnline,
      );
      expect(r.verdict, WifiVsInternetVerdict.onlineUnmeasured);
      expect(r.headline, 'You are online');
    });

    test('partial evidence (DNS + IP, no cloud) does NOT flip to online', () {
      const partial = OnlineEvidence(
        dnsResolved: true,
        publicIpObtained: true,
        // cloudReachable defaults false — not all three present.
      );
      final r = eval(
        tx: 600,
        rx: null,
        rxAvailable: false,
        down: null,
        up: null,
        onlineEvidence: partial,
      );
      // Falls back to the honest wifiUnknown internet-side caveat, NOT online.
      expect(r.verdict, WifiVsInternetVerdict.wifiUnknown);
    });

    test(
      'measured throughput is NOT overridden by evidence (the 7:11 run path '
      'stays correct)',
      () {
        // Internet measured fine (upstream verdict); strong evidence must not
        // hijack a real measurement into the online-unmeasured verdict.
        final r = eval(
          down: 100,
          up: 60, // avg 80, ratio ≈ 0.18 → upstream
          onlineEvidence: fullOnline,
        );
        expect(r.verdict, WifiVsInternetVerdict.upstream);
        expect(r.internetAvgMbps, isNotNull);
      },
    );
  });

  group('OnlineEvidence', () {
    test('isOnline requires all three signals', () {
      expect(
        const OnlineEvidence(
          dnsResolved: true,
          publicIpObtained: true,
          cloudReachable: true,
        ).isOnline,
        isTrue,
      );
      expect(
        const OnlineEvidence(dnsResolved: true, publicIpObtained: true)
            .isOnline,
        isFalse,
      );
      expect(const OnlineEvidence().isOnline, isFalse);
    });
  });

  group('SNR/RSSI context (supporting, never the headline)', () {
    test('low rate + low SNR → weak-signal line', () {
      // Low link rate (avg 120 < 200) + weak SNR (< 25 dB).
      final r = eval(tx: 120, rx: 120, snr: 18, down: 200, up: 100);
      expect(r.snrContext, contains('Weak signal'));
      expect(r.snrContext, contains('18dB'));
    });

    test('low rate + good SNR → interference/legacy-lock engineer flag', () {
      final r = eval(tx: 120, rx: 120, snr: 40, down: 30, up: 10);
      expect(r.snrContext, contains('Strong signal'));
      expect(r.snrContext, contains('interference'));
    });

    test('healthy rate → no context line (stays quiet)', () {
      final r = eval(tx: 866, rx: 780, snr: 20, down: 100, up: 40);
      expect(r.snrContext, isEmpty);
    });

    test('no SNR reading → no context line even on a low rate', () {
      final r = eval(tx: 120, rx: 120, snr: null, down: 100, up: 40);
      expect(r.snrContext, isEmpty);
    });

    test('unknown-rate path carries no SNR context', () {
      final r = eval(tx: null, rx: null, snr: 30, down: 50, up: 20);
      expect(r.snrContext, isEmpty);
    });
  });

  group('rate-basis caption', () {
    test('captions every basis', () {
      expect(
        WifiVsInternetEngine.rateBasisCaption(WifiRateBasis.averaged),
        'averaged Tx and Rx',
      );
      expect(
        WifiVsInternetEngine.rateBasisCaption(WifiRateBasis.txOnly),
        contains('Tx only'),
      );
      expect(
        WifiVsInternetEngine.rateBasisCaption(WifiRateBasis.rxOnly),
        contains('Rx only'),
      );
      expect(
        WifiVsInternetEngine.rateBasisCaption(WifiRateBasis.none),
        'no rate reported',
      );
    });
  });
}
