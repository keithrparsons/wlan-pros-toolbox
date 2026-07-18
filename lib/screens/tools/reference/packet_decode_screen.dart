// Packet Decode / Protocol Reference — a byte-level Layer 3-4 companion to the
// 802.11 references. Read-only: header anatomy (field / bits / meaning) for
// IPv4, IPv6, TCP, UDP, and ICMP; the TCP control bits; TCP connection states
// with the three-way handshake and teardown; and the ICMP / ICMPv6 type and
// code tables. A small IP-protocol-numbers table sits between the IP headers,
// because the IPv4 "Protocol" and IPv6 "Next Header" fields point straight at
// that IANA registry.
//
// DATA SOURCE (accuracy-critical): every field offset, bit length, flag, state,
// type, and code is transcribed VERBATIM from Pax's source-pinned brief at
// Deliverables/2026-07-18-packet-decode-reference/decode-data.md, which fetched
// each value from the primary source (rfc-editor.org / iana.org) on 2026-07-18.
// Each table renders its RFC / registry citation, matching this app's pinned-
// citation style (see reason_codes_screen / dscp_qos_screen). No field width is
// invented or approximated.
//
// Four points Pax pinned and Larry reconfirmed, encoded here on purpose:
//  1. TCP control bits use RFC 9293's canonical layout: a 4-bit reserved field
//     plus 8 control bits (CWR, ECE, URG, ACK, PSH, RST, SYN, FIN). The bit that
//     Wireshark still labels "NS" (bit 103) is Reserved in RFC 9293: it was NS
//     (Nonce Sum, RFC 3540, made Historic by RFC 8311) and is reassigned as AE
//     (Accurate ECN) by RFC 9768. It is shown, flagged historic in TEXT (never
//     by color alone), not presented as a current flag.
//  2. ICMP type 4 (Source Quench) is kept but marked DEPRECATED (RFC 6633).
//  3. The IPv4 ToS octet is shown as DSCP (6 bits) + ECN (2 bits) per RFC 2474 /
//     RFC 3168; the legacy RFC 791 precedence reading is footnoted, not led with.
//  4. A common IP-protocol-numbers table is included; ports are NOT duplicated
//     here (the app already ships a Well-Known Ports reference).
//
// States (SOP-007 §5): a static, fully-offline reference with no I/O. The only
// state is "success": the compile-time const datasets always render. There is no
// loading / empty / error path and no NetworkUnavailableView (nothing is fetched
// and nothing is executed, so GL-008 does not apply). Interactive state is the
// copy action (always enabled, static data) and the help footer.
//
// Pattern: mirrors dscp_qos_screen — Scaffold + AppBar (toolbarHeight 64,
// AppCopyAction), SafeArea(top: false), LayoutBuilder isDesktop @720,
// ConstrainedBox to calculatorMaxWidth, SingleChildScrollView, ConceptGraphicBand,
// a stack of wide _TableCard grids (HorizontalScrollTable + IntrinsicWidth so
// columns align and overflow scrolls at 320px), prose note callouts, and the
// ToolHelpFooter. All values come from GL-003 tokens; no literal hex / px color.
//
// Glyph note: ASCII hyphen-minus and "->" only; no em dash (GL-004 P0). "Wi-Fi"
// casing is irrelevant here (Layer 3-4), but the no-em-dash rule holds.

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

/// One header-anatomy row: a field, its bit offset, its bit length, and what it
/// means. Offset and length are Strings so "variable" survives verbatim.
@immutable
class PacketField {
  const PacketField(this.field, this.offset, this.length, this.meaning);

  /// Field name, e.g. `Version`.
  final String field;

  /// Bit offset from bit 0 of the header (0 = first / most-significant bit), or
  /// `variable`.
  final String offset;

  /// Bit length, or `variable`.
  final String length;

  /// Plain-language meaning.
  final String meaning;
}

/// One sub-field row addressed by bit position (the IPv4 Flags and the
/// ToS / DiffServ octet split): the bit or bit-range, a name, and a meaning.
@immutable
class BitFieldRow {
  const BitFieldRow(this.bits, this.name, this.meaning);

  /// The bit or bit range, e.g. `49` or `8-13`.
  final String bits;

  /// The name, e.g. `DF (Don't Fragment)` or `DSCP`.
  final String name;

  /// The meaning.
  final String meaning;
}

/// One TCP control-bit row: the flag, its bit position, a one-line meaning, and
/// whether it is a historic / reserved bit (not a current control bit).
@immutable
class TcpFlagRow {
  const TcpFlagRow(this.flag, this.bit, this.meaning, {this.historic = false});

  /// The flag mnemonic, e.g. `SYN`.
  final String flag;

  /// The bit position within the header.
  final int bit;

  /// One-line meaning.
  final String meaning;

  /// True for the reserved bit 103 (historic NS, now AE): shown for decoder
  /// completeness, not a current RFC 9293 control bit. The historic status is
  /// carried in [meaning] text too, so color is never the sole signal.
  final bool historic;
}

