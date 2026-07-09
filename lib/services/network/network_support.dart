// Platform-support gate for the active-network services layer.
//
// Single source of truth for "can this device actually run active network
// I/O?" The whole networking suite (Interface Info, DNS Lookup, Port Scan,
// and future Ping/Traceroute work) funnels its availability check through
// here so the answer is computed once and never drifts between tools.
//
// Web is the hard exclusion: browsers cannot open raw/TCP sockets, cannot
// read the device's interface table, and cannot resolve DNS outside an
// HTTPS fetch. Per brief §15 the network tools are HIDDEN on web with a
// "download the native app" prompt — never crashed, never shown broken.
//
// DNS-over-HTTPS is the one exception that *could* run in a browser (it is
// just an HTTPS GET), but the product decision in §15 is to keep the entire
// active-network category native-only for a coherent story, so DoH is gated
// the same way. If that decision is ever revisited, `dnsLookupSupported`
// is the single switch to flip.

import 'package:flutter/foundation.dart' show kIsWeb;

import 'pi_backend.dart';

/// Why a given network capability is unavailable, so the UI can render a
/// precise, non-apologetic message (brief §10 anti-patterns) instead of a
/// zero or a crash.
enum NetworkUnavailableReason {
  /// Running in a browser — raw sockets / interface table not exposed.
  web,

  /// The platform's public API does not surface this datum (e.g. iOS has no
  /// public Wi-Fi RSSI API). Distinct from [web] so copy can be specific.
  platformApiMissing,
}

/// Centralized capability checks for the active-network services.
///
/// All flags are compile-time-ish constants derived from [kIsWeb]; they do no
/// I/O and are safe to read in `build`.
class NetworkSupport {
  NetworkSupport._();

  /// True when the device can run socket-based active network tools
  /// (Interface Info, Port Scan, future Ping/Traceroute). False on web.
  static bool get activeNetworkSupported => !kIsWeb;

  /// DNS Lookup support. Native everywhere; ALSO available on Pi-hosted web,
  /// where the lookup runs ON the Pi via `/toolboxapi/dns` (the catalog id is
  /// `dns-lookup`; the proxy route is `dns`). On Netlify web the Pi backend is
  /// absent so this stays false and the tool keeps the download-the-app
  /// fallback. Off the Pi it remains the §15 native-only DoH decision.
  static bool get dnsLookupSupported => !kIsWeb || PiBackend.available;

  /// Interface Information support.
  ///
  /// Native everywhere; ALSO available on Pi-hosted web, where the device
  /// interface table is read from the Pi via `/toolboxapi/interfaces` (the
  /// browser has no `dart:io` interface table). On Netlify web the Pi backend is
  /// absent so this stays false and the tool keeps the download-the-app fallback.
  static bool get interfaceInfoSupported => !kIsWeb || PiBackend.available;

  /// Network Quality (Test My Connection, `net-quality`) support.
  ///
  /// Native everywhere; ALSO available on Pi-hosted web, where the connection
  /// test runs ON the Pi via `/toolboxapi/conntest` instead of the browser's
  /// (absent) `dart:io` sockets. On Netlify web this stays false and the tool
  /// keeps the download-the-app fallback. Distinct from
  /// [activeNetworkSupported], which stays `!kIsWeb`: only the capabilities with
  /// a live Pi endpoint are re-enabled on web (brief Phase A).
  static bool get netQualitySupported => !kIsWeb || PiBackend.available;

  /// Port Scan support.
  static bool get portScanSupported => !kIsWeb;

  /// Ping support. Native everywhere as a TCP-handshake RTT probe (see
  /// PingService — needs no raw socket, works on every native platform); ALSO
  /// available on Pi-hosted web, where a real ICMP ping runs ON the Pi via
  /// `/toolboxapi/ping`. On Netlify web the Pi backend is absent so this stays
  /// false and the tool keeps the download-the-app fallback.
  static bool get pingSupported => !kIsWeb || PiBackend.available;

  /// Ping Sweep support. Discovers responsive hosts on a subnet by running the
  /// same TCP-handshake probe as Ping across a range of addresses (see
  /// PingSweepService) — no raw socket, no subprocess. Works on every native
  /// platform, so the gate is the same `!kIsWeb` as the other socket tools.
  static bool get pingSweepSupported => !kIsWeb;

  /// SSL/TLS Certificate Inspector support. Needs a raw outbound TLS socket
  /// (`SecureSocket.connect`), which a browser cannot open — and a browser
  /// cannot read an arbitrary peer's certificate either. Native-only; web is
  /// routed to the download-the-app fallback. Same `!kIsWeb` gate as the other
  /// socket tools.
  static bool get sslInspectSupported => !kIsWeb;

  /// HTTP Header Inspector support. Needs to read arbitrary cross-origin
  /// response headers and follow the redirect chain — both blocked in a
  /// browser by CORS. Native-only; web is routed to the fallback.
  static bool get httpHeadersSupported => !kIsWeb;

  /// WHOIS lookup support. Runs over a raw outbound TCP socket to port 43
  /// (`Socket.connect`), the same socket capability the port scanner uses, so
  /// it works on every native platform. A browser cannot open a TCP/43 socket
  /// and the public RDAP endpoints are CORS-blocked, so web is routed to the
  /// download-the-app fallback. Same `!kIsWeb` gate as the other socket tools.
  static bool get whoisSupported => !kIsWeb;

