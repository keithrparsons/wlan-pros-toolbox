// Tool catalog — single source of truth for what appears on the home grid and
// what tools each category exposes.
//
// Category structure: the 4-category reorganization (Keith, 2026-06-01), which
// SUPERSEDES the prior LOCKED 6-category map
// (Deliverables/2026-05-30-quick-reference-additions-triage/
//  LOCKED-6-category-structure.md). The four current categories, in home-grid
// order, are:
//   1. Test Network    — live Wi-Fi/internet diagnostics (NEW; holds the three
//                         pinned tools moved out of Networking Tools:
//                         wifi-vs-internet, wifi-info, net-quality).
//   2. Networking Tools — the remaining networking utilities (lookups, scans,
//                         subnetting, inspectors, etc.).
//   3. Calculators & Tools — id stays 'rf-calculators' (stable; backs routes,
//                         assets, tests); title broadened from 'Calculators'.
//                         Absorbs all former Planning Tools.
//   4. Quick Reference — reference tables + the former Command & Capture and
//                         Checklists tools.
// The three dissolved categories (Planning Tools, Command & Capture,
// Checklists) merged their tools into the survivors per this map; nothing was
// dropped or duplicated. The tappable-checklist screen type
// (checklist_screen.dart) still renders the Pax-transcribed card content via
// the consts in data/checklists.dart — only the home category changed.
//
// Display-title rename pass (prior LOCKED map "Display-title rename pass"):
// titles were reclustered by function (e.g. "DNS Lookup" → "Lookup (DNS)"). The
// catalog `id` strings are STABLE and unchanged — they back 60 icon/graphic
// asset files, every route, and every test. Titles change; ids never.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'tool_keywords.dart';

/// A single tool that can be launched from a category screen.
@immutable
class ToolEntry {
  const ToolEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.routeName,
    this.isLive = false,
    this.keywords = const <String>[],
    this.subgroup,
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

  /// Synonyms, abbreviations, and domain terms a user might TYPE to find this
  /// tool that are NOT already in the title or description (e.g. `fspl` →
  /// 'path loss', 'attenuation'). Powers the global + in-category search
  /// (lib/data/tool_search.dart). Kept out of this file: the vocabulary lives
  /// in lib/data/tool_keywords.dart (one Keith-reviewable map) and is merged in
  /// by [_withKeywords] when the catalog is built, so the search index can be
  /// iterated without touching the catalog structure. Default `const []` keeps
  /// the constructor backward-compatible. Keywords describe what a tool DOES,
  /// never aspirational capability (GL-005).
  final List<String> keywords;

  /// Optional section a tool belongs to WITHIN its category, for the grouped
  /// category screen (Quick Reference, Calculators & Tools). `null` → the tool
  /// falls into a trailing "Other" section. Section ORDER is editorial, set by
  /// [kCategorySubgroupOrder] in lib/data/tool_subgroups.dart — never
  /// alphabetical on this string. Categories without an entry in that map render
  /// flat (no headers), so this field is additive and leaves the pinned
  /// Test Network ordering untouched.
  final String? subgroup;

  /// Returns a copy of this entry with [keywords] replaced. Used only by the
  /// catalog builder to fold in the external vocabulary; not for general use.
  ToolEntry _copyWithKeywords(List<String> keywords) => ToolEntry(
        id: id,
        title: title,
        description: description,
        routeName: routeName,
        isLive: isLive,
        keywords: keywords,
        subgroup: subgroup,
      );
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
    this.iconAsset,
    this.exampleToolTitles = const <String>[],
    this.countLabelOverride,
    this.isNew = false,
  });

  final String id;
  final String title;
  final String summary;
  final IconData icon;
  final List<ToolEntry> tools;

  /// Optional bespoke Tier-2 SVG glyph for the home-grid category tile
  /// (GL-003 §8.6 / §8.6.1). When set, the tile renders this `currentColor`
  /// line SVG (runtime-tinted lime when live, tertiary when placeholder) in
  /// place of the Material [icon]. When `null` (the default for most
  /// categories), the tile falls back to the Material [icon]. The path points
  /// at the already-registered `assets/tool-icons/` dir (e.g.
  /// 'assets/tool-icons/educational-resources.svg').
  final String? iconAsset;

  /// Curated example tool titles shown on the home tile (mockups 01/05), joined
  /// by " · " (e.g. "FSPL · EIRP · Link Budget"). When empty, the tile falls
  /// back to the first few tool titles in display order, so a category always
  /// previews its contents even if no examples are set. Titles must match live
  /// tools — never assert a capability that isn't there (GL-005).
  final List<String> exampleToolTitles;

  /// Optional label shown in place of the numeric count badge on the home tile
  /// (e.g. "~27" for an illustrative count). When `null`, the tile renders the
  /// exact live tool count. Today no category sets this — it exists for the
  /// 6-category future.
  final String? countLabelOverride;

  /// When `true`, the tile shows a lime "NEW" pill instead of a count badge —
  /// for a category genuinely NEW TO USERS post-launch. The capability is built
  /// now (mockups 01/05) but, per Keith (2026-06-03), NOTHING sets it in this
  /// build: the app hasn't gone public, so nothing is "new to a user" yet.
  final bool isNew;

  /// Whether at least one tool in this category is live. Used to grey the
  /// home-grid tile when the entire category is placeholder.
  bool get hasLiveTool => tools.any((t) => t.isLive);
}

/// Category ids gated OFF on the web build. The web flavor is a click-through
/// demo served from a browser; the live network/Wi-Fi diagnostics need OS-level
/// sockets, native link metrics, and platform plugins that do not exist on web,
/// so the two network categories are hidden from navigation on web entirely.
/// This is a `kIsWeb` filter, NOT a deletion — on iOS/macOS/Android the full
/// catalog renders unchanged. Flip the build target back to native and all 86
/// tools reappear with no further change. The 61 web-safe tools (Calculators &
/// Tools = 24, Quick Reference = 37) are pure-Dart math + bundled reference
/// assets and run identically in the browser.
const Set<String> kWebGatedCategoryIds = <String>{
  'test-network', // 5 live Wi-Fi/internet diagnostics
  'networking', // 21 socket/lookup/scan utilities
};

