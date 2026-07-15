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

import 'network_target.dart';
import 'tcp_probe_classifier.dart';

/// Thrown into the TCP ping stream when the target hostname cannot be resolved
/// to any IP address.
///
/// Parallel to `IcmpUnresolvedHostException` (same wording) so BOTH ping tools
/// report an unresolvable name identically. It is deliberately DISTINCT from
/// packet loss: loss means a real host was contacted and did not answer, while
/// a resolution failure means no host was ever contacted, because the name
/// could not be turned into an address. Collapsing the two into one "100% loss"
/// summary is the misleading report this fixes (the two-kinds-of-null
/// distinction, GL-005). The screen surfaces [message] and renders no
/// packet-loss summary, because no probe was ever sent.
class PingUnresolvedHostException implements Exception {
  const PingUnresolvedHostException(this.host);

  /// The user-entered host string that failed to resolve.
  final String host;

  /// GL-004-clean, user-facing explanation. Verdict first (what happened), then
  /// what to do. No em dash.
  String get message =>
      'Couldn\'t resolve "$host". Check the name for a typo, or enter an IP '
      'address.';

  @override
  String toString() => message;
}

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

  /// True when the host ANSWERED within the timeout — either the handshake
  /// completed, or the host actively refused it with a RST. Both are real round
  /// trips (tcping semantics). A timeout, an unreachable host, or a failed name
  /// lookup is a LOST packet, not a success.
  final bool success;

  /// Round-trip time of the handshake, or null when the packet was lost. Never
  /// a synthetic value: a lost probe has no RTT.
  final Duration? rtt;

  /// Short reason this probe failed ("timeout", "unreachable", "lookup failed",
  /// "error"), or null on success. Drives a precise per-reply line instead of a
  /// bare miss.
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
    Future<String?> Function(String host)? resolver,
  })  : _connect = connector ?? _defaultConnect,
        _resolve = resolver ?? _defaultResolve;

  final Future<Socket> Function(String host, int port,
      {required Duration timeout}) _connect;

  /// How a hostname becomes an IP for the pre-probe resolvability gate.
  /// Injected in tests so the resolve-failure path is exercised with zero DNS
  /// (mirrors the IcmpService resolver seam).
  final Future<String?> Function(String host) _resolve;

  static Future<Socket> _defaultConnect(
    String host,
    int port, {
    required Duration timeout,
  }) {
    return Socket.connect(host, port, timeout: timeout);
  }

  /// Real DNS resolution. Returns the first address, or null on any failure —
  /// an unresolvable host is a normal outcome here, not an exception.
  static Future<String?> _defaultResolve(String host) async {
    try {
      final List<InternetAddress> addrs = await InternetAddress.lookup(host);
      if (addrs.isEmpty) return null;
      return addrs.first.address;
    } on Object {
      return null;
    }
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
      // Resolve the target BEFORE probing so a name that cannot be resolved is
      // reported honestly as a resolution failure (a [PingUnresolvedHostException]
      // on the stream) and NEVER summarized as 100% packet loss. Parity with
      // IcmpService.ping. An IP literal is its own resolution and skips DNS
      // entirely, so its behavior is unchanged; on success we probe the ORIGINAL
      // host string (Socket.connect resolves again as before) so the actual
      // target is untouched — this resolve is purely the is-it-resolvable gate.
      final String h = host.trim();
      if (!(NetworkTarget.isIpv4(h) || NetworkTarget.isIpv6(h))) {
        final String? resolved = await _resolve(h);
        if (cancelled) {
          if (!controller.isClosed) await controller.close();
          return;
        }
        if (resolved == null) {
          if (!controller.isClosed) {
            controller.addError(PingUnresolvedHostException(h));
            await controller.close();
          }
          return;
        }
      }

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

  /// One probe. OPEN or REFUSED is a successful round trip (a RST proves the
  /// host answered the SYN — exactly how tcping treats it, and the RTT is
  /// real). DEAD — timeout, unreachable, host-down, lookup failure — is a LOST
  /// packet: no RTT, and it feeds packet loss.
  ///
  /// The old code asked `e.osError != null` and called that "refused". Dart
  /// stamps a synthetic errno on its OWN connect-timeout, so a DEAD host came
  /// back `success: true` with a fake RTT equal to the timeout — which meant
  /// Ping could never report packet loss at all. The classifier owns this call
  /// now; the elapsed-time guess is gone (the errno is authoritative).
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
    } on Object catch (e) {
      sw.stop();
      final TcpProbeFailure failure = classifyTcpFailure(e);
      if (failure.hostAnswered) {
        // REFUSED: a real round trip. Keep the RTT.
        return PingReply(sequence: seq, success: true, rtt: sw.elapsed);
      }
      return PingReply(
        sequence: seq,
        success: false,
        errorLabel: _labelFor(failure.reason),
      );
    }
  }

  /// Short, precise reason for the per-reply line. Never "refused" — a refusal
  /// is a success here, not a failure.
  static String _labelFor(TcpFailureReason reason) => switch (reason) {
        TcpFailureReason.timedOut => 'timeout',
        TcpFailureReason.unreachable => 'unreachable',
        TcpFailureReason.lookupFailure => 'lookup failed',
        TcpFailureReason.unknown => 'error',
        // Unreachable in practice: a refusal never reaches this method.
        TcpFailureReason.refused => 'refused',
      };
}
