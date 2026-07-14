// DHCP Options — a read-only reference for the DHCPv4 option codes a network /
// Wi-Fi pro meets, led by Option 138 (CAPWAP-AC) — how a lightweight AP learns
// its wireless LAN controller address from DHCP. Two tables: the option-code
// table (Option 138 first, then standard options in code order) and the
// Option-53 DHCP message-type table.
//
// DATA SOURCE: the IANA BOOTP/DHCP Parameters registry
// (iana.org/assignments/bootp-dhcp-parameters) for the option codes; base
// options RFC 2132; relay agent info RFC 3046; domain search RFC 3397;
// CAPWAP-AC option RFC 5417; message types RFC 2132 §9.6. Values reproduced
// verbatim from the verified dataset
// Deliverables/2026-06-08-reference-batch/protocols-data.md, Page 2.
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const datasets always render. No loading/empty/error path.
//
// Pattern: mirrors poe_reference_screen — Scaffold + AppBar (toolbarHeight 64,
// AppCopyAction), SafeArea(top: false), LayoutBuilder isDesktop @720,
// ConstrainedBox to calculatorMaxWidth, SingleChildScrollView,
// ConceptGraphicBand, two wide tables (each a HorizontalScrollTable +
// IntrinsicWidth grid of fixed-width cells), ToolHelpFooter. Each row is wrapped
// in ReferenceRowSemantics.
//
// Glyph note: ASCII only; no em dash. Option codes + RFC numbers render in the
// mono family (identifiers).

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

/// One DHCPv4 option: numeric code, name, plain-English purpose, defining RFC.
@immutable
class DhcpOption {
  const DhcpOption({
    required this.code,
    required this.name,
    required this.purpose,
    required this.rfc,
  });

  /// IANA option code (e.g. 138 for CAPWAP-AC, 53 for DHCP Message Type).
  final int code;

  /// Option name, e.g. `Subnet Mask`.
  final String name;

  /// Plain-English summary of what the option carries.
  final String purpose;

  /// The defining RFC, e.g. `RFC 2132`.
  final String rfc;
}

/// One Option-53 DHCP message type: numeric value, message name, its role in
/// the DORA / lease exchange.
@immutable
class DhcpMessageType {
  const DhcpMessageType({
    required this.value,
    required this.message,
    required this.role,
  });

  /// Option-53 value (1 = DHCPDISCOVER … 8 = DHCPINFORM).
  final int value;

  /// Message name, e.g. `DHCPDISCOVER`.
  final String message;

  /// The message's role in the exchange.
  final String role;
}

class DhcpOptionsScreen extends StatelessWidget {
  const DhcpOptionsScreen({super.key});

