// Analyze Results, the engine's OUTPUT model.
//
// A finding is one fired rule turned into a plain-language, conclusion-first
// explanation. The engine ([AnalyzeEngine]) evaluates the rule library
// ([kAnalyzeRules]) against an [AnalyzeInput] and returns an ordered list of
// these. The screen ([AnalyzeResultsScreen]) renders them and offers a single
// Copy affordance over the whole report.
//
// PURE DART by design: no Flutter imports, no platform channels, no I/O. The
// whole pipeline (input → rules → findings) is exhaustively unit-testable with
// plain values and no real network / radio. Nothing here is stored or sent,
// it is a local evaluation of data the Test My Connection result already holds
// (GL-005 / GL-008).

/// How load-bearing a finding is. Drives BOTH the sort order (P1 first) and the
/// §8.13 status hue the screen tints the finding's marker with, paired ALWAYS
/// with the severity WORD, never color alone (WCAG 2.2 SC 1.4.1).
///
/// Ported from the response-library priority key:
///   P1 critical/headline · P2 important · P3 context/nicety.
enum FindingSeverity {
  /// P1, critical / headline. A verdict, an open network, packet loss, a dead
  /// path. Renders with the §8.13 danger hue.
  critical,

  /// P2, important. A weak signal, an older standard, a high-latency path.
  /// Renders with the §8.13 warning hue.
  important,

  /// P3, context / nicety. A "no problem here" reassurance or a low-stakes
  /// note. Renders with the §8.13 info hue. Context-only findings are
  /// suppressed by the engine unless a P1/P2 also fired (see [AnalyzeRule]).
  context,
}

/// The numeric rank used to sort findings (lower = higher priority). Kept off
/// the enum so the ordering is explicit and testable.
extension FindingSeverityRank on FindingSeverity {
  /// 1 for [critical], 2 for [important], 3 for [context].
  int get rank {
    switch (this) {
      case FindingSeverity.critical:
        return 1;
      case FindingSeverity.important:
        return 2;
      case FindingSeverity.context:
        return 3;
    }
  }

  /// The short, all-caps severity WORD shown beside each finding (never color
  /// alone, SC 1.4.1). Plain English, not jargon.
  String get word {
    switch (this) {
      case FindingSeverity.critical:
        return 'ACTION';
      case FindingSeverity.important:
        return 'WORTH A LOOK';
      case FindingSeverity.context:
        return 'CONTEXT';
    }
  }
}

/// The broad subject a finding belongs to. Mirrors the response-library
/// category grouping (Verdict, Signal, Noise/SNR, Capability, Internet quality,
/// DNS, Security, Cloud reachability, Honesty/guard). Used for grouping/labels
/// and to let the verdict category always lead.
enum FindingCategory {
  verdict,
  signal,
  noise,
  capability,
  internetQuality,
  dns,
  security,
  cloudReachability,
  honesty,
}

/// The within-severity tiebreak rank for a category (lower sorts first). Encodes
/// the proposed tiebreak: verdict → security → worst measured-quality → the
/// rest, so that at EQUAL severity an open-network security finding leads a
/// packet-loss finding, and both lead a band/capability note. The verdict is P1
/// and rank 0, so it always leads overall.
extension FindingCategoryRank on FindingCategory {
  int get rank {
    switch (this) {
      case FindingCategory.verdict:
        return 0;
      case FindingCategory.security:
        return 1;
      // The measured-quality families ("worst measured-quality"): the
      // internet path, then the signal/noise that explain a weak link.
      case FindingCategory.internetQuality:
        return 2;
      case FindingCategory.signal:
        return 3;
      case FindingCategory.noise:
        return 4;
      case FindingCategory.cloudReachability:
        return 5;
      case FindingCategory.capability:
        return 6;
      case FindingCategory.dns:
        return 7;
      case FindingCategory.honesty:
        return 8;
    }
  }
}

/// Human-readable label for a [FindingCategory], shown as the small eyebrow
/// above a finding.
extension FindingCategoryLabel on FindingCategory {
  String get label {
    switch (this) {
      case FindingCategory.verdict:
        return 'Verdict';
      case FindingCategory.signal:
        return 'Signal';
      case FindingCategory.noise:
        return 'Noise & interference';
      case FindingCategory.capability:
        return 'Band & capability';
      case FindingCategory.internetQuality:
        return 'Internet quality';
      case FindingCategory.dns:
        return 'DNS';
      case FindingCategory.security:
        return 'Security';
      case FindingCategory.cloudReachability:
        return 'Cloud reachability';
      case FindingCategory.honesty:
        return 'What was measured';
    }
  }
}

