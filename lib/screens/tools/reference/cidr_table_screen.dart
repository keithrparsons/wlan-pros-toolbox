// Subnetting / CIDR Table — read-only /0 through /32 lookup: prefix, dotted
// mask, total addresses, usable hosts, and wildcard mask.
//
// Part of the "Addressing & Subnetting" reference sub-category. Mirrors the
// poe_reference_screen / power_phasing_screen template exactly: a typed const
// dataset on the screen class, a §8.16 AppCopyAction that emits the table as
// TSV, the shared LayoutBuilder / ConstrainedBox / SingleChildScrollView
// scaffold, and a ToolHelpFooter keyed on the catalog id.
//
// Data provenance (GL-005): every row is sourced from the verified addressing
// dataset (Deliverables/2026-06-08-reference-batch/addressing-data.md, Section
// 2) — pure arithmetic per the CIDR prefix model (total = 2^(32-n)), cross-
// referenced to RFC 4632 §3.1. The /31 and /32 EXCEPTIONS are honored:
//   * /31 = 2 USABLE host addresses (point-to-point, RFC 3021), NOT "0 usable".
//   * /32 = 1 host (single-host route, RFC 4632), NOT "-1".
// These two rows carry a `usableNote` string that renders inline next to the
// usable-hosts figure and is called out in the card footnote.
//
// CROSS-LINK: a one-line note points the user to the existing IPv4 Subnet
// Calculator tool for computing a specific network/broadcast/range. The link is
// rendered as plain reference text (this read-only screen does not navigate);
// Larry confirms the calculator's catalog id during the integration pass.
//
// Pure read-only reference — no inputs, no computation at runtime, no network.
// Works on every platform (no NetworkUnavailableView). The only state is
// "success": the compile-time const dataset always renders. No loading/empty/
// error path (GL-008 network/subprocess rules do not apply).
//
// Glyph notes (GL-004): ASCII hyphen-minus only, never an em dash; thousands
// separators use commas; prefixes and masks render in the mono inline-code
// register.

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

/// One CIDR-prefix row: prefix length, dotted subnet mask, total addresses,
/// usable hosts, and wildcard mask. Values are sourced verbatim from the
/// verified addressing dataset (Section 2).
@immutable
class CidrRow {
  const CidrRow({
    required this.prefix,
    required this.mask,
    required this.total,
    required this.usableHosts,
    required this.wildcard,
    this.usableNote,
  });

  /// Prefix length, 0-32 (rendered as `/n`).
  final int prefix;

  /// Dotted-decimal subnet mask, e.g. `255.255.255.0`.
  final String mask;

  /// Total addresses in the block, 2^(32-prefix).
  final int total;

  /// Usable host count. For /0-/30 this is total - 2; the /31 and /32
  /// exceptions override the arithmetic (see [usableNote]).
  final int usableHosts;

  /// Wildcard (inverse) mask, e.g. `0.0.0.255`.
  final String wildcard;

  /// Short exception note rendered inline next to the usable figure for the
  /// /31 (point-to-point, RFC 3021) and /32 (single host) rows. `null` for the
  /// standard total-minus-two rows.
  final String? usableNote;
}

class CidrTableScreen extends StatelessWidget {
  const CidrTableScreen({super.key});

