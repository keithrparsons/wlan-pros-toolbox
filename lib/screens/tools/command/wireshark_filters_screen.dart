// Wireshark 802.11 Filters — grouped, filterable display + capture filters.
//
// Display filters (applied after capture, in the filter bar) and capture filters
// (BPF syntax, applied during capture) for 802.11 analysis. Read-only with a
// free-text filter. Data is the Pax research deliverable
// (pax-research-7-additions.md, "Wireshark 802.11 Filters"), sourced from the
// Wireshark dfref, the RadioTap dfref, pcap-filter(7), and IEEE 802.11-2020.
//
// Two corrections from Pax carried through verbatim:
//  1. The RSN cipher-suite vs AKM tables were REBUILT from IEEE 802.11-2020
//     Tables 9-149 (cipher = pcs/gcs.type) and 9-151 (AKM = akms.type); the
//     source card mislabeled cipher values as AKM. These tables use the
//     corrected field names.
//  2. The 5 GHz band filter: Pax flagged `radiotap.channel.flags.5ghz` as a
//     child-token to confirm against the running Wireshark build, with a SAFE
//     FALLBACK to `radiotap.channel.freq` ranges. Felix cannot verify the
//     child-token against a live Wireshark here, so the SAFE FALLBACK ships:
//     `radiotap.channel.freq >= 5000 && radiotap.channel.freq < 6000` (and a
//     2.4 GHz companion). `radiotap.channel.freq` is a documented dfref field;
//     this never ships an unverified token.
//
// States (SOP-007 §5):
//  - success → the filtered, grouped filter list renders (default; const
//    dataset, no load step).
//  - empty   → a filter query that matches nothing; an honest "no match" card.
// No loading / error / NetworkUnavailableView — fully offline on every platform
// (filters are reference text, never executed; GL-008 does not apply).
//
// Pattern: the reason_codes grouped-searchable idiom (see linux_wlan_commands).
// The filter syntax is the LIME column.
//
// Glyph note: ASCII hyphen-minus only; no em dash. "802.11" / "802.1X" casing.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// One Wireshark filter: the exact syntax and what it matches. Immutable.
@immutable
class WiresharkFilter {
  const WiresharkFilter(this.filter, this.description);

  /// The exact filter syntax. LIME column.
  final String filter;

  /// What it matches.
  final String description;
}

/// A labeled group of filters (Frame type/subtype, Address, RSN AKM, etc.).
@immutable
class FilterGroup {
  const FilterGroup(this.label, this.filters);

  final String label;
  final List<WiresharkFilter> filters;
}

/// One 802.11 status or reason code: the numeric code and its meaning. These
/// are NOT filters — they are the lookup an analyst reaches for next to the
/// auth/deauth filter.
@immutable
class StatusReasonCode {
  const StatusReasonCode(this.code, this.meaning);

  /// The numeric code as it appears in the dissected frame.
  final int code;

  /// What the code means.
  final String meaning;
}

/// A labeled table of status or reason codes.
@immutable
class CodeTable {
  const CodeTable(this.label, this.codes);

  final String label;
  final List<StatusReasonCode> codes;
}

class WiresharkFiltersScreen extends StatefulWidget {
  const WiresharkFiltersScreen({super.key});

  static const String intro =
      'Display filters (applied after capture, in the filter bar) and capture '
      'filters (BPF syntax, applied during capture) for 802.11 analysis, plus a '
      'general TCP/IP display-filter set (IP, TCP, UDP, and the common '
      'higher-layer protocols). Filter by syntax or task.';

  static const String caveat =
      'Display-filter field names match Wireshark\'s dfref. Capture filters use '
      'libpcap/BPF "type/subtype" syntax and only work when capturing with a '
      'RadioTap/PPI header.';

  static const String footnote =
      'type_subtype is the combined value (type in the high bits, subtype in '
      'the low bits) and matches IEEE 802.11 frame type/subtype assignments. '
      'Capture filters require capturing with a RadioTap header (monitor mode). '
      'For the full RSN cipher and AKM number-to-name map, see the RSN tables '
      'above or the WPA Security reference tool. The status and reason code '
      'tables list the highest-frequency 802.11 codes: status codes appear in '
      'Auth/Assoc responses; reason codes appear in Deauth/Disassoc frames. '
      'The TCP/IP display filters use Wireshark dfref field names (ip, ipv6, '
      'tcp, udp, icmp, arp, dns, http, tls); for the Layer 3-4 header fields '
      'those filters match on, see the Packet Decode reference.';

