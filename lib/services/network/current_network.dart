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

import 'dart:io' show InternetAddress, InternetAddressType, NetworkInterface;

import 'package:network_info_plus/network_info_plus.dart';

import 'default_route_probe.dart';

import 'lan_discovery/subnet_seed.dart';
import 'link_info.dart';
import 'link_table_service.dart';
import 'transport_chooser.dart';
import 'transport_preference.dart';
import 'pi_backend_client.dart';

/// The prefill suggestion derived from the device's current network. Field
/// names mirror the spec's record shape `({cidr, gatewayIp, deviceIp,
/// maskWasReal})`; a class is used over the raw record for readability and
/// testable value-equality.
/// WHERE the addressing came from, because on a multi-homed desktop the two
/// sources can disagree and one of them is right.
///
/// THIS EXISTS BECAUSE THE FIX FOR THE `en0` DEFECT CANNOT REACH EVERY BUILD.
/// `DefaultRouteProbe` reads the routing table by running `route` and
/// `ifconfig`. The macOS App Store build ships sandboxed and DENIES that; the
/// Developer ID direct-download build does not (traceroute_service.dart:171,
/// network_details_service.dart:10). When the probe is refused we fall back to
/// `network_info_plus`, which matches on the interface NAME `en0`.
///
/// A SILENT FALLBACK IS THE WORSE FAILURE. The user would be shown the Wi-Fi
/// subnet while plugged into a different one, with nothing on screen saying the
/// better source had been refused. So the source travels with the answer, the
/// same way [maskWasReal] already travels with the prefix.
enum NetworkSource {
  /// The operating system named the interface holding the default route. This
  /// is the link carrying traffic, and it is not an inference.
  routingTable,

  /// The Wi-Fi interface's own address, from `network_info_plus`.
  ///
  /// CORRECT ON A PHONE AND SUSPECT ON A DESKTOP, which is the whole point. An
  /// iPhone has no wired NIC to confuse the read, so this IS the right answer
  /// there. A Mac with an Ethernet adapter can be on a completely different
  /// network from the one this reports.
  wifiInterface,

  /// Nothing was readable.
  none,
}