/// One fired rule, rendered as a finding: its id (for traceability + tests),
/// its category, its severity, and the plain-language explanation. Immutable.
///
/// The [explanation] is the rule's response text VERBATIM, the final,
/// Keith-ratified (2026-06-16) + Penn-voiced copy from response-library-final.
/// Because the copy lives in the rule data ([AnalyzeRule]), any future revoice
/// drops in by editing [kAnalyzeRules] alone, no engine or model change.
/// [pendingRatification] would flag a rule whose copy is not yet ratified; all
/// rules are ratified today, so it is false everywhere, but the field and its
/// surfacing path are kept for any future not-yet-final rule.
class AnalysisFinding {
  /// Creates a finding.
  const AnalysisFinding({
    required this.ruleId,
    required this.category,
    required this.severity,
    required this.explanation,
    this.isReassurance = false,
    this.pendingRatification = false,
  });

  /// The originating rule id (e.g. "R-01"), for tests + report traceability.
  final String ruleId;

  /// The subject category, drives grouping and the verdict-leads ordering.
  final FindingCategory category;

  /// How load-bearing the finding is, drives sort order + the §8.13 hue.
  final FindingSeverity severity;

  /// The conclusion-first, plain-language explanation. Rule data, swappable.
  final String explanation;

  /// True for a "no problem here" reassurance (the engine's `contextOnly`
  /// rules: R-12 excellent signal, R-22 Wi-Fi 5). The screen renders these with
  /// the §2 "Good" chip (success), not an advisory, so a genuine all-clear
  /// never wears a warning hue. A non-reassurance P3 note (slow DNS, an
  /// overlapping channel, R-18's strong-signal-but-low-rate advisory) stays a
  /// "Worth a look" — R-18 flags that SOMETHING is in the way, so it is
  /// deliberately NOT `contextOnly` and must not be listed as a reassurance.
  final bool isReassurance;

  /// True when the source rule's copy is not yet ratified / voiced. Surfaced
  /// honestly so nothing reads as final before it is. All rules are ratified as
  /// of 2026-06-16, so this is false for every finding today.
  final bool pendingRatification;

  /// True when this finding is the report's leading verdict (category
  /// [FindingCategory.verdict]). The screen promotes it to the §1 verdict hero
  /// rather than rendering it as a finding card.
  bool get isVerdict => category == FindingCategory.verdict;

  /// True when this finding is an honesty / "not measured" row
  /// ([FindingCategory.honesty]). The screen renders these as quiet §6 info
  /// rows at the bottom, never as amber / red findings.
  bool get isHonesty => category == FindingCategory.honesty;

  /// The plain-language verdict WORD shown in the §2 status chip AND written to
  /// the §7 copied report, so the verdict is identical on screen and on the
  /// clipboard and never survives as color-only (§8.13 rule 2 / SC 1.4.1).
  ///
  /// PURE presentation (no Flutter): both the screen's chip and the copy-text
  /// builder read this one getter, so the on-screen word and the clipboard word
  /// can never drift. Honesty rows read "Not measured"; a reassurance reads
  /// "Good"; otherwise the word follows the severity (Issue / Worth a look),
  /// with the all-clear verdict headline (R-04, "nothing to fix") reading
  /// "Good".
  String get verdictWord {
    if (isHonesty) return 'Not measured';
    if (isReassurance) return 'Good';
    switch (severity) {
      case FindingSeverity.critical:
        return 'Issue';
      case FindingSeverity.important:
        // The all-clear verdict headline is reassurance, not an advisory. R-04
        // is "nothing to fix"; R-06 is the honest "you are online" verdict when
        // the speed test stalled but reachability is strong, also reassuring.
        return (ruleId == 'R-04' || ruleId == 'R-06') ? 'Good' : 'Worth a look';
      case FindingSeverity.context:
        // Non-reassurance P3 notes (slow DNS, overlapping channel, WPA2 nudge)
        // are minor advisories, not all-clears.
        return 'Worth a look';
    }
  }


  @override
  String toString() =>
      'AnalysisFinding($ruleId, ${severity.name}, ${category.name})';
}
