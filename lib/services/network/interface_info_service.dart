// InterfaceInfoService — reads the device's local network state.
//
// Surfaces: per-interface IPv4/IPv6 addresses, interface name + type, and
// (where the platform exposes them) gateway, Wi-Fi SSID/BSSID, the interface
// hardware (MAC) address, and the active interface's IP.
//
// DATA SOURCES (after the Batch-1 enrichment):
//   * Wi-Fi-link IDENTITY (SSID, BSSID, interface name, hardware/MAC address)
//     now comes from the native `ConnectedAp` subsystem (WifiInfoSourceResolver
//     → MacWifiInfoAdapter on macOS / WiFiDetailsBridge on iOS), the SAME source
//     the Wi-Fi Information tool uses. `network_info_plus` returned null SSID/
//     BSSID on iOS/macOS, which surfaced as a misleading "not available" — the
//     native subsystem reads them correctly and carries the honest macOS
//     Location gate. The read is the no-prompt path (mirrors the consumer
//     connection check): it never pops a Location prompt; an ungranted macOS
//     Location simply yields null SSID/BSSID and [WifiLinkInfo.locationNeeded].
//   * Wi-Fi-link ADDRESSING (gateway, subnet mask, Wi-Fi IPv4/IPv6) stays on
//     `network_info_plus` — `dart:io` does not expose it and the native AP
//     subsystem is RF/identity-only.
//   * The per-interface address table stays on `dart:io NetworkInterface`.
//
// This service is the foundation the brief calls out (§ "Interface
// Information ... also displays the device's own IP, which future iperf-server
// work needs"). Ping/Traceroute and the iperf server screen will read
// `primaryIPv4` from here rather than re-deriving it.
//
// Web safety: this file imports `dart:io`, which does not exist on web. It is
// only ever imported behind a `NetworkSupport.interfaceInfoSupported` guard at
// the UI layer, and the screen uses a conditional import so the web build
// never reaches this code. Nothing here is referenced from a web code path.
//
// Graceful unavailable: every field that a platform cannot provide returns
// null (not 0, not ""), and the UI renders "Not available on this platform"
// for nulls (brief §10).

import 'dart:async';
import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

import 'connected_ap.dart';
import 'connected_ap_cache.dart';
import 'wifi_details_bridge.dart';
import 'wifi_info_adapter.dart';

/// The coarse kind of a network interface, inferred from its OS name. Used to
/// label rows ("Wi-Fi", "Ethernet", "Loopback") rather than show raw `en0`.
enum InterfaceKind { wifi, ethernet, cellular, loopback, vpn, other }

/// A single IP address bound to an interface, with its family.
class InterfaceAddress {
  const InterfaceAddress({required this.ip, required this.isIPv4});

  final String ip;
  final bool isIPv4;
}

/// One network interface and the addresses bound to it.
class NetworkInterfaceInfo {
  const NetworkInterfaceInfo({
    required this.name,
    required this.kind,
    required this.addresses,
  });

  final String name;
  final InterfaceKind kind;
  final List<InterfaceAddress> addresses;

  /// First IPv4 on this interface, or null if it has none.
  String? get firstIPv4 {
    for (final InterfaceAddress a in addresses) {
      if (a.isIPv4) return a.ip;
    }
    return null;
  }
}

/// Wi-Fi-link details. Each field is nullable because platforms (and permission
/// states) differ.
///
/// SOURCES (Batch-1): [ssid], [bssid], [interfaceName], and [hardwareAddress]
/// come from the native `ConnectedAp` subsystem (the same source the Wi-Fi
/// Information tool uses); [gatewayIP], [subnetMask], [wifiIPv4], and [wifiIPv6]
/// come from `network_info_plus`. [locationNeeded] is true on macOS when the
/// network name (SSID/BSSID) is gated behind Location Services that the user has
/// not granted — the honest "needs Location" state the Wi-Fi Information tool
/// already surfaces, mirrored here so the screen explains the empty name rather
/// than implying the platform cannot provide it.
class WifiLinkInfo {
  const WifiLinkInfo({
    this.ssid,
    this.bssid,
    this.gatewayIP,
    this.subnetMask,
    this.wifiIPv4,
    this.wifiIPv6,
    this.interfaceName,
    this.hardwareAddress,
    this.locationNeeded = false,
    this.cachedAt,
  });

