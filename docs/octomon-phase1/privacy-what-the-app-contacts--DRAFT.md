# What the Toolbox contacts on the internet, and why (DRAFT)

Draft for Keith's review, from octomon review recommendation 6(c). Not published. Built from the app's own code at commit `87c0ba5c`: every endpoint is pinned to file:line so a reviewer can check it. The pins come out before publishing; the tables stay.

Scope of this draft: the Dart code in `lib/` and `packages/net_quality/lib/`. The platform code under `ios/`, `macos/`, `android/` and `windows/`, and the iOS companion Shortcut, were **not** reviewed. Check those before this page goes live.

---

## The short version

- The app has no analytics, no crash reporting and no tracking. Nothing about you is sent to WLAN Pros.
- Nothing on a phone or computer contacts the internet when the app starts. (The web version served from a WLAN Pi asks that Pi one question at start-up, below.)
- Each tool contacts the internet only to do its job. Most wait for you to tap Run. A few start by themselves when you open them, and those are marked **Starts on open** below.
- Any server the app contacts sees your public IP address. That is how the internet works, and it is true of every website you visit.
- Lookups of things you type (a host to ping, a domain for WHOIS) go to the service doing the lookup, and to that host.

## Check My Connection

The card on the home screen starts the check as soon as it opens. The speed test is left out unless the app knows you are on Wi-Fi or another connection that does not cost you data.

| What it contacts | Why | When | Pin |
|---|---|---|---|
| `one.one.one.one`, port 443 (Cloudflare) | Latency, jitter, loss and responsiveness. Opens connections and times them; no data is sent. | When the check runs | `lib/screens/tools/network/test_my_connection_screen.dart:773`; `packages/net_quality/lib/src/probes/latency_probe.dart:96` |
| `speed.cloudflare.com`, `proof.ovh.net`, `nbg1-speed.hetzner.com`, `cachefly.cachefly.net`, `download.thinkbroadband.com` (backups: `fsn1-speed.hetzner.com`, `hel1-speed.hetzner.com`) | Download speed. Downloads test files and throws them away. Tens to hundreds of MB. | When the check runs with the speed test | `packages/net_quality/lib/src/probes/throughput_probe.dart:473-480` |
| `speed.cloudflare.com/__up` | Upload speed. Sends about 10 MB of filler bytes. | Same | `packages/net_quality/lib/src/probes/throughput_probe.dart:522`, `:486` |
| `ipinfo.io`, backup `get.geojs.io` | Your public IP, ISP and approximate city, for the report | When the check runs | `lib/services/network/ip_geo_service.dart:177-178`; `lib/screens/tools/network/test_my_connection_screen.dart:1869` |
| Your network's own DNS server, asked for `cloudflare.com`, then `google.com`, then `apple.com` | Proves names resolve, and times it | When the check runs | `lib/services/network/dns_probe_service.dart:77-81` |
| `www.facebook.com`, `www.instagram.com`, `www.tiktok.com`, `www.youtube.com`, `www.netflix.com`, `www.google.com`, `www.icloud.com`, `www.office.com`, `www.cloudflare.com`, `aws.amazon.com`, `zoom.us`, `slack.com`, `github.com`, `one.one.one.one`, all port 443 | "Cloud apps reachable?": can you reach the services people use? Opens a connection to each and times it; no data is sent. | **Starts on open** of the results | `packages/net_quality/lib/src/popular_sites.dart:46-69`; `lib/screens/tools/network/cloud_apps_panel.dart:82` |

The app also contains a backup speed test server of our own, `speedtest.wlanpros.com`. It is switched off and nothing in the app turns it on (`packages/net_quality/lib/src/probes/throughput_probe.dart:497`, `:696`).

## Tools that start by themselves when you open them

