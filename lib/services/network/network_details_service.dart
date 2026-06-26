// NetworkDetailsService — reads the device's local network ADDRESSING for the
// Test My Connection report (Keith #5): local IP, subnet mask, default gateway,
// and the honest unavailable state for DHCP server, DNS server(s), and VLAN.
//
// WHAT IS OBTAINABLE, AND HOW (GL-005 / GL-008):
//
//   * Local IP, subnet mask, default gateway — read from `network_info_plus`
//     (`getWifiIP` / `getWifiSubmask` / `getWifiGatewayIP`). That plugin is a
//     NATIVE method-channel call, NOT a subprocess, so it is safe inside the
//     sandboxed macOS App Store build (where `Process.run` of ifconfig/route/
//     scutil is DENIED by the App Sandbox — see TracerouteService.isLaunchable)
//     and works on iOS, where there is no shell. Local IP also falls back to
//     `NetworkInterface.list` (the same dart:io source Interface Information
//     uses) when the plugin returns null. Each field is nullable; whatever the
//     platform returns is what shows — a null renders "Not available", never a
//     fabricated address.
//
//   * DHCP server, DNS server(s) — platform-split (GL-005 / GL-008):
//
//       - iOS / macOS: NOT reachable. A sandboxed iOS app has no API for either;
//         on macOS reading them needs a CLI (`ipconfig getpacket`, `scutil
//         --dns`) the App Sandbox blocks (GL-008 Constraint 1). `network_info_
//         plus` exposes neither. The Shortcuts bridge surfaces only RF metrics
//         (SSID/BSSID/RSSI/Noise/Channel/Std/Rx/Tx — see WiFiDetails). So both
//         are reported as the honest unavailable state with the precise reason
//         "Not available on this device" — never guessed.
//
//       - Android: BOTH ARE available and ARE read. The DHCP server identifier
//         (option 54) comes from `WifiManager.getDhcpInfo().serverAddress`; the
//         resolver list from the modern `ConnectivityManager.getLinkProperties()
//         .getDnsServers()` (with `DhcpInfo.dns1/dns2` as the fallback). These
//         flow over the `com.wlanpros.toolbox/network_addressing` method channel
//         (MainActivity.kt). A 0 / 0.0.0.0 / empty native read still renders the
//         honest unavailable state ("Not reported for this network") — never a
//         placeholder. This is why the model carries instance-level reason
//         strings: the precise reason differs by platform.
//
//   * VLAN tag — an 802.1Q tag is stripped by the switch/AP before the frame
//     reaches the endpoint's OS, so an endpoint application CANNOT observe the
//     VLAN it is on. There is no real per-platform way to detect it. It is
//     reported as "Not visible to endpoint devices" so the field is honest
//     about WHY rather than silently omitted (GL-005).
//
// Web safety: this file imports `dart:io`. It is only ever constructed behind
// the same `NetworkSupport` gate the rest of Test My Connection sits behind, so
// the web build never reaches it.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';

/// The device's local network addressing snapshot for the connection report.
///
/// Each obtainable field is nullable: a null is the honest "not available"
/// state (never a fabricated value). [dhcpServer] and [dnsServers] are read for
/// real on Android (where the OS exposes them) and stay null/empty on iOS/macOS
/// (where a sandboxed app genuinely cannot read them). [vlanTag] is always null
/// on every platform — see [vlanReason]. The [dhcpReason] / [dnsReason] strings
/// are instance-level because the precise honest reason differs by platform.
class NetworkDetails {
  const NetworkDetails({
    this.localIp,
    this.subnetMask,
    this.gateway,
    this.dhcpServer,
    this.dnsServers = const <String>[],
    this.dhcpReason = defaultUnavailableReason,
    this.dnsReason = defaultUnavailableReason,
  });

  /// The honest empty snapshot — every obtainable field null. Used when the
  /// read fails entirely (offline / unsupported platform) or while in flight.
  /// Carries the platform-agnostic default reason; the live snapshot the service
  /// returns carries the precise per-platform reason.
  static const NetworkDetails empty = NetworkDetails();

  /// Local IPv4 address of the active interface, or null when unavailable.
  final String? localIp;