/// One IANA IP-protocol-number row: the number, its mnemonic, and a meaning.
@immutable
class ProtocolNumber {
  const ProtocolNumber(this.number, this.name, this.meaning);

  /// The protocol number as it appears in the IPv4 Protocol / IPv6 Next Header
  /// field.
  final int number;

  /// The protocol mnemonic, e.g. `TCP`.
  final String name;

  /// The meaning.
  final String meaning;
}

/// One TCP connection state: the state name and a one-line meaning.
@immutable
class TcpState {
  const TcpState(this.state, this.meaning);

  final String state;
  final String meaning;
}

/// One numbered step in the handshake or teardown sequence.
@immutable
class HandshakeStep {
  const HandshakeStep(this.n, this.detail);

  final int n;
  final String detail;
}

/// One ICMP / ICMPv6 type row: the numeric type, its name, the code column
/// (either a code list or a pointer to the code table), and whether the type is
/// deprecated.
@immutable
class IcmpTypeRow {
  const IcmpTypeRow(this.type, this.name, this.codes, {this.deprecated = false});

  final int type;
  final String name;

  /// Codes / purpose text for this type.
  final String codes;

  /// True for ICMP type 4 (Source Quench), deprecated by RFC 6633.
  final bool deprecated;
}

/// One ICMP code row (the Type 3 Destination-Unreachable code table): the
/// numeric code and its meaning.
@immutable
class IcmpCodeRow {
  const IcmpCodeRow(this.code, this.meaning);

  final int code;
  final String meaning;
}

/// Cell rendering intent, so the generic row builder styles each column right.
enum _CellKind { key, mono, prose }

/// One table cell: its text, its column width, and how it should render.
@immutable
class _Cell {
  const _Cell(this.text, this.width, this.kind);
  final String text;
  final double width;
  final _CellKind kind;
}

/// Packet Decode / Protocol Reference screen. Route '/tools/packet-decode'
/// (registered in app_router.dart / tool_catalog.dart).
class PacketDecodeScreen extends StatelessWidget {
  const PacketDecodeScreen({super.key});

  // ── Citations (rendered on-screen AND pinnable in test, so the source line
  //    cannot drift away from the values it justifies) ──

  static const String ipv4Citation =
      'RFC 791 §3.1; ToS octet redefined by RFC 2474 §3 (DSCP) + RFC 3168 §5 '
      '(ECN).';
  static const String ipv6Citation = 'RFC 8200 §3.';
  static const String protoNumbersCitation =
      'IANA Protocol Numbers registry. The IPv4 Protocol and IPv6 Next Header '
      'fields carry these values. For TCP/UDP port numbers see the Well-Known '
      'Ports reference.';
  static const String tcpCitation =
      'RFC 9293 §3.1 (header + control bits); ECN flags RFC 3168; NS -> AE bit '
      'history RFC 3540 (Historic) -> RFC 8311 -> RFC 9768.';
  static const String udpCitation = 'RFC 768.';
  static const String tcpStateCitation =
      'RFC 9293 §3.3.2 (states) and §3.5 (handshake and close).';
  static const String icmpCitation =
      'RFC 792; type / code assignments per the IANA ICMP Parameters registry '
      '(Type 3 codes 6-15 per RFC 1122 / RFC 1812).';
  static const String icmpv6Citation =
      'RFC 4443 (core messages); NDP types 133-137 per RFC 4861; assignments '
      'per the IANA ICMPv6 Parameters registry.';

  static const String intro =
      'Byte-level anatomy of the Layer 3-4 headers a capture shows below 802.11: '
      'IPv4, IPv6, TCP, UDP, and ICMP. Every field offset, width, flag, and code '
      'is transcribed from the RFCs and the IANA registries, cited per table. Bit '
      'offsets count from bit 0 of each header (bit 0 = first / most-significant '
      'bit); bit lengths are exact.';

  // ── IPv4 ──

  static const List<PacketField> ipv4Header = <PacketField>[
    PacketField('Version', '0', '4', 'IP version; always 4 here'),
    PacketField('IHL', '4', '4',
        'Header length in 32-bit words; minimum 5 (= 20 bytes)'),
    PacketField('Type of Service / DiffServ', '8', '8',
        'QoS octet: DSCP (6 bits) + ECN (2 bits), per RFC 2474 / RFC 3168. See '
        'the split below'),
    PacketField('Total Length', '16', '16',
        'Whole datagram length in octets (header + data)'),
    PacketField('Identification', '32', '16',
        'Sender ID used to group fragments of one datagram'),
    PacketField('Flags', '48', '3', 'Fragmentation control bits (see below)'),
    PacketField('Fragment Offset', '51', '13',
        "This fragment's position in the original, in 8-octet units"),
    PacketField('Time to Live', '64', '8',
        'Max remaining hops; decremented per router, discard at 0'),
    PacketField('Protocol', '72', '8',
        'Encapsulated next-layer protocol (IP protocol numbers below; e.g. '
        '6 = TCP, 17 = UDP, 1 = ICMP)'),
    PacketField('Header Checksum', '80', '16',
        'Ones-complement checksum over the header only'),
    PacketField('Source Address', '96', '32', 'Sender IPv4 address'),
    PacketField('Destination Address', '128', '32', 'Recipient IPv4 address'),
    PacketField('Options', '160', 'variable',
        'Optional controls; present only when IHL > 5'),
    PacketField('Padding', 'variable', 'variable',
        'Zero-fill so the header ends on a 32-bit boundary'),
  ];