| Tool | What it contacts | Why | Pin |
|---|---|---|---|
| Network Quality | `one.one.one.one`, port 443, 5 quick connections every 30 seconds while the screen is open | The live latency line | `lib/screens/tools/network/net_quality_screen.dart:193-196`; `lib/screens/tools/network/live_quality_monitor.dart:103-107` |
| Interface Info | `api.ipify.org`, backup `icanhazip.com` | Shows your public IP | `lib/services/network/public_ip_service.dart:39-40`; `lib/screens/tools/network/interface_info_screen.dart:156` |
| Network Discovery | `api.ipify.org` / `icanhazip.com`, and `ipinfo.io` / `get.geojs.io` | Public IP and ISP in the summary card | `lib/screens/tools/network/network_glance_card.dart:271`, `:656-657` |
| Current Location | `ipinfo.io` / `get.geojs.io`, **only** when GPS gives no fix | A rough location from your IP instead | `lib/services/location/device_location.dart:231-271` |
| Lat/Long | `tile.openstreetmap.org`, when it has coordinates (on open if location permission is already granted) | Map tiles. The tiles requested show roughly where you are looking. | `lib/widgets/location_map.dart:63`; `lib/screens/tools/calculators/lat_long_screen.dart:186` |
| About (direct-download Mac and Windows builds only) | `api.github.com`, the Toolbox's releases page | Checks for a newer version. Sends nothing about you or your version. Not on iPhone, Android, the Mac App Store build or the web. Checked at most every 6 hours. | `lib/services/update/update_platform_io.dart:19`; `lib/screens/about_screen.dart:103` |

## Tools that wait for you to tap Run

| Tool | What it contacts | What it sends | Pin |
|---|---|---|---|
| Network Quality (full run) | Same servers as Check My Connection | Same | `lib/screens/tools/network/net_quality_screen.dart:186-187` |
| IP Geolocation | `ipinfo.io`, backup `get.geojs.io` | The IP or host you type (blank means your own) | `lib/services/network/ip_geo_service.dart:243-263` |
| Lookup (DNS) | `cloudflare-dns.com` by default; `dns.google.com` or `dns.quad9.net` if you pick them | The name you look up | `lib/services/network/dns_lookup_service.dart:211`, `:396-427` |
| NTP | `time.apple.com` by default, `pool.ntp.org` with one tap, or a server you type (UDP 123) | A standard time request | `lib/services/network/ntp_service.dart:52-56` |
| WHOIS | `whois.iana.org` (TCP 43), then the registry and registrar it points to | The domain or IP you type | `lib/services/network/whois_service.dart:41` |
| BGP/ASN | `stat.ripe.net` | The IP or ASN you type, plus the tag `sourceapp=wlanprostoolbox`, which RIPE asks apps to send | `lib/services/network/bgp_asn_service.dart:135` |
| Link Info | `cloudflare.com`, port 443, from the link you chose | A connection only | `lib/services/network/link_bind_probe.dart:37` |
| Ping, Ping (ICMP), Ping Plotter, Traceroute, Port Scan, Inspector (SSL/TLS), HTTP Headers, Packet Sender | The host you type, and nothing else | The probes the tool describes | `lib/services/network/ping_service.dart:216`; `lib/services/network/traceroute_service.dart:269`; `lib/services/network/port_scan_service.dart:105` |

## Tools that stay on your own network

Wake-on-LAN, Ping Sweep, the Network Discovery scan and the neighbor table talk only to devices on your local network. Nothing leaves it. Pins: `lib/services/network/wake_on_lan_service.dart:88`; `lib/services/network/lan_discovery/connect_scan.dart:188`.

## Links you tap

Reference pages link to regulators, standards bodies, speed test sites, Apple support, maps and our own websites. Those open in your browser only when you tap them; the app itself does not contact them.

## When the Toolbox runs on a WLAN Pi

The web version served from a WLAN Pi asks that Pi one question at start-up, to find out whether it is on a Pi (`lib/main.dart:347`). After that, each tool asks the Pi to do the work (`/toolboxapi/...`, `lib/services/network/pi_backend_client.dart:704-709`). Any lookups to outside services, such as ipinfo or RIPE, are then made by the Pi, not by your browser.

---

## Open items for the reviewer

1. Platform code (`ios/`, `macos/`, `android/`, `windows/`) and the iOS companion Shortcut were not reviewed. They may contact other hosts.
2. The Google and Cloudflare DNS-over-HTTPS addresses come from a library (`basic_utils` 5.8.2), not from our code. A library upgrade could change them.
3. Worth a decision before publishing: the home-screen Check My Connection card, Network Quality's live monitor and the Cloud apps panel all start without a tap. That is by design, but this page should say it plainly, as it does above.
4. The ISP lookups to `ipinfo.io` and `get.geojs.io` identify the app in their user agent as `WLANProsToolbox/1.0 (+https://wlanpros.com)` (`lib/services/network/json_http_client.dart:90`). That names the app, not you.