class NetworkSuggestion {
  const NetworkSuggestion({
    required this.cidr,
    required this.gatewayIp,
    required this.deviceIp,
    required this.maskWasReal,
    this.source = NetworkSource.none,
    this.multiHomed = false,
    this.transport,
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

  /// Where the addressing came from.
  final NetworkSource source;

  /// True when this device has more than one link that could be carrying
  /// traffic, so naming the wrong one is a live possibility rather than a
  /// theoretical one.
  final bool multiHomed;

  /// What became of the user's app-wide transport choice, or null when the
  /// caller supplied no [TransportPreference] at all.
  ///
  /// NULL AND "NOTHING CHOSEN" ARE DIFFERENT AND THE UI MUST NOT MERGE THEM.
  /// Null means this code path never consulted a preference, which is every
  /// existing caller and every current test. A non-null value carrying
  /// [TransportResolution.followingSystem] means a preference WAS consulted and
  /// the user has deliberately left the OS in charge. Collapsing the two would
  /// make a screen claim a choice was honoured on a build that never read one.
  final ResolvedTransport? transport;

  /// The user picked a transport and the tools are NOT using it. The screen
  /// must say so; silence here is the whole defect this field exists to stop.
  bool get transportIgnored => transport?.isStale ?? false;

  /// Plain words for [transportIgnored], never empty when it is true.
  ///
  /// The chooser's own [TransportOption.reason] is used verbatim when it has
  /// one, because that string is already written for a human and writing a
  /// second one here would put two authors on the same sentence.
  String? get transportWarning {
    final ResolvedTransport? t = transport;
    if (t == null || !t.isStale) return null;
    final String kind = t.chosen?.label ?? 'the chosen link';
    final String tail = t.reason != null && t.reason!.isNotEmpty
        ? ' ${t.reason}'
        : '';
    return switch (t.resolution) {
      TransportResolution.chosenUnavailable =>
        'You chose $kind, and it has no usable link right now, so these '
            'numbers are for the link the system is actually using.$tail',
      TransportResolution.chosenNotSelectable =>
        'You chose $kind, and this platform will not let the app send this '
            'kind of traffic over it. These numbers are for the link the system '
            'is actually using.$tail',
      TransportResolution.chosenUntested =>
        'You chose $kind, and whether traffic can be pinned to it has not '
            'been established on this machine. These numbers are for the link '
            'the system is actually using.$tail',
      _ => null,
    };
  }

  /// True when a subnet CIDR was derived at all (BEST or PARTIAL).
  bool get hasCidr => cidr != null;

  /// The honesty gate for the second visible hint, and it mirrors
  /// [isAssumedPrefix] exactly: show it iff we fell back to the Wi-Fi
  /// interface ON A DEVICE THAT HAS ANOTHER LINK.
  ///
  /// NOT shown on a phone, where the Wi-Fi interface is genuinely the answer,
  /// and NOT shown on a single-homed desktop, where both sources agree. Warning
  /// in either of those cases would be noise, and noise is how a real warning
  /// stops being read.
  bool get linkMayBeWrong =>
      source == NetworkSource.wifiInterface && multiHomed && cidr != null;

  /// What the UI says when [linkMayBeWrong]. Never empty.
  String get linkWarning =>
      'This is the Wi-Fi interface\'s network. This build could not ask the '
      'system which link is actually carrying your traffic, and this device '
      'has more than one. If you are on a cable, check the address before you '
      'trust it.';

  /// The honesty gate for the visible hint: a derived-but-assumed /24.
  bool get isAssumedPrefix => cidr != null && !maskWasReal;

  /// A NONE suggestion — nothing measured, nothing derived, nothing gateway.
  static const NetworkSuggestion none = NetworkSuggestion(
    cidr: null,
    gatewayIp: null,
    deviceIp: null,
    maskWasReal: false,
    source: NetworkSource.none,
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
typedef CurrentNetworkReader =
    Future<({String? ip, String? mask, String? gateway})> Function();

/// Derives a [NetworkSuggestion] from the device's current network.
class CurrentNetwork {
  CurrentNetwork({
    CurrentNetworkReader? reader,
    TransportPreference? preference,
    LinkTableService? linkTable,
  }) : _reader = reader ?? _defaultReader,
       // ignore: prefer_initializing_formals
       _preference = preference,
       // ignore: prefer_initializing_formals
       _linkTable = linkTable;

  final CurrentNetworkReader _reader;

  /// The app-wide transport choice. NULL means this instance does not consult
  /// one, which keeps every existing caller byte-identical in behaviour.
  final TransportPreference? _preference;

  /// Enumerates the links a preference is resolved against. Only read when
  /// [_preference] is set, so no caller pays for a link-table read it did not
  /// ask for.
  final LinkTableService? _linkTable;

  /// ASK THE ROUTING TABLE FIRST. `network_info_plus` FALLS BACK, it does not
  /// lead.
  ///
  /// THE DEFECT, measured 2026-08-31. On macOS that plugin answers "your local
  /// IP" by looking for an interface literally NAMED `en0`
  /// (NetworkInfoPlusPlugin.swift:143). On a MacBook `en0` is Wi-Fi. With both
  /// links up on Keith's M5 the default route was `en5` at 192.168.8.233 while
  /// the plugin returned `en0` at 192.168.8.134, so every screen that prefills
  /// a target from here offered the WIRELESS network to a user on a cable. On
  /// Network Discovery, which derives its entire scan range from this and gives
  /// no field to correct, that means scanning a network you are not on and
  /// reporting the result as if you were.
  ///
  /// Phase 0's rule is "select by carrier, never by name, index or flag", and
  /// the default route is the only field that means "traffic goes here". So the
  /// route is asked first, and the name-matching plugin is what we fall back to
  /// where the route cannot be read at all (iOS, Android, web).
  ///
  /// THE FALLBACK IS STILL RIGHT WHERE IT APPLIES. On an iPhone there is no
  /// wired NIC to confuse the read, which is exactly why the plugin's
  /// assumption holds there and fails on a desktop.
  static Future<({String? ip, String? mask, String? gateway})>
  _defaultReader() async {
    try {
      final DefaultRoute? route = await DefaultRouteProbe().readV4();
      if (route != null && route.address != null) {
        _lastSource = NetworkSource.routingTable;
        return (
          ip: route.address,
          // Null rather than a guessed /24: a wrong prefix silently changes the
          // size of a scan, and a sweep of the wrong range looks like a
          // successful sweep that found nothing.
          mask: route.netmask,
          gateway: route.gateway,
        );
      }
    } on Object {
      // A platform we cannot shell, or a sandbox that refused. Fall through.
    }

    _lastSource = NetworkSource.wifiInterface;
    final NetworkInfo info = NetworkInfo();
    String? ip;
    String? mask;
    String? gateway;
    try {
      ip = await info.getWifiIP();
    } catch (_) {
      /* leave null - honest NONE, not a fabricated address */
    }
    try {
      mask = await info.getWifiSubmask();
    } catch (_) {
      /* leave null - mask often unreadable on wired/cell/web */
    }
    try {
      gateway = await info.getWifiGatewayIP();
    } catch (_) {
      /* leave null */
    }
    return (ip: ip, mask: mask, gateway: gateway);
  }

  /// A [CurrentNetwork] that asks the WLAN Pi hosting this page instead of the
  /// browser.
  ///
  /// WHY THIS EXISTS: the default reader calls `network_info_plus`, which on
  /// web has no Wi-Fi API at all. It returns nothing, so the subnet field stays
  /// empty and the user has to type their own network back to a tool that is
  /// running ON that network. The failure was silent and honest, but it was
  /// still a blank field where an exact answer was available: the Pi knows its
  /// own addressing, and under the Ethernet-access design the address the user
  /// typed IS one of the Pi's interfaces.
  factory CurrentNetwork.pi({PiBackendClient? client}) {
    final PiBackendClient c = client ?? PiBackendClient();
    return CurrentNetwork(reader: () => _piReader(c));
  }

  /// Reads ip + prefix from the Pi's own interfaces.
  ///
  /// INTERFACE CHOICE: prefer the interface whose address matches the host this
  /// client talks to (in production, the origin the page was served from),
  /// because that is provably the network the user is on with the Pi. Falls back to the first global IPv4 on a non-loopback
  /// interface. Returns all-null rather than guessing when nothing qualifies,
  /// so [suggestFrom]'s honest-NONE path still applies and no subnet is
  /// fabricated.
  ///
  /// GATEWAY IS LEFT NULL DELIBERATELY: `/toolboxapi/interfaces` does not carry
  /// a default gateway, and deriving one by assuming `.1` would be exactly the
  /// fabrication this file exists to avoid.
  static Future<({String? ip, String? mask, String? gateway})> _piReader(
    PiBackendClient client,
  ) async {
    final List<PiInterface> ifaces;
    try {
      ifaces = await client.interfaces();
    } on Object {
      return (ip: null, mask: null, gateway: null);
    }

    final String servedHost = client.baseHost;
    PiInterfaceAddress? chosen;

    for (final PiInterface i in ifaces) {
      if (i.name == 'lo') continue;
      for (final PiInterfaceAddress a in i.addresses) {
        if (!a.isIPv4 || a.prefixLen == null) continue;
        if (a.local == servedHost) {
          chosen = a;
          break;
        }
        chosen ??= a;
      }
      if (chosen != null && chosen.local == servedHost) break;
    }

    if (chosen == null) return (ip: null, mask: null, gateway: null);
    return (
      ip: chosen.local,
      mask: _maskFromPrefix(chosen.prefixLen!),
      gateway: null,
    );
  }

  /// Dotted-quad mask for a prefix length, so the Pi path can reuse
  /// [suggestFrom] unchanged rather than growing a second derivation.
  static String _maskFromPrefix(int prefix) {
    final int m = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
    return '${(m >> 24) & 0xFF}.${(m >> 16) & 0xFF}.'
        '${(m >> 8) & 0xFF}.${m & 0xFF}';
  }

  /// Reads the network and derives the suggestion.
  Future<NetworkSuggestion> suggest() async {
    final ({String? ip, String? mask, String? gateway}) net = await _reader();
    final NetworkSuggestion base = suggestFrom(
      ip: net.ip,
      mask: net.mask,
      gateway: net.gateway,
    );

    // STAMP WHERE IT CAME FROM. `_lastSource` is set by `_defaultReader`; an
    // injected reader (every test, and the Pi path) leaves it null and the
    // suggestion carries `NetworkSource.none`, claiming nothing either way.
    final NetworkSource src = _lastSource ?? NetworkSource.none;

    // THE APP-WIDE TRANSPORT CHOICE. Ruled by Keith 2026-09-01: one choice,
    // every tool honours it. This is the single place it is applied, which is
    // why all seven surfaces that prefill a target inherit it without any of
    // them being edited.
    //
    // A FAILURE HERE MUST NEVER COST THE USER A SUGGESTION. Every path below
    // falls back to the routing table's answer, which is what the screens got
    // before this feature existed.
    final ResolvedTransport? resolved = await _resolvePreference();
    if (resolved != null && resolved.isHonoured && resolved.link != null) {
      final NetworkSuggestion chosen = _fromLink(resolved.link!, base);
      return NetworkSuggestion(
        cidr: chosen.cidr,
        gatewayIp: chosen.gatewayIp,
        deviceIp: chosen.deviceIp,
        maskWasReal: chosen.maskWasReal,
        source: NetworkSource.routingTable,
        multiHomed: false,
        transport: resolved,
      );
    }

    return NetworkSuggestion(
      cidr: base.cidr,
      gatewayIp: base.gatewayIp,
      deviceIp: base.deviceIp,
      maskWasReal: base.maskWasReal,
      source: src,
      multiHomed: src == NetworkSource.wifiInterface
          ? await _looksMultiHomed()
          : false,
      transport: resolved,
    );
  }

  /// Reads the stored choice and resolves it against this machine's links.
  ///
  /// Returns null when no [TransportPreference] was supplied, so a caller that
  /// never asked for this behaves exactly as it did before.
  Future<ResolvedTransport?> _resolvePreference() async {
    final TransportPreference? pref = _preference;
    if (pref == null) return null;
    try {
      final TransportKind? chosen = await pref.read();
      final LinkTableResult result = await (_linkTable ?? LinkTableService())
          .read();
      final LinkTable? table = result.table;
      // No link table means nothing to resolve a choice against. Honest null:
      // the routing table's answer stands and no screen claims a choice was
      // applied.
      if (table == null) return null;
      return resolveTransport(
        chosen: chosen,
        options: buildTransportOptions(
          links: table.links,
          scope: TransportScope.localSubnet,
          platform: currentTransportPlatform(tableSource: table.source),
        ),
        activeLink: table.primary,
      );
    } on Object {
      // A link table we could not read is not a reason to lose the prefill.
      // Null here means "no preference applied", and the routing table's
      // answer stands.
      return null;
    }
  }

  /// Derives a suggestion from a specific link rather than the default route.
  ///
  /// THE GATEWAY IS DELIBERATELY DROPPED when the chosen link is not the one
  /// holding the default route. We know that link's address and prefix; we do
  /// NOT know its gateway, because a gateway belongs to a route and this link
  /// is not carrying one. Offering the DEFAULT route's gateway beside a
  /// different link's subnet would be the same class of lie the `en0` defect
  /// told: two numbers from two different networks presented as one.
  static NetworkSuggestion _fromLink(LinkInfo link, NetworkSuggestion base) {
    LinkAddress? v4;
    for (final LinkAddress a in link.addresses) {
      if (a.isIPv4 && !a.isLinkLocal) {
        v4 = a;
        break;
      }
    }
    if (v4 == null) return base;
    final String? mask = v4.prefixLength != null
        ? _maskFromPrefix(v4.prefixLength!)
        : null;
    return suggestFrom(
      ip: v4.address,
      mask: mask,
      gateway: link.isDefaultRouteV4 ? base.gatewayIp : null,
    );
  }

  /// Set by [_defaultReader] only. Static because the reader is static; the
  /// value is read immediately after the await in [suggest], on the same
  /// microtask chain.
  static NetworkSource? _lastSource;

  /// Does this device have more than one link that could be carrying traffic?
  ///
  /// PURE dart:io, so it works inside the App Sandbox where the shell-out does
  /// not. It cannot tell us WHICH link is carrying traffic, which is the thing
  /// we actually wanted, but it can tell us whether getting it wrong is
  /// possible here. That is exactly enough to decide whether to warn.
  ///
  /// Counts interfaces holding a non-link-local IPv4, excluding loopback. Two
  /// or more means the Wi-Fi address might not be the one in use.
  static Future<bool> _looksMultiHomed() async {
    try {
      final List<NetworkInterface> ifs = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      int usable = 0;
      for (final NetworkInterface ni in ifs) {
        final bool hasGlobal = ni.addresses.any(
          (InternetAddress a) =>
              !a.address.startsWith('169.254.') && a.address != '0.0.0.0',
        );
        if (hasGlobal) usable++;
      }
      return usable > 1;
    } on Object {
      // Cannot tell. Do not warn on a guess.
      return false;
    }
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
      final int maskBits = prefix == 0
          ? 0
          : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
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
