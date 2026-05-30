# TICKET-007 — Well-Known Ports / RFC Reference

**Difficulty:** Easy
**iOS blocker:** None
**Source:** `myPKA/Deliverables/2026-05-29-netscantools-pro-feature-map/brief.md` (NetScanTools Pro reference lookups)

## What it is

A searchable offline reference: type a port number or a service name and get the
registered service, transport (TCP/UDP), and a one-line description. Bundled IANA
data, no network call. NetScanTools Pro ships database/reference lookups; this is the
one a field tech reaches for ("what runs on 8443?").

## Value

Medium, high-frequency, zero risk. Useful standalone and as a companion to Port Scan
(map an open port to its likely service).

## Acceptance criteria

- Search by port number (exact) and by service-name substring (case-insensitive).
- Each result shows: port, transport, service name, short description.
- Works fully offline; data ships in `assets/`.
- Empty-result state handled cleanly.
- Optional polish: deep-link from a Port Scan result row to this reference.

## Implementation outline

- **Data:** curated IANA well-known/registered subset as a JSON asset in `assets/`
  (do not ship the full multi-thousand-row registry; curate to the ports techs
  actually meet). Register the asset in `pubspec.yaml`.
- **Service:** `lib/services/network/port_reference_service.dart` — load + index the
  asset once, expose `search(query)`. No Flutter imports.
- **Screen:** `lib/screens/tools/network/port_reference_screen.dart` — single search
  field, results as `value_row.dart` list. Reuse `labeled_field.dart`.
- **Catalog:** add `ToolEntry` (`id: 'port-reference'`, `isLive: true`); route in
  `app_router.dart`.
- **Tests:** `test/services/network/port_reference_service_test.dart` — known port
  lookups, name-substring search, empty-result path.

## Dependencies

None. Pure asset + Dart.

## Notes

Curation is the only real decision here: keep the list to ports a WLAN/network pro
meets in the field, not the exhaustive registry.
