// OSI Model — read-only 7-layer reference table.
//
// The OSI reference model, 7 layers top to bottom: number, name, one-word
// function keyword, PDU, example modern protocols, and typical hardware. Data
// is the Pax research deliverable (pax-research-7-additions.md, "OSI Model"),
// itself sourced from ISO/IEC 7498-1:1994 plus standard IETF/IEEE protocol-to-
// layer mappings. Keith's decision (2026-05-30): neutral function-word keyword
// column (no custom mnemonic); ARP stays at L2 with the L2/L3 footnote.
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const dataset always renders. No loading/empty/error path
// because nothing is fetched or parsed at runtime.
//
// Pattern: matches poe_reference_screen — Scaffold + AppBar (toolbarHeight 64),
// SafeArea(top: false), LayoutBuilder isDesktop @720, ConstrainedBox to
// calculatorMaxWidth, SingleChildScrollView, cards from app_tokens /
// app_typography. The table is wide, so it renders inside a horizontal
// SingleChildScrollView + IntrinsicWidth with fixed-width cells (the
// wifi_channels / poe_reference overflow-safe idiom): columns align and never
// overflow a phone-width card. The layer number is the LIME index column.
//
// Glyph note: "802.3" / "802.11" / "802.1Q" / "802.1X" / "IPv4" / "IPv6";
// ASCII hyphen-minus only; no em dash.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_action.dart';
import '../concept_graphic_band.dart';

/// One OSI layer row. Field names + values mirror the Pax research model
/// `OsiLayer`: [num, name, keyword, pdu, protocols, hardware].
@immutable
class OsiLayer {
  const OsiLayer({
    required this.num,
    required this.name,
    required this.keyword,
    required this.pdu,
    required this.protocols,
    required this.hardware,
  });

  /// Layer number, 7 (top) down to 1 (bottom). The primary index — LIME column.
  final int num;

  /// Layer name, e.g. `Application`.
  final String name;

  /// One-word function of the layer, e.g. `Routing` (neutral keyword per
  /// Keith's decision #1 — not a custom mnemonic).
  final String keyword;

  /// Protocol data unit at this layer, e.g. `Packet`.
  final String pdu;

  /// Example modern protocols operating at this layer.
  final String protocols;

  /// Typical hardware operating at this layer.
  final String hardware;
}

class OsiModelScreen extends StatelessWidget {
  const OsiModelScreen({super.key});

  /// The 7 OSI layers, top (7) to bottom (1). Verbatim from the Pax research
  /// deliverable. Public + static so tests can assert known rows without
  /// pumping the UI.
  static const List<OsiLayer> layers = <OsiLayer>[
    OsiLayer(
      num: 7,
      name: 'Application',
      keyword: 'Data',
      pdu: 'Data',
      protocols: 'HTTP, HTTPS, DNS, DHCP, SMTP, SSH',
      hardware: 'Host, firewall (L7)',
    ),
    OsiLayer(
      num: 6,
      name: 'Presentation',
      keyword: 'Translation',
      pdu: 'Data',
      protocols: 'TLS, ASCII, JPEG, JSON, MIME',
      hardware: 'Host',
    ),
    OsiLayer(
      num: 5,
      name: 'Session',
      keyword: 'Sessions',
      pdu: 'Data',
      protocols: 'TLS session, RPC, NetBIOS, SIP',
      hardware: 'Host',
    ),
    OsiLayer(
      num: 4,
      name: 'Transport',
      keyword: 'Segments',
      pdu: 'Segment',
      protocols: 'TCP, UDP, QUIC',
      hardware: 'Host, load balancer (L4)',
    ),
    OsiLayer(
      num: 3,
      name: 'Network',
      keyword: 'Routing',
      pdu: 'Packet',
      protocols: 'IPv4, IPv6, ICMP, IPsec',
      hardware: 'Router, L3 switch',
    ),
    OsiLayer(
      num: 2,
      name: 'Data Link',
      keyword: 'Framing',
      pdu: 'Frame',
      protocols: 'Ethernet (802.3), Wi-Fi (802.11), 802.1Q, ARP',
      hardware: 'Switch, AP, bridge, NIC',
    ),
    OsiLayer(
      num: 1,
      name: 'Physical',
      keyword: 'Bits',
      pdu: 'Bit',
      protocols: 'Ethernet PHY, RF (radio), fiber, copper',
      hardware: 'Cable, fiber, radio, hub, repeater',
    ),
  ];

