# TICKET-008 — SNMP Get / Walk

**Difficulty:** Moderate — **library-gated (see Spike).**
**iOS blocker:** None expected (SNMP is UDP/161, within the `RawDatagramSocket` path
we already use). Risk is library maturity, not the sandbox.
**Source:** `myPKA/Deliverables/2026-05-29-netscantools-pro-feature-map/brief.md` (NetScanTools Pro "SNMP")

## What it is

Query an SNMP agent over UDP/161: a single `GET` on an OID, and a `WALK` of a subtree.
Read-only. Covers the "what does this AP/switch/controller report" check. NetScanTools
Pro ships a full SNMP suite; we scope to SNMPv1/v2c read for v1.

## Spike first (decision gate)

Before committing the build, confirm a usable Dart path exists:

- Search pub.dev for a maintained SNMP package (BER/ASN.1 encode/decode + v2c GET/WALK).
- If a maintained package exists and builds clean on iOS → proceed, difficulty Moderate.
- If not, decide: hand-roll a minimal v2c GET/GETNEXT BER codec (larger effort,
  re-rate to Hard) **or drop the ticket.** Per Keith: try it; if it cannot be made to
  work cleanly, remove it.

## Value

Medium-high for the WLAN audience: pulling sysDescr, ifTable, and vendor OIDs off
infrastructure is real field work. No mobile tool we ship touches it.

## Acceptance criteria (if the spike passes)

- SNMPv2c `GET` on a user-supplied OID with a community string; renders OID + type +
  value.
- `WALK` of a subtree OID; renders the returned varbinds as a `value_row.dart` list,
  with a sane cap + "stop" control to avoid runaway walks.
- Community string is a field (default `public`), never hard-coded.
- Timeout + unreachable + no-such-OID map to the existing error taxonomy via
  `error_card.dart`.
- If the spike fails, ship nothing — do **not** ship a simulated/empty SNMP view.

## Implementation outline

- **Service:** `lib/services/network/snmp_service.dart` — UDP via `RawDatagramSocket`
  (same transport proven by the packet/UDP work). BER encode/decode from the chosen
  package. Typed result + error objects.
- **Screen:** `lib/screens/tools/network/snmp_screen.dart` — host, community, OID,
  GET/WALK toggle. Reuse shared widgets.
- **Catalog:** add `ToolEntry` (`id: 'snmp'`, `isLive: true`) on pass; route in
  `app_router.dart`.
- **Tests:** in-process UDP responder serving canned BER packets; assert GET decode,
  WALK iteration + cap, timeout path.

## Dependencies

A maintained Dart SNMP/BER package — **unverified at ticket time.** This is the gate.

## Notes

Scope is read-only v1/v2c. No SET (write to live infrastructure from a phone is a
liability), no SNMPv3 auth/priv in v1. Honest-unavailable rule applies: a fake passes
no one.
