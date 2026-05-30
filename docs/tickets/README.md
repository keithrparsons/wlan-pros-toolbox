# Implementation Tickets — Network Toolbox + NetScanTools Pro Feature Gap

Sources:
- `myPKA/Deliverables/2026-05-29-network-toolbox-comparison/brief.md`
  (Pax: Network Toolbox vs WLAN Pros Toolbox) — TICKET-001..005.
- `myPKA/Deliverables/2026-05-29-netscantools-pro-feature-map/brief.md`
  (Pax: NetScanTools Pro vs WLAN Pros Toolbox) — TICKET-006..011.

The first five tickets close the "show me what's on this network" gap a Wi-Fi pro
reaches for first. Tickets 006-011 are the NetScanTools Pro features Keith approved
for the commit list (2026-05-29). Note overlap: the NetScanTools review also surfaced
the **MAC/OUI lookup** and **IPv4 subnet calculator** as wins — those were already
captured as TICKET-002 and TICKET-003, so they are not duplicated.

Keith's directive on 006-011: build all of them; remove any that prove too hard or
impossible (the SNMP item in particular is library-gated by an explicit spike). Never
ship a simulated/empty tool in place of one that cannot be made to work.

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

## NetScanTools Pro tranche (TICKET-006..011, approved 2026-05-29)

Suggested order: do the Easy reference/DNS work first, then spike the UDP pair before
committing it, then the Moderate UI/diagnostic items.

| # | Ticket | Difficulty | Notes |
|---|--------|-----------|-------|
| 6 | [TICKET-006 — DNS advanced records](TICKET-006-dns-advanced-records.md) | Easy | Extends shipped DoH resolver (SPF/SRV/CAA/PTR) |
| 7 | [TICKET-007 — Well-known ports reference](TICKET-007-well-known-ports-reference.md) | Easy | Offline asset + search; pairs with Port Scan |
| 8 | [TICKET-009 — NTP query](TICKET-009-ntp-query.md) | Moderate | UDP/123, hand-rollable; relevant to 802.1X clock skew |
| 9 | [TICKET-008 — SNMP get / walk](TICKET-008-snmp-get-walk.md) | Moderate — **spike-gated** | UDP/161; gated on a usable Dart SNMP/BER package |
| 10 | [TICKET-010 — SMTP test + RBL check](TICKET-010-smtp-test-rbl-check.md) | Moderate | TCP banner/EHLO + DNS blocklist; reuses Port Scan + DoH |
| 11 | [TICKET-011 — Ping trend chart](TICKET-011-ping-trend-chart.md) | Moderate | Charts existing ping data; needs one chart package |

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
