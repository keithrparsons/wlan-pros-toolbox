// PortReferenceService — look up well-known / registered TCP/UDP ports from a
// bundled, curated table, fully offline.
//
// WHAT IT DOES: indexes a curated subset of the IANA Service Name and Transport
// Protocol Port Number Registry — trimmed to the ports a network / Wi-Fi pro
// actually meets in the field (not the full 49,151-entry registry) — and
// answers two questions a tech asks at a packet capture or a firewall rule:
//   - "what is running on port N?"  → numeric search
//   - "what port does <service> use?" → service-name substring search
//
// OFFLINE / NO NETWORK: the table is a bundled asset
// (assets/ports/well_known_ports.json, declared in pubspec.yaml), loaded and
// parsed once at startup and cached in memory for the process lifetime. No
// HTTP, no `dart:io`, NO Flutter imports — the screen reads the asset string
// via rootBundle and hands it to `PortReferenceService.fromJson`, so the logic
// is pure Dart and unit-testable from an in-memory string.
//
// HONESTY: an unmatched query returns an empty result list, never a fabricated
// "unknown service" row. The data is curated, so absence means "not in our
// field-relevant set," which the screen states plainly.
//
// ASSET SOURCE: IANA port registry, curated subset. Provenance is recorded in
// the asset's `_meta` block.

import 'dart:convert';

/// Transport protocol(s) a port entry applies to.
enum PortProtocol { tcp, udp, sctp }

extension PortProtocolLabel on PortProtocol {
  String get label {
    switch (this) {
      case PortProtocol.tcp:
        return 'TCP';
      case PortProtocol.udp:
        return 'UDP';
      case PortProtocol.sctp:
        return 'SCTP';
    }
  }

  /// Parse a wire token (case-insensitive). Returns null for unknown tokens so
  /// a typo in the asset is dropped, not silently mapped to the wrong protocol.
  static PortProtocol? tryParse(String token) {
    switch (token.trim().toLowerCase()) {
      case 'tcp':
        return PortProtocol.tcp;
      case 'udp':
        return PortProtocol.udp;
      case 'sctp':
        return PortProtocol.sctp;
      default:
        return null;
    }
  }
}

/// One curated port reference entry.
class PortEntry {
  const PortEntry({
    required this.port,
    required this.protocols,
    required this.name,
    required this.description,
  });

  /// The port number (0–65535).
  final int port;

  /// Transport protocol(s) this entry applies to (e.g. TCP and UDP for DNS).
  final List<PortProtocol> protocols;

  /// Short service name / mnemonic (e.g. `https`, `radius`).
  final String name;

  /// One-line plain-language description.
  final String description;

  /// `TCP/UDP` style protocol label for display.
  String get protocolLabel =>
      protocols.map((p) => p.label).join('/');

  /// Build from a decoded JSON map. Returns null when the row is malformed
  /// (missing/non-int port, no usable protocols, empty name) so a bad asset row
  /// is dropped rather than crashing the load or rendering a blank line.
  static PortEntry? fromMap(Map<String, dynamic> map) {
    final Object? rawPort = map['port'];
    final int? port = rawPort is int ? rawPort : int.tryParse('$rawPort');
    if (port == null || port < 0 || port > 65535) return null;

    final Object? rawName = map['name'];
    final String name = rawName is String ? rawName.trim() : '';
    if (name.isEmpty) return null;

    final Object? rawProtos = map['protocols'];
    final List<PortProtocol> protocols = <PortProtocol>[];
    if (rawProtos is List) {
      for (final Object? p in rawProtos) {
        final PortProtocol? parsed =
            p is String ? PortProtocolLabel.tryParse(p) : null;
        if (parsed != null && !protocols.contains(parsed)) {
          protocols.add(parsed);
        }
      }
    }
    if (protocols.isEmpty) return null;

    final Object? rawDesc = map['description'];
    final String description = rawDesc is String ? rawDesc.trim() : '';

    return PortEntry(
      port: port,
      protocols: protocols,
      name: name,
      description: description,
    );
  }
}

/// Indexes the curated port table and answers number / name searches.
class PortReferenceService {
  /// Build directly from parsed entries (used by tests and by [fromJson]).
  /// Builds a port→entries index once so numeric lookups are O(1).
  PortReferenceService.fromEntries(List<PortEntry> entries)
      : _entries = List<PortEntry>.unmodifiable(entries) {
    for (final PortEntry e in _entries) {
      _byPort.putIfAbsent(e.port, () => <PortEntry>[]).add(e);
    }
  }

  /// Build from the raw asset JSON string. Tolerant of malformed rows: bad
  /// entries are skipped, never thrown. Returns an empty-but-valid service if
  /// the document has no usable `ports` array.
  factory PortReferenceService.fromJson(String jsonString) {
    final List<PortEntry> entries = parseEntries(jsonString);
    return PortReferenceService.fromEntries(entries);
  }

  final List<PortEntry> _entries;
  final Map<int, List<PortEntry>> _byPort = <int, List<PortEntry>>{};

  /// All curated entries, in asset order.
  List<PortEntry> get all => _entries;

  /// Number of curated entries loaded.
  int get count => _entries.length;

  /// Parse the asset JSON into a list of entries. Static + pure so the parse is
  /// unit-testable without constructing a service.
  static List<PortEntry> parseEntries(String jsonString) {
    final Object? decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) return const <PortEntry>[];
    final Object? rawPorts = decoded['ports'];
    if (rawPorts is! List) return const <PortEntry>[];
    final List<PortEntry> out = <PortEntry>[];
    for (final Object? row in rawPorts) {
      if (row is Map<String, dynamic>) {
        final PortEntry? e = PortEntry.fromMap(row);
        if (e != null) out.add(e);
      }
    }
    return out;
  }

  /// Search by port number or service-name substring.
  ///
  /// - A query that is purely digits matches the exact port number.
  /// - Any other query is a case-insensitive substring match against the
  ///   service name AND the description, so "wpa" finds RADIUS and "vpn" finds
  ///   the tunneling ports.
  /// - Whitespace-only or empty query returns the full curated list (so the
  ///   screen can show everything before the user types).
  ///
  /// Results are ordered by ascending port number; ties keep asset order.
  List<PortEntry> search(String query) {
    final String q = query.trim();
    if (q.isEmpty) {
      return _sortedByPort(_entries);
    }

    // Pure-digit query → exact port-number lookup.
    if (RegExp(r'^\d+$').hasMatch(q)) {
      final int? port = int.tryParse(q);
      if (port == null) return const <PortEntry>[];
      return _sortedByPort(_byPort[port] ?? const <PortEntry>[]);
    }

    // Otherwise substring match on name + description (case-insensitive).
    final String needle = q.toLowerCase();
    final List<PortEntry> hits = _entries
        .where((PortEntry e) =>
            e.name.toLowerCase().contains(needle) ||
            e.description.toLowerCase().contains(needle))
        .toList();
    return _sortedByPort(hits);
  }

  static List<PortEntry> _sortedByPort(List<PortEntry> entries) {
    final List<PortEntry> copy = List<PortEntry>.of(entries);
    copy.sort((a, b) => a.port.compareTo(b.port));
    return copy;
  }
}