  static const List<BitFieldRow> ipv4Flags = <BitFieldRow>[
    BitFieldRow('48', 'Reserved', 'Must be 0'),
    BitFieldRow("49", "DF (Don't Fragment)",
        '1 = router must not fragment; drop instead'),
    BitFieldRow('50', 'MF (More Fragments)',
        '1 = more fragments follow; 0 = last fragment'),
  ];

  static const List<BitFieldRow> ipv4ToS = <BitFieldRow>[
    BitFieldRow('8-13', 'DSCP',
        'Differentiated Services Codepoint (per-hop QoS class), 6 bits'),
    BitFieldRow('14-15', 'ECN',
        'Explicit Congestion Notification, 2 bits: 00 = Not-ECT, 01 = ECT(1), '
        '10 = ECT(0), 11 = CE (Congestion Experienced)'),
  ];

  static const String ipv4ToSNote =
      'Legacy note: RFC 791 originally read these same 8 bits as a 3-bit '
      'Precedence plus Delay / Throughput / Reliability bits. DiffServ '
      '(RFC 2474 / RFC 3168) supersedes that reading; a modern decoder shows '
      'DSCP + ECN.';

  // ── IPv6 ──

  static const List<PacketField> ipv6Header = <PacketField>[
    PacketField('Version', '0', '4', 'IP version; always 6'),
    PacketField('Traffic Class', '4', '8',
        'QoS octet: DSCP (6 bits) + ECN (2 bits), as in IPv4 DiffServ'),
    PacketField('Flow Label', '12', '20',
        'Labels a packet flow for special handling by routers'),
    PacketField('Payload Length', '32', '16',
        'Length in octets of everything after this 40-byte header (extension '
        'headers + upper-layer data)'),
    PacketField('Next Header', '48', '8',
        'Type of the header immediately following (IP protocol numbers, or an '
        'extension-header type)'),
    PacketField('Hop Limit', '56', '8',
        'Max remaining hops; decremented per node, discard at 0 (IPv6 '
        'equivalent of TTL)'),
    PacketField('Source Address', '64', '128', 'Sender IPv6 address'),
    PacketField('Destination Address', '192', '128', 'Recipient IPv6 address'),
  ];

  static const String ipv6Note =
      'The fixed header is exactly 320 bits (40 octets). There is no header '
      'checksum and no in-header fragmentation: fragmentation is an extension '
      'header.';

  // ── Common IP protocol numbers (IANA) ──

  static const List<ProtocolNumber> protocolNumbers = <ProtocolNumber>[
    ProtocolNumber(1, 'ICMP', 'Internet Control Message Protocol (IPv4)'),
    ProtocolNumber(6, 'TCP', 'Transmission Control Protocol'),
    ProtocolNumber(17, 'UDP', 'User Datagram Protocol'),
    ProtocolNumber(47, 'GRE', 'Generic Routing Encapsulation'),
    ProtocolNumber(50, 'ESP', 'Encapsulating Security Payload (IPsec)'),
    ProtocolNumber(51, 'AH', 'Authentication Header (IPsec)'),
    ProtocolNumber(58, 'ICMPv6', 'ICMP for IPv6'),
    ProtocolNumber(88, 'EIGRP', 'Enhanced Interior Gateway Routing Protocol'),
    ProtocolNumber(89, 'OSPF', 'Open Shortest Path First (OSPFIGP)'),
    ProtocolNumber(132, 'SCTP', 'Stream Control Transmission Protocol'),
  ];

  // ── TCP ──

  static const List<PacketField> tcpHeader = <PacketField>[
    PacketField('Source Port', '0', '16', 'Sending port'),
    PacketField('Destination Port', '16', '16', 'Receiving port'),
    PacketField('Sequence Number', '32', '32',
        'Sequence number of first data octet in this segment; if SYN set, this '
        'is the ISN'),
    PacketField('Acknowledgment Number', '64', '32',
        'Next sequence number the sender expects (valid only when ACK set)'),
    PacketField('Data Offset', '96', '4',
        'TCP header length in 32-bit words; minimum 5 (= 20 bytes). Locates '
        'where data begins'),
    PacketField('Reserved', '100', '4',
        'Must be 0 in sent segments, ignored on receipt (see the flag history '
        'below)'),
    PacketField('Control Bits', '104', '8', 'The 8 flags (see TCP flags below)'),
    PacketField('Window', '112', '16',
        'Receive-window size the sender is currently offering, in octets'),
    PacketField('Checksum', '128', '16',
        'Ones-complement checksum over pseudo-header + TCP header + data'),
    PacketField('Urgent Pointer', '144', '16',
        'Offset to the last urgent-data octet (valid only when URG set)'),
    PacketField('Options', '160', 'variable',
        'Present when Data Offset > 5 (e.g. MSS, window scale, SACK, '
        'timestamps)'),
    PacketField('Data', 'variable', 'variable', 'Upper-layer payload'),
  ];