  static const String intro =
      'The OSI reference model, 7 layers top to bottom. Use it to localize a '
      'fault: which layer is failing tells you which tool to reach for.';

  static const String footnote =
      'PDU = protocol data unit, the name for the data structure at each layer. '
      'Layers 5-7 are commonly grouped as "data" in TCP/IP practice. ARP is '
      'widely placed at Layer 2 (some texts call it L2/L3); it resolves L3 '
      'addresses to L2 addresses.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OSI Model'),
        toolbarHeight: 64,
        // §8.16 — copy the 7 layers as TSV. Static data, always enabled.
        // §8.16 order: copy LEADS, help TRAILS.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
          ToolHelpAction(toolId: 'osi-model'),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the 7 OSI layers as TSV (number, name, function PDU,
  /// protocols, hardware), top (7) to bottom (1). One header row; one
  /// tab-separated row per layer. Always non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('OSI Model — the 7 layers')
      ..writeln(
        <String>[
          '#',
          'Layer',
          'Function',
          'PDU',
          'Protocols',
          'Hardware',
        ].join(tab),
      );
    for (final OsiLayer l in layers) {
      buf.writeln(
        <String>[
          '${l.num}',
          l.name,
          l.keyword,
          l.pdu,
          l.protocols,
          l.hardware,
        ].join(tab),
      );
    }
    return buf.toString().trimRight();
  }

  Widget _body(BuildContext context) {
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
                children: [
                  ConceptGraphicBand(toolId: 'osi-model', isDesktop: isDesktop),
                  if (ToolAssets.hasGraphic('osi-model'))
                    const SizedBox(height: AppSpacing.md),
                  _introCard(text),
                  const SizedBox(height: AppSpacing.md),
                  _tableCard(text, mono),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _introCard(TextTheme text) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Text(
        intro,
        style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
      ),
    );
  }

  Widget _tableCard(TextTheme text, AppMonoText mono) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The 7 layers',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          HorizontalScrollTable(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      _HeaderCell('#', width: 28),
                      _HeaderCell('Layer', width: 104),
                      _HeaderCell('Function', width: 96),
                      _HeaderCell('PDU', width: 88),
                      _HeaderCell('Protocols', width: 248),
                      _HeaderCell('Hardware', width: 184),
                    ],
                  ),
                  const Divider(color: AppColors.border, height: AppSpacing.sm),
                  ...layers.map(
                    (OsiLayer l) => _LayerRow(layer: l, mono: mono),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            footnote,
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// One layer row — number (lime index), name, keyword, PDU, protocols, hardware.
/// Merges to one semantic node so AT reads the layer as a single line.
class _LayerRow extends StatelessWidget {
  const _LayerRow({required this.layer, required this.mono});

  final OsiLayer layer;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label:
          'Layer ${layer.num}, ${layer.name}. ${layer.keyword}. '
          'PDU ${layer.pdu}. Protocols ${layer.protocols}. '
          'Hardware ${layer.hardware}.',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${layer.num}',
                style: mono.inlineCode.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SizedBox(
              width: 104,
              child: Text(
                layer.name,
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: 96,
              child: Text(
                layer.keyword,
                style: text.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            SizedBox(
              width: 88,
              child: Text(
                layer.pdu,
                style: mono.inlineCode.copyWith(color: AppColors.textSecondary),
              ),
            ),
            SizedBox(
              width: 248,
              child: Text(
                layer.protocols,
                style: text.labelMedium?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
            SizedBox(
              width: 184,
              child: Text(
                layer.hardware,
                style: text.labelMedium?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
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
    final TextTheme text = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          color: AppColors.textTertiary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
