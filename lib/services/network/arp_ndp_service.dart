// ArpNdpService — local-network neighbor discovery (IP ↔ MAC where exposed).
//
// THERE IS NO CAPABILITY MATRIX IN THIS FILE, ON PURPOSE.
//
// There used to be one, and it was INVERTED: it claimed a MAC read on Linux —
// which no reader in this app performs (platformArpReader() hands Linux an
// UnavailableArpReader, and this repo carries no linux/ build directory) —
// and denied it on macOS and Windows, where it works. It was written before
// macos/Runner/ArpTableChannel.swift existed and was never revisited, so this
// tool told macOS users "Not exposed on this platform" while Network Discovery
// read real MACs on the same machine. The app shipped the solution and told the
// user there wasn't one.
//
// The defect was not the wrong comment. The defect was that ONE fact — "can
// this platform expose MACs" — had TWO sources: this table, and the reader in
// lan_discovery/arp_reader.dart that does the work. A second source cannot be
// kept correct; it can only be caught late. See
// [[feedback_ui_rendered_a_decision_it_lacked]], "one representation, one
// derivation".
//
// So: capabilityFor() asks platformArpReader().readsMac, and discover() pulls
// MACs from that same reader. One dispatch, in arp_reader.dart. To learn what a
// platform can do, read platformArpReader() — not a comment here.
//
// WHY NO SUBPROCESS: shelling out to `arp -a` / `ip neigh` is blocked by the
// macOS App Sandbox (com.apple.security.app-sandbox: true) and impossible in
// the iOS/Android sandbox — exactly the trap Traceroute and WHOIS documented.
// ArpTableChannel.swift exists BECAUSE of that limit; it is the answer to it,
// not evidence against it. Discovery itself is pure Dart: derive the local /24
// from the interface, probe each host with a bounded-concurrency TCP-connect
// reachability check (the same primitive PortScanService uses), list the
// responders, then attach MACs from the platform reader where it has them.
//
// We NEVER invent a MAC. A null MAC renders a reason that distinguishes a
// platform that CANNOT read from a read that DID NOT return this host — see
// [MacReadOutcome].
//
// Web safety: imports dart:io; gated behind NetworkSupport.arpNdpSupported at
// the UI layer; never reached on web.

import 'dart:async';
import 'dart:io';

import 'lan_discovery/arp_reader.dart';
import 'tcp_probe_classifier.dart';

/// What this platform can actually do for neighbor discovery.
enum ArpCapability {
  /// Active sweep + a real MAC per responder from the OS neighbor table.
  sweepWithMac,

  /// Active sweep lists responders, but the platform does not expose MACs.
  sweepNoMac,

  /// The platform does not allow neighbor discovery from a third-party app.
  unavailable,
}

/// What happened to the MAC read during a sweep. The bit that separates a
/// platform that CANNOT read the neighbor table from a read that ran and DID
/// NOT return a given host. Rendering those two the same way is how a screen
/// ends up asserting a false platform incapability.
enum MacReadOutcome {
  /// No read was attempted: this platform has no reader that exposes MACs.
  /// The only outcome under which "not exposed on this platform" is true.
  notAttempted,

  /// The read ran and succeeded. A neighbor with a null MAC here was simply
  /// absent from the cache — "not in the ARP cache", not "cannot".
  ok,

  /// The read was attempted on a platform that implements it, and it FAILED.
  /// Honest phrasing is "could not read", never "this platform cannot".
  failed,
}

/// Why a neighbor has no MAC, in user-facing words. ONE derivation, shared by
/// every surface that renders it (the result row and the copied export), so
/// the two can never drift into disagreeing about the same fact.
///
/// Only [MacReadOutcome.notAttempted] earns a claim about the PLATFORM. The
/// other two describe this run: a read that failed, and a read that succeeded
/// without covering this host. Rendering all three as "not exposed on this
/// platform" is the false capability claim this enum exists to prevent.
String missingMacReason(MacReadOutcome outcome) => switch (outcome) {
      MacReadOutcome.notAttempted => 'Not exposed on this platform',
      MacReadOutcome.failed => 'MAC read failed',
      MacReadOutcome.ok => 'Not in the ARP cache',
    };

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
    this.macRead = MacReadOutcome.notAttempted,
  });

  /// Hosts probed so far.
  final int probed;
  final int total;

  /// Running count of neighbors found.
  final int found;

  /// The neighbor just discovered, or null on a tick that found nothing.
  final Neighbor? lastFound;

  /// Fate of the neighbor-table read for this sweep. Stays [notAttempted]
  /// until a responder triggers the lazy read, so the UI must not treat an
  /// early tick as proof the platform cannot read MACs.
  final MacReadOutcome macRead;

  double get fraction => total == 0 ? 0 : probed / total;
}

class ArpNdpService {
  ArpNdpService({
    Future<Socket> Function(String host, int port, {required Duration timeout})?
        connector,
    ArpReader? arpReader,
  })  : _connect = connector ?? _defaultConnect,
        _arpReader = arpReader ?? platformArpReader();

  final Future<Socket> Function(String host, int port,
      {required Duration timeout}) _connect;

  /// The platform neighbor-table reader — the SAME seam Network Discovery
  /// uses, so both tools read one ARP cache through one dispatch. Injectable
  /// for tests. This tool previously had no access to it at all, which is what
  /// let its capability claims invert.
  final ArpReader _arpReader;

