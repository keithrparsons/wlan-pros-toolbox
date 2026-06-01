// mDNS / Bonjour browse pass — Network Discovery (TICKET-HSD-02).
//
// Uses an IN-HOUSE native plugin over Apple's `NetServiceBrowser` + `NetService`
// (Foundation Bonjour), which drives the OS Bonjour daemon on iOS + macOS.
// Browses a curated set of DNS-SD service types, resolves each found instance to
// its host addresses, and yields (ip → {name, serviceTypes}) so the engine can
// fold mDNS names/services onto the connect-scan's host records.
//
// WHY IN-HOUSE NetServiceBrowser, NOT `bonsoir` (the spike's first native
// choice): bonsoir is GPL-3.0, incompatible with a closed-source commercial App
// Store app (PRD Decision Log 13). It is replaced by a thin in-Runner Swift
// EventChannel (ios/Runner/MdnsBrowseChannel.swift,
// macos/Runner/MdnsBrowseChannel.swift) that runs one `NetServiceBrowser` per
// service type and resolves each instance with `NetService` — the exact Apple
// API stack bonsoir_darwin used. Behavior is identical: found → resolve →
// resolved → host-addresses. An earlier in-house attempt used `NWBrowser`; on a
// sandboxed macOS app on-device it reached `.ready` but delivered ZERO browse
// results, so NWBrowser was removed entirely in favor of the bonsoir-proven
// NetServiceBrowser path.
//
// WHY NOT pure-Dart multicast_dns (the spike's ORIGINAL choice):
// on-device iOS testing found multicast_dns returned ZERO results even with the
// NSBonjourServices plist entries declared and many Bonjour devices present.
// Since iOS 14, a pure-Dart UDP socket that sends/receives to the mDNS
// multicast group 224.0.0.251:5353 needs Apple's
// com.apple.developer.networking.multicast entitlement, which is granted only
// by special application and which this app does NOT hold. iOS therefore
// silently drops the multicast traffic and the browse comes back empty. The TCP
// connect-scan kept working because it is unicast (covered by the granted Local
// Network permission). NetServiceBrowser hands the browse to the OS Bonjour
// daemon, which is allowed to multicast on the app's behalf, so it works with
// only NSBonjourServices declared (already present in Info.plist) and NO
// multicast entitlement — the App-Store-safe path, same as bonsoir but
// license-clean.
//
// ARCHITECTURE NOTE (deliberate, documented spike finding): the TCP connect-scan
// core stays pure-Dart and cross-platform; ONLY this mDNS/Bonjour enrichment
// layer is a native plugin. That is why this change requires a full native
// rebuild on device, while the rest of the scan engine is unchanged.
//
// PLATFORM GATES: on iOS/macOS, the browsed service types MUST be declared in
// Info.plist `NSBonjourServices` or the native browser returns nothing — see
// kBrowsedServiceTypes, kept in lockstep with the plist. On Android (and any
// other platform) the native channel is not registered — NsdManager is deferred
// per project-toolbox-platform-scope — so the factory returns a clean
// unavailable (empty-stream) discovery; nothing is faked. A multicast lock is
// still acquired around the browse as a no-op risk-reduction.
//
// HONESTY: an mDNS failure here is non-fatal. The scan still returns hosts from
// the connect-scan; mDNS only enriches. A platform that returns nothing is
// reported as "no mDNS results", never as a crash.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

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
// The real discovery rides the in-house native NetServiceBrowser EventChannel,
// which
// cannot run in a pure-Dart unit test (no platform channel). To keep the browse
// deterministic and off the network in tests, discovery is abstracted behind
// [MdnsDiscovery]: a tiny interface that yields normalized [MdnsDiscoveryEvent]s
// for ONE service type. Production wraps [NWBrowserMdnsDiscovery], which shares
// a single native EventChannel stream across ALL service types in the browse via
// [_MdnsBrowseTransport] (a Flutter EventChannel allows only ONE active stream
// per channel name — see the kMdnsBrowseChannel contract); tests inject a fake
// that replays a scripted list of events. The seam is unchanged from the bonsoir
// version — only the production implementation behind it changed.

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
/// non-fatal. [dispose] must release all native resources (the native
/// NetServiceBrowser and its resolving NetServices are explicitly stopped; none
/// may leak).
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