  /// The /0 through /32 table. Verbatim from dataset Section 2. Total =
  /// 2^(32-n); usable = total - 2 except the /31 and /32 exceptions.
  static const List<CidrRow> rows = <CidrRow>[
    CidrRow(prefix: 0, mask: '0.0.0.0', total: 4294967296, usableHosts: 4294967294, wildcard: '255.255.255.255'),
    CidrRow(prefix: 1, mask: '128.0.0.0', total: 2147483648, usableHosts: 2147483646, wildcard: '127.255.255.255'),
    CidrRow(prefix: 2, mask: '192.0.0.0', total: 1073741824, usableHosts: 1073741822, wildcard: '63.255.255.255'),
    CidrRow(prefix: 3, mask: '224.0.0.0', total: 536870912, usableHosts: 536870910, wildcard: '31.255.255.255'),
    CidrRow(prefix: 4, mask: '240.0.0.0', total: 268435456, usableHosts: 268435454, wildcard: '15.255.255.255'),
    CidrRow(prefix: 5, mask: '248.0.0.0', total: 134217728, usableHosts: 134217726, wildcard: '7.255.255.255'),
    CidrRow(prefix: 6, mask: '252.0.0.0', total: 67108864, usableHosts: 67108862, wildcard: '3.255.255.255'),
    CidrRow(prefix: 7, mask: '254.0.0.0', total: 33554432, usableHosts: 33554430, wildcard: '1.255.255.255'),
    CidrRow(prefix: 8, mask: '255.0.0.0', total: 16777216, usableHosts: 16777214, wildcard: '0.255.255.255'),
    CidrRow(prefix: 9, mask: '255.128.0.0', total: 8388608, usableHosts: 8388606, wildcard: '0.127.255.255'),
    CidrRow(prefix: 10, mask: '255.192.0.0', total: 4194304, usableHosts: 4194302, wildcard: '0.63.255.255'),
    CidrRow(prefix: 11, mask: '255.224.0.0', total: 2097152, usableHosts: 2097150, wildcard: '0.31.255.255'),
    CidrRow(prefix: 12, mask: '255.240.0.0', total: 1048576, usableHosts: 1048574, wildcard: '0.15.255.255'),
    CidrRow(prefix: 13, mask: '255.248.0.0', total: 524288, usableHosts: 524286, wildcard: '0.7.255.255'),
    CidrRow(prefix: 14, mask: '255.252.0.0', total: 262144, usableHosts: 262142, wildcard: '0.3.255.255'),
    CidrRow(prefix: 15, mask: '255.254.0.0', total: 131072, usableHosts: 131070, wildcard: '0.1.255.255'),
    CidrRow(prefix: 16, mask: '255.255.0.0', total: 65536, usableHosts: 65534, wildcard: '0.0.255.255'),
    CidrRow(prefix: 17, mask: '255.255.128.0', total: 32768, usableHosts: 32766, wildcard: '0.0.127.255'),
    CidrRow(prefix: 18, mask: '255.255.192.0', total: 16384, usableHosts: 16382, wildcard: '0.0.63.255'),
    CidrRow(prefix: 19, mask: '255.255.224.0', total: 8192, usableHosts: 8190, wildcard: '0.0.31.255'),
    CidrRow(prefix: 20, mask: '255.255.240.0', total: 4096, usableHosts: 4094, wildcard: '0.0.15.255'),
    CidrRow(prefix: 21, mask: '255.255.248.0', total: 2048, usableHosts: 2046, wildcard: '0.0.7.255'),
    CidrRow(prefix: 22, mask: '255.255.252.0', total: 1024, usableHosts: 1022, wildcard: '0.0.3.255'),
    CidrRow(prefix: 23, mask: '255.255.254.0', total: 512, usableHosts: 510, wildcard: '0.0.1.255'),
    CidrRow(prefix: 24, mask: '255.255.255.0', total: 256, usableHosts: 254, wildcard: '0.0.0.255'),
    CidrRow(prefix: 25, mask: '255.255.255.128', total: 128, usableHosts: 126, wildcard: '0.0.0.127'),
    CidrRow(prefix: 26, mask: '255.255.255.192', total: 64, usableHosts: 62, wildcard: '0.0.0.63'),
    CidrRow(prefix: 27, mask: '255.255.255.224', total: 32, usableHosts: 30, wildcard: '0.0.0.31'),
    CidrRow(prefix: 28, mask: '255.255.255.240', total: 16, usableHosts: 14, wildcard: '0.0.0.15'),
    CidrRow(prefix: 29, mask: '255.255.255.248', total: 8, usableHosts: 6, wildcard: '0.0.0.7'),
    CidrRow(prefix: 30, mask: '255.255.255.252', total: 4, usableHosts: 2, wildcard: '0.0.0.3'),
    CidrRow(
      prefix: 31,
      mask: '255.255.255.254',
      total: 2,
      usableHosts: 2,
      wildcard: '0.0.0.1',
      usableNote: 'point-to-point, RFC 3021',
    ),
    CidrRow(
      prefix: 32,
      mask: '255.255.255.255',
      total: 1,
      usableHosts: 1,
      wildcard: '0.0.0.0',
      usableNote: 'single host',
    ),
  ];

  /// The /31 and /32 exception note, shown beneath the table.
  static const String exceptionNote =
      'Usable hosts = total minus 2 (network + broadcast), with two '
      'exceptions: a /31 carries 2 usable host addresses on a point-to-point '
      'link (RFC 3021), and a /32 is a single-host route (1 host). For very '
      'short prefixes (/0, /1) the usable figure is the literal 2^(32-n) minus '
      '2 arithmetic; in practice these are routing aggregates, not host '
      'subnets.';

  /// Cross-link to the existing IPv4 Subnet Calculator tool. The screen is
  /// read-only and does not navigate; this is a discoverability pointer.
  static const String calculatorCrossLink =
      'Need a specific network, broadcast, and host range? Use the IPv4 Subnet '
      'Calculator tool.';

