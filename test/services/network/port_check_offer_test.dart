// When Check My Connection offers the port check: only when the ladder points at
// the internet or at services (Keith, 16 NOV, approach A). No ladder row, no
// auto-run.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/analyze/triage_ladder.dart';
import 'package:wlan_pros_toolbox/services/network/port_check_verdict.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_vs_internet.dart';

const OnlineEvidence _online = OnlineEvidence(
  dnsResolved: true,
  publicIpObtained: true,
  cloudReachable: true,
);

TriageLadder ladder({
  WifiVsInternetVerdict verdict = WifiVsInternetVerdict.bothHealthy,
  int cloudReachable = 14,
}) => TriageLadder.compute(
  TriageInput(
    verdict: verdict,
    rssiDbm: -55,
    dns: TriageDnsState.resolved,
    dnsMs: 20,
    evidence: _online,
    internetMeasured: true,
    internetHealth: InternetHealth.good,
    cloudPanelPresent: true,
    cloudReachableCount: cloudReachable,
    cloudTotalCount: 14,
  ),
);

void main() {
  test('a healthy run does not offer it', () {
    expect(offerPortCheck(ladder()), isFalse);
  });

  test('services Looks off offers it', () {
    expect(offerPortCheck(ladder(cloudReachable: 9)), isTrue);
  });

  test('the internet rung Looks off (a sign-in network) offers it', () {
    expect(
      offerPortCheck(ladder(verdict: WifiVsInternetVerdict.captivePortal)),
      isTrue,
    );
  });

  test('no run yet offers nothing', () {
    expect(offerPortCheck(TriageLadder.compute(const TriageInput())), isFalse);
  });
}