  /// TCP control bits, MSB -> LSB. The historic bit 103 leads, flagged in text;
  /// then the 8 canonical RFC 9293 control bits (CWR through FIN).
  static const List<TcpFlagRow> tcpFlags = <TcpFlagRow>[
    TcpFlagRow('Reserved (was NS)', 103,
        'Reserved in RFC 9293. Historically NS (Nonce Sum, RFC 3540, made '
        'Historic by RFC 8311); reassigned as AE (Accurate ECN) by RFC 9768. '
        'Wireshark may still label this bit NS',
        historic: true),
    TcpFlagRow('CWR', 104,
        'Congestion Window Reduced: sender shrank its window after ECN feedback'),
    TcpFlagRow('ECE', 105,
        'ECN-Echo: receiver reflects that a Congestion-Experienced mark arrived'),
    TcpFlagRow('URG', 106,
        'Urgent Pointer field is meaningful: expedited data present'),
    TcpFlagRow('ACK', 107, 'Acknowledgment Number field is meaningful'),
    TcpFlagRow('PSH', 108,
        "Deliver buffered data to the application immediately, don't wait to "
        'fill a segment'),
    TcpFlagRow('RST', 109, 'Abort the connection immediately (reset)'),
    TcpFlagRow('SYN', 110, 'Synchronize sequence numbers: opens a connection'),
    TcpFlagRow('FIN', 111,
        'Sender has finished sending: begins a graceful close'),
  ];

  static const String tcpFlagsNote =
      "RFC 9293's canonical layout is a 4-bit reserved field plus 8 control bits "
      '(CWR through FIN). Bit 103 is shown for decoder completeness only; it is '
      'not a current control bit.';

  // ── UDP ──

  static const List<PacketField> udpHeader = <PacketField>[
    PacketField('Source Port', '0', '16',
        'Sending port; optional (may be 0 if no reply expected)'),
    PacketField('Destination Port', '16', '16', 'Receiving port'),
    PacketField('Length', '32', '16',
        'Length in octets of this header + data (minimum 8)'),
    PacketField('Checksum', '48', '16',
        'Ones-complement checksum over pseudo-header + header + data; '
        '0 = not computed (IPv4 only)'),
  ];

  static const String udpNote =
      'Fixed 8-octet header. No sequence numbers, no connection state: UDP is '
      'connectionless.';

  // ── TCP connection states + handshake / teardown ──

  static const List<TcpState> tcpStates = <TcpState>[
    TcpState('CLOSED', 'No connection exists (the notional start / end state)'),
    TcpState('LISTEN', 'Server waiting for an inbound connection request'),
    TcpState('SYN-SENT', "Client has sent SYN, waiting for the peer's SYN-ACK"),
    TcpState('SYN-RECEIVED',
        'SYN received and SYN-ACK sent; waiting for the final ACK'),
    TcpState('ESTABLISHED',
        'Connection open; normal bidirectional data transfer'),
    TcpState('FIN-WAIT-1',
        "Local side sent FIN; waiting for its ACK or the peer's FIN"),
    TcpState('FIN-WAIT-2', "Local FIN acked; waiting for the peer's FIN"),
    TcpState('CLOSE-WAIT',
        'Peer sent FIN; waiting for the local application to close'),
    TcpState('CLOSING',
        'Both sides sent FIN simultaneously; waiting for the ACK of ours'),
    TcpState('LAST-ACK',
        'Local side sent its FIN after CLOSE-WAIT; waiting for the final ACK'),
    TcpState('TIME-WAIT',
        'Local close complete; waiting twice the MSL to absorb stray / '
        'duplicate segments before CLOSED'),
  ];

  static const List<HandshakeStep> handshake = <HandshakeStep>[
    HandshakeStep(1, 'Client -> Server: SYN (client ISN). Client: SYN-SENT.'),
    HandshakeStep(2,
        'Server -> Client: SYN, ACK (server ISN, acks client ISN). '
        'Server: SYN-RECEIVED.'),
    HandshakeStep(3,
        'Client -> Server: ACK (acks server ISN). Both: ESTABLISHED.'),
  ];

  static const List<HandshakeStep> teardown = <HandshakeStep>[
    HandshakeStep(1, 'Initiator -> Peer: FIN. Initiator: FIN-WAIT-1.'),
    HandshakeStep(2,
        'Peer -> Initiator: ACK of the FIN. Initiator: FIN-WAIT-2; '
        'Peer: CLOSE-WAIT.'),
    HandshakeStep(3,
        'Peer -> Initiator: FIN (once its app closes). Peer: LAST-ACK.'),
    HandshakeStep(4,
        'Initiator -> Peer: ACK of that FIN. Initiator: TIME-WAIT (waits twice '
        'the MSL) -> CLOSED; Peer: CLOSED on receipt.'),
  ];