  /// Provenance footnote shown at the foot of the card.
  static const String footnote =
      'Source: arithmetic per the CIDR prefix model, RFC 4632 §3.1. The /31 '
      'point-to-point exception is RFC 3021; the /32 host-route convention is '
      'RFC 4632.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subnetting / CIDR Table'),
        toolbarHeight: 64,
        // §8.16 — copy the whole /0-/32 table as TSV. The /31 and /32 rows
        // append their exception note to the usable-hosts cell so the pasted
        // text carries the exception. Static data, always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the full table as one TSV section, plus the exception
  /// note and the calculator cross-link. Always non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Subnetting / CIDR Table')
      ..writeln()
      ..writeln(
        <String>[
          'Prefix',
          'Dotted Mask',
          'Total Addresses',
          'Usable Hosts',
          'Wildcard Mask',
        ].join(tab),
      );
    for (final CidrRow r in rows) {
      final String usable = r.usableNote == null
          ? _grouped(r.usableHosts)
          : '${_grouped(r.usableHosts)} (${r.usableNote})';
      buf.writeln(
        <String>[
          '/${r.prefix}',
          r.mask,
          _grouped(r.total),
          usable,
          r.wildcard,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln(exceptionNote)
      ..writeln()
      ..writeln(calculatorCrossLink)
      ..writeln()
      ..writeln(footnote);
    return buf.toString().trimRight();
  }

  Widget _body(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
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
                  ConceptGraphicBand(
                    toolId: 'cidr-table',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('cidr-table'))
                    const SizedBox(height: AppSpacing.md),
                  _crossLinkCard(colors, text),
                  const SizedBox(height: AppSpacing.md),
                  _tableCard(colors, text, mono),
                  ToolHelpFooter(toolId: 'cidr-table'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The cross-link pointer card to the IPv4 Subnet Calculator. Rendered as a
  /// distinct surface above the table so it reads as guidance, not data.
  Widget _crossLinkCard(AppColorScheme colors, TextTheme text) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Text(
        calculatorCrossLink,
        style: text.bodyMedium?.copyWith(color: colors.textSecondary),
      ),
    );
  }

  Widget _tableCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'Prefix /0 to /32',
      note: exceptionNote,
      footnote: footnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Prefix', width: 56),
          _HeaderCell('Dotted Mask', width: 144),
          _HeaderCell('Total Addresses', width: 136),
          _HeaderCell('Usable Hosts', width: 232),
          _HeaderCell('Wildcard Mask', width: 144),
        ],
      ),
      rows: rows.map((CidrRow r) {
        return ReferenceRowSemantics(
          label: rowLabel('/${r.prefix}', <String?>[
            'mask ${r.mask}',
            'total ${_grouped(r.total)}',
            r.usableNote == null
                ? '${_grouped(r.usableHosts)} usable hosts'
                : '${_grouped(r.usableHosts)} usable, ${r.usableNote}',
            'wildcard ${r.wildcard}',
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 56,
                  child: Text(
                    '/${r.prefix}',
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 144,
                  child: Text(
                    r.mask,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 136,
                  child: Text(
                    _grouped(r.total),
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 232,
                  child: _UsableCell(
                    value: _grouped(r.usableHosts),
                    note: r.usableNote,
                    colors: colors,
                    text: text,
                    mono: mono,
                  ),
                ),
                SizedBox(
                  width: 144,
                  child: Text(
                    r.wildcard,
                    style: mono.inlineCode.copyWith(
                      color: colors.textTertiary,
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

  /// Format an int with comma thousands separators (e.g. 4294967296 ->
  /// "4,294,967,296"). US-locale grouping, ASCII commas only.
  static String _grouped(int n) {
    final String s = n.toString();
    final StringBuffer out = StringBuffer();
    final int firstGroup = s.length % 3;
    for (int i = 0; i < s.length; i++) {
      if (i != 0 && (i - firstGroup) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }
}

/// The usable-hosts cell: the figure in the mono numeric register, with the
/// /31 or /32 exception note wrapping beneath it when present (so a tech sees
/// "2" alongside "point-to-point, RFC 3021" rather than a misleading bare 2).
class _UsableCell extends StatelessWidget {
  const _UsableCell({
    required this.value,
    required this.note,
    required this.colors,
    required this.text,
    required this.mono,
  });

  final String value;
  final String? note;
  final AppColorScheme colors;
  final TextTheme text;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          style: mono.inlineCode.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (note != null)
          Text(
            note!,
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
      ],
    );
  }
}

/// Card surface wrapping a wide table: title over an optional note, then a
/// horizontally-scrolling IntrinsicWidth grid (header + rows share one width so
/// columns align), with an optional full-width footnote beneath. Matches the
/// poe_reference_screen / power_phasing_screen overflow-safe idiom.
class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.title,
    required this.header,
    required this.rows,
    this.note,
    this.footnote,
  });

  final String title;
  final Widget header;
  final List<Widget> rows;
  final String? note;
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
          if (note != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              note!,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ],
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
