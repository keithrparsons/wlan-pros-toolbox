// GlossaryService — load the bundled Wi-Fi Glossary (assets/data/glossary.json,
// declared in pubspec.yaml) into typed Dart models, fully offline.
//
// WHAT IT DOES: parses the 92-term curated glossary into [GlossaryTerm] models,
// groups them by `category` IN FILE ORDER (the curation order of categories and
// of terms within each category is deliberate — never alphabetized), and answers
// a free-text search consistent with the app's other reference/list screens
// (case-insensitive substring match across term, abbr, and definition).
//
// OFFLINE / NO NETWORK: the glossary is a bundled asset, loaded and parsed once
// at screen open. No HTTP, NO Flutter imports — the screen reads the asset string
// via rootBundle and hands it to [GlossaryService.fromJson], so the logic is pure
// Dart and unit-testable from an in-memory string.
//
// ORDER PRESERVATION: groups appear in the order their category is FIRST SEEN in
// the `terms` array, and terms inside a group keep their file order. The dataset
// lists all terms of a category contiguously, so first-seen order reproduces the
// intended 8-category sequence without a separate order list. When the glossary
// is filtered (search), the same ordering rule applies to the surviving subset.
//
// HONESTY (GL-005): an unmatched query returns an empty result, never a
// fabricated row. A malformed entry (missing id/term/category) is dropped, not
// rendered as a blank line.

import 'dart:convert';

/// One glossary term.
///
/// [abbr] is the companion identifier the dataset pairs with the term. When the
/// term is a full name, [abbr] is its acronym (e.g. "Co-Channel Interference" →
/// "CCI"); when the term is itself an acronym, [abbr] is the expansion (e.g.
/// "RSSI" → "Received Signal Strength Indicator"). It is `null` when the dataset
/// carries no companion form.
class GlossaryTerm {
  const GlossaryTerm({
    required this.id,
    required this.term,
    required this.abbr,
    required this.category,
    required this.definition,
  });

  /// Stable identifier (kebab-case). Never renamed — backs tests.
  final String id;

  /// The term as displayed (e.g. "Co-Channel Interference", "RSSI").
  final String term;

  /// Companion identifier (acronym or expansion), or `null` when absent.
  final String? abbr;

  /// Curated category name (one of the 8 groups), verbatim from the dataset.
  final String category;

  /// Plain-language definition (one or more sentences).
  final String definition;

  /// Build from a decoded JSON map. Returns `null` when the row is malformed
  /// (missing id / term / category / definition) so a bad asset row is dropped
  /// rather than crashing the load or rendering a blank line.
  static GlossaryTerm? fromMap(Map<String, dynamic> map) {
    final String id = _str(map['id']);
    final String term = _str(map['term']);
    final String category = _str(map['category']);
    final String definition = _str(map['definition']);
    if (id.isEmpty ||
        term.isEmpty ||
        category.isEmpty ||
        definition.isEmpty) {
      return null;
    }
    // abbr is optional: a non-empty string, else null.
    final Object? rawAbbr = map['abbr'];
    final String? abbr =
        (rawAbbr is String && rawAbbr.trim().isNotEmpty) ? rawAbbr.trim() : null;

    return GlossaryTerm(
      id: id,
      term: term,
      abbr: abbr,
      category: category,
      definition: definition,
    );
  }

  static String _str(Object? v) => v is String ? v.trim() : '';
}

/// A category group: a header plus the terms under it, in file order.
class GlossaryGroup {
  const GlossaryGroup({required this.category, required this.terms});

  /// The category name (the group header).
  final String category;

  /// Terms in this category, in file order.
  final List<GlossaryTerm> terms;

  /// Number of terms in the group.
  int get count => terms.length;
}

/// Indexes the Wi-Fi Glossary and answers grouping + search. Pure Dart; no
/// Flutter dependency, so it is unit-testable from a JSON string.
class GlossaryService {
  /// Build directly from parsed entries (used by tests and by [fromJson]).
  GlossaryService.fromEntries(
    List<GlossaryTerm> entries, {
    this.title = 'Wi-Fi Glossary',
    this.source = '',
  }) : _entries = List<GlossaryTerm>.unmodifiable(entries);

