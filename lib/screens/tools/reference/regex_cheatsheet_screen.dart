// Regex Cheat Sheet - read-only reference of regular-expression syntax:
// anchors, character classes, quantifiers, groups/references, and alternation /
// escapes.
//
// Data ported verbatim from the verified dataset at
// Deliverables/2026-06-08-reference-batch/time-encoding-improvements-data.md
// SECTION 4 (REGEX CHEAT SHEET - NEW PAGE), subsections 4A-4E.
//
// HONESTY / DIALECT (GL-005, flagged explicitly in the source data §4): there is
// no single normative regex authority. POSIX (BRE/ERE), PCRE2, ECMAScript
// (JavaScript), Python, Java, Go (RE2), and .NET differ. This page is scoped to
// the COMMON PCRE2 (Perl-compatible) subset and:
//   * shows a visible "Dialect: PCRE2 (Perl-compatible)" banner at the top, and
//   * flags every token whose behavior changes by dialect via a per-row
//     `dialect` note and, when the token is NOT universal, a "DIALECT" status
//     badge.
// No token is presented as universal unless the source data marks it so.
//
// Pure read-only reference - no inputs, no computation, no network. The only
// state is "success": the compile-time const dataset always renders. No loading
// / empty / error / disabled path (SOP-007 §5: structurally impossible, not
// skipped). GL-008 network/subprocess rules do not apply.
//
// Pattern: mirrors poe_reference_screen (wide table idiom) + wpa_security_screen
// (the §8.13 StatusTone badge). The "DIALECT" badge uses StatusTone.warning; the
// word always accompanies the §8.13 color, so color is never the sole carrier
// of meaning (SC 1.4.1) and the border clears SC 1.4.11 on surface1. Each row is
// wrapped in ReferenceRowSemantics.
//
// Glyph note: ASCII only. Backslash-escape tokens are literal regex syntax, not
// markdown escapes; no em dash.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'reference_row_semantics.dart';

/// One regex token row: the token, what it matches, an optional dialect note,
/// and whether it is universal across engines. When [universal] is false the row
/// gets a "DIALECT" badge so the divergence is visible, not buried.
@immutable
class RegexToken {
  const RegexToken({
    required this.token,
    required this.matches,
    this.dialect,
    this.universal = false,
  });

  /// The regex token, e.g. `\b`, `(?:...)`, `*?`.
  final String token;

  /// What it matches / means.
  final String matches;

  /// Dialect divergence note (which engines support it / differ). Null when the
  /// token is universal.
  final String? dialect;

  /// True only when the source data marks the token "Universal" across engines.
  /// Drives the absence of the "DIALECT" badge.
  final bool universal;
}

class RegexCheatsheetScreen extends StatelessWidget {
  const RegexCheatsheetScreen({super.key});

  static const String _toolId = 'regex-cheatsheet';

  /// The visible dialect label, per the source data §4 binding requirement.
  static const String dialectLabel = 'Dialect: PCRE2 (Perl-compatible)';
  static const String dialectNote =
      'No single regex authority exists. This is the common PCRE2 subset - the '
      'most widely-implemented superset. POSIX (BRE/ERE), ECMAScript '
      '(JavaScript), Python, Java, Go (RE2), and .NET differ; per-token '
      'divergences are flagged below. Do not assume a flagged token works in '
      'every engine.';

  /// §4A - anchors.
  static const List<RegexToken> anchors = <RegexToken>[
    RegexToken(
      token: '^',
      matches: 'Start of string (or line in multiline mode)',
      dialect: 'Universal',
      universal: true,
    ),
    RegexToken(
      token: r'$',
      matches: 'End of string / before trailing newline (or line in multiline)',
      dialect: 'Universal',
      universal: true,
    ),
    RegexToken(
      token: r'\b',
      matches: r'Word boundary (between \w and non-\w)',
      dialect: 'PCRE2, ECMAScript, Python. Not in POSIX BRE/ERE',
    ),
    RegexToken(
      token: r'\B',
      matches: 'Not a word boundary',
      dialect: r'Same support as \b',
    ),
    RegexToken(
      token: r'\A',
      matches: 'Start of string (never line)',
      dialect: 'PCRE2, Python, Java. Not in ECMAScript',
    ),
    RegexToken(
      token: r'\z / \Z',
      matches: r'End of string (\Z allows trailing newline)',
      dialect: 'PCRE2, Python, Java. Not in ECMAScript',
    ),
  ];

