// "WI-FI IS UP, THE INTERNET IS DOWN" — THE SENTENCE THE APP COULD NOT SAY.
//
// ============================================================================
// KEITH'S DEVICE. ONE FRAME. A REAL CONFERENCE SSID.
// ============================================================================
//
//   headline: "We could not finish the check."
//   Wi-Fi: Weak  (RED chip)      Internet: Couldn't check
//   body:  "We could not read your Wi-Fi or your internet. Make sure you are on
//           Wi-Fi, then try again."
//   ...and directly beneath: Wi-Fi usable capacity 48 Mbps, full green bar.
//
// SAME MOMENT, Wi-Fi Information, same network: Tx 97 / Rx 77 Mbps, both green.
// SSID `Tom-Hildebrand-Science-Project`. A Ubiquiti AP. He was plainly associated.
//
// THE SCREEN CONTRADICTED ITSELF FOUR TIMES: it said it could not read the Wi-Fi
// WHILE PRINTING THE WI-FI RATE; it called a 97/77 Mbps link "Weak" in red; it told
// a man associated to a named AP to "make sure you are on Wi-Fi"; and it said
// "Couldn't check" about an internet it had checked THREE WAYS and got a definitive
// NO from.
//
// THE ARITHMETIC CONFIRMS IT WAS HIS OWN NUMBERS ON SCREEN:
//   avg(97, 77) = 87 Mbps link  ->  0.55 x 87 = 47.85  ->  "48 Mbps" usable.
// The app HAD the Wi-Fi reading. It printed it. And in the same card it claimed it
// could not read it.
//
// ============================================================================
// THE STRUCTURAL CAUSE
// ============================================================================
//
// `WifiVsInternetVerdict` had SIX members and NOT ONE meant "the Wi-Fi is up and the
// internet is not reachable." `OnlineEvidence` was read ONLY AS A POSITIVE — all
// three true -> `onlineUnmeasured`. Its NEGATIVE (all three false = DEFINITIVELY
// OFFLINE) was gathered on every single run and THROWN AWAY.
//
// So a working Wi-Fi link with a dead internet fell through to `wifiUnknown`
// ("Internet not measured") and the consumer layer rendered the D2 row: "Couldn't
// complete the check" + "Make sure you're connected to Wi-Fi and try again."
//
// THE APP'S DEFAULT EXPLANATION FOR ANYTHING IT COULD NOT MEASURE WAS "YOUR WI-FI IS
// BAD", because that was the only explanation it owned.
//
// ============================================================================
// THE THIRD KIND OF NULL
// ============================================================================
//
//   "we failed to measure it"  !=  "we chose not to"  !=  "WE MEASURED IT AND THERE
//                                                          IS NOTHING THERE"
//
// A definitively-offline internet is the THIRD, and it was printed as the FIRST.
// `consumer_verdict.dart` documents FOUR prior instances of this exact error in its
// own comments — and then committed the fifth one line later.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/consumer_verdict.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_vs_internet.dart';

/// Keith's actual link: Tx 97 / Rx 77 Mbps.
WifiVsInternetResult _evaluate({
  required OnlineEvidence evidence,
  double? tx = 97,
  double? rx = 77,
  bool notOnWifi = false,
}) =>
    WifiVsInternetEngine.evaluate(
      txRateMbps: tx,
      rxRateMbps: rx,
      internetDownMbps: null, // the speed test could not complete: no internet
      internetUpMbps: null,
      internetHealth: InternetHealth.marginal,
      onlineEvidence: evidence,
      notOnWifi: notOnWifi,
    );

/// DEFINITIVELY OFFLINE: all three probes ANSWERED, all three said NO.
const OnlineEvidence _offline = OnlineEvidence(
  dnsResolved: false,
  publicIpObtained: false,
  cloudReachable: false,
);

/// CAPTIVE PORTAL: DNS resolves (hijacked), cloud endpoints answer (the portal
/// accepts the TCP connection), and no public IP comes back (the portal cannot
/// forge TLS for the HTTPS lookup).
const OnlineEvidence _portal = OnlineEvidence(
  dnsResolved: true,
  publicIpObtained: false,
  cloudReachable: true,
);

/// GENUINELY ONLINE, speed test stalled.
const OnlineEvidence _online = OnlineEvidence(
  dnsResolved: true,
  publicIpObtained: true,
  cloudReachable: true,
);

/// NOTHING HAS COME BACK YET. The normal mid-flight state of every healthy run.
const OnlineEvidence _pending = OnlineEvidence();