  final String? ssid;
  final String? bssid;
  final String? gatewayIP;
  final String? subnetMask;
  final String? wifiIPv4;
  final String? wifiIPv6;

  /// BSD interface name (e.g. "en0") for the Wi-Fi link, from `ConnectedAp`.
  /// Null when the source does not expose it (iOS Shortcut path).
  final String? interfaceName;

  /// Interface hardware (MAC) address, from `ConnectedAp`. Null when the source
  /// does not expose it. On iOS this is unreadable (Apple blocks app reads of
  /// the device Wi-Fi MAC); the UI labels that honestly via
  /// [MacRandomizationClassifier].
  final String? hardwareAddress;

  /// macOS only: true when SSID/BSSID are absent BECAUSE Location Services is
  /// not granted (not because the platform cannot provide them). Drives the
  /// honest "needs Location" hint.
  final bool locationNeeded;

  /// Non-null ONLY when the Wi-Fi IDENTITY (SSID/BSSID/interface/MAC) was served
  /// from the shared [ConnectedApCache] rather than a fresh native/live read —
  /// it is the wall-clock time that cached reading was taken (`updatedAt`). The
  /// UI uses it to surface an honest "as of HH:MM" indicator so a remembered
  /// reading is never presented as a live one (Batch 8 truthfulness fix). A
  /// genuinely fresh macOS CoreWLAN poll or iOS live read leaves this null — only
  /// cache-sourced identity carries an as-of stamp.
  ///
  /// Readings older than [InterfaceInfoService.cacheStaleThreshold] are treated
  /// as effectively cold (the cache is bypassed) so stale identity is never
  /// shown as current, so a non-null [cachedAt] is always within that window.
  final DateTime? cachedAt;

  /// True when the Wi-Fi identity on this snapshot came from the shared cache
  /// (a remembered reading) rather than a fresh native/live read.
  bool get isCacheSourced => cachedAt != null;
}

/// Aggregate snapshot of the device's network state at the moment of read.
class InterfaceInfoSnapshot {
  const InterfaceInfoSnapshot({
    required this.interfaces,
    required this.wifi,
    required this.hostname,
  });

  final List<NetworkInterfaceInfo> interfaces;
  final WifiLinkInfo wifi;
  final String? hostname;

  /// The device's primary routable IPv4 — first non-loopback IPv4 across all
  /// interfaces, preferring the Wi-Fi link IP when known. This is the value
  /// the future iperf-server screen displays as "give this IP to the client".
  String? get primaryIPv4 {
    if (wifi.wifiIPv4 != null && wifi.wifiIPv4!.isNotEmpty) {
      return wifi.wifiIPv4;
    }
    for (final NetworkInterfaceInfo iface in interfaces) {
      if (iface.kind == InterfaceKind.loopback) continue;
      final String? v4 = iface.firstIPv4;
      if (v4 != null) return v4;
    }
    return null;
  }
}

/// Reads the connected AP's identity from the native Wi-Fi subsystem WITHOUT
/// surfacing any OS prompt. Returns null when there is no reading (not connected,
/// channel error, or — on macOS — Location not granted, in which case the name
/// fields come back null and the gate is reported separately).
///
/// [authorized] reports the CURRENT macOS Location authorization (no prompt), so
/// the caller can distinguish "name absent because Location is off" from "name
/// absent for some other reason" and show the honest hint.
typedef ConnectedApRead = Future<({ConnectedAp? ap, bool authorized})>
    Function();

/// Reads local interface + Wi-Fi state. Pure I/O, no UI — unit-testable by
/// injecting a fake [NetworkInfo], a fake interface lister, and a fake
/// connected-AP reader.
class InterfaceInfoService {
  InterfaceInfoService({
    NetworkInfo? networkInfo,
    Future<List<NetworkInterface>> Function()? interfaceLister,
    ConnectedApRead? connectedApReader,
    ConnectedApCache? connectedApCache,
    DateTime Function()? now,
  })  : _networkInfo = networkInfo ?? NetworkInfo(),
        _interfaceLister = interfaceLister ?? _defaultLister,
        _cache = connectedApCache ?? ConnectedApCache.instance,
        _readConnectedAp = connectedApReader ?? _defaultConnectedApRead,
        _now = now ?? DateTime.now;