/// The name of the in-house native mDNS browse EventChannel. Shared with
/// `ios/Runner/MdnsBrowseChannel.swift` and `macos/Runner/MdnsBrowseChannel.swift`.
///
/// CRITICAL CONTRACT (2026-05-31 stream-lifecycle fix): a Flutter [EventChannel]
/// keyed by NAME supports exactly ONE active broadcast stream. The whole browse
/// therefore opens the channel ONCE, passing the FULL LIST of service types
/// (`List<String>`) as the single `onListen` argument. The native side runs one
/// `NetServiceBrowser` per type under ONE session and tags every event with the
/// `serviceType` it was found under, so the single Dart stream is demultiplexed
/// back to per-type discoveries. (The earlier bug opened one
/// `receiveBroadcastStream` PER service type on this one channel — 16 concurrent
/// listens on a single-stream channel — which thrashed the framework's
/// subscribe/cancel bookkeeping, tore the native browsers down before mDNS could
/// hear any announcement, and produced a "No active stream to cancel" storm.)
const String kMdnsBrowseChannel = 'com.wlanpros.toolbox/mdns_browse';

/// Process-wide transport that owns the ONE allowed [EventChannel] subscription
/// for the whole browse and fans events out to per-type [NWBrowserMdnsDiscovery]
/// listeners by `serviceType`.
///
/// Why a shared transport: a Flutter [EventChannel] supports a SINGLE active
/// broadcast stream per channel name. The browse runs N service types
/// concurrently but they must all ride ONE native stream. This transport opens
/// that stream once (with the full type list as the listen argument), holds it
/// open for the whole discovery window, and tears it down with a SINGLE cancel
/// when the last per-type discovery disposes. Reference-counted so back-to-back
/// browses each get a fresh, correctly-bounded stream.
///
/// HONESTY: any channel/platform failure (channel unregistered on a deferred
/// platform, no permission, native error) surfaces as silence — listeners simply
/// receive no events. Never a throw to the caller; mDNS enrichment is non-fatal.
class _MdnsBrowseTransport {
  _MdnsBrowseTransport._();

  /// Singleton: one transport per process so all per-type discoveries in a
  /// single browse share the one allowed channel stream.
  static final _MdnsBrowseTransport instance = _MdnsBrowseTransport._();

  final EventChannel _channel = const EventChannel(kMdnsBrowseChannel);

  /// Per-service-type sinks for the currently-active browse, demultiplexed from
  /// the single native stream by the `serviceType` field on each event.
  final Map<String, Set<StreamController<MdnsDiscoveryEvent>>> _sinks =
      <String, Set<StreamController<MdnsDiscoveryEvent>>>{};

  /// The ONE active native subscription, or null when no browse is running.
  StreamSubscription<dynamic>? _sub;

  /// Reference count of live per-type discoveries; the native stream is opened
  /// when it goes 0→1 and cancelled (single cancel) when it returns to 0.
  int _refs = 0;

  /// Registers [controller] to receive events for [serviceType], opening the
  /// single native stream on the first registration. The listen argument is the
  /// FULL set of service types being browsed so the native side starts one
  /// browser per type under one session.
  void register(
    String serviceType,
    StreamController<MdnsDiscoveryEvent> controller,
    List<String> allServiceTypes,
  ) {
    _sinks.putIfAbsent(serviceType, () => <StreamController<MdnsDiscoveryEvent>>{}).add(controller);
    _refs++;
    if (_sub == null) {
      // First listener of this browse: open the ONE native stream. Pass the full
      // type list as the listen argument so a single session browses them all.
      try {
        _sub = _channel
            .receiveBroadcastStream(allServiceTypes)
            .listen(_onNativeEvent, onError: (Object _) {/* non-fatal */});
      } catch (_) {
        // Synchronous failure (e.g. missing channel): no stream, listeners stay
        // silent. Leave _sub null so a later browse can retry.
      }
    }
  }

  /// Unregisters [controller]; when the last live discovery for the browse
  /// unregisters, the ONE native stream is cancelled exactly once.
  Future<void> unregister(
    String serviceType,
    StreamController<MdnsDiscoveryEvent> controller,
  ) async {
    final Set<StreamController<MdnsDiscoveryEvent>>? set = _sinks[serviceType];
    if (set != null) {
      set.remove(controller);
      if (set.isEmpty) _sinks.remove(serviceType);
    }
    if (_refs > 0) _refs--;
    if (_refs == 0) {
      // Last listener gone: single, clean cancel of the one native stream. The
      // native onCancel stops every NetServiceBrowser + resolving NetService.
      final StreamSubscription<dynamic>? sub = _sub;
      _sub = null;
      _sinks.clear();
      try {
        await sub?.cancel();
      } catch (_) {/* ignore */}
    }
  }

