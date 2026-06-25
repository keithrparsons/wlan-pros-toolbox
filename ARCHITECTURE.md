# Architecture

This document is a developer-level overview of the WLAN Pros Toolbox: how a tool is defined and wired, how the network-quality engine works, how the app integrates with each platform, and how the supporting systems (help, copy, theming, testing, build) fit together. Where the code is denser than this summary, the relevant file is named so you can read it directly.

## App structure

The Toolbox is a single Flutter app. The navigation graph is shallow: Home, then a Category screen, then a Tool screen. `lib/main.dart` is the entry point; it pre-loads the bundled asset manifests and the help JSON before the first frame, installs the iOS ICMP backend, loads the theme controller, and runs `ToolboxApp`.

### The data-driven catalog

`lib/data/tool_catalog.dart` is the single source of truth for what the app exposes. It defines:

- `ToolEntry` — one launchable tool: a stable kebab-case `id`, a `title`, a one-line `description`, a `routeName`, an `isLive` flag (a not-yet-shipped tool renders as a disabled "Coming soon" row), optional `keywords` for search, an optional `subgroup` for grouped category screens, and an `androidOnly` flag.
- `ToolCategory` — one home-grid category: `id`, `title`, `summary`, an icon, and its list of `ToolEntry` objects.

There are five categories in home-grid order: Test Network, Networking Tools, Calculators & Tools (catalog id `rf-calculators`), Quick Reference, and Educational Resources. The home tile count is read from the catalog, not hardcoded.

A tool's `id` is the join key across the whole app. The same string backs the route argument, the per-tool icon and concept-graphic asset lookups (`assets/tool-icons/<id>.svg`, `assets/tool-graphics/<id>.svg`), the help entry (`tool_help.json` keyed by id), and the tests. Titles get renamed; **ids never do**. Search keywords live separately in `lib/data/tool_keywords.dart` and are merged into the catalog at build time, so the search vocabulary can be edited without touching catalog structure.

The catalog builder applies platform filtering: `androidOnly` tools (for example `nearby-ap-scan`) are dropped from navigation and search on non-Android native targets, and a separate list marks tools that show a web-unavailable warning on the web build.

### The router

`lib/router/app_router.dart` is a plain named-route table (`Map<String, WidgetBuilder>`) handed to `MaterialApp.routes`. It deliberately avoids `go_router` because the graph is only two screens deep. Live tool routes are static and argument-less; category screens push themselves with `MaterialPageRoute` because they need a typed `ToolCategory` argument. Each route constant pairs with a catalog `routeName`. `catalog_route_integrity_test.dart` guards that every live catalog tool resolves to a registered route.

So the "define once, wire everywhere" pattern is: add a `ToolEntry` to the catalog, add a route constant and builder to the router, drop a help entry into `tool_help.json` (the help-file rule), and the search index, home count, icon resolver, and help footer all pick it up by id.

### Screen organization

Tool screens live under `lib/screens/tools/`, grouped by kind:

- `calculators/` — the RF, GPS, and conversion calculators.
- `network/` — the live and lookup network tools.
- `reference/` — the read-only reference tables and cards.
- `command/`, `checklists/`, `guides/`, `educational/` — CLI/Wireshark sheets, interactive checklists, bundled how-to guides, and the curated learning directory.

Shared widgets (the copy action, the help footer, tables, sparklines, field rows) live in `lib/widgets/`. Platform and data services live in `lib/services/` (notably `lib/services/network/` for the live tools and bridges). Theming lives in `lib/theme/`.

## The net_quality engine

`packages/net_quality` is a pure-Dart, backend-agnostic network-quality engine. It has no Flutter and no plugin dependencies; it runs on every Flutter target because it depends only on `dart:io` sockets and HTTP. Its own `ARCHITECTURE.md` is the authoritative reference; the summary here is the shape.

### The seam

There is exactly one contract between the app UI and any measurement backend:

```
QualityClient.measure() -> Stream<QualityProgress>, then QualityResult
```

`QualityResult` is a list of individually graded `QualityMetric` objects plus a source and a timestamp. The Network Quality screen (`net_quality_screen.dart`) depends only on the `QualityClient` seam, never on a concrete probe. Two implementations ship: `MockQualityClient` (deterministic data for tests and previews) and `OwnEngineQualityClient` (the real engine, composed from the probes).

