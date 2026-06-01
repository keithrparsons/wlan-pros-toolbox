// TCP connect-scan core, isolate-runnable — Network Discovery (TICKET-HSD-02).
//
// The spine of the scanner (brief §5 + anti-pattern #1): bounded-concurrency
// `Socket.connect` across the subnet on a curated port set. NO ICMP — raw ICMP
// sockets are privileged on both mobile OSes.
//
// THREE honest probe outcomes, not two. A TCP connect probe to (host, port)
// settles one of three ways, and they must NOT be collapsed:
//   1. open    — the handshake completed. The port is genuinely OPEN. This is
//                the ONLY signal that feeds openPorts + the device-type
//                heuristic + the debug display.
//   2. refused — the host answered the SYN with a RST (ECONNREFUSED) or reset an
//                in-flight connection (ECONNRESET). The host is ALIVE but that
//                port is CLOSED. Proves liveness; does NOT open the port.
//   3. dead    — host/network unreachable or timeout (EHOSTUNREACH / EHOSTDOWN
//                / ENETUNREACH / ETIMEDOUT, or our own connect-timeout with a
//                null osError). NO host answered on this port. Contributes
//                nothing — not a port, not liveness.
//
// A host enters the result set iff it had ≥1 OPEN port OR ≥1 REFUSED response.
// A host that only ever produced DEAD outcomes is dropped. This is the fix for
// the on-device bug where dead IPs (which throw SocketException-with-osError for
// EHOSTUNREACH on iOS/macOS) were all being reported live with the full curated
// port set and stamped `Printer`.
//
// ISOLATE: the whole sweep (up to 254 hosts × 10 ports = ~2540 connects) is
// run off the UI isolate via Isolate.run in lan_discovery_engine.dart, so the
// app stays responsive during a full /24 sweep (brief anti-pattern #4). This
// file is the pure dart:io work the isolate runs. It is self-contained — it
// closes over only plain data (the request), never a Flutter object — so it is
// safe to ship to Isolate.run.
//
// The connector is injectable for unit tests (no real sockets), mirroring
// PingSweepService / PortScanService.

import 'dart:async';
import 'dart:io';

/// Immutable request describing one connect-scan. Plain data only, so it can
/// cross the isolate boundary.
class ConnectScanRequest {
  const ConnectScanRequest({
    required this.hosts,
    required this.ports,
    this.timeout = const Duration(milliseconds: 400),
    this.concurrency = 64,
  });

  /// Host IPs to probe.
  final List<String> hosts;

  /// Ports to probe on each host.
  final List<int> ports;

  /// Per-connect timeout. Short (~300–500ms) per the ticket — a LAN host
  /// answers fast or not at all.
  final Duration timeout;

  /// Maximum concurrent socket connects in flight (50–100 per the ticket).
  final int concurrency;
}

/// The three honest outcomes of a single TCP connect probe.
enum ProbeOutcome {
  /// Handshake completed — the port is genuinely OPEN.
  open,

  /// Host answered with a RST / reset the connection — ALIVE, port CLOSED.
  refused,

  /// Host/network unreachable or timeout — NO host answered on this port.
  dead,
}

/// One host's connect-scan result.
///
/// [openPorts] holds ONLY genuinely-open ports (a completed handshake). [alive]
/// is true when the host produced at least one OPEN or one REFUSED response —
/// i.e. something on that IP answered TCP, even if no probed port is open. Hosts
/// that only ever produced [ProbeOutcome.dead] are dropped before this is
/// returned, so every returned instance is alive.
class HostPorts {
  const HostPorts({
    required this.ip,
    required this.openPorts,
    this.alive = true,
  });

  /// The probed host IP.
  final String ip;

  /// Genuinely-open ports (completed handshake only). May be empty for a host
  /// that is alive but had every probed port closed (all refused).
  final List<int> openPorts;

  /// True when the host answered TCP on at least one probe (open OR refused).
  /// Always true for returned instances; dead-only hosts never get here.
  final bool alive;
}

/// Connector seam: returns an open socket or throws. Injectable for tests.
typedef Connector = Future<Socket> Function(
  String host,
  int port,
  Duration timeout,
);

