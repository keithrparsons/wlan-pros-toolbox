// Analyze Results — the in-app report view (GL-003 App Mode).
//
// Reached by tapping "Analyze" on the Test My Connection results screen,
// ALONGSIDE Copy (Copy = save the raw report for support; Analyze = this local,
// plain-language explanation). It runs the pure [AnalyzeEngine] over the SAME
// result data already on screen, LOCALLY — no network call, nothing stored,
// nothing leaves the device. Findings are rendered conclusion-first, ordered by
// severity (verdict leads), each carrying its severity WORD + a §8.13 status
// hue (never color alone — SC 1.4.1). A Copy action on the report saves the
// whole thing.
//
// Tokens used (all semantic, GL-003): surface1 cards + §8.1 border, §8.13
// status colors (danger/warning/info, paired with the word), textPrimary/
// secondary/tertiary, §3 type scale via the M3 TextTheme, §4/§8.7 spacing,
// §8.11 radii, §8.16 AppCopyAction, §8.16.1 ToolHelpFooter.
//
// DRAFT-COPY HONESTY: the finding text is Pax's DRAFT pending Keith's
// ratification + Penn's SOP-020 voice pass. When any rendered finding comes
// from a still-pending rule, the screen shows an honest "draft advice" note so
// the copy never reads as final (GL-005). Remove the note once the rules ship
// ratified.

import 'package:flutter/material.dart';

import '../../../services/network/analyze/analysis_finding.dart';
import '../../../services/network/analyze/analyze_engine.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/centered_content.dart';
import '../../../widgets/tool_help_footer.dart';

/// The Analyze Results report screen. Stateless: it receives an already-computed
/// [AnalysisReport] (the caller runs the engine over its live result data) plus
/// the plain-text payload builder for the report's Copy action.
class AnalyzeResultsScreen extends StatelessWidget {
  /// Creates the report screen.
  const AnalyzeResultsScreen({
    required this.report,
    required this.copyTextBuilder,
    super.key,
  });

  /// The ordered findings to render, conclusion-first. May be empty (→ the
  /// empty state).
  final AnalysisReport report;

  /// Builds the full plain-text report for the §8.16 Copy affordance, or null
  /// when there is nothing to copy (empty report). Evaluated lazily at tap time.
  final String? Function() copyTextBuilder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('Analyze Results'),
          ),
        ),
        toolbarHeight: 64,
        // §8.16: Copy is the single trailing AppBar action; help is the bottom
        // footer. This is the report's own Copy — saves the whole analysis.
        actions: <Widget>[
          AppCopyAction(textBuilder: copyTextBuilder),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        return CenteredContent(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              edge,
              AppSpacing.md,
              edge,
              edge + AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _intro(context),
                const SizedBox(height: AppSpacing.md),
                if (!report.hasFindings)
                  _EmptyState()
                else ...<Widget>[
                  for (int i = 0; i < report.findings.length; i++) ...<Widget>[
                    _FindingCard(
                      finding: report.findings[i],
                      isHeadline: i == 0,
                    ),
                    if (i != report.findings.length - 1)
                      const SizedBox(height: AppSpacing.sm),
                  ],
                  if (report.hasPendingDraft) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    _DraftNote(),
                  ],
                ],
                const SizedBox(height: AppSpacing.md),
                _localOnlyNote(context),
                ToolHelpFooter(toolId: 'analyze-results'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _intro(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Text(
      report.hasFindings
          ? "Here's what your connection check is telling you, in plain "
              'language. The most important items are first.'
          : 'Run a connection check first, then come back to analyze the '
              'result.',
      style: text.bodyLarge?.copyWith(color: colors.textSecondary),
    );
  }

  Widget _localOnlyNote(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Center(
      child: Text(
        'Analyzed on your device. Nothing is sent or stored.',
        textAlign: TextAlign.center,
        style: text.labelSmall?.copyWith(color: colors.textTertiary),
      ),
    );
  }
}

/// One finding rendered as a conclusion-first card: an eyebrow row (severity
/// WORD + category), then the plain-language explanation.
class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.finding, required this.isHeadline});

  final AnalysisFinding finding;

  /// The first/top finding — rendered slightly more prominently (the headline).
  final bool isHeadline;

  /// Maps a severity to its §8.13 status hue. ALWAYS paired with the severity
  /// word in the eyebrow, so the color reinforces but never carries the meaning.
  Color _severityColor(AppColorScheme colors) {
    switch (finding.severity) {
      case FindingSeverity.critical:
        return colors.statusDanger;
      case FindingSeverity.important:
        return colors.statusWarning;
      case FindingSeverity.context:
        return colors.statusInfo;
    }
  }

  IconData get _severityIcon {
    switch (finding.severity) {
      case FindingSeverity.critical:
        return Icons.error_outline;
      case FindingSeverity.important:
        return Icons.warning_amber_outlined;
      case FindingSeverity.context:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final Color hue = _severityColor(colors);

    return Semantics(
      container: true,
      label: '${finding.severity.word}. ${finding.category.label}. '
          '${finding.explanation}',
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface1,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: colors.border,
              width: colors.isLight ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Eyebrow: glyph + SEVERITY WORD (in the status hue) + category.
              // Word + glyph carry the severity; the hue only reinforces.
              Row(
                children: <Widget>[
                  Icon(_severityIcon, size: AppTextSize.body, color: hue),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      finding.severity.word,
                      style: text.labelMedium?.copyWith(
                        color: hue,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      '· ${finding.category.label}',
                      style: text.labelMedium
                          ?.copyWith(color: colors.textTertiary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              // The conclusion-first explanation (rule DRAFT copy).
              Text(
                finding.explanation,
                style: (isHeadline ? text.bodyLarge : text.bodyMedium)
                    ?.copyWith(color: colors.textPrimary),
              ),
              if (finding.pendingRatification) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Draft guidance — wording not yet finalized.',
                  style: text.labelSmall?.copyWith(color: colors.textTertiary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The honest "some of this advice is draft" note, shown when any rendered
/// finding came from a rule still pending Keith's ratification / Penn's voice
/// pass. Remove once the rules ship ratified.
class _DraftNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline,
              size: AppTextSize.body, color: colors.statusInfo),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Some recommendations above are draft guidance under review. The '
              'measurements are accurate; the suggested wording may change.',
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty state — no findings (e.g. analyze tapped before a check completed, or
/// a wholly-unmeasured run). Honest, never an invented finding.
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Nothing to analyze yet',
            style: text.headlineSmall?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'There were no measured results to evaluate. Run Test My Connection '
            'on a live Wi-Fi connection, then analyze the result.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
