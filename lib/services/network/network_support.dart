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

  /// DNS Lookup support. Tied to [activeNetworkSupported] per the §15 product
  /// decision (DoH is technically web-capable, but the network category is
  /// native-only for a coherent download story). Flip this independently if
  /// that decision changes.
  static bool get dnsLookupSupported => !kIsWeb;

  /// Interface Information support.
  static bool get interfaceInfoSupported => !kIsWeb;

  /// Port Scan support.
  static bool get portScanSupported => !kIsWeb;

  /// Ping support. Implemented as a TCP-handshake RTT probe (see
  /// PingService) — needs no raw socket and works on every native platform,
  /// so the gate is the same `!kIsWeb` as the other socket tools.
  static bool get pingSupported => !kIsWeb;

  /// Traceroute support. The *screen* is reachable off-web on every native
  /// platform (so the tool catalog can route to it), but the genuine
  /// hop-by-hop run only works on desktop where the OS traceroute binary can
  /// be spawned. The per-platform desktop-vs-mobile verdict is decided inside
  /// TracerouteService (`isSupportedPlatform`) and surfaced in the UI; this
  /// flag only excludes web, where no part of it can run.
  static bool get tracerouteSupported => !kIsWeb;

  /// The reason active tools are unavailable, or null when they are available.
  static NetworkUnavailableReason? get unavailableReason =>
      kIsWeb ? NetworkUnavailableReason.web : null;
}
