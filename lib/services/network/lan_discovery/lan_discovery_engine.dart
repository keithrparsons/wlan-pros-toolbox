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

/// The connect-scan is the long pole, so it owns a wide band of the overall
/// progress bar. Streamed probe counts map linearly from [_kScanStart] (right
/// after seeding) to [_kScanEnd] (scan complete, before reverse DNS).
const double _kScanStart = 0.05;
const double _kScanEnd = 0.6;

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
    // Public-named so tests can inject these seams; initializer-list assigned to
    // the private fields (an initializing formal would force the param name to
    // start with `_`, which callers in other libraries cannot supply).
    ConnectScanRunner? scanRunner,
    Connector? connector,
  }) : _seedDeriver = seedDeriver ?? SubnetSeedDeriver(),
       _mdnsBrowser = mdnsBrowser ?? MdnsBrowser(),
       _multicastLock = multicastLock ?? platformMulticastLock(),
       _reverseDns = reverseDns ?? _defaultReverseDns,
       _ports = ports ?? CuratedPorts.all,
       _connectScanRunner = scanRunner, // ignore: prefer_initializing_formals
       _connector = connector; // ignore: prefer_initializing_formals

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

  /// Test seam: a fake socket connector. When set (with [runInIsolate] false),
  /// the in-process scan runs the REAL [runConnectScan] against this connector,
  /// so its streamed progress (onProgress) is exercised exactly as production —
  /// letting tests assert that progress is reported incrementally. Null in
  /// production (the default real socket connector is used).
  final Connector? _connector;

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
    yield DiscoveryProgress(
      DiscoveryPhase.scanning,
      _kScanStart,
      note: seed.label,
    );

    // --- 2. Connect-scan (isolate), with real streamed progress ---
    final ConnectScanRequest request = ConnectScanRequest(
      hosts: seed.hosts,
      ports: _ports,
      timeout: _connectTimeout,
      concurrency: _concurrency,
    );

    // The scan streams (completed, total) probe counts back out of the isolate.
    // We translate them into a smoothly-increasing fraction across the scanning
    // band (_kScanStart.._kScanEnd) and yield one progress event per update,
    // keeping the fraction monotonic. The actual result completes the stream.
    List<HostPorts> hostPorts;
    try {
      final Stream<_ScanEvent> events = _runScan(request);
      List<HostPorts>? scanned;
      double lastFraction = _kScanStart;
      await for (final _ScanEvent ev in events) {
        switch (ev) {
          case _ScanProgress(:final int completed, :final int total):
            if (total <= 0) break;
            final double raw =
                _kScanStart + (_kScanEnd - _kScanStart) * (completed / total);
            // Clamp into the band and never go backwards.
            final double frac = raw.clamp(_kScanStart, _kScanEnd).toDouble();
            if (frac > lastFraction) lastFraction = frac;
            yield DiscoveryProgress(
              DiscoveryPhase.scanning,
              lastFraction,
              note: 'probed $completed / $total',
            );
          case _ScanDone(:final List<HostPorts> hosts):
            scanned = hosts;
        }
      }
      // The stream closed without a done event → treat as a scan failure.
      if (scanned == null) {
        throw StateError('connect-scan ended without a result');
      }
      hostPorts = scanned;
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
    yield DiscoveryProgress(
      DiscoveryPhase.scanning,
      _kScanEnd,
      note: '${byIp.length} host(s) responded',
    );

    // --- 3. Reverse DNS per discovered host (concurrent, bounded) ---
    yield const DiscoveryProgress(DiscoveryPhase.resolving, 0.65);
    await Future.wait(
      byIp.values.map((LanHost h) async {
        try {
          h.hostname = await _reverseDns(h.ip);
        } catch (_) {
          /* leave null */
        }
      }),
    );
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

  /// Runs the connect-scan and streams progress + the final result as
  /// [_ScanEvent]s. In an isolate by default (UI stays responsive); a test
  /// runner, if injected, takes precedence and runs in-process. The in-process
  /// path also emits progress so tests can assert it.
  Stream<_ScanEvent> _runScan(ConnectScanRequest request) {
    if (_connectScanRunner != null) {
      return _streamInProcess(() => _connectScanRunner(request));
    }
    if (runInIsolate) {
      return _streamInIsolate(request);
    }
    // In-process: run the real scan against the (possibly fake) connector so its
    // streamed onProgress is exercised exactly as production.
    return _streamInProcess(() => runConnectScan(request), request: request);
  }

  /// In-process scan that emits streamed progress. Used by tests (via an
  /// injected runner) and by the non-isolate production path. When [request] is
  /// provided, the real [runConnectScan] is invoked with an onProgress hook so
  /// progress events are produced; when only a [run] thunk is provided (test
  /// runner replacing the whole pass), progress comes from that runner if it
  /// chooses to call back — otherwise just the done event is emitted.
  Stream<_ScanEvent> _streamInProcess(
    Future<List<HostPorts>> Function() run, {
    ConnectScanRequest? request,
  }) async* {
    final StreamController<_ScanEvent> controller =
        StreamController<_ScanEvent>();
    late final Future<void> work;
    if (request != null) {
      work =
          runConnectScan(
                request,
                connector: _connector,
                onProgress: (int c, int t) =>
                    controller.add(_ScanProgress(c, t)),
              )
              .then((List<HostPorts> hosts) {
                controller.add(_ScanDone(hosts));
              })
              .whenComplete(controller.close);
    } else {
      work = run()
          .then((List<HostPorts> hosts) {
            controller.add(_ScanDone(hosts));
          })
          .whenComplete(controller.close);
    }
    // Surface any error from `work` through the stream.
    unawaited(
      work.catchError((Object e, StackTrace s) {
        if (!controller.isClosed) controller.addError(e, s);
      }),
    );
    yield* controller.stream;
  }

  /// Isolate scan: spawns a worker that runs the sweep off the UI isolate and
  /// streams (completed, total) progress back over a SendPort, then the final
  /// host list, then exits. Errors and unexpected exits surface as a stream
  /// error so the engine's try/catch turns them into a failed DiscoveryResult
  /// rather than hanging.
  Stream<_ScanEvent> _streamInIsolate(ConnectScanRequest request) {
    final StreamController<_ScanEvent> controller =
        StreamController<_ScanEvent>();
    final ReceivePort messages = ReceivePort();
    final ReceivePort errors = ReceivePort();
    final ReceivePort exits = ReceivePort();
    Isolate? isolate;
    bool gotResult = false;

    void cleanup() {
      messages.close();
      errors.close();
      exits.close();
      isolate?.kill(priority: Isolate.immediate);
    }

    messages.listen((dynamic msg) {
      if (msg is _ScanProgressMsg) {
        controller.add(_ScanProgress(msg.completed, msg.total));
      } else if (msg is _ScanDoneMsg) {
        gotResult = true;
        controller.add(_ScanDone(msg.hosts));
        controller.close();
        cleanup();
      }
    });

    // onError delivers [error, stackTrace] as strings for a crashed isolate.
    errors.listen((dynamic err) {
      if (!controller.isClosed) {
        controller.addError(StateError('connect-scan isolate error: $err'));
        controller.close();
      }
      cleanup();
    });

    // onExit fires when the isolate ends. If it ended before sending a result,
    // that is a failure (crash / premature exit), not a clean finish.
    exits.listen((dynamic _) {
      if (!gotResult && !controller.isClosed) {
        controller.addError(
          StateError('connect-scan isolate exited without a result'),
        );
        controller.close();
      }
      cleanup();
    });

    Isolate.spawn<_ScanIsolateMessage>(
          _connectScanIsolateEntry,
          _ScanIsolateMessage(request, messages.sendPort),
          onError: errors.sendPort,
          onExit: exits.sendPort,
          errorsAreFatal: true,
        )
        .then((Isolate spawned) {
          isolate = spawned;
        })
        .catchError((Object e) {
          if (!controller.isClosed) {
            controller.addError(StateError('failed to spawn connect-scan: $e'));
            controller.close();
          }
          cleanup();
        });

    return controller.stream;
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
typedef ConnectScanRunner =
    Future<List<HostPorts>> Function(ConnectScanRequest request);

// --- Internal scan-event stream (engine ↔ scan runner) ---------------------
//
// The connect-scan pass reports as a small stream of events instead of a bare
// Future, so streamed progress reaches the UI whether the scan runs in-process
// or in an isolate. These are private to the engine.

/// Base type for events streamed out of the connect-scan pass.
sealed class _ScanEvent {
  const _ScanEvent();
}

/// A streamed progress tick: [completed] of [total] (host, port) probes done.
class _ScanProgress extends _ScanEvent {
  const _ScanProgress(this.completed, this.total);
  final int completed;
  final int total;
}

/// The terminal event: the full list of alive hosts the scan produced.
class _ScanDone extends _ScanEvent {
  const _ScanDone(this.hosts);
  final List<HostPorts> hosts;
}

// --- Isolate boundary messages ---------------------------------------------
//
// These cross the SendPort, so they are plain data (no closures, no Flutter).
// ConnectScanRequest and HostPorts are already plain data, so they transfer
// fine.

/// Message handed to the spawned worker: the request plus the reply port.
class _ScanIsolateMessage {
  const _ScanIsolateMessage(this.request, this.reply);
  final ConnectScanRequest request;
  final SendPort reply;
}

/// Progress message sent from the worker back to the engine.
class _ScanProgressMsg {
  const _ScanProgressMsg(this.completed, this.total);
  final int completed;
  final int total;
}

/// Result message sent from the worker once the sweep finishes.
class _ScanDoneMsg {
  const _ScanDoneMsg(this.hosts);
  final List<HostPorts> hosts;
}

/// Top-level isolate entry point. Runs the sweep, streaming progress back over
/// the SendPort as it goes, then sends the final host list and returns (which
/// fires the engine's onExit). Must be top-level/static to be sent to an
/// isolate. Any throw here propagates via the spawn's onError port.
Future<void> _connectScanIsolateEntry(_ScanIsolateMessage message) async {
  final SendPort reply = message.reply;
  final List<HostPorts> hosts = await runConnectScan(
    message.request,
    onProgress: (int completed, int total) =>
        reply.send(_ScanProgressMsg(completed, total)),
  );
  reply.send(_ScanDoneMsg(hosts));
}
