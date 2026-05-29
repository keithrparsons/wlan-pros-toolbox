// ArpNdpService — local-network neighbor discovery (IP ↔ MAC where exposed).
//
// THE HONEST CAPABILITY MATRIX (this is the part to scrutinize):
//
//   Platform   | Neighbor table read           | MAC populated? | How
//   -----------|-------------------------------|----------------|----------------
//   Android    | /proc/net/arp (world-readable)| YES            | read table + sweep
//   Linux      | /proc/net/arp (world-readable)| YES            | read table + sweep
//   macOS      | none (no readable arp file;    | NO             | active sweep only
//              |  `arp -a` subprocess is App-   |                |
//              |  Sandbox-blocked — the         |                |
//              |  traceroute/whois trap)        |                |
//   Windows    | none (GetIpNetTable is a       | NO             | active sweep only
//              |  native FFI call out of scope; |                |
//              |  `arp -a` subprocess unreliable|                |
//              |  under packaging)              |                |
//   iOS        | NOT accessible to third-party  | n/a            | UNAVAILABLE state
//              |  apps                          |                |
//   Web        | n/a                            | n/a            | NetworkUnavailableView
//
// WHY NO SUBPROCESS: shelling out to `arp -a` / `ip neigh` is blocked by the
// macOS App Sandbox (com.apple.security.app-sandbox: true) and impossible in
// the iOS/Android sandbox — exactly the trap Traceroute and WHOIS documented.
// So the cross-platform path is ACTIVE DISCOVERY: derive the local /24 (or the
// real prefix) from the interface, probe each host with a bounded-concurrency
// TCP-connect reachability check (the same primitive PortScanService uses), and
// list the responders. On Linux/Android we ALSO read /proc/net/arp to attach
// the real MAC the kernel cached; on macOS/Windows we list reachable hosts with
// MAC = null and the UI says plainly that MAC is not exposed on this platform.
//
// We NEVER invent a MAC. A null MAC renders "Not exposed on this platform".
//
// Web safety: imports dart:io; gated behind NetworkSupport.arpNdpSupported at
// the UI layer; never reached on web.

import 'dart:async';
import 'dart:io';

/// What this platform can actually do for neighbor discovery.
enum ArpCapability {
  /// Active sweep + a real MAC per responder from the OS neighbor table.
  sweepWithMac,

  /// Active sweep lists responders, but the platform does not expose MACs.
  sweepNoMac,

  /// The platform does not allow neighbor discovery from a third-party app.
  unavailable,
}

/// One discovered neighbor on the local subnet.
class Neighbor {
  const Neighbor({
    required this.ip,
    this.mac,
    this.rttMs,
    this.fromArpTable = false,
  });

  final String ip;

  /// Link-layer address, or null when the platform does not expose it. Never
  /// fabricated.
  final String? mac;

  /// Round-trip time of the reachability probe in ms, or null (e.g. a host that
  /// was only found in the ARP table, not via an active probe).
  final double? rttMs;

  /// True when this entry came from the OS ARP table read (vs. only an active
  /// probe response).
  final bool fromArpTable;
}

/// Live progress of a discovery sweep, streamed to the UI.
class ArpScanProgress {
  const ArpScanProgress({
    required this.probed,
    required this.total,
    required this.found,
    this.lastFound,
  });

  /// Hosts probed so far.
  final int probed;
  final int total;

  /// Running count of neighbors found.
  final int found;

  /// The neighbor just discovered, or null on a tick that found nothing.
  final Neighbor? lastFound;

  double get fraction => total == 0 ? 0 : probed / total;
}

class ArpNdpService {
  ArpNdpService({
    Future<Socket> Function(String host, int port, {required Duration timeout})?
        connector,
    Future<String?> Function()? arpTableReader,
  })  : _connect = connector ?? _defaultConnect,
        _readArpTable = arpTableReader ?? _defaultArpTableReader;

  final Future<Socket> Function(String host, int port,
      {required Duration timeout}) _connect;

  /// Reads the raw /proc/net/arp text (Linux/Android), or null where it does
  /// not exist. Injectable for tests.
  final Future<String?> Function() _readArpTable;

  static Future<Socket> _defaultConnect(
    String host,
    int port, {
    required Duration timeout,
  }) =>
      Socket.connect(host, port, timeout: timeout);

