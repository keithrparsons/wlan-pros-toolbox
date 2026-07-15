// "SKIPPED" IS NOT "FAILED" — the two kinds of null behind a missing speed.
//
// WHY THIS FILE EXISTS (round-4 review, K5 / K6 / K22). Three lines carried the
// distinction between "the speed test RAN AND FAILED" and "the speed test was never
// RUN", and all three survived the full suite when mutated. The comments in the
// source asserted the rules were "mutually exclusive, so exactly one fires, never
// both and never neither" — and NOTHING TESTED THAT. A claim in a comment is not a
// guarantee; it is a hope.
//
// It matters because the two produce OPPOSITE advice:
//
//   R-06  "the speed test did not complete... Try again in a moment."
//   R-06S "the speed test was skipped to save cellular data."
//
// If both fire, a user who just DECLINED the data cost is told, in the same report,
// to try again — inviting them to burn the very data they chose not to spend. And if
// neither fires, the report says nothing at all about the missing number.
//
// The same shape one rule up:
//
//   R-05  "One side could not be measured" + install the companion Shortcut.
//   R-05N "there was no Wi-Fi link to check."
//
// R-05 firing on a device with NO Wi-Fi link is Keith's original bug, in the analyzer.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/analyze/analysis_finding.dart';
import 'package:wlan_pros_toolbox/services/network/analyze/analyze_engine.dart';
import 'package:wlan_pros_toolbox/services/network/analyze/analyze_input.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_vs_internet.dart';

Set<String> _fired(AnalyzeInput i) => AnalyzeEngine.analyze(i)
    .findings
    .map((AnalysisFinding f) => f.ruleId)
    .toSet();

void main() {
  group('R-06 / R-06S — skipped is not failed (EXACTLY ONE fires)', () {
    AnalyzeInput online({required bool skipped}) => AnalyzeInput(
          verdict: WifiVsInternetVerdict.onlineUnmeasured,
          internetMeasured: false,
          speedTestSkipped: skipped,
          dnsResolutionMs: 12,
          cloudReachableCount: 4,
          cloudTotalCount: 4,
        );

    test('the user DECLINED: R-06S fires, R-06 does NOT', () {
      final Set<String> ids = _fired(online(skipped: true));
      expect(ids, contains('R-06S'));
      expect(
        ids,
        isNot(contains('R-06')),
        reason: 'R-06 tells the user the test "did not complete" and to "try again '
            'in a moment". Nothing failed — they declined. Saying both invites them '
            'to spend the cellular data they just chose not to spend.',
      );
    });

    test('the test STALLED: R-06 fires, R-06S does NOT', () {
      final Set<String> ids = _fired(online(skipped: false));
      expect(ids, contains('R-06'));
      expect(ids, isNot(contains('R-06S')),
          reason: 'nothing was skipped: the test ran and failed');
    });

    test('EXACTLY ONE of R-06 / R-06S fires — never both, never neither', () {
      // The property the source comment claims. Now it is enforced.
      for (final bool skipped in <bool>[true, false]) {
        final Set<String> ids = _fired(online(skipped: skipped));
        final int n = ids.intersection(<String>{'R-06', 'R-06S'}).length;
        expect(n, 1,
            reason: 'speedTestSkipped=$skipped fired $n of {R-06, R-06S}; the '
                'verdict must produce exactly one explanation for the missing speed');
      }
    });
  });

  group('R-05 / R-05N — a failed read is not an absent link (EXACTLY ONE fires)',
      () {
    AnalyzeInput unknownWifi({required bool notOnWifi}) => AnalyzeInput(
          verdict: WifiVsInternetVerdict.wifiUnknown,
          platformIsIos: true,
          wifiSignalCaptured: false,
          notOnWifi: notOnWifi,
          internetMeasured: true,
          downloadMbps: 60,
          uploadMbps: 20,
        );

    test('NO Wi-Fi link: R-05N fires, R-05 does NOT', () {
      final Set<String> ids = _fired(unknownWifi(notOnWifi: true));
      expect(ids, contains('R-05N'));
      expect(
        ids,
        isNot(contains('R-05')),
        reason: 'R-05 says "one side could not be measured" and offers the '
            'companion Shortcut. There was no side. That is Keith\'s original bug, '
            'inside the analyzer.',
      );
    });

    test('the Wi-Fi READ failed: R-05 fires, R-05N does NOT', () {
      final Set<String> ids = _fired(unknownWifi(notOnWifi: false));
      expect(ids, contains('R-05'));
      expect(ids, isNot(contains('R-05N')));
    });

    test('EXACTLY ONE of R-05 / R-05N fires — never both, never neither', () {
      for (final bool notOnWifi in <bool>[true, false]) {
        final Set<String> ids = _fired(unknownWifi(notOnWifi: notOnWifi));
        final int n = ids.intersection(<String>{'R-05', 'R-05N'}).length;
        expect(n, 1,
            reason: 'notOnWifi=$notOnWifi fired $n of {R-05, R-05N}');
      }
    });
  });

  // ========================================================================
  // K22 — the ENGINE's own explanation copy for the same distinction. The rules
  // above are the ANALYZER; this is the verdict the result screen reads.
  // ========================================================================
  group("the engine's onlineUnmeasured explanation (K22)", () {
    // `internet == null` (no measured throughput) + full online evidence is the
    // shape that produces the `onlineUnmeasured` verdict.
    WifiVsInternetResult compute({required bool skipped}) =>
        WifiVsInternetEngine.evaluate(
          internetHealth: InternetHealth.marginal,
          onlineEvidence: const OnlineEvidence(
            dnsResolved: true,
            publicIpObtained: true,
            cloudReachable: true,
          ),
          speedTestSkipped: skipped,
        );

    test('DECLINED: names the skip, and never says "did not complete"', () {
      final WifiVsInternetResult r = compute(skipped: true);
      expect(r.verdict, WifiVsInternetVerdict.onlineUnmeasured);
      expect(r.explanation, contains('was skipped'));
      expect(
        r.explanation,
        isNot(contains('did not complete')),
        reason: 'a test that never ran did not "fail to complete"',
      );
      expect(r.explanation, isNot(contains('Try again in a moment')),
          reason: 'never invite the user to re-spend the data they just declined');
    });

    test('STALLED: names the failure, and never claims a skip', () {
      final WifiVsInternetResult r = compute(skipped: false);
      expect(r.explanation, contains('did not complete'));
      expect(r.explanation, isNot(contains('was skipped')),
          reason: 'nothing was skipped — the test ran and failed');
    });
  });
}
