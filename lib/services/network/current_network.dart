// CurrentNetwork — the ONE source of truth for "what network is this device on
// right now", used to PREFILL the networking tools (Ping Sweep, Port Scan) and
// to OFFER a one-tap gateway target (Ping, Ping Plotter, Traceroute).
//
// Wave 2 / 1.7.2 enhancement. It replaces the generic 192.168.1.0/24 default
// with the device's REAL subnet where we can measure it, so a user on
// 172.19.0.x or 10.x doesn't have to know and type their own subnet.
//
// 🔴 HONEST-NULL (the load-bearing rule, same discipline as the 1.7.1 audit —
// [[feedback_unsourced_is_not_invalid]]). There are three cases and three
// honest behaviors. A guessed prefix must NEVER be presented as a measured one:
//
//   | Case    | We have               | cidr                 | maskWasReal |
//   |---------|-----------------------|----------------------|-------------|
//   | BEST    | real IP + real mask   | the TRUE CIDR        | true        |
//   | PARTIAL | IP only, mask null    | an IP-derived /24    | false       |
//   | NONE    | neither (cell/VPN/web)| null (keep default)  | false       |
//
// The BEST case surfaces the TRUE prefix, not a /24 — a device on a /23 gets
// `x.x.x.0/23`, because showing `/24` for a `/23` without a hint is exactly the
// small lie the 1.7.1 audit removed. `maskWasReal` is the honesty contract the
// UI reads: when it is false AND a cidr was derived (PARTIAL), the screen shows
// the visible "assumed /24 — edit if your network is wider" hint. When it is
// true (BEST) no hint is shown. NONE derives nothing and fabricates nothing.
//
// Deliberately NOT clamped to /24 (that clamp is a scan-SCOPE guard living in
// subnet_seed.dart; it does not belong in the honest description of the network
// the device is actually on). Ping Sweep's own 254-host cap handles a too-wide
// range with an honest, instructive error at Sweep time.
//
// The ip↔int and mask→prefix math is the SAME parser SubnetSeedDeriver uses
// (its now-public statics), so there is one implementation of the number
// crunching, not two that can drift.

import 'package:network_info_plus/network_info_plus.dart';

import 'lan_discovery/subnet_seed.dart';

/// The prefill suggestion derived from the device's current network. Field
/// names mirror the spec's record shape `({cidr, gatewayIp, deviceIp,
/// maskWasReal})`; a class is used over the raw record for readability and
/// testable value-equality.
class NetworkSuggestion {
  const NetworkSuggestion({
    required this.cidr,
    required this.gatewayIp,
    required this.deviceIp,
    required this.maskWasReal,
  });

  /// The suggested subnet in CIDR notation (e.g. `172.19.0.0/24`), or null when
  /// there is no usable device IPv4 (NONE) — in which case a screen keeps its
  /// own generic default and shows no suggestion.
  final String? cidr;

  /// The default gateway IPv4, or null. The most common first scan / ping
  /// target. Sanitized: `0.0.0.0` and unparseable values become null.
  final String? gatewayIp;

  /// The device's own IPv4 (canonicalized), or null when unreadable.
  final String? deviceIp;

  /// True only in the BEST case, where [cidr] was computed from a REAL subnet
  /// mask (a measured claim). False in PARTIAL (cidr is an assumed /24, show the
  /// hint) and in NONE (cidr is null). This flag IS the honesty contract — the
  /// UI must show the "assumed /24" hint iff `cidr != null && !maskWasReal`.
  final bool maskWasReal;

  /// True when a subnet CIDR was derived at all (BEST or PARTIAL).
  bool get hasCidr => cidr != null;

  /// The honesty gate for the visible hint: a derived-but-assumed /24.
  bool get isAssumedPrefix => cidr != null && !maskWasReal;

  /// A NONE suggestion — nothing measured, nothing derived, nothing gateway.
  static const NetworkSuggestion none = NetworkSuggestion(
    cidr: null,
    gatewayIp: null,
    deviceIp: null,
    maskWasReal: false,
  );

  @override
  bool operator ==(Object other) =>
      other is NetworkSuggestion &&
      other.cidr == cidr &&
      other.gatewayIp == gatewayIp &&
      other.deviceIp == deviceIp &&
      other.maskWasReal == maskWasReal;

  @override
  int get hashCode => Object.hash(cidr, gatewayIp, deviceIp, maskWasReal);

