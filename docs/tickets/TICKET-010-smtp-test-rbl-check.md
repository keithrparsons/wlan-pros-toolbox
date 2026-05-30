# TICKET-010 — SMTP Test + Blocklist (RBL) Check

**Difficulty:** Moderate
**iOS blocker:** None. SMTP is a TCP socket; RBL is a DNS lookup.
**Source:** `myPKA/Deliverables/2026-05-29-netscantools-pro-feature-map/brief.md` (NetScanTools Pro "SMTP" + "RBL/blocklist")

## What it is

Two related mail-diagnostic checks:
1. **SMTP test** — open a TCP connection to a mail server, read the banner, run
   `EHLO` (and optionally `STARTTLS` capability check), report what the server
   advertises. Diagnostic only; no message is sent.
2. **RBL check** — given an IP, query a configurable set of DNS blocklists (e.g.
   `zen.spamhaus.org`) by reverse-octet `A` lookup and report listed/not-listed.

NetScanTools Pro ships both; they pair naturally.

## Value

Medium. Niche for a pure-Wi-Fi audience but squarely useful for the IT-generalist
side of the user base, and both ride transport we already own.

## Acceptance criteria

- **SMTP:** connect to `host:port` (default 25/587), read banner, send `EHLO`,
  display the multiline capability response. Clean timeout/refused handling. No mail
  is transmitted.
- **RBL:** accept an IPv4 address, query each configured blocklist via reversed-octet
  DNS `A` lookup, show per-list listed/not-listed plus any returned TXT reason.
- Blocklist set is a small editable/default list, not hard-coded to one provider.
- All failure modes map to the existing error taxonomy via `error_card.dart`.

## Implementation outline

- **Service:** `lib/services/network/mail_diag_service.dart` — TCP `Socket` for SMTP
  (mirror `port_scan_service.dart` connect/timeout); reuse the DoH resolver from the
  DNS tool for the RBL `A`/`TXT` queries. Typed result + error objects.
- **Screen:** `lib/screens/tools/network/mail_diag_screen.dart` — a mode toggle
  (SMTP test / RBL check) or two sub-panels; shared widgets throughout.
- **Catalog:** add `ToolEntry` (`id: 'mail-diag'`, `isLive: true`); route in
  `app_router.dart`.
- **Tests:** in-process TCP server emitting a canned SMTP banner + EHLO response;
  stub DNS for RBL listed/not-listed both paths.

## Dependencies

Reuses the existing DoH resolver (TICKET-006 territory) and the Port Scan
connect/timeout pattern. No new packages expected.

## Notes

Keep it strictly diagnostic: banner + capabilities + blocklist status. No auth, no
sending. That keeps it off any "this app sends mail" App Store review flag.
