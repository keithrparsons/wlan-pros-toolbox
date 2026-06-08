// Hash & Crypto Output Lengths - read-only reference of common hash algorithms,
// their output sizes (bits / bytes / hex characters), family, and security
// status. MD5 and SHA-1 carry an explicit "broken / deprecated" flag.
//
// Data ported verbatim from the verified dataset at
// Deliverables/2026-06-08-reference-batch/time-encoding-improvements-data.md
// SECTION 3 (HASH / CRYPTO OUTPUT LENGTHS - NEW PAGE). Values trace to NIST
// FIPS 180-4 (SHA-1, SHA-2 family), FIPS 202 (SHA-3 / Keccak), and RFC 1321
// (MD5); deprecation per NIST SP 800-131A and the 2017 SHAttered SHA-1
// collision.
//
// Pure read-only reference - no inputs, no computation, no network. The only
// state is "success": the compile-time const dataset always renders. No loading
// / empty / error / disabled path (SOP-007 §5: structurally impossible, not
// skipped). GL-008 network/subprocess rules do not apply.
//
// Pattern: mirrors poe_reference_screen (wide table idiom) + wpa_security_screen
// (the §8.13 StatusTone verdict chip). The security-status word always
// accompanies the §8.13 status color, so color is never the sole carrier of
// meaning (SC 1.4.1), and the chip border clears SC 1.4.11 (3:1 non-text) on
// surface1. Each row is wrapped in ReferenceRowSemantics.
//
// Glyph note: ASCII hyphen-minus only ("SHA-1", "SHA3-256"); no em dash.

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

/// One hash algorithm row. Field data verbatim from the source §3 table; the
/// security verdict is mapped to a §8.13 StatusTone by its meaning (danger for
/// broken/deprecated, success for the recommended default, info for current).
@immutable
class HashAlgo {
  const HashAlgo({
    required this.name,
    required this.bits,
    required this.bytes,
    required this.hexChars,
    required this.family,
    required this.statusTone,
    required this.status,
  });

  /// Algorithm name, e.g. `SHA-256`.
  final String name;

  /// Output length in bits.
  final int bits;

  /// Output length in bytes.
  final int bytes;

  /// Output length in hex characters (= bits / 4 = bytes x 2).
  final int hexChars;

  /// Family, e.g. `SHA-2 (FIPS 180-4)`.
  final String family;

  /// Verdict tone, resolved to a §8.13/§8.20.1 status color at render via
  /// [AppColorScheme.statusToneColor]; never a baked Color (theme-dependent).
  final StatusTone statusTone;

  /// Security status word, e.g. `Broken`, `Current`, `Recommended`.
  final String status;
}

class HashLengthsScreen extends StatelessWidget {
  const HashLengthsScreen({super.key});

  static const String _toolId = 'hash-lengths';

  /// Hash algorithms, in source order. Public-static for testing.
  static const List<HashAlgo> algorithms = <HashAlgo>[
    HashAlgo(
      name: 'MD5',
      bits: 128,
      bytes: 16,
      hexChars: 32,
      family: 'Rivest (RFC 1321)',
      statusTone: StatusTone.danger,
      status: 'Broken',
    ),
    HashAlgo(
      name: 'SHA-1',
      bits: 160,
      bytes: 20,
      hexChars: 40,
      family: 'SHA-1 (FIPS 180-4)',
      statusTone: StatusTone.danger,
      status: 'Deprecated',
    ),
    HashAlgo(
      name: 'SHA-224',
      bits: 224,
      bytes: 28,
      hexChars: 56,
      family: 'SHA-2 (FIPS 180-4)',
      statusTone: StatusTone.info,
      status: 'Current',
    ),
    HashAlgo(
      name: 'SHA-256',
      bits: 256,
      bytes: 32,
      hexChars: 64,
      family: 'SHA-2 (FIPS 180-4)',
      statusTone: StatusTone.success,
      status: 'Recommended',
    ),
    HashAlgo(
      name: 'SHA-384',
      bits: 384,
      bytes: 48,
      hexChars: 96,
      family: 'SHA-2 (FIPS 180-4)',
      statusTone: StatusTone.info,
      status: 'Current',
    ),
    HashAlgo(
      name: 'SHA-512',
      bits: 512,
      bytes: 64,
      hexChars: 128,
      family: 'SHA-2 (FIPS 180-4)',
      statusTone: StatusTone.info,
      status: 'Current',
    ),
    HashAlgo(
      name: 'SHA-512/224',
      bits: 224,
      bytes: 28,
      hexChars: 56,
      family: 'SHA-2 (FIPS 180-4)',
      statusTone: StatusTone.info,
      status: 'Current',
    ),
    HashAlgo(
      name: 'SHA-512/256',
      bits: 256,
      bytes: 32,
      hexChars: 64,
      family: 'SHA-2 (FIPS 180-4)',
      statusTone: StatusTone.info,
      status: 'Current',
    ),
    HashAlgo(
      name: 'SHA3-224',
      bits: 224,
      bytes: 28,
      hexChars: 56,
      family: 'SHA-3 / Keccak (FIPS 202)',
      statusTone: StatusTone.info,
      status: 'Current',
    ),
    HashAlgo(
      name: 'SHA3-256',
      bits: 256,
      bytes: 32,
      hexChars: 64,
      family: 'SHA-3 / Keccak (FIPS 202)',
      statusTone: StatusTone.info,
      status: 'Current',
    ),
    HashAlgo(
      name: 'SHA3-384',
      bits: 384,
      bytes: 48,
      hexChars: 96,
      family: 'SHA-3 / Keccak (FIPS 202)',
      statusTone: StatusTone.info,
      status: 'Current',
    ),
    HashAlgo(
      name: 'SHA3-512',
      bits: 512,
      bytes: 64,
      hexChars: 128,
      family: 'SHA-3 / Keccak (FIPS 202)',
      statusTone: StatusTone.info,
      status: 'Current',
    ),
  ];

