// SPIKE-HSD-01 — mDNS / Bonjour browse pass (THROWAWAY spike).
//
// Uses `multicast_dns` (pure-Dart, no native plugin — see pubspec rationale).
// Browses a curated set of DNS-SD service types, resolves each instance to its
// SRV target + A record, and yields (ip → {name, serviceTypes}) so the engine
// can fold mDNS names/services onto the connect-scan's host records.
//
// PLATFORM GATES (brief anti-pattern #3): on iOS, mDNS returns EMPTY unless the
// browsed service types are declared in Info.plist `NSBonjourServices`. On
// Android a multicast lock is needed (CHANGE_WIFI_MULTICAST_STATE). Both are
// wired in the platform manifests; without them this pass silently yields
// nothing — which is exactly the gate Keith validates on-device.
//
// HONESTY: an mDNS failure here is non-fatal. The scan still returns hosts from
// the connect-scan; mDNS only enriches. A platform that returns nothing is
// reported as "no mDNS results", never as a crash.

import 'dart:async';

import 'package:multicast_dns/multicast_dns.dart';

/// One mDNS-discovered host: its addresses and the service types it advertised.
class MdnsRecord {
  MdnsRecord({required this.ip, this.name, Set<String>? services})
      : services = services ?? <String>{};

  /// IPv4 address resolved for the instance (from the A record).
  final String ip;

  /// Friendly instance/device name (the instance label of the PTR), or null.
  String? name;

  /// Service types this address advertised (e.g. `_airplay._tcp`).
  final Set<String> services;
}

/// The DNS-SD service types the spike browses. Kept in lockstep with the iOS
/// `NSBonjourServices` plist array — anything browsed here MUST be declared
/// there or iOS returns nothing (brief anti-pattern #3).
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

/// Browses mDNS for [serviceTypes] for up to [timeout] and returns one
/// [MdnsRecord] per discovered IPv4 address. Pure Dart over UDP/5353.
///
/// [clientFactory] is injectable so the browse loop is unit-testable with a
/// fake MDnsClient (no real multicast).
class MdnsBrowser {
  MdnsBrowser({
    this.serviceTypes = kBrowsedServiceTypes,
    this.timeout = const Duration(seconds: 4),
    MDnsClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? _defaultClientFactory;

  final List<String> serviceTypes;
  final Duration timeout;
  final MDnsClient Function() _clientFactory;

  static MDnsClient _defaultClientFactory() => MDnsClient();

  /// Runs the browse. Returns a map keyed by IPv4 address. Never throws — on
  /// any failure (no multicast, permission denied, platform gate) it returns
  /// whatever it gathered, which may be empty.
  Future<Map<String, MdnsRecord>> browse() async {
    final Map<String, MdnsRecord> byIp = <String, MdnsRecord>{};
    final MDnsClient client = _clientFactory();
    try {
      await client.start();
      final DateTime deadline = DateTime.now().add(timeout);

      for (final String service in serviceTypes) {
        if (DateTime.now().isAfter(deadline)) break;
        final Duration remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) break;

        // PTR: service type → instance names.
        await for (final PtrResourceRecord ptr in client
            .lookup<PtrResourceRecord>(
              ResourceRecordQuery.serverPointer(service),
            )
            .timeout(remaining, onTimeout: (sink) => sink.close())) {
          final String instance = ptr.domainName;
          final String friendly = _instanceLabel(instance, service);

          // SRV: instance → target host + port.
          await for (final SrvResourceRecord srv in client
              .lookup<SrvResourceRecord>(
                ResourceRecordQuery.service(instance),
              )
              .timeout(const Duration(milliseconds: 800),
                  onTimeout: (sink) => sink.close())) {
            // A: target host → IPv4.
            await for (final IPAddressResourceRecord a in client
                .lookup<IPAddressResourceRecord>(
                  ResourceRecordQuery.addressIPv4(srv.target),
                )
                .timeout(const Duration(milliseconds: 800),
                    onTimeout: (sink) => sink.close())) {
              final String ip = a.address.address;
              if (a.address.type.name != 'IPv4' && !_looksIpv4(ip)) continue;
              final MdnsRecord rec =
                  byIp.putIfAbsent(ip, () => MdnsRecord(ip: ip));
              rec.name ??= friendly;
              rec.services.add(service);
            }
          }
        }
      }
    } catch (_) {
      // Non-fatal: return whatever was gathered.
    } finally {
      try {
        client.stop();
      } catch (_) {/* ignore */}
    }
    return byIp;
  }

  /// Extracts the human instance label from a DNS-SD instance name like
  /// "Living Room._airplay._tcp.local" → "Living Room".
  static String _instanceLabel(String instance, String service) {
    final int cut = instance.indexOf('.$service');
    if (cut > 0) return instance.substring(0, cut);
    final int dot = instance.indexOf('.');
    return dot > 0 ? instance.substring(0, dot) : instance;
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
