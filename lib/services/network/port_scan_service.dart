// PortScanService — TCP connect scan (no raw sockets).
//
// Method: for each target port, attempt `Socket.connect(host, port)` with a
// per-port timeout. Connect succeeds → OPEN. Connection actively refused
// (SocketException with a "refused"/"reset" signal) → CLOSED. Times out with
// no response → FILTERED (a firewall silently dropping the SYN). This is the
// same open/closed/filtered taxonomy nmap reports for a connect scan, and it
// needs no elevated privilege or raw-socket entitlement on any platform.
//
// Concurrency: connects run in bounded parallel batches (default 64 in
// flight) via a simple worker pool. A large custom range (say 1–65535) must
// never open tens of thousands of sockets at once — that exhausts file
// descriptors and trips OS connection-rate limits. The pool keeps exactly
// `concurrency` sockets live at a time and streams results as they land so the
// UI can render incrementally.
//
// Web safety: imports `dart:io` (Socket). Gated behind
// `NetworkSupport.portScanSupported` at the UI layer; never reached on web.
//
// The open/closed/filtered call itself is NOT made here — it is delegated to the
// shared classifier in `tcp_probe_classifier.dart`, the single source of truth
// for "did this host answer?" across every probe in the app.

import 'dart:async';
import 'dart:io';

import 'tcp_probe_classifier.dart';

/// Per-port scan outcome.
enum PortStatus {
  /// TCP handshake completed — service is listening.
  open,

  /// Connection actively refused / reset — host reachable, nothing listening.
  closed,

  /// No response before timeout — likely a firewall dropping the SYN.
  filtered,
}

/// One scanned port and its outcome.
class PortResult {
  const PortResult({
    required this.port,
    required this.status,
    this.serviceName,
    required this.elapsed,
  });

  final int port;
  final PortStatus status;

  /// Well-known service label for this port, if any (e.g. 443 → "HTTPS").
  final String? serviceName;

  /// How long the connect attempt took.
  final Duration elapsed;
}

/// Live progress of a scan, streamed to the UI.
class PortScanProgress {
  const PortScanProgress({
    required this.completed,
    required this.total,
    this.lastResult,
  });

  final int completed;
  final int total;

  /// The most recently completed port, or null for the initial 0/total tick.
  final PortResult? lastResult;

  double get fraction => total == 0 ? 0 : completed / total;
}

/// A named preset of common ports to scan.
class PortPreset {
  const PortPreset({required this.label, required this.ports});

  final String label;
  final List<int> ports;
}

