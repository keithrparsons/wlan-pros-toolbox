# Implementation Tickets — Network Toolbox "Do-First" Shortlist

Source: `myPKA/Deliverables/2026-05-29-network-toolbox-comparison/brief.md`
(Pax competitor gap analysis, Network Toolbox vs WLAN Pros Toolbox).

These five tickets are the high-value / low-to-moderate-difficulty features that
Network Toolbox ships and we do not. They close the "show me what's on this
network" gap that a Wi-Fi pro reaches for first.

## Recommended build order

Order is sequenced by dependency and effort, not by ticket number alone. The OUI
lookup (TICKET-002) feeds the LAN scanner's vendor column, so build it first.

| # | Ticket | Difficulty | Why this slot |
|---|--------|-----------|---------------|
| 1 | [TICKET-002 — MAC OUI vendor lookup](TICKET-002-mac-oui-vendor-lookup.md) | Easy | Standalone value + feeds the scanner |
| 2 | [TICKET-003 — IPv4 subnet calculator](TICKET-003-ipv4-subnet-calculator.md) | Easy | Pure-Dart, already a catalog placeholder |
| 3 | [TICKET-005 — Packet sender (TCP/UDP)](TICKET-005-packet-sender-tcp-udp.md) | Easy | Pure-Dart sockets, no native channel |
| 4 | [TICKET-001 — LAN / network scanner](TICKET-001-lan-network-scanner.md) | Moderate | Reuses Ping Sweep + ARP/NDP + OUI |
| 5 | [TICKET-004 — Bonjour / mDNS discovery](TICKET-004-bonjour-mdns-discovery.md) | Moderate | Native channel + iOS Local Network permission |

## Codebase conventions every ticket follows

- **Logic** lives in `lib/services/network/<name>_service.dart` (no Flutter imports).
- **UI** lives in `lib/screens/tools/network/<name>_screen.dart`.
- **Registration** is one `ToolEntry` in `lib/data/tool_catalog.dart` with a stable
  kebab-case `id`, plus a route in `lib/router/app_router.dart`.
- **Shared widgets:** reuse `error_card.dart`, `value_row.dart`, `labeled_field.dart`,
  and `network_unavailable_view.dart` (the honest-unavailable pattern) rather than
  re-rolling UI.
- **Tests** go in `test/`, mirroring the service path. Keep the suite green
  (currently 235 tests).
- **Accessibility:** screen-reader labels + focus-ring per the §8.3 pass already in
  the tree (commit 3483822). New screens match it.

## Out of scope (deliberately skipped, per the brief)

SSH/Telnet/SMB/FTP reach tools (hard, large security surface), and the entire
security-research surface (Shodan, Dorks, exploit/password probing) — off-brand for
a vendor-neutral WLAN audience and an App Store review liability. A true nearby-Wi-Fi
SSID/RSSI scanner is iOS-structurally-blocked (NEHotspotHelper) and stays out.
