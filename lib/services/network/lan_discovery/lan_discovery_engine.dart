// SPIKE-HSD-01 — LAN Discovery engine (THROWAWAY spike).
//
// Orchestrates the four scan passes into a single discovery run, mirroring the
// net_quality engine shape: a client that emits a Stream<DiscoveryProgress> and
// finishes with a result, depending only on injectable seams so the whole thing
// is testable with no real network.
//
// PASSES (in order):
//  1. Subnet seed   — derive the local /24 host list (network_info_plus).
//  2. Connect-scan  — bounded-concurrency TCP connect across the /24 × curated
//                     ports, RUN IN AN ISOLATE (Isolate.run) so the UI stays
//                     responsive during a full sweep (brief anti-pattern #4).
//  3. Reverse DNS   — InternetAddress.reverse() per discovered host.
//  4. mDNS browse   — multicast_dns browse, folded onto the host records.
//  Then the pure device-type heuristic runs on each host's ports + services.
//
// HONESTY: any single pass can fail without aborting the run. A failed mDNS
// browse just means no mDNS enrichment; a host with no PTR keeps a null
// hostname. Nothing is faked (GL-005).

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'connect_scan.dart';
import 'curated_ports.dart';
import 'device_type.dart';
import 'lan_host.dart';
import 'mdns_browse.dart';
import 'multicast_lock.dart';
import 'subnet_seed.dart';

/// Phases a discovery run passes through, in order.
enum DiscoveryPhase {
  idle,
  seeding, // deriving the subnet
  scanning, // TCP connect-scan across the /24
  resolving, // reverse DNS per host
  mdns, // mDNS browse
  complete,
  failed,
}

/// A progress event emitted during a discovery run.
class DiscoveryProgress {
  const DiscoveryProgress(this.phase, this.fraction, {this.note});

  final DiscoveryPhase phase;

  /// Overall completion fraction 0.0–1.0, monotonic.
  final double fraction;

  /// Optional human note for the debug screen (e.g. the derived subnet label).
  final String? note;

  @override
  String toString() =>
      'DiscoveryProgress(${phase.name}, ${fraction.toStringAsFixed(2)})';
}

/// The result of one discovery run.
class DiscoveryResult {
  const DiscoveryResult({
    required this.hosts,
    required this.subnetLabel,
    this.selfIp,
    this.gateway,
    this.error,
  });

  /// Discovered hosts, enriched, ascending by IP.
  final List<LanHost> hosts;

  /// Human label of the scanned range (e.g. "192.168.1.1–192.168.1.254").
  final String subnetLabel;

  final String? selfIp;
  final String? gateway;

  /// Null on success; a short reason when the run could not start (e.g. no
  /// subnet). A run that started but found nothing is success with empty hosts.
  final String? error;
}

/// Reverse-DNS seam: IP → hostname or null. Injectable for tests.
typedef ReverseDnsResolver = Future<String?> Function(String ip);

/// The discovery engine. Depends only on injectable seams.
class LanDiscoveryEngine {
  LanDiscoveryEngine({
    SubnetSeedDeriver? seedDeriver,
    MdnsBrowser? mdnsBrowser,
    MulticastLock? multicastLock,
    ReverseDnsResolver? reverseDns,
    List<int>? ports,
    this._connectTimeout = const Duration(milliseconds: 400),
    this._concurrency = 64,
    this.runInIsolate = true,
    this._connectScanRunner,
  })  : _seedDeriver = seedDeriver ?? SubnetSeedDeriver(),
        _mdnsBrowser = mdnsBrowser ?? MdnsBrowser(),
        _multicastLock = multicastLock ?? platformMulticastLock(),
        _reverseDns = reverseDns ?? _defaultReverseDns,
        _ports = ports ?? CuratedPorts.all;

  final SubnetSeedDeriver _seedDeriver;
  final MdnsBrowser _mdnsBrowser;
  final MulticastLock _multicastLock;
  final ReverseDnsResolver _reverseDns;
  final List<int> _ports;
  final Duration _connectTimeout;
  final int _concurrency;

  /// When true, the connect-scan runs in a background isolate. Tests set false
  /// so an injected in-process connector (via [_connectScanRunner]) is used.
  final bool runInIsolate;

  /// Test seam: replaces the whole connect-scan pass (so tests skip the isolate
  /// and inject a fake connector). Null in production.
  final ConnectScanRunner? _connectScanRunner;