  static const String teardownNote =
      'Simultaneous close: both sides send FIN and pass through CLOSING -> '
      'TIME-WAIT.';

  // ── ICMP (IPv4) ──

  static const List<PacketField> icmpHeader = <PacketField>[
    PacketField('Type', '0', '8', 'Message type'),
    PacketField('Code', '8', '8', 'Subtype within a type'),
    PacketField('Checksum', '16', '16',
        'Ones-complement checksum over the ICMP message'),
    PacketField('Rest of Header', '32', '32',
        'Type-specific (Identifier + Sequence for echo; gateway address for '
        'redirect; pointer for parameter problem)'),
  ];

  static const List<IcmpTypeRow> icmpTypes = <IcmpTypeRow>[
    IcmpTypeRow(0, 'Echo Reply', '0'),
    IcmpTypeRow(3, 'Destination Unreachable', 'see the code table below'),
    IcmpTypeRow(4, 'Source Quench', '0', deprecated: true),
    IcmpTypeRow(5, 'Redirect',
        '0 = network, 1 = host, 2 = ToS + network, 3 = ToS + host'),
    IcmpTypeRow(8, 'Echo Request', '0'),
    IcmpTypeRow(11, 'Time Exceeded',
        '0 = TTL exceeded in transit, 1 = fragment-reassembly time exceeded'),
    IcmpTypeRow(12, 'Parameter Problem',
        '0 = pointer indicates error, 1 = missing required option, '
        '2 = bad length'),
    IcmpTypeRow(13, 'Timestamp', '0'),
    IcmpTypeRow(14, 'Timestamp Reply', '0'),
  ];

  static const List<IcmpCodeRow> icmpType3Codes = <IcmpCodeRow>[
    IcmpCodeRow(0, 'Net unreachable'),
    IcmpCodeRow(1, 'Host unreachable'),
    IcmpCodeRow(2, 'Protocol unreachable'),
    IcmpCodeRow(3, 'Port unreachable'),
    IcmpCodeRow(4, 'Fragmentation needed and DF set (path MTU)'),
    IcmpCodeRow(5, 'Source route failed'),
    IcmpCodeRow(6, 'Destination network unknown'),
    IcmpCodeRow(7, 'Destination host unknown'),
    IcmpCodeRow(8, 'Source host isolated'),
    IcmpCodeRow(9, 'Network administratively prohibited'),
    IcmpCodeRow(10, 'Host administratively prohibited'),
    IcmpCodeRow(11, 'Network unreachable for ToS'),
    IcmpCodeRow(12, 'Host unreachable for ToS'),
    IcmpCodeRow(13, 'Communication administratively prohibited'),
    IcmpCodeRow(14, 'Host precedence violation'),
    IcmpCodeRow(15, 'Precedence cutoff in effect'),
  ];

  // ── ICMPv6 ──

  static const List<PacketField> icmpv6Header = <PacketField>[
    PacketField('Type', '0', '8',
        'Message type; high bit 0 = error (0-127), high bit 1 = informational '
        '(128-255)'),
    PacketField('Code', '8', '8', 'Subtype within a type'),
    PacketField('Checksum', '16', '16',
        'Checksum over the ICMPv6 message + the IPv6 pseudo-header (mandatory, '
        'unlike UDP over IPv4)'),
    PacketField('Message Body', '32', 'variable', 'Type-specific'),
  ];

  static const List<IcmpTypeRow> icmpv6Types = <IcmpTypeRow>[
    IcmpTypeRow(1, 'Destination Unreachable',
        '0 = no route, 1 = admin prohibited, 2 = beyond scope of source '
        'address, 3 = address unreachable, 4 = port unreachable, 5 = source '
        'address failed ingress / egress policy, 6 = reject route to '
        'destination'),
    IcmpTypeRow(2, 'Packet Too Big',
        '0 (carries the MTU; the IPv6 path-MTU mechanism, no in-transit '
        'fragmentation)'),
    IcmpTypeRow(3, 'Time Exceeded',
        '0 = hop limit exceeded in transit, 1 = fragment-reassembly time '
        'exceeded'),
    IcmpTypeRow(4, 'Parameter Problem',
        '0 = erroneous header field, 1 = unrecognized Next Header type, '
        '2 = unrecognized IPv6 option'),
    IcmpTypeRow(128, 'Echo Request', '0'),
    IcmpTypeRow(129, 'Echo Reply', '0'),
  ];

