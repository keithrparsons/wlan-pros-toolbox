import 'dart:async';
import 'dart:io';

/// A function that opens a connection to [host]:[port] within [timeout] and
/// returns the time taken. Implementations should throw on failure or timeout.
///
/// This is the injectable seam that lets the latency probe be tested with no
/// real network.
typedef LatencyConnector = Future<Duration> Function(
  String host,
  int port,
  Duration timeout,
);

/// Aggregated latency statistics over a run of samples.
class LatencyStats {
  /// Mean RTT over successful samples, milliseconds. 0 when none succeeded.
  final double avgMs;

  /// Minimum RTT over successful samples, milliseconds. 0 when none succeeded.
  final double minMs;

  /// Maximum RTT over successful samples, milliseconds. 0 when none succeeded.
  final double maxMs;

  /// Jitter as RFC 3550-style mean deviation between consecutive successful
  /// samples, milliseconds. 0 with fewer than two successes.
  final double jitterMs;

  /// Sample loss percent: (sent - received) / sent * 100.
  final double lossPct;

  /// Number of samples attempted.
  final int sent;

  /// Number of samples that succeeded.
  final int received;

  /// Creates latency statistics.
  const LatencyStats({
    required this.avgMs,
    required this.minMs,
    required this.maxMs,
    required this.jitterMs,
    required this.lossPct,
    required this.sent,
    required this.received,
  });

  @override
  String toString() =>
      'LatencyStats(avg ${avgMs.toStringAsFixed(1)}ms, '
      'min ${minMs.toStringAsFixed(1)}ms, max ${maxMs.toStringAsFixed(1)}ms, '
      'jitter ${jitterMs.toStringAsFixed(1)}ms, '
      'loss ${lossPct.toStringAsFixed(1)}%, $received/$sent)';
}

/// Measures latency, jitter, and loss with sequential TCP connects.
///
/// We use TCP-connect RTT rather than ICMP ping because the macOS App Sandbox
/// (and iOS) block raw sockets for sandboxed apps. See GL-008. A SYN/SYN-ACK
/// round trip to a real host on port 443 is a faithful, sandbox-legal proxy.
class LatencyProbe {
  /// Host to connect to.
  final String host;

  /// Port to connect to. Defaults to 443 (HTTPS).
  final int port;

  /// Number of samples to take.
  final int samples;

  /// Per-sample timeout.
  final Duration timeout;

  /// Connection seam; defaults to a real [Socket.connect] timing.
  final LatencyConnector connector;

  /// Creates a latency probe.
  LatencyProbe({
    required this.host,
    this.port = 443,
    this.samples = 10,
    this.timeout = const Duration(seconds: 2),
    LatencyConnector? connector,
  }) : connector = connector ?? _defaultConnector;

  /// Default connector: opens a TCP socket, measures the connect time, and
  /// closes it immediately. Throws on failure or timeout.
  static Future<Duration> _defaultConnector(
    String host,
    int port,
    Duration timeout,
  ) async {
    final sw = Stopwatch()..start();
    final socket = await Socket.connect(host, port, timeout: timeout);
    sw.stop();
    socket.destroy();
    return sw.elapsed;
  }

  /// Runs the probe.
  ///
  /// Failures and timeouts count as lost samples; they are never thrown out of
  /// the result. With zero successes the result reports avg/min/max as 0 and
  /// loss as 100 percent.
  Future<LatencyStats> measure() async {
    final successesMs = <double>[];
    for (var i = 0; i < samples; i++) {
      try {
        final d = await connector(host, port, timeout);
        successesMs.add(d.inMicroseconds / 1000.0);
      } catch (_) {
        // Lost sample; intentionally swallowed.
      }
    }

    final received = successesMs.length;
    final lossPct =
        samples == 0 ? 0.0 : (samples - received) / samples * 100.0;

    if (received == 0) {
      return LatencyStats(
        avgMs: 0,
        minMs: 0,
        maxMs: 0,
        jitterMs: 0,
        lossPct: samples == 0 ? 0.0 : 100.0,
        sent: samples,
        received: 0,
      );
    }

    var sum = 0.0;
    var min = successesMs.first;
    var max = successesMs.first;
    for (final v in successesMs) {
      sum += v;
      if (v < min) min = v;
      if (v > max) max = v;
    }
    final avg = sum / received;

    // RFC 3550-style mean deviation between consecutive successful samples.
    var jitter = 0.0;
    if (received >= 2) {
      var diffSum = 0.0;
      for (var i = 1; i < received; i++) {
        diffSum += (successesMs[i] - successesMs[i - 1]).abs();
      }
      jitter = diffSum / (received - 1);
    }

    return LatencyStats(
      avgMs: avg,
      minMs: min,
      maxMs: max,
      jitterMs: jitter,
      lossPct: lossPct,
      sent: samples,
      received: received,
    );
  }
}
