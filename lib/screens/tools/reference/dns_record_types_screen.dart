// DNS Record Types — a read-only reference card for the DNS resource-record
// TYPE codes a network / Wi-Fi pro meets: the numeric TYPE code, what the
// record does, and the RFC that defines it.
//
// DATA SOURCE: the IANA DNS Resource Record (RR) TYPEs registry
// (iana.org/assignments/dns-parameters) for the numeric TYPE codes, plus the
// defining RFC cited per row. Values are reproduced verbatim from the verified
// dataset Deliverables/2026-06-08-reference-batch/protocols-data.md, which
// cross-checked each code against the live IANA registry (CAA now governed by
// RFC 8659 obsoleting RFC 6844; HTTPS/SVCB by RFC 9460). Plain-English purpose
// lines summarize the defining RFC; nothing is invented.
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const dataset always renders. No loading/empty/error path
// because nothing is fetched or parsed at runtime (GL-008 network/subprocess
// rules do not apply — nothing to fabricate, nothing to shell out to).
//
// Pattern: mirrors poe_reference_screen — Scaffold + AppBar (toolbarHeight 64,
// AppCopyAction), SafeArea(top: false), LayoutBuilder isDesktop @720,
// ConstrainedBox to calculatorMaxWidth, SingleChildScrollView, a
// ConceptGraphicBand header (degrades to nothing when no asset), one wide table
// in a HorizontalScrollTable + IntrinsicWidth grid with fixed-width cells, and
// a ToolHelpFooter. Each row is wrapped in ReferenceRowSemantics so a screen
// reader reads it as one node.
//
// Glyph note: ASCII only; no em dash. Type names and RFC numbers render in the
// mono family (Roboto Mono inline-code) since they are identifiers.

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

/// One DNS resource-record type: its mnemonic, numeric TYPE code, a plain-English
/// purpose, and the defining RFC. Field values mirror the verified dataset.
@immutable
class DnsRecordType {
  const DnsRecordType({
    required this.type,
    required this.code,
    required this.purpose,
    required this.rfc,
  });

  /// Record-type mnemonic, e.g. `A`, `AAAA`, `CNAME`.
  final String type;

  /// IANA numeric TYPE code (e.g. 1 for A, 28 for AAAA).
  final int code;

  /// Plain-English summary of what the record does.
  final String purpose;

  /// The defining RFC, e.g. `RFC 1035`.
  final String rfc;
}

class DnsRecordTypesScreen extends StatelessWidget {
  const DnsRecordTypesScreen({super.key});