  /// §4B - character classes.
  static const List<RegexToken> classes = <RegexToken>[
    RegexToken(
      token: '.',
      matches: 'Any char except newline (any char incl. newline with dotall/s)',
      dialect: 'Universal',
      universal: true,
    ),
    RegexToken(
      token: r'\d',
      matches: r'Digit [0-9] (Unicode digits if Unicode mode)',
      dialect: r'PCRE2/ECMAScript/Python. POSIX uses [[:digit:]]',
    ),
    RegexToken(
      token: r'\D',
      matches: 'Non-digit',
      dialect: 'Same',
    ),
    RegexToken(
      token: r'\w',
      matches: r'Word char [A-Za-z0-9_]',
      dialect: r'PCRE2/ECMAScript/Python. POSIX uses [[:alnum:]] (no underscore)',
    ),
    RegexToken(
      token: r'\W',
      matches: 'Non-word char',
      dialect: 'Same',
    ),
    RegexToken(
      token: r'\s',
      matches: 'Whitespace (space, tab, newline, etc.)',
      dialect: r'PCRE2/ECMAScript/Python. POSIX uses [[:space:]]',
    ),
    RegexToken(
      token: r'\S',
      matches: 'Non-whitespace',
      dialect: 'Same',
    ),
    RegexToken(
      token: '[abc]',
      matches: 'Any one of a, b, c',
      dialect: 'Universal',
      universal: true,
    ),
    RegexToken(
      token: '[a-z]',
      matches: 'Range a through z',
      dialect: 'Universal',
      universal: true,
    ),
    RegexToken(
      token: '[^abc]',
      matches: 'Any char except a, b, c (negated class)',
      dialect: 'Universal',
      universal: true,
    ),
    RegexToken(
      token: '[[:alpha:]]',
      matches: 'POSIX class inside a bracket expression',
      dialect: 'POSIX + PCRE2; not ECMAScript',
    ),
  ];

  /// §4C - quantifiers.
  static const List<RegexToken> quantifiers = <RegexToken>[
    RegexToken(
      token: '*',
      matches: '0 or more (greedy)',
      dialect: 'Universal',
      universal: true,
    ),
    RegexToken(
      token: '+',
      matches: '1 or more (greedy)',
      dialect: 'Universal',
      universal: true,
    ),
    RegexToken(
      token: '?',
      matches: '0 or 1 (greedy)',
      dialect: 'Universal',
      universal: true,
    ),
    RegexToken(
      token: '{n}',
      matches: 'Exactly n',
      dialect: 'Universal',
      universal: true,
    ),
    RegexToken(
      token: '{n,}',
      matches: 'n or more',
      dialect: 'Universal',
      universal: true,
    ),
    RegexToken(
      token: '{n,m}',
      matches: 'Between n and m',
      dialect: 'Universal',
      universal: true,
    ),
    RegexToken(
      token: '*? +? ?? {n,m}?',
      matches: 'Lazy (non-greedy) - match as few as possible',
      dialect: 'PCRE2/ECMAScript/Python/Java. Not in POSIX (always greedy)',
    ),
    RegexToken(
      token: '*+ ++ ?+ {n,m}+',
      matches: 'Possessive - greedy with no backtracking',
      dialect: 'PCRE2, Java. Not in ECMAScript or POSIX',
    ),
  ];

  static const String quantifierFootnote =
      'Greedy vs lazy: a.*b on axbxb matches axbxb (greedy, to the last b); '
      'a.*?b matches axb (lazy, to the first b).';

