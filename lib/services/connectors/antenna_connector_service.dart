// AntennaConnectorService — load the bundled Antenna Connectors reference
// (assets/data/antenna_connectors.json, declared in pubspec.yaml) into typed
// Dart models, fully offline.
//
// WHAT IT DOES: parses an 18-connector practical Wi-Fi antenna-connector table
// into [AntennaConnector] models, groups them by `group` IN FILE ORDER (the
// curation order of groups and of connectors within each group is deliberate —
// never alphabetized), and answers a free-text search consistent with the app's
// other reference/list screens (case-insensitive substring match across every
// displayed field). It also surfaces three editorial sections verbatim from the
// document: vendor trends, a largest→smallest size ordering, and a "top-6
// connectors a Wi-Fi engineer actually meets" teaching list.
//
// OFFLINE / NO NETWORK: the dataset is a bundled asset, loaded and parsed once
// at screen open. No HTTP, NO Flutter imports — the screen reads the asset
// string via rootBundle and hands it to [AntennaConnectorService.fromJson], so
// the logic is pure Dart and unit-testable from an in-memory string.
//
// ORDER PRESERVATION: groups appear in the order their `group` is FIRST SEEN in
// the `connectors` array, and connectors inside a group keep their file order.
//
// HONESTY (GL-005): an unmatched query returns an empty result, never a
// fabricated row. A malformed entry (missing id / connector name) is dropped,
// not rendered as a blank line. Field copy (including the DART entry, which the
// dataset deliberately does NOT spell out as an acronym) is rendered verbatim;
// the service never invents an expansion.
//
// ASSET SOURCE: Keith Parsons draft, verified + augmented by Pax 2026-06-05.
// Provenance is recorded in the document's top-level `source`.

import 'dart:convert';

/// One antenna connector entry. Fields mirror the bundled dataset's connector
/// object. Every field is rendered verbatim — the service never rewrites or
/// expands copy (notably the DART entry's name, which the dataset intentionally
/// leaves un-expanded).
class AntennaConnector {
  const AntennaConnector({
    required this.id,
    required this.connector,
    required this.fullName,
    required this.group,
    required this.reversePolarity,
    required this.typicalWifiUse,
    required this.indoorOutdoor,
    required this.coupling,
    required this.size,
    required this.rfPath,
    required this.impedance,
    required this.frequency,
    required this.mating,
    required this.notes,
  });

  /// Stable identifier (kebab-case). Never renamed — backs the diagram-asset
  /// lookup (`assets/connector-diagrams/<id>.svg`) and tests.
  final String id;

  /// Short connector name as displayed (e.g. "RP-SMA", "N-Type", "DART").
  final String connector;

  /// Full / descriptive name. For DART this is the dataset's
  /// "Cisco Smart Antenna Connector (DART)" — NOT an acronym expansion.
  final String fullName;

  /// Curated group name (one of the document's groups), verbatim.
  final String group;

  /// Reverse-polarity status / note ("Yes (this is the RP variant…)", "No …").
  final String reversePolarity;

  /// Typical Wi-Fi use, one line.
  final String typicalWifiUse;

  /// Indoor / outdoor suitability.
  final String indoorOutdoor;

  /// Coupling mechanism (threaded / push-pull snap / bayonet / multi-port).
  final String coupling;

  /// Physical body size — across-flats for threaded parts, outer diameter for
  /// board-level parts (recognition-aid granularity, not precision metrology).
  /// Sourced from the size-comparison diagram + photo-manifest size data.
  final String size;

  /// Signal-path / typical-use shorthand. "Single coax (1 RF path)" for every
  /// single-coax body; DART is the one multi-path case ("8 RF + 16 digital").
  final String rfPath;

  /// Characteristic impedance (every Wi-Fi connector here is 50 ohm).
  final String impedance;

  /// Upper frequency rating / band coverage.
  final String frequency;

  /// Mating compatibility — the field-troubleshooting column.
  final String mating;

  /// Field notes.
  final String notes;

  /// `true` when this is a reverse-polarity variant, derived from the dataset's
  /// `reverse_polarity` text beginning with "Yes". Drives the optional RP chip.
  bool get isReversePolarity =>
      reversePolarity.trim().toLowerCase().startsWith('yes');

  /// All text fields concatenated lower-case, for substring search.
  String get _searchBlob => <String>[
        connector,
        fullName,
        group,
        reversePolarity,
        typicalWifiUse,
        indoorOutdoor,
        coupling,
        size,
        rfPath,
        impedance,
        frequency,
        mating,
        notes,
      ].join(' ').toLowerCase();

