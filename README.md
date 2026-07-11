# WLAN Pros Toolbox

A free field toolkit for Wi-Fi and network professionals: live network tests, RF and network calculators, and reference tables in one app. Built for and by the WLAN Pros community.

The app is honest about platform limits. Where an operating system blocks a capability (iOS exposes no public RSSI or MCS API, raw ICMP needs privileges some platforms deny), the tool says so plainly instead of faking a result.

## What it is

The Toolbox bundles 120+ tools into five categories:

- **Test Network** — live Wi-Fi and internet diagnostics: Network Quality, Wi-Fi Information, Cellular Information, and the consumer-facing "Check My Connection" front door.
- **Networking Tools** — interface info, device info, DNS lookup, port scan, ping (TCP and ICMP), ping plotter, ping sweep, network discovery, nearby AP scan, traceroute, SSL/TLS inspector, HTTP header inspector, WHOIS, Wake-on-LAN, ARP/NDP, BGP/ASN, IP geolocation, current location, MAC vendor OUI lookup, packet sender, and IPv4/IPv6 subnetting.
- **Calculators & Tools** — RF, GPS, signal, and planning math: dBm/Watt, free space path loss, EIRP, Fresnel zone, cable loss, link budget, wavelength, antenna downtilt, earth curvature, ITU rain fade, noise floor, RF attenuation, PoE budget, throughput, capacity planning, point-to-point link checks, GPS conversions, unit converters, QR and DTMF generators, and more.
- **Quick Reference** — field-reference tables and guides: 802.11 standards, MCS index, signal thresholds, WPA security, roaming parameters, AP placement, channel and spectrum maps, cabling and connector references, reason codes, frame exchange, 802.1X/EAP types, regulatory domains, standards bodies, glossaries, checklists, and CLI/Wireshark cheatsheets.
- **Educational Resources** — curated, independent-author places to learn Wi-Fi: blogs, talks, channels, podcasts, and reference diagrams.

The catalog is the single source of truth for what ships; the home-grid count is read straight from it.

### Local-first and private

The Toolbox collects no personal data. There is no account, no login, and no analytics or telemetry in the build.

- Reference tables, calculators, glossaries, and the bundled guides and PDF cards run fully offline. Typography is bundled (no runtime font fetch), so the app renders on first launch with no network.
- Live network tools reach the network only to do their job (a ping reaches its target, a speed test reaches the throughput endpoint). The connection analyzer ("Analyze") runs on-device; nothing is uploaded.
- Location is used only to read the connected Wi-Fi SSID (a platform requirement on recent macOS and on Android) and for the optional GPS tools. It is never stored or shared.

## Platforms

One Flutter codebase targets iOS, macOS, Windows, Android, and the web.

- **iOS** is on the Apple App Store.
- **macOS** ships as a direct `.dmg` download from the WLAN Pros website (not the App Store).
- **Android** is live on Google Play.
- **Windows** is live in the Microsoft Store.
- **Web** is a hosted build. Calculators and reference tables work in the browser; network-dependent tools (ping, port scan, traceroute, and similar) need a native build and are hidden on web with a prompt to install the app.

### Platform capability notes

- **iOS** has no public API for RSSI or PHY rate / MCS index. Those metrics are surfaced through a companion Apple Shortcut ("WLAN Pros Live") where iOS allows it, and are reported as honestly unavailable where it does not. Local Network access prompts on first use.
- **Nearby AP scan** runs on Android today. Apple platforms (iOS and macOS) block third-party Wi-Fi scanning at the OS level; a Windows version is planned (Windows can enumerate access points, it is just not wired into this tool yet).
- **Traceroute** has two forms: a system-binary traceroute on desktop (macOS, Windows, Linux), and a mobile TTL-walk that works on Android but is honestly unavailable on iOS (the available ICMP layer only parses Echo Reply, never Time Exceeded).
- **Ping (TCP)** is a TCP-handshake RTT probe, labeled as such; **Ping (ICMP)** is the separate echo-based tool.

