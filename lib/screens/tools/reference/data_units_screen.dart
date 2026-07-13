// Data Units & Prefixes - read-only reference for the two parallel size ladders
// (SI decimal kB/MB/GB... vs IEC binary KiB/MiB/GiB...), the exact byte counts,
// the compounding divergence between them, and the bit-vs-byte (b vs B, x8)
// distinction.
//
// Data ported verbatim from the verified dataset at
// Deliverables/2026-06-08-reference-batch/time-encoding-improvements-data.md
// SECTION 2 (DATA UNITS & BINARY-VS-DECIMAL PREFIXES - NEW PAGE), subsections
// 2A and 2B. Byte counts and divergence percentages trace to IEC 80000-13:2008
// and the BIPM SI Brochure (9th ed.).
//
// Pure read-only reference - no inputs, no computation, no network. The only
// state is "success": the compile-time const datasets always render. No loading
// / empty / error / disabled path (SOP-007 §5: structurally impossible, not
// skipped). GL-008 network/subprocess rules do not apply.
//
// Pattern: mirrors poe_reference_screen exactly - Scaffold + AppBar
// (toolbarHeight 64) with §8.16 AppCopyAction, SafeArea(top: false),
// LayoutBuilder isDesktop @720, ConstrainedBox to calculatorMaxWidth,
// SingleChildScrollView of cards, ToolHelpFooter. The wide ladder table uses the
// HorizontalScrollTable + IntrinsicWidth fixed-width-cell idiom; each row is
// wrapped in ReferenceRowSemantics.
//
// Concept graphic: this page references a NAMED graphic, data-units-prefixes.svg
// (the dual-ladder diagram), resolved through the convention asset resolver
// (ToolAssets.graphicPath / ConceptGraphicBand keyed on the graphic id rather
// than the catalog id). It degrades gracefully - when the SVG is not yet
// bundled (Charta authors it later), the band collapses to nothing and no
// broken-image box appears. The catalog id remains `data-units`.
//
// Glyph note: ASCII hyphen-minus only; no em dash. The "x8" multiplier uses a
// lowercase x, not a multiplication sign, to stay ASCII-safe.

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

/// One rung of the dual SI/IEC ladder: the SI symbol + its exact byte count, the
/// IEC symbol + its exact byte count, and the divergence at that rank. Mirrors
/// the source §2A table columns.
@immutable
class UnitLadderRow {
  const UnitLadderRow({
    required this.siSymbol,
    required this.siPower,
    required this.siBytes,
    required this.iecSymbol,
    required this.iecPower,
    required this.iecBytes,
    required this.divergence,
  });

  /// SI (decimal) symbol, e.g. `kB`, `MB`.
  final String siSymbol;

  /// SI power-of-ten label, e.g. `10^3`.
  final String siPower;

  /// SI exact byte count, grouped, e.g. `1,000`.
  final String siBytes;

  /// IEC (binary) symbol, e.g. `KiB`, `MiB`.
  final String iecSymbol;

  /// IEC power-of-two label, e.g. `2^10`.
  final String iecPower;

  /// IEC exact byte count, grouped, e.g. `1,024`.
  final String iecBytes;

  /// Divergence (IEC larger than SI) at this rank, e.g. `2.40%`.
  final String divergence;
}

/// One bit-vs-byte row (§2B).
@immutable
class BitByteRow {
  const BitByteRow({
    required this.symbol,
    required this.unit,
    required this.equals,
  });

  /// The symbol, `b` or `B`.
  final String symbol;

  /// The unit name.
  final String unit;

  /// What it equals.
  final String equals;
}

class DataUnitsScreen extends StatelessWidget {
  const DataUnitsScreen({super.key});

  /// Catalog id (drives the help lookup, route, and catalog entry).
  static const String _toolId = 'data-units';

  /// Named concept-graphic id - resolves to assets/tool-graphics/
  /// data-units-prefixes.svg via the convention resolver. Distinct from the
  /// catalog id because the diagram is the dual-ladder illustration, not a
  /// generic per-tool icon. Degrades gracefully when not yet bundled.
  static const String _graphicId = 'data-units-prefixes';

  /// §2A - the two parallel ladders. Ported verbatim from the dataset.
  static const List<UnitLadderRow> ladder = <UnitLadderRow>[
    UnitLadderRow(
      siSymbol: 'kB',
      siPower: '10^3',
      siBytes: '1,000',
      iecSymbol: 'KiB',
      iecPower: '2^10',
      iecBytes: '1,024',
      divergence: '2.40%',
    ),
    UnitLadderRow(
      siSymbol: 'MB',
      siPower: '10^6',
      siBytes: '1,000,000',
      iecSymbol: 'MiB',
      iecPower: '2^20',
      iecBytes: '1,048,576',
      divergence: '4.86%',
    ),
    UnitLadderRow(
      siSymbol: 'GB',
      siPower: '10^9',
      siBytes: '1,000,000,000',
      iecSymbol: 'GiB',
      iecPower: '2^30',
      iecBytes: '1,073,741,824',
      divergence: '7.37%',
    ),
    UnitLadderRow(
      siSymbol: 'TB',
      siPower: '10^12',
      siBytes: '1,000,000,000,000',
      iecSymbol: 'TiB',
      iecPower: '2^40',
      iecBytes: '1,099,511,627,776',
      divergence: '9.95%',
    ),
    UnitLadderRow(
      siSymbol: 'PB',
      siPower: '10^15',
      siBytes: '1,000,000,000,000,000',
      iecSymbol: 'PiB',
      iecPower: '2^50',
      iecBytes: '1,125,899,906,842,624',
      divergence: '12.59%',
    ),
    UnitLadderRow(
      siSymbol: 'EB',
      siPower: '10^18',
      siBytes: '1,000,000,000,000,000,000',
      iecSymbol: 'EiB',
      iecPower: '2^60',
      iecBytes: '1,152,921,504,606,846,976',
      divergence: '15.29%',
    ),
  ];

