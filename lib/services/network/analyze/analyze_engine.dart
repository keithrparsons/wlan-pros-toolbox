// Analyze Results, THE RULE ENGINE (pure, testable).
//
// Input: an [AnalyzeInput] (the same data the Test My Connection result already
// holds). Output: an ordered list of [AnalysisFinding]s, conclusion-first, each
// with a severity + a plain-language explanation.
//
// PURE DART: no Flutter, no I/O, no platform channels, NOTHING stored, NOTHING
// sent. It evaluates [kAnalyzeRules] against the input and orders the matches.
// All advice copy lives in the rule DATA (analyze_rules.dart), the engine
// authors none of it, so ratified + Penn-voiced copy drops in by editing the
// rules file alone (GL-005 / GL-008).
//
// ORDERING (Pax's proposed priority/tiebreak, response-library-v1):
//   1. By severity: P1 (critical) → P2 (important) → P3 (context).
//   2. Within a severity, by the rule library's DECLARATION ORDER, which is
//      authored verdict → signal/noise → capability → internet quality → DNS →
//      security → cloud → honesty. The tiebreak is "verdict → security → worst
//      measured-quality"; verdict rules are P1 and declared first so they lead,
//      and the declaration order encodes the rest. The verdict finding is
//      ALWAYS first when present (it is the headline).
//
// CONTEXT-ONLY SUPPRESSION (Pax open-question #4): a rule marked
// [AnalyzeRule.contextOnly] (a "no problem here" reassurance: R-12 excellent
// signal, R-22 Wi-Fi 5, R-30 width-not-captured, R-42 slow-but-reachable) is
// DROPPED unless at least one non-context-only finding also fired, so the report
// never opens by narrating a non-issue. This mirrors the app's `_snrContext`
// stay-quiet discipline.

import 'analysis_finding.dart';
import 'analyze_input.dart';
import 'analyze_rules.dart';

/// The result of one analysis: the ordered findings plus a couple of derived
/// conveniences for the report view. Immutable value object.
class AnalysisReport {
  /// Creates a report from an already-ordered, already-suppressed finding list.
  const AnalysisReport(this.findings);

  /// The ordered findings, P1 → P3, verdict first. Empty when nothing fired
  /// (e.g. a wholly-unmeasured run), the UI then shows its empty state.
  final List<AnalysisFinding> findings;

  /// True when at least one finding fired.
  bool get hasFindings => findings.isNotEmpty;

  /// The single headline finding (the first in order, the verdict when one
  /// fired), or null when nothing fired.
  AnalysisFinding? get headline =>
      findings.isEmpty ? null : findings.first;

  /// The highest-priority [FindingSeverity] present, or null when empty. The
  /// report view tints its hero marker with this.
  FindingSeverity? get topSeverity =>
      findings.isEmpty ? null : findings.first.severity;

  /// True when any fired finding came from a rule still pending Keith's
  /// ratification / Penn's voice pass, the UI surfaces this honestly so the
  /// draft advice never reads as final. All rules are ratified as of 2026-06-16,
  /// so this is false today and the draft note never shows.
  bool get hasPendingDraft =>
      findings.any((AnalysisFinding f) => f.pendingRatification);
}

/// The pure analyzer. Stateless: [analyze] is a total function of its input, so
/// the whole matrix is unit-testable with plain values and no real radio.
class AnalyzeEngine {
  const AnalyzeEngine._();

  /// Evaluates every rule against [input], applies context-only suppression,
  /// orders the survivors, and returns the report.
  ///
  /// [maxFindings] optionally caps the returned list (Pax: "render the top 1–3"
  /// for the compact web widget). The in-app report view passes null to show the
  /// full ordered list (the user came for the whole picture), but the cap is
  /// available so a compact caller can take the top N.
  static AnalysisReport analyze(AnalyzeInput input, {int? maxFindings}) {
    // 1. Fire every matching rule.
    final List<_Fired> fired = <_Fired>[];
    for (int index = 0; index < kAnalyzeRules.length; index++) {
      final AnalyzeRule rule = kAnalyzeRules[index];
      bool matched;
      try {
        matched = rule.condition(input);
      } catch (_) {
        // A misbehaving predicate must never crash the analysis; treat it as a
        // non-match (defensive: the predicates are pure and total today).
        matched = false;
      }
      if (matched) fired.add(_Fired(rule, index));
    }

    // 2. Context-only suppression: drop "no problem here" notes unless a real
    //    (non-context-only) finding also fired.
    final bool hasSubstantive =
        fired.any((_Fired f) => !f.rule.contextOnly);
    final List<_Fired> kept = hasSubstantive
        ? fired
        : fired.where((_Fired f) => !f.rule.contextOnly).toList();

    // 3. Order: severity rank first (P1 → P3), then Pax's category tiebreak
    //    (verdict → security → worst measured-quality → the rest), then the
    //    rule library's declaration order as the final stable tiebreak.
    kept.sort((_Fired a, _Fired b) {
      final int bySeverity =
          a.rule.severity.rank.compareTo(b.rule.severity.rank);
      if (bySeverity != 0) return bySeverity;
      final int byCategory =
          a.rule.category.rank.compareTo(b.rule.category.rank);
      if (byCategory != 0) return byCategory;
      return a.index.compareTo(b.index);
    });

    // 4. Map to findings, optionally capping to the top N.
    Iterable<_Fired> out = kept;
    if (maxFindings != null && kept.length > maxFindings) {
      out = kept.take(maxFindings);
    }

    final List<AnalysisFinding> findings = out
        .map((_Fired f) => AnalysisFinding(
              ruleId: f.rule.id,
              category: f.rule.category,
              severity: f.rule.severity,
              explanation: f.rule.responseDraft,
              // The engine's "no problem here" reassurance rules (contextOnly)
              // surface to the screen as the §2 "Good" chip, not an advisory.
              isReassurance: f.rule.contextOnly,
              pendingRatification: f.rule.pendingRatification,
            ))
        .toList(growable: false);

    return AnalysisReport(findings);
  }
}

/// A fired rule paired with its declaration index (the stable sort tiebreak).
class _Fired {
  const _Fired(this.rule, this.index);
  final AnalyzeRule rule;
  final int index;
}
