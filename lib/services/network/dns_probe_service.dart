// DnsProbeService — measures DNS RESOLUTION TIME using the device's own
// resolver (Keith #3).
//
// WHAT IT MEASURES (and what it does NOT): this is a genuine, timed
// name-resolution. It calls `InternetAddress.lookup(host)` and times the round
// trip with a [Stopwatch]. That call resolves through the OS resolver — i.e.
// the DNS server(s) the device is actually configured to use on this network —
// so the number is the real wall-clock time to turn a hostname into an IP on
// THIS connection. It is reported and labelled as "DNS resolution time", never
// as anything else (GL-005). It is distinct from the net_quality engine, which
// measures throughput / latency / loss and produces NO DNS figure — that is why
// the connection report previously carried no DNS line at all.
//
// PLATFORM / SANDBOX (GL-008): `InternetAddress.lookup` is the cross-platform
// path. It is a native resolver call inside the app's own process — NOT a
// subprocess, NOT a CLI spawn — so it is safe inside the sandboxed macOS App
// Store build and works on iOS, where there is no shell. It needs only the
// `network.client` entitlement the app already ships.
//
// HONESTY: a lookup that fails (offline, captive portal, NXDOMAIN, timeout)
// produces an honest [DnsProbeResult.unavailable] — never a fabricated time.
// The probe tries a small set of well-known, stable hostnames and reports the
// FIRST that resolves, so one dead name does not mark DNS unavailable when the
// resolver is in fact working.
//
// Web safety: this file imports `dart:io`. It is only ever constructed behind
// the same `NetworkSupport` gate the rest of Test My Connection sits behind
// (the browser has no `InternetAddress.lookup`), so the web build never reaches
// it.

import 'dart:io';

/// The outcome of one DNS resolution-time probe.
///
/// Either a real measured [millis] for the [host] that resolved, or the honest
/// unavailable state (no host resolved / offline). Immutable.
class DnsProbeResult {
  const DnsProbeResult._({this.host, this.millis});

  /// A successful probe: [host] resolved in [millis] milliseconds.
  factory DnsProbeResult.success({
    required String host,
    required int millis,
  }) =>
      DnsProbeResult._(host: host, millis: millis);

  /// The honest unavailable state — no probed host resolved (offline, blocked,
  /// or every lookup timed out). Never carries a fabricated time (GL-005).
  factory DnsProbeResult.unavailable() => const DnsProbeResult._();

  /// The hostname that resolved, or null when unavailable.
  final String? host;

  /// Measured resolution time in milliseconds, or null when unavailable.
  final int? millis;

  /// True when a real resolution time was measured.
  bool get isAvailable => millis != null;
}

/// Measures DNS resolution time via the device's configured resolver. The
/// [resolver] seam keeps it unit-testable without a live network — a test
/// injects a fake that returns a controlled duration or throws.
class DnsProbeService {
  DnsProbeService({
    List<String>? hosts,
    Future<List<InternetAddress>> Function(String host)? resolver,
    Duration? timeout,
  })  : _hosts = hosts ?? _defaultHosts,
        _lookup = resolver ?? InternetAddress.lookup,
        _timeout = timeout ?? const Duration(seconds: 5);

  /// The hostnames probed, in order. Stable, widely-resolvable names so a real
  /// failure means the resolver path is genuinely broken, not that one name is
  /// down. The first to resolve wins; the rest are not tried.
  final List<String> _hosts;
  final Future<List<InternetAddress>> Function(String host) _lookup;
  final Duration _timeout;

  static const List<String> _defaultHosts = <String>[
    'cloudflare.com',
    'google.com',
    'apple.com',
  ];

  /// Resolve the probe hosts in order and report the resolution time of the
  /// first that succeeds. Returns [DnsProbeResult.unavailable] when none
  /// resolve within the timeout. Never throws to the caller.
  Future<DnsProbeResult> measure() async {
    for (final String host in _hosts) {
      final Stopwatch sw = Stopwatch()..start();
      try {
        final List<InternetAddress> addrs =
            await _lookup(host).timeout(_timeout);
        sw.stop();
        if (addrs.isNotEmpty) {
          return DnsProbeResult.success(
            host: host,
            millis: sw.elapsedMilliseconds,
          );
        }
        // Empty answer — try the next host rather than reporting a 0 ms "hit".
      } catch (_) {
        // This host failed (offline / NXDOMAIN / timeout) — try the next one.
      }
    }
    return DnsProbeResult.unavailable();
  }
}