  /// Subnet mask of the active interface, or null when the platform did not
  /// expose it (iOS frequently returns null here — reported honestly, never
  /// guessed).
  final String? subnetMask;

  /// Default gateway IPv4, or null when the platform did not expose it.
  final String? gateway;

  /// Configured DNS server(s). Populated on Android from the active network's
  /// resolver list (ConnectivityManager link properties, with DhcpInfo.dns1/dns2
  /// as fallback). Empty on iOS/macOS — neither exposes them to a sandboxed app,
  /// so the UI shows [dnsReason]. Empty on Android too means "none reported for
  /// this network" (honest, never a guessed resolver).
  final List<String> dnsServers;

  /// DHCP server identifier (option 54). Read for real on Android via
  /// WifiManager.getDhcpInfo().serverAddress. Null on iOS/macOS (reading it needs
  /// `ipconfig getpacket`, sandbox-blocked, or an API iOS does not provide), and
  /// null on Android when there is no DHCP lease / no active link. A null renders
  /// [dhcpReason], never a fabricated address.
  final String? dhcpServer;

  /// 802.1Q VLAN tag. Always null on every platform: VLAN tags are stripped
  /// before traffic reaches the endpoint OS, so an endpoint app cannot observe
  /// one. See [vlanReason]. Left as a getter precisely because it is never read.
  String? get vlanTag => null;

  /// The honest reason the DHCP server is not shown, for THIS snapshot's
  /// platform. iOS/macOS: "Not available on this device". Android (when the read
  /// legitimately returns nothing): "Not reported for this network".
  final String dhcpReason;

  /// The honest reason the DNS server(s) are not shown, for THIS snapshot's
  /// platform. Same platform split as [dhcpReason].
  final String dnsReason;

  /// The default reason used on platforms where the field is structurally
  /// unavailable to a sandboxed app (iOS / macOS), and the safe transient
  /// default for [empty].
  static const String defaultUnavailableReason = 'Not available on this device';

  /// The honest reason on Android when the value genuinely could not be read for
  /// the current network (e.g. no DHCP lease, wired, or no active link). The
  /// data IS on the device in general, so "Not available on this device" would
  /// be inaccurate here — this says precisely what is true.
  static const String androidUnreadReason = 'Not reported for this network';

  /// The honest reason a VLAN tag is not shown — it is a true platform fact,
  /// not a missing read: the tag is stripped before the endpoint sees the frame.
  /// This is platform-agnostic, so it stays a static constant.
  static const String vlanReason = 'Not visible to endpoint devices';
}

/// Reads the device's local addressing. Pure I/O, no UI. The [networkInfo],
/// [interfaceLister], [isAndroid], and [androidAddressingReader] seams keep it
/// unit-testable without a live network or a real platform channel.
class NetworkDetailsService {
  NetworkDetailsService({
    NetworkInfo? networkInfo,
    Future<List<NetworkInterface>> Function()? interfaceLister,
    bool? isAndroid,
    Future<Map<Object?, Object?>?> Function()? androidAddressingReader,
  })  : _networkInfo = networkInfo ?? NetworkInfo(),
        _interfaceLister = interfaceLister ?? _defaultLister,
        _isAndroid = isAndroid ?? Platform.isAndroid,
        _androidAddressingReader =
            androidAddressingReader ?? _defaultAndroidAddressingReader;

  final NetworkInfo _networkInfo;
  final Future<List<NetworkInterface>> Function() _interfaceLister;
  final bool _isAndroid;
  final Future<Map<Object?, Object?>?> Function() _androidAddressingReader;

  /// The Android-only native channel that surfaces the DHCP server identifier
  /// and the resolver list. Has NO handler on iOS/macOS/web — a call there
  /// throws MissingPluginException, which [read] swallows to the honest
  /// unavailable state. Mirrors the app's other native channels.
  static const MethodChannel _androidChannel =
      MethodChannel('com.wlanpros.toolbox/network_addressing');

  static Future<List<NetworkInterface>> _defaultLister() {
    return NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
  }

  static Future<Map<Object?, Object?>?> _defaultAndroidAddressingReader() {
    return _androidChannel
        .invokeMethod<Map<Object?, Object?>>('getNetworkAddressing');
  }