  /// The DNS record types. TYPE codes verbatim from the IANA registry; purpose
  /// + RFC per the verified dataset (protocols-data.md, Page 1).
  static const List<DnsRecordType> records = <DnsRecordType>[
    DnsRecordType(
      type: 'A',
      code: 1,
      purpose: 'Maps a hostname to an IPv4 address.',
      rfc: 'RFC 1035',
    ),
    DnsRecordType(
      type: 'AAAA',
      code: 28,
      purpose: 'Maps a hostname to an IPv6 address.',
      rfc: 'RFC 3596',
    ),
    DnsRecordType(
      type: 'CNAME',
      code: 5,
      purpose: 'Aliases one name to another (canonical name).',
      rfc: 'RFC 1035',
    ),
    DnsRecordType(
      type: 'MX',
      code: 15,
      purpose: 'Names the mail servers for a domain, with priority.',
      rfc: 'RFC 1035',
    ),
    DnsRecordType(
      type: 'NS',
      code: 2,
      purpose: 'Delegates a zone to a set of authoritative name servers.',
      rfc: 'RFC 1035',
    ),
    DnsRecordType(
      type: 'TXT',
      code: 16,
      purpose:
          'Holds arbitrary text; carries SPF, DKIM, domain verification.',
      rfc: 'RFC 1035',
    ),
    DnsRecordType(
      type: 'SOA',
      code: 6,
      purpose: 'Start of Authority: zone serial, primary server, timers.',
      rfc: 'RFC 1035',
    ),
    DnsRecordType(
      type: 'PTR',
      code: 12,
      purpose: 'Maps an IP address back to a hostname (reverse DNS).',
      rfc: 'RFC 1035',
    ),
    DnsRecordType(
      type: 'SRV',
      code: 33,
      purpose: 'Locates the host and port for a named service.',
      rfc: 'RFC 2782',
    ),
    DnsRecordType(
      type: 'CAA',
      code: 257,
      purpose: 'Authorizes which CAs may issue certificates for a domain.',
      rfc: 'RFC 8659',
    ),
    DnsRecordType(
      type: 'DNSKEY',
      code: 48,
      purpose: 'Publishes the public key used to verify DNSSEC signatures.',
      rfc: 'RFC 4034',
    ),
    DnsRecordType(
      type: 'DS',
      code: 43,
      purpose:
          "Delegation Signer: links a child zone's key into the parent "
          '(chain of trust).',
      rfc: 'RFC 4034',
    ),
    DnsRecordType(
      type: 'RRSIG',
      code: 46,
      purpose: 'The DNSSEC signature over a record set.',
      rfc: 'RFC 4034',
    ),
    DnsRecordType(
      type: 'NSEC',
      code: 47,
      purpose: 'Proves a name or type does not exist (authenticated denial).',
      rfc: 'RFC 4034',
    ),
    DnsRecordType(
      type: 'HTTPS',
      code: 65,
      purpose: 'Service binding for HTTPS origins (ALPN, ECH, IP hints).',
      rfc: 'RFC 9460',
    ),
    DnsRecordType(
      type: 'SVCB',
      code: 64,
      purpose:
          'Generic service binding record (HTTPS is its HTTP-specific form).',
      rfc: 'RFC 9460',
    ),
    DnsRecordType(
      type: 'NAPTR',
      code: 35,
      purpose:
          'Naming Authority Pointer: regex-based rewrites for service '
          'discovery (ENUM, SIP).',
      rfc: 'RFC 3403',
    ),
    DnsRecordType(
      type: 'TLSA',
      code: 52,
      purpose: 'Binds a TLS certificate or key to a name for DANE.',
      rfc: 'RFC 6698',
    ),
  ];

  /// Footnote — registry + RFC provenance.
  static const String footnote =
      'TYPE codes are from the IANA DNS Resource Record (RR) TYPEs registry; '
      'each row cites its defining RFC. CAA is now governed by RFC 8659 '
      '(obsoleting RFC 6844); HTTPS and SVCB by RFC 9460.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DNS Record Types'),
        toolbarHeight: 64,
        // §8.16 — copy the reference as one-section TSV. Static data, always
        // enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the record-type table as a single-section TSV. Header
  /// + one tab-separated row per record. Columns: Type, Code, Purpose, RFC.
  /// Always non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('DNS Record Types')
      ..writeln()
      ..writeln(<String>['Type', 'Code', 'Purpose', 'RFC'].join(tab));
    for (final DnsRecordType r in records) {
      buf.writeln(
        <String>['${r.code}', r.type, r.purpose, r.rfc].join(tab),
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
                  ConceptGraphicBand(
                    toolId: 'dns-record-types',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('dns-record-types'))
                    const SizedBox(height: AppSpacing.md),
                  _recordsCard(colors, text, mono),
                  ToolHelpFooter(toolId: 'dns-record-types'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _recordsCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'Resource record types',
      footnote: footnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Type', width: 80),
          _HeaderCell('Code', width: 56),
          _HeaderCell('Purpose', width: 320),
          _HeaderCell('RFC', width: 88),
        ],
      ),
      rows: records.map((DnsRecordType r) {
        return ReferenceRowSemantics(
          label: rowLabel('Type ${r.type}', <String?>[
            'code ${r.code}',
            r.purpose,
            r.rfc,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 80,
                  child: Text(
                    r.type,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '${r.code}',
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: Text(
                    r.purpose,
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 88,
                  child: Text(
                    r.rfc,
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

/// Card surface wrapping a wide table: title (full-width, wraps) over a
/// horizontally-scrolling IntrinsicWidth grid (header + rows share one width so
/// columns align), with an optional full-width footnote beneath. Matches the
/// poe_reference_screen / wifi_channels_screen overflow-safe idiom.
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
