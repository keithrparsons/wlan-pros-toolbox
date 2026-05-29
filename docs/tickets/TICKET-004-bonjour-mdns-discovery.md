# TICKET-004 — Bonjour / mDNS Service Discovery

**Difficulty:** Moderate
**Build order:** 5 of 5
**iOS blocker:** Local Network permission prompt is mandatory (not a hard block)
**Source:** brief.md §"Recommended additions" #4

## What it is

Discover services advertised on the local link via mDNS/DNS-SD (Bonjour): AirPlay,
printers (`_ipp._tcp`), Chromecast (`_googlecast._tcp`), HTTP admin services
(`_http._tcp`), SSH, SMB, and any custom service type. Finds devices a plain ping
sweep misses, because they answer multicast discovery rather than ICMP.

## Value

High in Keith's audience — Apple-heavy and AV-heavy environments where Bonjour is how
half the gear announces itself. Network Toolbox ships Bonjour/UPnP discovery; this is
a natural companion to the LAN scanner (TICKET-001) and arguably finds the more
interesting devices.

## Acceptance criteria

- Browses a set of common service types out of the box, plus a field to enter an
  arbitrary `_service._proto` type.
- Per discovered service: instance name, service type, host, resolved IP(s), port, and
  TXT-record key/values (often the useful metadata: model, firmware, capabilities).
- Live-updating list as responders reply; cancellable.
- Honest empty/permission state: if Local Network permission is denied, say so and
  link to Settings rather than showing a silent empty list.

## Implementation outline

- **Package:** evaluate `multicast_dns` (Dart, used by Flutter tooling) first — it is
  pure-Dart DNS-SD and may avoid a custom native channel. If its platform coverage or
  continuous-browse behavior is insufficient, fall back to a maintained Bonjour plugin
  (e.g. an `nsd`/bonsoir-style package) behind a platform channel. Record the choice
  and the reason in the service file header.
- **Service:** `lib/services/network/mdns_discovery_service.dart` — wraps the chosen
  package, exposes a stream of discovered+resolved services with TXT records. No
  Flutter imports.
- **Screen:** `lib/screens/tools/network/mdns_discovery_screen.dart` — service-type
  chips + custom-type field, a live results list (expandable rows showing TXT
  records), permission-denied state via `network_unavailable_view.dart`.
- **Catalog:** add `ToolEntry` (`id: 'mdns-discovery'`, `isLive: true`) to the
  Networking category; route in `app_router.dart`.
- **Entitlements / Info.plist:**
  - iOS: `NSLocalNetworkUsageDescription` + `NSBonjourServices` (list each browsed
    service type) in `ios/Runner/Info.plist`. Without `NSBonjourServices`, iOS 14+
    silently drops the responses.
  - macOS: enable the multicast networking entitlement on the App Sandbox.
- **Tests:** `test/services/network/mdns_discovery_service_test.dart` — unit-test the
  result-parsing/TXT-decode logic against canned mDNS records; the live multicast path
  is integration-tested manually on device (note this in the test file).

## Dependencies

- Shares the iOS `NSLocalNetworkUsageDescription` requirement with TICKET-001; if that
  ticket already added it, extend rather than duplicate, and add `NSBonjourServices`.
- New pub dependency (mDNS package) — first one in this shortlist that adds a package;
  vet its maintenance and license before adding.

## iOS notes

Once Local Network permission is granted and `NSBonjourServices` declares the types,
mDNS works on iOS. The permission prompt is mandatory and one-time; design the empty
state to explain it. This is the "moderate" cost vs the easy pure-Dart tickets:
native entitlements + a permission UX, not just logic.
