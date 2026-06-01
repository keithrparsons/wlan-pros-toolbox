// SPIKE-HSD-01 — mDNS / Bonjour browse pass (THROWAWAY spike).
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
// for ONE service type. Production wraps [NWBrowserMdnsDiscovery] (one native
// EventChannel stream per service type); tests inject a fake that replays a
// scripted list of events. The seam is unchanged from the bonsoir version — only
// the production implementation behind it changed.

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
/// The browsed service type is passed as the stream's `onListen` argument, so a
/// single channel multiplexes one independent NetServiceBrowser per service type.
const String kMdnsBrowseChannel = 'com.wlanpros.toolbox/mdns_browse';

/// Production discovery backed by the in-house native NetServiceBrowser
/// EventChannel. (The class name retains the historical `NWBrowser` prefix for
/// API/test stability; the native implementation is now NetServiceBrowser.)
///
/// One [NWBrowserMdnsDiscovery] opens one stream on [kMdnsBrowseChannel] with
/// its [serviceType] as the listen argument. The native side runs a
/// `NetServiceBrowser` for that type and, for each found instance, resolves it
/// with `NetService`, then pushes `{serviceType, name, hostAddresses}` up the
/// stream — the same found→resolve→resolved→host-addresses flow bonsoir
/// performed. Each native event is normalized into an [MdnsDiscoveryEvent].
/// [dispose] cancels the Dart subscription, which fires the native `onCancel` so
/// the NetServiceBrowser and all its in-flight resolving NetServices are torn
/// down — no native resource leak.
///
/// HONESTY: any channel/platform failure (e.g. the channel is unregistered on a
/// platform where Android NsdManager is deferred) surfaces as an empty stream,
/// never a throw. mDNS enrichment is non-fatal by contract.
class NWBrowserMdnsDiscovery implements MdnsDiscovery {
  NWBrowserMdnsDiscovery(this.serviceType)
      : _channel = const EventChannel(kMdnsBrowseChannel);

  @override
  final String serviceType;

  final EventChannel _channel;
  final StreamController<MdnsDiscoveryEvent> _out =
      StreamController<MdnsDiscoveryEvent>.broadcast();
  StreamSubscription<dynamic>? _sub;
  bool _disposed = false;

  @override
  Stream<MdnsDiscoveryEvent> start() {
    // Subscribe to the native stream, passing the service type as the listen
    // argument so the native side browses exactly this type. Any error on the
    // platform stream (no permission, channel unregistered, browser failed) is
    // swallowed — _out simply stays empty. Never thrown to the caller.
    try {
      _sub = _channel
          .receiveBroadcastStream(serviceType)
          .listen(_onNativeEvent, onError: (Object _) {/* non-fatal */});
    } catch (_) {
      // Synchronous failure (e.g. missing channel): leave _out empty.
    }
    return _out.stream;
  }

  void _onNativeEvent(dynamic event) {
    if (_out.isClosed) return;
    final MdnsDiscoveryEvent? ev = parseNativeEvent(serviceType, event);
    if (ev != null) _out.add(ev);
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
    // Cancelling the subscription fires the native onCancel, which stops the
    // NetServiceBrowser + all resolving NetServices (no native leak).
    try {
      await _sub?.cancel();
    } catch (_) {/* ignore */}
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

/// Picks the discovery for the current platform: the native NetServiceBrowser
/// channel on iOS + macOS (the only platforms whose Runner registers the channel
/// this phase), an honest empty discovery everywhere else.
MdnsDiscovery _defaultDiscoveryFactory(String serviceType) {
  if (Platform.isIOS || Platform.isMacOS) {
    return NWBrowserMdnsDiscovery(serviceType);
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