  /// Build from a decoded JSON map. Returns `null` when the row is malformed
  /// (missing id or connector name) so a bad asset row is dropped rather than
  /// crashing the load or rendering a blank line.
  static AntennaConnector? fromMap(Map<String, dynamic> map) {
    final String id = _str(map['id']);
    final String connector = _str(map['connector']);
    if (id.isEmpty || connector.isEmpty) return null;

    return AntennaConnector(
      id: id,
      connector: connector,
      fullName: _str(map['full_name']),
      group: _str(map['group']),
      reversePolarity: _str(map['reverse_polarity']),
      typicalWifiUse: _str(map['typical_wifi_use']),
      indoorOutdoor: _str(map['indoor_outdoor']),
      coupling: _str(map['coupling']),
      size: _str(map['size']),
      rfPath: _str(map['rf_path']),
      impedance: _str(map['impedance']),
      frequency: _str(map['frequency']),
      mating: _str(map['mating']),
      notes: _str(map['notes']),
    );
  }

  static String _str(Object? v) => v is String ? v.trim() : '';
}

/// A connector group: a header plus the connectors under it, in file order.
class AntennaConnectorGroup {
  const AntennaConnectorGroup({required this.group, required this.connectors});

  /// The group name (the section header).
  final String group;

  /// Connectors in this group, in file order.
  final List<AntennaConnector> connectors;

  /// Number of connectors in the group.
  int get count => connectors.length;
}

/// One vendor → typical-connector mapping (editorial "Vendor Trends" section).
class VendorTrend {
  const VendorTrend({required this.vendor, required this.commonConnector});

  final String vendor;
  final String commonConnector;

  static VendorTrend? fromMap(Map<String, dynamic> map) {
    final String vendor = AntennaConnector._str(map['vendor']);
    final String common = AntennaConnector._str(map['common_connector']);
    if (vendor.isEmpty || common.isEmpty) return null;
    return VendorTrend(vendor: vendor, commonConnector: common);
  }
}

/// One row of the "top-6 connectors a Wi-Fi engineer actually meets" teaching
/// list — a connector name plus the context a tech meets it in.
class TopConnector {
  const TopConnector({required this.connector, required this.context});

  final String connector;
  final String context;

  static TopConnector? fromMap(Map<String, dynamic> map) {
    final String connector = AntennaConnector._str(map['connector']);
    final String context = AntennaConnector._str(map['context']);
    if (connector.isEmpty) return null;
    return TopConnector(connector: connector, context: context);
  }
}

/// The "troubleshooting class top 6" editorial block (intro + the 6 + a
/// coverage note).
class TroubleshootingTop6 {
  const TroubleshootingTop6({
    required this.intro,
    required this.connectors,
    required this.coverageNote,
  });

  final String intro;
  final List<TopConnector> connectors;
  final String coverageNote;

  bool get isEmpty => connectors.isEmpty;
}

/// Indexes the Antenna Connectors reference and answers grouping + search +
/// editorial accessors. Pure Dart; no Flutter dependency, so it is
/// unit-testable from a JSON string.
class AntennaConnectorService {
  /// Build directly from parsed parts (used by tests and by [fromJson]).
  AntennaConnectorService.fromParts(
    List<AntennaConnector> connectors, {
    this.title = 'Antenna Connectors',
    this.source = '',
    this.intro = '',
    List<VendorTrend> vendorTrends = const <VendorTrend>[],
    List<String> sizeOrder = const <String>[],
    this.sizeOrderNote = '',
    this.troubleshootingTop6 = const TroubleshootingTop6(
      intro: '',
      connectors: <TopConnector>[],
      coverageNote: '',
    ),
  })  : _connectors = List<AntennaConnector>.unmodifiable(connectors),
        vendorTrends = List<VendorTrend>.unmodifiable(vendorTrends),
        sizeOrder = List<String>.unmodifiable(sizeOrder);

  /// Build from the raw asset JSON string. Tolerant of malformed rows: bad
  /// entries are skipped, never thrown. Returns an empty-but-valid service if
  /// the document has no usable `connectors` array.
  factory AntennaConnectorService.fromJson(String jsonString) {
    final Object? decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      return AntennaConnectorService.fromParts(const <AntennaConnector>[]);
    }

    final List<AntennaConnector> connectors = parseConnectors(decoded);

    String title = 'Antenna Connectors';
    final String t = AntennaConnector._str(decoded['title']);
    if (t.isNotEmpty) title = t;