  /// DHCPv4 options. Option 138 (CAPWAP-AC) leads — the Wi-Fi controller
  /// discovery hook — then the standard options in code order. Codes verbatim
  /// from the IANA registry; purpose + RFC per the verified dataset.
  static const List<DhcpOption> options = <DhcpOption>[
    DhcpOption(
      code: 138,
      name: 'CAPWAP Access Controller (OPTION_CAPWAP_AC_V4)',
      purpose:
          'Hands a CAPWAP-capable AP (WTP) one or more IPv4 addresses of its '
          'wireless LAN controller(s). This is DHCP-based controller discovery.',
      rfc: 'RFC 5417',
    ),
    DhcpOption(
      code: 1,
      name: 'Subnet Mask',
      purpose: "The subnet mask for the client's interface.",
      rfc: 'RFC 2132',
    ),
    DhcpOption(
      code: 3,
      name: 'Router',
      purpose: 'Default gateway address(es), in preference order.',
      rfc: 'RFC 2132',
    ),
    DhcpOption(
      code: 6,
      name: 'Domain Name Server',
      purpose: 'DNS resolver address(es), in preference order.',
      rfc: 'RFC 2132',
    ),
    DhcpOption(
      code: 12,
      name: 'Host Name',
      purpose: "The client's hostname.",
      rfc: 'RFC 2132',
    ),
    DhcpOption(
      code: 15,
      name: 'Domain Name',
      purpose:
          'The domain name the client should use to resolve hostnames.',
      rfc: 'RFC 2132',
    ),
    DhcpOption(
      code: 28,
      name: 'Broadcast Address',
      purpose: "The broadcast address for the client's subnet.",
      rfc: 'RFC 2132',
    ),
    DhcpOption(
      code: 42,
      name: 'NTP Servers',
      purpose: 'Network Time Protocol server address(es).',
      rfc: 'RFC 2132',
    ),
    DhcpOption(
      code: 43,
      name: 'Vendor-Specific Information',
      purpose:
          'Vendor-defined data; carries sub-options (e.g. some '
          'controller-discovery and AP-provisioning schemes).',
      rfc: 'RFC 2132',
    ),
    DhcpOption(
      code: 50,
      name: 'Requested IP Address',
      purpose:
          'Client asks the server for a specific address (sent in '
          'DISCOVER/REQUEST).',
      rfc: 'RFC 2132',
    ),
    DhcpOption(
      code: 51,
      name: 'IP Address Lease Time',
      purpose: 'Lease duration, in seconds.',
      rfc: 'RFC 2132',
    ),
    DhcpOption(
      code: 53,
      name: 'DHCP Message Type',
      purpose:
          'Identifies the DHCP message (see message-type table below).',
      rfc: 'RFC 2132',
    ),
    DhcpOption(
      code: 54,
      name: 'Server Identifier',
      purpose:
          "The DHCP server's address; selects/targets a server in the "
          'exchange.',
      rfc: 'RFC 2132',
    ),
    DhcpOption(
      code: 55,
      name: 'Parameter Request List',
      purpose:
          "Client's list of option codes it wants the server to return.",
      rfc: 'RFC 2132',
    ),
    DhcpOption(
      code: 60,
      name: 'Vendor Class Identifier',
      purpose:
          'Client advertises its vendor/type so the server can tailor a '
          'reply.',
      rfc: 'RFC 2132',
    ),
    DhcpOption(
      code: 66,
      name: 'TFTP Server Name',
      purpose: 'Name of the TFTP/boot server (overloaded sname field).',
      rfc: 'RFC 2132',
    ),
    DhcpOption(
      code: 67,
      name: 'Bootfile Name',
      purpose: 'Name of the boot file to load (overloaded file field).',
      rfc: 'RFC 2132',
    ),
    DhcpOption(
      code: 82,
      name: 'Relay Agent Information',
      purpose:
          'Relay inserts client circuit/remote-ID context (sub-options) on '
          'the way to the server.',
      rfc: 'RFC 3046',
    ),
    DhcpOption(
      code: 119,
      name: 'Domain Search List',
      purpose:
          'An ordered list of domain suffixes for resolving unqualified '
          'names.',
      rfc: 'RFC 3397',
    ),
  ];

  /// Option-53 DHCP message types — the DORA / lease exchange. Verbatim from
  /// the verified dataset (RFC 2132 §9.6).
  static const List<DhcpMessageType> messageTypes = <DhcpMessageType>[
    DhcpMessageType(
      value: 1,
      message: 'DHCPDISCOVER',
      role: 'Client broadcasts to locate available servers.',
    ),
    DhcpMessageType(
      value: 2,
      message: 'DHCPOFFER',
      role: 'Server offers an address and parameters.',
    ),
    DhcpMessageType(
      value: 3,
      message: 'DHCPREQUEST',
      role: 'Client requests/confirms a specific offer (or renews).',
    ),
    DhcpMessageType(
      value: 4,
      message: 'DHCPDECLINE',
      role: 'Client signals the offered address is already in use.',
    ),
    DhcpMessageType(
      value: 5,
      message: 'DHCPACK',
      role: 'Server confirms the lease and parameters.',
    ),
    DhcpMessageType(
      value: 6,
      message: 'DHCPNAK',
      role: 'Server refuses: lease invalid or expired.',
    ),
    DhcpMessageType(
      value: 7,
      message: 'DHCPRELEASE',
      role: 'Client relinquishes its lease.',
    ),
    DhcpMessageType(
      value: 8,
      message: 'DHCPINFORM',
      role: 'Client already has an address; asks only for config parameters.',
    ),
  ];

