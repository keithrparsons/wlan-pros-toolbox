// Network Discovery host model (TICKET-HSD-02 — productized from SPIKE-HSD-01).
//
// The validated host record from the spike, kept as the production model. Pure
// data — no dart:io, no Flutter — so it crosses the isolate boundary as a plain
// field bag and stays trivially unit-testable.
//
// The IPv4 `ip` is the stable host key (locked decision 2026-05-31). W4 will
// attach resolved IPv6 addresses to this same record and give IPv6-only hosts
// their own row; the IPv4 keying here does not block that and is unchanged.

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

  /// A flat, log-friendly dump of the host's enrichment fields. Diagnostic
  /// only — not a UI string contract (the screen renders each field directly)
  /// and not the export shape (CSV/JSON export is W5).
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
