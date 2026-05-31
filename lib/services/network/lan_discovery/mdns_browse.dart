// SPIKE-HSD-01 — mDNS / Bonjour browse pass (THROWAWAY spike).
//
// Uses `bonsoir`, which drives each OS's NATIVE service-discovery daemon
// (NWBrowser/NetService on iOS+macOS, NsdManager on Android, native resolvers
// on Windows/Linux). Browses a curated set of DNS-SD service types, resolves
// each found instance to its host addresses + port, and yields
// (ip → {name, serviceTypes}) so the engine can fold mDNS names/services onto
// the connect-scan's host records.
//
// WHY bonsoir, NOT pure-Dart multicast_dns (the spike's first implementation):
// on-device iOS testing found multicast_dns returned ZERO results even with the
// NSBonjourServices plist entries declared and many Bonjour devices present.
// Since iOS 14, a pure-Dart UDP socket that sends/receives to the mDNS
// multicast group 224.0.0.251:5353 needs Apple's
// com.apple.developer.networking.multicast entitlement, which is granted only
// by special application and which this app does NOT hold. iOS therefore
// silently drops the multicast traffic and the browse comes back empty. The TCP
// connect-scan kept working because it is unicast (covered by the granted Local
// Network permission). bonsoir hands the browse to the OS Bonjour daemon, which
// is allowed to multicast on the app's behalf, so it works with only
// NSBonjourServices declared (already present in Info.plist) and NO multicast
// entitlement — the App-Store-safe path.
//
// ARCHITECTURE NOTE (deliberate, documented spike finding): the TCP connect-scan
// core stays pure-Dart and cross-platform; ONLY this mDNS/Bonjour enrichment
// layer becomes a native plugin. That is why this change requires a full native
// rebuild on device, while the rest of the scan engine is unchanged.
//
// PLATFORM GATES: on iOS/macOS, the browsed service types MUST be declared in
// Info.plist `NSBonjourServices` or the native browser returns nothing — see
// kBrowsedServiceTypes, kept in lockstep with the plist. On Android a multicast
// lock is still acquired around the browse as a no-op risk-reduction (NsdManager
// generally does not require it, but it costs nothing to hold).
//
// HONESTY: an mDNS failure here is non-fatal. The scan still returns hosts from
// the connect-scan; mDNS only enriches. A platform that returns nothing is
// reported as "no mDNS results", never as a crash.

import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

/// One mDNS-discovered host: its addresses and the service types it advertised.
class MdnsRecord {
  MdnsRecord({required this.ip, this.name, Set<String>? services})
      : services = services ?? <String>{};

  /// IPv4 address resolved for the instance (from the resolved host addresses).
  final String ip;

  /// Friendly instance/device name (the service instance name), or null.
  String? name;

  /// Service types this address advertised (e.g. `_airplay._tcp`).
  final Set<String> services;
}

/// The DNS-SD service types the spike browses. Kept in lockstep with the iOS
/// `NSBonjourServices` plist array — anything browsed here MUST be declared
/// there (and in the macOS Info.plist) or the native browser returns nothing.
const List<String> kBrowsedServiceTypes = <String>[
  '_http._tcp', // web UIs, many devices
  '_https._tcp',
  '_airplay._tcp', // Apple TV / AirPlay receivers
  '_raop._tcp', // AirTunes (AirPlay audio)
  '_ipp._tcp', // printers (IPP)
  '_ipps._tcp',
  '_printer._tcp', // printers (LPD)
  '_pdl-datastream._tcp', // printers (port 9100 / JetDirect)
  '_companion-link._tcp', // Apple device pairing
  '_googlecast._tcp', // Chromecast / Google TV
  '_sonos._tcp', // Sonos speakers (device-type heuristic classifies these)
  '_spotify-connect._tcp', // Spotify Connect speakers / media
  '_smb._tcp', // SMB / file sharing
  '_ssh._tcp', // SSH hosts
  '_device-info._tcp', // generic device metadata
  '_workstation._tcp', // generic hosts (avahi/macOS)
];

// --- Injectable discovery seam ---------------------------------------------
//
// The real discovery rides bonsoir's native plugin, which cannot run in a
// pure-Dart unit test (no platform channel). To keep the browse deterministic
// and off the network in tests, discovery is abstracted behind [MdnsDiscovery]:
// a tiny interface that yields normalized [MdnsDiscoveryEvent]s for ONE service
// type. Production wraps `BonsoirDiscovery`; tests inject a fake that replays a
// scripted list of events. This mirrors the old `clientFactory` seam, adapted
// to bonsoir's per-type, event-stream model.

/// A normalized mDNS discovery event for one resolved service instance.
///
/// Only resolved instances (with at least one host address) are surfaced — the
/// browse layer does not care about found-but-unresolved or lost events, so the
/// interface stays small and the fake stays trivial to script.
class MdnsDiscoveryEvent {
  const MdnsDiscoveryEvent({
    required this.serviceType,
    required this.name,
    required this.hostAddresses,
  });

  /// The browsed service type this instance was found under (e.g. `_sonos._tcp`).
  final String serviceType;

  /// The instance's friendly name (may be empty).
  final String name;

  /// The resolved host addresses (IPv4 and/or IPv6 literals).
  final List<String> hostAddresses;
}

/// Discovers resolved instances of a single [serviceType], emitting one
/// [MdnsDiscoveryEvent] per resolved instance, until [dispose] is called.
///
/// Implementations must NOT throw from [start]/[events]: a platform/permission
/// failure surfaces as an empty (or error-swallowed) stream so the browse stays
/// non-fatal. [dispose] must release all native resources (bonsoir discoveries
/// are explicitly stopped/disposed; none may leak).
abstract interface class MdnsDiscovery {
  /// The service type being discovered.
  String get serviceType;

