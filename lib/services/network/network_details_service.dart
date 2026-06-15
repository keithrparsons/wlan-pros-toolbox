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
//   * DHCP server, DNS server(s) — NOT exposed by `network_info_plus` and NOT
//     reachable on either target without spawning a CLI (`ipconfig getpacket`,
//     `scutil --dns`), which the macOS App Sandbox blocks (GL-008 Constraint 1),
//     or shipping a bespoke native plugin. On iOS a sandboxed app cannot read
//     them at all, and the existing Shortcuts bridge surfaces only RF metrics
//     (SSID/BSSID/RSSI/Noise/Channel/Std/Rx/Tx — see WiFiDetails), none of these
//     addressing fields. So both are reported as the honest unavailable state
//     with a precise reason — never guessed.
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

import 'package:network_info_plus/network_info_plus.dart';

/// The device's local network addressing snapshot for the connection report.
///
/// Each obtainable field is nullable: a null is the honest "not available"
/// state (never a fabricated value). [dhcpServer], [dnsServers], and [vlanTag]
/// are intentionally absent on both targets — see [dhcpReason] / [dnsReason] /
/// [vlanReason] for the precise, honest explanation each carries.
class NetworkDetails {
  const NetworkDetails({
    this.localIp,
    this.subnetMask,
    this.gateway,
    this.dnsServers = const <String>[],
  });

  /// The honest empty snapshot — every obtainable field null. Used when the
  /// read fails entirely (offline / unsupported platform).
  static const NetworkDetails empty = NetworkDetails();

  /// Local IPv4 address of the active interface, or null when unavailable.
  final String? localIp;

  /// Subnet mask of the active interface, or null when the platform did not
  /// expose it (iOS frequently returns null here — reported honestly, never
  /// guessed).
  final String? subnetMask;

  /// Default gateway IPv4, or null when the platform did not expose it.
  final String? gateway;

  /// Configured DNS server(s). Empty on every current target: neither macOS
  /// (sandboxed, no `scutil --dns` subprocess) nor iOS (sandboxed, no API)
  /// exposes them to the app. Kept as a typed field so a future native plugin
  /// can populate it without a signature change; today it is always empty and
  /// the UI shows [dnsReason].
  final List<String> dnsServers;

  /// DHCP server identifier (option 54). Always null on every current target —
  /// reading it needs `ipconfig getpacket` (macOS, sandbox-blocked) or an API
  /// iOS does not provide. See [dhcpReason].
  String? get dhcpServer => null;

  /// 802.1Q VLAN tag. Always null: VLAN tags are stripped before traffic
  /// reaches the endpoint OS, so an endpoint app cannot observe one. See
  /// [vlanReason].
  String? get vlanTag => null;

  /// The honest reason the DHCP server is not shown.
  static const String dhcpReason = 'Not available on this device';

  /// The honest reason the DNS server(s) are not shown.
  static const String dnsReason = 'Not available on this device';

  /// The honest reason a VLAN tag is not shown — it is a true platform fact,
  /// not a missing read: the tag is stripped before the endpoint sees the frame.
  static const String vlanReason = 'Not visible to endpoint devices';
}

/// Reads the device's local addressing. Pure I/O, no UI. The [networkInfo] and
/// [interfaceLister] seams keep it unit-testable without a live network.
class NetworkDetailsService {
  NetworkDetailsService({
    NetworkInfo? networkInfo,
    Future<List<NetworkInterface>> Function()? interfaceLister,
  })  : _networkInfo = networkInfo ?? NetworkInfo(),
        _interfaceLister = interfaceLister ?? _defaultLister;

  final NetworkInfo _networkInfo;
  final Future<List<NetworkInterface>> Function() _interfaceLister;

  static Future<List<NetworkInterface>> _defaultLister() {
    return NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
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

    return NetworkDetails(
      localIp: localIp,
      subnetMask: submask,
      gateway: gateway,
    );
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