    return AntennaConnectorService.fromParts(
      connectors,
      title: title,
      source: AntennaConnector._str(decoded['source']),
      intro: AntennaConnector._str(decoded['note']),
      vendorTrends: _parseVendorTrends(decoded['vendor_trends']),
      sizeOrder: _parseStringList(decoded['size_order_largest_to_smallest']),
      sizeOrderNote: AntennaConnector._str(decoded['size_order_note']),
      troubleshootingTop6:
          _parseTop6(decoded['troubleshooting_class_top_6']),
    );
  }

  final List<AntennaConnector> _connectors;

  /// Document title.
  final String title;

  /// Provenance string (may be empty).
  final String source;

  /// Top-level intro / framing note for the reference.
  final String intro;

  /// Editorial "Vendor Trends" rows, in file order.
  final List<VendorTrend> vendorTrends;

  /// Editorial size ordering, largest → smallest.
  final List<String> sizeOrder;

  /// One-line caveat for the size ordering.
  final String sizeOrderNote;

  /// Editorial "top 6 in the field" teaching block.
  final TroubleshootingTop6 troubleshootingTop6;

  /// All connectors, in file order.
  List<AntennaConnector> get all => _connectors;

  /// Number of connectors loaded.
  int get count => _connectors.length;

  /// Distinct group names, in first-seen (file) order. Drives the section
  /// sequence and is asserted by tests.
  List<String> get groupsInOrder {
    final List<String> order = <String>[];
    for (final AntennaConnector e in _connectors) {
      if (e.group.isNotEmpty && !order.contains(e.group)) order.add(e.group);
    }
    return List<String>.unmodifiable(order);
  }

  /// Number of distinct groups.
  int get groupCount => groupsInOrder.length;

  /// Parse the decoded asset document into a list of connectors. Static + pure
  /// so the parse is unit-testable without constructing a service.
  static List<AntennaConnector> parseConnectors(Map<String, dynamic> decoded) {
    final Object? raw = decoded['connectors'];
    if (raw is! List) return const <AntennaConnector>[];
    final List<AntennaConnector> out = <AntennaConnector>[];
    for (final Object? row in raw) {
      if (row is Map<String, dynamic>) {
        final AntennaConnector? e = AntennaConnector.fromMap(row);
        if (e != null) out.add(e);
      }
    }
    return out;
  }

  static List<VendorTrend> _parseVendorTrends(Object? raw) {
    if (raw is! List) return const <VendorTrend>[];
    final List<VendorTrend> out = <VendorTrend>[];
    for (final Object? row in raw) {
      if (row is Map<String, dynamic>) {
        final VendorTrend? v = VendorTrend.fromMap(row);
        if (v != null) out.add(v);
      }
    }
    return out;
  }

  static List<String> _parseStringList(Object? raw) {
    if (raw is! List) return const <String>[];
    final List<String> out = <String>[];
    for (final Object? row in raw) {
      final String s = AntennaConnector._str(row);
      if (s.isNotEmpty) out.add(s);
    }
    return out;
  }

  static TroubleshootingTop6 _parseTop6(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return const TroubleshootingTop6(
        intro: '',
        connectors: <TopConnector>[],
        coverageNote: '',
      );
    }
    final List<TopConnector> conns = <TopConnector>[];
    final Object? list = raw['connectors'];
    if (list is List) {
      for (final Object? row in list) {
        if (row is Map<String, dynamic>) {
          final TopConnector? c = TopConnector.fromMap(row);
          if (c != null) conns.add(c);
        }
      }
    }
    return TroubleshootingTop6(
      intro: AntennaConnector._str(raw['intro']),
      connectors: conns,
      coverageNote: AntennaConnector._str(raw['coverage_note']),
    );
  }

  /// Look up a single connector by id, or `null` when absent.
  AntennaConnector? byId(String id) {
    for (final AntennaConnector e in _connectors) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Group [entries] (default: all) by `group`, ordered by first appearance in
  /// the file (which reproduces the curated sequence). Connectors keep their
  /// file order within each group. Empty groups are omitted.
  List<AntennaConnectorGroup> grouped([List<AntennaConnector>? entries]) {
    final List<AntennaConnector> source = entries ?? _connectors;

    final Map<String, List<AntennaConnector>> buckets =
        <String, List<AntennaConnector>>{};
    final List<String> order = <String>[];
    for (final AntennaConnector e in source) {
      final List<AntennaConnector> bucket = buckets.putIfAbsent(e.group, () {
        order.add(e.group);
        return <AntennaConnector>[];
      });
      bucket.add(e);
    }

    return <AntennaConnectorGroup>[
      for (final String g in order)
        AntennaConnectorGroup(group: g, connectors: buckets[g]!),
    ];
  }

  /// Case-insensitive substring search across every displayed field. A
  /// whitespace-only or empty query returns all connectors (in file order) so
  /// the screen shows the full reference before the user types. Results
  /// preserve file order so grouping stays stable.
  List<AntennaConnector> search(String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return _connectors;
    return _connectors
        .where((AntennaConnector e) => e._searchBlob.contains(q))
        .toList();
  }
}
