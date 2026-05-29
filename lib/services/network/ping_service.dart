// PingService — TCP-handshake reachability/latency probe.
//
// WHY TCP, NOT ICMP (deliberate, documented decision — read before changing):
//
// A true ICMP echo ping needs one of two things, neither of which is viable
// for this project's cross-platform, distribution-safe target:
//   1. A raw ICMP socket — requires root / a raw-socket entitlement Dart's
//      dart:io cannot open on any of the four targets without elevation.
//   2. The system `ping` binary spawned as a subprocess (the `dart_ping`
//      package's approach) — blocked by the macOS App Sandbox this project
//      enables (`com.apple.security.app-sandbox: true`), and impossible inside
//      the iOS/Android sandbox. `dart_ping_ios` (SimplePing) covers iOS only
//      and adds a native plugin + build risk we cannot verify without a device.
//
// So v1 measures the time to complete a *TCP three-way handshake* to a port on
// the target host. This is the same primitive the PortScanService already uses
// (`Socket.connect`), needs no entitlement, behaves identically on iOS /
// Android / macOS / Windows, and is fully unit-testable with an injected
// connector. It is a reachability + round-trip-latency probe, NOT ICMP echo —
// the UI states that plainly (it shows the target port and labels the metric
// "TCP RTT"). ICMP-via-SimplePing/dart_ping is a documented fast-follow once
// the iOS plugin build and macOS entitlement story are verified on a device.
//
// Behaviour parallels the network world's `tcping`/`paping` tools, which Wi-Fi
// and network pros already use precisely because ICMP is often filtered while
// a TCP port (443) answers.
//
// Web safety: imports dart:io (Socket). Gated behind
// `NetworkSupport.pingSupported` at the UI layer; never reached on web.

import 'dart:async';
import 'dart:io';

/// One probe attempt (one "ping").
class PingReply {
  const PingReply({
    required this.sequence,
    required this.success,
    this.rtt,
    this.errorLabel,
  });

  /// 1-based sequence number of this probe.
  final int sequence;

  /// True when the TCP handshake completed within the timeout.
  final bool success;

  /// Round-trip time of the handshake, or null on timeout/failure.
  final Duration? rtt;

  /// Short reason this probe failed (e.g. "timeout", "refused"), or null on
  /// success. Drives a precise per-reply line instead of a bare miss.
  final String? errorLabel;
}

/// Running aggregate over the replies seen so far. Recomputed on each reply so
/// the UI can show live min/avg/max/loss without re-scanning history.
class PingStats {
  const PingStats({
    required this.sent,
    required this.received,
    required this.minMs,
    required this.avgMs,
    required this.maxMs,
    required this.rttsMs,
  });

  final int sent;
  final int received;

  /// Min / avg / max RTT in milliseconds across successful replies. NaN-safe:
  /// null when there are zero successful replies yet.
  final double? minMs;
  final double? avgMs;
  final double? maxMs;

  /// Successful RTTs in milliseconds, in arrival order — feeds the sparkline.
  final List<double> rttsMs;

  int get lost => sent - received;

  /// Packet loss as a fraction 0..1. Zero when nothing has been sent.
  double get lossFraction => sent == 0 ? 0 : lost / sent;

  static const PingStats empty = PingStats(
    sent: 0,
    received: 0,
    minMs: null,
    avgMs: null,
    maxMs: null,
    rttsMs: <double>[],
  );

  /// Fold one more reply into the aggregate.
  PingStats accumulate(PingReply reply) {
    final List<double> rtts = List<double>.of(rttsMs);
    if (reply.success && reply.rtt != null) {
      rtts.add(reply.rtt!.inMicroseconds / 1000.0);
    }
    final int newSent = sent + 1;
    final int newReceived = received + (reply.success ? 1 : 0);
    double? mn;
    double? mx;
    double? av;
    if (rtts.isNotEmpty) {
      mn = rtts.first;
      mx = rtts.first;
      double sum = 0;
      for (final double v in rtts) {
        if (v < mn!) mn = v;
        if (v > mx!) mx = v;
        sum += v;
      }
      av = sum / rtts.length;
    }
    return PingStats(
      sent: newSent,
      received: newReceived,
      minMs: mn,
      avgMs: av,
      maxMs: mx,
      rttsMs: rtts,
    );
  }
}