  /// The grouped filter set, verbatim from the Pax research deliverable, with
  /// the 5 GHz/2.4 GHz band filters using the SAFE freq-range fallback (see
  /// file header). Public + static so tests can assert known rows.
  static const List<FilterGroup> groups = <FilterGroup>[
    FilterGroup('Frame type/subtype (display)', <WiresharkFilter>[
      WiresharkFilter('wlan.fc.type == 0', 'All management frames'),
      WiresharkFilter('wlan.fc.type == 1', 'All control frames'),
      WiresharkFilter('wlan.fc.type == 2', 'All data frames'),
      WiresharkFilter('wlan.fc.type_subtype == 0', 'Association request'),
      WiresharkFilter('wlan.fc.type_subtype == 1', 'Association response'),
      WiresharkFilter('wlan.fc.type_subtype == 2', 'Reassociation request'),
      WiresharkFilter('wlan.fc.type_subtype == 3', 'Reassociation response'),
      WiresharkFilter('wlan.fc.type_subtype == 4', 'Probe request'),
      WiresharkFilter('wlan.fc.type_subtype == 5', 'Probe response'),
      WiresharkFilter('wlan.fc.type_subtype == 6', 'Timing advertisement'),
      WiresharkFilter('wlan.fc.type_subtype == 8', 'Beacon'),
      WiresharkFilter('wlan.fc.type_subtype == 9', 'ATIM'),
      WiresharkFilter('wlan.fc.type_subtype == 10', 'Disassociation'),
      WiresharkFilter('wlan.fc.type_subtype == 11', 'Authentication'),
      WiresharkFilter('wlan.fc.type_subtype == 12', 'Deauthentication'),
      WiresharkFilter('wlan.fc.type_subtype == 13', 'Action'),
      WiresharkFilter('wlan.fc.type_subtype == 14', 'Action no ack'),
      WiresharkFilter('wlan.fc.type_subtype == 23', 'Control wrapper'),
      WiresharkFilter('wlan.fc.type_subtype == 24', 'Block Ack Request'),
      WiresharkFilter('wlan.fc.type_subtype == 25', 'Block Ack'),
      WiresharkFilter('wlan.fc.type_subtype == 26', 'PS-Poll'),
      WiresharkFilter('wlan.fc.type_subtype == 27', 'RTS'),
      WiresharkFilter('wlan.fc.type_subtype == 28', 'CTS'),
      WiresharkFilter('wlan.fc.type_subtype == 29', 'Ack'),
      WiresharkFilter('wlan.fc.type_subtype == 30', 'CF-End'),
      WiresharkFilter('wlan.fc.type_subtype == 31', 'CF-End + CF-Ack'),
      WiresharkFilter('wlan.fc.type_subtype == 32', 'Data'),
      WiresharkFilter('wlan.fc.type_subtype == 36', 'Null data (no payload)'),
      WiresharkFilter('wlan.fc.type_subtype == 40', 'QoS data'),
      WiresharkFilter('wlan.fc.type_subtype == 44', 'QoS Null (no data)'),
    ]),
    FilterGroup('Address (display)', <WiresharkFilter>[
      WiresharkFilter('wlan.addr == aa:bb:cc:dd:ee:ff', 'Any address field equals this MAC (TA, RA, SA, or DA)'),
      WiresharkFilter('wlan.ta == aa:bb:cc:dd:ee:ff', 'Transmitter address'),
      WiresharkFilter('wlan.ra == aa:bb:cc:dd:ee:ff', 'Receiver address'),
      WiresharkFilter('wlan.sa == aa:bb:cc:dd:ee:ff', 'Source address'),
      WiresharkFilter('wlan.da == aa:bb:cc:dd:ee:ff', 'Destination address'),
    ]),
    FilterGroup('BSSID/SSID (display)', <WiresharkFilter>[
      WiresharkFilter('wlan.bssid == aa:bb:cc:dd:ee:ff', 'Frames for a specific BSSID'),
      WiresharkFilter('wlan.ssid == "MyNetwork"', 'Frames carrying this SSID (beacons, probes)'),
      WiresharkFilter('wlan.ssid contains "Guest"', 'SSID contains a substring'),
    ]),
    FilterGroup('RadioTap (display)', <WiresharkFilter>[
      WiresharkFilter('radiotap.channel.freq == 2412', 'Captured on this channel center frequency (MHz)'),
      WiresharkFilter('radiotap.datarate >= 6', 'PHY data rate at least 6 Mb/s'),
      WiresharkFilter('radiotap.dbm_antsignal > -70', 'RSSI stronger than -70 dBm'),
      WiresharkFilter('radiotap.dbm_antnoise < -90', 'Noise floor below -90 dBm'),
      // SAFE FALLBACK (Pax flag): freq-range band filters instead of the
      // unverified radiotap.channel.flags.5ghz child-token. freq is a
      // documented dfref field.
      WiresharkFilter('radiotap.channel.freq >= 2400 && radiotap.channel.freq < 2500', 'Captured in the 2.4 GHz band (frequency range)'),
      WiresharkFilter('radiotap.channel.freq >= 5000 && radiotap.channel.freq < 5900', 'Captured in the 5 GHz band (frequency range)'),
      WiresharkFilter('radiotap.channel.freq >= 5925 && radiotap.channel.freq <= 7125', 'Captured in the 6 GHz band (frequency range)'),
      WiresharkFilter('wlan_radio.signal_dbm < -75', 'Weak signal (uses the generic wlan_radio layer, not radiotap)'),
    ]),
    // NET-NEW (2026-06-12): retries, QoS, and weak-signal display filters.
    FilterGroup('Retries / QoS / weak signal (display)', <WiresharkFilter>[
      WiresharkFilter('wlan.fc.retry == 1', 'Retried frames (retransmissions)'),
      WiresharkFilter('wlan.fc.type_subtype == 5 && wlan_radio.signal_dbm < -75', 'Weak probe responses'),
      WiresharkFilter('wlan.fc.type_subtype == 4 && wlan_radio.signal_dbm < -75', 'Weak probe requests'),
      WiresharkFilter('wlan.qos.priority == 6', 'QoS priority / TID = 6 (voice access category)'),
    ]),
    // NET-NEW (2026-06-12): 802.11k/v/r roaming filters. From Keith's ECSE-T
    // course sheet. wlan.tag.number == 55 is the Mobility Domain element (MDE).
    FilterGroup('802.11k / v / r roaming (display)', <WiresharkFilter>[
      WiresharkFilter('wlan.fixed.action_code == 23', '802.11v DMS request'),
      WiresharkFilter('wlan.fixed.action_code == 24', '802.11v DMS response'),
      WiresharkFilter('wlan.rm.action_code == 4', '802.11k Neighbor report request'),
      WiresharkFilter('wlan.rm.action_code == 5', '802.11k Neighbor report response'),
      WiresharkFilter('(wlan.fc.type_subtype == 0) && (wlan.rsn.akms.type == 3)', '802.11r FT authentication request (FT over 802.1X)'),
      WiresharkFilter('(wlan.fc.type_subtype == 1) && (wlan.tag.number == 55)', '802.11r FT authentication response (Mobility Domain element)'),
      WiresharkFilter('(wlan.fc.type_subtype == 2) && (wlan.tag.number == 55)', '802.11r FT reassociation request'),
      WiresharkFilter('(wlan.fc.type_subtype == 3) && (wlan.tag.number == 55)', '802.11r FT reassociation response'),
    ]),
    // NET-NEW (2026-06-12): EAPOL / 4-way-handshake display filters.
    FilterGroup('Security / EAPOL (display)', <WiresharkFilter>[
      WiresharkFilter('eapol', 'All EAPOL key frames'),
      WiresharkFilter('wlan.addr == aa:bb:cc:dd:ee:ff && eapol', 'The 4-way handshake for one client'),
    ]),
    FilterGroup('Capture filter (BPF)', <WiresharkFilter>[
      WiresharkFilter('type mgt', 'Only management frames'),
      WiresharkFilter('type ctl', 'Only control frames'),
      WiresharkFilter('type data', 'Only data frames'),
      WiresharkFilter('type mgt subtype beacon', 'Beacons only'),
      WiresharkFilter('type mgt subtype probe-req', 'Probe requests only'),
      WiresharkFilter('type mgt subtype probe-resp', 'Probe responses only'),
      WiresharkFilter('type mgt subtype assoc-req', 'Association requests only'),
      WiresharkFilter('type mgt subtype assoc-resp', 'Association responses only'),
      WiresharkFilter('type mgt subtype auth', 'Authentication frames only'),
      WiresharkFilter('type mgt subtype deauth', 'Deauthentication frames only'),
      WiresharkFilter('type mgt subtype disassoc', 'Disassociations only'),
      WiresharkFilter('type ctl subtype rts', 'RTS frames only'),
      WiresharkFilter('type ctl subtype rts || subtype cts', 'RTS/CTS frames only'),
      WiresharkFilter('type ctl subtype ack', 'Acknowledgement frames only'),
      WiresharkFilter('type ctl subtype ps-poll', 'PS-Poll frames only'),
      WiresharkFilter('type data subtype null', 'Null data frames only'),
      WiresharkFilter('type data subtype qos-data', 'QoS data frames only'),
      WiresharkFilter('wlan host aa:bb:cc:dd:ee:ff', 'Frames to/from this L2 address'),
      WiresharkFilter('ether host aa:bb:cc:dd:ee:ff', 'Frames to/from this L2 address (ether-host form)'),
      WiresharkFilter('not broadcast', 'Drop broadcast frames'),
      WiresharkFilter('not multicast', 'Drop multicast frames'),
    ]),
    // CORRECTED per Pax: cipher-suite selectors are pcs/gcs.type (Table 9-149),
    // NOT akms.type. The source card mislabeled these as AKM.
    FilterGroup('RSN cipher (display)', <WiresharkFilter>[
      WiresharkFilter('wlan.rsn.pcs.type == 4', 'Pairwise cipher = CCMP-128 (00-0F-AC:4)'),
      WiresharkFilter('wlan.rsn.pcs.type == 8', 'Pairwise cipher = GCMP-128 (00-0F-AC:8)'),
      WiresharkFilter('wlan.rsn.pcs.type == 9', 'Pairwise cipher = GCMP-256 (00-0F-AC:9)'),
      WiresharkFilter('wlan.rsn.gcs.type == 2', 'Group cipher = TKIP (00-0F-AC:2)'),
    ]),
    // CORRECTED per Pax: AKM selectors are akms.type (Table 9-151).
    FilterGroup('RSN AKM (display)', <WiresharkFilter>[
      WiresharkFilter('wlan.rsn.akms.type == 1', 'AKM = 802.1X (00-0F-AC:1)'),
      WiresharkFilter('wlan.rsn.akms.type == 2', 'AKM = PSK (00-0F-AC:2)'),
      WiresharkFilter('wlan.rsn.akms.type == 8', 'AKM = SAE / WPA3-Personal (00-0F-AC:8)'),
      WiresharkFilter('wlan.rsn.akms.type == 18', 'AKM = OWE (00-0F-AC:18)'),
    ]),
    // NET-NEW (2026-06-12): display-filter operators reference. Both the symbol
    // and the word form are valid; shown so a reader can build combined filters,
    // e.g. wlan.bssid == aa:bb:cc:dd:ee:ff && wlan.fc.retry == 1.
    FilterGroup('Operators (display, reference)', <WiresharkFilter>[
      WiresharkFilter('==  /  eq', 'Equal'),
      WiresharkFilter('!=  /  ne', 'Not equal'),
      WiresharkFilter('&&  /  and', 'And'),
      WiresharkFilter('||  /  or', 'Or'),
      WiresharkFilter('^^  /  xor', 'Xor'),
      WiresharkFilter('!  /  not', 'Not'),
      WiresharkFilter('contains', 'Substring / byte-sequence match'),
    ]),
    // ── General TCP/IP display filters (2026-07-18) ──
    // Layer 3-4 display filters that pair with the Packet Decode reference. Field
    // names match Wireshark's dfref (ip, ipv6, tcp, udp, icmp, arp, dns, http,
    // tls). These decode the L3-4 headers that ride below 802.11 and are the
    // filters an analyst reaches for once past the radio layer.
    FilterGroup('IP addressing (TCP/IP display)', <WiresharkFilter>[
      WiresharkFilter('ip.addr == 10.0.0.5', 'IPv4 source OR destination equals this address'),
      WiresharkFilter('ip.src == 10.0.0.5', 'IPv4 source address'),
      WiresharkFilter('ip.dst == 10.0.0.5', 'IPv4 destination address'),
      WiresharkFilter('ip.addr == 192.168.1.0/24', 'Any IPv4 address in this subnet (CIDR)'),
      WiresharkFilter('!(ip.addr == 10.0.0.5)', 'Exclude all traffic to/from an address'),
      WiresharkFilter('ipv6.addr == 2001:db8::1', 'IPv6 source OR destination address'),
      WiresharkFilter('ipv6.src == 2001:db8::1', 'IPv6 source address'),
      WiresharkFilter('ipv6.dst == 2001:db8::1', 'IPv6 destination address'),
      WiresharkFilter('ip.ttl < 5', 'Low IPv4 TTL (near a routing loop or a traceroute)'),
    ]),
    FilterGroup('TCP / UDP (TCP/IP display)', <WiresharkFilter>[
      WiresharkFilter('tcp.port == 443', 'TCP source OR destination port'),
      WiresharkFilter('tcp.dstport == 22', 'TCP destination port only'),
      WiresharkFilter('udp.port == 53', 'UDP source OR destination port'),
      WiresharkFilter('tcp.flags.syn == 1 && tcp.flags.ack == 0', 'SYN without ACK (connection attempts)'),
      WiresharkFilter('tcp.flags.reset == 1', 'TCP resets (RST)'),
      WiresharkFilter('tcp.flags.fin == 1', 'TCP FINs (graceful close)'),
      WiresharkFilter('tcp.analysis.retransmission', 'Retransmitted TCP segments'),
      WiresharkFilter('tcp.analysis.zero_window', 'Zero-window (receiver told the sender to stop)'),
      WiresharkFilter('tcp.analysis.flags', 'All of Wireshark\'s TCP expert findings'),
      WiresharkFilter('tcp.stream eq 0', 'Every packet of one TCP conversation (stream index)'),
      WiresharkFilter('tcp.len > 0', 'TCP segments that carry payload (exclude pure ACKs)'),
    ]),
    FilterGroup('Higher-layer protocols (TCP/IP display)', <WiresharkFilter>[
      WiresharkFilter('icmp', 'All ICMP (IPv4)'),
      WiresharkFilter('icmpv6', 'All ICMPv6 (incl. Neighbor Discovery)'),
      WiresharkFilter('arp', 'All ARP requests and replies'),
      WiresharkFilter('dns', 'All DNS queries and responses'),
      WiresharkFilter('dns.flags.response == 1', 'DNS responses only'),
      WiresharkFilter('http', 'All HTTP'),
      WiresharkFilter('http.request', 'HTTP requests only'),
      WiresharkFilter('http.response.code == 404', 'HTTP responses with a given status code'),
      WiresharkFilter('tls', 'All TLS records'),
      WiresharkFilter('tls.handshake.type == 1', 'TLS Client Hello (handshake type 1)'),
      WiresharkFilter('dhcp', 'All DHCP (was bootp in older Wireshark)'),
    ]),
  ];