### Probes and metrics

The engine measures latency, jitter, loss, download, upload, and a simplified responsiveness/RPM, via four injectable probes (`LatencyProbe`, `ThroughputProbe`, `ReachabilityProbe`, `ResponsivenessProbe`). Each probe takes function-typedef seams, so the whole engine is unit-testable with no real network.

- Latency and reachability use a **timed TCP connect** (SYN/SYN-ACK round trip) to a real host on port 443, not ICMP echo, because the macOS App Sandbox and iOS block raw sockets for sandboxed apps. A TCP-connect RTT is a sandbox-legal proxy for round-trip latency.
- Throughput is two-rung. **Rung 1 (primary)** is the Cloudflare speed endpoints over `HttpClient`. **Rung 2 (fallback)** is a self-hosted OpenSpeedTest endpoint (`https://speedtest.wlanpros.com`), consulted only after Cloudflare's own retries are exhausted, and only when it is both feature-enabled and a cheap liveness probe confirms it answers. The fallback ships **dormant** (the feature flag defaults off, the endpoint is not deployed yet), degrading silently to the honest terminal state until the box answers. Native clients pass the fallback's Origin gate with a public, rotatable `X-Toolbox-Client` header (not a secret; abuse protection is server-side rate limiting); the web build authenticates by Origin/CORS instead and never ships the header. See `packages/net_quality/lib/src/probes/throughput_probe.dart`.
- Jitter is RFC 3550-style mean deviation between consecutive successful samples.
- Responsiveness RPM is a simplified single-flow loaded-latency estimate inspired by RFC 9097 and Apple's networkQuality. It is not the full multi-flow RPM standard and is not presented as one.

### Graded, not composite

Each dimension is graded on its own (`excellent` / `good` / `fair` / `poor`) and deliberately **not** rolled into a single headline score. A dimension that cannot be measured on a given platform or run is reported as `unavailable`, shown honestly, never faked. The scoring bands (`packages/net_quality/lib/src/scoring.dart`) document, per dimension, whether they are standard-grounded (latency from ITU-T G.114, jitter and loss from VoIP guidance, responsiveness from RFC 9097 / Apple networkQuality) or explicitly heuristic (download and upload). Where a standard exists it grounds direction and magnitude; the exact cut points are the project's own choice.

The Wi-Fi radio metrics (RSSI, SNR, TX rate, MCS, channel width) are **not** in this package. They need platform channels into the OS Wi-Fi APIs and live in app-layer Flutter services. Their metric ids are reserved in the engine's `MetricIds` so both halves share one vocabulary, but the engine never measures them.

## Platform integration

### macOS: CoreWLAN

`macos/Runner/WifiInfoChannel.swift` bridges live Wi-Fi metrics from CoreWLAN to Flutter over the method channel `com.wlanpros.toolbox/wifi_info`. Every CoreWLAN read is wrapped defensively: a missing interface, nil value, or unexpected enum case becomes null in the payload rather than a thrown error. Two honest constraints are encoded:

- On recent macOS, reading SSID and BSSID requires Location Services authorization (When-In-Use is enough). Without it, `ssid` and `bssid` are null while RSSI, noise, rate, channel, width, band, and PHY still resolve. The payload reports `locationAuthorized` so the UI can explain the missing fields.
- Public CoreWLAN exposes Tx rate but not Rx rate or Tx power, so those fields are simply absent, never invented.

Other macOS in-Runner channels include `ArpTableChannel.swift`, `MdnsBrowseChannel.swift`, and `SystemInfoChannel.swift`.

### iOS: the Shortcuts bridge

iOS exposes no public API for RSSI or PHY rate / MCS to third-party apps. To get that data honestly, the app uses a companion Apple Shortcut, "WLAN Pros Live," that harvests RF metrics via the stock "Get Network Details" action, assembles them into JSON, and hands them to a native receiver App Intent.

