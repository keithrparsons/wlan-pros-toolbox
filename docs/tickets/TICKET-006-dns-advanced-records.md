# TICKET-006 — DNS Advanced Record Types

**Difficulty:** Easy
**iOS blocker:** None
**Source:** `myPKA/Deliverables/2026-05-29-netscantools-pro-feature-map/brief.md` (NetScanTools Pro "DNS Tools")

## What it is

Extend our existing DNS-over-HTTPS lookup to resolve the record types a network
tech actually chases during mail, service, and reverse-DNS troubleshooting: SPF
(TXT), SRV, CAA, and PTR (reverse). NetScanTools Pro bundles a deep DNS suite; this
closes the gap with the types that matter without re-architecting.

## Value

High frequency, low cost. We already ship a working DoH resolver, so each new record
type is incremental. SPF/CAA/SRV/PTR are the records people open a terminal for.

## Acceptance criteria

- Adds A/AAAA/CNAME/MX/NS/TXT (if not already present) plus **SPF (via TXT), SRV,
  CAA, and PTR (reverse lookup from an IPv4/IPv6 address)**.
- PTR accepts a raw IP and constructs the `in-addr.arpa` / `ip6.arpa` query
  internally; the user does not hand-build the reverse name.
- Record type is user-selectable; results render as a `value_row.dart` list with
  TTL shown per record.
- Empty / NXDOMAIN / SERVFAIL responses map to the existing error taxonomy via
  `error_card.dart`, not a blank screen.

## Implementation outline

- **Service:** extend the existing DoH service in `lib/services/network/`
  (the current DNS lookup service). Add the record-type enum cases and the
  PTR-name construction helper. No new transport, no native channel.
- **Screen:** extend the existing DNS lookup screen with the new record-type options
  in its selector. Reuse `labeled_field.dart`, `value_row.dart`, `error_card.dart`.
- **Catalog:** no new `ToolEntry` required if it stays inside the existing DNS tool;
  add one only if we decide reverse-DNS warrants its own entry.
- **Tests:** mirror the existing DNS service tests; add vectors for SRV/CAA parsing
  and PTR-name construction (IPv4 and IPv6).

## Dependencies

None. Pure extension of the shipped DoH resolver.

## Notes

Lowest-risk item in this NetScanTools tranche. All HTTPS, fully cross-platform.