  /// Footnote — registry + RFC provenance, with the CAPWAP-AC lead called out.
  static const String footnote =
      'Codes are from the IANA BOOTP/DHCP Parameters registry. Option 138 '
      '(CAPWAP-AC) is the DHCP-based wireless LAN controller discovery hook for '
      'lightweight APs (RFC 5417). Base options RFC 2132; relay agent info RFC '
      '3046; domain search RFC 3397.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DHCP Options'),
        toolbarHeight: 64,
        // §8.16 — copy both tables as a two-section TSV. Static data, always
        // enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — both sub-tables as a two-section TSV. Section 1 is the
  /// option table (Code, Name, Purpose, RFC); section 2 is the Option-53
  /// message-type table (Value, Message, Role). Always non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('DHCP Options')
      ..writeln()
      ..writeln('DHCPv4 options')
      ..writeln(<String>['Code', 'Name', 'Purpose', 'RFC'].join(tab));
    for (final DhcpOption o in options) {
      buf.writeln(
        <String>['${o.code}', o.name, o.purpose, o.rfc].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('Option 53: DHCP message types')
      ..writeln(<String>['Value', 'Message', 'Role'].join(tab));
    for (final DhcpMessageType m in messageTypes) {
      buf.writeln(
        <String>['${m.value}', m.message, m.role].join(tab),
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
                    toolId: 'dhcp-options',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('dhcp-options'))
                    const SizedBox(height: AppSpacing.md),
                  _optionsCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _messageTypesCard(colors, text, mono),
                  ToolHelpFooter(toolId: 'dhcp-options'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _optionsCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'DHCPv4 options',
      footnote: footnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Code', width: 56),
          _HeaderCell('Name', width: 200),
          _HeaderCell('Purpose', width: 320),
          _HeaderCell('RFC', width: 88),
        ],
      ),
      rows: options.map((DhcpOption o) {
        // Option 138 leads and is the Wi-Fi-relevant hook — give its code cell
        // the accent treatment so the controller-discovery option stands out
        // without color being the sole carrier (name + purpose say it too).
        final bool lead = o.code == 138;
        return ReferenceRowSemantics(
          label: rowLabel('Option ${o.code}', <String?>[
            o.name,
            o.purpose,
            o.rfc,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 56,
                  child: Text(
                    '${o.code}',
                    style: mono.inlineCode.copyWith(
                      color: lead ? colors.textAccent : colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: Text(
                    o.name,
                    style: text.labelMedium?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: lead ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: Text(
                    o.purpose,
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 88,
                  child: Text(
                    o.rfc,
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

  Widget _messageTypesCard(
    AppColorScheme colors,
    TextTheme text,
    AppMonoText mono,
  ) {
    return _TableCard(
      title: 'Option 53: DHCP message types',
      header: const Row(
        children: <Widget>[
          _HeaderCell('Value', width: 56),
          _HeaderCell('Message', width: 140),
          _HeaderCell('Role in the exchange', width: 320),
        ],
      ),
      rows: messageTypes.map((DhcpMessageType m) {
        return ReferenceRowSemantics(
          label: rowLabel('Value ${m.value}', <String?>[
            m.message,
            m.role,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 56,
                  child: Text(
                    '${m.value}',
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: Text(
                    m.message,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: Text(
                    m.role,
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
/// poe_reference_screen overflow-safe idiom.
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
