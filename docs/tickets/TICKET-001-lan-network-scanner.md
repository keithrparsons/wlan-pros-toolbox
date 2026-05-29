# TICKET-001 — LAN / Network Scanner

**Difficulty:** Moderate
**Build order:** 4 of 5 (after TICKET-002 OUI, which supplies the vendor column)
**iOS blocker:** Partial — degrade gracefully (see iOS notes)
**Source:** brief.md §"Recommended additions" #1 (the headline gap)

## What it is

Sweep the local subnet and list live hosts: IP, hostname (where resolvable), MAC, and
vendor. This is the "what's alive on this network?" tool a Wi-Fi pro reaches for first
on site. It is the assembly of pieces we already have, plus a host-list UI.

## Value

High — the single biggest gap in the brief. Network Toolbox's headline is "scan the
LAN, then connect to what you found." We already hold the diagnostic spine; this is
the discovery layer that makes the rest of the toolbox land on a real network.

## Acceptance criteria

- Auto-detects the active interface's subnet (from `interface_info_service.dart`) and
  proposes the range; lets the user override the CIDR.
- Probes the range concurrently (bounded concurrency, with progress) and lists live
  hosts as they're found, not only at the end.
- Per host: IP (always), reverse-DNS hostname (when resolvable), MAC (when the OS
  exposes the ARP/NDP entry), vendor (via TICKET-002 OUI service).
- Honest degradation: where the OS hides the ARP cache (notably iOS), show IPs and
  hostnames and clearly mark MAC/vendor as unavailable on this platform — do not fake
  it. Reuse `network_unavailable_view.dart` messaging tone.
- Cancellable mid-scan; safe re-run; sensible defaults for large subnets (warn before
  scanning anything bigger than, say, a /22).
- Tappable host could deep-link to Ping / Port Scan pre-filled (nice-to-have, not
  required for v1).

## Implementation outline

- **Service:** `lib/services/network/lan_scan_service.dart` — orchestrates:
  1. subnet enumeration (reuse the range logic behind `ping_sweep_service.dart`),
  2. liveness probe per host (reuse Ping Sweep / ICMP-or-TCP probe),
  3. MAC resolution via `arp_ndp_service.dart`,
  4. vendor via the TICKET-002 `mac_oui_service.dart`,
  5. optional reverse-DNS via `dns_lookup_service.dart`.
  Emit results as a stream so the UI fills incrementally. No Flutter imports.
- **Screen:** `lib/screens/tools/network/lan_scan_screen.dart` — range field +
  scan/cancel, a live-updating host list (IP / host / MAC / vendor columns), progress
  indicator, per-platform unavailable banner for MAC/vendor where blocked.
- **Catalog:** add `ToolEntry` (`id: 'lan-scanner'`, `isLive: true`) to the
  Networking category; route in `app_router.dart`.
- **Tests:** `test/services/network/lan_scan_service_test.dart` — mock the probe and
  ARP layers; assert hosts stream in, vendor enrichment attaches, the MAC-unavailable
  path is marked (not errored), cancel stops further probes.

## Dependencies

- **TICKET-002 (MAC OUI lookup)** — required for the vendor column. Build it first.
- Reuses existing `ping_sweep_service.dart`, `arp_ndp_service.dart`,
  `interface_info_service.dart`, `dns_lookup_service.dart`. No new packages expected.

## iOS notes

- iOS exposes the ARP cache inconsistently; MAC/vendor may be unavailable. The tool
  still delivers value (live IPs + hostnames) and marks the rest honestly — the same
  pattern we already use for iOS traceroute.
- Subnet probing triggers the iOS Local Network privacy prompt (iOS 14+). Add the
  `NSLocalNetworkUsageDescription` string to `ios/Runner/Info.plist`; without it the
  scan silently returns nothing. (Shared with TICKET-004.)