The handoff (`ios/Runner/ShortcutsBridge.swift`, consumed by `lib/services/network/wifi_details_bridge.dart`) does not message a MethodChannel directly from the intent's `perform()`, because App Intents can run in a freshly launched or background-resumed process where no live Flutter engine is reachable. Instead the intent writes the JSON to an App Group shared `UserDefaults` key and posts a Darwin notification. The Dart side then **pulls** the key on launch/resume (the foreground-bounce flow) and is **pushed** via the Darwin notification when already foregrounded. Both resolve the same App Group key, so they cannot disagree. Off iOS, the channels have no handler and the screen reports the honest per-platform state.

### macOS sandbox handling

The macOS app is shipped via `scripts/ship_macos.sh` signed **without** the App Sandbox but **with** the hardened runtime (required for notarization). The sandbox blocks subprocess spawning, which would break the system-binary Traceroute, so direct notarized distribution avoids it. The `net_quality` engine independently avoids raw ICMP for the same sandbox reason and uses TCP-connect RTT instead. Tools that probe for a capability at runtime fall back to a `NetworkUnavailableView` rather than failing hard.

## Supporting systems

### Help

`assets/help/tool_help.json` carries one entry per catalog tool id, generated from the field manual. `lib/services/help/tool_help.dart` parses it once at startup, tolerantly (a malformed entry is skipped, a corrupt asset degrades to "no help", never a crash) and caches it for the process lifetime. `ToolHelpFooter` (`lib/widgets/tool_help_footer.dart`) renders an "About this tool" footer at the end of a tool screen **only** when a real help entry exists for that id; a tool with no help renders no footer. Every new tool ships its help entry as part of definition-of-done.

### Copy results

`AppCopyAction` (`lib/widgets/app_copy_action.dart`) is the shared "Copy results" AppBar affordance used across results, calculator, and reference screens. The screen passes a `textBuilder` closure that returns the full plain-text payload (or null when there are no results yet); the closure is evaluated lazily at tap time, so a screen never has to pre-serialize its results. It owns the clipboard write, the icon-swap confirmation, the screen-reader announcement, and the disabled no-results state.

### Theming

`lib/theme/` holds the design tokens (per GL-003): `app_tokens.dart`, `app_color_scheme.dart`, `app_typography.dart`, `app_theme.dart`, and `theme_controller.dart`. The app supports Light, Dark, and System modes; `ThemeController` persists an explicit Light/Dark pick via `shared_preferences` and restores it before the first frame (no theme flash), while System re-reads the OS appearance each launch. `MaterialApp` is wired with `theme: AppTheme.light()`, `darkTheme: AppTheme.dark()`, and the controller-driven `themeMode`. Typography is bundled (IBM Plex Sans, DM Mono, Roboto Mono) so type renders offline with no runtime font fetch.

### The connection analyzer

`lib/services/network/analyze/analyze_rules.dart` is a data-driven rule engine behind the one-tap "Analyze" action on the connection tools. Each rule pairs a `condition` against an `AnalyzeInput` with a ratified `responseDraft` string; the engine renders the fired rules' copy and never hardcodes prose. Thresholds are imported from the same app constants the rest of the app uses (the Wi-Fi grading bands, the `net_quality` scoring bands, the verdict thresholds), so advice and measurement can never drift apart. It runs entirely on-device.

## Testing and build

### Tests

The suite under `test/` covers the engine and services (unit), the screens (widget), and visual baselines (golden). `packages/net_quality` carries its own unit tests for each probe and the scoring. Notable structural guards include `catalog_route_integrity_test.dart` (every live tool routes), `category_tool_order_test.dart` and `tool_subgroups_test.dart` (ordering), and the reference golden tests. Golden and on-device PDF rendering use `integration_test` (run against a real platform embedder, for example `flutter test -d macos`) because Apple PDFKit is a no-op in the headless test environment. Run the full suite with `flutter test` and static analysis with `flutter analyze` (flutter_lints).

### Build and ship

iOS ships via `scripts/ship_ios.sh` (signed IPA upload to App Store Connect) plus the `appstore_release` fastlane lane (public update: "What's New", attach build, reuse listing, submit, auto-release). macOS ships via `scripts/ship_macos.sh` (Developer ID sign, notarize, staple, `.dmg`). See `ios/fastlane/Fastfile` for the full lane set and `README.md` for the contributor-facing build commands.
