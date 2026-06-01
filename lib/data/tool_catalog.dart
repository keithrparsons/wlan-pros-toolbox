// Tool catalog — single source of truth for what appears on the home grid and
// what tools each category exposes.
//
// Category structure: the LOCKED 6-category map
// (Deliverables/2026-05-30-quick-reference-additions-triage/
//  LOCKED-6-category-structure.md), which supersedes the prior 8-category
// layout. The four dissolved categories (GPS Tools, Cabling & Connectors,
// Infrastructure, Wi-Fi Design) merged their tools into the survivors per the
// locked map; nothing was dropped.
//
// Category activation (Felix, 2026-05-30): the two NEW categories from the
// LOCKED map — Command & Capture and Checklists — were initially deferred while
// their tools were pending. Their 7 additions (Hex/ASCII, OSI Model, 3 command
// sheets, 2 checklists) are now built and live, so both categories are ACTIVE.
// The home grid now renders all 6 LOCKED categories (Calculators, Networking
// Tools, Planning Tools, Quick Reference, Command & Capture, Checklists). The
// tappable-checklist screen type (checklist_screen.dart) renders the
// Pax-transcribed card content via the consts in data/checklists.dart.
//
// Display-title rename pass (LOCKED map "Display-title rename pass"): titles
// were reclustered by function (e.g. "DNS Lookup" → "Lookup (DNS)"). The
// catalog `id` strings are STABLE and unchanged — they back 60 icon/graphic
// asset files, every route, and every test. Titles change; ids never.

import 'package:flutter/material.dart';

/// A single tool that can be launched from a category screen.
@immutable
class ToolEntry {
  const ToolEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.routeName,
    this.isLive = false,
  });

  /// Stable identifier (kebab-case). Used as the route argument and for
  /// telemetry later. NEVER renamed — backs asset files, routes, and tests.
  final String id;

  /// Title shown on the category tile / list row.
  final String title;

  /// One-line description shown under the title.
  final String description;

  /// Route name passed to `Navigator.pushNamed`. Ignored when `isLive` false.
  final String routeName;

  /// `true` when the tool is shippable; `false` renders as a disabled
  /// "Coming soon" row.
  final bool isLive;
}

/// One of the home-grid categories.
@immutable
class ToolCategory {
  const ToolCategory({
    required this.id,
    required this.title,
    required this.summary,
    required this.icon,
    required this.tools,
  });

  final String id;
  final String title;
  final String summary;
  final IconData icon;
  final List<ToolEntry> tools;

  /// Whether at least one tool in this category is live. Used to grey the
  /// home-grid tile when the entire category is placeholder.
  bool get hasLiveTool => tools.any((t) => t.isLive);
}