  void _onNativeEvent(dynamic event) {
    if (event is! Map) return;
    final Object? rawType = event['serviceType'];
    if (rawType is! String) return;
    final Set<StreamController<MdnsDiscoveryEvent>>? set = _sinks[rawType];
    if (set == null || set.isEmpty) return;
    final MdnsDiscoveryEvent? ev =
        NWBrowserMdnsDiscovery.parseNativeEvent(rawType, event);
    if (ev == null) return;
    for (final StreamController<MdnsDiscoveryEvent> c in set) {
      if (!c.isClosed) c.add(ev);
    }
  }
}

/// Production discovery backed by the in-house native NetServiceBrowser
/// EventChannel. (The class name retains the historical `NWBrowser` prefix for
/// API/test stability; the native implementation is now NetServiceBrowser.)
///
/// Each [NWBrowserMdnsDiscovery] registers ITS [serviceType] with the shared
/// [_MdnsBrowseTransport], which owns the ONE allowed channel stream for the
/// whole browse. The native side runs a `NetServiceBrowser` per type under one
/// session and, for each found instance, resolves it with `NetService`, then
/// pushes `{serviceType, name, hostAddresses}` up the single stream — the same
/// found→resolve→resolved→host-addresses flow bonsoir performed. The transport
/// fans each event to the matching discovery by `serviceType`; this class
/// normalizes it into an [MdnsDiscoveryEvent]. [dispose] unregisters from the
/// transport; when the last discovery unregisters, the transport fires the ONE
/// native cancel so the NetServiceBrowsers and all in-flight resolving
/// NetServices are torn down — no native resource leak, no cancel storm.
///
/// [allServiceTypes] is the full set the browse will run, passed through to the
/// native side as the single stream's listen argument.
///
/// HONESTY: any channel/platform failure (e.g. the channel is unregistered on a
/// platform where Android NsdManager is deferred) surfaces as an empty stream,
/// never a throw. mDNS enrichment is non-fatal by contract.
class NWBrowserMdnsDiscovery implements MdnsDiscovery {
  NWBrowserMdnsDiscovery(
    this.serviceType, {
    List<String>? allServiceTypes,
  })  : _allServiceTypes = allServiceTypes ?? <String>[serviceType],
        _transport = _MdnsBrowseTransport.instance;

  @override
  final String serviceType;

  final List<String> _allServiceTypes;
  final _MdnsBrowseTransport _transport;
  final StreamController<MdnsDiscoveryEvent> _out =
      StreamController<MdnsDiscoveryEvent>.broadcast();
  bool _started = false;
  bool _disposed = false;

  @override
  Stream<MdnsDiscoveryEvent> start() {
    // Register this type with the shared transport, which opens (or reuses) the
    // ONE native stream for the whole browse. Any failure inside the transport
    // is swallowed there — _out simply stays empty. Never thrown to the caller.
    if (!_started && !_disposed) {
      _started = true;
      _transport.register(serviceType, _out, _allServiceTypes);
    }
    return _out.stream;
  }

  /// Normalizes one native payload `{serviceType, name, hostAddresses:[...]}`
  /// into an [MdnsDiscoveryEvent], or null when the payload is malformed or has
  /// no usable address (resolved-only contract). Pure (no channel) so it is
  /// unit-testable with a literal map shaped like the platform-channel event.
  /// Defensive against malformed maps — anything unexpected returns null, never
  /// throws.
  static MdnsDiscoveryEvent? parseNativeEvent(
    String serviceType,
    Object? event,
  ) {
    if (event is! Map) return null;
    final Object? rawAddrs = event['hostAddresses'];
    if (rawAddrs is! List) return null;
    final List<String> addresses = <String>[
      for (final Object? a in rawAddrs)
        if (a is String && a.isNotEmpty) a,
    ];
    if (addresses.isEmpty) return null; // resolved-only: skip address-less

    final Object? rawName = event['name'];
    final String name = rawName is String ? rawName : '';

    return MdnsDiscoveryEvent(
      serviceType: serviceType,
      name: name,
      hostAddresses: addresses,
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // Unregister from the shared transport. When the last live discovery
    // unregisters, the transport fires the ONE native cancel, which stops the
    // NetServiceBrowsers + all resolving NetServices (no native leak).
    if (_started) {
      await _transport.unregister(serviceType, _out);
    }
    try {
      if (!_out.isClosed) await _out.close();
    } catch (_) {/* ignore */}
  }
}

/// A discovery that yields nothing — used on platforms where the native mDNS
/// channel is not registered (Android NsdManager is deferred per
/// project-toolbox-platform-scope, and any other non-iOS/macOS target). Mirrors
/// how [UnavailableArpReader] handles non-macOS: a clean empty result, never
/// faked, never thrown.
class UnavailableMdnsDiscovery implements MdnsDiscovery {
  const UnavailableMdnsDiscovery(this.serviceType);