  static const String footnote =
      'Rule of thumb: hex chars = bits / 4 = bytes x 2 (each hex digit encodes '
      '4 bits). MD5 and SHA-1 remain acceptable only for non-security checksums '
      '(deduplication, non-adversarial integrity). For any signature, '
      'certificate, password, or authentication use, choose SHA-256 or '
      'SHA3-256 and above. "Broken" means a collision is computationally '
      'feasible - not that the output length changed.';

  static const String _intro =
      'Common hash algorithms and their output sizes - bits, bytes, and hex '
      'characters - with family and security status. MD5 and SHA-1 are flagged '
      'broken/deprecated for security use.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hash & Crypto Output Lengths'),
        toolbarHeight: 64,
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload - the algorithm table as TSV. Static data, always
  /// enabled. Each row's security verdict (the §8.13 status-hued chip
  /// on-screen) is carried as the worded Status cell (§8.16 verdict-word rule).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Hash & Crypto Output Lengths')
      ..writeln()
      ..writeln(
        <String>[
          'Algorithm',
          'Bits',
          'Bytes',
          'Hex chars',
          'Family',
          'Status',
        ].join(tab),
      );
    for (final HashAlgo a in algorithms) {
      buf.writeln(
        <String>[
          a.name,
          '${a.bits}',
          '${a.bytes}',
          '${a.hexChars}',
          a.family,
          a.status,
        ].join(tab),
      );
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
                  _IntroText(text: _intro),
                  const SizedBox(height: AppSpacing.sm),
                  _algoCard(colors, text, mono),
                  ToolHelpFooter(toolId: _toolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _algoCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'Hash output lengths',
      footnote: footnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Algorithm', width: 120),
          _HeaderCell('Bits', width: 52),
          _HeaderCell('Bytes', width: 56),
          _HeaderCell('Hex', width: 48),
          _HeaderCell('Family', width: 200),
          _HeaderCell('Status', width: 124),
        ],
      ),
      rows: algorithms.map((HashAlgo a) {
        final Color tone = colors.statusToneColor(a.statusTone);
        return ReferenceRowSemantics(
          label: rowLabel(a.name, <String?>[
            '${a.bits} bits',
            '${a.bytes} bytes',
            '${a.hexChars} hex characters',
            a.family,
            'status ${a.status}',
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 120,
                  child: Text(
                    a.name,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${a.bits}',
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '${a.bytes}',
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${a.hexChars}',
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: Text(
                    a.family,
                    style: text.labelSmall?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 124,
                  child: _StatusChip(label: a.status, color: tone),
                ),
              ],
            ),
          ),
        );
      }).toList(),
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

/// Verdict chip. The 1px border takes the §8.13 status token; a subtle tint band
/// uses the same token at 12% alpha. The verdict word renders in textPrimary, so
/// color is never the sole carrier of meaning (SC 1.4.1), and the §8.13 border
/// clears SC 1.4.11 (3:1 non-text) on surface1. Verbatim from the wpa_security
/// `_StatusChip` idiom.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: t.labelSmall?.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
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
