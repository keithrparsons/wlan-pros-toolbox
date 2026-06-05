// PlmnReferenceService — look up US mobile-network PLMN IDs (MCC/MNC) from a
// bundled, curated table, fully offline.
//
// WHAT IT DOES: indexes a curated table of US Public Land Mobile Network
// identifiers (MCCs 310–316, covering US/PR/GU/VI/AS) and answers the two
// questions a tech asks when a device or a capture shows a raw PLMN code:
//   - "whose network is PLMN N (or MCC/MNC)?" → digit search across mcc / mnc /
//      plmn_id (substring, so "310" finds all 310xxx and "030" finds MNC 030).
//   - "what codes does <carrier> use?"        → carrier/operator substring search.
//
// OFFLINE / NO NETWORK: the table is a bundled asset
// (assets/data/plmn_us.json, declared in pubspec.yaml), loaded and parsed once
// at startup and cached in memory for the process lifetime. No HTTP, no
// `dart:io`, NO Flutter imports — the screen reads the asset string via
// rootBundle and hands it to `PlmnReferenceService.fromJson`, so the logic is
// pure Dart and unit-testable from an in-memory string.
//
// LOAD-BEARING RULE: `mnc` and `plmn_id` are STRINGS with significant leading
// zeros ("004", "030", "061"). They are fixed-width identifiers, not numbers —
// the model declares them `final String` and NEVER `int.tryParse`s them. A
// numeric cast silently corrupts "030" → 30 and "061" → 61.
//
// HONESTY: an unmatched query returns an empty result list, never a fabricated
// "unknown carrier" row. The data is curated from live Wikipedia (provenance in
// the asset's `_meta` block); absence means "not in this US dataset," which the
// screen states plainly. `status` is reproduced as sourced (incl. `unknown` and
// `reserved`) — never upgraded to `operational`.

import 'dart:convert';

/// Live-status of a PLMN allocation, as asserted by the source.
///
/// `unknown` means the allocation exists but live/dead state was not asserted —
/// it is NOT a synonym for operational. `reserved` is a special/non-consumer
/// allocation (public-safety reserve, CBRS).
enum PlmnStatus { operational, notOperational, reserved, unknown }

extension PlmnStatusLabel on PlmnStatus {
  /// Human display label (title-cased; computed in Dart, never stored in JSON).
  String get label {
    switch (this) {
      case PlmnStatus.operational:
        return 'Operational';
      case PlmnStatus.notOperational:
        return 'Not operational';
      case PlmnStatus.reserved:
        return 'Reserved';
      case PlmnStatus.unknown:
        return 'Unknown';
    }
  }

  /// Parse a wire token (case-insensitive). Returns [PlmnStatus.unknown] for an
  /// unrecognized or empty token so a malformed status never reads as
  /// operational and never throws.
  static PlmnStatus fromWire(String token) {
    switch (token.trim().toLowerCase()) {
      case 'operational':
        return PlmnStatus.operational;
      case 'not operational':
        return PlmnStatus.notOperational;
      case 'reserved':
        return PlmnStatus.reserved;
      case 'unknown':
      default:
        return PlmnStatus.unknown;
    }
  }
}

/// One curated US PLMN reference entry. All identifier fields are strings —
/// leading zeros are significant.
class PlmnEntry {
  const PlmnEntry({
    required this.mcc,
    required this.mnc,
    required this.plmnId,
    required this.country,
    required this.region,
    required this.carrier,
    required this.operator,
    required this.status,
  });

  /// Mobile Country Code, 3 digits as a string ("310"). String for schema
  /// consistency with [mnc]/[plmnId].
  final String mcc;

  /// Mobile Network Code, zero-padded to its allocated width as a string
  /// ("004", "030"). NEVER an int — leading zeros are part of the code.
  final String mnc;

  /// The full PLMN ID — mcc + mnc, 5–6 chars as a string ("310004").
  final String plmnId;

  /// Country name ("United States" throughout this dataset).
  final String country;

  /// Territory the allocation serves: US / PR / GU / VI / AS.
  final String region;

  /// Consumer-facing brand (e.g. "Verizon", "Metro by T-Mobile", "FirstNet").
  final String carrier;

  /// Parent legal / registered operator (e.g. "T-Mobile US", "AT&T Mobility").
  /// Empty string when the source carries no distinct parent.
  final String operator;

  /// Live-status as asserted by the source. Reproduced honestly, never
  /// upgraded.
  final PlmnStatus status;

  /// `MCC-MNC` display label, e.g. "310-004". Computed, never stored.
  String get mccMncLabel => '$mcc-$mnc';

  /// `<carrier> (<plmnId>)` short label for screen-reader / list summaries.
  String get label => '$carrier ($plmnId)';

  /// Build from a decoded JSON map. Returns null when a required identifier is
  /// missing/empty (`mcc`, `mnc`, `plmnId`, `carrier`) so a bad asset row is
  /// dropped rather than crashing the load or rendering a blank line. `country`,
  /// `region`, `operator`, and `status` fall back to safe defaults.
  static PlmnEntry? fromMap(Map<String, dynamic> map) {
    final String mcc = _str(map['mcc']);
    final String mnc = _str(map['mnc']);
    final String plmnId = _str(map['plmn_id']);
    final String carrier = _str(map['carrier']);
    if (mcc.isEmpty || mnc.isEmpty || plmnId.isEmpty || carrier.isEmpty) {
      return null;
    }

    return PlmnEntry(
      mcc: mcc,
      mnc: mnc,
      plmnId: plmnId,
      country: _str(map['country']),
      region: _str(map['region']),
      carrier: carrier,
      operator: _str(map['operator']),
      status: PlmnStatusLabel.fromWire(_str(map['status'])),
    );
  }