  static Future<String?> _defaultArpTableReader() async {
    try {
      final File f = File('/proc/net/arp');
      if (!await f.exists()) return null;
      return await f.readAsString();
    } on Object {
      return null;
    }
  }

  /// Ports a typical LAN host answers — used only as a reachability signal for
  /// discovery (a refused connection still proves the host is up). Curated to
  /// the services most consumer/IoT/infra devices expose.
  static const List<int> probePorts = <int>[80, 443, 22, 445, 139, 53, 8080];

  /// The honest capability for the current platform.
  static ArpCapability capabilityFor({
    bool? isAndroidOverride,
    bool? isIOSOverride,
    bool? isLinuxOverride,
  }) {
    final bool isIOS = isIOSOverride ?? Platform.isIOS;
    if (isIOS) return ArpCapability.unavailable;
    final bool isAndroid = isAndroidOverride ?? Platform.isAndroid;
    final bool isLinux = isLinuxOverride ?? Platform.isLinux;
    if (isAndroid || isLinux) return ArpCapability.sweepWithMac;
    // macOS / Windows: discovery works, MAC is not exposed without native FFI.
    return ArpCapability.sweepNoMac;
  }

  /// Parse the kernel /proc/net/arp text into an IP → MAC map. Skips the header
  /// row and incomplete entries (flag 0x0 / all-zero MAC). Exposed for tests.
  ///
  /// Format (one header line then rows):
  ///   IP address  HW type  Flags  HW address         Mask  Device
  ///   192.168.1.1 0x1      0x2    aa:bb:cc:dd:ee:ff  *     wlan0
  static Map<String, String> parseProcNetArp(String text) {
    final Map<String, String> out = <String, String>{};
    final List<String> lines = text.split('\n');
    for (int i = 1; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty) continue;
      final List<String> cols =
          line.split(RegExp(r'\s+')).where((String s) => s.isNotEmpty).toList();
      if (cols.length < 4) continue;
      final String ip = cols[0];
      final String flags = cols[2];
      final String mac = cols[3].toLowerCase();
      // Flag 0x0 = incomplete; an all-zero MAC is not a real neighbor.
      if (flags == '0x0') continue;
      if (mac == '00:00:00:00:00:00') continue;
      if (!_validIp(ip) || !_validMac(mac)) continue;
      out[ip] = mac;
    }
    return out;
  }

  /// Derive the list of host IPs to probe from an interface IPv4 and a CIDR
  /// prefix length. Returns the usable host range (excludes network + broadcast)
  /// and, for safety, refuses to enumerate anything larger than a /22 (1022
  /// hosts) so a misread /8 never spawns a 16-million-host sweep. Exposed for
  /// tests — this math is the regression-prone part.
  static List<String> hostsForSubnet(String ipv4, int prefixLength) {
    if (!_validIp(ipv4) || ipv4.contains(':')) return const <String>[];
    if (prefixLength < 22 || prefixLength > 30) {
      // Below /22 is too large to sweep responsibly; /31 and /32 have no usable
      // host range to enumerate here. Clamp /24 default handled by caller.
      if (prefixLength < 22) return const <String>[];
    }
    final int? base = _ipToInt(ipv4);
    if (base == null) return const <String>[];
    final int mask = prefixLength == 0 ? 0 : (0xFFFFFFFF << (32 - prefixLength)) & 0xFFFFFFFF;
    final int network = base & mask;
    final int broadcast = network | (~mask & 0xFFFFFFFF);
    final List<String> hosts = <String>[];
    for (int addr = network + 1; addr < broadcast; addr++) {
      hosts.add(_intToIp(addr));
    }
    return hosts;
  }

  /// Convenience: derive hosts assuming a /24 around [ipv4] when the real mask
  /// is unknown (the common LAN case). Excludes the device's own IP.
  static List<String> defaultLanHosts(String ipv4) {
    final List<String> all = hostsForSubnet(ipv4, 24);
    return all.where((String h) => h != ipv4).toList(growable: false);
  }

  /// Run an active discovery sweep over [hosts], streaming progress. On
  /// platforms with a readable ARP table, the cached MACs are merged in as
  /// probes complete (a responding host gets its real MAC attached).
  ///
  /// - [timeout] bounds each connect (default 600ms — LAN-fast).
  /// - [concurrency] caps sockets in flight (default 48).
  /// - [cancel] aborts the sweep.
  Stream<ArpScanProgress> discover({
    required List<String> hosts,
    ArpCapability? capabilityOverride,
    Duration timeout = const Duration(milliseconds: 600),
    int concurrency = 48,
    Future<void>? cancel,
  }) {
    final ArpCapability cap = capabilityOverride ?? capabilityFor();
    final StreamController<ArpScanProgress> controller =
        StreamController<ArpScanProgress>();

    final List<String> queue = List<String>.of(hosts);
    final int total = queue.length;
    int probed = 0;
    int found = 0;
    int index = 0;
    int active = 0;
    bool cancelled = false;
    bool closed = false;
    Map<String, String> arpCache = <String, String>{};

    cancel?.then((_) => cancelled = true);

    void finishIfDone() {
      if (closed) return;
      if ((cancelled || probed >= total) && active == 0) {
        closed = true;
        controller.close();
      }
    }

    void pump() {
      while (!cancelled && active < concurrency && index < queue.length) {
        final String host = queue[index++];
        active++;
        _probe(host, timeout).then((double? rttMs) async {
          active--;
          probed++;
          Neighbor? n;
          if (rttMs != null) {
            // Refresh the ARP cache lazily once we have any responder, so a
            // host that just answered has its freshly-learned MAC available.
            if (cap == ArpCapability.sweepWithMac && arpCache.isEmpty) {
              arpCache = await _loadArpCache();
            }
            final String? mac =
                cap == ArpCapability.sweepWithMac ? arpCache[host] : null;
            found++;
            n = Neighbor(ip: host, mac: mac, rttMs: rttMs);
          }
          if (!closed) {
            controller.add(ArpScanProgress(
              probed: probed,
              total: total,
              found: found,
              lastFound: n,
            ));
          }
          if (!cancelled) pump();
          finishIfDone();
        });
      }
      finishIfDone();
    }

    controller.add(ArpScanProgress(probed: 0, total: total, found: 0));
    if (total == 0) {
      closed = true;
      controller.close();
    } else {
      pump();
    }
    return controller.stream;
  }

  Future<Map<String, String>> _loadArpCache() async {
    final String? text = await _readArpTable();
    if (text == null) return <String, String>{};
    return parseProcNetArp(text);
  }

  /// Probe [host] for reachability: a successful connect OR an actively-refused
  /// connection both prove the host is up (a live host that refuses still
  /// answered at the IP layer). Only a timeout / unreachable counts as "down".
  /// Returns the RTT in ms when up, else null.
  Future<double?> _probe(String host, Duration timeout) async {
    final Stopwatch sw = Stopwatch()..start();
    for (final int port in probePorts) {
      try {
        final Socket s = await _connect(host, port, timeout: timeout);
        sw.stop();
        s.destroy();
        return sw.elapsedMicroseconds / 1000.0;
      } on SocketException catch (e) {
        // A refusal/reset (OS error present) means the host is UP but the port
        // is closed — that is a positive reachability signal, return now.
        if (e.osError != null && !_isUnreachable(e)) {
          sw.stop();
          return sw.elapsedMicroseconds / 1000.0;
        }
        // No OS error → our timeout fired, or host unreachable → try next port.
        continue;
      } on Object {
        continue;
      }
    }
    sw.stop();
    return null;
  }

  static bool _isUnreachable(SocketException e) {
    final String m = (e.osError?.message ?? '').toLowerCase();
    return m.contains('unreachable') || m.contains('no route');
  }

  static bool _validIp(String ip) {
    if (ip.contains(':')) return RegExp(r'^[0-9a-fA-F:]+$').hasMatch(ip);
    final List<String> p = ip.split('.');
    if (p.length != 4) return false;
    for (final String o in p) {
      final int? n = int.tryParse(o);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  static bool _validMac(String mac) =>
      RegExp(r'^[0-9a-f]{2}(:[0-9a-f]{2}){5}$').hasMatch(mac);

  static int? _ipToInt(String ip) {
    final List<String> p = ip.split('.');
    if (p.length != 4) return null;
    int v = 0;
    for (final String o in p) {
      final int? n = int.tryParse(o);
      if (n == null || n < 0 || n > 255) return null;
      v = (v << 8) | n;
    }
    return v & 0xFFFFFFFF;
  }

  static String _intToIp(int v) {
    return '${(v >> 24) & 0xFF}.${(v >> 16) & 0xFF}.${(v >> 8) & 0xFF}.${v & 0xFF}';
  }
}