void main() {
  group('THE ENGINE CAN NOW SAY IT', () {
    test('KEITH\'S FRAME: Wi-Fi up, internet definitively down', () {
      final WifiVsInternetResult r = _evaluate(evidence: _offline);

      // BEFORE: `WifiVsInternetVerdict.wifiUnknown`, headline "Internet not
      // measured" -> consumer D2 -> "We could not finish the check."
      expect(r.verdict, WifiVsInternetVerdict.internetUnreachable);
      expect(r.headline, 'No internet');

      // THE WI-FI AXIS KEEPS ITS MEASURED TIER. If we measured 48 Mbps we SAY
      // 48 Mbps — a dead internet is never a reason to downgrade a reading we took.
      expect(r.linkRateMbps, 87);
      expect(r.usableWifiMbps, closeTo(47.85, 0.01));
      expect(r.rateBasis, WifiRateBasis.averaged);

      // ...and the explanation names the Wi-Fi as WORKING and the problem as PAST it.
      expect(r.explanation, contains('your Wi-Fi link is working'));
      expect(r.explanation, contains('past your Wi-Fi, not in it'));
      // It must NOT tell a man plainly associated to an AP to get on Wi-Fi.
      expect(r.explanation.toLowerCase(), isNot(contains('make sure you are on')));
    });

    test('CAPTIVE PORTAL: the conference sign-in page', () {
      final WifiVsInternetResult r = _evaluate(evidence: _portal);
      expect(r.verdict, WifiVsInternetVerdict.captivePortal);
      expect(r.headline, 'Sign in to this network');
      expect(r.explanation, contains('sign-in page'));
      expect(r.explanation, contains('Open your browser'));
      // The Wi-Fi keeps its measurement here too.
      expect(r.usableWifiMbps, closeTo(47.85, 0.01));
    });

    test('a WORKING internet is untouched (no over-firing)', () {
      // The most important negative control on this whole change. If `isOffline` were
      // sloppy, EVERY healthy run whose speed test stalled would now read "No
      // internet" — a far worse lie than the one being fixed.
      final WifiVsInternetResult r = _evaluate(evidence: _online);
      expect(r.verdict, WifiVsInternetVerdict.onlineUnmeasured);
      expect(r.headline, 'You are online');
    });

    test(
      'A PENDING PROBE IS NOT AN OFFLINE PROBE — and this is the trap the whole '
      'fix turns on',
      () {
        // THE ONE THAT WOULD HAVE SHIPPED A DISASTER.
        //
        // The three evidence signals land ASYNCHRONOUSLY, and the verdict is first
        // computed in `onDone` — often BEFORE they report. They used to default to
        // `false`, so "no probe has answered yet" and "every probe answered NO" were
        // THE SAME VALUE.
        //
        // A naive "all three false means offline" would therefore have fired on the
        // NORMAL MID-FLIGHT STATE OF EVERY HEALTHY RUN, and told half the app's users
        // their internet was down. That is the two-kinds-of-null error one level
        // deeper than the four this codebase already fixed.
        //
        // `null` = UNANSWERED. `false` = ANSWERED NO. `isOffline` demands all three
        // be an actual `false`.
        final WifiVsInternetResult r = _evaluate(evidence: _pending);
        expect(
          r.verdict,
          isNot(WifiVsInternetVerdict.internetUnreachable),
          reason: 'a probe that has not answered yet is NOT a probe that said no',
        );
        expect(_pending.isOffline, isFalse);
        expect(_pending.isOnline, isFalse);
        expect(_pending.isCaptivePortal, isFalse);
      },
    );

    test('a PARTIALLY-answered probe set asserts nothing', () {
      // DNS said no; the other two have not reported. We know nothing yet.
      const OnlineEvidence half = OnlineEvidence(dnsResolved: false);
      expect(half.isOffline, isFalse);
      expect(
        _evaluate(evidence: half).verdict,
        isNot(WifiVsInternetVerdict.internetUnreachable),
      );
    });

    test('a CELLULAR-only phone keeps its honest not-on-Wi-Fi copy', () {
      // DO NOT REGRESS. Keith verified this on his physical iPhone today. These
      // verdicts are about a WORKING WI-FI LINK with a dead internet behind it; a
      // phone with no Wi-Fi at all has a different (and already correct) story.
      final WifiVsInternetResult r = _evaluate(
        evidence: _offline,
        tx: null,
        rx: null,
        notOnWifi: true,
      );
      expect(r.verdict, WifiVsInternetVerdict.wifiUnknown);
      expect(r.headline, 'Not connected to Wi-Fi');
    });

    test('internetUnreachable still fires with NO Wi-Fi rate, and stays honest', () {
      // A wired desktop with a dead internet. We have no Wi-Fi reading, so we must
      // not claim the Wi-Fi "is working" — but the internet is still definitively
      // not there, and that is still the useful thing to say.
      final WifiVsInternetResult r =
          _evaluate(evidence: _offline, tx: null, rx: null);
      expect(r.verdict, WifiVsInternetVerdict.internetUnreachable);
      expect(r.usableWifiMbps, isNull);
      expect(
        r.explanation,
        isNot(contains('your Wi-Fi link is working')),
        reason: 'never assert a Wi-Fi reading we do not have (GL-005)',
      );
      expect(r.explanation, contains('Nothing on the internet is answering'));
    });
  });

  group('THE CONSUMER LAYER STOPS BLAMING THE WI-FI', () {
    test('KEITH\'S FRAME, translated: every one of the four lies is gone', () {
      final ConsumerVerdict v =
          ConsumerVerdictMapper.map(_evaluate(evidence: _offline));

      // LIE 1 — "We could not finish the check." It finished. It found the answer.
      expect(v.outcome, ConsumerOutcome.internetDown);
      expect(v.headline, 'No internet');

      // LIE 2 — "Internet: Couldn't check". We CHECKED it. Three ways.
      expect(v.internetStatus, AxisStatus.unreachable);

      // LIE 3 — the Wi-Fi axis. It keeps its MEASURED tier: 47.85 Mbps usable really
      // is below the 100 Mbps `weak` threshold, and that grade is CORRECT — the lie
      // was never the tier, it was the FRAME around it. The app is no longer claiming
      // it could not read a link whose rate it is printing.
      expect(v.wifiStatus, AxisStatus.weak);

      // LIE 4 — "Make sure you are on Wi-Fi". He WAS on Wi-Fi.
      expect(v.body, contains("You're connected to Wi-Fi"));
      expect(v.body.toLowerCase(), isNot(contains('make sure')));

      // AND THE ONE THAT MATTERS MOST: the self-help no longer points at the Wi-Fi.
      // Every unmeasurable thing used to route to `reconnect` / the Wi-Fi advice.
      expect(
        v.selfHelp,
        SelfHelpTopic.internet,
        reason: 'the fix is the ISP or the router, NOT boosting the Wi-Fi signal',
      );
    });

    test('a captive portal routes to SIGN IN, not to "reconnect"', () {
      final ConsumerVerdict v =
          ConsumerVerdictMapper.map(_evaluate(evidence: _portal));
      expect(v.outcome, ConsumerOutcome.signInRequired);
      expect(v.internetStatus, AxisStatus.unreachable);
      expect(v.wifiStatus, AxisStatus.weak); // measured, kept
      expect(v.selfHelp, SelfHelpTopic.signIn);
      expect(v.body, contains('sign-in page'));
    });

    test('"Not reachable" is NOT "Couldn\'t check" — the fifth kind of null', () {
      // The whole point, in one assertion. `unknown` means WE TRIED AND FAILED.
      // `unreachable` means WE SUCCEEDED AND THE ANSWER IS NO. The rate is null in
      // both, which is exactly why the RATE alone can never tell them apart and the
      // VERDICT has to reach the decision.
      final ConsumerVerdict down =
          ConsumerVerdictMapper.map(_evaluate(evidence: _offline));
      expect(down.internetStatus, isNot(AxisStatus.unknown));
      expect(down.internetStatus, AxisStatus.unreachable);

      // ...and `unreachable` is NOT a real tier, so it can never produce a
      // "both sides are X" sentence out of a link that has no rate.
      expect(AxisStatus.unreachable.isRealTier, isFalse);
      expect(down.sameRealTier(), isNull);
    });

    test('a HEALTHY connection is untouched', () {
      final WifiVsInternetResult healthy = WifiVsInternetEngine.evaluate(
        txRateMbps: 900,
        rxRateMbps: 900,
        internetDownMbps: 400,
        internetUpMbps: 40,
        internetHealth: InternetHealth.good,
        onlineEvidence: _online,
      );
      final ConsumerVerdict v =
          ConsumerVerdictMapper.map(healthy, internetHealthy: true);
      expect(v.outcome, ConsumerOutcome.bothFine);
      expect(v.internetStatus, AxisStatus.strong); // 400 > 250
      expect(v.wifiStatus, AxisStatus.strong); // 0.55 * 900 = 495 > 250
    });
  });
}
