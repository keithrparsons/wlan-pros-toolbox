// SPIKE-HSD-01 — LAN Discovery prototype models.
//
// THROWAWAY: this whole lan_discovery/ tree is a time-boxed spike to de-risk a
// cross-platform LAN scanner (see Deliverables/2026-05-31-lan-scanner-
// feasibility/SPIKE-lan-scanner.md). It is deleted when the real LAN Discovery
// build ticket (TICKET-HSD-02) starts. No GL-003 styling, no Vera gate.
//
// Pure data + a pure heuristic. No dart:io, no Flutter — so the heuristic and
// the models are trivially unit-testable, and the models can cross the isolate
// boundary as plain field bags.

import 'device_type.dart';

/// One discovered host on the local subnet, enriched across the scan passes.
///
/// A host enters the result set the moment the TCP connect-scan finds ANY open
/// port (the liveness spine). Reverse DNS, mDNS, and the device-type heuristic
/// then enrich the same record. Every enrichment field is nullable / empty
/// because each pass can fail or return nothing independently (GL-005: a blank
/// field is shown as blank, never faked).
class LanHost {
  LanHost({
    required this.ip,
    Set<int>? openPorts,
    this.hostname,
    this.mdnsName,
    Set<String>? mdnsServices,
    this.deviceType = DeviceType.unknown,
    this.mac,
    this.vendor,
  })  : openPorts = openPorts ?? <int>{},
        mdnsServices = mdnsServices ?? <String>{};

  /// IPv4 address (dotted-quad). The stable key for a host across passes.
  final String ip;

  /// Open TCP ports discovered by the connect-scan. The liveness evidence.
  final Set<int> openPorts;

  /// Reverse-DNS (PTR) hostname, or null if the resolver returned nothing.
  String? hostname;

  /// mDNS/Bonjour instance/device name, or null if not seen over mDNS.
  String? mdnsName;

  /// mDNS service types advertised by this host (e.g. `_airplay._tcp`).
  final Set<String> mdnsServices;

  /// Heuristic device type inferred from open ports + mDNS service types.
  /// On mobile there is no MAC anchor, so the heuristic itself uses none; on
  /// macOS the MAC/vendor below are read from the ARP cache as a separate
  /// desktop-only enrichment (SPIKE-HSD-01 Gate 2) and do not feed the
  /// heuristic for the spike.
  DeviceType deviceType;

  /// Link-layer MAC read from the macOS ARP cache (Gate 2), or null when no MAC
  /// was available for this host (every non-macOS platform, or a host not in
  /// the cache). Never fabricated.
  String? mac;

  /// Vendor name resolved from [mac]'s OUI, or null when there is no MAC.
  String? vendor;

  /// A flat, log-friendly dump for the throwaway debug list. Not a UI string
  /// contract — this screen is deleted with the spike.
  Map<String, Object?> toDebugMap() => <String, Object?>{
        'ip': ip,
        'hostname': hostname,
        'mdnsName': mdnsName,
        'openPorts': (openPorts.toList()..sort()),
        'mdnsServices': (mdnsServices.toList()..sort()),
        'deviceType': deviceType.label,
        'mac': mac,
        'vendor': vendor,
      };

  @override
  String toString() => 'LanHost($ip, ports=${openPorts.toList()..sort()}, '
      'host=$hostname, mdns=$mdnsName, type=${deviceType.label}, '
      'mac=$mac, vendor=$vendor)';
}
