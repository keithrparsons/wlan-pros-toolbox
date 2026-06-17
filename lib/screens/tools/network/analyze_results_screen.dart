// Analyze Results, the in-app report view (GL-003 App Mode).
//
// Reached by tapping "Analyze" on the Test My Connection results screen,
// ALONGSIDE Copy (Copy = save the raw report for support; Analyze = this local,
// plain-language explanation). It runs the pure [AnalyzeEngine] over the SAME
// result data already on screen, LOCALLY, no network call, nothing stored,
// nothing leaves the device.
//
// GRAPHICAL CUES (Iris's report-visual-spec, 2026-06-16):
//   * §1 VERDICT HERO at the top: the plain-language conclusion in display-scale
//     `--text-h1` NEUTRAL primary ink (never a status hue, the hero is language,
//     not a per-finding verdict).
//   * §2 reusable [StatusChip] (word + glyph + hue, never color-only) per
//     finding, resolving dark-tint vs light-solid-pill off the active theme.
//   * §3 a neutral CATEGORY ICON per finding (Wi-Fi / internet / DNS / security
//     / router-access-point), tinted textSecondary, never a status hue.
//   * §4 FINDING CARDS: category icon + status chip + headline + plain
//     explanation, with an optional §4.1 severity accent (dark tint band /
//     light 6px left bar, no text on it).
//   * §5 ORDERING: verdict hero, then security, then worst measured quality
//     (issue -> heads-up -> good), then the §6 info / "not measured" rows last.
//   * §6 HONESTY INFO ROWS: info hue, "Not measured", quieter, at the bottom,
//     never amber / red.
//   * §7 COPY: the shared §8.16 AppCopyAction (AppBar trailing); the copied
//     plain text carries every verdict WORD so nothing is color-only on the
//     clipboard (the copy-text builder lives in test_my_connection_screen).
//
// Tokens used (all semantic, GL-003): surface1 cards + §8.1 border, §8.13 /
// §8.20.4 status colors via [StatusChip], textPrimary/secondary/tertiary, §3
// type scale via the M3 TextTheme, §4/§8.7 spacing, §8.11 radii, §8.6 icon
// sizes, §8.16 AppCopyAction, §8.16.1 ToolHelpFooter.
//
// ZERO em-dashes anywhere in this file (UI, strings, comments), per the
// standing Analyze Results rule. No bare "AP": the device term is
// "router/access point".
//
// DRAFT-COPY HONESTY (vestigial as of 2026-06-16): all rules are now ratified
// and Penn-voiced, so no finding is pendingRatification and the draft note
// never triggers. The rendering path is kept so a future not-yet-ratified rule
// can surface honestly (GL-005), but with nothing pending it does not show.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../services/network/analyze/analysis_finding.dart';
import '../../../services/network/analyze/analyze_engine.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/centered_content.dart';
import '../../../widgets/status_chip.dart';
import '../../../widgets/tool_help_footer.dart';

/// Maps a finding's [FindingSeverity] + reassurance flag to the §2 chip kind.
/// The single source of truth for the screen's verdict-to-chip resolution.
StatusChipKind _chipKindFor(AnalysisFinding f) {
  if (f.isHonesty) return StatusChipKind.info;
  if (f.isReassurance) return StatusChipKind.good;
  switch (f.severity) {
    case FindingSeverity.critical:
      return StatusChipKind.issue;
    case FindingSeverity.important:
      // The all-clear verdict headline (R-04) reads as a "Good", not advisory.
      return f.ruleId == 'R-04' ? StatusChipKind.good : StatusChipKind.headsUp;
    case FindingSeverity.context:
      return StatusChipKind.headsUp;
  }
}

/// One category-icon spec: either a Material glyph or a Tier-2 SVG asset path.
/// The §3 category icon NAMES the finding's subject and is tinted neutral
/// (textSecondary), never a status hue (the hue lives in the §2 chip).
@immutable
class _CategoryIcon {
  const _CategoryIcon.material(this.icon) : asset = null;
  const _CategoryIcon.asset(this.asset) : icon = null;
  final IconData? icon;
  final String? asset;
}