  final NetworkInfo _networkInfo;
  final Future<List<NetworkInterface>> Function() _interfaceLister;
  final ConnectedApCache _cache;
  final ConnectedApRead _readConnectedAp;

  /// Wall-clock source, injectable in tests so cache-staleness can be exercised
  /// deterministically without sleeping.
  final DateTime Function() _now;

  /// A cached Wi-Fi identity older than this is treated as effectively COLD: the
  /// service bypasses the cache and falls through to the per-platform read,
  /// rather than presenting a remembered reading as the current network. After
  /// an AP switch the cached SSID/BSSID belong to the PREVIOUS network, so a
  /// few-minute ceiling bounds how long a remembered identity is trusted. Within
  /// the window the cache is still served, but stamped with [WifiLinkInfo.cachedAt]
  /// so the UI shows an honest "as of HH:MM" rather than implying it is live.
  static const Duration cacheStaleThreshold = Duration(minutes: 5);

  static Future<List<NetworkInterface>> _defaultLister() {
    return NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: true,
      type: InternetAddressType.any,
    );
  }

  /// Default connected-AP read — the no-prompt path that mirrors the consumer
  /// connection check. macOS: read the CoreWLAN snapshot via [MacWifiInfoAdapter]
  /// (its [WifiInfoAdapter.fetch] never pops a Location prompt; an ungranted
  /// Location simply yields null SSID/BSSID) and report current authorization so
  /// the gate can be shown. iOS: read the last Shortcut payload via
  /// [WiFiDetailsBridge.readLatest]. Other platforms: no reading.
  static Future<({ConnectedAp? ap, bool authorized})>
      _defaultConnectedApRead() async {
    final WifiInfoSource source = WifiInfoSourceResolver.resolve();
    switch (source) {
      case WifiInfoSource.macosCoreWlan:
      case WifiInfoSource.androidWifiManager:
      case WifiInfoSource.windowsNativeWifi:
        // All three snapshot sources use a [WifiInfoAdapter]; pick the
        // platform's. None pops a prompt here — Windows needs no Location grant
        // at all, and an ungranted macOS/Android Location simply yields null
        // SSID/BSSID while currentNameAuthorization reports the gate state
        // (always authorized on Windows).
        final WifiInfoAdapter adapter = switch (source) {
          WifiInfoSource.androidWifiManager => AndroidWifiInfoAdapter(),
          WifiInfoSource.windowsNativeWifi => WindowsWifiInfoAdapter(),
          _ => MacWifiInfoAdapter(),
        };
        try {
          final ConnectedAp ap = await adapter.fetch().timeout(
                const Duration(seconds: 5),
                onTimeout: () =>
                    throw TimeoutException('Wi-Fi link read timed out'),
              );
          final bool authorized = await adapter.currentNameAuthorization();
          return (ap: ap, authorized: authorized);
        } catch (_) {
          // Read failed; still report whether Location is authorized so the gate
          // hint stays accurate. Swallow any error from that probe too.
          bool authorized = false;
          try {
            authorized = await adapter.currentNameAuthorization();
          } catch (_) {/* leave false */}
          return (ap: null, authorized: authorized);
        }
      case WifiInfoSource.iosShortcuts:
        try {
          final WiFiDetailsBridge bridge = WiFiDetailsBridge();
          final details = await bridge.readLatest();
          return (
            ap: details == null ? null : ConnectedAp.fromWifiDetails(details),
            // iOS has no in-app Location gate for this path.
            authorized: true,
          );
        } catch (_) {
          return (ap: null, authorized: true);
        }
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        return (ap: null, authorized: true);
    }
  }

  /// Take a snapshot. Each sub-read is independently guarded so one failing
  /// platform call (e.g. SSID denied) never blanks the whole screen — that
  /// field comes back null and the rest still render.
  Future<InterfaceInfoSnapshot> read() async {
    final List<NetworkInterfaceInfo> interfaces = await _readInterfaces();
    final WifiLinkInfo wifi = await _readWifi();
    final String? hostname = _safeHostname();

    return InterfaceInfoSnapshot(
      interfaces: interfaces,
      wifi: wifi,
      hostname: hostname,
    );
  }

  Future<List<NetworkInterfaceInfo>> _readInterfaces() async {
    final List<NetworkInterface> raw;
    try {
      raw = await _interfaceLister();
    } on Object {
      return const <NetworkInterfaceInfo>[];
    }

    return raw.map((NetworkInterface iface) {
      final List<InterfaceAddress> addrs = iface.addresses
          .map(
            (InternetAddress a) => InterfaceAddress(
              ip: a.address,
              isIPv4: a.type == InternetAddressType.IPv4,
            ),
          )
          .toList(growable: false);
      return NetworkInterfaceInfo(
        name: iface.name,
        kind: classifyInterface(iface.name),
        addresses: addrs,
      );
    }).toList(growable: false);
  }

  Future<WifiLinkInfo> _readWifi() async {
    // ADDRESSING from network_info_plus (the native AP subsystem is identity/RF
    // only). Each call is wrapped: a denied permission or unsupported platform
    // throws a PlatformException; we swallow it to null rather than fail.
    final String? gateway =
        await _tryStr(() => _networkInfo.getWifiGatewayIP());
    final String? submask =
        await _tryStr(() => _networkInfo.getWifiSubmask());
    final String? ipv4 = await _tryStr(() => _networkInfo.getWifiIP());
    final String? ipv6 = await _tryStr(() => _networkInfo.getWifiIPv6());

    // IDENTITY (SSID/BSSID/interface/MAC) from the native ConnectedAp subsystem.
    // network_info_plus returns null SSID/BSSID on iOS/macOS — the misleading
    // "not available" Keith flagged — so the identity fields are re-sourced here.
    //
    // WARM PATH FIRST (Batch 8, item 1). If any tool (the Wi-Fi Information tool)
    // has already obtained a reading this session, the shared cache holds it, so
    // Interface Info shows the same SSID/BSSID WITHOUT re-running the iOS
    // Shortcut. A cached reading came from a successful read, so authorization is
    // implied (the macOS Location gate already passed when it was cached). Only
    // when the cache is cold do we fall to the per-platform no-prompt read below
    // (which, on iOS, is just `readLatest()` — still no Shortcut bounce).
    //
    // STALENESS GATE (Batch 8, truthfulness fix). The cache is sticky on purpose,
    // but a remembered identity is only trustworthy for a while: after an AP
    // switch the cached SSID/BSSID belong to the PREVIOUS network. So the warm
    // path is taken ONLY when the cached reading is within [cacheStaleThreshold].
    // A reading older than that is treated as effectively cold and we fall
    // through to a fresh per-platform read instead of presenting stale identity
    // as current. When the warm path IS taken, [cachedAt] stamps the reading so
    // the UI surfaces an honest "as of HH:MM" — a fresh native/live read leaves
    // it null and gets no as-of treatment.
    ({ConnectedAp? ap, bool authorized}) read;
    DateTime? cachedAt;
    final ConnectedAp? cached = _cache.latest;
    final DateTime? cacheTime = _cache.updatedAt;
    final bool cacheFresh = cached != null &&
        cached.hasAnyData &&
        cacheTime != null &&
        _now().difference(cacheTime) < cacheStaleThreshold;
    if (cacheFresh) {
      read = (ap: cached, authorized: true);
      cachedAt = cacheTime;
    } else {
      try {
        read = await _readConnectedAp();
      } catch (_) {
        read = (ap: null, authorized: true);
      }
    }
    final ConnectedAp? ap = read.ap;

    // macOS: SSID/BSSID need Location. When neither is present AND Location is
    // not authorized, that is the honest "needs Location" state — not a platform
    // limitation. (iOS reports authorized=true, so this never trips there.)
    final bool nameMissing =
        (ap?.ssid == null || ap!.ssid!.trim().isEmpty) &&
            (ap?.bssid == null || ap!.bssid!.trim().isEmpty);
    final bool locationNeeded = nameMissing && !read.authorized;

    return WifiLinkInfo(
      ssid: _cleanSsid(ap?.ssid),
      bssid: _blankToNull(ap?.bssid),
      gatewayIP: gateway,
      subnetMask: submask,
      wifiIPv4: ipv4,
      wifiIPv6: ipv6,
      interfaceName: _blankToNull(ap?.interfaceName),
      hardwareAddress: _blankToNull(ap?.hardwareAddress),
      locationNeeded: locationNeeded,
      // Only set when the identity above came from the warm cache path; null for
      // a fresh native/live read, which gets no "as of" treatment.
      cachedAt: cachedAt,
    );
  }

  static String? _blankToNull(String? v) {
    if (v == null) return null;
    final String t = v.trim();
    return t.isEmpty ? null : t;
  }

  static Future<String?> _tryStr(Future<String?> Function() fn) async {
    try {
      final String? v = await fn();
      if (v == null) return null;
      final String t = v.trim();
      return t.isEmpty ? null : t;
    } on Object {
      return null;
    }
  }

  static String? _cleanSsid(String? ssid) {
    if (ssid == null) return null;
    String s = ssid.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1).trim();
    }
    // Some platforms return a placeholder when permission is missing.
    if (s.isEmpty || s == '<unknown ssid>') return null;
    return s;
  }

  String? _safeHostname() {
    try {
      return normalizeHostname(Platform.localHostname);
    } on Object {
      return null;
    }
  }

  /// BF5-4: normalize the OS-reported hostname. On iOS, `Platform.localHostname`
  /// returns the loopback name "localhost" (the device's real hostname is not
  /// exposed to apps). Showing "localhost" reads as a bug, so any loopback-style
  /// name collapses to null → the UI renders the honest "Not available on this
  /// platform" treatment (ValueRow). On macOS / Linux / Windows the real machine
  /// hostname is legitimately available and passes through unchanged. Static and
  /// pure so it is unit-testable without a Platform mock.
  static String? normalizeHostname(String? raw) {
    if (raw == null) return null;
    final String h = raw.trim();
    if (h.isEmpty) return null;
    final String lower = h.toLowerCase();
    if (lower == 'localhost' ||
        lower.startsWith('localhost.') ||
        lower == 'ip6-localhost' ||
        lower == 'loopback') {
      return null;
    }
    return h;
  }

  /// Best-effort interface-kind inference from the OS interface name. Names are
  /// not standardized across platforms, so this is heuristic and intentionally
  /// conservative — anything unrecognized falls to [InterfaceKind.other].
  static InterfaceKind classifyInterface(String name) {
    final String n = name.toLowerCase();
    if (n.startsWith('lo') || n == 'lo0' || n.contains('loopback')) {
      return InterfaceKind.loopback;
    }
    if (n.startsWith('en') ||
        n.startsWith('wl') ||
        n.contains('wi-fi') ||
        n.contains('wifi') ||
        n.contains('wireless')) {
      // macOS `en0` is usually Wi-Fi; Linux `wlan*`/`wl*` is Wi-Fi.
      if (n.startsWith('wl') || n.contains('wi') || n.contains('wireless')) {
        return InterfaceKind.wifi;
      }
      // `en*` on macOS is ambiguous (en0 Wi-Fi, en1+ Ethernet/Thunderbolt).
      // Label as Wi-Fi for en0, Ethernet otherwise — heuristic only.
      return name == 'en0' ? InterfaceKind.wifi : InterfaceKind.ethernet;
    }
    if (n.startsWith('eth') || n.contains('ethernet')) {
      return InterfaceKind.ethernet;
    }
    if (n.startsWith('rmnet') ||
        n.startsWith('pdp') ||
        n.startsWith('ccmni') ||
        n.contains('cellular')) {
      return InterfaceKind.cellular;
    }
    if (n.startsWith('utun') ||
        n.startsWith('tun') ||
        n.startsWith('tap') ||
        n.startsWith('ppp') ||
        n.contains('vpn')) {
      return InterfaceKind.vpn;
    }
    return InterfaceKind.other;
  }
}
