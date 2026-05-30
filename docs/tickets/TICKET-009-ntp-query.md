# TICKET-009 — NTP Query

**Difficulty:** Moderate (simpler protocol than SNMP; likely hand-rollable).
**iOS blocker:** None expected. NTP is UDP/123 via `RawDatagramSocket`.
**Source:** `myPKA/Deliverables/2026-05-29-netscantools-pro-feature-map/brief.md` (NetScanTools Pro "Time / NTP")

## What it is

Send an SNTP request to an NTP server (UDP/123) and show server time, the local clock
offset, round-trip delay, stratum, and reference ID. NetScanTools Pro ships a Time/NTP
tool; the protocol is small and well-documented (RFC 4330 SNTP).

## Value

Medium. A clean diagnostic for "is this NTP source reachable and how far off is my
clock," which matters for 802.1X / RADIUS / cert-validation troubleshooting where
clock skew breaks auth.

## Acceptance criteria

- Send a mode-3 SNTP packet to a user-supplied server (default `pool.ntp.org`).
- Parse the 48-byte response: stratum, reference ID, transmit timestamp; compute
  offset and round-trip delay from the four timestamps.
- Display server UTC time, computed offset (signed, ms), round-trip delay, stratum.
- Timeout / unreachable / malformed-response map to the existing error taxonomy via
  `error_card.dart`.

## Implementation outline

- **Service:** `lib/services/network/ntp_service.dart` — build the 48-byte SNTP
  request, send via `RawDatagramSocket`, parse the response, do the offset/delay math.
  Pure Dart, no native channel. (A maintained pub.dev SNTP package is acceptable if one
  builds clean on iOS; otherwise hand-roll — the packet is fixed-format and small.)
- **Screen:** `lib/screens/tools/network/ntp_screen.dart` — server field, query action,
  result `value_row.dart` list. Reuse shared widgets.
- **Catalog:** add `ToolEntry` (`id: 'ntp'`, `isLive: true`); route in `app_router.dart`.
- **Tests:** in-process UDP responder returning a known SNTP packet; assert timestamp
  parse + offset/delay math against hand-computed values; assert timeout path.

## Dependencies

None hard-required (hand-rollable). Optional maintained SNTP package if clean on iOS.

## Notes

The NTP-timestamp epoch is 1900, not 1970 — handle the offset explicitly in tests.