/// Catalog seed — the LOCKED 6-category map, with Command & Capture and
/// Checklists deferred until their tools are built (see file header). Tool
/// order within each category follows the LOCKED map exactly.
const List<ToolCategory> kToolCategories = <ToolCategory>[
  // ───────────────────────── 1. Calculators ─────────────────────────
  // Was "RF Calculators". Absorbs all GPS tools + Noise Floor + RF Attenuation
  // (from the dissolved Infrastructure category).
  ToolCategory(
    id: 'rf-calculators',
    title: 'Calculators',
    summary: 'RF, GPS, and signal math — FSPL, EIRP, coordinates',
    icon: Icons.calculate_outlined,
    tools: <ToolEntry>[
      ToolEntry(
        id: 'dbm-watt-converter',
        title: 'dBm / Watt Converter',
        description: 'Live two-way conversion across dBm, Watts, and mW',
        routeName: '/tools/dbm-watt',
        isLive: true,
      ),
      ToolEntry(
        id: 'fspl',
        title: 'Free Space Path Loss',
        description: 'FSPL for any frequency and distance',
        routeName: '/tools/fspl',
        isLive: true,
      ),
      ToolEntry(
        id: 'eirp',
        title: 'EIRP Calculator',
        description: 'Effective isotropic radiated power',
        routeName: '/tools/eirp',
        isLive: true,
      ),
      ToolEntry(
        id: 'fresnel',
        title: 'Fresnel Zone',
        description: 'First-zone radius and 60% clearance',
        routeName: '/tools/fresnel',
        isLive: true,
      ),
      ToolEntry(
        id: 'cable-loss',
        title: 'Cable Loss',
        description: 'Coax loss by cable type, length, and frequency',
        routeName: '/tools/cable-loss',
        isLive: true,
      ),
      ToolEntry(
        id: 'link-budget',
        title: 'Link Budget',
        description: 'Received signal and fade margin end to end',
        routeName: '/tools/link-budget',
        isLive: true,
      ),
      ToolEntry(
        id: 'wavelength',
        title: 'Wavelength',
        description: 'Wavelength from frequency, m / cm / ft / in',
        routeName: '/tools/wavelength',
        isLive: true,
      ),
      ToolEntry(
        id: 'downtilt',
        title: 'Antenna Downtilt',
        description: 'Downtilt angle from height and target distance',
        routeName: '/tools/downtilt',
        isLive: true,
      ),
      ToolEntry(
        id: 'earth-curvature',
        title: 'Earth Curvature',
        description: 'Earth bulge over a path, with K-factor',
        routeName: '/tools/earth-curvature',
        isLive: true,
      ),
      ToolEntry(
        id: 'rain-fade',
        title: 'ITU Rain Fade',
        description: 'Rain attenuation per ITU-R P.838-3 and P.530',
        routeName: '/tools/rain-fade',
        isLive: true,
      ),
      ToolEntry(
        id: 'downtilt-coverage',
        title: 'Downtilt Coverage',
        description: 'Coverage edges from height, tilt, and beamwidth',
        routeName: '/tools/downtilt-coverage',
        isLive: true,
      ),
      // ── from the dissolved GPS Tools category ──
      ToolEntry(
        id: 'metric-conversion',
        title: 'Metric Conversion',
        description: 'm, km, mi, ft, cm, in, nmi',
        routeName: '/tools/metric-conversion',
        isLive: true,
      ),
      // ── from the dissolved Infrastructure category ──
      ToolEntry(
        id: 'noise-floor',
        title: 'Noise Floor',
        description: 'Thermal noise floor by channel width and NF',
        routeName: '/tools/noise-floor',
        isLive: true,
      ),
      ToolEntry(
        id: 'rf-attenuation',
        title: 'RF Attenuation',
        description: 'Path loss through building materials by band',
        routeName: '/tools/rf-attenuation',
        isLive: true,
      ),
      // ── from the dissolved GPS Tools category ──
      ToolEntry(
        id: 'lat-long',
        title: 'Lat / Long Conversion',
        description: 'Convert between DD, DDM, and DMS',
        routeName: '/tools/lat-long',
        isLive: true,
      ),
      ToolEntry(
        id: 'dist-bearing',
        title: 'Distance and Bearing',
        description: 'Great-circle distance and bearing between two points',
        routeName: '/tools/dist-bearing',
        isLive: true,
      ),
      ToolEntry(
        id: 'midpoint',
        title: 'Midpoint',
        description: 'Great-circle midpoint between two coordinates',
        routeName: '/tools/midpoint',
        isLive: true,
      ),
      ToolEntry(
        id: 'final-point',
        title: 'Final Point',
        description: 'Destination from a start point, bearing, and distance',
        routeName: '/tools/final-point',
        isLive: true,
      ),
      // Hex / ASCII converter + printable-ASCII table — NEW.
      ToolEntry(
        id: 'hex-ascii',
        title: 'Hex / ASCII',
        description: 'Dec/hex/binary converter + ASCII table',
        routeName: '/tools/hex-ascii',
        isLive: true,
      ),
    ],
  ),

  // ──────────────────────── 2. Networking Tools ─────────────────────
  // Unchanged set + IPv6 Subnet moved in from Planning. Display titles
  // reclustered by function per the LOCKED rename pass.
  ToolCategory(
    id: 'networking',
    title: 'Networking Tools',
    summary: 'Interface info, lookups, scans, subnetting',
    icon: Icons.lan_outlined,
    tools: <ToolEntry>[
      ToolEntry(
        id: 'interface-info',
        title: 'Interface Information',
        description: 'Local IPs, gateway, DNS, Wi-Fi link, interface type',
        routeName: '/tools/interface-info',
        isLive: true,
      ),
      ToolEntry(
        id: 'dns-lookup',
        title: 'Lookup (DNS)',
        description:
            'A, AAAA, MX, TXT, NS, SOA, PTR, SRV, CAA, SPF over DNS-over-HTTPS',
        routeName: '/tools/dns-lookup',
        isLive: true,
      ),
      ToolEntry(
        id: 'port-scan',
        title: 'Port Scan',
        description: 'TCP connect scan — common ports preset or custom range',
        routeName: '/tools/port-scan',
        isLive: true,
      ),
      ToolEntry(
        id: 'ping',
        title: 'Ping (TCP)',
        description:
            'TCP-handshake round-trip probe (not ICMP) — works on every '
            'platform incl. sandboxed desktop',
        routeName: '/tools/ping',
        isLive: true,
      ),
      ToolEntry(
        id: 'icmp-ping',
        title: 'Ping (ICMP)',
        description:
            'Real ICMP echo round-trip (mobile) — live RTT, min/avg/max, loss',
        routeName: '/tools/icmp-ping',
        isLive: true,
      ),
      ToolEntry(
        id: 'ping-sweep',
        title: 'Ping Sweep',
        description:
            'Discover responsive hosts on a subnet — TCP-probe sweep, no ICMP',
        routeName: '/tools/ping-sweep',
        isLive: true,
      ),
      ToolEntry(
        id: 'network-discovery',
        title: 'Network Discovery',
        description:
            'Find live hosts on your network — name, services, device type, '
            'and vendor (desktop)',
        routeName: '/tools/network-discovery',
        isLive: true,
      ),
      ToolEntry(
        id: 'wifi-vs-internet',
        title: 'Wi-Fi vs Internet',
        description:
            'Is the slowdown your Wi-Fi link or the internet upstream? '
            'Compares link rate to measured throughput',
        routeName: '/tools/wifi-vs-internet',
        isLive: true,
      ),
      ToolEntry(
        id: 'net-quality',
        title: 'Network Quality',
        description:
            'Latency, jitter, loss, throughput, responsiveness, and site '
            'reachability',
        routeName: '/tools/net-quality',
        isLive: true,
      ),
      ToolEntry(
        id: 'wifi-info',
        title: 'Wi-Fi Information',
        description:
            'Live Wi-Fi link details: SSID, BSSID, RSSI, noise, SNR, channel, '
            'width, band, standard (macOS)',
        routeName: '/tools/wifi-info',
        isLive: true,
      ),
      ToolEntry(
        id: 'traceroute',
        title: 'Traceroute (System)',
        description: 'Hop-by-hop path via the OS traceroute — desktop',
        routeName: '/tools/traceroute',
        isLive: true,
      ),
      ToolEntry(
        id: 'mobile-traceroute',
        title: 'Traceroute (Mobile)',
        description:
            'Hop-by-hop path via an ICMP TTL-walk — Android (iOS unsupported)',
        routeName: '/tools/mobile-traceroute',
        isLive: true,
      ),
      ToolEntry(
        id: 'ssl-inspect',
        title: 'Inspector (SSL/TLS)',
        description:
            'Certificate fields, validity, SAN, fingerprints over TLS',
        routeName: '/tools/ssl-inspect',
        isLive: true,
      ),
      ToolEntry(
        id: 'http-headers',
        title: 'Inspector (HTTP Header)',
        description: 'Status, redirect chain, and all response headers',
        routeName: '/tools/http-headers',
        isLive: true,
      ),
      ToolEntry(
        id: 'whois',
        title: 'WHOIS',
        description: 'Domain / IP registration record over WHOIS (port 43)',
        routeName: '/tools/whois',
        isLive: true,
      ),
      ToolEntry(
        id: 'wake-on-lan',
        title: 'Wake-on-LAN',
        description: 'Send a magic packet to wake a host by MAC address',
        routeName: '/tools/wake-on-lan',
        isLive: true,
      ),
      ToolEntry(
        id: 'arp-ndp',
        title: 'Lookup (ARP/NDP)',
        description: 'Discover local neighbors — IP and MAC where exposed',
        routeName: '/tools/arp-ndp',
        isLive: true,
      ),
      ToolEntry(
        id: 'bgp-asn',
        title: 'Lookup (BGP/ASN)',
        description: 'ASN, holder, prefix, registry, peers via RIPEstat',
        routeName: '/tools/bgp-asn',
        isLive: true,
      ),
      ToolEntry(
        id: 'ip-geo',
        title: 'IP Geolocation',
        description: 'Country, city, coordinates, timezone, ISP, ASN',
        routeName: '/tools/ip-geo',
        isLive: true,
      ),
      ToolEntry(
        id: 'mac-oui-lookup',
        title: 'MAC Vendor OUI Lookup',
        description:
            'MAC → vendor from a bundled IEEE OUI table, fully offline',
        routeName: '/tools/mac-oui',
        isLive: true,
      ),
      ToolEntry(
        id: 'packet-sender',
        title: 'Packet Sender',
        description: 'Send a custom TCP/UDP payload and read the reply',
        routeName: '/tools/packet-sender',
        isLive: true,
      ),
      ToolEntry(
        id: 'ipv4-subnet',
        title: 'IP Subnetting (IPv4)',
        description: 'Network, broadcast, host range, mask ⇄ prefix, CIDR math',
        routeName: '/tools/ipv4-subnet',
        isLive: true,
      ),
      // ── moved in from the (now-small) Planning Tools category ──
      ToolEntry(
        id: 'ipv6-subnet',
        title: 'IP Subnetting (IPv6)',
        description: 'IPv6 prefix, expansion, and address counts',
        routeName: '/tools/ipv6-subnet',
        isLive: true,
      ),
    ],
  ),

  // ───────────────────────── 3. Planning Tools ──────────────────────
  // Kept deliberately small (4 tools). PoE Budget moved in from the dissolved
  // Infrastructure category; IPv6 Subnet moved out to Networking.
  ToolCategory(
    id: 'planning-tools',
    title: 'Planning Tools',
    summary: 'PoE budget, throughput, capacity, PtP',
    icon: Icons.architecture_outlined,
    tools: <ToolEntry>[
      // ── from the dissolved Infrastructure category ──
      ToolEntry(
        id: 'poe-budget',
        title: 'PoE Budget',
        description: 'Switch PoE budget vs connected device draw',
        routeName: '/tools/poe-budget',
        isLive: true,
      ),
      ToolEntry(
        id: 'throughput-calc',
        title: 'Throughput Calculator',
        description: 'PHY rate and effective throughput by MCS',
        routeName: '/tools/throughput-calc',
        isLive: true,
      ),
      ToolEntry(
        id: 'capacity-planner',
        title: 'Capacity Planner',
        description: 'Recommended AP count by users and demand',
        routeName: '/tools/capacity-planner',
        isLive: true,
      ),
      ToolEntry(
        id: 'ptp-link',
        title: 'PtP Link Check',
        description: 'Point-to-point link budget and fade margin',
        routeName: '/tools/ptp-link',
        isLive: true,
      ),
    ],
  ),

  // ──────────────────────── 4. Quick Reference ──────────────────────
  // Absorbs all Cabling & Connectors, the 3 Wi-Fi Design tools, PoE Reference
  // (from Infrastructure), plus the existing Wi-Fi reference tables. Tool order
  // follows the LOCKED map. (OSI Model — NEW — pending build, not added yet.)
  ToolCategory(
    id: 'quick-reference',
    title: 'Quick Reference',
    summary: 'PoE, channels, standards, cabling, lookup tables',
    icon: Icons.menu_book_outlined,
    tools: <ToolEntry>[
      // ── from the dissolved Infrastructure category ──
      ToolEntry(
        id: 'poe-reference',
        title: 'PoE Reference',
        description: 'PoE class, wattage, and budget',
        routeName: '/tools/poe-reference',
        isLive: true,
      ),
      ToolEntry(
        id: 'wifi-channels',
        title: 'Wi-Fi Channels',
        description: 'Channels, center frequencies, widths, DFS by band',
        routeName: '/tools/wifi-channels',
        isLive: true,
      ),
      ToolEntry(
        id: '80211-standards',
        title: '802.11 Standards',
        description: 'Generations, bands, rates, widths, Wi-Fi 4 to 7',
        routeName: '/tools/standards',
        isLive: true,
      ),
      ToolEntry(
        id: 'mcs-index',
        title: 'MCS Index',
        description: 'Modulation and data rates by MCS, width, streams',
        routeName: '/tools/mcs-index',
        isLive: true,
      ),
      ToolEntry(
        id: 'signal-thresholds',
        title: 'Signal Thresholds',
        description: 'RSSI and SNR targets by application',
        routeName: '/tools/signal-thresholds',
        isLive: true,
      ),
      // ── from the dissolved Wi-Fi Design category ──
      ToolEntry(
        id: 'wpa-security',
        title: 'WPA Security',
        description: 'WPA2 / WPA3 reference matrix',
        routeName: '/tools/wpa-security',
        isLive: true,
      ),
      ToolEntry(
        id: 'roaming',
        title: 'Roaming Parameters',
        description: '802.11r/k/v and RSSI/SNR roaming thresholds',
        routeName: '/tools/roaming',
        isLive: true,
      ),
      ToolEntry(
        id: 'ap-placement',
        title: 'AP Placement',
        description: 'Mounting, spacing, and cell-overlap guidance',
        routeName: '/tools/ap-placement',
        isLive: true,
      ),
      ToolEntry(
        id: 'port-reference',
        title: 'Well-Known Ports',
        description:
            'Search common TCP/UDP ports by number or service name — offline',
        routeName: '/tools/port-reference',
        isLive: true,
      ),
      ToolEntry(
        id: 'reason-codes',
        title: '802.11 Reason Codes',
        description: '802.11 deauth / disassoc reason and status codes',
        routeName: '/tools/reason-codes',
        isLive: true,
      ),
      ToolEntry(
        id: 'frame-exchange',
        title: '802.11 Frame Exchange',
        description: '802.11 association and handshake frame sequences',
        routeName: '/tools/frame-exchange',
        isLive: true,
      ),
      ToolEntry(
        id: 'db-reference',
        title: 'dB Reference',
        description: 'dB to ratio and dBm anchor values',
        routeName: '/tools/db-reference',
        isLive: true,
      ),
      ToolEntry(
        id: 'channel-map',
        title: 'Channel Map',
        description: '5 and 6 GHz channel bonding map by width',
        routeName: '/tools/channel-map',
        isLive: true,
      ),
      ToolEntry(
        id: 'spectrum',
        title: 'Spectrum Reference',
        description: 'Band allocations, sub-bands, and co-existence',
        routeName: '/tools/spectrum',
        isLive: true,
      ),
      // ── from the dissolved Cabling & Connectors category ──
      ToolEntry(
        id: 'ethernet-pinout',
        title: 'Ethernet Pinout',
        description: 'T568A / T568B reference',
        routeName: '/tools/ethernet-pinout',
        isLive: true,
      ),
      ToolEntry(
        id: 'coax-cable',
        title: 'Coax Cable',
        description: 'Coax types: impedance, velocity factor, max frequency',
        routeName: '/tools/coax-cable',
        isLive: true,
      ),
      ToolEntry(
        id: 'ethernet-cable',
        title: 'Ethernet Cable',
        description: 'Cat5e to Cat8: speed, bandwidth, distance, PoE',
        routeName: '/tools/ethernet-cable',
        isLive: true,
      ),
      ToolEntry(
        id: 'fiber-optic',
        title: 'Fiber Optic',
        description: 'OM1 to OM5, OS1/OS2: distance, bandwidth, color code',
        routeName: '/tools/fiber-optic',
        isLive: true,
      ),
      ToolEntry(
        id: 'rf-connectors',
        title: 'RF Connectors',
        description: 'N, SMA, RP-SMA, TNC and more: frequency, impedance',
        routeName: '/tools/rf-connectors',
        isLive: true,
      ),
      // OSI Model — NEW (Quick Reference, last per the LOCKED map order).
      ToolEntry(
        id: 'osi-model',
        title: 'OSI Model',
        description: '7 layers, PDUs, and hardware',
        routeName: '/tools/osi-model',
        isLive: true,
      ),
      ToolEntry(
        id: 'ascii-reference',
        title: 'ASCII / Hex / Binary',
        description: 'ASCII table with hex, octal, binary, and control codes',
        routeName: '/tools/ascii-reference',
        isLive: true,
      ),
      ToolEntry(
        id: 'emoji-reference',
        title: 'Top 30 Emoji',
        description: 'The 30 most-used emoji, names, and common meaning',
        routeName: '/tools/emoji-reference',
        isLive: true,
      ),
    ],
  ),

  // ──────────────────── 5. Command & Capture ────────────────────────
  // NEW category (LOCKED map §5). Its 3 tools are built and live; the category
  // is now active. Tool order follows the LOCKED map.
  ToolCategory(
    id: 'command-capture',
    title: 'Command & Capture',
    summary: 'CLI commands, monitor-mode, Wireshark filters',
    icon: Icons.terminal_outlined,
    tools: <ToolEntry>[
      ToolEntry(
        id: 'cli-commands',
        title: 'Network CLI Commands',
        description: 'Windows + macOS/Linux troubleshooting',
        routeName: '/tools/cli-commands',
        isLive: true,
      ),
      ToolEntry(
        id: 'linux-wlan-commands',
        title: 'Linux / WLAN Commands',
        description: 'Linux CLI + monitor-mode for WLAN',
        routeName: '/tools/linux-wlan-commands',
        isLive: true,
      ),
      ToolEntry(
        id: 'wireshark-80211-filters',
        title: 'Wireshark 802.11 Filters',
        description: 'Display + capture filters for 802.11',
        routeName: '/tools/wireshark-80211-filters',
        isLive: true,
      ),
    ],
  ),

  // ───────────────────────── 6. Checklists ──────────────────────────
  // NEW category (LOCKED map §6). Its 2 tools are built and live (the reusable
  // tappable-checklist screen type renders the Pax-transcribed card content);
  // the category is now active.
  ToolCategory(
    id: 'checklists',
    title: 'Checklists',
    summary: 'Field checklists for install and client testing',
    icon: Icons.checklist_outlined,
    tools: <ToolEntry>[
      ToolEntry(
        id: 'checklist-ap-install',
        title: 'How to NOT Have a Wireless Problem',
        description: 'AP install pre/post-check phases',
        routeName: '/tools/checklist-ap-install',
        isLive: true,
      ),
      ToolEntry(
        id: 'checklist-client-test',
        title: 'Wi-Fi Client Testing Checklist',
        description: '12 client-side connectivity tests',
        routeName: '/tools/checklist-client-test',
        isLive: true,
      ),
    ],
  ),
];
