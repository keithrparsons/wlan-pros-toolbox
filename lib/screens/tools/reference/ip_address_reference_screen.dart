// IP Address Reference — read-only reference of IANA/IETF special-use address
// blocks for IPv4 and IPv6, plus the IPv6 text-notation rules.
//
// Part of the "Addressing & Subnetting" reference sub-category. Mirrors the
// poe_reference_screen / power_phasing_screen template exactly: typed const
// datasets on the screen class, a §8.16 AppCopyAction that emits the whole page
// as sectioned TSV, the shared LayoutBuilder / ConstrainedBox /
// SingleChildScrollView scaffold, and a ToolHelpFooter keyed on the catalog id.
//
// Data provenance (GL-005): every row is sourced verbatim from the verified
// build dataset (Deliverables/2026-06-08-reference-batch/addressing-data.md,
// Section 1), assembled from the IANA IPv4/IPv6 Special-Purpose Address
// Registries (fetched 2026-06-08) cross-checked against each defining RFC.
//   * MULTICAST-REGISTRY SPLIT FLAG (honored): the multicast blocks
//     224.0.0.0/4 (IPv4) and ff00::/8 (IPv6) are NOT carried in the IANA
//     special-purpose registries — they live in the separate IANA multicast
//     registries and are sourced to their defining RFCs (RFC 5771 / RFC 1112;
//     RFC 4291 §2.7). Each carries a `multicastRegistry: true` flag so the row
//     renders a footnote marker and the card footnote explains the split.
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const datasets always render. No loading/empty/error path
// because nothing is fetched or parsed at runtime (GL-008 network/subprocess
// rules do not apply — nothing to fabricate, nothing to shell out to).
//
// Glyph notes (GL-004): "Wi-Fi" never "WiFi"; ASCII hyphen-minus only, never an
// em dash; CIDR prefixes and addresses render in the mono inline-code register.

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

/// One special-use address block — a CIDR prefix, its purpose, and the defining
/// RFC. Used for both the IPv4 and IPv6 tables. Field values are sourced
/// verbatim from the verified addressing dataset (Section 1A / 1B).
@immutable
class SpecialUseBlock {
  const SpecialUseBlock({
    required this.cidr,
    required this.purpose,
    required this.rfc,
    this.multicastRegistry = false,
  });

  /// The address block in CIDR notation, e.g. `10.0.0.0/8` or `fc00::/7`.
  final String cidr;

  /// What the block is reserved for, e.g. `Private-Use (RFC 1918)`.
  final String purpose;

  /// The defining RFC reference, e.g. `RFC 1918` or `RFC 4291 §2.7`.
  final String rfc;

  /// `true` for the multicast blocks (224.0.0.0/4, ff00::/8) that live in the
  /// IANA multicast registries rather than the special-purpose registries, so
  /// they are sourced to their defining RFCs and flagged in the card footnote.
  final bool multicastRegistry;
}

/// One IPv6 text-notation rule — the canonical-form and compression rules a tech
/// needs to read and write IPv6 addresses correctly. Sourced from Section 1C.
@immutable
class Ipv6NotationRule {
  const Ipv6NotationRule({
    required this.rule,
    required this.definition,
    required this.source,
  });

  /// Short rule name, e.g. `Zero compression (::)`.
  final String rule;

  /// The rule's definition in prose.
  final String definition;

  /// The defining RFC reference, e.g. `RFC 5952 §4`.
  final String source;
}

class IpAddressReferenceScreen extends StatelessWidget {
  const IpAddressReferenceScreen({super.key});