  /// NDP messages (RFC 4861), all Code 0. Reuses [IcmpTypeRow] with the purpose
  /// carried in the codes column.
  static const List<IcmpTypeRow> icmpv6Ndp = <IcmpTypeRow>[
    IcmpTypeRow(133, 'Router Solicitation',
        'Host asks routers to send a Router Advertisement now'),
    IcmpTypeRow(134, 'Router Advertisement',
        'Router announces its presence, prefixes, and link parameters'),
    IcmpTypeRow(135, 'Neighbor Solicitation',
        "Resolve a neighbor's link-layer address / confirm reachability "
        "(IPv6's ARP)"),
    IcmpTypeRow(136, 'Neighbor Advertisement',
        'Reply to a solicitation, or unsolicited link-layer-address update'),
    IcmpTypeRow(137, 'Redirect',
        'Router tells a host of a better first hop for a destination'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Packet Decode'),
        toolbarHeight: 64,
        // §8.16 — copy every table as a multi-section TSV. Static data, always
        // enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
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
                    toolId: 'packet-decode',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('packet-decode'))
                    const SizedBox(height: AppSpacing.md),
                  _introCard(context),
                  const SizedBox(height: AppSpacing.md),

                  // Header anatomy.
                  _fieldTable(context, 'IPv4 header', ipv4Header, ipv4Citation),
                  const SizedBox(height: AppSpacing.sm),
                  _bitTable(context, 'IPv4 Flags (bits 48-50)', ipv4Flags, null),
                  const SizedBox(height: AppSpacing.sm),
                  _bitTable(
                    context,
                    'IPv4 ToS octet: DSCP + ECN (bits 8-15)',
                    ipv4ToS,
                    ipv4ToSNote,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  _fieldTable(context, 'IPv6 header', ipv6Header, ipv6Citation,
                      note: ipv6Note),
                  const SizedBox(height: AppSpacing.md),

                  _protocolNumberTable(context),
                  const SizedBox(height: AppSpacing.md),

                  _fieldTable(context, 'TCP header', tcpHeader, tcpCitation),
                  const SizedBox(height: AppSpacing.sm),
                  _tcpFlagsTable(context),
                  const SizedBox(height: AppSpacing.md),

                  _fieldTable(context, 'UDP header', udpHeader, udpCitation,
                      note: udpNote),
                  const SizedBox(height: AppSpacing.md),

                  // TCP connection states + sequences.
                  _tcpStateTable(context),
                  const SizedBox(height: AppSpacing.sm),
                  _StepCard(
                    title: 'Three-way handshake (connection setup)',
                    steps: handshake,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _StepCard(
                    title: 'Connection teardown (graceful, four-way)',
                    steps: teardown,
                    note: teardownNote,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // ICMP.
                  _fieldTable(
                    context,
                    'ICMP common header (IPv4)',
                    icmpHeader,
                    icmpCitation,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _icmpTypeTable(context, 'ICMP types', icmpTypes, null),
                  const SizedBox(height: AppSpacing.sm),
                  _icmpCodeTable(context),
                  const SizedBox(height: AppSpacing.md),

                  // ICMPv6.
                  _fieldTable(
                    context,
                    'ICMPv6 common header',
                    icmpv6Header,
                    icmpv6Citation,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _icmpTypeTable(
                    context,
                    'ICMPv6 types',
                    icmpv6Types,
                    null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _icmpTypeTable(
                    context,
                    'ICMPv6 Neighbor Discovery (NDP, all Code 0)',
                    icmpv6Ndp,
                    'Purpose',
                  ),

                  ToolHelpFooter(toolId: 'packet-decode'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _introCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Text(
        intro,
        style: text.labelMedium?.copyWith(color: colors.textSecondary),
      ),
    );
  }

  // ── Table builders (all share the _TableCard + _dataRow idiom) ──

  Widget _fieldTable(
    BuildContext context,
    String title,
    List<PacketField> fields,
    String citation, {
    String? note,
  }) {
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return _TableCard(
      title: title,
      footnote: note == null ? citation : '$note\n\n$citation',
      header: const Row(
        children: <Widget>[
          _HeaderCell('Field', width: 168),
          _HeaderCell('Offset', width: 72),
          _HeaderCell('Len', width: 64),
          _HeaderCell('Meaning', width: 360),
        ],
      ),
      rows: fields
          .map((PacketField f) => _dataRow(context, mono, <_Cell>[
                _Cell(f.field, 168, _CellKind.key),
                _Cell(f.offset, 72, _CellKind.mono),
                _Cell(f.length, 64, _CellKind.mono),
                _Cell(f.meaning, 360, _CellKind.prose),
              ]))
          .toList(),
    );
  }

  Widget _bitTable(
    BuildContext context,
    String title,
    List<BitFieldRow> bits,
    String? note,
  ) {
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return _TableCard(
      title: title,
      footnote: note,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Bits', width: 72),
          _HeaderCell('Name', width: 168),
          _HeaderCell('Meaning', width: 360),
        ],
      ),
      rows: bits
          .map((BitFieldRow b) => _dataRow(context, mono, <_Cell>[
                _Cell(b.bits, 72, _CellKind.mono),
                _Cell(b.name, 168, _CellKind.key),
                _Cell(b.meaning, 360, _CellKind.prose),
              ]))
          .toList(),
    );
  }

  Widget _protocolNumberTable(BuildContext context) {
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return _TableCard(
      title: 'Common IP protocol numbers',
      footnote: protoNumbersCitation,
      header: const Row(
        children: <Widget>[
          _HeaderCell('No.', width: 56),
          _HeaderCell('Name', width: 96),
          _HeaderCell('Meaning', width: 300),
        ],
      ),
      rows: protocolNumbers
          .map((ProtocolNumber p) => _dataRow(context, mono, <_Cell>[
                _Cell('${p.number}', 56, _CellKind.key),
                _Cell(p.name, 96, _CellKind.mono),
                _Cell(p.meaning, 300, _CellKind.prose),
              ]))
          .toList(),
    );
  }

  Widget _tcpFlagsTable(BuildContext context) {
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return _TableCard(
      title: 'TCP flags (control bits 104-111)',
      footnote: tcpFlagsNote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Flag', width: 140),
          _HeaderCell('Bit', width: 48),
          _HeaderCell('Meaning', width: 372),
        ],
      ),
      rows: tcpFlags.map((TcpFlagRow f) {
        // The historic bit's status is spoken via its meaning text and shown in
        // textTertiary; color is never the sole signal (SC 1.4.1).
        final String flagLabel =
            f.historic ? '${f.flag} (historic)' : f.flag;
        return _dataRow(
          context,
          mono,
          <_Cell>[
            _Cell(flagLabel, 140, f.historic ? _CellKind.mono : _CellKind.key),
            _Cell('${f.bit}', 48, _CellKind.mono),
            _Cell(f.meaning, 372, _CellKind.prose),
          ],
        );
      }).toList(),
    );
  }

  Widget _tcpStateTable(BuildContext context) {
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return _TableCard(
      title: 'TCP connection states',
      footnote: tcpStateCitation,
      header: const Row(
        children: <Widget>[
          _HeaderCell('State', width: 148),
          _HeaderCell('Meaning', width: 372),
        ],
      ),
      rows: tcpStates
          .map((TcpState s) => _dataRow(context, mono, <_Cell>[
                _Cell(s.state, 148, _CellKind.key),
                _Cell(s.meaning, 372, _CellKind.prose),
              ]))
          .toList(),
    );
  }

  Widget _icmpTypeTable(
    BuildContext context,
    String title,
    List<IcmpTypeRow> types,
    String? codesHeaderOverride,
  ) {
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final String codesHeader = codesHeaderOverride ?? 'Codes';
    return _TableCard(
      title: title,
      footnote: null,
      header: Row(
        children: <Widget>[
          const _HeaderCell('Type', width: 56),
          const _HeaderCell('Name', width: 180),
          _HeaderCell(codesHeader, width: 400),
        ],
      ),
      rows: types.map((IcmpTypeRow t) {
        final String name =
            t.deprecated ? '${t.name} (deprecated)' : t.name;
        return _dataRow(context, mono, <_Cell>[
          _Cell('${t.type}', 56, _CellKind.key),
          _Cell(name, 180, _CellKind.mono),
          _Cell(t.codes, 400, _CellKind.prose),
        ]);
      }).toList(),
    );
  }

  Widget _icmpCodeTable(BuildContext context) {
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return _TableCard(
      title: 'ICMP Type 3 (Destination Unreachable) codes',
      footnote: icmpCitation,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Code', width: 56),
          _HeaderCell('Meaning', width: 372),
        ],
      ),
      rows: icmpType3Codes
          .map((IcmpCodeRow c) => _dataRow(context, mono, <_Cell>[
                _Cell('${c.code}', 56, _CellKind.key),
                _Cell(c.meaning, 372, _CellKind.prose),
              ]))
          .toList(),
    );
  }