  /// 802.11 status and reason codes (the lookup an analyst reaches for next to
  /// the auth/deauth filter). NOT filters — a companion reference table rendered
  /// below the filter groups. From the Garringer reference (CWNE #179); the
  /// highest-frequency subset. Public + static for tests.
  static const List<CodeTable> codeTables = <CodeTable>[
    CodeTable(
      'Status codes (Auth/Assoc responses, never connected)',
      <StatusReasonCode>[
        StatusReasonCode(0, 'Success'),
        StatusReasonCode(1, 'Unspecified failure'),
        StatusReasonCode(10, 'Mismatched / unsupported capabilities'),
        StatusReasonCode(11, 'Inability to confirm association'),
        StatusReasonCode(12, 'Outside the scope of the standard'),
        StatusReasonCode(13, 'STA does not support the auth algorithm'),
        StatusReasonCode(17, 'AP unable to support additional associations (cell full)'),
        StatusReasonCode(18, 'Refused - basic rates mismatch'),
        StatusReasonCode(27, 'Requesting STA has no HT support'),
        StatusReasonCode(41, 'Invalid group cipher'),
        StatusReasonCode(42, 'Invalid pairwise cipher'),
        StatusReasonCode(104, 'Requesting STA does not support VHT features'),
      ],
    ),
    CodeTable(
      'Reason codes (Deauth/Disassoc, no longer connected)',
      <StatusReasonCode>[
        StatusReasonCode(1, 'Unspecified reason'),
        StatusReasonCode(2, 'Previous authentication no longer valid'),
        StatusReasonCode(3, 'Deauthenticated - sending STA is leaving/has left'),
        StatusReasonCode(4, 'Disassociated due to inactivity'),
        StatusReasonCode(5, 'AP unable to handle all currently associated STAs'),
        StatusReasonCode(6, 'Class 2 frame from a non-authenticated STA'),
        StatusReasonCode(7, 'Class 3 frame from a non-associated STA'),
        StatusReasonCode(14, 'Message integrity code (MIC) failure'),
        StatusReasonCode(15, '4-way handshake timeout'),
        StatusReasonCode(16, 'Group key handshake timeout'),
        StatusReasonCode(23, 'IEEE 802.1X authentication failed'),
        StatusReasonCode(49, 'Invalid pairwise master key identifier (PMKID)'),
      ],
    ),
  ];