  /// Take a snapshot of the obtainable local addressing. Each sub-read is
  /// independently guarded so one failing platform call never blanks the rest;
  /// a field that cannot be read comes back null (honest "not available").
  /// Never throws to the caller.
  Future<NetworkDetails> read() async {
    final String? wifiIp = await _tryStr(() => _networkInfo.getWifiIP());
    final String? submask = await _tryStr(() => _networkInfo.getWifiSubmask());
    final String? gateway =
        await _tryStr(() => _networkInfo.getWifiGatewayIP());

    // Local-IP fallback: when the Wi-Fi plugin returns null (e.g. wired, or a
    // platform that does not report the Wi-Fi IP), use the first non-loopback
    // IPv4 from dart:io — the SAME source Interface Information uses.
    final String? localIp = wifiIp ?? await _firstNonLoopbackIPv4();

    // DHCP server + DNS servers: REAL on Android (the OS exposes them); left
    // null/empty with the iOS/macOS reason elsewhere. The Android read is fully
    // guarded — a thrown/missing channel falls back to the honest unavailable
    // state, never a fabricated value (GL-005).
    String? dhcpServer;
    List<String> dnsServers = const <String>[];
    String dhcpReason = NetworkDetails.defaultUnavailableReason;
    String dnsReason = NetworkDetails.defaultUnavailableReason;

    if (_isAndroid) {
      // On Android the data IS on the device; the precise reason for a null read
      // is "not reported for this network", not "not available on this device".
      dhcpReason = NetworkDetails.androidUnreadReason;
      dnsReason = NetworkDetails.androidUnreadReason;
      final (String?, List<String>) android = await _readAndroidAddressing();
      dhcpServer = android.$1;
      dnsServers = android.$2;
    }

    return NetworkDetails(
      localIp: localIp,
      subnetMask: submask,
      gateway: gateway,
      dhcpServer: dhcpServer,
      dnsServers: dnsServers,
      dhcpReason: dhcpReason,
      dnsReason: dnsReason,
    );
  }

  /// Reads the DHCP server + DNS list from the Android native channel and
  /// normalizes the payload. Returns `(null, const [])` on any failure (missing
  /// channel, platform exception, malformed payload) — the honest unavailable
  /// state, never a guess. A blank / empty DHCP string becomes null; the DNS
  /// list is trimmed, de-duped, and stripped of empties.
  Future<(String?, List<String>)> _readAndroidAddressing() async {
    try {
      final Map<Object?, Object?>? map = await _androidAddressingReader();
      if (map == null) return (null, const <String>[]);

      final Object? rawDhcp = map['dhcpServer'];
      String? dhcp;
      if (rawDhcp is String) {
        final String t = rawDhcp.trim();
        if (t.isNotEmpty) dhcp = t;
      }

      final Object? rawDns = map['dnsServers'];
      final List<String> dns = <String>[];
      if (rawDns is List) {
        for (final Object? e in rawDns) {
          if (e is String) {
            // Canonicalize defensively: the native side already emits compressed
            // IPv6, but normalize here too (idempotent) so a long-form address
            // from any source never reaches the UI. De-dupe AFTER canonicalizing
            // so the compressed and expanded forms of one resolver collapse.
            final String? c = canonicalizeDnsAddress(e);
            if (c != null && !dns.contains(c)) dns.add(c);
          }
        }
      }

      return (dhcp, List<String>.unmodifiable(dns));
    } on MissingPluginException {
      // No handler (non-Android, or runner not yet built). Honest unavailable.
      return (null, const <String>[]);
    } on PlatformException catch (e) {
      debugPrint('NetworkDetailsService.android addressing failed: $e');
      return (null, const <String>[]);
    } on Object {
      // Any other malformed-payload / unexpected error → honest unavailable.
      return (null, const <String>[]);
    }
  }