/// The router/access-point category icon: the Tier-2 `ap-placement.svg` asset
/// (Vera-passed), tinted neutral `textSecondary` like every other §3 category
/// icon. It leads the band / capability findings, which are about the router/
/// access point's own configuration. This is the single swap point for the
/// router/access-point category icon.
const _CategoryIcon _routerApIcon =
    _CategoryIcon.asset('assets/tool-icons/ap-placement.svg');

/// Resolves a [FindingCategory] to its §3 neutral category icon. The single
/// mapping point: every category's icon is decided here. The router/access-point
/// category resolves to the Tier-2 `ap-placement.svg` (see [_routerApIcon]).
_CategoryIcon _categoryIconFor(FindingCategory category) {
  switch (category) {
    // Wi-Fi link family (the wireless hop): signal, noise.
    case FindingCategory.signal:
    case FindingCategory.noise:
      return const _CategoryIcon.material(Icons.wifi);
    // Band / capability findings are about the router/access point itself
    // (its band, standard, channel, and width configuration), so they lead
    // with the router/access-point icon, not the over-the-air Wi-Fi fan.
    case FindingCategory.capability:
      return _routerApIcon;
    // Internet service / reachability past the router/access point.
    case FindingCategory.internetQuality:
    case FindingCategory.cloudReachability:
      return const _CategoryIcon.material(Icons.public);
    case FindingCategory.dns:
      return const _CategoryIcon.asset('assets/tool-icons/dns-lookup.svg');
    case FindingCategory.security:
      return const _CategoryIcon.material(Icons.lock_outline);
    // Verdict renders as the §1 hero (no category icon); honesty renders as a
    // §6 info row. Both still resolve here for completeness, reading as the
    // Wi-Fi family (honesty rows name the Wi-Fi capture they could not read).
    case FindingCategory.verdict:
    case FindingCategory.honesty:
      return const _CategoryIcon.material(Icons.wifi);
  }
}

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

  /// The ordered findings to render, conclusion-first. May be empty (to the
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
        // footer. This is the report's own Copy, saves the whole analysis.
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
              children: _content(context),
            ),
          ),
        );
      },
    );
  }

  /// Assembles the ordered content: §1 hero, then §4 finding cards, then §6
  /// honesty info rows last. Partitions the engine's already-ordered list
  /// (verdict first, honesty last) into the three visual registers.
  List<Widget> _content(BuildContext context) {
    if (!report.hasFindings) {
      return <Widget>[
        _intro(context),
        const SizedBox(height: AppSpacing.md),
        _EmptyState(),
        const SizedBox(height: AppSpacing.md),
        _localOnlyNote(context),
        ToolHelpFooter(toolId: 'analyze-results'),
      ];
    }

    // Partition the ordered findings: the leading verdict becomes the §1 hero;
    // honesty rows go to the quiet §6 block at the bottom; everything else is a
    // §4 finding card, in the engine's order (security, then worst quality).
    final List<AnalysisFinding> all = report.findings;
    final AnalysisFinding? hero =
        all.isNotEmpty && all.first.isVerdict ? all.first : null;
    final List<AnalysisFinding> cards = <AnalysisFinding>[];
    final List<AnalysisFinding> honesty = <AnalysisFinding>[];
    for (int i = 0; i < all.length; i++) {
      final AnalysisFinding f = all[i];
      if (identical(f, hero)) continue;
      if (f.isHonesty) {
        honesty.add(f);
      } else {
        cards.add(f);
      }
    }

    final List<Widget> out = <Widget>[];

    if (hero != null) {
      out.add(_VerdictHero(finding: hero));
      out.add(const SizedBox(height: AppSpacing.md));
    } else {
      // No verdict fired (a partial read), keep the plain-language lead-in so
      // the screen never opens cold.
      out.add(_intro(context));
      out.add(const SizedBox(height: AppSpacing.md));
    }

    for (int i = 0; i < cards.length; i++) {
      out.add(_FindingCard(finding: cards[i]));
      if (i != cards.length - 1) {
        out.add(const SizedBox(height: AppSpacing.md));
      }
    }

    if (honesty.isNotEmpty) {
      if (cards.isNotEmpty) out.add(const SizedBox(height: AppSpacing.md));
      out.add(_HonestyHeader());
      for (final AnalysisFinding f in honesty) {
        out.add(const SizedBox(height: AppSpacing.xs));
        out.add(_InfoRow(finding: f));
      }
    }

    if (report.hasPendingDraft) {
      out.add(const SizedBox(height: AppSpacing.md));
      out.add(_DraftNote());
    }

    out.add(const SizedBox(height: AppSpacing.md));
    out.add(_localOnlyNote(context));
    out.add(ToolHelpFooter(toolId: 'analyze-results'));
    return out;
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

/// §1, the verdict hero. The plain-language conclusion at display scale, in
/// NEUTRAL primary ink (never a status hue: the hero is language, not a
/// per-finding verdict, §1.2). The headline is the verdict's conclusion-first
/// first sentence; any remainder reads as the optional supporting sub-line.
class _VerdictHero extends StatelessWidget {
  const _VerdictHero({required this.finding});

  final AnalysisFinding finding;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final _Split split = _Split.of(finding.explanation);

    return Semantics(
      container: true,
      header: true,
      label: 'Your result. ${finding.explanation}',
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
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // §1.2 overline label, neutral tertiary ink, never a status hue.
              Text(
                'YOUR RESULT',
                style: (text.labelSmall ?? const TextStyle()).copyWith(
                  color: colors.textTertiary,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              // §1.2 verdict headline, `--text-h1`, PLAIN neutral primary ink.
              Text(
                split.headline,
                style: (text.displaySmall ?? const TextStyle()).copyWith(
                  fontSize: AppTextSize.h1,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              if (split.body != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  split.body!,
                  style: text.bodyLarge?.copyWith(color: colors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// §4, one finding rendered as a card: a header row (category icon + §2 status
/// chip), then the conclusion-first headline, then the plain explanation. An
/// optional §4.1 severity accent reinforces (dark tint band / light 6px left
/// bar), never a text-bearing element.
class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.finding});

  final AnalysisFinding finding;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final StatusChipKind kind = _chipKindFor(finding);
    final Color hue = kind.hue(colors);
    final _Split split = _Split.of(finding.explanation);
    // §4.1 severity accent only for the load-bearing verdicts (issue /
    // heads-up). A "Good" card stays calm with no accent.
    final bool accent =
        kind == StatusChipKind.issue || kind == StatusChipKind.headsUp;

    // §4.1 light accent: a true 6px left EDGE (no text on it). Rendered as a
    // separate strip behind a uniform-border rounded card, never via a
    // non-uniform border color (illegal with a borderRadius in Flutter).
    final bool lightAccent = accent && colors.isLight;

    final Widget content = Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Header row: §3 neutral category icon + §2 status chip.
          Row(
            children: <Widget>[
              _CategoryIconView(category: finding.category),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: StatusChip(kind: kind, word: finding.verdictWord),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // §4.2 headline, `--text-h3`, conclusion-first, primary ink.
          Text(
            split.headline,
            style: (text.titleLarge ?? const TextStyle()).copyWith(
              fontSize: AppTextSize.h3,
              height: 1.4,
              fontWeight: colors.isLight ? FontWeight.w700 : FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          if (split.body != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            // §4.2 explanation, `--text-body`, secondary ink.
            Text(
              split.body!,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );

    // The card body: a uniform-border rounded surface. §4.1 dark gets a subtle
    // status-tint band behind the whole card; light keeps the white surface and
    // carries its accent as the left edge strip (below).
    final Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: accent && !colors.isLight
            ? Color.alphaBlend(hue.withValues(alpha: 0.10), colors.surface1)
            : colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      // Inset the content past the 6px edge on light-accent cards so no text
      // ever sits on the bar (no-overlap, §0 rule 3).
      child: lightAccent
          ? Padding(
              padding: const EdgeInsets.only(left: 6),
              child: content,
            )
          : content,
    );

    final Widget card = lightAccent
        ? ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Stack(
              children: <Widget>[
                body,
                // The 6px full-saturation left-accent EDGE. Decorative; no text.
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: 0,
                  child: Container(width: 6, color: hue),
                ),
              ],
            ),
          )
        : body;

    return Semantics(
      container: true,
      label: '${finding.verdictWord}. ${finding.category.label}. '
          '${finding.explanation}',
      child: ExcludeSemantics(child: card),
    );
  }
}

/// §6, the quiet header above the honesty / "not measured" block.
class _HonestyHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Text(
      'WHAT WAS MEASURED',
      style: (text.labelSmall ?? const TextStyle()).copyWith(
        color: colors.textTertiary,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// §6, an honesty / "not measured" row. Info hue, "Not measured" word, plain
/// explanation of the honest limit. Quieter than a finding card, never amber or
/// red. This honesty is the brand (GL-005).
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.finding});

  final AnalysisFinding finding;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final _Split split = _Split.of(finding.explanation);

    return Semantics(
      container: true,
      label: 'Not measured. ${finding.explanation}',
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
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // §2 info chip: word + glyph + info hue (resolves dark-tint /
              // light-pill via StatusChip).
              StatusChip(
                kind: StatusChipKind.info,
                word: finding.verdictWord,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                split.headline,
                style: (text.titleMedium ?? const TextStyle()).copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              if (split.body != null) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  split.body!,
                  style:
                      text.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// §3, the neutral category icon. Tier-1 Material glyph or Tier-2 SVG asset,
/// tinted `textSecondary` (NEVER a status hue), rendered at `--app-icon-content`
/// (20px). The colored verdict lives in the §2 chip, not here.
class _CategoryIconView extends StatelessWidget {
  const _CategoryIconView({required this.category});

  final FindingCategory category;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final Color tint = colors.textSecondary; // §3 neutral tint, never a hue.
    final _CategoryIcon spec = _categoryIconFor(category);
    // §8.6 `--app-icon-content` (20px) inline-with-text leading icon size.
    const double size = 20;

    if (spec.asset != null) {
      return SvgPicture.asset(
        spec.asset!,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
        excludeFromSemantics: true,
        placeholderBuilder: (_) => const SizedBox(width: size, height: size),
      );
    }
    return Icon(spec.icon, size: size, color: tint);
  }
}

/// Splits a conclusion-first explanation into a HEADLINE (the leading sentence,
/// the §4.2 H3) and the BODY remainder (the §4.2 explanation), so each card and
/// the hero lead with the conclusion and carry the detail below. Penn authored
/// every rule's copy conclusion-first, so the first sentence is the headline.
@immutable
class _Split {
  const _Split(this.headline, this.body);

  final String headline;
  final String? body;

  /// Parses [explanation] at its first sentence boundary. A short single-
  /// sentence explanation becomes an all-headline split (no body).
  factory _Split.of(String explanation) {
    final String s = explanation.trim();
    // First sentence end: ". " (period + space). Avoid splitting on a decimal
    // or an abbreviation by requiring the period be followed by a space and an
    // uppercase letter or end-of-string is the simplest robust heuristic for
    // this curated, hand-authored copy.
    final RegExp boundary = RegExp(r'\.\s+');
    final Match? m = boundary.firstMatch(s);
    if (m == null) return _Split(s, null);
    final String headline = s.substring(0, m.start + 1).trim();
    final String body = s.substring(m.end).trim();
    if (body.isEmpty) return _Split(headline, null);
    return _Split(headline, body);
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

/// Empty state, no findings (e.g. analyze tapped before a check completed, or
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
