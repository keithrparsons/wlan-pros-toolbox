// PingSweepService — discover responsive hosts on a subnet by running the
// existing TCP-handshake probe across a range of addresses. NO subprocess.
//
// WHY TCP, NOT ICMP (deliberate, documented — read before changing):
//
// A subnet "ping sweep" classically shells out to `/sbin/ping` (or `fping` /
// `nmap -sn`) once per host. Every one of those is a subprocess spawn, which
// the macOS App Sandbox blocks and iOS has no shell for — the documented
// GL-008 trap. There is also no raw-ICMP socket available to dart:io on any of
// the four targets without elevation.
//
// So a sweep here is exactly the same primitive PingService and PortScanService
// already use: a TCP three-way handshake (`Socket.connect`) to a common port on
// each candidate host. A completed handshake (or an actively-refused RST) proves
// the host answered on TCP; a timeout means no answer on that port. This needs
// no entitlement, behaves identically on iOS / Android / macOS / Windows, and
// is fully unit-testable with an injected connector. It parallels the network
// world's `tcping`-style sweepers, which pros already use because ICMP is often
// filtered while a TCP port (443) answers.
//
// HONESTY BAR (GL-008 honesty corollary, GL-005): a TCP-probe response means
// "responds on TCP port N", NOT "host is up". A host silent on the probed port
// may still be alive (ICMP-only, or the port is firewalled). The service models
// this precisely — a host is only ever reported as `responded`, never "up" —
// and the UI states the method and its limitation. Never claim ICMP-style
// liveness.
//
// Concurrency: connects run in a bounded worker pool (default 32 in flight),
// same shape as PortScanService. A /24 is 254 hosts; opening 254 sockets at
// once would exhaust file descriptors and trip OS connection-rate limits, so
// the pool keeps exactly `concurrency` live and streams results as they land.
//
// Web safety: imports dart:io (Socket). Gated behind
// `NetworkSupport.pingSweepSupported` at the UI layer; never reached on web.

import 'dart:async';
import 'dart:io';

import 'tcp_probe_classifier.dart';

/// Why a sweep spec was rejected before any socket opened. Drives a precise,
/// non-apologetic inline message instead of a silent no-op or a crash.
enum SweepSpecError {
  /// The string is neither a parseable CIDR nor a base+range.
  malformed,

  /// Parsed fine, but the host count exceeds [PingSweepService.maxHosts].
  tooLarge,
}

/// A validated, ready-to-sweep set of hosts. Either [hosts] is non-empty and
/// [error] is null (valid), or [hosts] is empty and [error] explains why.
class SweepSpec {
  const SweepSpec._({
    required this.hosts,
    required this.label,
    this.error,
    this.requestedCount = 0,
  });

  factory SweepSpec.valid({
    required List<String> hosts,
    required String label,
  }) =>
      SweepSpec._(hosts: hosts, label: label, requestedCount: hosts.length);

  factory SweepSpec.invalid(
    SweepSpecError error, {
    String label = '',
    int requestedCount = 0,
  }) =>
      SweepSpec._(
        hosts: const <String>[],
        label: label,
        error: error,
        requestedCount: requestedCount,
      );

  /// The concrete IPv4 addresses to probe, in ascending order.
  final List<String> hosts;

  /// Human-readable description of the range (e.g. "192.168.1.1–192.168.1.254").
  final String label;

  /// Null when the spec is valid; otherwise the rejection reason.
  final SweepSpecError? error;

  /// How many hosts the user's input expanded to (even when rejected as too
  /// large) — lets the UI say "that's N hosts, the cap is M".
  final int requestedCount;

  bool get isValid => error == null && hosts.isNotEmpty;
}

/// One host's sweep outcome.
class SweepHostResult {
  const SweepHostResult({
    required this.host,
    required this.responded,
    this.rtt,
    this.answer,
  });

  /// The probed IPv4 address.
  final String host;