## How to get it

- **iOS and macOS** — the App Store (search "WLAN Pros Toolbox").
- **Web** — the hosted web build.
- **WLAN Pros website** — the Toolbox page links to the current download options.

## For contributors

The app is a standard Flutter project.

### Prerequisites

- **Flutter** with the Dart SDK at `^3.12.0` (per `pubspec.yaml` `environment:`).
- Xcode (iOS / macOS builds), and the platform toolchains for any target you build.

### Run, test, analyze

```bash
flutter pub get
flutter run            # attached device or simulator
flutter test           # unit + widget + golden suite
flutter analyze        # static analysis (flutter_lints)
flutter build web      # web build
```

The `net_quality` engine is a local path package under `packages/net_quality`; `flutter pub get` resolves it automatically.

### Build and ship

The release scripts live in `scripts/`:

- `scripts/ship_ios.sh` — builds a signed iOS IPA and uploads it to App Store Connect via fastlane. It switches the Runner to manual distribution signing for the build, stamps a timestamp build number, then restores automatic signing.
- `scripts/ship_macos.sh` — builds, signs (Developer ID, hardened runtime, no sandbox), notarizes, staples, and packages a notarized `.dmg`.
- `scripts/serve_web_demo.sh` — serves a local web build.

fastlane lanes (in `ios/fastlane/Fastfile`) wrap the App Store Connect work:

- `appstore_release` — submits a public App Store update: sets "What's New" from `metadata/en-US/release_notes.txt`, attaches the already-uploaded build, reuses the existing listing and screenshots, submits for review, and auto-releases on approval.
- `appstore_status` — prints current App Store version states from the CLI.
- `upload` — uploads a built IPA to TestFlight (waits for processing).
- `check`, `make_app`, `signing`, `mac_cert`, `internal_group`, `external_group`, `invite_external`, `submit_external_review` — auth checks, app-record and certificate setup, and TestFlight group management.

A typical public update is `./scripts/ship_ios.sh` to upload the binary, then `fastlane appstore_release` (after editing `release_notes.txt`).

There is no committed macOS fastlane config; macOS ships via `scripts/ship_macos.sh`.

### Architecture

See `ARCHITECTURE.md` for the data-driven catalog and router pattern, the `net_quality` engine, platform integration (CoreWLAN, the iOS Shortcuts bridge, the macOS sandbox), the help and copy patterns, theming, and testing.

## Credits

Built for and by the WLAN Pros community. RF calculator formulas mirror the WLAN Pros RF Tools reference set. Offline MAC vendor data is derived from the public IEEE OUI registry. Bundled reference content credits its independent authors in the Educational Resources entries and in each tool's help.

## License

**The WLAN Pros Toolbox is free software, licensed under the [GNU AGPL-3.0](LICENSE).**

In plain English:

- **Use it for anything, including your paid consulting work.** Running the Toolbox on a billable site survey is exactly what it is for. There is no restriction on commercial use.
- **Fork it, read it, improve it.** Pull requests welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md). You will be asked to sign a [CLA](CLA.md), which is what lets us keep shipping the app on the App Store.
- **If you distribute a modified version — including running it over a network — you must publish your source** under the same license. That is the AGPL's bargain, and the reason we chose it.
- **You may not use the "WLAN Pros" name or logo on your fork.** The AGPL covers the code, not the brand. See [`TRADEMARK.md`](TRADEMARK.md). Rename and rebrand.

Third-party dependencies keep their own licenses: [`THIRD-PARTY-LICENSES.md`](THIRD-PARTY-LICENSES.md) (generated) and [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) (bundled components). Store distribution is addressed in [`LICENSE-EXCEPTION-APPSTORE.md`](LICENSE-EXCEPTION-APPSTORE.md). The rationale behind all of this is in [`docs/LICENSING.md`](docs/LICENSING.md).

Copyright © 2026 Wireless LAN Professionals, Inc.