  @override
  String toString() =>
      'NetworkSuggestion(cidr: $cidr, gatewayIp: $gatewayIp, '
      'deviceIp: $deviceIp, maskWasReal: $maskWasReal)';
}

/// Reads the device's current IPv4, subnet mask, and gateway. Injectable so the
/// pure derivation is testable with no device (same seam as subnet_seed).
typedef CurrentNetworkReader
    = Future<({String? ip, String? mask, String? gateway})> Function();

/// Derives a [NetworkSuggestion] from the device's current network.
class CurrentNetwork {
  CurrentNetwork({CurrentNetworkReader? reader})
      : _reader = reader ?? _defaultReader;

  final CurrentNetworkReader _reader;

  static Future<({String? ip, String? mask, String? gateway})>
      _defaultReader() async {
    final NetworkInfo info = NetworkInfo();
    String? ip;
    String? mask;
    String? gateway;
    try {
      ip = await info.getWifiIP();
    } catch (_) {/* leave null — honest NONE, not a fabricated address */}
    try {
      mask = await info.getWifiSubmask();
    } catch (_) {/* leave null — mask often unreadable on wired/cell/web */}
    try {
      gateway = await info.getWifiGatewayIP();
    } catch (_) {/* leave null */}
    return (ip: ip, mask: mask, gateway: gateway);
  }

  /// Reads the network and derives the suggestion.
  Future<NetworkSuggestion> suggest() async {
    final ({String? ip, String? mask, String? gateway}) net = await _reader();
    return suggestFrom(ip: net.ip, mask: net.mask, gateway: net.gateway);
  }

  /// PURE: derive the suggestion from an ip + mask + gateway. No plugins, so
  /// this is the unit-tested core. Uses SubnetSeedDeriver's public parser for
  /// the ip↔int and mask→prefix math — one source of truth.
  ///
  /// The three honest-null cases live here:
  ///  - no usable IPv4              → NONE  (cidr null; gateway still passed if
  ///                                  present, e.g. some VPNs expose only that).
  ///  - IPv4 + a REAL mask          → BEST  (true CIDR at the true prefix).
  ///  - IPv4, mask null/unparseable → PARTIAL (assumed /24, maskWasReal false).
  static NetworkSuggestion suggestFrom({
    required String? ip,
    required String? mask,
    String? gateway,
  }) {
    final String? gw = _sanitizeGateway(gateway);

    final int? ipInt = SubnetSeedDeriver.ipToInt(ip);
    if (ipInt == null) {
      // NONE — no measurable device IPv4. Fabricate nothing; a screen keeps its
      // generic default. Pass through a gateway if one exists on its own.
      return NetworkSuggestion(
        cidr: null,
        gatewayIp: gw,
        deviceIp: null,
        maskWasReal: false,
      );
    }

    final String deviceIp = SubnetSeedDeriver.intToIp(ipInt);
    final int? prefix = SubnetSeedDeriver.maskToPrefix(mask);

    if (prefix != null) {
      // BEST — a real, contiguous mask. Surface the TRUE CIDR at the TRUE
      // prefix (no /24 clamp). This is a measured claim, so no "assumed" hint.
      final int maskBits =
          prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
      final int network = ipInt & maskBits;
      return NetworkSuggestion(
        cidr: '${SubnetSeedDeriver.intToIp(network)}/$prefix',
        gatewayIp: gw,
        deviceIp: deviceIp,
        maskWasReal: true,
      );
    }

    // PARTIAL — we have an IP but no real mask. Derive a /24 as an ASSUMPTION
    // and flag it (maskWasReal: false) so the UI shows the honest hint. Never
    // present this as measured.
    final int network24 = ipInt & 0xFFFFFF00;
    return NetworkSuggestion(
      cidr: '${SubnetSeedDeriver.intToIp(network24)}/24',
      gatewayIp: gw,
      deviceIp: deviceIp,
      maskWasReal: false,
    );
  }

  /// A gateway is only useful as a target if it is a real, non-zero IPv4.
  /// `0.0.0.0` (a common "no gateway" sentinel) and unparseable values → null,
  /// so a screen never offers a dead target.
  static String? _sanitizeGateway(String? gateway) {
    final int? g = SubnetSeedDeriver.ipToInt(gateway);
    if (g == null || g == 0) return null;
    return SubnetSeedDeriver.intToIp(g);
  }
}
