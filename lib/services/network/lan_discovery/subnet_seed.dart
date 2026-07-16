// Subnet seed derivation — Network Discovery (TICKET-HSD-02).
//
// Derive the local /24-ish host list to scan from the device's own IPv4 + the
// subnet mask, both read from network_info_plus (getWifiIP / getWifiSubmask).
//
// Split into a PURE part (compute the host list from ip + mask strings — fully
// unit-testable, no plugins) and a thin async reader that calls
// network_info_plus. The reader is injectable so the deriver is testable with
// no device.
//
// SCOPE GUARD: a LAN connect-scan is meant for the local /24-class. A user on a
// /16 would expand to 65k hosts, which is not a discovery scan. We cap the host
// list at [kMaxScanHosts] and, for masks wider than /24, scan only the /24 the
// device's own address sits in. This keeps the spike fast and honest.

import 'package:network_info_plus/network_info_plus.dart';

/// Hard cap on hosts the spike will enumerate for a single scan (a /24's worth
/// of usable hosts). Mirrors PingSweepService.maxHosts.
const int kMaxScanHosts = 254;

/// The derived subnet seed: the host IPs to probe plus a human label.
class SubnetSeed {
  const SubnetSeed({
    required this.hosts,
    required this.label,
    required this.selfIp,
    this.gateway,
    this.error,
  });

  /// Concrete IPv4 host addresses to probe, ascending. Empty when [error] set.
  final List<String> hosts;

  /// Human-readable description (e.g. "192.168.1.1–192.168.1.254").
  final String label;

  /// The device's own IPv4, or null if it could not be read.
  final String? selfIp;

  /// The gateway IPv4, if network_info_plus returned one. Informational for the
  /// debug screen; not required to compute the scan range.
  final String? gateway;

  /// Null on success; a short reason when the seed could not be derived (no
  /// Wi-Fi IP, unparseable address, etc.).
  final String? error;

  bool get isValid => error == null && hosts.isNotEmpty;
}

/// Reads the device's own IPv4, subnet mask, and gateway. Injectable so the
/// deriver is testable without a device.
typedef WifiNetworkReader = Future<({String? ip, String? mask, String? gateway})>
    Function();

/// Derives a [SubnetSeed] for the local subnet.
class SubnetSeedDeriver {
  SubnetSeedDeriver({WifiNetworkReader? reader})
      : _reader = reader ?? _defaultReader;

  final WifiNetworkReader _reader;

  static Future<({String? ip, String? mask, String? gateway})>
      _defaultReader() async {
    final NetworkInfo info = NetworkInfo();
    String? ip;
    String? mask;
    String? gateway;
    try {
      ip = await info.getWifiIP();
    } catch (_) {/* leave null */}
    try {
      mask = await info.getWifiSubmask();
    } catch (_) {/* leave null */}
    try {
      gateway = await info.getWifiGatewayIP();
    } catch (_) {/* leave null */}
    return (ip: ip, mask: mask, gateway: gateway);
  }

  /// Reads the network and computes the seed.
  Future<SubnetSeed> derive() async {
    final ({String? ip, String? mask, String? gateway}) net = await _reader();
    return computeSeed(ip: net.ip, mask: net.mask, gateway: net.gateway);
  }

  /// PURE: compute the seed from an IP + mask + gateway. No plugins, so this is
  /// the unit-tested core. A null/blank mask falls back to /24 (the common LAN
  /// case), which is what discovery wants anyway.
  static SubnetSeed computeSeed({
    required String? ip,
    required String? mask,
    String? gateway,
  }) {
    final int? ipInt = ipToInt(ip);
    if (ipInt == null) {
      return SubnetSeed(
        hosts: const <String>[],
        label: '',
        selfIp: ip,
        gateway: gateway,
        error: 'No usable Wi-Fi IPv4 address. Is Wi-Fi connected and granted?',
      );
    }

    // Prefix from the mask; default to /24 when absent or unparseable, and
    // never scan wider than a /24 (clamp the prefix up to 24).
    int prefix = maskToPrefix(mask) ?? 24;
    if (prefix < 24) prefix = 24;
    if (prefix > 30) prefix = 30; // keep at least a couple of host bits

    final int maskBits = (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
    final int network = ipInt & maskBits;
    final int blockSize = 1 << (32 - prefix);
    final int firstHost = network + 1;
    final int lastHost = network + blockSize - 2;

    final List<String> hosts = <String>[
      for (int a = firstHost; a <= lastHost && (a - firstHost) < kMaxScanHosts;
          a++)
        intToIp(a),
    ];

    return SubnetSeed(
      hosts: hosts,
      label: hosts.isEmpty
          ? ''
          : '${intToIp(firstHost)}–${intToIp(lastHost)}',
      selfIp: ip,
      gateway: gateway,
    );
  }

  /// IPv4 dotted-quad → 32-bit int, or null if malformed / null.
  ///
  /// Public so the shared [CurrentNetwork] prefill helper computes CIDRs from
  /// the SAME parser this deriver uses — one source of truth for the ip↔int
  /// math (see current_network.dart).
  static int? ipToInt(String? ip) {
    if (ip == null) return null;
    final List<String> octets = ip.trim().split('.');
    if (octets.length != 4) return null;
    int value = 0;
    for (final String o in octets) {
      if (o.isEmpty || o.length > 3) return null;
      final int? n = int.tryParse(o);
      if (n == null || n < 0 || n > 255) return null;
      value = (value << 8) | n;
    }
    return value & 0xFFFFFFFF;
  }

  /// 32-bit int → IPv4 dotted-quad. Public: shared with [CurrentNetwork].
  static String intToIp(int value) {
    final int v = value & 0xFFFFFFFF;
    return '${(v >> 24) & 0xFF}.${(v >> 16) & 0xFF}.'
        '${(v >> 8) & 0xFF}.${v & 0xFF}';
  }

  /// Dotted-quad mask (e.g. 255.255.255.0) → prefix length, or null if the
  /// mask is null/blank/not a contiguous mask. Public: shared with
  /// [CurrentNetwork] so a null return (unparseable / non-contiguous mask) is
  /// the SAME signal both call sites act on — the honest "no real mask" case.
  static int? maskToPrefix(String? mask) {
    final int? m = ipToInt(mask);
    if (m == null || m == 0) return null;
    // Must be a contiguous run of 1s from the MSB.
    final int inverted = (~m) & 0xFFFFFFFF;
    // inverted+1 must be a power of two for a valid contiguous mask.
    if ((inverted & (inverted + 1)) != 0) return null;
    int bits = 0;
    int x = m;
    while (x & 0x80000000 != 0) {
      bits++;
      x = (x << 1) & 0xFFFFFFFF;
    }
    return bits;
  }
}
