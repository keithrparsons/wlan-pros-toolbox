// SPIKE-HSD-01 — TCP connect-scan core, isolate-runnable (THROWAWAY spike).
//
// The spine of the scanner (brief §5 + anti-pattern #1): bounded-concurrency
// `Socket.connect` across the subnet on a curated port set. NO ICMP — raw ICMP
// sockets are privileged on both mobile OSes. A completed handshake OR an
// actively-refused RST means the host answered on that port (the same honest
// rule PingSweepService uses: this proves "responds on TCP port N", not full
// liveness).
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

/// One host's open-port result from the connect-scan.
class HostPorts {
  const HostPorts({required this.ip, required this.openPorts});

  /// The probed host IP.
  final String ip;

  /// Ports that answered (handshake or RST). Empty hosts are dropped before
  /// this is returned, so an instance always has at least one open port.
  final List<int> openPorts;
}

/// Connector seam: returns an open socket or throws. Injectable for tests.
typedef Connector = Future<Socket> Function(
  String host,
  int port,
  Duration timeout,
);

/// Runs a TCP connect-scan with bounded concurrency and returns only the hosts
/// that answered on at least one port. Pure dart:io; no Flutter.
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
  final Map<String, Set<int>> openByHost = <String, Set<int>>{};

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
      _probe(connect, job.host, job.port, request.timeout).then((bool open) {
        active--;
        completed++;
        if (open) {
          (openByHost[job.host] ??= <int>{}).add(job.port);
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

  // Return only responsive hosts, ports ascending, hosts in scan order.
  final List<HostPorts> results = <HostPorts>[];
  for (final String h in request.hosts) {
    final Set<int>? ports = openByHost[h];
    if (ports != null && ports.isNotEmpty) {
      results.add(HostPorts(ip: h, openPorts: ports.toList()..sort()));
    }
  }
  return results;
}

/// Probe one (host, port): true if the host answered (handshake or RST).
Future<bool> _probe(
  Connector connect,
  String host,
  int port,
  Duration timeout,
) async {
  try {
    final Socket socket = await connect(host, port, timeout);
    socket.destroy();
    return true;
  } on SocketException catch (e) {
    // A real OS error (connection refused / reset) means the host answered the
    // SYN with a RST → it is reachable on TCP. A null osError is our own
    // connect timeout → no answer on this port.
    return e.osError != null;
  } catch (_) {
    return false;
  }
}

Future<Socket> _defaultConnect(String host, int port, Duration timeout) {
  return Socket.connect(host, port, timeout: timeout);
}
