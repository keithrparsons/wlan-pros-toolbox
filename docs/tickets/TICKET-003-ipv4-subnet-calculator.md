# TICKET-003 — IPv4 Subnet Calculator

**Difficulty:** Easy
**Build order:** 2 of 5
**iOS blocker:** None
**Source:** brief.md §"Recommended additions" #3

## What it is

Given an IPv4 address and a CIDR prefix (or dotted mask), compute the network
address, broadcast address, usable host range, host count, wildcard mask, and
mask/prefix conversions. Bread-and-butter network-tech math.

## Value

Medium, but high-frequency. Already seeded as a placeholder in our catalog (the brief
notes IPv4 subnetting is a placeholder). Closing it removes a visible "Coming soon"
and gives every network tech a tool they reach for constantly.

## Acceptance criteria

- Accepts `address/prefix` (e.g. `10.20.0.0/22`) and address + dotted mask
  (`10.20.0.0` + `255.255.252.0`).
- Returns: network address, broadcast address, first/last usable host, total hosts,
  usable hosts, wildcard mask, prefix length, dotted mask.
- Correct edge cases: `/31` (RFC 3021 point-to-point, 2 usable hosts), `/32`
  (single host), `/0` through `/30` standard.
- Validates octet ranges and prefix range; rejects malformed input with a clear
  message via `error_card.dart`.
- Optional polish: "contains this host?" check and next/previous subnet of the same
  size.

## Implementation outline

- **Service:** `lib/services/network/subnet_calc_service.dart` — pure Dart integer
  math on the 32-bit address. No network, no Flutter imports. API:
  `SubnetResult calculate({required String address, int? prefix, String? mask})`.
- **Screen:** `lib/screens/tools/network/subnet_calc_screen.dart` — two
  `labeled_field.dart` inputs (address; prefix-or-mask), results as a `value_row.dart`
  list. Live-recompute on valid input is a nice touch.
- **Catalog:** flip the existing IPv4-subnetting placeholder `ToolEntry` to
  `isLive: true` (or add one if only the category is seeded) in
  `lib/data/tool_catalog.dart`; add the route in `app_router.dart`.
- **Tests:** `test/services/network/subnet_calc_service_test.dart` — known-good
  vectors per prefix, the `/31` and `/32` edge cases, mask⇄prefix round-trips,
  malformed-input rejection.

## Dependencies

None.

## Notes

Pure-Dart, fully deterministic, trivially unit-testable. This is the lowest-risk
ticket in the set; good warm-up / good first issue.