/// Catalog seed — the 4-category reorganization (Keith, 2026-06-01; see file
/// header). The list order IS the home-grid order: Test Network, Networking
/// Tools, Calculators & Tools, Quick Reference. Tool order within each category
/// is presentation-sorted in category_screen.dart (alphabetical, except the
/// pinned three in Test Network).
///
/// This is the FULL, platform-agnostic catalog. UI consumers MUST read
/// [kToolCategories] (below), which applies the web gate. Only touch this raw
/// list when adding/removing a tool from the product itself.
const List<ToolCategory> _kAllToolCategories = <ToolCategory>[
  // ───────────────────────── 1. Test Network ────────────────────────
  // NEW (2026-06-01). The live Wi-Fi/internet diagnostics moved out of
  // Networking Tools, pinned in this order on the category screen (Keith,
  // 2026-06-01): consumer one-tap first, then the deeper pro tools.
  // test-my-connection, net-quality, wifi-info, wifi-vs-internet.
  ToolCategory(
    id: 'test-network',
    title: 'Test Network',
    summary: 'Live Wi-Fi and internet diagnostics',
    icon: Icons.network_check,
    // Home-tile example list (mockup 01/05). Curated headliners; titles match
    // live tools (GL-005). Falls back to first-N tool titles if left empty.
    exampleToolTitles: <String>[
      'Network Quality',
      'Wi-Fi Information',
      'Cellular Information',
    ],
    tools: <ToolEntry>[
      // Wave 4 (Keith, 2026-06-04): the consumer `test-my-connection` and pro
      // `wifi-vs-internet` tools merged into ONE tool reached via the home hero
      // card, so BOTH tiles were removed from this category (full catalog
      // removal — not tiled, not searchable; the home hero is the entry point).
      // The merged screen still lives at /tools/test-my-connection, and
      // /tools/wifi-vs-internet redirects to it (deep links keep working).
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
        id: 'cellular-info',
        title: 'Cellular Information',
        description:
            'Carrier, radio technology, signal bars, country code, and '
            'roaming (iPhone)',
        routeName: '/tools/cellular-info',
        isLive: true,
      ),
    ],
  ),

  // ──────────────────────── 2. Networking Tools ─────────────────────
  // The networking utilities MINUS the three diagnostics moved to Test Network.
  // Display titles reclustered by function per the prior rename pass.
  ToolCategory(
    id: 'networking',
    title: 'Networking Tools',
    summary: 'Interface info, lookups, scans, subnetting',
    icon: Icons.lan_outlined,
    // Mockup 01 showed "Wi-Fi Information" here, but that tool lives in Test
    // Network — examples must name tools that are actually in this category
    // (GL-005). Headliners drawn from real Networking Tools entries.
    exampleToolTitles: <String>[
      'Ping (TCP)',
      'Traceroute (System)',
      'Network Discovery',
      'Ping Sweep',
    ],
    tools: <ToolEntry>[
      ToolEntry(
        id: 'interface-info',
        title: 'Interface Information',
        description: 'Local IPs, gateway, DNS, Wi-Fi link, interface type',
        routeName: '/tools/interface-info',
        isLive: true,
      ),
      ToolEntry(
        id: 'device-info',
        title: 'Device Info',
        description:
            'Device model, total memory, uptime, and cellular IP — the '
            "device's own system facts",
        routeName: '/tools/device-info',
        isLive: true,
      ),
      ToolEntry(
        id: 'dns-lookup',
        title: 'Lookup (DNS)',
        description:
            'Dig-style all-records view + single-type and reverse PTR over '
            'DNS-over-HTTPS',
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
        id: 'ping-plotter',
        title: 'Ping Plotter',
        description:
            'Sustained ping charted over time — live latency trend with '
            'min/avg/max, jitter, and visible dropped probes',
        routeName: '/tools/ping-plotter',
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
        description: 'Certificate fields, validity, SAN, fingerprints over TLS',
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
      // My Current Location (BF5-16): auto-runs the GPS fix on open and shows
      // latitude / longitude / altitude / accuracy directly. Reuses the
      // DeviceLocationService backend behind the Lat / Long calculator so the
      // answers are not buried in a converter people don't find.
      ToolEntry(
        id: 'my-current-location',
        title: 'Current Location',
        description:
            'Your GPS latitude, longitude, altitude, and accuracy — read on '
            'open',
        routeName: '/tools/my-current-location',
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
      ToolEntry(
        id: 'ipv6-subnet',
        title: 'IP Subnetting (IPv6)',
        description: 'IPv6 prefix, expansion, and address counts',
        routeName: '/tools/ipv6-subnet',
        isLive: true,
      ),
    ],
  ),

  // ─────────────────────── 3. Calculators & Tools ───────────────────
  // id stays 'rf-calculators' (stable — backs routes, assets, tests). Title
  // broadened from 'Calculators'. Original RF/GPS/signal calculators plus ALL
  // former Planning Tools (PoE Budget, Throughput, Capacity, PtP) appended.
  ToolCategory(
    id: 'rf-calculators',
    title: 'Calculators & Tools',
    summary: 'RF, GPS, signal, and planning math — FSPL, EIRP, PoE, capacity',
    icon: Icons.calculate_outlined,
    exampleToolTitles: <String>[
      'Free Space Path Loss',
      'EIRP Calculator',
      'Link Budget',
      'dBm / Watt Converter',
    ],
    tools: <ToolEntry>[
      ToolEntry(
        id: 'dbm-watt-converter',
        title: 'dBm / Watt Converter',
        description: 'Live two-way conversion across dBm, Watts, and mW',
        routeName: '/tools/dbm-watt',
        isLive: true,
        subgroup: 'Conversions',
      ),
      ToolEntry(
        id: 'fspl',
        title: 'Free Space Path Loss',
        description: 'FSPL for any frequency and distance',
        routeName: '/tools/fspl',
        isLive: true,
        subgroup: 'RF & Propagation',
      ),
      ToolEntry(
        id: 'eirp',
        title: 'EIRP Calculator',
        description: 'Effective isotropic radiated power',
        routeName: '/tools/eirp',
        isLive: true,
        subgroup: 'Antenna & Coverage',
      ),
      ToolEntry(
        id: 'fresnel',
        title: 'Fresnel Zone',
        description: 'First-zone radius and 60% clearance',
        routeName: '/tools/fresnel',
        isLive: true,
        subgroup: 'RF & Propagation',
      ),
      ToolEntry(
        id: 'cable-loss',
        title: 'Cable Loss',
        description: 'Coax loss by cable type, length, and frequency',
        routeName: '/tools/cable-loss',
        isLive: true,
        subgroup: 'RF & Propagation',
      ),
      ToolEntry(
        id: 'link-budget',
        title: 'Link Budget',
        description: 'Received signal and fade margin end to end',
        routeName: '/tools/link-budget',
        isLive: true,
        subgroup: 'RF & Propagation',
      ),
      ToolEntry(
        id: 'wavelength',
        title: 'Wavelength',
        description: 'Wavelength from frequency, m / cm / ft / in',
        routeName: '/tools/wavelength',
        isLive: true,
        subgroup: 'Antenna & Coverage',
      ),
      ToolEntry(
        id: 'downtilt',
        title: 'Antenna Downtilt',
        description: 'Downtilt angle from height and target distance',
        routeName: '/tools/downtilt',
        isLive: true,
        subgroup: 'Antenna & Coverage',
      ),
      ToolEntry(
        id: 'earth-curvature',
        title: 'Earth Curvature',
        description: 'Earth bulge over a path, with K-factor',
        routeName: '/tools/earth-curvature',
        isLive: true,
        subgroup: 'RF & Propagation',
      ),
      ToolEntry(
        id: 'rain-fade',
        title: 'ITU Rain Fade',
        description: 'Rain attenuation per ITU-R P.838-3 and P.530',
        routeName: '/tools/rain-fade',
        isLive: true,
        subgroup: 'RF & Propagation',
      ),
      ToolEntry(
        id: 'downtilt-coverage',
        title: 'Downtilt Coverage',
        description: 'Coverage edges from height, tilt, and beamwidth',
        routeName: '/tools/downtilt-coverage',
        isLive: true,
        subgroup: 'Antenna & Coverage',
      ),
      // ── from the dissolved GPS Tools category ──
      ToolEntry(
        id: 'metric-conversion',
        title: 'Metric Conversion',
        description: 'm, km, mi, ft, cm, in, nmi',
        routeName: '/tools/metric-conversion',
        isLive: true,
        subgroup: 'Conversions',
      ),
      // ── from the dissolved Infrastructure category ──
      ToolEntry(
        id: 'noise-floor',
        title: 'Noise Floor',
        description: 'Thermal noise floor by channel width and NF',
        routeName: '/tools/noise-floor',
        isLive: true,
        subgroup: 'RF & Propagation',
      ),
      ToolEntry(
        id: 'rf-attenuation',
        title: 'RF Attenuation',
        description: 'Path loss through building materials by band',
        routeName: '/tools/rf-attenuation',
        isLive: true,
        subgroup: 'RF & Propagation',
      ),
      // ── from the dissolved GPS Tools category ──
      ToolEntry(
        id: 'lat-long',
        title: 'Lat / Long Conversion',
        description: 'Convert between DD, DDM, and DMS',
        routeName: '/tools/lat-long',
        isLive: true,
        subgroup: 'Coordinates & GPS',
      ),
      ToolEntry(
        id: 'dist-bearing',
        title: 'Distance and Bearing',
        description: 'Great-circle distance and bearing between two points',
        routeName: '/tools/dist-bearing',
        isLive: true,
        subgroup: 'Coordinates & GPS',
      ),
      ToolEntry(
        id: 'midpoint',
        title: 'Midpoint',
        description: 'Great-circle midpoint between two coordinates',
        routeName: '/tools/midpoint',
        isLive: true,
        subgroup: 'Coordinates & GPS',
      ),
      ToolEntry(
        id: 'final-point',
        title: 'Final Point',
        description: 'Destination from a start point, bearing, and distance',
        routeName: '/tools/final-point',
        isLive: true,
        subgroup: 'Coordinates & GPS',
      ),
      // Hex / ASCII converter + printable-ASCII table — NEW.
      ToolEntry(
        id: 'hex-ascii',
        title: 'Hex / ASCII',
        description: 'Dec/hex/binary converter + ASCII table',
        routeName: '/tools/hex-ascii',
        isLive: true,
        subgroup: 'Conversions',
      ),
      // ── Batch 4a: general-purpose unit converter (sibling of the
      // distance-only metric-conversion). Custom icon is a follow-up; the
      // catalog falls back to the category glyph until an SVG ships. ──
      ToolEntry(
        id: 'unit-converter',
        title: 'Unit Converter',
        description: 'Data rate, storage, length, power, time, and more',
        routeName: '/tools/unit-converter',
        isLive: true,
        subgroup: 'Conversions',
      ),
      // ── Batch 4b/4c: standalone field utilities. New "Utilities &
      // Generators" subgroup (registered in tool_subgroups.dart). Custom icons
      // are a follow-up; both fall back to the category glyph for now. ──
      ToolEntry(
        id: 'qr-generator',
        title: 'QR Code Generator',
        description: 'Encode text or a URL to a scannable QR code',
        routeName: '/tools/qr-generator',
        isLive: true,
        subgroup: 'Utilities & Generators',
      ),
      ToolEntry(
        id: 'dtmf-generator',
        title: 'DTMF Generator',
        description: 'Play Touch-Tone keypad tones (0-9, *, #, A-D)',
        routeName: '/tools/dtmf-generator',
        isLive: true,
        subgroup: 'Utilities & Generators',
      ),
      // ── moved in from the dissolved Planning Tools category (2026-06-01) ──
      ToolEntry(
        id: 'poe-budget',
        title: 'PoE Budget',
        description: 'Switch PoE budget vs connected device draw',
        routeName: '/tools/poe-budget',
        isLive: true,
        subgroup: 'Capacity & Power',
      ),
      ToolEntry(
        id: 'throughput-calc',
        title: 'Throughput Calculator',
        description: 'PHY rate and effective throughput by MCS',
        routeName: '/tools/throughput-calc',
        isLive: true,
        subgroup: 'Capacity & Power',
      ),
      ToolEntry(
        id: 'capacity-planner',
        title: 'Capacity Planner',
        description: 'Why capacity planning needs a pro, not a calculator',
        routeName: '/tools/capacity-planner',
        isLive: true,
        subgroup: 'Capacity & Power',
      ),
      ToolEntry(
        id: 'ptp-link',
        title: 'PtP Link Check',
        description: 'Point-to-point link budget and fade margin',
        routeName: '/tools/ptp-link',
        isLive: true,
        subgroup: 'RF & Propagation',
      ),
    ],
  ),

  // ──────────────────────── 4. Quick Reference ──────────────────────
  // Reference tables (PoE, channels, standards, cabling) + PDF reference cards,
  // plus the former Command & Capture tools (CLI / Wireshark sheets) and the
  // former Checklists tools (tappable + PDF checklists), all merged in here on
  // 2026-06-01. The category screen sorts alphabetically by title, so every
  // tool type interleaves automatically — no manual ordering. The moved tools
  // keep their stable ids/titles/routes/asset paths; only their home category
  // changed.
  ToolCategory(
    id: 'quick-reference',
    title: 'Quick Reference',
    summary: 'Tables, cards, CLI/Wireshark sheets, and checklists',
    icon: Icons.menu_book_outlined,
    exampleToolTitles: <String>[
      'Wi-Fi Channels',
      '802.11 Standards',
      'MCS Index',
    ],
    tools: <ToolEntry>[
      // ── from the dissolved Infrastructure category ──
      ToolEntry(
        id: 'poe-reference',
        title: 'PoE Reference',
        description: 'PoE class, wattage, and budget',
        routeName: '/tools/poe-reference',
        isLive: true,
        subgroup: 'Wi-Fi & RF',
      ),
      // Wi-Fi Channels (the plainer channels reference table) was REMOVED
      // 2026-06-06 (BF6-13): it duplicated the visual "Channel Map". Channel Map
      // is the survivor; the one band Channel Map lacked (sub-1 GHz Wi-Fi HaLow)
      // was folded into Channel Map as its own HaLow reference section.
      ToolEntry(
        id: 'non-wifi-channels',
        title: 'Non-Wi-Fi Wireless Channels',
        description: 'LoRaWAN, 802.15.4, Bluetooth, BLE, Zigbee channel plans',
        routeName: '/tools/non-wifi-channels',
        subgroup: 'Wi-Fi & RF',
        isLive: true,
      ),
      ToolEntry(
        id: '80211-standards',
        title: '802.11 Standards',
        description: 'Generations, bands, rates, widths, Wi-Fi 4 to 7',
        routeName: '/tools/standards',
        isLive: true,
        subgroup: 'Wi-Fi & RF',
      ),
      // How Strong Is Wi-Fi, Really? — v1.1 read-along reference. Puts Wi-Fi RF
      // exposure in perspective against everyday sunlight (one hour of sun ≈ 2.3
      // years inside a ring of ten APs at 4 m), with the FCC/ICNIRP safety-limit
      // context and an honest non-ionizing-mechanism note. No inputs, no runtime
      // math — every figure is a verified, stated number (Pax brief). Bespoke
      // concept graphic ships; bespoke <id>.svg icon is a follow-up.
      ToolEntry(
        id: 'wifi-exposure-perspective',
        title: 'How Strong Is Wi-Fi, Really?',
        description: 'Wi-Fi vs sunlight: RF exposure in perspective',
        routeName: '/tools/wifi-exposure-perspective',
        isLive: true,
        subgroup: 'Wi-Fi & RF',
      ),
      ToolEntry(
        id: 'mcs-index',
        title: 'MCS Index',
        description: 'Modulation and data rates by MCS, width, streams',
        routeName: '/tools/mcs-index',
        isLive: true,
        subgroup: 'Wi-Fi & RF',
      ),
      ToolEntry(
        id: 'signal-thresholds',
        title: 'Signal Thresholds',
        description: 'RSSI and SNR targets by application',
        routeName: '/tools/signal-thresholds',
        isLive: true,
        subgroup: 'Wi-Fi & RF',
      ),
      // ── from the dissolved Wi-Fi Design category ──
      ToolEntry(
        id: 'wpa-security',
        title: 'WPA Security',
        description: 'WPA2 / WPA3 reference matrix',
        routeName: '/tools/wpa-security',
        isLive: true,
        subgroup: 'Wi-Fi & RF',
      ),
      ToolEntry(
        id: 'roaming',
        title: 'Roaming Parameters',
        description: '802.11r/k/v and RSSI/SNR roaming thresholds',
        routeName: '/tools/roaming',
        isLive: true,
        subgroup: 'Wi-Fi & RF',
      ),
      ToolEntry(
        id: 'ap-placement',
        title: 'AP Placement',
        description: 'Mounting, spacing, and cell-overlap guidance',
        routeName: '/tools/ap-placement',
        isLive: true,
        subgroup: 'Wi-Fi & RF',
      ),
      ToolEntry(
        id: 'port-reference',
        title: 'Well-Known Ports',
        description:
            'Search common TCP/UDP ports by number or service name — offline',
        routeName: '/tools/port-reference',
        isLive: true,
        subgroup: 'Protocols',
      ),
      ToolEntry(
        id: 'plmn-id-reference',
        title: 'PLMN ID Reference',
        description:
            'US mobile carrier codes — MCC, MNC, PLMN ID — offline',
        routeName: '/tools/plmn-id-reference',
        isLive: true,
        subgroup: 'Protocols',
      ),
      ToolEntry(
        id: 'reason-codes',
        title: '802.11 Reason Codes',
        description: '802.11 deauth / disassoc reason and status codes',
        routeName: '/tools/reason-codes',
        isLive: true,
        subgroup: 'Protocols',
      ),
      ToolEntry(
        id: 'frame-exchange',
        title: '802.11 Frame Exchange',
        description: '802.11 association and handshake frame sequences',
        routeName: '/tools/frame-exchange',
        isLive: true,
        subgroup: 'Protocols',
      ),
      ToolEntry(
        id: 'http-status-codes',
        title: 'HTTP Status Codes',
        description:
            'HTTP response status codes by class — 1xx to 5xx, offline',
        routeName: '/tools/http-status-codes',
        isLive: true,
        subgroup: 'Protocols',
      ),
      ToolEntry(
        id: 'db-reference',
        title: 'dB Reference',
        description: 'dB to ratio and dBm anchor values',
        routeName: '/tools/db-reference',
        isLive: true,
        subgroup: 'Wi-Fi & RF',
      ),
      ToolEntry(
        id: 'channel-map',
        title: 'Channel Map',
        description: '5 and 6 GHz channel bonding map by width',
        routeName: '/tools/channel-map',
        isLive: true,
        subgroup: 'Wi-Fi & RF',
      ),
      ToolEntry(
        id: 'spectrum',
        title: 'Spectrum Reference',
        description: 'Band allocations, sub-bands, and co-existence',
        routeName: '/tools/spectrum',
        isLive: true,
        subgroup: 'Wi-Fi & RF',
      ),
      // Antenna Fundamentals MOVED 2026-06-06 (BF6-3) from Quick Reference into
      // the Educational Resources category (it is a read-along teaching screen,
      // not a quick-lookup table). Its ToolEntry now lives in that category's
      // `tools` list; the route, id, asset, and help entry are unchanged.
      // ── from the dissolved Cabling & Connectors category ──
      ToolEntry(
        id: 'ethernet-pinout',
        title: 'Ethernet Pinout',
        description: 'T568A / T568B reference',
        routeName: '/tools/ethernet-pinout',
        isLive: true,
        subgroup: 'Cabling & Connectors',
      ),
      ToolEntry(
        id: 'coax-cable',
        title: 'Coax Cable',
        description: 'Coax types: impedance, velocity factor, max frequency',
        routeName: '/tools/coax-cable',
        isLive: true,
        subgroup: 'Cabling & Connectors',
      ),
      ToolEntry(
        id: 'ethernet-cable',
        title: 'Ethernet Cable',
        description: 'Cat5e to Cat8: speed, bandwidth, distance, PoE',
        routeName: '/tools/ethernet-cable',
        isLive: true,
        subgroup: 'Cabling & Connectors',
      ),
      ToolEntry(
        id: 'fiber-optic',
        title: 'Fiber Optic',
        description:
            'OM1 to OM5, OS1/OS2, connectors (LC/SC/MPO), polish (PC/UPC/APC)',
        routeName: '/tools/fiber-optic',
        isLive: true,
        subgroup: 'Cabling & Connectors',
      ),
      ToolEntry(
        id: 'cable-bend-radius',
        title: 'Bend Radius & Pull Tension',
        description: 'Min bend radius and max pull tension, copper and fiber',
        routeName: '/tools/cable-bend-radius',
        isLive: true,
        subgroup: 'Cabling & Connectors',
      ),
      ToolEntry(
        id: 'rack-units',
        title: 'Rack Units',
        description: 'U sizes, EIA-310 holes, the 19-inch reality, rack screws',
        routeName: '/tools/rack-units',
        isLive: true,
        subgroup: 'Cabling & Connectors',
      ),
      ToolEntry(
        id: 'screw-drives',
        title: 'Screw Drives',
        description: 'Common + security driver bits on APs, enclosures, racks',
        routeName: '/tools/screw-drives',
        isLive: true,
        subgroup: 'Cabling & Connectors',
      ),
      // Optical Transceivers — searchable, offline reference of 35 optical
      // Ethernet variants (1G–400G) grouped by speed tier (lead tiers
      // 10G/25G/100G first), plus the SFP→OSFP form-factor ladder. IEEE vs
      // vendor (ZR/ZX/EX) variants are distinguished and vendor reach is hedged
      // (loss-budget dependent), never stated as an IEEE guarantee. No bespoke
      // <id>.svg yet — bespoke icon is a follow-up; ToolRow shows the fallback.
      ToolEntry(
        id: 'optical-transceivers',
        title: 'Optical Transceivers',
        description:
            'SFP to OSFP optics by speed tier: reach, fiber, wavelength — offline',
        routeName: '/tools/optical-transceivers',
        isLive: true,
        subgroup: 'Cabling & Connectors',
      ),
      // RF Connectors + Antenna Connectors MERGED 2026-06-06 (BF6-18) into the
      // single "Antenna Connectors" tool below (Keith: "we only need one"). The
      // former `rf-connectors` coaxial-only card's unique connector rows were
      // folded into the antenna-connectors dataset; its route/help/keywords were
      // removed.
      // Antenna Connectors — searchable, grouped connector reference for Wi-Fi
      // antenna + RF systems (full name, RP variant, coupling, impedance,
      // frequency, mating, notes) + vendor trends, size order, and the connectors
      // a Wi-Fi engineer meets. Offline bundled JSON. Now the single connector
      // reference after the RF Connectors merge.
      ToolEntry(
        id: 'antenna-connectors',
        title: 'Antenna Connectors',
        description:
            'N, SMA, RP-SMA, TNC, RP-TNC, DART, U.FL: use, frequency, '
            'impedance, coupling, mating',
        routeName: '/tools/antenna-connectors',
        isLive: true,
        subgroup: 'Cabling & Connectors',
      ),
      // RJ Connectors — registered-jack form factors (RJ11/14/25/45/48 etc.):
      // positions, conductors, typical use. Cross-links to Ethernet Pinout for
      // T568A/B wiring rather than duplicating it. Batch 5.
      ToolEntry(
        id: 'rj-connectors',
        title: 'RJ Connectors',
        description: 'RJ11, RJ45 (8P8C), RJ48: positions, conductors, use',
        routeName: '/tools/rj-connectors',
        isLive: true,
        subgroup: 'Cabling & Connectors',
      ),
      // OSI Model — NEW (Quick Reference, last per the LOCKED map order).
      ToolEntry(
        id: 'osi-model',
        title: 'OSI Model',
        description: '7 layers, PDUs, and hardware',
        routeName: '/tools/osi-model',
        isLive: true,
        subgroup: 'Protocols',
      ),
      // Top-Level Domains — curated DNS TLD reference grouped by registry type
      // (gTLD / ccTLD / sponsored / infrastructure / newer gTLDs). Batch 5.
      ToolEntry(
        id: 'top-level-domains',
        title: 'Top-Level Domains',
        description: 'gTLD, ccTLD, sponsored and infrastructure domains',
        routeName: '/tools/top-level-domains',
        isLive: true,
        subgroup: 'Protocols',
      ),
      ToolEntry(
        id: 'ascii-reference',
        title: 'ASCII / Hex / Binary',
        description: 'ASCII table with hex, octal, binary, and control codes',
        routeName: '/tools/ascii-reference',
        isLive: true,
        subgroup: 'Encoding',
      ),
      ToolEntry(
        id: 'emoji-reference',
        title: 'Top 30 Emoji',
        description: 'The 30 most-used emoji, names, and common meaning',
        routeName: '/tools/emoji-reference',
        isLive: true,
        subgroup: 'Encoding',
      ),
      // Wi-Fi Glossary — searchable, grouped plain-language definitions
      // (offline bundled JSON). Carries its bespoke Tier-2 SVG icon
      // (assets/tool-icons/wifi-glossary.svg), resolved by the <id>.svg
      // convention in ToolAssets — no per-tool wiring needed.
      ToolEntry(
        id: 'wifi-glossary',
        title: 'Wi-Fi Glossary',
        description: 'Plain-language definitions of 92 Wi-Fi terms',
        routeName: '/tools/wifi-glossary',
        subgroup: 'Wi-Fi & RF',
        isLive: true,
      ),
      // Wi-Fi Authentication Glossary — sibling of the Wi-Fi Glossary,
      // searchable/grouped/offline, reusing WifiGlossaryScreen + GlossaryService
      // pointed at assets/data/wifi_auth_glossary.json. No bespoke <id>.svg yet,
      // so ToolRow shows the lime-bolt fallback (bespoke icon = follow-up).
      ToolEntry(
        id: 'wifi-auth-glossary',
        title: 'Wi-Fi Authentication Glossary',
        description:
            'Plain-language definitions of 58 Wi-Fi authentication terms',
        routeName: '/tools/wifi-auth-glossary',
        subgroup: 'Wi-Fi & RF',
        isLive: true,
      ),
      // Wi-Fi Tools Comparison — v1.1 beta. A vendor-neutral capability-and-cost
      // reference of professional Wi-Fi survey/design/spectrum/troubleshooting
      // toolkits, grouped by activity (offline bundled JSON). TCO + up-front
      // figures are MODELED ESTIMATES shown with a date-stamp + modeled-estimate
      // + beta-review disclaimer. No vendor logos/photos (permission pending).
      // Not a ranking; alphabetical by vendor. Tamosoft excluded (Keith
      // 2026-06-05). No bespoke <id>.svg yet, so ToolRow shows the lime-bolt
      // fallback (bespoke icon = follow-up).
      ToolEntry(
        id: 'wifi-tools-comparison',
        title: 'Wi-Fi Tools Comparison',
        description:
            'Survey, design, spectrum and troubleshooting toolkits compared by capability and cost — offline',
        routeName: '/tools/wifi-tools-comparison',
        subgroup: 'Wi-Fi & RF',
        isLive: true,
      ),
      // NOTE: the 10 laminated PDF reference cards (6 reference cards + 4
      // checklist cards) MOVED to the Educational Resources category on
      // 2026-06-04 (Keith). They render at the top of EducationalResourcesScreen
      // as a "Reference Cards" section. The two INTERACTIVE checklists
      // (checklist-ap-install, checklist-client-test) stayed here in the
      // "Checklists" section and did NOT move. `mcs-index-card` (a card) is
      // deliberately distinct from the existing `mcs-index` table id, which
      // stays in Quick Reference.
      // ── Reference batch (2026-06-08): 14 new reference screens across three
      // NEW Quick Reference sub-categories (Addressing & Subnetting, Models &
      // Standards, Time & Formats) plus additions to Protocols, Wi-Fi & RF, and
      // Encoding. All read-only, offline, pure-Dart const datasets. ──
      // Addressing & Subnetting.
      ToolEntry(
        id: 'ip-address-reference',
        title: 'IP Address Reference',
        description:
            'IANA/IETF special-use IPv4 and IPv6 address blocks, plus IPv6 '
            'notation rules',
        routeName: '/tools/ip-address-reference',
        isLive: true,
        subgroup: 'Addressing & Subnetting',
      ),
      ToolEntry(
        id: 'cidr-table',
        title: 'Subnetting / CIDR Table',
        description:
            '/0 to /32: prefix, subnet mask, total addresses, usable hosts, '
            'wildcard mask',
        routeName: '/tools/cidr-table',
        isLive: true,
        subgroup: 'Addressing & Subnetting',
      ),
      ToolEntry(
        id: 'naming-conventions',
        title: 'Naming & Addressing Conventions',
        description:
            'Hostname/DNS-label rules, MAC EUI-48/EUI-64, the U/L and I/G bits, '
            'and OUI/CID',
        routeName: '/tools/naming-conventions',
        isLive: true,
        subgroup: 'Addressing & Subnetting',
      ),
      // Protocols additions.
      ToolEntry(
        id: 'dns-record-types',
        title: 'DNS Record Types',
        description:
            'A, AAAA, CNAME, MX, TXT, SRV, and more — purpose and format',
        routeName: '/tools/dns-record-types',
        isLive: true,
        subgroup: 'Protocols',
      ),
      ToolEntry(
        id: 'dhcp-options',
        title: 'DHCP Options',
        description: 'Common DHCPv4 option codes, names, and typical use',
        routeName: '/tools/dhcp-options',
        isLive: true,
        subgroup: 'Protocols',
      ),
      ToolEntry(
        id: 'http-methods',
        title: 'HTTP Methods & Headers',
        description: 'HTTP request methods plus common request/response headers',
        routeName: '/tools/http-methods',
        isLive: true,
        subgroup: 'Protocols',
      ),
      ToolEntry(
        id: 'dscp-qos',
        title: 'DSCP / QoS Markings',
        description:
            'DSCP code points, names, decimal/binary values, and the WMM '
            'access-category mapping',
        routeName: '/tools/dscp-qos',
        isLive: true,
        subgroup: 'Protocols',
      ),
      // Models & Standards.
      ToolEntry(
        id: 'eap-types',
        title: '802.1X / EAP Types',
        description:
            'EAP methods for 802.1X: credentials, tunneling, and where each '
            'fits',
        routeName: '/tools/eap-types',
        isLive: true,
        subgroup: 'Models & Standards',
      ),
      ToolEntry(
        id: 'wifi-feature-matrix',
        title: '802.11 Feature Matrix',
        description:
            '802.11 amendments by band, modulation, channel width, and key '
            'features',
        routeName: '/tools/wifi-feature-matrix',
        isLive: true,
        subgroup: 'Models & Standards',
      ),
      // Wi-Fi & RF addition.
      ToolEntry(
        id: 'regulatory-domains',
        title: 'Regulatory Domains',
        description:
            'Per-region Wi-Fi band availability, power limits, and DFS rules',
        routeName: '/tools/regulatory-domains',
        isLive: true,
        subgroup: 'Wi-Fi & RF',
      ),
      ToolEntry(
        id: 'wifi-standards-bodies',
        title: 'Wi-Fi Standards Bodies',
        description:
            'Who defines, certifies, and coordinates Wi-Fi: IEEE, Wi-Fi Alliance, ITU-R, and more',
        routeName: '/tools/wifi-standards-bodies',
        isLive: true,
        subgroup: 'Wi-Fi & RF',
      ),
      // Time & Formats.
      ToolEntry(
        id: 'datetime-standards',
        title: 'Date / Time Standards',
        description:
            'ISO 8601, RFC 3339, Unix time, time zones, and common format '
            'tokens',
        routeName: '/tools/datetime-standards',
        isLive: true,
        subgroup: 'Time & Formats',
      ),
      ToolEntry(
        id: 'data-units',
        title: 'Data Units',
        description:
            'Bit/byte units, SI vs binary (kB vs KiB) prefixes, and the data-'
            'rate ladder',
        routeName: '/tools/data-units',
        isLive: true,
        subgroup: 'Time & Formats',
      ),
      // Encoding additions.
      ToolEntry(
        id: 'hash-lengths',
        title: 'Hash Lengths',
        description:
            'Common hash and digest algorithms by output length and typical '
            'use',
        routeName: '/tools/hash-lengths',
        isLive: true,
        subgroup: 'Encoding',
      ),
      ToolEntry(
        id: 'regex-cheatsheet',
        title: 'Regex Cheatsheet',
        description:
            'Regular-expression syntax: anchors, classes, quantifiers, groups, '
            'and lookarounds',
        routeName: '/tools/regex-cheatsheet',
        isLive: true,
        subgroup: 'Encoding',
      ),
      ToolEntry(
        id: 'markdown-cheatsheet',
        title: 'Markdown Cheatsheet',
        description:
            'CommonMark + GitHub Flavored Markdown: what you type and what it renders as',
        routeName: '/tools/markdown-cheatsheet',
        isLive: true,
        subgroup: 'Encoding',
      ),
      // ── moved in from the dissolved Command & Capture category
      // (2026-06-01): CLI / monitor-mode / Wireshark reference sheets ──
      ToolEntry(
        id: 'cli-commands',
        title: 'Network CLI Commands',
        description: 'Windows + macOS/Linux troubleshooting',
        routeName: '/tools/cli-commands',
        isLive: true,
        subgroup: 'CLI & Capture',
      ),
      ToolEntry(
        id: 'linux-wlan-commands',
        title: 'Linux / WLAN Commands',
        description: 'Linux CLI + monitor-mode for WLAN',
        routeName: '/tools/linux-wlan-commands',
        isLive: true,
        subgroup: 'CLI & Capture',
      ),
      ToolEntry(
        id: 'wireshark-80211-filters',
        title: 'Wireshark 802.11 Filters',
        description: 'Display + capture filters for 802.11',
        routeName: '/tools/wireshark-80211-filters',
        isLive: true,
        subgroup: 'CLI & Capture',
      ),
      // ── moved in from the dissolved Checklists category (2026-06-01):
      // tappable-checklist screens + PDF reference-card checklists ──
      // The two INTERACTIVE (non-PDF) checklists — these stay in "Checklists".
      ToolEntry(
        id: 'checklist-ap-install',
        title: 'How to NOT Have a Wireless Problem',
        description: 'AP install pre/post-check phases',
        routeName: '/tools/checklist-ap-install',
        isLive: true,
        subgroup: 'Checklists',
      ),
      ToolEntry(
        id: 'checklist-client-test',
        title: 'Wi-Fi Client Testing Checklist',
        description: '12 client-side connectivity tests',
        routeName: '/tools/checklist-client-test',
        isLive: true,
        subgroup: 'Checklists',
      ),
      // The 4 checklist PDF cards moved to Educational Resources on 2026-06-04
      // (see the NOTE above); only the two interactive checklists remain here.
      // ── Guides (2026-06-05): step-by-step how-tos that bundle a downloadable
      // companion file. Distinct from the tappable checklists above (which track
      // session state): a Guide is a read-along walkthrough with a download.
      ToolEntry(
        id: 'dual-orb-wlanpi',
        title: 'Dual Orbs on WLAN Pi',
        description:
            'Turn a WLAN Pi R4/M4+ into two Orb sensors (Ethernet + Wi-Fi)',
        routeName: '/tools/dual-orb-wlanpi',
        isLive: true,
        subgroup: 'Guides',
      ),
      ToolEntry(
        id: 'freeradius-wlanpi',
        title: 'FreeRADIUS on WLAN Pi',
        description: 'Stand up a lab RADIUS server for 802.1X (guide + script)',
        routeName: '/tools/freeradius-wlanpi',
        isLive: true,
        subgroup: 'Guides',
        keywords: <String>[
          'radius',
          '802.1X',
          'dot1x',
          'peap',
          'mschapv2',
          'wpa-enterprise',
          'wpa2-enterprise',
          'authentication',
          'eap',
          'wlan pi',
          'wlanpi',
          'raspberry pi',
          'aaa',
          'radtest',
          'ferney munoz',
        ],
      ),
      // ── Power & Cooling (subgroup) ──
      // Demoted from a standalone top-level category to a Quick Reference
      // subgroup on 2026-06-08 (Keith): power phasing/voltages, the Ohm's-Law
      // power wheel, thermal conversions, and the IEC/NEMA/international
      // connector references all belong under References, not as a peer
      // category. Routes, ids, assets, and help entries are unchanged from
      // their standalone life. Subgroup ordering lives in tool_subgroups.dart;
      // it sits after 'Cabling & Connectors' (connectors → power feeds).
      ToolEntry(
        id: 'power-phasing',
        title: 'Power Phasing',
        description:
            'Single-phase 120V, split-phase 120/240V, and three-phase wye '
            '208V — and the 208-vs-240 distinction installers confuse',
        routeName: '/tools/power-phasing',
        isLive: true,
        subgroup: 'Power & Cooling',
      ),
      ToolEntry(
        id: 'ohms-law',
        title: "Ohm's Law & Power Wheel",
        description:
            'The V / I / R / P relationships, the 12-segment power wheel, and '
            'single-phase vs three-phase power with the power-factor caveat',
        routeName: '/tools/ohms-law',
        isLive: true,
        subgroup: 'Power & Cooling',
      ),
      ToolEntry(
        id: 'cooling-thermal',
        title: 'Cooling & Thermal',
        description:
            'BTU/hr, watts, and tons of cooling conversions, plus the airflow '
            'and heat-load references for sizing rack and closet cooling',
        routeName: '/tools/cooling-thermal',
        isLive: true,
        subgroup: 'Power & Cooling',
      ),
      ToolEntry(
        id: 'iec-connectors',
        title: 'IEC Power Connectors',
        description:
            'IEC 60320 appliance couplers (C13/C14, C15/C16, C19/C20) and IEC '
            '60309 pin-and-sleeve connectors, with current ratings and keying',
        routeName: '/tools/iec-connectors',
        isLive: true,
        subgroup: 'Power & Cooling',
      ),
      ToolEntry(
        id: 'nema-connectors',
        title: 'NEMA Connectors',
        description:
            'NEMA straight-blade and locking plug/receptacle configurations '
            'with voltage, current, and pole/wire counts',
        routeName: '/tools/nema-connectors',
        isLive: true,
        subgroup: 'Power & Cooling',
      ),
      ToolEntry(
        id: 'international-plugs',
        title: 'International Power Plugs',
        description:
            'Plug types A through N by region, with nominal voltage and '
            'frequency, so you know what mains to expect on site',
        routeName: '/tools/international-plugs',
        isLive: true,
        subgroup: 'Power & Cooling',
      ),
    ],
  ),

  // ───────────────────── 5. Educational Resources ───────────────────
  // A data-driven directory of Wi-Fi learning resources (32 independent-author
  // entries: community tools, conference/talk archives, YouTube channels,
  // podcasts, independent blogs, training/certification — megavendor/product
  // docs excluded per Keith), loaded from a bundled JSON asset and grouped by
  // topic. ONE tile for the whole directory — NOT one tile per resource. The
  // tile is intercepted in HomeScreen._openCategory: instead of pushing the
  // generic CategoryScreen (which lists ToolEntry routes), it pushes the
  // dedicated EducationalResourcesScreen, because the resources are external
  // links with rich detail, not in-app tool routes. The single placeholder
  // ToolEntry below exists only so the tile reads as live and the category is
  // non-empty; it never renders as generic ToolEntry rows. The 10 laminated PDF
  // reference cards (moved here from Quick Reference 2026-06-04) plus the
  // Antenna Fundamentals teaching screen (moved here 2026-06-06, BF6-3) ARE its
  // `tools` list: EducationalResourcesScreen reads them and renders an in-app
  // references section at the top, above the 37 online resources. No `subgroup`
  // — this is not a subgroup-ordered category.
  //
  // Tile count: the home badge would show only the live tool count (the 11 in-
  // app references). The true total is 11 + 37 online resources = 48, so
  // [countLabelOverride] pins '48' (guard test in
  // test/screens/tools/educational/ asserts it equals card-count + the bundled
  // JSON `_meta.count` so the number cannot silently drift).
  ToolCategory(
    id: 'educational-resources',
    title: 'Educational Resources',
    summary: 'Curated places to learn Wi-Fi: blogs, talks, channels, podcasts',
    icon: Icons.school_outlined,
    // Bespoke Tier-2 mortarboard glyph (GL-003 §8.6.1). Falls back to the
    // Material [icon] above if the asset is ever absent from the bundle.
    iconAsset: 'assets/tool-icons/educational-resources.svg',
    exampleToolTitles: <String>['Reference Cards', 'Blogs', 'Podcasts'],
    // 49 = 11 in-app references (10 PDF cards + Antenna Fundamentals, moved here
    // 2026-06-06 BF6-3) + 38 online resources (WiFi Training added 2026-06-07
    // under Training Providers; MackenzieWiFi re-added 2026-06-08, site back up
    // over http). The count-guard test recomputes this from the catalog tool
    // count + the bundled JSON `_meta.count`.
    countLabelOverride: '49',
    tools: <ToolEntry>[
      // The 6 PDF reference cards.
      ToolEntry(
        id: 'bubble-diagram',
        title: 'WLAN Pros Bubble Diagram',
        description: 'Wi-Fi design decision bubble diagram',
        routeName: '/tools/bubble-diagram',
        isLive: true,
      ),
      ToolEntry(
        id: 'troubleshooting-causes',
        title: 'Wireless LAN Troubleshooting Causes',
        description: 'Common causes to check when troubleshooting',
        routeName: '/tools/troubleshooting-causes',
        isLive: true,
      ),
      ToolEntry(
        id: 'channel-allocations-24ghz',
        title: '2.4 GHz Channel Allocations',
        description: '2.4 GHz channel layout and allocations',
        routeName: '/tools/channel-allocations-24ghz',
        isLive: true,
      ),
      ToolEntry(
        id: 'channel-allocations-5ghz',
        title: '5 GHz Channel Allocations',
        description: '5 GHz channel layout and allocations',
        routeName: '/tools/channel-allocations-5ghz',
        isLive: true,
      ),
      ToolEntry(
        id: 'channel-allocations-6ghz',
        title: '6 GHz Channel Allocations',
        description: '6 GHz channel layout and allocations',
        routeName: '/tools/channel-allocations-6ghz',
        isLive: true,
      ),
      ToolEntry(
        id: 'mcs-index-card',
        title: 'Modulation and Coding Schemes (MCS Index)',
        description: 'MCS index, rates, and modulation',
        routeName: '/tools/mcs-index-card',
        isLive: true,
      ),
      // The 4 checklist PDF cards.
      ToolEntry(
        id: 'top-20-checklist',
        title: 'Top 20 Wi-Fi Checklist',
        description: 'The Top 20 Wi-Fi design checklist',
        routeName: '/tools/top-20-checklist',
        isLive: true,
      ),
      ToolEntry(
        id: 'extended-checklist',
        title: 'Extended Wi-Fi Checklist',
        description: 'Extended design checklist items',
        routeName: '/tools/extended-checklist',
        isLive: true,
      ),
      ToolEntry(
        id: 'extended-checklist-nonadvertised',
        title: 'Extended Checklist (Non-Advertised Items)',
        description: 'Extended checklist, non-advertised items',
        routeName: '/tools/extended-checklist-nonadvertised',
        isLive: true,
      ),
      ToolEntry(
        id: 'connection-checklist',
        title: 'Wi-Fi Connection Checklist',
        description: 'Client connection sequence checklist',
        routeName: '/tools/connection-checklist',
        isLive: true,
      ),
      // Antenna Fundamentals — MOVED here 2026-06-06 (BF6-3) from Quick
      // Reference. A read-along teaching screen (not a PDF card), so it renders
      // in the in-app references section of the Educational Resources directory.
      // Route, id, asset, and help entry are unchanged from its Quick Reference
      // life.
      ToolEntry(
        id: 'antenna-fundamentals',
        title: 'Antenna Fundamentals',
        description:
            'Gain, beamwidth, polarization, downtilt, and reading a radiation '
            'pattern — with diagrams',
        routeName: '/tools/antenna-fundamentals',
        isLive: true,
      ),
    ],
  ),
];

/// Route to the Educational Resources directory screen. Declared here (not only
/// in AppRouter) so the catalog entry and the home-tile intercept share one
/// constant. Mirrors the `/tools/...` route namespace of the other tools.
const String kEducationalResourcesRoute = '/tools/educational-resources';

/// The catalog the UI renders. On native targets this is the full
/// [_kAllToolCategories]; on web it drops the [kWebGatedCategoryIds]
/// categories (the network diagnostics that have no browser implementation),
/// leaving only the 61 web-safe Calculators & Tools and Quick Reference tools.
/// Every catalog consumer (home grid, category screen) reads this list, so
/// gating here is sufficient to keep gated tools out of all navigation and
/// search surfaces on web. Reversible: it's a `kIsWeb` filter, not a deletion.
final List<ToolCategory> kToolCategories = _buildCatalog();

/// Builds the UI catalog: folds the external search vocabulary
/// ([kToolKeywords], lib/data/tool_keywords.dart) into each [ToolEntry], then
/// applies the web gate. Keeping the vocabulary in its own file lets Keith
/// iterate the search terms without editing the catalog structure, and keeps the
/// catalog the single source of truth for everything else.
List<ToolCategory> _buildCatalog() {
  final List<ToolCategory> source = kIsWeb
      ? _kAllToolCategories
            .where((ToolCategory c) => !kWebGatedCategoryIds.contains(c.id))
            .toList(growable: false)
      : _kAllToolCategories;

  return source
      .map(
        (ToolCategory c) => ToolCategory(
          id: c.id,
          title: c.title,
          summary: c.summary,
          icon: c.icon,
          iconAsset: c.iconAsset,
          exampleToolTitles: c.exampleToolTitles,
          countLabelOverride: c.countLabelOverride,
          isNew: c.isNew,
          tools: c.tools
              .map(
                (ToolEntry t) => t._copyWithKeywords(
                  kToolKeywords[t.id] ?? const <String>[],
                ),
              )
              .toList(growable: false),
        ),
      )
      .toList(growable: false);
}