  static const String ladderFootnote =
      'Divergence = (binary - decimal) / decimal: how much larger the IEC unit '
      'is than the SI unit of the same rank. It compounds ~2.4 points per step '
      '(the gap is 1.024^n - 1). SI uses lowercase k for kilo (kB), uppercase '
      'for M and above; IEC binary prefixes are Ki, Mi, Gi, Ti, Pi, Ei - note '
      "Ki is a capital K, unlike SI's lowercase k.";

  /// §2B - bit vs byte.
  static const List<BitByteRow> bitByte = <BitByteRow>[
    BitByteRow(symbol: 'b', unit: 'bit', equals: '1 binary digit'),
    BitByteRow(symbol: 'B', unit: 'byte (octet)', equals: '8 bits'),
  ];

  static const String bitByteFootnote =
      'Network/link speeds are quoted in bits per second (bps, kbps, Mbps, '
      'Gbps) - decimal prefixes. A "1 Gbps" link = 1,000,000,000 bits/s. '
      'Storage and file sizes are quoted in bytes. Practical conversion: divide '
      'a bit-rate by 8 for theoretical byte throughput - 100 Mbps / 8 = '
      '12.5 MB/s (before overhead). Reading "Mbps" as "MB/s" produces an 8x '
      'error. A drive sold as "1 TB" = 1,000,000,000,000 bytes (SI), but an OS '
      // Label fix (Wave-2 finding C): the 1000->931 illusion is the GB/GiB
      // division step (7.37%), not TB/TiB (which is 9.95% per this screen's own
      // ladder). The OS divides bytes by 2^30 = GiB, so the gap that shows is
      // the GB/GiB one. Value 7.37% was correct; only the label was wrong.
      'reporting in binary shows ~931 GiB - the 7.37% GB/GiB gap is why a '
      '"1 TB" drive appears to lose capacity on screen.';

  static const String _intro =
      'The two parallel size ladders - SI decimal (kB, MB, GB) vs IEC binary '
      '(KiB, MiB, GiB) - their exact byte counts, the compounding divergence '
      'between them, and the bit-vs-byte (b vs B, x8) distinction.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Units & Prefixes'),
        toolbarHeight: 64,
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload - both sections as TSV blocks. Static data, always
  /// enabled / non-null.
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Data Units & Prefixes')
      ..writeln()
      ..writeln('SI decimal vs IEC binary ladders')
      ..writeln(
        <String>[
          'SI',
          'SI power',
          'SI bytes',
          'IEC',
          'IEC power',
          'IEC bytes',
          'Divergence',
        ].join(tab),
      );
    for (final UnitLadderRow r in ladder) {
      buf.writeln(
        <String>[
          r.siSymbol,
          r.siPower,
          r.siBytes,
          r.iecSymbol,
          r.iecPower,
          r.iecBytes,
          r.divergence,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('Bit vs byte')
      ..writeln(<String>['Symbol', 'Unit', 'Equals'].join(tab));
    for (final BitByteRow b in bitByte) {
      buf.writeln(<String>[b.symbol, b.unit, b.equals].join(tab));
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
                  // Named graphic, resolved by graphic id and gated on the
                  // build-time asset manifest - degrades to nothing when the
                  // SVG is not bundled.
                  ConceptGraphicBand(toolId: _graphicId, isDesktop: isDesktop),
                  if (ToolAssets.hasGraphic(_graphicId))
                    const SizedBox(height: AppSpacing.md),
                  _IntroText(text: _intro),
                  const SizedBox(height: AppSpacing.sm),
                  _ladderCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _bitByteCard(colors, text, mono),
                  ToolHelpFooter(toolId: _toolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _ladderCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'SI decimal vs IEC binary ladders',
      footnote: ladderFootnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('SI', width: 56),
          _HeaderCell('Power', width: 60),
          _HeaderCell('SI bytes', width: 200),
          _HeaderCell('IEC', width: 56),
          _HeaderCell('Power', width: 60),
          _HeaderCell('IEC bytes', width: 220),
          _HeaderCell('Diverge', width: 72),
        ],
      ),
      rows: ladder.map((UnitLadderRow r) {
        return ReferenceRowSemantics(
          label: rowLabel(r.siSymbol, <String?>[
            '${r.siPower} = ${r.siBytes} bytes',
            '${r.iecSymbol} ${r.iecPower} = ${r.iecBytes} bytes',
            'divergence ${r.divergence}',
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 56,
                  child: Text(
                    r.siSymbol,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    r.siPower,
                    style: mono.inlineCode.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: Text(
                    r.siBytes,
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    r.iecSymbol,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    r.iecPower,
                    style: mono.inlineCode.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: Text(
                    r.iecBytes,
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    r.divergence,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
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

  Widget _bitByteCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'Bit vs byte (b vs B)',
      footnote: bitByteFootnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Symbol', width: 72),
          _HeaderCell('Unit', width: 140),
          _HeaderCell('Equals', width: 160),
        ],
      ),
      rows: bitByte.map((BitByteRow b) {
        return ReferenceRowSemantics(
          label: rowLabel(b.symbol, <String?>[b.unit, b.equals]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 72,
                  child: Text(
                    b.symbol,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: Text(
                    b.unit,
                    style: text.labelMedium?.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: Text(
                    b.equals,
                    style: mono.inlineCode.copyWith(
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