  /// True when the host ANSWERED on the probed port — the handshake completed,
  /// or the host actively refused it with a RST. NOT a liveness claim.
  final bool responded;

  /// Round-trip time of the answer, or null when the host did not respond.
  final Duration? rtt;

  /// HOW the host answered: [TcpProbeOutcome.open] (handshake completed) or
  /// [TcpProbeOutcome.refused] (RST — the host answered, port closed). Null
  /// when the host did not answer at all.
  ///
  /// This is surfaced to the user, on screen AND in the copied report. A
  /// refusal counting as "responded" is correct, but it must be VISIBLE: a
  /// middlebox RSTing on behalf of every address would otherwise produce a
  /// report reading "254 of 254 hosts responded" with nothing to distinguish it
  /// from 254 genuinely-listening hosts. That is the exact string that started
  /// this investigation, and the reader of a pasted report never saw the screen.
  final TcpProbeOutcome? answer;

  /// True when the host answered by actively REFUSING (a RST). It is there, but
  /// nothing is listening on the probed port.
  bool get refused => answer == TcpProbeOutcome.refused;

  double? get rttMs => rtt == null ? null : rtt!.inMicroseconds / 1000.0;
}

/// Live progress streamed to the UI as each host settles.
class SweepProgress {
  const SweepProgress({
    required this.completed,
    required this.total,
    required this.live,
    this.lastResponsive,
  });

  /// Hosts probed so far (responsive + silent).
  final int completed;

  /// Total hosts in the sweep.
  final int total;

  /// Count of responsive hosts so far.
  final int live;

  /// The most recent responsive host, or null for ticks where the settled host
  /// was silent (or the initial 0/total tick).
  final SweepHostResult? lastResponsive;

  double get fraction => total == 0 ? 0 : completed / total;
}

/// TCP-handshake subnet sweeper. Injectable [connector] keeps it testable
/// without a live network (mirrors PingService / PortScanService).
class PingSweepService {
  PingSweepService({
    Future<Socket> Function(String host, int port, {required Duration timeout})?
        connector,
  }) : _connect = connector ?? _defaultConnect;

  final Future<Socket> Function(String host, int port,
      {required Duration timeout}) _connect;

  static Future<Socket> _defaultConnect(
    String host,
    int port, {
    required Duration timeout,
  }) {
    return Socket.connect(host, port, timeout: timeout);
  }

  /// Default probe port. 443 answers on the vast majority of reachable hosts
  /// and routers and is rarely firewall-dropped the way ICMP often is. Matches
  /// PingService.defaultPort.
  static const int defaultPort = 443;

  /// Common probe ports a sweep can target. A host is reported responsive if it
  /// answers on ANY of the probed ports.
  static const List<int> commonPorts = <int>[443, 80, 22, 53];

  /// Hard cap on sweep size. A /24 (254 usable hosts) is the sensible ceiling
  /// for an on-LAN TCP sweep — bigger ranges take too long, open too many
  /// sockets, and aren't what this tool is for. Anything larger is rejected
  /// with [SweepSpecError.tooLarge] — never silently truncated (GL-005).
  static const int maxHosts = 254;

  /// Parse and validate a sweep spec. Accepts:
  ///  - CIDR:        "192.168.1.0/24"
  ///  - base+range:  "192.168.1.10-192.168.1.40" or "192.168.1.10-40"
  ///  - single host: "192.168.1.5" (a one-host sweep)
  ///
  /// Returns a [SweepSpec]: valid (hosts populated) or invalid (with reason).
  /// Pure and side-effect-free — exposed for unit tests, opens no sockets.
  static SweepSpec parseSpec(String raw) {
    final String spec = raw.trim();
    if (spec.isEmpty) return SweepSpec.invalid(SweepSpecError.malformed);

    if (spec.contains('/')) return _parseCidr(spec);
    if (spec.contains('-')) return _parseRange(spec);

    // A bare single IPv4 → a one-host sweep.
    final int? single = _ipToInt(spec);
    if (single == null) return SweepSpec.invalid(SweepSpecError.malformed);
    return SweepSpec.valid(hosts: <String>[_intToIp(single)], label: spec);
  }