  /// §4D - groups and references.
  static const List<RegexToken> groups = <RegexToken>[
    RegexToken(
      token: '(...)',
      matches: 'Capturing group (numbered left-to-right by opening paren)',
      dialect: 'Universal',
      universal: true,
    ),
    RegexToken(
      token: '(?:...)',
      matches: 'Non-capturing group',
      dialect: 'PCRE2/ECMAScript/Python/Java. Not POSIX',
    ),
    RegexToken(
      token: '(?<name>...)',
      matches: 'Named capturing group',
      dialect: 'PCRE2/ECMAScript(2018+); Python uses (?P<name>...). Syntax varies',
    ),
    RegexToken(
      token: r'\1, \2 ...',
      matches: 'Backreference to numbered group',
      dialect: 'PCRE2/ECMAScript/Python/Java. Not in RE2 (Go) or POSIX ERE',
    ),
    RegexToken(
      token: r'\k<name>',
      matches: 'Named backreference',
      dialect: 'PCRE2/ECMAScript. Python uses (?P=name)',
    ),
    RegexToken(
      token: '(?=...)',
      matches: 'Positive lookahead',
      dialect: 'PCRE2/ECMAScript/Python/Java. Not POSIX',
    ),
    RegexToken(
      token: '(?!...)',
      matches: 'Negative lookahead',
      dialect: 'Same',
    ),
    RegexToken(
      token: '(?<=...)',
      matches: 'Positive lookbehind',
      dialect: 'PCRE2/Python/Java/.NET; ECMAScript 2018+. Not POSIX, not RE2',
    ),
    RegexToken(
      token: '(?<!...)',
      matches: 'Negative lookbehind',
      dialect: 'Same',
    ),
  ];

  /// §4E - alternation and common escapes.
  static const List<RegexToken> escapes = <RegexToken>[
    RegexToken(
      token: 'a|b',
      matches: 'Alternation: match a or b (lowest precedence)',
      dialect: 'Universal',
      universal: true,
    ),
    RegexToken(
      token: r'\. \* \+ \? \( \) \[ \] \{ \} \| \^ \$ \\',
      matches: 'Escaped literal of a metacharacter',
      dialect: 'Universal',
      universal: true,
    ),
    RegexToken(
      token: r'\t',
      matches: 'Tab',
      dialect: 'Universal',
      universal: true,
    ),
    RegexToken(
      token: r'\n',
      matches: 'Newline',
      dialect: 'Universal',
      universal: true,
    ),
    RegexToken(
      token: r'\r',
      matches: 'Carriage return',
      dialect: 'Universal',
      universal: true,
    ),
    RegexToken(
      // \v split out below (Wave-2 finding C): it is NOT universal and NOT the
      // vertical-tab literal in this page's declared PCRE2 dialect. \f and \0
      // are genuinely universal, so they stay here.
      token: r'\f \0',
      matches: 'Form feed, null',
      dialect: 'Universal',
      universal: true,
    ),
    RegexToken(
      // In PCRE2 (this page's dialect) \v is the vertical-WHITESPACE character
      // class (matches LF, VT, FF, CR, NEL, U+2028, U+2029), NOT vertical-tab
      // only. It is vertical-tab only in JS, Python, .NET, Ruby, Tcl, RE2. One
      // of the most dialect-divergent tokens on the sheet, so it must NOT be
      // marked Universal. Source: PCRE2 pcre2pattern. Wave-2 finding C.
      token: r'\v',
      matches: 'Vertical whitespace class (LF, VT, FF, CR, NEL, U+2028/2029)',
      dialect: 'PCRE2 (here) / vertical tab only in JS, Python, .NET, Ruby, RE2',
    ),
    RegexToken(
      token: r'\xHH',
      matches: 'Char by 2-digit hex code',
      dialect: 'PCRE2/ECMAScript/Python',
    ),
    RegexToken(
      token: r'\x{HHHH}',
      matches: 'Char by hex code point',
      dialect: 'PCRE2 / Unicode mode',
    ),
  ];

  /// All the sections in display order, paired with their titles + footnotes.
  static const List<_RegexSection> _sections = <_RegexSection>[
    _RegexSection('Anchors', anchors),
    _RegexSection('Character classes', classes),
    _RegexSection('Quantifiers', quantifiers, footnote: quantifierFootnote),
    _RegexSection('Groups & references', groups),
    _RegexSection('Alternation & escapes', escapes),
  ];

