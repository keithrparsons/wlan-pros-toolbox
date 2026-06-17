// Analyze Results — rule engine unit tests.
//
// Pure-value tests: build an [AnalyzeInput] with plain numbers, run the
// [AnalyzeEngine], assert the fired rules, their order, severity, context-only
// suppression, the pending-draft flag, and that the thresholds match the SAME
// ratified app constants the rest of the app uses (no duplicated numbers).

import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart' show QualityScoring, QualityGrade;
import 'package:wlan_pros_toolbox/services/network/analyze/analysis_finding.dart';
import 'package:wlan_pros_toolbox/services/network/analyze/analyze_engine.dart';
import 'package:wlan_pros_toolbox/services/network/analyze/analyze_input.dart';
import 'package:wlan_pros_toolbox/services/network/analyze/analyze_rules.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_grading.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_security.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_vs_internet.dart';

/// Convenience: the set of fired rule ids for an input.
Set<String> _firedIds(AnalyzeInput input) => AnalyzeEngine.analyze(input)
    .findings
    .map((AnalysisFinding f) => f.ruleId)
    .toSet();

void main() {
  group('rule library shape', () {
    test('implements every response-library-v1 table rule except the parser '
        'guard, across all 9 categories', () {
      // Pax's response-library-v1 enumerates rules R-01..R-42 in its category
      // tables plus R-50 (a PARSER guard for the future web "paste a report"
      // surface). This in-app engine reads live in-memory objects, not pasted
      // text, so R-50 has no analogue and is intentionally omitted (see the note
      // in analyze_rules.dart). Every other table rule is ported → 32 rules.
      expect(kAnalyzeRules.length, 32);
      final Set<FindingCategory> cats =
          kAnalyzeRules.map((r) => r.category).toSet();
      expect(cats.length, FindingCategory.values.length); // all 9
      // R-50 is deliberately absent.
      expect(
        kAnalyzeRules.map((r) => r.id), isNot(contains('R-50')),
      );
    });

    test('every rule id is unique', () {
      final List<String> ids = kAnalyzeRules.map((r) => r.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('the two doctrine guardrails are flagged pendingRatification', () {
      final r20 = kAnalyzeRules.firstWhere((r) => r.id == 'R-20');
      final r23 = kAnalyzeRules.firstWhere((r) => r.id == 'R-23');
      expect(r20.pendingRatification, isTrue,
          reason: 'R-20 (2.4 GHz) must be flagged pending Keith');
      expect(r23.pendingRatification, isTrue,
          reason: 'R-23 (narrow width) must be flagged pending Keith');
    });
  });

  group('verdict rules (R-01..R-05) lead', () {
    test('wifiLimiter → R-01 leads, critical', () {
      final report = AnalyzeEngine.analyze(
        const AnalyzeInput(verdict: WifiVsInternetVerdict.wifiLimiter),
      );
      expect(report.headline!.ruleId, 'R-01');
      expect(report.headline!.severity, FindingSeverity.critical);
      expect(report.headline!.category, FindingCategory.verdict);
    });

    test('each verdict maps to its rule', () {
      expect(
        _firedIds(const AnalyzeInput(
            verdict: WifiVsInternetVerdict.upstream)),
        contains('R-02'),
      );
      expect(
        _firedIds(const AnalyzeInput(
            verdict: WifiVsInternetVerdict.bothContributing)),
        contains('R-03'),
      );
      expect(
        _firedIds(const AnalyzeInput(
            verdict: WifiVsInternetVerdict.bothHealthy)),
        contains('R-04'),
      );
      expect(
        _firedIds(const AnalyzeInput(
            verdict: WifiVsInternetVerdict.wifiUnknown)),
        contains('R-05'),
      );
    });

    test('the verdict finding is always first even when other rules fire', () {
      // wifiLimiter verdict + an open network (R-35, also critical) + poor loss
      // (R-25, critical). Verdict must still lead.
      final report = AnalyzeEngine.analyze(
        const AnalyzeInput(
          verdict: WifiVsInternetVerdict.wifiLimiter,
          security: WifiSecurity.open,
          lossPct: 5,
        ),
      );
      expect(report.findings.first.ruleId, 'R-01');
      // Security comes before the measured-quality loss finding (Pax tiebreak:
      // verdict → security → worst measured-quality).
      final ids = report.findings.map((f) => f.ruleId).toList();
      expect(ids.indexOf('R-35'), lessThan(ids.indexOf('R-25')));
    });
  });

  group('RSSI rules use the ratified WifiGradingBands', () {
    test('poor RSSI fires R-10', () {
      // Below the Fair floor (-72) → Poor.
      final rssi = WifiGradingBands.rssiFairDbm - 1; // -73
      expect(WifiGrading.gradeRssi(rssi), QualityGrade.poor);
      expect(_firedIds(AnalyzeInput(rssiDbm: rssi)), contains('R-10'));
    });

    test('excellent RSSI alone is suppressed (context-only)', () {
      // R-12 is context-only: with no other finding it must NOT render.
      final rssi = WifiGradingBands.rssiExcellentDbm; // -59
      expect(WifiGrading.gradeRssi(rssi), QualityGrade.excellent);
      expect(_firedIds(AnalyzeInput(rssiDbm: rssi)), isNot(contains('R-12')));
    });

    test('excellent RSSI renders when a real finding also fired', () {
      final rssi = WifiGradingBands.rssiExcellentDbm; // -59 excellent
      final report = AnalyzeEngine.analyze(
        AnalyzeInput(rssiDbm: rssi, lossPct: 5), // loss poor → R-25
      );
      final ids = report.findings.map((f) => f.ruleId).toSet();
      expect(ids, containsAll(<String>['R-25', 'R-12']));
    });
  });

  group('SNR + rate context rules', () {
    test('poor SNR fires R-15', () {
      final snr = WifiGradingBands.snrFairDb - 1; // 14 → poor
      expect(_firedIds(AnalyzeInput(snrDb: snr)), contains('R-15'));
    });

    test('weak SNR + low link rate fires R-17 (app 200 Mbps constant)', () {
      expect(kLowLinkRateMbps, 200);
      final report = AnalyzeEngine.analyze(
        const AnalyzeInput(snrDb: 20, linkRateMbps: 100),
      );
      expect(report.findings.map((f) => f.ruleId), contains('R-17'));
    });

    test('strong SNR + low link rate fires R-18 (context-only, needs sibling)',
        () {
      // R-18 is context-only: paired here with the verdict so it surfaces.
      final report = AnalyzeEngine.analyze(
        const AnalyzeInput(
          snrDb: 40,
          linkRateMbps: 100,
          verdict: WifiVsInternetVerdict.wifiLimiter,
        ),
      );
      expect(report.findings.map((f) => f.ruleId), contains('R-18'));
    });
  });

  group('band / PHY / width doctrine guardrails', () {
    test('2.4 GHz with a modern PHY fires R-20 and is marked pending', () {
      final report = AnalyzeEngine.analyze(
        const AnalyzeInput(band: '2.4 GHz', standard: '802.11ax (Wi-Fi 6)'),
      );
      final r20 = report.findings.firstWhere((f) => f.ruleId == 'R-20');
      expect(r20.pendingRatification, isTrue);
      // The honest trade-off wording must carry the trade-off AND explicitly
      // disclaim a blanket "always switch" recommendation (the doctrine
      // guardrail — never tell users to blanket-switch bands).
      expect(r20.explanation.toLowerCase(), contains('trade-off'));
      expect(r20.explanation.toLowerCase(),
          contains('not a blanket "always switch"'));
    });

    test('narrow width on a fast band fires R-23 and never says force 160', () {
      final report = AnalyzeEngine.analyze(
        const AnalyzeInput(
          band: '5 GHz',
          channelWidthMhz: 20,
          channelWidthAvailable: true,
          verdict: WifiVsInternetVerdict.wifiLimiter, // sibling so R-23 surfaces
        ),
      );
      final r23 = report.findings.firstWhere((f) => f.ruleId == 'R-23');
      expect(r23.pendingRatification, isTrue);
      expect(r23.explanation.toLowerCase(), contains('not'));
      expect(r23.explanation, contains('160 MHz'));
      expect(r23.explanation.toLowerCase(),
          isNot(contains('force 160 mhz to')));
    });

    test('legacy PHY fires R-21; Wi-Fi 5 does not match legacy', () {
      expect(
        _firedIds(const AnalyzeInput(standard: '802.11n (Wi-Fi 4)')),
        contains('R-21'),
      );
      expect(
        _firedIds(const AnalyzeInput(
            standard: '802.11ac (Wi-Fi 5)',
            verdict: WifiVsInternetVerdict.wifiLimiter)),
        isNot(contains('R-21')),
      );
    });

    test('2.4 GHz channel outside 1/6/11 fires R-24', () {
      expect(
        _firedIds(const AnalyzeInput(band: '2.4 GHz', channel: 3)),
        contains('R-24'),
      );
      expect(
        _firedIds(const AnalyzeInput(band: '2.4 GHz', channel: 6)),
        isNot(contains('R-24')),
      );
    });
  });

  group('internet-quality rules use QualityScoring bands', () {
    test('poor loss fires R-25 (matches scoring.dart)', () {
      expect(QualityScoring.gradeLossPct(2.5), QualityGrade.poor);
      expect(_firedIds(const AnalyzeInput(lossPct: 2.5)), contains('R-25'));
    });

    test('poor latency fires R-26', () {
      expect(QualityScoring.gradeLatencyMs(100), QualityGrade.poor);
      expect(_firedIds(const AnalyzeInput(latencyMs: 100)), contains('R-26'));
    });

    test('good speed + bad quality fires R-29', () {
      // download 200 (excellent) + loss 5 (poor) → speed-fine-quality-bad.
      final report = AnalyzeEngine.analyze(
        const AnalyzeInput(downloadMbps: 200, lossPct: 5),
      );
      expect(report.findings.map((f) => f.ruleId), contains('R-29'));
    });
  });

  group('security rules', () {
    test('open network fires R-35 critical', () {
      final report =
          AnalyzeEngine.analyze(const AnalyzeInput(security: WifiSecurity.open));
      final f = report.findings.firstWhere((f) => f.ruleId == 'R-35');
      expect(f.severity, FindingSeverity.critical);
    });

    test('WEP fires R-36 critical', () {
      expect(_firedIds(const AnalyzeInput(security: WifiSecurity.wep)),
          contains('R-36'));
    });
  });

  group('cloud reachability', () {
    test('0 of M reachable (internet measured) fires R-40', () {
      expect(
        _firedIds(const AnalyzeInput(
          cloudReachableCount: 0,
          cloudTotalCount: 14,
          internetMeasured: true,
        )),
        contains('R-40'),
      );
    });

    test('mixed reachability fires R-41', () {
      expect(
        _firedIds(const AnalyzeInput(
            cloudReachableCount: 8, cloudTotalCount: 14)),
        contains('R-41'),
      );
    });
  });

  group('honesty / null discipline', () {
    test('unmeasured input fires nothing — empty report, honest', () {
      final report = AnalyzeEngine.analyze(const AnalyzeInput());
      expect(report.hasFindings, isFalse);
      expect(report.headline, isNull);
    });

    test('iOS without Wi-Fi capture fires R-31', () {
      expect(
        _firedIds(const AnalyzeInput(
            platformIsIos: true, wifiSignalCaptured: false)),
        contains('R-31'),
      );
    });

    test('width-not-captured (R-30) is context-only, suppressed alone', () {
      // band present, width not available → R-30 condition true, but it is
      // context-only and nothing substantive fired, so it is suppressed.
      expect(
        _firedIds(const AnalyzeInput(
            band: '5 GHz', channelWidthAvailable: false)),
        isNot(contains('R-30')),
      );
    });

    test('hasPendingDraft is true when a pending rule fired', () {
      final report = AnalyzeEngine.analyze(
        const AnalyzeInput(band: '2.4 GHz', standard: '802.11ax (Wi-Fi 6)'),
      );
      expect(report.hasPendingDraft, isTrue);
    });
  });

  group('ordering + cap', () {
    test('findings are sorted critical → important → context', () {
      final report = AnalyzeEngine.analyze(
        const AnalyzeInput(
          verdict: WifiVsInternetVerdict.wifiLimiter, // R-01 critical
          rssiDbm: -73, // R-10 important
          standard: '802.11ac (Wi-Fi 5)', // R-22 context-only
        ),
      );
      final ranks =
          report.findings.map((f) => f.severity.rank).toList();
      final sorted = <int>[...ranks]..sort();
      expect(ranks, sorted);
    });

    test('maxFindings caps the returned list', () {
      final report = AnalyzeEngine.analyze(
        const AnalyzeInput(
          verdict: WifiVsInternetVerdict.wifiLimiter,
          security: WifiSecurity.open,
          lossPct: 5,
        ),
        maxFindings: 2,
      );
      expect(report.findings.length, 2);
    });
  });

  group('every fired rule carries non-empty conclusion-first copy', () {
    test('explanations are non-empty for all rules', () {
      for (final rule in kAnalyzeRules) {
        expect(rule.responseDraft.trim(), isNotEmpty, reason: rule.id);
      }
    });
  });
}
