// GlossaryService — load the bundled Wi-Fi Glossary (assets/data/glossary.json,
// declared in pubspec.yaml) into typed Dart models, fully offline.
//
// WHAT IT DOES: parses the 92-term curated glossary into [GlossaryTerm] models,
// groups them by `category` IN FILE ORDER (the curation order of categories and
// of terms within each category is deliberate — never alphabetized), and answers
// a free-text search consistent with the app's other reference/list screens
// (case-insensitive substring match across term, abbr, and definition).
//
// MULTILINGUAL (added 2026-06-12): each term carries its DEFINITION in five
// languages — English (default) plus ES / FR / IT / DE — keyed by ISO 639-1 code
// in the `definitions` map. The TERM and its `abbr` ALWAYS stay English: Wi-Fi
// professionals do not translate "beamforming", "OFDMA", or "RSSI", so only the
// explanatory prose is localized. English is the guaranteed fallback: a term
// with no translation for the active language renders its English definition.
// Translations are author-generated drafts flagged `translation_status:
// draft-needs-review` until a professional review lands (GL-005).
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
// rendered as a blank line. A missing translation falls back to English (never a
// blank or fabricated definition).

import 'dart:convert';

/// The languages the glossary can render a definition in.
///
/// The TERM itself (and its [GlossaryTerm.abbr]) always stays in English —
/// professionals do not translate "beamforming", "OFDMA", or "RSSI". Only the
/// explanatory DEFINITION is localized. English is the default and the
/// guaranteed fallback: every other language falls back to [GlossaryLanguage.en]
/// when a translation is missing for a given term.
enum GlossaryLanguage {
  en('en', 'English'),
  es('es', 'Español'),
  fr('fr', 'Français'),
  it('it', 'Italiano'),
  de('de', 'Deutsch');

  const GlossaryLanguage(this.code, this.label);

  /// ISO 639-1 code used as the key in the dataset's `definitions` map.
  final String code;

  /// The endonym shown in the language picker (each language names itself).
  final String label;

  /// The non-English members, in dataset order — the languages whose
  /// translations carry the draft-review flag.
  static List<GlossaryLanguage> get translated =>
      GlossaryLanguage.values.where((GlossaryLanguage l) => l != en).toList();

  /// Resolve a code to a language, or `null` when unrecognized.
  static GlossaryLanguage? fromCode(String code) {
    for (final GlossaryLanguage l in GlossaryLanguage.values) {
      if (l.code == code) return l;
    }
    return null;
  }
}

/// One glossary term.
///
/// [abbr] is the companion identifier the dataset pairs with the term. When the
/// term is a full name, [abbr] is its acronym (e.g. "Co-Channel Interference" →
/// "CCI"); when the term is itself an acronym, [abbr] is the expansion (e.g.
/// "RSSI" → "Received Signal Strength Indicator"). It is `null` when the dataset
/// carries no companion form.
///
/// [definitions] holds the per-language DEFINITION text keyed by ISO 639-1 code.
/// English (`en`) is always present (it mirrors [definition]); the other four
/// languages are present when a draft translation exists. Read a localized
/// definition via [definitionFor], which falls back to English.
class GlossaryTerm {
  GlossaryTerm({
    required this.id,
    required this.term,
    required this.abbr,
    required this.category,
    required this.definition,
    Map<String, String>? definitions,
  }) : definitions = Map<String, String>.unmodifiable(<String, String>{
          // English is always present and authoritative; a `definitions.en`
          // override is ignored in favor of the canonical `definition` field.
          ...?definitions,
          GlossaryLanguage.en.code: definition,
        });

  /// Stable identifier (kebab-case). Never renamed — backs tests.
  final String id;

  /// The term as displayed (e.g. "Co-Channel Interference", "RSSI"). Always
  /// English — never translated.
  final String term;

  /// Companion identifier (acronym or expansion), or `null` when absent. Always
  /// English — never translated.
  final String? abbr;

  /// Curated category name (one of the 8 groups), verbatim from the dataset.
  final String category;

  /// Plain-language English definition (one or more sentences). The default and
  /// the fallback for every other language.
  final String definition;

  /// Per-language definition text keyed by ISO 639-1 code. Always carries `en`;
  /// carries `es` / `fr` / `it` / `de` when a draft translation exists.
  final Map<String, String> definitions;

  /// The definition in [lang], falling back to the English [definition] when no
  /// translation exists for that language. Never returns an empty string for a
  /// well-formed term (GL-005: fall back, never blank).
  String definitionFor(GlossaryLanguage lang) =>
      definitions[lang.code] ?? definition;

  /// `true` when this term carries a non-empty translation for [lang] (i.e. the
  /// localized text is not just the English fallback). Always `false` for
  /// English (English is the source, not a translation).
  bool hasTranslation(GlossaryLanguage lang) {
    if (lang == GlossaryLanguage.en) return false;
    final String? t = definitions[lang.code];
    return t != null && t.trim().isNotEmpty;
  }

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

    // definitions is optional: a map of {lang-code: text}. Only non-empty string
    // values for the four translated languages are kept; English is sourced from
    // the canonical `definition` field, not this map.
    final Map<String, String> defs = <String, String>{};
    final Object? rawDefs = map['definitions'];
    if (rawDefs is Map) {
      for (final GlossaryLanguage lang in GlossaryLanguage.translated) {
        final Object? v = rawDefs[lang.code];
        if (v is String && v.trim().isNotEmpty) {
          defs[lang.code] = v.trim();
        }
      }
    }

    return GlossaryTerm(
      id: id,
      term: term,
      abbr: abbr,
      category: category,
      definition: definition,
      definitions: defs,
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

  /// `true` when at least one term carries a non-English translation — i.e. the
  /// dataset is multilingual and the screen should offer the language picker.
  /// The Wi-Fi Authentication Glossary (English-only) returns `false`, so it
  /// renders without a picker that would otherwise promise translations it lacks.
  bool get hasTranslations => _entries.any(
        (GlossaryTerm e) => GlossaryLanguage.translated.any(e.hasTranslation),
      );

  /// The languages this glossary can actually render: English plus any
  /// translated language for which at least one term carries text. Always leads
  /// with English. An English-only dataset returns just `[en]`.
  List<GlossaryLanguage> get availableLanguages => <GlossaryLanguage>[
        GlossaryLanguage.en,
        for (final GlossaryLanguage l in GlossaryLanguage.translated)
          if (_entries.any((GlossaryTerm e) => e.hasTranslation(l))) l,
      ];

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

  /// Case-insensitive substring search across term, abbr, and the definition in
  /// [lang]. A whitespace-only or empty query returns all terms (in file order)
  /// so the screen shows the full glossary before the user types. Results
  /// preserve file order so grouping stays stable.
  ///
  /// The term and abbr are always searched in English (they are never
  /// translated). The definition searched is the one for [lang] (default
  /// English) — so a user reading the Spanish glossary can search Spanish words
  /// in the definitions while still matching the English term / acronym.
  List<GlossaryTerm> search(
    String query, {
    GlossaryLanguage lang = GlossaryLanguage.en,
  }) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return _entries;
    return _entries.where((GlossaryTerm e) {
      if (e.term.toLowerCase().contains(q)) return true;
      final String? a = e.abbr;
      if (a != null && a.toLowerCase().contains(q)) return true;
      // English definition always searchable (it is the canonical text and the
      // fallback); the active-language definition is searched too when different.
      if (e.definition.toLowerCase().contains(q)) return true;
      final String localized = e.definitionFor(lang);
      if (localized.toLowerCase().contains(q)) return true;
      return false;
    }).toList();
  }
}