  Future<String?> _firstNonLoopbackIPv4() async {
    try {
      final List<NetworkInterface> ifaces = await _interfaceLister();
      for (final NetworkInterface iface in ifaces) {
        for (final InternetAddress a in iface.addresses) {
          if (a.type == InternetAddressType.IPv4 && !a.isLoopback) {
            return a.address;
          }
        }
      }
    } catch (_) {
      // Swallow — return null (honest "not available").
    }
    return null;
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
}

/// Canonicalizes a DNS resolver address for display (GL-005: honest, never
/// fabricated). IPv4 passes through trimmed. IPv6 is rendered in the RFC 5952
/// canonical compressed form — lowercase, leading zeros stripped, the longest
/// run of zero hextets (>= 2, leftmost on a tie) collapsed to `::` — so a
/// long-form resolver can never overflow the narrow value column. Idempotent:
/// an already-compressed address returns unchanged. Returns null for an empty /
/// unspecified (`0.0.0.0` / `::`) address; an unparseable-but-non-empty string
/// is returned lowercased rather than dropped (never lose a real value).
@visibleForTesting
String? canonicalizeDnsAddress(String raw) {
  String s = raw.trim();
  if (s.isEmpty) return null;
  // Strip any IPv6 zone/scope id (e.g. "fe80::1%wlan0").
  final int pct = s.indexOf('%');
  if (pct >= 0) s = s.substring(0, pct);
  if (s.isEmpty) return null;

  // No colon → IPv4 (or a hostname we leave verbatim). Drop the unspecified.
  if (!s.contains(':')) {
    return s == '0.0.0.0' ? null : s;
  }

  // IPv6 with an embedded IPv4 tail (IPv4-mapped, e.g. "::ffff:1.2.3.4") is rare
  // for a resolver; leave it lowercased rather than risk a wrong re-encoding.
  if (s.contains('.')) {
    final String low = s.toLowerCase();
    return low == '::' ? null : low;
  }

  final List<int>? groups = _parseIpv6Groups(s);
  if (groups == null) {
    final String low = s.toLowerCase();
    return low == '::' ? null : low;
  }
  if (groups.every((int g) => g == 0)) return null; // unspecified "::"
  return _compressIpv6Groups(groups);
}

/// Parses an IPv6 string (full or `::`-compressed, no embedded IPv4) into its 8
/// 16-bit groups, or null if it is malformed.
List<int>? _parseIpv6Groups(String s) {
  if (s.contains('::')) {
    final List<String> halves = s.split('::');
    if (halves.length != 2) return null; // more than one "::" is illegal
    final List<String> head =
        halves[0].isEmpty ? <String>[] : halves[0].split(':');
    final List<String> tail =
        halves[1].isEmpty ? <String>[] : halves[1].split(':');
    final int fill = 8 - head.length - tail.length;
    if (fill < 0) return null;
    return _hextetsToInts(<String>[
      ...head,
      for (int i = 0; i < fill; i++) '0',
      ...tail,
    ]);
  }
  return _hextetsToInts(s.split(':'));
}

List<int>? _hextetsToInts(List<String> parts) {
  if (parts.length != 8) return null;
  final List<int> out = <int>[];
  for (final String p in parts) {
    if (p.isEmpty || p.length > 4) return null;
    final int? v = int.tryParse(p, radix: 16);
    if (v == null || v < 0 || v > 0xffff) return null;
    out.add(v);
  }
  return out;
}

/// Renders 8 IPv6 groups to the RFC 5952 canonical compressed string.
String _compressIpv6Groups(List<int> groups) {
  int bestStart = -1;
  int bestLen = 0;
  int curStart = -1;
  int curLen = 0;
  for (int i = 0; i < 8; i++) {
    if (groups[i] == 0) {
      if (curStart == -1) curStart = i;
      curLen++;
      if (curLen > bestLen) {
        bestLen = curLen;
        bestStart = curStart;
      }
    } else {
      curStart = -1;
      curLen = 0;
    }
  }
  if (bestLen < 2) bestStart = -1;

  final StringBuffer sb = StringBuffer();
  int i = 0;
  while (i < 8) {
    if (i == bestStart) {
      sb.write('::');
      i = bestStart + bestLen;
    } else {
      sb.write(groups[i].toRadixString(16));
      // Emit a separator unless the next index opens the "::" gap (which carries
      // its own colons) or this is the final hextet.
      if (i < 7 && (i + 1) != bestStart) sb.write(':');
      i++;
    }
  }
  return sb.toString();
}
