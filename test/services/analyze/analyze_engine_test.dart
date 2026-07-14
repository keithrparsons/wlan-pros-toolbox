// Analyze Results, rule engine unit tests.
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
import 'package:wlan_pros_toolbox/services/network/analyze/analyze_report_text.dart';
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
      // in analyze_rules.dart). Every other table rule is ported → 32 rules,
      // plus R-06 (the honest "you are online" verdict added 2026-06-17 for the
      // stalled-speed-test-but-reachable case) → 33, plus R-05N (the not-on-Wi-Fi
      // half of the `wifiUnknown` verdict, split out 2026-07-13) → 34, plus R-06S
      // (the speed-test-SKIPPED half of `onlineUnmeasured`, split out the same day
      // when the cellular-data consent gate landed — see below) → 35.
      expect(kAnalyzeRules.length, 35);
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

    test('no rule tells a user with NO Wi-Fi link to install the Wi-Fi Shortcut',
        () {
      // THE MECHANICAL GUARD (2026-07-13). Suppressing R-31 was not enough: R-05
      // carried the SAME advice ("install the companion Shortcut") through a
      // different rule, and Keith hit it on a cellular-only iPhone. Rather than
      // patch rules one at a time as they are discovered, assert the property
      // over the WHOLE library: fire every rule that a not-on-Wi-Fi device can
      // fire, and let no Shortcut/capture advice through.
      const AnalyzeInput cellularOnly = AnalyzeInput(
        verdict: WifiVsInternetVerdict.wifiUnknown,
        platformIsIos: true,
        wifiSignalCaptured: false,
        notOnWifi: true,
        internetMeasured: true,
        downloadMbps: 60,
        uploadMbps: 20,
      );
      final AnalysisReport report = AnalyzeEngine.analyze(cellularOnly);

      for (final AnalysisFinding f in report.findings) {
        final String text = f.explanation.toLowerCase();
        expect(text, isNot(contains('shortcut')),
            reason: '${f.ruleId} tells a device with no Wi-Fi link to use the '
                'companion Shortcut. No Shortcut can read a link that does not '
                'exist (GL-005, two kinds of null).');
        expect(text, isNot(contains('capture wi-fi details')),
            reason: '${f.ruleId} offers a capture for a link that is not there');
      }
    });

    test('all rules are ratified, no rule is flagged pendingRatification', () {
      // Keith ratified the rules 2026-06-16; the copy is Penn-voiced and final.
      // No rule may still read as draft.
      for (final rule in kAnalyzeRules) {
        expect(rule.pendingRatification, isFalse,
            reason: '${rule.id} must be ratified (not pending) post 2026-06-16');
      }
    });
  });

  group('verdict rules (R-01..R-06) lead', () {
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
      expect(
        _firedIds(const AnalyzeInput(
            verdict: WifiVsInternetVerdict.onlineUnmeasured)),
        contains('R-06'),
      );
    });

    test('wifiUnknown splits on WHY: R-05 when the read failed, R-05N when there '
        'is no Wi-Fi link', () {
      // The SAME verdict, two different truths (GL-005). R-05's copy ("one side
      // could not be measured", "install the companion Shortcut") is correct for a
      // link we failed to READ, and false for a link that does not EXIST. Exactly
      // one of the two must fire — never both, never neither.
      final Set<String> readFailed = _firedIds(const AnalyzeInput(
        verdict: WifiVsInternetVerdict.wifiUnknown,
      )).toSet();
      expect(readFailed, contains('R-05'));
      expect(readFailed, isNot(contains('R-05N')));

      final Set<String> noLink = _firedIds(const AnalyzeInput(
        verdict: WifiVsInternetVerdict.wifiUnknown,
        notOnWifi: true,
      )).toSet();
      expect(noLink, contains('R-05N'),
          reason: 'a cellular-only phone must get the honest "you are not on '
              'Wi-Fi, that is not a failed reading" finding');
      expect(noLink, isNot(contains('R-05')),
          reason: 'and must NOT be told one side "could not be measured" or to '
              'install a Shortcut to read a link that does not exist');
    });

    test(
      'onlineUnmeasured → R-06 leads with the honest "you are online" verdict, '
      'reads "Good", never "could not read"',
      () {
        final report = AnalyzeEngine.analyze(
          const AnalyzeInput(
            verdict: WifiVsInternetVerdict.onlineUnmeasured,
          ),
        );
        expect(report.headline!.ruleId, 'R-06');
        expect(report.headline!.category, FindingCategory.verdict);
        // Calm, reassuring verdict word — not an advisory.
        expect(report.headline!.verdictWord, 'Good');
        expect(report.headline!.explanation, contains('You are online'));
        expect(report.headline!.explanation, contains('reachable'));
        expect(report.headline!.explanation, isNot(contains('could not read')));
        // R-05 (partial read) must NOT also fire for this distinct verdict.
        expect(_firedIds(const AnalyzeInput(
            verdict: WifiVsInternetVerdict.onlineUnmeasured)),
            isNot(contains('R-05')));
      },
    );

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

  group('RSSI rules grade on Keith\'s canonical bands', () {
    // Expected grades are HAND-DERIVED from Keith's confirmed bands, never read
    // back from WifiGradingBands — the 1.7.1 failure mode (F2) was tests that
    // derived their expected values from the very constant under test, so a
    // wrong constant stayed green. Literals below fail if the bands ever drift.
    test('poor RSSI (-73, Keith\'s Poor floor) fires R-10', () {
      const int rssi = -73; // Poor: -73 or weaker.
      expect(WifiGrading.gradeRssi(rssi), QualityGrade.poor);
      expect(_firedIds(const AnalyzeInput(rssiDbm: rssi)), contains('R-10'));
    });

    test('excellent RSSI (-59, i.e. > -60) alone is suppressed (context-only)',
        () {
      // R-12 is context-only: with no other finding it must NOT render.
      const int rssi = -59; // Excellent: rssi > -60.
      expect(WifiGrading.gradeRssi(rssi), QualityGrade.excellent);
      expect(
        _firedIds(const AnalyzeInput(rssiDbm: rssi)),
        isNot(contains('R-12')),
      );
    });

    test('excellent RSSI renders when a real finding also fired', () {
      const int rssi = -59; // Excellent: rssi > -60.
      final report = AnalyzeEngine.analyze(
        const AnalyzeInput(rssiDbm: rssi, lossPct: 5), // loss poor → R-25
      );
      final ids = report.findings.map((f) => f.ruleId).toSet();
      expect(ids, containsAll(<String>['R-25', 'R-12']));
    });
  });

  group('SNR + rate context rules', () {
    test('poor SNR (14, below the 15 dB Fair floor) fires R-15', () {
      const int snr = 14; // Poor: snr < 15.
      expect(_firedIds(const AnalyzeInput(snrDb: snr)), contains('R-15'));
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
    test('2.4 GHz with a modern PHY fires R-20, ratified, keeps honest caveat',
        () {
      final report = AnalyzeEngine.analyze(
        const AnalyzeInput(band: '2.4 GHz', standard: '802.11ax (Wi-Fi 6)'),
      );
      final r20 = report.findings.firstWhere((f) => f.ruleId == 'R-20');
      expect(r20.pendingRatification, isFalse);
      // The ratified copy must keep the honest 2.4 GHz caveat (the doctrine
      // guardrail: never tell users to blanket-switch bands).
      expect(r20.explanation.toLowerCase(), contains('honest caveat'));
      expect(r20.explanation.toLowerCase(),
          contains('the right choice on purpose'));
      // It must never issue a blanket "always switch" instruction.
      expect(r20.explanation.toLowerCase(), isNot(contains('always switch')));
    });

    test('narrow width on a fast band fires R-23, ratified, never forces wide',
        () {
      final report = AnalyzeEngine.analyze(
        const AnalyzeInput(
          band: '5 GHz',
          channelWidthMhz: 20,
          channelWidthAvailable: true,
          verdict: WifiVsInternetVerdict.wifiLimiter, // sibling so R-23 surfaces
        ),
      );
      final r23 = report.findings.firstWhere((f) => f.ruleId == 'R-23');
      expect(r23.pendingRatification, isFalse);
      // The ratified copy keeps the "wider is not automatically better"
      // guardrail and tells a crowded-area user to leave the channel alone.
      expect(r23.explanation.toLowerCase(),
          contains('wider is not automatically better'));
      expect(r23.explanation.toLowerCase(),
          contains('leave it where it is'));
      // It must never tell anyone to force a wide channel.
      expect(r23.explanation.toLowerCase(), isNot(contains('force')));
      expect(r23.explanation, isNot(contains('160 MHz')));
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

    // Regression: 802.11be (Wi-Fi 7) must NOT be misread as legacy. The
    // case-insensitive substring "802.11b" also matched "802.11be", so every
    // Wi-Fi 7 device wrongly tripped R-21 ("802.11n or earlier"). A real beta
    // tester on "802.11be - Wi-Fi 7" (Tx 1921 / Rx 2041 Mbps) saw this.
    group('802.11be (Wi-Fi 7) legacy-classification regression', () {
      const String wifi7 = '802.11be - Wi-Fi 7'; // exact iOS Shortcut string
      const double wifi7Rate = 1981; // avg(1921, 2041)

      test('802.11be is NOT legacy (the bug case)', () {
        expect(const AnalyzeInput(standard: wifi7).isLegacyPhy, isFalse);
      });

      test('802.11be is NOT flagged by R-21 or R-22, end to end', () {
        // The beta tester's real reading: Wi-Fi 7, fast link rate, no problems.
        final Set<String> ids = _firedIds(const AnalyzeInput(
          standard: wifi7,
          linkRateMbps: wifi7Rate,
        ));
        expect(ids, isNot(contains('R-21')));
        expect(ids, isNot(contains('R-22')));
      });

      test('802.11be is recognized as modern (Wi-Fi 6+)', () {
        // _isWifi6Plus is private, so assert via R-20: a modern PHY on the
        // 2.4 GHz band fires the "use a faster band" finding; a legacy PHY
        // would not. This proves be reads as modern, not legacy.
        final Set<String> ids = _firedIds(const AnalyzeInput(
          band: '2.4 GHz',
          standard: wifi7,
        ));
        expect(ids, contains('R-20'));
        expect(ids, isNot(contains('R-21')));
      });

      test('real legacy 802.11b labels still classify as legacy (no regression)',
          () {
        // The labels the app actually produces: macOS emits a bare "802.11b"
        // (pre-branding modes get no Wi-Fi generation); iOS emits the dash
        // form; a parenthesized form is also covered defensively.
        for (final String legacy in <String>[
          '802.11b',
          '802.11b - Wi-Fi 1',
          '802.11b (Wi-Fi 1)',
        ]) {
          expect(AnalyzeInput(standard: legacy).isLegacyPhy, isTrue,
              reason: '"$legacy" must read as legacy');
          expect(_firedIds(AnalyzeInput(standard: legacy)), contains('R-21'),
              reason: '"$legacy" must fire R-21');
        }
      });

      test('802.11ac is Wi-Fi 5 (not legacy); 802.11ax/be are not legacy', () {
        const AnalyzeInput ac = AnalyzeInput(standard: '802.11ac (Wi-Fi 5)');
        expect(ac.isWifi5Phy, isTrue);
        expect(ac.isLegacyPhy, isFalse);

        expect(
            const AnalyzeInput(standard: '802.11ax (Wi-Fi 6)').isLegacyPhy,
            isFalse);
        expect(const AnalyzeInput(standard: wifi7).isLegacyPhy, isFalse);
      });
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
    test('unmeasured input fires nothing, empty report, honest', () {
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

    test('iOS with NO WI-FI AT ALL does NOT fire R-31 (cold-eyes F2)', () {
      // THE TWO KINDS OF NULL (GL-005). `wifiSignalCaptured: false` arrives here
      // for two completely different devices:
      //   * on Wi-Fi, RF not harvested yet  → R-31's "tap Capture Wi-Fi details,
      //     which uses the companion Shortcut" is exactly right;
      //   * NOT on Wi-Fi at all             → there is no link to capture, so that
      //     same advice sends the user chasing a read that cannot exist. It is the
      //     same wrong-kind-of-null failure as the stale-reading bug, wearing the
      //     Analyze report as a costume.
      // The Analyze screen is the FOURTH surface that inverted the meaning of the
      // suppressed RF (after the Wi-Fi link card, the copy report, and the Shortcut
      // offer card) and the only one the cold-eyes review did not list.
      expect(
        _firedIds(const AnalyzeInput(
          platformIsIos: true,
          wifiSignalCaptured: false,
          notOnWifi: true,
        )),
        isNot(contains('R-31')),
        reason: 'no Shortcut can capture a Wi-Fi link that does not exist',
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

    test('hasPendingDraft is false now that every rule is ratified', () {
      // Post 2026-06-16 ratification, no rule is pending, so the draft note
      // never triggers regardless of which rules fire.
      final report = AnalyzeEngine.analyze(
        const AnalyzeInput(band: '2.4 GHz', standard: '802.11ax (Wi-Fi 6)'),
      );
      expect(report.hasPendingDraft, isFalse);
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

  group('verdict words (the §2 chip word / §7 clipboard word)', () {
    test('severity + reassurance map to the right plain word', () {
      // Critical -> "Issue".
      final AnalysisFinding open = AnalyzeEngine.analyze(
        const AnalyzeInput(security: WifiSecurity.open),
      ).findings.first;
      expect(open.verdictWord, 'Issue');

      // Important advisory -> "Worth a look" (weak RSSI, R-10).
      final AnalysisFinding weak = AnalyzeEngine.analyze(
        const AnalyzeInput(rssiDbm: -73),
      ).findings.firstWhere((AnalysisFinding f) => f.ruleId == 'R-10');
      expect(weak.verdictWord, 'Worth a look');

      // The all-clear verdict headline (R-04) -> "Good".
      final AnalysisFinding allClear = AnalyzeEngine.analyze(
        const AnalyzeInput(verdict: WifiVsInternetVerdict.bothHealthy),
      ).findings.first;
      expect(allClear.ruleId, 'R-04');
      expect(allClear.verdictWord, 'Good');

      // A reassurance (contextOnly) -> "Good".
      final AnalysisFinding reassure = AnalyzeEngine.analyze(
        const AnalyzeInput(
          verdict: WifiVsInternetVerdict.upstream, // a substantive finding
          rssiDbm: -45, // excellent RSSI -> R-12 reassurance
        ),
      ).findings.firstWhere((AnalysisFinding f) => f.ruleId == 'R-12');
      expect(reassure.isReassurance, isTrue);
      expect(reassure.verdictWord, 'Good');

      // An honesty row -> "Not measured".
      final AnalysisFinding honesty = AnalyzeEngine.analyze(
        const AnalyzeInput(platformIsIos: true, wifiSignalCaptured: false),
      ).findings.firstWhere((AnalysisFinding f) => f.isHonesty);
      expect(honesty.verdictWord, 'Not measured');
    });
  });

  group('§7 copy content contract', () {
    test('copied report text carries EVERY finding verdict WORD (never '
        'color-only on the clipboard)', () {
      // A report spanning every verdict register: Issue (open security),
      // Worth a look (weak RSSI), Good (excellent-signal reassurance), and
      // Not measured (the iOS honesty row).
      final AnalysisReport report = AnalyzeEngine.analyze(
        const AnalyzeInput(
          verdict: WifiVsInternetVerdict.upstream,
          security: WifiSecurity.open, // -> Issue
          rssiDbm: -73, // poor -> Worth a look (R-10)
          platformIsIos: true,
          wifiSignalCaptured: false, // -> Not measured (R-31)
        ),
      );
      final String text = analysisReportToPlainText(report);

      // Every finding's verdict WORD appears in the copied text, in words.
      for (final AnalysisFinding f in report.findings) {
        expect(
          text,
          contains(f.verdictWord),
          reason: '${f.ruleId} verdict word "${f.verdictWord}" missing from '
              'copied report',
        );
        // And each finding's category label is paired with its word.
        expect(text, contains('${f.category.label}: ${f.verdictWord}'));
      }

      // Spot-check the load-bearing words are literally present.
      expect(text, contains('Issue'));
      expect(text, contains('Worth a look'));
      expect(text, contains('Not measured'));

      // Zero em-dashes on the clipboard (U+2014 referenced by code unit so no
      // literal em-dash glyph appears in source, per the standing rule).
      expect(text.contains(String.fromCharCode(0x2014)), isFalse);
    });

    test('empty report serializes to an empty string', () {
      final AnalysisReport empty = AnalyzeEngine.analyze(const AnalyzeInput());
      expect(empty.hasFindings, isFalse);
      expect(analysisReportToPlainText(empty), isEmpty);
    });
  });
}
