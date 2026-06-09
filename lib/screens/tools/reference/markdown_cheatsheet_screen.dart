// Markdown Cheatsheet — read-only reference of CommonMark + GitHub Flavored
// Markdown (GFM) syntax: headings, emphasis, links/images, lists, blocks,
// fenced code, and tables, each as a (Element | You type | Renders as) row.
//
// Data lives in markdown_cheatsheet_data.dart (typed const). The "You type"
// column shows the LITERAL markdown (e.g. **bold**) in DM Mono — the asterisks,
// backticks, and pipes render as text, never as formatting, because they are
// plain string data drawn by a Text widget (no markdown renderer runs here).
//
// Pure read-only reference — no inputs, no computation, no network. The only
// state is "success": the compile-time const dataset always renders. No loading
// / empty / error / disabled path (SOP-007 §5: structurally impossible, not
// skipped). GL-008 network/subprocess rules do not apply.
//
// Pattern: mirrors regex_cheatsheet_screen (the syntax/meaning wide-table idiom,
// the §8.16 copy-as-TSV action, HorizontalScrollTable, ReferenceRowSemantics,
// the scope banner, and the §8.13 StatusTone "GFM" badge on non-core rows). A
// LargeGraphic concept pane sits at the top, resolved through MarkdownDiagrams
// (asset markdown-render-example) and degrading gracefully to nothing when the
// SVG is not yet bundled (Charta authors it in parallel).
//
// Glyph note (GL-004): ASCII only, no em dash, US spelling. The backslash and
// markup characters in the data are literal markdown syntax, not Dart escapes.

import 'package:flutter/material.dart';

import '../../../data/markdown_cheatsheet_data.dart';
import '../../../data/markdown_diagrams.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';
import 'large_face_card.dart';
import 'reference_row_semantics.dart';

class MarkdownCheatsheetScreen extends StatelessWidget {
  const MarkdownCheatsheetScreen({super.key});