  static const String _intro =
      'Anchors, character classes, quantifiers, groups, and escapes. Scoped to '
      'the PCRE2 (Perl-compatible) subset; tokens that differ by engine are '
      'flagged DIALECT - none is presented as universal unless it is.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Regex Cheat Sheet'),
        toolbarHeight: 64,
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload - the dialect label + every section as a TSV block.
  /// Static data, always enabled. Non-universal tokens carry a "(DIALECT)"
  /// marker so the copied text keeps the divergence flag the screen shows.
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Regex Cheat Sheet')
      ..writeln(dialectLabel)
      ..writeln();
    for (final _RegexSection section in _sections) {
      buf
        ..writeln(section.title)
        ..writeln(<String>['Token', 'Matches', 'Dialect'].join(tab));
      for (final RegexToken r in section.tokens) {
        final String dialect = r.dialect ?? '';
        final String flagged = r.universal ? dialect : '$dialect (DIALECT)';
        buf.writeln(<String>[r.token, r.matches, flagged].join(tab));
      }
      if (section.footnote != null) buf.writeln(section.footnote!);
      buf.writeln();
    }
    return buf.toString().trimRight();
  }

  Widget _body(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

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
                  ConceptGraphicBand(toolId: _toolId, isDesktop: isDesktop),
                  if (ToolAssets.hasGraphic(_toolId))
                    const SizedBox(height: AppSpacing.md),
                  _DialectBanner(label: dialectLabel, note: dialectNote),
                  const SizedBox(height: AppSpacing.sm),
                  _IntroText(text: _intro),
                  const SizedBox(height: AppSpacing.sm),
                  for (int i = 0; i < _sections.length; i++) ...<Widget>[
                    _sectionCard(_sections[i], colors, text, mono),
                    if (i < _sections.length - 1)
                      const SizedBox(height: AppSpacing.md),
                  ],
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
    _RegexSection section,
    AppColorScheme colors,
    TextTheme text,
    AppMonoText mono,
  ) {
    final Color dialectTone = colors.statusToneColor(StatusTone.warning);
    return _TableCard(
      title: section.title,
      footnote: section.footnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Token', width: 168),
          _HeaderCell('Matches', width: 260),
          _HeaderCell('Dialect', width: 320),
        ],
      ),
      rows: section.tokens.map((RegexToken r) {
        return ReferenceRowSemantics(
          label: rowLabel(r.token, <String?>[
            r.matches,
            r.universal ? 'universal' : 'dialect-specific',
            r.dialect,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 168,
                  child: Text(
                    r.token,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: Text(
                    r.matches,
                    style: text.labelSmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (!r.universal) ...<Widget>[
                        _DialectBadge(color: dialectTone),
                        const SizedBox(height: AppSpacing.xxs),
                      ],
                      Text(
                        r.dialect ?? '',
                        style: text.labelSmall?.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
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

/// Section descriptor - a title, its tokens, and an optional footnote.
@immutable
class _RegexSection {
  const _RegexSection(this.title, this.tokens, {this.footnote});

  final String title;
  final List<RegexToken> tokens;
  final String? footnote;
}

/// The prominent dialect banner pinned above the tables (source §4 binding
/// requirement). Uses a §8.13 info-toned card so the scope reads at a glance;
/// the label text never relies on color alone (SC 1.4.1).
class _DialectBanner extends StatelessWidget {
  const _DialectBanner({required this.label, required this.note});

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

/// The per-token "DIALECT" badge - a §8.13 warning-toned chip shown only on
/// tokens that are NOT universal. The word "DIALECT" always accompanies the
/// color, so color is never the sole carrier of meaning (SC 1.4.1), and the
/// border clears SC 1.4.11 (3:1 non-text) on surface1.
class _DialectBadge extends StatelessWidget {
  const _DialectBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        'DIALECT',
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

/// Card surface wrapping a wide table - verbatim from the poe_reference idiom.
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