  /// IPv4 special-purpose address blocks. Verbatim from dataset Section 1A.
  static const List<SpecialUseBlock> ipv4Blocks = <SpecialUseBlock>[
    SpecialUseBlock(
      cidr: '0.0.0.0/8',
      purpose: '"This network" (this host on this network, source only)',
      rfc: 'RFC 791 §3.2',
    ),
    SpecialUseBlock(
      cidr: '0.0.0.0/32',
      purpose: '"This host on this network"',
      rfc: 'RFC 1122 §3.2.1.3',
    ),
    SpecialUseBlock(
      cidr: '10.0.0.0/8',
      purpose: 'Private-Use (RFC 1918)',
      rfc: 'RFC 1918',
    ),
    SpecialUseBlock(
      cidr: '100.64.0.0/10',
      purpose: 'Shared Address Space (Carrier-Grade NAT / CGNAT)',
      rfc: 'RFC 6598',
    ),
    SpecialUseBlock(
      cidr: '127.0.0.0/8',
      purpose: 'Loopback',
      rfc: 'RFC 1122 §3.2.1.3',
    ),
    SpecialUseBlock(
      cidr: '169.254.0.0/16',
      purpose: 'Link-Local (APIPA)',
      rfc: 'RFC 3927',
    ),
    SpecialUseBlock(
      cidr: '172.16.0.0/12',
      purpose: 'Private-Use (RFC 1918)',
      rfc: 'RFC 1918',
    ),
    SpecialUseBlock(
      cidr: '192.0.0.0/24',
      purpose: 'IETF Protocol Assignments',
      rfc: 'RFC 6890 §2.1',
    ),
    SpecialUseBlock(
      cidr: '192.0.0.0/29',
      purpose: 'IPv4 Service Continuity Prefix (DS-Lite)',
      rfc: 'RFC 7335',
    ),
    SpecialUseBlock(
      cidr: '192.0.0.8/32',
      purpose: 'IPv4 dummy address',
      rfc: 'RFC 7600',
    ),
    SpecialUseBlock(
      cidr: '192.0.0.9/32',
      purpose: 'Port Control Protocol (PCP) Anycast',
      rfc: 'RFC 7723',
    ),
    SpecialUseBlock(
      cidr: '192.0.0.10/32',
      purpose: 'TURN Anycast (Traversal Using Relays around NAT)',
      rfc: 'RFC 8155',
    ),
    SpecialUseBlock(
      cidr: '192.0.0.170/32, 192.0.0.171/32',
      purpose: 'NAT64/DNS64 Discovery',
      rfc: 'RFC 8880, RFC 7050 §2.2',
    ),
    SpecialUseBlock(
      cidr: '192.0.2.0/24',
      purpose: 'Documentation (TEST-NET-1)',
      rfc: 'RFC 5737',
    ),
    SpecialUseBlock(
      cidr: '192.31.196.0/24',
      purpose: 'AS112-v4',
      rfc: 'RFC 7535',
    ),
    SpecialUseBlock(
      cidr: '192.52.193.0/24',
      purpose: 'AMT (Automatic Multicast Tunneling)',
      rfc: 'RFC 7450',
    ),
    SpecialUseBlock(
      cidr: '192.88.99.0/24',
      purpose: 'Deprecated (6to4 Relay Anycast)',
      rfc: 'RFC 7526',
    ),
    SpecialUseBlock(
      cidr: '192.168.0.0/16',
      purpose: 'Private-Use (RFC 1918)',
      rfc: 'RFC 1918',
    ),
    SpecialUseBlock(
      cidr: '192.175.48.0/24',
      purpose: 'Direct Delegation AS112 Service',
      rfc: 'RFC 7534',
    ),
    SpecialUseBlock(
      cidr: '198.18.0.0/15',
      purpose: 'Benchmarking',
      rfc: 'RFC 2544',
    ),
    SpecialUseBlock(
      cidr: '198.51.100.0/24',
      purpose: 'Documentation (TEST-NET-2)',
      rfc: 'RFC 5737',
    ),
    SpecialUseBlock(
      cidr: '203.0.113.0/24',
      purpose: 'Documentation (TEST-NET-3)',
      rfc: 'RFC 5737',
    ),
    SpecialUseBlock(
      cidr: '224.0.0.0/4',
      purpose: 'Multicast (Class D)',
      rfc: 'RFC 5771; RFC 1112 §4',
      multicastRegistry: true,
    ),
    SpecialUseBlock(
      cidr: '240.0.0.0/4',
      purpose: 'Reserved (former Class E)',
      rfc: 'RFC 1112 §4',
    ),
    SpecialUseBlock(
      cidr: '255.255.255.255/32',
      purpose: 'Limited Broadcast',
      rfc: 'RFC 8190; RFC 919 §7',
    ),
  ];

