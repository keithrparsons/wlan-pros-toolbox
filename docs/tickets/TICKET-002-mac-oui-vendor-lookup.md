# TICKET-002 — MAC OUI / Vendor Lookup

**Difficulty:** Easy
**Build order:** 1 of 5 (build first — feeds TICKET-001's vendor column)
**iOS blocker:** None
**Source:** brief.md §"Recommended additions" #2

## What it is

Turn a MAC address into a vendor name (`b8:27:eb:...` to "Raspberry Pi Foundation",
`00:1a:1e:...` to "Aruba Networks"). Standalone tool, and a reusable service the LAN
scanner calls for its vendor column.

## Value

Medium-high for a Wi-Fi pro. Reading a client list or an ARP table and instantly
knowing "that's a Cisco Meraki AP, that's an Apple TV, that's a Ubiquiti switch" is a
daily-use lookup. Network Toolbox ships a MAC OUI database; we have nothing.

## Acceptance criteria

- Accepts a MAC in any common format (colon, hyphen, dot, no-separator; upper/lower).
- Normalizes to the 24-bit OUI and returns the registered organization name.
- Handles the three IEEE registry sizes: MA-L (/24, the common case), and ideally
  MA-M (/28) and MA-S (/36) for completeness.
- Flags locally-administered / randomized MACs (the U/L bit) — critical, because
  modern phones randomize MACs and the vendor lookup is meaningless for those. Say so
  honestly rather than returning a wrong vendor.
- Works fully offline against a bundled table; no network call required.
- Unknown OUI returns a clean "not in registry" state, not an error.

## Implementation outline

- **Asset:** bundle a trimmed IEEE OUI table as a project asset under `assets/oui/`
  (declare in `pubspec.yaml`). Source: IEEE `oui.csv` (MA-L). Trim to
  `oui_hex,organization` to keep the asset small; load and parse once, cache in
  memory. Document the asset's source + retrieval date in a header comment so it can
  be refreshed.
- **Service:** `lib/services/network/mac_oui_service.dart` — pure Dart. API:
  `OuiResult lookup(String mac)` returning `{normalizedMac, oui, vendor?, isLocal,
  isMulticast, matched}`. No Flutter imports.
- **Screen:** `lib/screens/tools/network/mac_oui_screen.dart` — single
  `labeled_field.dart` input, result via `value_row.dart`, errors via `error_card.dart`.
- **Catalog:** add a `ToolEntry` (`id: 'mac-oui-lookup'`, `isLive: true`) to the
  Networking category in `lib/data/tool_catalog.dart`; route in `app_router.dart`.
- **Tests:** `test/services/network/mac_oui_service_test.dart` — all input formats
  normalize equal; known OUI resolves; locally-administered bit detected; unknown OUI
  returns unmatched; malformed input rejected.

## Dependencies

None. This is the feeder for TICKET-001 (LAN scanner), so it lands first.

## Notes

Decide refresh policy: bundled-static (simple, goes stale) vs fetch-and-cache from
IEEE on first run (fresher, needs a network path + offline fallback). Recommend
bundled-static for v1 with a documented refresh step; the brief rates the easy win on
the offline table.