  /// Trim-and-stringify a raw JSON value. A numeric JSON value (which a careless
  /// edit could introduce for `mnc`) is stringified WITHOUT re-parsing, so the
  /// guard preserves whatever digits are present — but the asset stores strings.
  static String _str(Object? raw) => raw is String ? raw.trim() : '';
}

/// One MCC group of PLMN entries, in ascending `plmnId` order. Used by the
/// screen to render the table as browsable sections (MCC 310, 311, …) instead
/// of one flat 376-row list.
class PlmnGroup {
  const PlmnGroup({required this.mcc, required this.entries});

  /// The Mobile Country Code shared by every entry in this group ("310").
  final String mcc;

  /// Entries under this MCC, ascending by `plmnId`.
  final List<PlmnEntry> entries;

  int get count => entries.length;
}

/// Indexes the curated US PLMN table and answers code / carrier searches.
class PlmnReferenceService {
  /// Build directly from parsed entries (used by tests and by [fromJson]).
  /// Builds a plmnId→entry index once so exact PLMN lookups are O(1).
  PlmnReferenceService.fromEntries(List<PlmnEntry> entries)
      : _entries = List<PlmnEntry>.unmodifiable(_sortedByPlmnId(entries)) {
    for (final PlmnEntry e in _entries) {
      _byPlmnId.putIfAbsent(e.plmnId, () => e);
    }
  }

  /// Build from the raw asset JSON string. Tolerant of malformed rows: bad
  /// entries are skipped, never thrown. Returns an empty-but-valid service if
  /// the document has no usable `plmn` array.
  factory PlmnReferenceService.fromJson(String jsonString) {
    final List<PlmnEntry> entries = parseEntries(jsonString);
    return PlmnReferenceService.fromEntries(entries);
  }

  final List<PlmnEntry> _entries;
  final Map<String, PlmnEntry> _byPlmnId = <String, PlmnEntry>{};

  /// All curated entries, ascending by `plmnId`.
  List<PlmnEntry> get all => _entries;

  /// Number of curated entries loaded.
  int get count => _entries.length;

  /// Exact PLMN-ID lookup ("310004" → the one entry), or null if absent.
  PlmnEntry? byPlmnId(String plmnId) => _byPlmnId[plmnId.trim()];

  /// Parse the asset JSON into a list of entries. Static + pure so the parse is
  /// unit-testable without constructing a service.
  static List<PlmnEntry> parseEntries(String jsonString) {
    final Object? decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) return const <PlmnEntry>[];
    final Object? rawPlmn = decoded['plmn'];
    if (rawPlmn is! List) return const <PlmnEntry>[];
    final List<PlmnEntry> out = <PlmnEntry>[];
    for (final Object? row in rawPlmn) {
      if (row is Map<String, dynamic>) {
        final PlmnEntry? e = PlmnEntry.fromMap(row);
        if (e != null) out.add(e);
      }
    }
    return out;
  }

  /// Search by PLMN code or by carrier/operator name.
  ///
  /// - A pure-digit query is a substring match across `mcc`, `mnc`, and
  ///   `plmnId`, so "310" finds every 310xxx code, "030" finds MNC 030, and
  ///   "310030" finds the exact code. Leading zeros matter — "30" and "030" are
  ///   different queries.
  /// - Any other query is a case-insensitive substring match against `carrier`
  ///   AND `operator`, so "metro" finds Metro by T-Mobile and "dish" finds the
  ///   Boost/Dish rows by their parent.
  /// - Whitespace-only / empty query returns the full list (so the screen shows
  ///   everything before the user types).
  ///
  /// Results are ordered ascending by `plmnId`.
  List<PlmnEntry> search(String query) {
    final String q = query.trim();
    if (q.isEmpty) return _entries;

    // Pure-digit query → substring across the three code fields.
    if (RegExp(r'^\d+$').hasMatch(q)) {
      return _entries
          .where((PlmnEntry e) =>
              e.plmnId.contains(q) ||
              e.mnc.contains(q) ||
              e.mcc.contains(q))
          .toList();
    }

    // Otherwise case-insensitive substring on carrier + operator.
    final String needle = q.toLowerCase();
    return _entries
        .where((PlmnEntry e) =>
            e.carrier.toLowerCase().contains(needle) ||
            e.operator.toLowerCase().contains(needle))
        .toList();
  }

  /// Group the given entries (defaults to all) by MCC, ascending by MCC, each
  /// group's entries already ascending by `plmnId`. Empty groups are omitted, so
  /// a filtered query only shows MCCs that have a hit.
  List<PlmnGroup> grouped([List<PlmnEntry>? entries]) {
    final List<PlmnEntry> source = entries ?? _entries;
    final Map<String, List<PlmnEntry>> byMcc = <String, List<PlmnEntry>>{};
    for (final PlmnEntry e in source) {
      byMcc.putIfAbsent(e.mcc, () => <PlmnEntry>[]).add(e);
    }
    final List<String> mccs = byMcc.keys.toList()..sort();
    return <PlmnGroup>[
      for (final String mcc in mccs)
        PlmnGroup(mcc: mcc, entries: byMcc[mcc]!),
    ];
  }

  /// Number of distinct MCCs in the full dataset (7 for the US: 310–316).
  int get mccCount => grouped().length;

  static List<PlmnEntry> _sortedByPlmnId(List<PlmnEntry> entries) {
    // Fixed-width codes → lexical string compare gives correct numeric order.
    final List<PlmnEntry> copy = List<PlmnEntry>.of(entries);
    copy.sort((PlmnEntry a, PlmnEntry b) => a.plmnId.compareTo(b.plmnId));
    return copy;
  }
}