  static SweepSpec _parseCidr(String spec) {
    final List<String> parts = spec.split('/');
    if (parts.length != 2) return SweepSpec.invalid(SweepSpecError.malformed);
    final int? base = _ipToInt(parts[0].trim());
    final int? prefix = int.tryParse(parts[1].trim());
    if (base == null || prefix == null || prefix < 0 || prefix > 32) {
      return SweepSpec.invalid(SweepSpecError.malformed);
    }

    // Total addresses in the block.
    final int blockSize = prefix == 0 ? (1 << 32) : (1 << (32 - prefix));
    // Network address (mask off host bits).
    final int mask =
        prefix == 0 ? 0 : ((0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF);
    final int network = base & mask;

    // Usable host range. For /31 and /32 there is no network/broadcast split,
    // so every address is a probe target; otherwise exclude network and
    // broadcast addresses (the .0 and .255 of a /24).
    final int firstHost;
    final int lastHost;
    if (prefix >= 31) {
      firstHost = network;
      lastHost = network + blockSize - 1;
    } else {
      firstHost = network + 1;
      lastHost = network + blockSize - 2;
    }

    final int count = lastHost - firstHost + 1;
    if (count > maxHosts) {
      return SweepSpec.invalid(
        SweepSpecError.tooLarge,
        label: spec,
        requestedCount: count,
      );
    }
    return _build(firstHost, lastHost, spec);
  }

  static SweepSpec _parseRange(String spec) {
    final int dash = spec.indexOf('-');
    final String lhs = spec.substring(0, dash).trim();
    final String rhs = spec.substring(dash + 1).trim();

    final int? start = _ipToInt(lhs);
    if (start == null) return SweepSpec.invalid(SweepSpecError.malformed);

    int? end;
    if (rhs.contains('.')) {
      // Full end address: "192.168.1.10-192.168.1.40".
      end = _ipToInt(rhs);
    } else {
      // Last-octet shorthand: "192.168.1.10-40" → replace the final octet.
      final int? lastOctet = int.tryParse(rhs);
      if (lastOctet == null || lastOctet < 0 || lastOctet > 255) {
        return SweepSpec.invalid(SweepSpecError.malformed);
      }
      end = (start & 0xFFFFFF00) | lastOctet;
    }
    if (end == null) return SweepSpec.invalid(SweepSpecError.malformed);
    if (end < start) return SweepSpec.invalid(SweepSpecError.malformed);

    final int count = end - start + 1;
    if (count > maxHosts) {
      return SweepSpec.invalid(
        SweepSpecError.tooLarge,
        label: spec,
        requestedCount: count,
      );
    }
    return _build(start, end, spec);
  }

  static SweepSpec _build(int first, int last, String rawLabel) {
    final List<String> hosts = <String>[
      for (int a = first; a <= last; a++) _intToIp(a),
    ];
    final String label = hosts.length == 1
        ? hosts.first
        : '${_intToIp(first)}–${_intToIp(last)}';
    return SweepSpec.valid(hosts: hosts, label: label);
  }

  /// IPv4 dotted-quad → 32-bit int, or null if malformed.
  static int? _ipToInt(String ip) {
    final List<String> octets = ip.split('.');
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

  /// 32-bit int → IPv4 dotted-quad.
  static String _intToIp(int value) {
    final int v = value & 0xFFFFFFFF;
    return '${(v >> 24) & 0xFF}.${(v >> 16) & 0xFF}.'
        '${(v >> 8) & 0xFF}.${v & 0xFF}';
  }

  /// Sweep every host in [spec], probing [ports] per host with a per-host
  /// [timeout] and a bounded [concurrency] worker pool. Emits a [SweepProgress]
  /// as each host settles, with the running live/total tally.
  ///
  /// - The [spec] must be valid; an invalid spec yields a single completed/total
  ///   = 0/0 tick and closes (the UI validates before calling, but this keeps
  ///   the stream contract honest).
  /// - A host counts as responsive the moment ANY probed port answers; the
  ///   remaining ports for that host are not probed (first-answer wins).
  /// - [cancel] lets the UI abort mid-sweep; the pool stops launching new
  ///   probes once it completes and closes after in-flight probes settle.
  Stream<SweepProgress> sweep({
    required SweepSpec spec,
    List<int> ports = const <int>[defaultPort],
    Duration timeout = const Duration(milliseconds: 600),
    int concurrency = 32,
    Future<void>? cancel,
  }) {
    final StreamController<SweepProgress> controller =
        StreamController<SweepProgress>();

    final List<String> queue = List<String>.of(spec.hosts);
    final List<int> probePorts =
        ports.isEmpty ? const <int>[defaultPort] : ports;
    final int total = queue.length;
    int completed = 0;
    int live = 0;
    int index = 0;
    int active = 0;
    bool cancelled = false;
    bool closed = false;

    cancel?.then((_) => cancelled = true);

    void finishIfDone() {
      if (closed) return;
      if ((cancelled || completed >= total) && active == 0) {
        closed = true;
        controller.close();
      }
    }

    void pump() {
      while (!cancelled && active < concurrency && index < queue.length) {
        final String host = queue[index++];
        active++;
        _probeHost(host, probePorts, timeout).then((SweepHostResult result) {
          active--;
          completed++;
          if (result.responded) live++;
          if (!closed) {
            controller.add(
              SweepProgress(
                completed: completed,
                total: total,
                live: live,
                lastResponsive: result.responded ? result : null,
              ),
            );
          }
          if (!cancelled) pump();
          finishIfDone();
        });
      }
      finishIfDone();
    }

    // Initial 0/total tick so the UI can render the progress bar immediately.
    controller.add(SweepProgress(completed: 0, total: total, live: 0));
    if (total == 0) {
      closed = true;
      controller.close();
    } else {
      pump();
    }

    return controller.stream;
  }

  /// Probe one host across [ports]; first port to answer wins.
  ///
  /// The host "responded" iff a probe came back OPEN (handshake completed) or
  /// REFUSED (the host answered our SYN with a RST — tcping semantics). A DEAD
  /// probe (timeout, unreachable, host-down, lookup failure) answers nothing:
  /// try the next port, and if every port is dead the host is NOT listed and
  /// NOT counted in `live`.
  ///
  /// The classification is [classifyTcpError]'s job, not ours. The old code here
  /// asked `e.osError != null` and called that "the host answered" — which is
  /// how a /24 of dead IPs reported "254 / 254 · 254 live". Dart stamps a
  /// synthetic errno on its OWN connect-timeout. See tcp_probe_classifier.dart.
  Future<SweepHostResult> _probeHost(
    String host,
    List<int> ports,
    Duration timeout,
  ) async {
    for (final int port in ports) {
      final Stopwatch sw = Stopwatch()..start();
      try {
        final Socket socket = await _connect(host, port, timeout: timeout);
        sw.stop();
        socket.destroy();
        return SweepHostResult(
          host: host,
          responded: true,
          rtt: sw.elapsed,
          answer: TcpProbeOutcome.open,
        );
      } on Object catch (e) {
        sw.stop();
        if (classifyTcpError(e) == TcpProbeOutcome.refused) {
          // The host answered with a RST: alive, this port closed.
          return SweepHostResult(
            host: host,
            responded: true,
            rtt: sw.elapsed,
            answer: TcpProbeOutcome.refused,
          );
        }
        // DEAD on this port → try the next one.
      }
    }
    return SweepHostResult(host: host, responded: false);
  }
}
