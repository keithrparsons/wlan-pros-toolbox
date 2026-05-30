# WLAN Pros Toolbox

A free, cross-platform field toolkit for Wi-Fi and network professionals: 60 RF calculators, live network diagnostics, and reference tables in one app. Built for the WLAN Pros community.

The app is honest about platform limits. Where an operating system blocks a capability (iOS has no public RSSI or MCS API, raw ICMP needs privileges some platforms deny), the tool says so plainly instead of faking a result.

## What's inside

60 tools across 8 categories:

- **RF Calculators** (11) — dBm/Watt, Free Space Path Loss, EIRP, Fresnel Zone, Cable Loss, Link Budget, Wavelength, Antenna Downtilt, Earth Curvature, ITU Rain Fade, Downtilt Coverage
- **GPS Tools** (5) — Metric Conversion, Lat/Long Conversion, Distance and Bearing, Midpoint, Final Point
- **Networking** (22) — Interface Information, DNS Lookup, Port Scan, Ping (TCP), ICMP Ping, Ping Sweep, Traceroute, Mobile Traceroute, SSL/TLS Inspector, HTTP Header Inspector, WHOIS, Wake-on-LAN, ARP/NDP Lookup, BGP/ASN Lookup, IP Geolocation, MAC Vendor Lookup, Packet Sender, IPv4 Subnetting, Wi-Fi Channels, 802.11 Standards, MCS Index, Signal Thresholds
- **Infrastructure** (4) — PoE Budget, RF Attenuation, Noise Floor, PoE Reference
- **Planning Tools** (4) — Throughput Calculator, Capacity Planner, PtP Link Check, IPv6 Subnet
- **Cabling and Connectors** (5) — Ethernet Pinout, Coax Cable, Ethernet Cable, Fiber Optic, RF Connectors
- **Wi-Fi Design** (3) — WPA Security, Roaming Parameters, AP Placement
- **Quick Reference** (6) — Well-Known Ports, Reason Codes, Frame Exchange, dB Reference, Channel Map, Spectrum Reference

## Platforms

iOS, Android, macOS, Windows, and Web from a single Flutter codebase. The calculators and reference tables work everywhere, including the browser. Network-dependent tools (ping, port scan, traceroute, and similar) require a native build and are hidden on Web with a prompt to install the app.

### Platform capability notes

- **iOS** — no public API for RSSI or PHY rate / MCS index; those tools are unavailable on iOS by design, not omitted silently. ICMP Ping uses SimplePing. Local Network access prompts on first use.
- **Mobile Traceroute** — Android can perform a real TTL walk; iOS cannot (the available ICMP layer only parses Echo Reply, never Time Exceeded), so iOS shows an honest unavailable state and points to Ping.
- **Traceroute (system)** — desktop only (macOS, Windows, Linux), via the system binary.
- **Ping (TCP)** is a TCP-handshake RTT probe, not an ICMP echo, and is labeled as such in the UI. ICMP Ping is the separate echo-based tool.

## Permissions

The app requests only what a given tool needs:

- **iOS** — Local Network (device/port inspection on your LAN) and Location-When-In-Use (read the connected Wi-Fi SSID only; location is never stored or shared).
- **Android** — Internet, Network State, Wi-Fi State, and Fine Location (Android ties Wi-Fi SSID access to location permission).

## Distribution

Free to the community. Not published to the App Store or Google Play.

- **iOS** — TestFlight (public link)
- **Android** — sideloaded APK
- **macOS** — notarized DMG
- **Windows** — signed installer
- **Web** — hosted build

## Development

Flutter 3.44.0, Dart. Dark theme, lime accent, IBM Plex Sans + DM Mono.

```bash
flutter pub get
flutter run            # attached device or simulator
flutter test           # full suite
flutter analyze        # static analysis
flutter build web      # web build
```

Bundle identifier: `com.wlanpros.wlanProsToolbox`

## Credits

Built for and by the WLAN Pros community. RF calculator formulas mirror the WLAN Pros RF Tools reference set. Offline MAC vendor data is derived from the public IEEE OUI registry.