/// A single tick streamed to the UI: the reply that just landed plus the
/// updated running aggregate.
class PingProgress {
  const PingProgress({required this.reply, required this.stats});

  final PingReply reply;
  final PingStats stats;
}

/// TCP-handshake ping. Injectable [connector] keeps it testable without a live
/// network (mirrors PortScanService).
class PingService {
  PingService({
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
  /// and routers, and is rarely firewall-dropped the way ICMP often is.
  static const int defaultPort = 443;

  /// Common probe-port presets a network pro reaches for.
  static const List<int> commonPorts = <int>[443, 80, 53, 22, 7];

  /// Stream [count] probes to [host]:[port], one every [interval], each bounded
  /// by [timeout]. Emits a [PingProgress] per probe with the running stats.
  ///
  /// - [count] <= 0 means continuous until [cancel] completes.
  /// - [cancel] lets the UI stop mid-run; no further probes are launched and
  ///   the stream closes after the in-flight probe settles.
  Stream<PingProgress> ping({
    required String host,
    int port = defaultPort,
    int count = 10,
    Duration interval = const Duration(seconds: 1),
    Duration timeout = const Duration(seconds: 2),
    Future<void>? cancel,
  }) {
    final StreamController<PingProgress> controller =
        StreamController<PingProgress>();
    bool cancelled = false;
    cancel?.then((_) => cancelled = true);

    Future<void> run() async {
      PingStats stats = PingStats.empty;
      int seq = 0;
      final bool continuous = count <= 0;
      while (!cancelled && (continuous || seq < count)) {
        seq++;
        final PingReply reply = await _probe(host, port, seq, timeout);
        if (cancelled) break;
        stats = stats.accumulate(reply);
        if (controller.isClosed) break;
        controller.add(PingProgress(reply: reply, stats: stats));

        final bool more = continuous || seq < count;
        if (!more || cancelled) break;
        // Space probes by `interval`, minus the time the probe already took,
        // so the cadence stays close to the requested interval under latency.
        final Duration spent = reply.rtt ?? timeout;
        final Duration wait =
            interval > spent ? interval - spent : Duration.zero;
        if (wait > Duration.zero) {
          await Future<void>.delayed(wait);
        }
      }
      if (!controller.isClosed) await controller.close();
    }

    // Kick off only when the stream is listened to, so an unlistened stream
    // does no I/O.
    controller.onListen = run;
    return controller.stream;
  }

  Future<PingReply> _probe(
    String host,
    int port,
    int seq,
    Duration timeout,
  ) async {
    final Stopwatch sw = Stopwatch()..start();
    try {
      final Socket socket = await _connect(host, port, timeout: timeout);
      sw.stop();
      socket.destroy();
      return PingReply(sequence: seq, success: true, rtt: sw.elapsed);
    } on SocketException catch (e) {
      sw.stop();
      // A refused/reset still proves the host is *reachable* and answered the
      // SYN with a RST — that is a successful round trip for latency purposes,
      // exactly how tcping treats it. Only a genuine timeout (no OS error,
      // elapsed ~ deadline) or a lookup failure counts as a loss.
      final bool refused = e.osError != null;
      if (refused) {
        return PingReply(sequence: seq, success: true, rtt: sw.elapsed);
      }
      final bool timedOut =
          sw.elapsed >= timeout - const Duration(milliseconds: 50);
      return PingReply(
        sequence: seq,
        success: false,
        errorLabel: timedOut ? 'timeout' : 'unreachable',
      );
    } on Object {
      sw.stop();
      return PingReply(sequence: seq, success: false, errorLabel: 'error');
    }
  }
}
