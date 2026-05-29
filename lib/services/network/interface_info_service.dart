// InterfaceInfoService — reads the device's local network state.
//
// Surfaces: per-interface IPv4/IPv6 addresses, interface name + type, and
// (where the platform exposes them) gateway, DNS servers, Wi-Fi SSID/BSSID,
// and the active interface's IP. Built on `dart:io NetworkInterface` for the
// address/interface table and `network_info_plus` for Wi-Fi-link details
// (SSID/BSSID/gateway) that `dart:io` does not expose.
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

import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

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

/// Wi-Fi-link details from `network_info_plus`. Each field is nullable because
/// platforms (and permission states) differ: iOS needs the wifi-info
/// entitlement + location permission for SSID/BSSID; macOS/Android vary.
class WifiLinkInfo {
  const WifiLinkInfo({
    this.ssid,
    this.bssid,
    this.gatewayIP,
    this.subnetMask,
    this.wifiIPv4,
    this.wifiIPv6,
  });

  final String? ssid;
  final String? bssid;
  final String? gatewayIP;
  final String? subnetMask;
  final String? wifiIPv4;
  final String? wifiIPv6;
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

/// Reads local interface + Wi-Fi state. Pure I/O, no UI — unit-testable by
/// injecting a fake [NetworkInfo] and a fake interface lister.
class InterfaceInfoService {
  InterfaceInfoService({
    NetworkInfo? networkInfo,
    Future<List<NetworkInterface>> Function()? interfaceLister,
  })  : _networkInfo = networkInfo ?? NetworkInfo(),
        _interfaceLister = interfaceLister ?? _defaultLister;

  final NetworkInfo _networkInfo;
  final Future<List<NetworkInterface>> Function() _interfaceLister;

  static Future<List<NetworkInterface>> _defaultLister() {
    return NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: true,
      type: InternetAddressType.any,
    );
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
    // Each call is wrapped: a denied permission or unsupported platform throws
    // a PlatformException; we swallow it to null rather than fail the snapshot.
    final String? ssid = await _tryStr(() => _networkInfo.getWifiName());
    final String? bssid = await _tryStr(() => _networkInfo.getWifiBSSID());
    final String? gateway =
        await _tryStr(() => _networkInfo.getWifiGatewayIP());
    final String? submask =
        await _tryStr(() => _networkInfo.getWifiSubmask());
    final String? ipv4 = await _tryStr(() => _networkInfo.getWifiIP());
    final String? ipv6 = await _tryStr(() => _networkInfo.getWifiIPv6());

    return WifiLinkInfo(
      // network_info_plus brackets some SSIDs with quotes on some platforms;
      // strip them so the displayed value is clean.
      ssid: _cleanSsid(ssid),
      bssid: bssid,
      gatewayIP: gateway,
      subnetMask: submask,
      wifiIPv4: ipv4,
      wifiIPv6: ipv6,
    );
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
    String s = ssid;
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1);
    }
    // Some platforms return a placeholder when permission is missing.
    if (s.isEmpty || s == '<unknown ssid>') return null;
    return s;
  }

  String? _safeHostname() {
    try {
      final String h = Platform.localHostname;
      return h.isEmpty ? null : h;
    } on Object {
      return null;
    }
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