  static const String _toolId = 'markdown-cheatsheet';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Markdown Cheatsheet'),
        toolbarHeight: 64,
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the scope label + every section as a TSV block, with
  /// the GFM flag preserved so the copied text keeps the divergence marker the
  /// screen shows. Static data, always enabled.
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Markdown Cheatsheet')
      ..writeln(MarkdownCheatsheetData.scopeLabel)
      ..writeln();
    for (final MarkdownSection section in MarkdownCheatsheetData.sections) {
      buf
        ..writeln(section.title)
        ..writeln(<String>['Element', 'You type', 'Renders as', 'Flavor'].join(tab));
      for (final MarkdownRow r in section.rows) {
        final String flavor = r.gfm ? 'GFM' : 'CommonMark';
        buf.writeln(
          <String>[r.element, r.youType, r.rendersAs, flavor].join(tab),
        );
      }
      if (section.footnote != null) buf.writeln(section.footnote!);
      buf.writeln();
    }
    buf.writeln('Gotchas');
    for (final String g in MarkdownCheatsheetData.gotchas) {
      buf.writeln('- $g');
    }
    return buf.toString().trimRight();
  }

  Widget _body(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final bool hasGraphic = MarkdownDiagrams.has(MarkdownDiagrams.renderExample);

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.calculatorMaxWidth,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Concept graphic: a "you type / renders as" example pane.
                  // Degrades to SizedBox.shrink() until Charta's SVG is bundled.
                  LargeGraphic(
                    assetName: MarkdownDiagrams.renderExample,
                    path: MarkdownDiagrams.path,
                    has: MarkdownDiagrams.has,
                  ),
                  if (hasGraphic) const SizedBox(height: AppSpacing.md),
                  _ScopeBanner(
                    label: MarkdownCheatsheetData.scopeLabel,
                    note: MarkdownCheatsheetData.scopeNote,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _IntroText(text: MarkdownCheatsheetData.intro),
                  const SizedBox(height: AppSpacing.sm),
                  for (int i = 0;
                      i < MarkdownCheatsheetData.sections.length;
                      i++) ...<Widget>[
                    _sectionCard(
                      MarkdownCheatsheetData.sections[i],
                      colors,
                      text,
                      mono,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  _GotchasCard(gotchas: MarkdownCheatsheetData.gotchas),
                  ToolHelpFooter(toolId: _toolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sectionCard(
    MarkdownSection section,
    AppColorScheme colors,
    TextTheme text,
    AppMonoText mono,
  ) {
    final Color gfmTone = colors.statusToneColor(StatusTone.info);
    return _TableCard(
      title: section.title,
      footnote: section.footnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Element', width: 160),
          _HeaderCell('You type', width: 300),
          _HeaderCell('Renders as', width: 320),
        ],
      ),
      rows: section.rows.map((MarkdownRow r) {
        return ReferenceRowSemantics(
          label: rowLabel(r.element, <String?>[
            // The literal markdown reads poorly to a screen reader; describe the
            // result and the flavor instead of spelling out the punctuation.
            r.rendersAs,
            r.gfm ? 'GitHub Flavored Markdown extension' : 'CommonMark core',
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 160,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        r.element,
                        style: text.labelMedium?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (r.gfm) ...<Widget>[
                        const SizedBox(height: AppSpacing.xxs),
                        _GfmBadge(color: gfmTone),
                      ],
                    ],
                  ),
                ),
                SizedBox(
                  width: 300,
                  // The LITERAL markdown in DM Mono. The asterisks, backticks,
                  // and pipes are plain text here — a Text widget never
                  // interprets them as formatting. Newlines in multi-line
                  // snippets are shown with a literal "\n" marker in the data so
                  // each row stays single-logical-line in the column.
                  child: Text(
                    r.youType,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: Text(
                    r.rendersAs,
                    style: text.labelSmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// The prominent scope banner pinned above the tables — states the CommonMark +
/// GFM scope so a reader knows the GFM-flagged rows may not work everywhere.
/// Uses a §8.13 info-toned card; the label text never relies on color alone
/// (SC 1.4.1). Mirrors the regex page's dialect banner.
class _ScopeBanner extends StatelessWidget {
  const _ScopeBanner({required this.label, required this.note});

  final String label;
  final String note;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final Color tone = colors.statusToneColor(StatusTone.info);
    return Semantics(
      container: true,
      label: '$label. $note',
      child: Container(
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: tone, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.info_outline, size: 24, color: colors.textPrimary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    label,
                    style: t.bodyLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              note,
              style: t.labelMedium?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// The per-row "GFM" badge — a §8.13 info-toned chip shown only on rows whose
/// syntax is a GFM extension (not CommonMark core). The word "GFM" always
/// accompanies the color, so color is never the sole carrier of meaning
/// (SC 1.4.1), and the border clears SC 1.4.11 (3:1 non-text) on surface1.
class _GfmBadge extends StatelessWidget {
  const _GfmBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        'GFM',
        style: t.labelSmall?.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Intro paragraph, secondary text on the canvas.
class _IntroText extends StatelessWidget {
  const _IntroText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: t.labelMedium?.copyWith(color: colors.textSecondary),
    );
  }
}

/// The "Gotchas" card — the short watch-out notes the brief asks for, as a
/// bulleted list on a surface1 card. Each bullet is its own semantics node.
class _GotchasCard extends StatelessWidget {
  const _GotchasCard({required this.gotchas});

  final List<String> gotchas;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Gotchas',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final String g in gotchas) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '- ',
                    style: text.bodyMedium?.copyWith(color: colors.textTertiary),
                  ),
                  Expanded(
                    child: Text(
                      g,
                      style:
                          text.bodyMedium?.copyWith(color: colors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Card surface wrapping a wide table — verbatim from the regex/poe idiom.
class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.title,
    required this.header,
    required this.rows,
    this.footnote,
  });

  final String title;
  final Widget header;
  final List<Widget> rows;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          HorizontalScrollTable(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  header,
                  Divider(color: colors.border, height: AppSpacing.sm),
                  ...rows,
                ],
              ),
            ),
          ),
          if (footnote != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              footnote!,
              style: text.labelMedium?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// One column-header label, caption-styled to align with the data cells.
class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          color: colors.textTertiary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