/// Runs a TCP connect-scan with bounded concurrency and returns only the hosts
/// that answered TCP on at least one probe (open OR refused). Each returned
/// host's [HostPorts.openPorts] contains only genuinely-open ports. Pure
/// dart:io; no Flutter.
///
/// [onProgress] (optional) is called as each (host, port) probe settles, with
/// the running completed/total counts — used by the UI to drive a progress
/// bar. When the scan runs inside Isolate.run there is no progress callback
/// (closures can't cross the boundary); the engine reports coarse progress
/// instead. In-process callers (and tests) may pass one.
Future<List<HostPorts>> runConnectScan(
  ConnectScanRequest request, {
  Connector? connector,
  void Function(int completed, int total)? onProgress,
}) async {
  final Connector connect = connector ?? _defaultConnect;

  // Build the flat (host, port) work queue. Track open ports per host.
  final List<({String host, int port})> work = <({String host, int port})>[
    for (final String h in request.hosts)
      for (final int p in request.ports) (host: h, port: p),
  ];
  final int total = work.length;
  // Strictly-open ports per host (outcome #1 only).
  final Map<String, Set<int>> openByHost = <String, Set<int>>{};
  // Hosts that answered TCP at all (outcome #1 OR #2) — the liveness set.
  final Set<String> aliveHosts = <String>{};

  int index = 0;
  int completed = 0;
  int active = 0;
  final Completer<void> done = Completer<void>();

  void finishIfDone() {
    if (done.isCompleted) return;
    if (completed >= total && active == 0) done.complete();
  }

  void pump() {
    while (active < request.concurrency && index < work.length) {
      final ({String host, int port}) job = work[index++];
      active++;
      _probe(connect, job.host, job.port, request.timeout)
          .then((ProbeOutcome outcome) {
        active--;
        completed++;
        switch (outcome) {
          case ProbeOutcome.open:
            // #1: genuinely open → record the port AND mark host alive.
            (openByHost[job.host] ??= <int>{}).add(job.port);
            aliveHosts.add(job.host);
          case ProbeOutcome.refused:
            // #2: host answered (RST) but port closed → liveness only.
            aliveHosts.add(job.host);
          case ProbeOutcome.dead:
            // #3: nothing answered → contributes nothing.
            break;
        }
        onProgress?.call(completed, total);
        pump();
        finishIfDone();
      });
    }
    finishIfDone();
  }

  if (total == 0) return const <HostPorts>[];
  pump();
  await done.future;

  // Return only hosts that answered TCP (open or refused), in scan order, with
  // their genuinely-open ports ascending. Dead-only hosts are never included.
  final List<HostPorts> results = <HostPorts>[];
  for (final String h in request.hosts) {
    if (!aliveHosts.contains(h)) continue;
    final Set<int> ports = openByHost[h] ?? const <int>{};
    results.add(HostPorts(ip: h, openPorts: ports.toList()..sort()));
  }
  return results;
}

/// errno values for the only two errors that prove liveness (host answered).
/// They differ between the BSD family (iOS/macOS) and Linux (Android), so we
/// match BOTH so the classification is correct on every target, not iOS-only.
///
///   ECONNREFUSED — SYN answered with a RST: host alive, port closed.
///   ECONNRESET   — an established connection was reset by the peer.
///
/// Everything else (EHOSTUNREACH, EHOSTDOWN, ENETUNREACH, ETIMEDOUT, …) and a
/// null osError (our own connect-timeout) is DEAD: no host answered.
const Set<int> _kRefusedErrno = <int>{
  61, // ECONNREFUSED on macOS / iOS (BSD)
  54, // ECONNRESET   on macOS / iOS (BSD)
  111, // ECONNREFUSED on Linux / Android
  104, // ECONNRESET   on Linux / Android
};

/// Probe one (host, port) and classify the result into the three honest
/// outcomes. See [ProbeOutcome].
Future<ProbeOutcome> _probe(
  Connector connect,
  String host,
  int port,
  Duration timeout,
) async {
  try {
    final Socket socket = await connect(host, port, timeout);
    socket.destroy();
    return ProbeOutcome.open; // #1: handshake completed.
  } on SocketException catch (e) {
    // Classify by errno. ECONNREFUSED/ECONNRESET → the host answered (alive,
    // port closed). Crucially, EHOSTUNREACH/EHOSTDOWN/ENETUNREACH/ETIMEDOUT all
    // carry a NON-null osError on iOS/macOS too — the old code treated any
    // non-null osError as "alive", which is exactly why every dead IP looked
    // live with the full port set. We must match the refusal errnos
    // specifically, not "osError != null".
    final int? code = e.osError?.errorCode;
    if (code != null && _kRefusedErrno.contains(code)) {
      return ProbeOutcome.refused; // #2: alive, port closed.
    }
    // Belt-and-braces for platforms/locales where the errno isn't surfaced:
    // a message that names a refusal still counts as alive; unreachable/down/
    // timeout messages do NOT. Default is dead.
    final String msg = (e.osError?.message ?? e.message).toLowerCase();
    final bool unreachable = msg.contains('unreachable') ||
        msg.contains('no route') ||
        msg.contains('host is down') ||
        msg.contains('timed out') ||
        msg.contains('timeout');
    if (!unreachable &&
        (msg.contains('refused') || msg.contains('reset'))) {
      return ProbeOutcome.refused;
    }
    return ProbeOutcome.dead; // #3: nothing answered.
  } catch (_) {
    return ProbeOutcome.dead;
  }
}

Future<Socket> _defaultConnect(String host, int port, Duration timeout) {
  return Socket.connect(host, port, timeout: timeout);
}