  static Future<Socket> _defaultConnect(
    String host,
    int port, {
    required Duration timeout,
  }) =>
      Socket.connect(host, port, timeout: timeout);

  /// Ports a typical LAN host answers — used only as a reachability signal for
  /// discovery (a refused connection still proves the host is up). Curated to
  /// the services most consumer/IoT/infra devices expose.
  static const List<int> probePorts = <int>[80, 443, 22, 445, 139, 53, 8080];

  /// The honest capability for the current platform, DERIVED from the reader
  /// that does the work rather than from a hand-maintained platform list.
  ///
  /// Two independent axes, deliberately not collapsed:
  ///  - Can this tool sweep at all? iOS says no. That is a product decision
  ///    about the sweep, not something a neighbor-table reader can answer, so
  ///    it stays an explicit platform check here.
  ///  - Can MACs be exposed? Ask [ArpReader.readsMac]. Never restate it.
  ///
  /// [readerOverride] is a test seam only; production reads the platform.
  static ArpCapability capabilityFor({
    bool? isIOSOverride,
    ArpReader? readerOverride,
  }) {
    final bool isIOS = isIOSOverride ?? Platform.isIOS;
    if (isIOS) return ArpCapability.unavailable;
    final ArpReader reader = readerOverride ?? platformArpReader();
    return reader.readsMac
        ? ArpCapability.sweepWithMac
        : ArpCapability.sweepNoMac;
  }

  // NOTE: a static parseProcNetArp() lived here and parsed /proc/net/arp. It
  // was removed with the inverted matrix: this app ships no Linux target, and
  // the MAC source is now the platform ArpReader on every platform. It was the
  // second representation the stale table was written against — keeping it as
  // dead code would just re-seed the drift.

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
    // Derive from THIS service's reader, not from platformArpReader(). Reading
    // the capability from one reader while reading MACs from another
    // (`_arpReader`, which tests inject) is two derivations of the single fact
    // this whole seam exists to unify — the defect one layer down, inside its
    // own fix.
    final ArpCapability cap =
        capabilityOverride ?? capabilityFor(readerOverride: _arpReader);
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
    bool arpCacheLoaded = false;
    MacReadOutcome macRead = MacReadOutcome.notAttempted;

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
          Neighbor? n;
          if (rttMs != null) {
            // Read the neighbor table lazily once we have any responder, so a
            // host that just answered has its freshly-learned MAC available.
            // Guard on "loaded", not on "cache is empty": a successful read
            // that returned NO entries is a valid result, and re-reading on
            // every responder would hammer the channel.
            //
            // NOTE the await below happens while this probe still counts as
            // ACTIVE. Decrementing `active`/incrementing `probed` before it
            // let a sibling probe observe probed >= total && active == 0 and
            // CLOSE the controller mid-read, so the tick carrying the read's
            // outcome was dropped and the sweep reported notAttempted after a
            // read that had in fact succeeded.
            if (cap == ArpCapability.sweepWithMac && !arpCacheLoaded) {
              arpCacheLoaded = true;
              final ArpReadResult r = await _arpReader.read();
              // THREE outcomes from two bits, never two. `available == false`
              // alone does not say which kind of failure it is — mapping it
              // straight to `failed` re-collapses `unsupported` into `failed`
              // and re-creates the exact defect this enum exists to prevent.
              macRead = !r.platformSupported
                  ? MacReadOutcome.notAttempted
                  : (r.available ? MacReadOutcome.ok : MacReadOutcome.failed);
              arpCache = r.available ? r.byIp : <String, String>{};
            }
            final String? mac =
                cap == ArpCapability.sweepWithMac ? arpCache[host] : null;
            found++;
            n = Neighbor(
              ip: host,
              mac: mac,
              rttMs: rttMs,
              fromArpTable: mac != null,
            );
          }
          // Only now is this probe finished.
          active--;
          probed++;
          if (!closed) {
            controller.add(ArpScanProgress(
              probed: probed,
              total: total,
              found: found,
              lastFound: n,
              macRead: macRead,
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

  /// Probe [host] for reachability: a completed connect (OPEN) OR an
  /// actively-refused one (REFUSED) both prove the host is up — a live host that
  /// refuses still answered at the IP layer. Only a DEAD probe (timeout,
  /// unreachable, host-down, lookup failure) counts as "not there".
  /// Returns the RTT in ms when up, else null.
  ///
  /// This used to run its own reachability test: `e.osError != null &&
  /// !_isUnreachable(e)`, where `_isUnreachable` looked for "unreachable" and
  /// "no route" but NOT "timed out". That was the hole — Dart's own
  /// connect-timeout carries a non-null osError, so every dead neighbour was
  /// discovered as present. The shared classifier now makes the call.
  Future<double?> _probe(String host, Duration timeout) async {
    final Stopwatch sw = Stopwatch()..start();
    for (final int port in probePorts) {
      try {
        final Socket s = await _connect(host, port, timeout: timeout);
        sw.stop();
        s.destroy();
        return sw.elapsedMicroseconds / 1000.0;
      } on Object catch (e) {
        if (classifyTcpError(e) == TcpProbeOutcome.refused) {
          // Host answered with a RST: it is there, this port is just closed.
          sw.stop();
          return sw.elapsedMicroseconds / 1000.0;
        }
        // DEAD on this port → try the next one.
        continue;
      }
    }
    sw.stop();
    return null;
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