  @override
  State<WiresharkFiltersScreen> createState() => _WiresharkFiltersScreenState();
}

class _WiresharkFiltersScreenState extends State<WiresharkFiltersScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  String _query = '';

  @override
  void dispose() {
    _queryCtrl.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  bool _matches(WiresharkFilter f, String q) {
    if (q.isEmpty) return true;
    return f.filter.toLowerCase().contains(q) ||
        f.description.toLowerCase().contains(q);
  }

  FilterGroup? _filterGroup(FilterGroup g, String q) {
    if (q.isEmpty) return g;
    if (g.label.toLowerCase().contains(q)) return g;
    final List<WiresharkFilter> kept =
        g.filters.where((WiresharkFilter f) => _matches(f, q)).toList();
    if (kept.isEmpty) return null;
    return FilterGroup(g.label, kept);
  }

  bool _matchesCode(StatusReasonCode c, String q) {
    if (q.isEmpty) return true;
    return c.code.toString().contains(q) || c.meaning.toLowerCase().contains(q);
  }

  CodeTable? _filterCodeTable(CodeTable t, String q) {
    if (q.isEmpty) return t;
    if (t.label.toLowerCase().contains(q)) return t;
    final List<StatusReasonCode> kept =
        t.codes.where((StatusReasonCode c) => _matchesCode(c, q)).toList();
    if (kept.isEmpty) return null;
    return CodeTable(t.label, kept);
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    final String q = value.trim().toLowerCase();
    int n = 0;
    for (final FilterGroup g in WiresharkFiltersScreen.groups) {
      final FilterGroup? f = _filterGroup(g, q);
      if (f != null) n += f.filters.length;
    }
    for (final CodeTable t in WiresharkFiltersScreen.codeTables) {
      final CodeTable? f = _filterCodeTable(t, q);
      if (f != null) n += f.codes.length;
    }
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0 ? 'No matching rows' : '$n matching row${n == 1 ? '' : 's'}',
      TextDirection.ltr,
    );
  }

  /// §8.16 plain-text payload — every filter group with its exact syntax, then
  /// the status/reason-code tables, so a reader can paste the whole sheet.
  static String _copyText() {
    const String tab = '\t';
    final StringBuffer b = StringBuffer()
      ..writeln('Wireshark 802.11 Filters')
      ..writeln();
    for (final FilterGroup g in WiresharkFiltersScreen.groups) {
      b.writeln(g.label);
      for (final WiresharkFilter f in g.filters) {
        b.writeln('  ${f.filter}$tab${f.description}');
      }
      b.writeln();
    }
    for (final CodeTable t in WiresharkFiltersScreen.codeTables) {
      b.writeln(t.label);
      for (final StatusReasonCode c in t.codes) {
        b.writeln('  ${c.code}$tab${c.meaning}');
      }
      b.writeln();
    }
    b.writeln(WiresharkFiltersScreen.footnote);
    return b.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wireshark 802.11 Filters'),
        toolbarHeight: 64,
        actions: <Widget>[
          AppCopyAction(textBuilder: _copyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
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
                  ConceptGraphicBand(
                    toolId: 'wireshark-80211-filters',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('wireshark-80211-filters'))
                    const SizedBox(height: AppSpacing.md),
                  _introCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _searchCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  ..._results(context),
                  ToolHelpFooter(toolId: 'wireshark-80211-filters'),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            WiresharkFiltersScreen.intro,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            WiresharkFiltersScreen.caveat,
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _searchCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: LabeledField(
        label: 'Filter',
        hint: 'syntax or task',
        semanticLabel: 'Filter Wireshark filters by syntax or task',
        field: TextField(
          controller: _queryCtrl,
          focusNode: _queryFocus,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          cursorColor: colors.textAccent,
          decoration: const InputDecoration(
            hintText: 'e.g. beacon or rsn',
          ),
        ),
      ),
    );
  }

  List<Widget> _results(BuildContext context) {
    final String q = _query.trim().toLowerCase();

    final List<Widget> cards = <Widget>[];
    for (final FilterGroup g in WiresharkFiltersScreen.groups) {
      final FilterGroup? f = _filterGroup(g, q);
      if (f != null) {
        cards.add(_GroupCard(group: f));
        cards.add(const SizedBox(height: AppSpacing.sm));
      }
    }
    for (final CodeTable t in WiresharkFiltersScreen.codeTables) {
      final CodeTable? f = _filterCodeTable(t, q);
      if (f != null) {
        cards.add(_CodeTableCard(table: f));
        cards.add(const SizedBox(height: AppSpacing.sm));
      }
    }

    if (cards.isEmpty) {
      return <Widget>[
        _MessageCard(
          icon: Icons.search_off,
          title: 'No match',
          body: 'No filter or code matches "${_query.trim()}".',
        ),
      ];
    }

    cards.add(_footnote(context));
    return cards;
  }

  Widget _footnote(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      WiresharkFiltersScreen.footnote,
      style: text.labelSmall?.copyWith(color: colors.textTertiary),
    );
  }
}

