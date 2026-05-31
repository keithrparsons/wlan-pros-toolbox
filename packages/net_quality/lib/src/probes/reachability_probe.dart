import 'dart:async';
import 'dart:io';

import '../popular_sites.dart';

/// Probes [host]:[port] within [timeout] and returns the round-trip time, or
/// null if the host could not be reached. The injectable reachability seam.
typedef SiteProber = Future<Duration?> Function(
  String host,
  int port,
  Duration timeout,
);

/// Reachability outcome for a single site.
class SiteReachability {
  /// The site that was probed.
  final PopularSite site;

  /// Whether the connect succeeded.
  final bool reachable;

  /// Connect RTT in milliseconds, or null when unreachable.
  final double? latencyMs;

  /// Creates a reachability outcome.
  const SiteReachability({
    required this.site,
    required this.reachable,
    required this.latencyMs,
  });

  @override
  String toString() => 'SiteReachability(${site.name}, '
      '${reachable ? '${latencyMs?.toStringAsFixed(1)}ms' : 'unreachable'})';
}

/// Probes a set of popular sites for reachability, concurrently.
///
/// As with [LatencyProbe], this uses TCP-connect RTT rather than ICMP because
/// sandboxed macOS and iOS apps cannot open raw sockets. See GL-008.
class ReachabilityProbe {
  /// Sites to probe.
  final List<PopularSite> sites;

  /// Per-site timeout.
  final Duration timeout;

  /// Reachability seam; defaults to a real [Socket.connect] timing.
  final SiteProber prober;

  /// Creates a reachability probe.
  ReachabilityProbe({
    this.sites = kPopularSites,
    this.timeout = const Duration(seconds: 2),
    SiteProber? prober,
  }) : prober = prober ?? _defaultProber;

  /// Default prober: times a TCP connect, returning the RTT, or null on any
  /// failure or timeout.
  static Future<Duration?> _defaultProber(
    String host,
    int port,
    Duration timeout,
  ) async {
    try {
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(host, port, timeout: timeout);
      sw.stop();
      socket.destroy();
      return sw.elapsed;
    } catch (_) {
      return null;
    }
  }

  /// Probes all [sites] concurrently and returns results in input order.
  Future<List<SiteReachability>> measure() async {
    final futures = sites.map((site) async {
      final rtt = await prober(site.host, site.port, timeout);
      return SiteReachability(
        site: site,
        reachable: rtt != null,
        latencyMs: rtt == null ? null : rtt.inMicroseconds / 1000.0,
      );
    }).toList();
    return Future.wait(futures);
  }
}
