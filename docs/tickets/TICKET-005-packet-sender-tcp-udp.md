# TICKET-005 — Packet Sender (TCP / UDP)

**Difficulty:** Easy (TCP/UDP). Hard/blocked only if raw-IP framing is attempted.
**Build order:** 3 of 5
**iOS blocker:** None for TCP/UDP. Raw IP framing is iOS-blocked — stay scoped to TCP/UDP.
**Source:** brief.md §"Recommended additions" #5

## What it is

Send a custom payload to a `host:port` over TCP or UDP and show the response (raw
bytes + hex + decoded text). Good for probing a service banner, testing a captive
portal, poking a controller's API port, or checking a UDP service responds.

## Value

Medium. A flexible "talk to this port" tool covers a long tail of one-off field
checks that no fixed-purpose tool does. Network Toolbox ships a packet sender/receiver
and socket terminal; we have none.

## Acceptance criteria

- TCP mode: connect to `host:port`, send the payload, read the reply until timeout or
  connection close, display bytes received + hex + UTF-8/ASCII decode.
- UDP mode: send a datagram, wait for a reply within a timeout, display it (handle the
  no-reply case honestly — UDP gives no delivery guarantee).
- Payload input supports plain text and hex-escape entry (e.g. `\x00\xff`).
- Per-attempt timeout, surfaced in the UI; clean cancel.
- Errors (refused, unreachable, timeout, DNS failure) map to the existing error
  taxonomy via `error_card.dart`, consistent with Port Scan and Ping.

## Implementation outline

- **Service:** `lib/services/network/packet_sender_service.dart` — Dart `Socket`
  (TCP) and `RawDatagramSocket` (UDP). Returns a result object with sent bytes,
  received bytes, elapsed time, and a typed error. Mirror the structure of
  `port_scan_service.dart`, which already does TCP-connect with a timeout.
- **Screen:** `lib/screens/tools/network/packet_sender_screen.dart` — host/port
  fields, a TCP/UDP toggle, a payload field, a "Send" action, a result panel with a
  text/hex view switch. Reuse `labeled_field.dart`, `value_row.dart`, `error_card.dart`.
- **Catalog:** add `ToolEntry` (`id: 'packet-sender'`, `isLive: true`) to the
  Networking category; route in `app_router.dart`.
- **Tests:** `test/services/network/packet_sender_service_test.dart` — spin up an
  in-process TCP and UDP echo server on `127.0.0.1`, assert round-trip; assert
  timeout/refused paths produce the right typed error; assert hex-escape parsing.

## Dependencies

None. Reuses the timeout/error patterns already proven in Port Scan.

## Notes

**Hard scope line: TCP and UDP only.** Do not attempt raw sockets / custom ICMP or IP
framing — that is the same iOS wall that blocked our ICMP traceroute (raw sockets
unavailable in a sandboxed App Store app). Scoped to `Socket`/`RawDatagramSocket`, the
tool ships clean on every platform.
