// Tool catalog — single source of truth for what appears on the home grid and
// what tools each category exposes.
//
// Category list sourced from Deliverables/2026-05-28-active-network-utility-
// feasibility/brief.md §3.1–§3.8. For MVP, only the dBm/Watt Converter is
// live; the rest are "Coming soon" placeholders that still route to a
// (greyed) category screen.

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
  /// telemetry later.
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

/// One of the eight home-grid categories.
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

/// Catalog seed — keep this list aligned with the feasibility brief §3.
const List<ToolCategory> kToolCategories = <ToolCategory>[
  ToolCategory(
    id: 'rf-calculators',
    title: 'RF Calculators',
    summary: 'FSPL, dBm/Watt, Fresnel, EIRP, link budget',
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
        routeName: '',
      ),
      ToolEntry(
        id: 'eirp',
        title: 'EIRP Calculator',
        description: 'Effective isotropic radiated power',
        routeName: '',
      ),
      ToolEntry(
        id: 'fresnel',
        title: 'Fresnel Zone',
        description: 'First-zone radius and 60% clearance',
        routeName: '',
      ),
    ],
  ),
  ToolCategory(
    id: 'gps-tools',
    title: 'GPS Tools',
    summary: 'Coordinate conversions, distance, bearing',
    icon: Icons.explore_outlined,
    tools: <ToolEntry>[
      ToolEntry(
        id: 'metric-conversion',
        title: 'Metric Conversion',
        description: 'm, km, mi, ft, cm, in, nmi',
        routeName: '',
      ),
    ],
  ),
  ToolCategory(
    id: 'networking',
    title: 'Networking',
    summary: 'IP subnetting, IPv6, MAC lookup',
    icon: Icons.lan_outlined,
    tools: <ToolEntry>[
      ToolEntry(
        id: 'ipv4-subnet',
        title: 'IP Subnetting (IPv4)',
        description: 'Subnet math and CIDR breakdown',
        routeName: '',
      ),
    ],
  ),
  ToolCategory(
    id: 'infrastructure',
    title: 'Infrastructure',
    summary: 'PoE, power, switch capacity',
    icon: Icons.electrical_services_outlined,
    tools: <ToolEntry>[
      ToolEntry(
        id: 'poe-reference',
        title: 'PoE Reference',
        description: 'PoE class, wattage, and budget',
        routeName: '',
      ),
    ],
  ),
  ToolCategory(
    id: 'planning-tools',
    title: 'Planning Tools',
    summary: 'Throughput, capacity, roaming',
    icon: Icons.architecture_outlined,
    tools: <ToolEntry>[
      ToolEntry(
        id: 'throughput-calc',
        title: 'Throughput Calculator',
        description: 'Estimated airtime and effective rate',
        routeName: '',
      ),
    ],
  ),
  ToolCategory(
    id: 'cabling',
    title: 'Cabling and Connectors',
    summary: 'Ethernet pinouts, connector lookup',
    icon: Icons.cable_outlined,
    tools: <ToolEntry>[
      ToolEntry(
        id: 'ethernet-pinout',
        title: 'Ethernet Pinout',
        description: 'T568A / T568B reference',
        routeName: '',
      ),
    ],
  ),
  ToolCategory(
    id: 'wifi-design',
    title: 'Wi-Fi Design',
    summary: 'WPA, channels, regulatory',
    icon: Icons.wifi,
    tools: <ToolEntry>[
      ToolEntry(
        id: 'wpa-security',
        title: 'WPA Security',
        description: 'WPA2 / WPA3 reference matrix',
        routeName: '',
      ),
    ],
  ),
  ToolCategory(
    id: 'quick-reference',
    title: 'Quick Reference',
    summary: 'Ports, standards, lookup tables',
    icon: Icons.menu_book_outlined,
    tools: <ToolEntry>[
      ToolEntry(
        id: 'well-known-ports',
        title: 'Well-Known Ports',
        description: 'TCP / UDP common ports lookup',
        routeName: '',
      ),
    ],
  ),
];
