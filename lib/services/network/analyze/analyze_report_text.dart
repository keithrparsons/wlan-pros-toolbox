// Analyze Results, the §7 COPY-REPORT plain-text serializer (pure).
//
// GL-003 §8.16 + Iris's report-visual-spec §7 CONTENT CONTRACT (load-bearing):
// the copied plain text MUST carry every on-screen verdict as its WORD, using
// the SAME [AnalysisFinding.verdictWord] the on-screen StatusChip shows, so no
// verdict survives as color-only on the clipboard (§8.13 rule 2 / SC 1.4.1).
//
// Each finding serializes as:
//   Category: Verdict-WORD
//   <plain explanation>
// in the same order shown on screen. Plain text only, no markdown, ZERO
// em-dashes (the category-and-verdict line uses a colon, not a dash).
//
// PURE DART: a total function of its inputs, so the contract is unit-testable
// with plain values. The Test My Connection screen wraps this with its run
// header (timestamp + platform); the body it shares with this function is the
// part the §7 contract governs.

import 'analyze_engine.dart';
import 'analysis_finding.dart';

/// Serializes [report]'s findings to the §7 copy body, one block per finding,
/// each leading with `Category: Verdict-WORD` so every verdict reaches the
/// clipboard in WORDS. Returns an empty string for an empty report (the caller
/// gates Copy disabled on that).
String analysisReportToPlainText(AnalysisReport report) {
  if (!report.hasFindings) return '';
  final StringBuffer buf = StringBuffer();
  for (int i = 0; i < report.findings.length; i++) {
    final AnalysisFinding f = report.findings[i];
    if (i > 0) buf.writeln('');
    // "Category: Verdict-WORD" carries the verdict in WORDS, never color.
    buf.writeln('${f.category.label}: ${f.verdictWord}');
    buf.writeln(f.explanation);
    if (f.pendingRatification) {
      buf.writeln('(Draft guidance, wording not yet finalized.)');
    }
  }
  return buf.toString().trimRight();
}