  /// IPv6 special-purpose address blocks. Verbatim from dataset Section 1B.
  static const List<SpecialUseBlock> ipv6Blocks = <SpecialUseBlock>[
    SpecialUseBlock(
      cidr: '::1/128',
      purpose: 'Loopback Address',
      rfc: 'RFC 4291',
    ),
    SpecialUseBlock(
      cidr: '::/128',
      purpose: 'Unspecified Address',
      rfc: 'RFC 4291',
    ),
    SpecialUseBlock(
      cidr: '::ffff:0:0/96',
      purpose: 'IPv4-mapped Address',
      rfc: 'RFC 4291',
    ),
    SpecialUseBlock(
      cidr: '64:ff9b::/96',
      purpose: 'IPv4-IPv6 Translation (NAT64 well-known prefix)',
      rfc: 'RFC 6052',
    ),
    SpecialUseBlock(
      cidr: '64:ff9b:1::/48',
      purpose: 'IPv4-IPv6 Translation (local-use NAT64)',
      rfc: 'RFC 8215',
    ),
    SpecialUseBlock(
      cidr: '100::/64',
      purpose: 'Discard-Only Address Block',
      rfc: 'RFC 6666',
    ),
    SpecialUseBlock(
      cidr: '2001::/23',
      purpose: 'IETF Protocol Assignments',
      rfc: 'RFC 2928',
    ),
    SpecialUseBlock(
      cidr: '2001::/32',
      purpose: 'TEREDO',
      rfc: 'RFC 4380, RFC 8190',
    ),
    SpecialUseBlock(
      cidr: '2001:2::/48',
      purpose: 'Benchmarking',
      rfc: 'RFC 5180',
    ),
    SpecialUseBlock(
      cidr: '2001:3::/32',
      purpose: 'AMT (Automatic Multicast Tunneling)',
      rfc: 'RFC 7450',
    ),
    SpecialUseBlock(
      cidr: '2001:4:112::/48',
      purpose: 'AS112-v6',
      rfc: 'RFC 7535',
    ),
    SpecialUseBlock(
      cidr: '2001:20::/28',
      purpose: 'ORCHIDv2',
      rfc: 'RFC 7343',
    ),
    SpecialUseBlock(
      cidr: '2001:db8::/32',
      purpose: 'Documentation',
      rfc: 'RFC 3849',
    ),
    SpecialUseBlock(
      cidr: '2002::/16',
      purpose: '6to4',
      rfc: 'RFC 3056',
    ),
    SpecialUseBlock(
      cidr: '2620:4f:8000::/48',
      purpose: 'Direct Delegation AS112 Service',
      rfc: 'RFC 7534',
    ),
    SpecialUseBlock(
      cidr: '3fff::/20',
      purpose: 'Documentation',
      rfc: 'RFC 9637',
    ),
    SpecialUseBlock(
      cidr: 'fc00::/7',
      purpose: 'Unique-Local (ULA)',
      rfc: 'RFC 4193, RFC 8190',
    ),
    SpecialUseBlock(
      cidr: 'fe80::/10',
      purpose: 'Link-Local Unicast',
      rfc: 'RFC 4291',
    ),
    SpecialUseBlock(
      cidr: 'ff00::/8',
      purpose: 'Multicast',
      rfc: 'RFC 4291 §2.7',
      multicastRegistry: true,
    ),
  ];

  /// IPv6 text-notation rules. Verbatim from dataset Section 1C.
  static const List<Ipv6NotationRule> ipv6Notation = <Ipv6NotationRule>[
    Ipv6NotationRule(
      rule: 'Address length',
      definition:
          '128 bits, written as eight 16-bit groups (hextets) separated by '
          'colons, each group 4 hex digits. Example: '
          '2001:0db8:0000:0000:0000:ff00:0042:8329.',
      source: 'RFC 4291 §2.2',
    ),
    Ipv6NotationRule(
      rule: 'Leading-zero omission',
      definition:
          'Leading zeros in any group may be omitted. 0db8 becomes db8; 0000 '
          'becomes 0.',
      source: 'RFC 4291 §2.2',
    ),
    Ipv6NotationRule(
      rule: 'Zero compression (::)',
      definition:
          'One or more consecutive all-zero groups may be replaced by a single '
          '"::". The "::" may appear only once in an address. The example above '
          'becomes 2001:db8::ff00:42:8329.',
      source: 'RFC 4291 §2.2',
    ),
    Ipv6NotationRule(
      rule: 'Canonical / recommended form',
      definition:
          'Lowercase hex; suppress all leading zeros; use "::" to compress the '
          'longest run of zero groups (and the first such run if tied); do not '
          'compress a single zero group.',
      source: 'RFC 5952 §4',
    ),
    Ipv6NotationRule(
      rule: 'Embedded IPv4 (mixed notation)',
      definition:
          'The last 32 bits may be written in dotted-decimal, e.g. '
          '::ffff:192.0.2.1.',
      source: 'RFC 4291 §2.2',
    ),
    Ipv6NotationRule(
      rule: 'Prefix notation',
      definition: 'address/prefix-length, e.g. 2001:db8::/32.',
      source: 'RFC 4291 §2.3',
    ),
  ];

  /// Footnote for the IPv4 table — explains the multicast-registry split.
  static const String ipv4Footnote =
      'Source: IANA IPv4 Special-Purpose Address Registry (fetched '
      '2026-06-08). [*] 224.0.0.0/4 is governed by the IANA IPv4 Multicast '
      'Address Space Registry (RFC 5771) and the original Class D definition '
      '(RFC 1112 §4), not the special-purpose registry, so it is sourced '
      'separately.';