  /// Time Server (NTP) support. Sends a unicast SNTP request over an outbound
  /// UDP datagram (`RawDatagramSocket.bind` + `send`) to a remote time server
  /// on port 123. Browsers cannot open UDP sockets, so web is routed to the
  /// download-the-app fallback. Same `!kIsWeb` gate as the other socket tools.
  /// On native this needs only the outbound network-client capability already
  /// shipped (macOS `network.client`; iOS allows outbound UDP to a remote host
  /// without a local-network grant since the target is not on the LAN).
  static bool get ntpSupported => !kIsWeb;

  /// Wake-on-LAN support. Sends a UDP magic packet via a broadcast datagram
  /// socket (`RawDatagramSocket.bind` + `broadcastEnabled`). Browsers cannot
  /// open UDP sockets or send broadcasts, so web is routed to the fallback.
  /// Same `!kIsWeb` gate as the other socket tools.
  static bool get wakeOnLanSupported => !kIsWeb;

  /// Packet Sender support. Sends a custom payload over TCP (`Socket`) or UDP
  /// (`RawDatagramSocket`) and reads the reply. Browsers cannot open either
  /// socket type, so web is routed to the download-the-app fallback. Same
  /// `!kIsWeb` gate as the other socket tools. (Raw-IP/ICMP framing is out of
  /// scope per TICKET-005 — TCP/UDP only.)
  static bool get packetSenderSupported => !kIsWeb;

  /// BGP / ASN Lookup support. Talks to the RIPEstat Data API over HTTPS via
  /// `dart:io HttpClient`. Because `dart:io` does not exist on web and we have
  /// not verified the API sends permissive CORS, the tool is native-only and
  /// web is routed to the download-the-app fallback. Same `!kIsWeb` gate.
  static bool get bgpAsnSupported => !kIsWeb;

  /// IP Geolocation support. Talks to the ipinfo.io API (geojs.io fallback)
  /// over HTTPS via `dart:io HttpClient`. Native-only for the same reason as
  /// [bgpAsnSupported] (no `dart:io` on web; CORS unverified). Web → fallback.
  static bool get ipGeoSupported => !kIsWeb;

  /// ARP / NDP neighbor discovery support. The *screen* is reachable off-web on
  /// every native platform so the catalog can route to it, but the genuine
  /// per-platform capability (sweep-with-MAC on Linux/Android, sweep-no-MAC on
  /// macOS/Windows, unavailable on iOS) is decided inside ArpNdpService
  /// (`capabilityFor`) and surfaced in the UI. This flag only excludes web,
  /// where raw sockets and the neighbor table are both inaccessible.
  static bool get arpNdpSupported => !kIsWeb;

  /// Real ICMP Ping support. The *screen* is reachable off-web on every native
  /// platform so the catalog can route to it, but the genuine ICMP-echo
  /// capability is per-platform (available on iOS/Android, sandboxed-out on
  /// desktop where the only ICMP path is a subprocess the macOS App Sandbox
  /// blocks). That verdict is decided inside IcmpService (`echoCapability`) and
  /// surfaced in the UI; this flag only excludes web, where no raw-socket /
  /// dart:io path exists at all.
  static bool get icmpPingSupported => !kIsWeb;

  /// Mobile Traceroute (ICMP TTL-walk) support. Same web exclusion; the genuine
  /// per-platform verdict (available on Android, unavailable-no-TimeExceeded on
  /// iOS, sandboxed-out on desktop where the system traceroute is the path) is
  /// decided inside IcmpService (`tracerouteCapability`) and surfaced in the UI.
  static bool get icmpTracerouteSupported => !kIsWeb;

  /// Traceroute support. The *screen* is reachable off-web on every native
  /// platform (so the tool catalog can route to it), but the genuine
  /// hop-by-hop run only works on desktop where the OS traceroute binary can
  /// be spawned. The per-platform desktop-vs-mobile verdict is decided inside
  /// TracerouteService (`isSupportedPlatform`) and surfaced in the UI; this
  /// flag excludes web EXCEPT Pi-hosted web, where the traceroute runs ON the
  /// Pi via `/toolboxapi/traceroute`. On Netlify web the Pi backend is absent
  /// so this stays false and the tool keeps the download-the-app fallback.
  static bool get tracerouteSupported => !kIsWeb || PiBackend.available;

  /// Network Discovery (LAN host + service scan) support. The *screen* is
  /// reachable off-web on every native platform so the catalog can route to it.
  /// The scan uses `dart:io` TCP connect probes (liveness), the in-house mDNS
  /// EventChannel (enrichment), and — desktop-only — a sandbox-safe sysctl ARP
  /// read for MAC/vendor; none of those exist in a browser, so the gate is the
  /// same `!kIsWeb` as the other socket tools. The per-platform MAC/vendor
  /// ceiling (desktop reads it, iOS cannot) is surfaced honestly inside the
  /// screen, not gated here.
  static bool get networkDiscoverySupported => !kIsWeb;

  /// The reason active tools are unavailable, or null when they are available.
  static NetworkUnavailableReason? get unavailableReason =>
      kIsWeb ? NetworkUnavailableReason.web : null;
}
