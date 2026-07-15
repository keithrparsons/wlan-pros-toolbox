// "NEVER SAY WE COULD NOT CHECK SOMETHING WE CHECKED" (Keith, 2026-07-14).
//
// On a cellular-only iPhone the result header read:
//
//     Internet:  [?] Couldn't check
//
// directly above the body text it was rendered from:
//
//     "You are online. Your internet is reachable, but the speed test did not
//      complete, so its speed could not be measured."
//
// Both came from the SAME result object. One of them was false. The app had
// reached the internet three independent ways — DNS resolved, a public IP was
// obtained, cloud apps answered ([OnlineEvidence]) — which is the ONLY way the
// engine ever emits `onlineUnmeasured`. The chip then reported that success as a
// failed read, and sent the user hunting for a problem that did not exist.
//
// This is the same wrong-kind-of-null that produced `Wi-Fi: Couldn't check` on a
// phone with no Wi-Fi (fixed 2026-07-13 with [AxisStatus.notApplicable]), one
// square over. The rate is null in every one of these cases, so the RATE cannot
// tell them apart; the VERDICT has to.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/consumer_verdict.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_vs_internet.dart';

/// The engine result a cellular-only phone produces when the speed test stalls
/// but all three online signals succeeded — Keith's exact case.
WifiVsInternetResult _onlineButUnmeasured() => const WifiVsInternetResult(
      verdict: WifiVsInternetVerdict.onlineUnmeasured,
      headline: 'You are online',
      explanation: 'Your internet is reachable, but the speed test did not '
          'complete, so its speed could not be measured. Try again in a moment.',
      snrContext: '',
      rateBasis: WifiRateBasis.none,
      usableWifiMbps: null,
      internetMbps: null,
      linkRateMbps: null,
      ratio: null,
      notOnWifi: true,
      speedTestSkipped: false,
    );

void main() {
  group('the internet axis must not report a successful check as a failure', () {
    test(
      'onlineUnmeasured -> reachableUnmeasured, NOT unknown ("Couldn\'t check")',
      () {
        final ConsumerVerdict v =
            ConsumerVerdictMapper.map(_onlineButUnmeasured());

        expect(
          v.internetStatus,
          AxisStatus.reachableUnmeasured,
          reason: 'The engine proved the internet is reachable (DNS + public IP '
              '+ cloud apps). The speed is what it could not measure.',
        );
        expect(
          v.internetStatus,
          isNot(AxisStatus.unknown),
          reason: '"Couldn\'t check" claims a failed read. The read succeeded.',
        );
      },
    );

    test(
      'the Wi-Fi axis on the same cellular-only result stays "Not connected"',
      () {
        final ConsumerVerdict v =
            ConsumerVerdictMapper.map(_onlineButUnmeasured());

        // Guard the 2026-07-13 fix: no regression back to "Couldn't check".
        expect(v.wifiStatus, AxisStatus.notApplicable);
      },
    );

    test(
      'reachableUnmeasured is NOT a real tier — it carries no measured rate',
      () {
        expect(AxisStatus.reachableUnmeasured.isRealTier, isFalse);
      },
    );
  });
}