  @override
  final String serviceType;

  @override
  Stream<MdnsDiscoveryEvent> start() => const Stream<MdnsDiscoveryEvent>.empty();

  @override
  Future<void> dispose() async {}
}

/// Builds an [MdnsDiscovery] for one [serviceType] within a browse of
/// [allServiceTypes]. Injectable so tests supply a fake (no native plugin, no
/// multicast). The production factory passes [allServiceTypes] through to the
/// native side as the single stream's listen argument.
typedef MdnsDiscoveryFactoryFull = MdnsDiscovery Function(
  String serviceType,
  List<String> allServiceTypes,
);

/// Picks the discovery for the current platform: the native NetServiceBrowser
/// channel on iOS + macOS (the only platforms whose Runner registers the channel
/// this phase), an honest empty discovery everywhere else.
///
/// [allServiceTypes] is the full set the browse will run; on iOS/macOS it is
/// passed to the shared transport so the ONE native stream starts one browser
/// per type under a single session.
MdnsDiscovery _defaultDiscoveryFactory(
  String serviceType,
  List<String> allServiceTypes,
) {
  if (Platform.isIOS || Platform.isMacOS) {
    return NWBrowserMdnsDiscovery(
      serviceType,
      allServiceTypes: allServiceTypes,
    );
  }
  return UnavailableMdnsDiscovery(serviceType);
}

/// Browses mDNS for [serviceTypes] for up to [timeout] and returns one
/// [MdnsRecord] per discovered IPv4 address, via the OS Bonjour daemon (the
/// in-house native NetServiceBrowser EventChannel on iOS + macOS).
///
/// [discoveryFactory] is injectable so the browse loop is unit-testable with a
/// fake discovery (no native plugin, no real multicast).
class MdnsBrowser {
  MdnsBrowser({
    this.serviceTypes = kBrowsedServiceTypes,
    this.timeout = const Duration(seconds: 4),
    MdnsDiscoveryFactory? discoveryFactory,
    // Public-named so callers in other libraries (tests) can supply it; an
    // initializing formal would force the param name to start with `_`.
  }) : _discoveryFactory = discoveryFactory; // ignore: prefer_initializing_formals

  final List<String> serviceTypes;
  final Duration timeout;

  /// Test seam: a single-arg factory `(serviceType) -> MdnsDiscovery`. When set,
  /// it takes precedence (tests inject fakes that ignore the type list). When
  /// null, production uses [_defaultDiscoveryFactory], which also receives the
  /// full [serviceTypes] list so the native side opens one stream for the whole
  /// browse.
  final MdnsDiscoveryFactory? _discoveryFactory;

  /// Builds the per-type discovery, honoring an injected test factory if present
  /// and otherwise the production factory (which gets the full type list).
  MdnsDiscovery _buildDiscovery(String service, List<String> allTypes) {
    final MdnsDiscoveryFactory? injected = _discoveryFactory;
    if (injected != null) return injected(service);
    return _defaultDiscoveryFactory(service, allTypes);
  }

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
        final MdnsDiscovery disc = _buildDiscovery(service, serviceTypes);
        discoveries.add(disc);
        subs.add(disc.start().listen(fold, onError: (_) {/* non-fatal */}));
      }
      // ONE shared discovery window held open for the whole [timeout] (the dwell
      // mDNS needs to hear devices announce). All per-type discoveries ride the
      // single native stream opened by the shared transport; nothing is torn
      // down until this window elapses. The native browser streams resolved
      // instances as they arrive across the window.
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
        await d.dispose(); // NetServiceBrowser + resolving NetServices MUST stop.
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