  /// Build from the raw asset JSON string. Tolerant of malformed rows: bad
  /// entries are skipped, never thrown. Returns an empty-but-valid service if
  /// the document has no usable `terms` array.
  factory GlossaryService.fromJson(String jsonString) {
    final Object? decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      return GlossaryService.fromEntries(const <GlossaryTerm>[]);
    }

    final List<GlossaryTerm> entries = parseEntries(decoded);

    String title = 'Wi-Fi Glossary';
    final String t = GlossaryTerm._str(decoded['title']);
    if (t.isNotEmpty) title = t;
    final String source = GlossaryTerm._str(decoded['source']);

    return GlossaryService.fromEntries(
      entries,
      title: title,
      source: source,
    );
  }

  final List<GlossaryTerm> _entries;

  /// Glossary title from the document's top-level `title`.
  final String title;

  /// Provenance string from the document's top-level `source` (may be empty).
  final String source;

  /// All terms, in file order.
  List<GlossaryTerm> get all => _entries;

  /// Number of terms loaded.
  int get count => _entries.length;

  /// The distinct category names, in first-seen (file) order. Drives the section
  /// sequence and is asserted by tests.
  List<String> get categoriesInOrder {
    final List<String> order = <String>[];
    for (final GlossaryTerm e in _entries) {
      if (!order.contains(e.category)) order.add(e.category);
    }
    return List<String>.unmodifiable(order);
  }

  /// Number of distinct categories.
  int get categoryCount => categoriesInOrder.length;

  /// Parse the decoded asset document into a list of terms. Static + pure so the
  /// parse is unit-testable without constructing a service.
  static List<GlossaryTerm> parseEntries(Map<String, dynamic> decoded) {
    final Object? rawTerms = decoded['terms'];
    if (rawTerms is! List) return const <GlossaryTerm>[];
    final List<GlossaryTerm> out = <GlossaryTerm>[];
    for (final Object? row in rawTerms) {
      if (row is Map<String, dynamic>) {
        final GlossaryTerm? e = GlossaryTerm.fromMap(row);
        if (e != null) out.add(e);
      }
    }
    return out;
  }

  /// Look up a single term by id, or `null` when absent.
  GlossaryTerm? byId(String id) {
    for (final GlossaryTerm e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Group [entries] (default: all) by `category`, ordered by first appearance
  /// in the file (which reproduces the curated 8-category sequence, since each
  /// category's terms are contiguous). Terms keep their file order within each
  /// group. Empty categories are omitted.
  List<GlossaryGroup> grouped([List<GlossaryTerm>? entries]) {
    final List<GlossaryTerm> source = entries ?? _entries;

    final Map<String, List<GlossaryTerm>> buckets =
        <String, List<GlossaryTerm>>{};
    final List<String> order = <String>[];
    for (final GlossaryTerm e in source) {
      final List<GlossaryTerm> bucket = buckets.putIfAbsent(e.category, () {
        order.add(e.category);
        return <GlossaryTerm>[];
      });
      bucket.add(e);
    }

    return <GlossaryGroup>[
      for (final String c in order)
        GlossaryGroup(category: c, terms: buckets[c]!),
    ];
  }

  /// Case-insensitive substring search across term, abbr, and definition. A
  /// whitespace-only or empty query returns all terms (in file order) so the
  /// screen shows the full glossary before the user types. Results preserve file
  /// order so grouping stays stable.
  List<GlossaryTerm> search(String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return _entries;
    return _entries.where((GlossaryTerm e) {
      if (e.term.toLowerCase().contains(q)) return true;
      final String? a = e.abbr;
      if (a != null && a.toLowerCase().contains(q)) return true;
      if (e.definition.toLowerCase().contains(q)) return true;
      return false;
    }).toList();
  }
}