  /// Runs one discovery pass, emitting progress and finishing with a result.
  Stream<DiscoveryProgress> run() async* {
    // --- 1. Subnet seed ---
    yield const DiscoveryProgress(DiscoveryPhase.seeding, 0.02);
    final SubnetSeed seed = await _seedDeriver.derive();
    if (!seed.isValid) {
      _lastResult = DiscoveryResult(
        hosts: const <LanHost>[],
        subnetLabel: seed.label,
        selfIp: seed.selfIp,
        gateway: seed.gateway,
        error: seed.error ?? 'Could not derive a local subnet to scan.',
      );
      yield DiscoveryProgress(DiscoveryPhase.failed, 1.0, note: seed.error);
      return;
    }
    yield DiscoveryProgress(DiscoveryPhase.scanning, 0.05, note: seed.label);

    // --- 2. Connect-scan (isolate) ---
    final ConnectScanRequest request = ConnectScanRequest(
      hosts: seed.hosts,
      ports: _ports,
      timeout: _connectTimeout,
      concurrency: _concurrency,
    );

    List<HostPorts> hostPorts;
    try {
      hostPorts = await _runScan(request);
    } catch (e) {
      _lastResult = DiscoveryResult(
        hosts: const <LanHost>[],
        subnetLabel: seed.label,
        selfIp: seed.selfIp,
        gateway: seed.gateway,
        error: 'Connect-scan failed: $e',
      );
      yield const DiscoveryProgress(DiscoveryPhase.failed, 1.0);
      return;
    }

    // Build host records from the scan.
    final Map<String, LanHost> byIp = <String, LanHost>{
      for (final HostPorts hp in hostPorts)
        hp.ip: LanHost(ip: hp.ip, openPorts: hp.openPorts.toSet()),
    };
    yield DiscoveryProgress(DiscoveryPhase.scanning, 0.6,
        note: '${byIp.length} host(s) responded');

    // --- 3. Reverse DNS per discovered host (concurrent, bounded) ---
    yield const DiscoveryProgress(DiscoveryPhase.resolving, 0.65);
    await Future.wait(byIp.values.map((LanHost h) async {
      try {
        h.hostname = await _reverseDns(h.ip);
      } catch (_) {/* leave null */}
    }));
    yield const DiscoveryProgress(DiscoveryPhase.resolving, 0.8);

    // --- 4. mDNS browse, folded onto host records ---
    yield const DiscoveryProgress(DiscoveryPhase.mdns, 0.82);
    try {
      // Android needs a held multicast lock or inbound multicast is dropped;
      // no-op on every other platform. Released in finally so it never leaks.
      await _multicastLock.acquire();
      final Map<String, MdnsRecord> mdns = await _mdnsBrowser.browse();
      mdns.forEach((String ip, MdnsRecord rec) {
        // mDNS can surface hosts the connect-scan missed (no open TCP port but
        // an mDNS responder). Add them too — they are still real LAN hosts.
        final LanHost host = byIp.putIfAbsent(ip, () => LanHost(ip: ip));
        host.mdnsName ??= rec.name;
        host.mdnsServices.addAll(rec.services);
      });
    } catch (_) {
      // mDNS is enrichment only; non-fatal.
    } finally {
      await _multicastLock.release();
    }
    yield const DiscoveryProgress(DiscoveryPhase.mdns, 0.95);

    // --- Heuristic device-type on each host ---
    for (final LanHost h in byIp.values) {
      h.deviceType = inferDeviceType(
        openPorts: h.openPorts,
        mdnsServices: h.mdnsServices,
      );
    }

    final List<LanHost> hosts = byIp.values.toList()
      ..sort((LanHost a, LanHost b) => _ipKey(a.ip).compareTo(_ipKey(b.ip)));

    _lastResult = DiscoveryResult(
      hosts: hosts,
      subnetLabel: seed.label,
      selfIp: seed.selfIp,
      gateway: seed.gateway,
    );
    yield const DiscoveryProgress(DiscoveryPhase.complete, 1.0);
  }

  DiscoveryResult? _lastResult;

  /// The most recent result, or null if no run has completed.
  DiscoveryResult? get lastResult => _lastResult;

  /// Runs the connect-scan, in an isolate by default. A test runner, if
  /// injected, takes precedence and runs in-process with a fake connector.
  Future<List<HostPorts>> _runScan(ConnectScanRequest request) {
    if (_connectScanRunner != null) return _connectScanRunner(request);
    if (runInIsolate) {
      // Isolate.run ships the plain-data request to a fresh isolate, runs the
      // sweep there (keeping the UI isolate free), and returns the results.
      return Isolate.run(() => runConnectScan(request));
    }
    return runConnectScan(request);
  }

  /// Default reverse-DNS: InternetAddress.reverse(), null on any failure.
  static Future<String?> _defaultReverseDns(String ip) async {
    try {
      final InternetAddress addr = InternetAddress(ip);
      final InternetAddress resolved = await addr.reverse();
      final String host = resolved.host;
      // reverse() returns the literal IP back when there is no PTR record.
      return host == ip ? null : host;
    } catch (_) {
      return null;
    }
  }

  /// Sortable integer key for an IPv4 string.
  static int _ipKey(String ip) {
    final List<String> p = ip.split('.');
    if (p.length != 4) return 0;
    int v = 0;
    for (final String o in p) {
      v = (v << 8) | (int.tryParse(o) ?? 0);
    }
    return v & 0xFFFFFFFF;
  }
}

/// Test seam type: replaces the connect-scan pass wholesale.
typedef ConnectScanRunner = Future<List<HostPorts>> Function(
  ConnectScanRequest request,
);