  /// Begins discovery and returns the stream of resolved-instance events.
  Stream<MdnsDiscoveryEvent> start();

  /// Stops discovery and releases all resources. Idempotent, never throws.
  Future<void> dispose();
}

/// Builds an [MdnsDiscovery] for a given service type. Injectable so tests
/// supply a fake (no native plugin, no multicast).
typedef MdnsDiscoveryFactory = MdnsDiscovery Function(String serviceType);

/// Production discovery backed by `BonsoirDiscovery` (native OS Bonjour daemon).
///
/// On a `serviceFound` event the instance is asked to resolve; on the resulting
/// `serviceResolved` event the host addresses are available and a normalized
/// [MdnsDiscoveryEvent] is emitted. All bonsoir resources are torn down in
/// [dispose]; failures there are swallowed (non-fatal honesty contract).
class BonsoirMdnsDiscovery implements MdnsDiscovery {
  BonsoirMdnsDiscovery(this.serviceType)
      : _discovery = BonsoirDiscovery(type: serviceType);

  @override
  final String serviceType;

  final BonsoirDiscovery _discovery;
  final StreamController<MdnsDiscoveryEvent> _out =
      StreamController<MdnsDiscoveryEvent>.broadcast();
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;
  bool _disposed = false;

  @override
  Stream<MdnsDiscoveryEvent> start() {
    // Kick off bonsoir asynchronously; pipe normalized events into _out. Any
    // failure just leaves _out empty — never thrown to the caller.
    unawaited(_run());
    return _out.stream;
  }

  Future<void> _run() async {
    try {
      await _discovery.initialize();
      _sub = _discovery.eventStream?.listen(_onEvent);
      await _discovery.start();
    } catch (_) {
      // Permission / platform failure → no events. Non-fatal.
    }
  }

  void _onEvent(BonsoirDiscoveryEvent event) {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        // Found but not yet resolved: ask the OS resolver for host addresses.
        unawaited(
          event.service.resolve(_discovery.serviceResolver).catchError((_) {}),
        );
      case BonsoirDiscoveryServiceResolvedEvent():
        final BonsoirService s = event.service;
        if (s.hostAddresses.isNotEmpty && !_out.isClosed) {
          _out.add(
            MdnsDiscoveryEvent(
              serviceType: serviceType,
              name: s.name,
              hostAddresses: s.hostAddresses,
            ),
          );
        }
      default:
        // started / updated / lost / resolveFailed / stopped / unknown: ignore.
        break;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _sub?.cancel();
    } catch (_) {/* ignore */}
    try {
      await _discovery.stop();
    } catch (_) {/* ignore */}
    try {
      if (!_out.isClosed) await _out.close();
    } catch (_) {/* ignore */}
  }
}

MdnsDiscovery _defaultDiscoveryFactory(String serviceType) =>
    BonsoirMdnsDiscovery(serviceType);

/// Browses mDNS for [serviceTypes] for up to [timeout] and returns one
/// [MdnsRecord] per discovered IPv4 address, via each OS's native Bonjour
/// daemon (bonsoir).
///
/// [discoveryFactory] is injectable so the browse loop is unit-testable with a
/// fake discovery (no native plugin, no real multicast).
class MdnsBrowser {
  MdnsBrowser({
    this.serviceTypes = kBrowsedServiceTypes,
    this.timeout = const Duration(seconds: 4),
    MdnsDiscoveryFactory? discoveryFactory,
  }) : _discoveryFactory = discoveryFactory ?? _defaultDiscoveryFactory;

  final List<String> serviceTypes;
  final Duration timeout;
  final MdnsDiscoveryFactory _discoveryFactory;

  /// Runs the browse. Returns a map keyed by IPv4 address. Never throws — on
  /// any failure (no permission, platform gate, native error) it returns
  /// whatever it gathered, which may be empty.
  ///
  /// All browsed service types are discovered concurrently for a single shared
  /// [timeout] window (the native daemon multiplexes them), then every
  /// discovery is explicitly disposed so no native resource leaks.
  Future<Map<String, MdnsRecord>> browse() async {
    final Map<String, MdnsRecord> byIp = <String, MdnsRecord>{};
    final List<MdnsDiscovery> discoveries = <MdnsDiscovery>[];
    final List<StreamSubscription<MdnsDiscoveryEvent>> subs =
        <StreamSubscription<MdnsDiscoveryEvent>>[];

    void fold(MdnsDiscoveryEvent ev) {
      for (final String addr in ev.hostAddresses) {
        if (!_looksIpv4(addr)) continue; // keep the record keyed by IPv4
        final MdnsRecord rec = byIp.putIfAbsent(addr, () => MdnsRecord(ip: addr));
        if (ev.name.isNotEmpty) rec.name ??= ev.name;
        rec.services.add(ev.serviceType);
      }
    }

    try {
      for (final String service in serviceTypes) {
        final MdnsDiscovery disc = _discoveryFactory(service);
        discoveries.add(disc);
        subs.add(disc.start().listen(fold, onError: (_) {/* non-fatal */}));
      }
      // One shared discovery window; the native browser streams as it resolves.
      await Future<void>.delayed(timeout);
    } catch (_) {
      // Non-fatal: return whatever was gathered.
    } finally {
      for (final StreamSubscription<MdnsDiscoveryEvent> s in subs) {
        try {
          await s.cancel();
        } catch (_) {/* ignore */}
      }
      for (final MdnsDiscovery d in discoveries) {
        await d.dispose(); // bonsoir discoveries MUST be stopped/disposed.
      }
    }
    return byIp;
  }

  static bool _looksIpv4(String s) {
    final List<String> parts = s.split('.');
    if (parts.length != 4) return false;
    return parts.every((String p) {
      final int? n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }
}