/// TCP-connect port scanner. Injectable [connector] keeps it testable without
/// touching a live network.
class PortScanService {
  PortScanService({
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

  /// Common-ports preset — the HE.NET-style default the Port Scan screen
  /// offers before a custom range. Curated to the ports a Wi-Fi/network pro
  /// actually checks on a LAN host, not an exhaustive 1000-port list.
  static const PortPreset commonPorts = PortPreset(
    label: 'Common ports',
    ports: <int>[
      20, 21, 22, 23, 25, 53, 67, 80, 110, 123, 135, 139, 143, 161, 389,
      443, 445, 465, 514, 587, 631, 636, 993, 995, 1080, 1433, 1521, 1723,
      2049, 3128, 3306, 3389, 5060, 5201, 5353, 5432, 5900, 6379, 8000,
      8080, 8443, 8888, 9100, 27017,
    ],
  );

  /// Well-known service names for labeling results.
  static const Map<int, String> _serviceNames = <int, String>{
    20: 'FTP-DATA',
    21: 'FTP',
    22: 'SSH',
    23: 'Telnet',
    25: 'SMTP',
    53: 'DNS',
    67: 'DHCP',
    80: 'HTTP',
    110: 'POP3',
    123: 'NTP',
    135: 'MS-RPC',
    139: 'NetBIOS',
    143: 'IMAP',
    161: 'SNMP',
    389: 'LDAP',
    443: 'HTTPS',
    445: 'SMB',
    465: 'SMTPS',
    514: 'Syslog',
    587: 'SMTP-Sub',
    631: 'IPP',
    636: 'LDAPS',
    993: 'IMAPS',
    995: 'POP3S',
    1080: 'SOCKS',
    1433: 'MSSQL',
    1521: 'Oracle',
    1723: 'PPTP',
    2049: 'NFS',
    3128: 'Squid',
    3306: 'MySQL',
    3389: 'RDP',
    5060: 'SIP',
    5201: 'iperf3',
    5353: 'mDNS',
    5432: 'PostgreSQL',
    5900: 'VNC',
    6379: 'Redis',
    8000: 'HTTP-Alt',
    8080: 'HTTP-Proxy',
    8443: 'HTTPS-Alt',
    8888: 'HTTP-Alt',
    9100: 'JetDirect',
    27017: 'MongoDB',
  };

  /// Service label for [port], or null if unknown.
  static String? serviceFor(int port) => _serviceNames[port];

  /// Parse a custom port spec like `"22, 80, 443, 8000-8100"` into a sorted,
  /// de-duplicated, bounds-checked port list. Returns an empty list if nothing
  /// valid was found; the caller surfaces that as a validation error.
  static List<int> parsePortSpec(String spec) {
    final Set<int> ports = <int>{};
    for (final String chunkRaw in spec.split(RegExp(r'[,\s]+'))) {
      final String chunk = chunkRaw.trim();
      if (chunk.isEmpty) continue;
      if (chunk.contains('-')) {
        final List<String> ends = chunk.split('-');
        if (ends.length != 2) continue;
        final int? lo = int.tryParse(ends[0].trim());
        final int? hi = int.tryParse(ends[1].trim());
        if (lo == null || hi == null) continue;
        final int a = lo <= hi ? lo : hi;
        final int b = lo <= hi ? hi : lo;
        for (int p = a; p <= b; p++) {
          if (_validPort(p)) ports.add(p);
        }
      } else {
        final int? p = int.tryParse(chunk);
        if (p != null && _validPort(p)) ports.add(p);
      }
    }
    final List<int> out = ports.toList()..sort();
    return out;
  }

  static bool _validPort(int p) => p >= 1 && p <= 65535;

  /// Scan [ports] on [host] as a TCP-connect scan, streaming each port's
  /// result as it completes.
  ///
  /// - [timeout] bounds each individual connect (default 800ms — long enough
  ///   for a LAN host, short enough that a filtered port doesn't stall the UI).
  /// - [concurrency] caps sockets in flight (default 64).
  /// - [cancel] lets the UI abort mid-scan; the pool stops launching new
  ///   connects once it completes.
  Stream<PortScanProgress> scan({
    required String host,
    required List<int> ports,
    Duration timeout = const Duration(milliseconds: 800),
    int concurrency = 64,
    Future<void>? cancel,
  }) {
    final StreamController<PortScanProgress> controller =
        StreamController<PortScanProgress>();

    final List<int> queue = List<int>.of(ports);
    final int total = queue.length;
    int completed = 0;
    int index = 0;
    int active = 0;
    bool cancelled = false;
    bool closed = false;

    cancel?.then((_) => cancelled = true);

    void finishIfDone() {
      if (closed) return;
      if (cancelled && active == 0) {
        closed = true;
        controller.close();
        return;
      }
      if (completed >= total && active == 0) {
        closed = true;
        controller.close();
      }
    }

    void pump() {
      while (!cancelled && active < concurrency && index < queue.length) {
        final int port = queue[index++];
        active++;
        _probe(host, port, timeout).then((PortResult result) {
          active--;
          completed++;
          if (!closed) {
            controller.add(
              PortScanProgress(
                completed: completed,
                total: total,
                lastResult: result,
              ),
            );
          }
          if (cancelled) {
            finishIfDone();
          } else {
            pump();
            finishIfDone();
          }
        });
      }
      finishIfDone();
    }

    // Initial 0/total tick so the UI can render the progress bar immediately.
    controller.add(PortScanProgress(completed: 0, total: total));
    if (total == 0) {
      closed = true;
      controller.close();
    } else {
      pump();
    }

    return controller.stream;
  }

  /// Probe one port and map the three honest outcomes onto the three port
  /// states — they line up exactly:
  ///
  ///   OPEN    → [PortStatus.open]     handshake completed, something listening
  ///   REFUSED → [PortStatus.closed]   host answered with a RST: UP, not listening
  ///   DEAD    → [PortStatus.filtered] no answer at all (dropped, or host down)
  ///
  /// The DEAD → filtered mapping is the fix. The old code asked
  /// `e.osError == null && elapsed >= timeout - 50ms` to detect a timeout, but
  /// Dart's own connect-timeout carries a NON-null osError — so every port on a
  /// dead host was reported "closed", which tells a network pro the host is UP
  /// and actively refusing. The exact opposite of the truth. The errno is
  /// authoritative; the elapsed-time guess is gone.
  Future<PortResult> _probe(String host, int port, Duration timeout) async {
    final Stopwatch sw = Stopwatch()..start();
    try {
      final Socket socket = await _connect(host, port, timeout: timeout);
      sw.stop();
      // Connected → open. Tear the socket down immediately; we only needed the
      // handshake, not data.
      socket.destroy();
      return PortResult(
        port: port,
        status: PortStatus.open,
        serviceName: serviceFor(port),
        elapsed: sw.elapsed,
      );
    } on Object catch (e) {
      sw.stop();
      final TcpProbeOutcome outcome = classifyTcpError(e);
      return PortResult(
        port: port,
        status: outcome == TcpProbeOutcome.refused
            ? PortStatus.closed
            : PortStatus.filtered,
        serviceName: serviceFor(port),
        elapsed: sw.elapsed,
      );
    }
  }
}