  /// Footnote for the IPv6 table — explains the multicast-registry split.
  static const String ipv6Footnote =
      'Source: IANA IPv6 Special-Purpose Address Registry (fetched '
      '2026-06-08). [*] ff00::/8 is defined in RFC 4291 §2.7 and managed via '
      'the IANA IPv6 Multicast Address Space Registry, not the special-purpose '
      'registry, so it is sourced to the defining RFC.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IP Address Reference'),
        toolbarHeight: 64,
        // §8.16 — copy the whole page as sectioned TSV: IPv4 blocks, IPv6
        // blocks, then the IPv6 notation rules. Static data, always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the full page as three TSV sections. The multicast
  /// rows carry a trailing " [*]" marker on their purpose so the split is
  /// visible in pasted text. Always non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('IP Address Reference')
      ..writeln()
      ..writeln('IPv4 special-purpose blocks')
      ..writeln(<String>['CIDR', 'Purpose', 'RFC'].join(tab));
    for (final SpecialUseBlock b in ipv4Blocks) {
      buf.writeln(
        <String>[
          b.cidr,
          b.multicastRegistry ? '${b.purpose} [*]' : b.purpose,
          b.rfc,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln(ipv4Footnote)
      ..writeln()
      ..writeln('IPv6 special-purpose blocks')
      ..writeln(<String>['CIDR', 'Purpose', 'RFC'].join(tab));
    for (final SpecialUseBlock b in ipv6Blocks) {
      buf.writeln(
        <String>[
          b.cidr,
          b.multicastRegistry ? '${b.purpose} [*]' : b.purpose,
          b.rfc,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln(ipv6Footnote)
      ..writeln()
      ..writeln('IPv6 notation rules')
      ..writeln(<String>['Rule', 'Definition', 'Source'].join(tab));
    for (final Ipv6NotationRule r in ipv6Notation) {
      buf.writeln(<String>[r.rule, r.definition, r.source].join(tab));
    }
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
                    toolId: 'ip-address-reference',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('ip-address-reference'))
                    const SizedBox(height: AppSpacing.md),
                  _blocksCard(
                    title: 'IPv4 special-purpose blocks',
                    footnote: ipv4Footnote,
                    blocks: ipv4Blocks,
                    colors: colors,
                    text: text,
                    mono: mono,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _blocksCard(
                    title: 'IPv6 special-purpose blocks',
                    footnote: ipv6Footnote,
                    blocks: ipv6Blocks,
                    colors: colors,
                    text: text,
                    mono: mono,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _notationCard(colors, text, mono),
                  ToolHelpFooter(toolId: 'ip-address-reference'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _blocksCard({
    required String title,
    required String footnote,
    required List<SpecialUseBlock> blocks,
    required AppColorScheme colors,
    required TextTheme text,
    required AppMonoText mono,
  }) {
    return _TableCard(
      title: title,
      footnote: footnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('CIDR', width: 176),
          _HeaderCell('Purpose', width: 320),
          _HeaderCell('RFC', width: 168),
        ],
      ),
      rows: blocks.map((SpecialUseBlock b) {
        // The multicast rows append " [*]" to the purpose to flag the
        // separate-registry sourcing explained in the card footnote.
        final String purposeText =
            b.multicastRegistry ? '${b.purpose} [*]' : b.purpose;
        return ReferenceRowSemantics(
          label: rowLabel(b.cidr, <String?>[
            purposeText,
            b.rfc,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 176,
                  child: Text(
                    b.cidr,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: Text(
                    purposeText,
                    style: text.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 168,
                  child: Text(
                    b.rfc,
                    style: text.labelMedium?.copyWith(
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

  Widget _notationCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'IPv6 notation rules',
      footnote: 'Source: RFC 4291 §2.2-2.3 (IPv6 Addressing Architecture); '
          'RFC 5952 §4 (canonical text representation).',
      header: const Row(
        children: <Widget>[
          _HeaderCell('Rule', width: 200),
          _HeaderCell('Definition', width: 420),
          _HeaderCell('Source', width: 128),
        ],
      ),
      rows: ipv6Notation.map((Ipv6NotationRule r) {
        return ReferenceRowSemantics(
          label: rowLabel(r.rule, <String?>[r.definition, r.source]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 200,
                  child: Text(
                    r.rule,
                    style: text.labelMedium?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 420,
                  child: Text(
                    r.definition,
                    style: text.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 128,
                  child: Text(
                    r.source,
                    style: text.labelMedium?.copyWith(
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
}

/// Card surface wrapping a wide table: title (full-width, wraps) over a
/// horizontally-scrolling IntrinsicWidth grid (header + rows share one width so
/// columns align), with an optional full-width footnote beneath. Matches the
/// poe_reference_screen / power_phasing_screen overflow-safe idiom.
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