  /// One data row: a per-cell styled Row wrapped in [ReferenceRowSemantics] so a
  /// screen reader announces it as a single node keyed on the first cell.
  Widget _dataRow(BuildContext context, AppMonoText mono, List<_Cell> cells) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    TextStyle styleFor(_Cell c) {
      switch (c.kind) {
        case _CellKind.key:
          return mono.inlineCode.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
          );
        case _CellKind.mono:
          return mono.inlineCode.copyWith(color: colors.textSecondary);
        case _CellKind.prose:
          return (text.labelMedium ?? const TextStyle())
              .copyWith(color: colors.textTertiary);
      }
    }

    return ReferenceRowSemantics(
      label: rowLabel(
        cells.first.text,
        cells.skip(1).map((_Cell c) => c.text).toList(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: cells
              .map((_Cell c) => SizedBox(
                    width: c.width,
                    child: Text(c.text, style: styleFor(c)),
                  ))
              .toList(),
        ),
      ),
    );
  }

  /// §8.16 copy payload — every table as a multi-section TSV so no value on
  /// screen survives only as layout or color. Always non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer b = StringBuffer()..writeln('Packet Decode');

    void fieldSection(String title, List<PacketField> fields, String cite) {
      b
        ..writeln()
        ..writeln(title)
        ..writeln(<String>['Field', 'Offset', 'Len', 'Meaning'].join(tab));
      for (final PacketField f in fields) {
        b.writeln(<String>[f.field, f.offset, f.length, f.meaning].join(tab));
      }
      b.writeln(cite);
    }

    void bitSection(String title, List<BitFieldRow> rows, String? note) {
      b
        ..writeln()
        ..writeln(title)
        ..writeln(<String>['Bits', 'Name', 'Meaning'].join(tab));
      for (final BitFieldRow r in rows) {
        b.writeln(<String>[r.bits, r.name, r.meaning].join(tab));
      }
      if (note != null) b.writeln(note);
    }

    fieldSection('IPv4 header', ipv4Header, ipv4Citation);
    bitSection('IPv4 Flags (bits 48-50)', ipv4Flags, null);
    bitSection('IPv4 ToS octet: DSCP + ECN (bits 8-15)', ipv4ToS, ipv4ToSNote);

    fieldSection('IPv6 header', ipv6Header, ipv6Citation);
    b.writeln(ipv6Note);

    b
      ..writeln()
      ..writeln('Common IP protocol numbers')
      ..writeln(<String>['No.', 'Name', 'Meaning'].join(tab));
    for (final ProtocolNumber p in protocolNumbers) {
      b.writeln(<String>['${p.number}', p.name, p.meaning].join(tab));
    }
    b.writeln(protoNumbersCitation);

    fieldSection('TCP header', tcpHeader, tcpCitation);

    b
      ..writeln()
      ..writeln('TCP flags (control bits 104-111)')
      ..writeln(<String>['Flag', 'Bit', 'Meaning'].join(tab));
    for (final TcpFlagRow f in tcpFlags) {
      final String flagLabel = f.historic ? '${f.flag} (historic)' : f.flag;
      b.writeln(<String>[flagLabel, '${f.bit}', f.meaning].join(tab));
    }
    b.writeln(tcpFlagsNote);

    fieldSection('UDP header', udpHeader, udpCitation);
    b.writeln(udpNote);

    b
      ..writeln()
      ..writeln('TCP connection states')
      ..writeln(<String>['State', 'Meaning'].join(tab));
    for (final TcpState s in tcpStates) {
      b.writeln(<String>[s.state, s.meaning].join(tab));
    }
    b.writeln(tcpStateCitation);

    b
      ..writeln()
      ..writeln('Three-way handshake (connection setup)');
    for (final HandshakeStep s in handshake) {
      b.writeln('${s.n}. ${s.detail}');
    }
    b
      ..writeln()
      ..writeln('Connection teardown (graceful, four-way)');
    for (final HandshakeStep s in teardown) {
      b.writeln('${s.n}. ${s.detail}');
    }
    b.writeln(teardownNote);

    fieldSection('ICMP common header (IPv4)', icmpHeader, icmpCitation);

    void typeSection(String title, List<IcmpTypeRow> types, String codesHeader) {
      b
        ..writeln()
        ..writeln(title)
        ..writeln(<String>['Type', 'Name', codesHeader].join(tab));
      for (final IcmpTypeRow t in types) {
        final String name = t.deprecated ? '${t.name} (deprecated)' : t.name;
        b.writeln(<String>['${t.type}', name, t.codes].join(tab));
      }
    }

    typeSection('ICMP types', icmpTypes, 'Codes');

    b
      ..writeln()
      ..writeln('ICMP Type 3 (Destination Unreachable) codes')
      ..writeln(<String>['Code', 'Meaning'].join(tab));
    for (final IcmpCodeRow c in icmpType3Codes) {
      b.writeln(<String>['${c.code}', c.meaning].join(tab));
    }

    fieldSection('ICMPv6 common header', icmpv6Header, icmpv6Citation);
    typeSection('ICMPv6 types', icmpv6Types, 'Codes');
    typeSection('ICMPv6 Neighbor Discovery (NDP, all Code 0)', icmpv6Ndp,
        'Purpose');

    return b.toString().trimRight();
  }
}