/// One group: a heading over its filter rows in a bordered card.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final FilterGroup group;

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
        children: [
          Text(
            group.label,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...group.filters.map(
            (WiresharkFilter f) =>
                _FilterRow(filter: f, mono: mono, text: text),
          ),
        ],
      ),
    );
  }
}

/// One filter row: the mono syntax (lime) over its description.
class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.filter,
    required this.mono,
    required this.text,
  });

  final WiresharkFilter filter;
  final AppMonoText mono;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${filter.filter}, ${filter.description}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              filter.filter,
              style: mono.inlineCode.copyWith(
                color: colors.textAccent,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              filter.description,
              style: text.labelMedium?.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

/// One status/reason-code table: a heading over numeric-code rows. The code
/// number sits in a fixed mono gutter so the meanings align.
class _CodeTableCard extends StatelessWidget {
  const _CodeTableCard({required this.table});

  final CodeTable table;

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
        children: [
          Text(
            table.label,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...table.codes.map(
            (StatusReasonCode c) => Semantics(
              container: true,
              excludeSemantics: true,
              label: 'Code ${c.code}, ${c.meaning}',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${c.code}',
                        style: mono.inlineCode.copyWith(
                          color: colors.textAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        c.meaning,
                        style: text.labelMedium
                            ?.copyWith(color: colors.textTertiary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty-state card — mirrors the reason_codes "no match" surface.
class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: text.labelMedium?.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