/// Card surface wrapping a wide table: a title, a horizontally-scrolling
/// IntrinsicWidth grid (header + rows share one width so columns align), and an
/// optional full-width footnote. Mirrors dscp_qos_screen's overflow-safe idiom.
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
              fontWeight: FontWeight.w600,
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
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
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

/// A numbered-step card (the handshake / teardown sequences): a title over
/// numbered rows, each a neutral step chip + the step detail. Optional note.
class _StepCard extends StatelessWidget {
  const _StepCard({required this.title, required this.steps, this.note});

  final String title;
  final List<HandshakeStep> steps;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
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
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...steps.map(
            (HandshakeStep s) => ReferenceRowSemantics(
              label: 'Step ${s.n}: ${s.detail}',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Neutral numbered step chip: surface + strong border + a
                    // DM Mono index. No status hue; the chip is structural and
                    // excluded from semantics (the row label already says the
                    // step number).
                    ExcludeSemantics(
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.surface2,
                          borderRadius:
                              BorderRadius.circular(AppRadius.control),
                          border:
                              Border.all(color: colors.borderStrong, width: 1),
                        ),
                        child: Text(
                          '${s.n}',
                          style: mono.inlineCode.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        s.detail,
                        style: text.labelMedium
                            ?.copyWith(color: colors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (note != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              note!,
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}
