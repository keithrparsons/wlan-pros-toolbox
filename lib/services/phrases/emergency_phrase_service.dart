// EmergencyPhraseService — load the bundled Emergency Phrases dataset
// (assets/data/emergency_phrases.json, declared in pubspec.yaml) into typed Dart
// models, fully offline.
//
// WHAT IT DOES: parses ~124 travel/emergency phrases into [EmergencyPhrase]
// models, each carrying an English source plus four target translations
// (es / fr / it / de). It groups the phrases by `category` IN FILE ORDER (the
// curation order of categories, and of phrases within a category, is deliberate
// — never alphabetized), and answers a free-text search consistent with the
// app's other reference/list screens (case-insensitive substring match across
// every language string + the id).
//
// OFFLINE / NO NETWORK: the dataset is a bundled asset, loaded and parsed once
// at screen open. No HTTP, NO Flutter imports — the screen reads the asset
// string via rootBundle and hands it to [EmergencyPhraseService.fromJson], so
// the logic is pure Dart and unit-testable from an in-memory string.
//
// TRANSLATION HONESTY (GL-005): the dataset is flagged
// `translation_status: "draft-needs-review"`. These are DRAFT machine
// translations that have NOT been reviewed by a native or professional
// translator. The service surfaces that flag verbatim via [translationStatus]
// and [translationNote] so the screen can show the user a clear draft banner;
// it never silently presents a draft translation as verified. A malformed row
// (missing id / category / English, or missing ANY of the four target
// translations) is DROPPED, not rendered as a blank cell — the screen never
// shows an empty translation that could be mistaken for "no word needed".
//
// ORDER PRESERVATION: groups appear in the order their category is FIRST SEEN in
// the `phrases` array, and phrases inside a group keep their file order. When
// the list is filtered (search), the same ordering rule applies to the
// surviving subset.

import 'dart:convert';

/// The sentinel value of `translation_status` that marks the dataset as
/// unreviewed draft machine translation. The screen shows its draft banner
/// whenever [EmergencyPhraseService.translationStatus] equals this.
const String kDraftNeedsReview = 'draft-needs-review';

/// A target (non-English) language column in the dataset.
class PhraseLanguage {
  const PhraseLanguage({
    required this.code,
    required this.label,
    required this.native,
  });

  /// ISO-639-1 code (`es`, `fr`, `it`, `de`). Backs the per-phrase map lookup
  /// and is stable.
  final String code;

  /// English label of the language (e.g. "Spanish"). Used in the picker.
  final String label;

  /// Endonym / native name (e.g. "Español"). Shown beside the English label.
  final String native;

  /// Build from a decoded JSON map. Returns `null` when the row is malformed
  /// (missing code or label) so a bad asset row is dropped.
  static PhraseLanguage? fromMap(Map<String, dynamic> map) {
    final String code = _str(map['code']);
    final String label = _str(map['label']);
    if (code.isEmpty || label.isEmpty) return null;
    final String native = _str(map['native']);
    return PhraseLanguage(
      code: code,
      label: label,
      native: native.isEmpty ? label : native,
    );
  }

  static String _str(Object? v) => v is String ? v.trim() : '';
}

/// One phrase: an English source plus its four target translations, keyed by
/// language code.
class EmergencyPhrase {
  const EmergencyPhrase({
    required this.id,
    required this.category,
    required this.english,
    required this.translations,
  });

  /// Stable identifier (kebab-case). Never renamed — backs tests.
  final String id;

  /// Curated category name (one of the situation groups), verbatim from the
  /// dataset.
  final String category;

  /// The English source phrase (always present; it is the canonical text).
  final String english;

  /// Target translations keyed by language code (`es`/`fr`/`it`/`de`). Every
  /// target language in the dataset header is guaranteed present and non-empty
  /// for a surviving row (a row missing any target is dropped in [fromMap]).
  final Map<String, String> translations;

  /// Translation for [code], or `null` when absent. `en` returns [english].
  String? forCode(String code) =>
      code == 'en' ? english : translations[code];

  /// Build from a decoded JSON map against the dataset's [targetCodes]. Returns
  /// `null` when the row is malformed: missing id / category / English, or
  /// missing/blank ANY required target translation. A dropped row is never
  /// rendered, so the screen cannot show a blank translation cell.
  static EmergencyPhrase? fromMap(
    Map<String, dynamic> map,
    List<String> targetCodes,
  ) {
    final String id = _str(map['id']);
    final String category = _str(map['category']);
    final String english = _str(map['en']);
    if (id.isEmpty || category.isEmpty || english.isEmpty) return null;

    final Map<String, String> translations = <String, String>{};
    for (final String code in targetCodes) {
      final String value = _str(map[code]);
      if (value.isEmpty) return null; // every target must be present + non-empty
      translations[code] = value;
    }

    return EmergencyPhrase(
      id: id,
      category: category,
      english: english,
      translations: Map<String, String>.unmodifiable(translations),
    );
  }

  static String _str(Object? v) => v is String ? v.trim() : '';
}

/// A category group: a header plus the phrases under it, in file order.
class PhraseGroup {
  const PhraseGroup({required this.category, required this.phrases});

  /// The category name (the group header).
  final String category;

  /// Phrases in this category, in file order.
  final List<EmergencyPhrase> phrases;

  /// Number of phrases in the group.
  int get count => phrases.length;
}

/// Indexes the Emergency Phrases dataset and answers grouping + search. Pure
/// Dart; no Flutter dependency, so it is unit-testable from a JSON string.
class EmergencyPhraseService {
  /// Build directly from parsed entries (used by tests and by [fromJson]).
  EmergencyPhraseService.fromEntries(
    List<EmergencyPhrase> entries, {
    this.title = 'Emergency Phrases',
    this.languages = const <PhraseLanguage>[],
    this.translationStatus = '',
    this.translationNote = '',
  }) : _entries = List<EmergencyPhrase>.unmodifiable(entries);

  /// Build from the raw asset JSON string. Tolerant of malformed rows: bad
  /// entries are skipped, never thrown. Returns an empty-but-valid service if
  /// the document has no usable `phrases` array.
  factory EmergencyPhraseService.fromJson(String jsonString) {
    Object? decoded;
    try {
      decoded = jsonDecode(jsonString);
    } on FormatException {
      // A non-JSON string yields an empty-but-valid service rather than
      // throwing — the screen renders its honest error/empty state, never a
      // crash. (A shipped asset is always valid JSON; this guards tests + a
      // corrupted asset.)
      return EmergencyPhraseService.fromEntries(const <EmergencyPhrase>[]);
    }
    if (decoded is! Map<String, dynamic>) {
      return EmergencyPhraseService.fromEntries(const <EmergencyPhrase>[]);
    }

    final List<PhraseLanguage> languages = parseLanguages(decoded);
    final List<String> targetCodes = <String>[
      for (final PhraseLanguage l in languages)
        if (l.code != 'en') l.code,
    ];
    final List<EmergencyPhrase> entries = parseEntries(decoded, targetCodes);

    String title = 'Emergency Phrases';
    final String t = EmergencyPhrase._str(decoded['title']);
    if (t.isNotEmpty) title = t;

    return EmergencyPhraseService.fromEntries(
      entries,
      title: title,
      languages: languages,
      translationStatus: EmergencyPhrase._str(decoded['translation_status']),
      translationNote: EmergencyPhrase._str(decoded['translation_note']),
    );
  }

  final List<EmergencyPhrase> _entries;

  /// Dataset title from the document's top-level `title`.
  final String title;

  /// The languages declared in the dataset header, in display order. The first
  /// is always English (the source); the rest are the target columns.
  final List<PhraseLanguage> languages;

  /// The dataset's `translation_status`. When it equals [kDraftNeedsReview] the
  /// screen shows the draft banner. Surfaced verbatim — never suppressed.
  final String translationStatus;

  /// The dataset's `translation_note` — a short human-readable caveat shown in
  /// the draft banner and help entry.
  final String translationNote;

  /// `true` when the dataset is flagged as unreviewed draft machine translation.
  bool get isDraft => translationStatus == kDraftNeedsReview;

  /// English source language descriptor (the first dataset language), or a
  /// default English descriptor when the header omitted it.
  PhraseLanguage get sourceLanguage => languages.isNotEmpty
      ? languages.first
      : const PhraseLanguage(code: 'en', label: 'English', native: 'English');

  /// The non-English target languages, in dataset order.
  List<PhraseLanguage> get targetLanguages =>
      languages.where((PhraseLanguage l) => l.code != 'en').toList();

  /// All phrases, in file order.
  List<EmergencyPhrase> get all => _entries;

  /// Number of phrases loaded.
  int get count => _entries.length;

  /// The distinct category names, in first-seen (file) order. Drives the
  /// section sequence and is asserted by tests.
  List<String> get categoriesInOrder {
    final List<String> order = <String>[];
    for (final EmergencyPhrase e in _entries) {
      if (!order.contains(e.category)) order.add(e.category);
    }
    return List<String>.unmodifiable(order);
  }

  /// Number of distinct categories.
  int get categoryCount => categoriesInOrder.length;

  /// Parse the dataset header `languages` array. Static + pure so it is
  /// unit-testable without constructing a service. Falls back to the standard
  /// EN + es/fr/it/de set when the header is absent or empty (defensive).
  static List<PhraseLanguage> parseLanguages(Map<String, dynamic> decoded) {
    final Object? raw = decoded['languages'];
    final List<PhraseLanguage> out = <PhraseLanguage>[];
    if (raw is List) {
      for (final Object? row in raw) {
        if (row is Map<String, dynamic>) {
          final PhraseLanguage? l = PhraseLanguage.fromMap(row);
          if (l != null) out.add(l);
        }
      }
    }
    if (out.isEmpty) {
      return const <PhraseLanguage>[
        PhraseLanguage(code: 'en', label: 'English', native: 'English'),
        PhraseLanguage(code: 'es', label: 'Spanish', native: 'Español'),
        PhraseLanguage(code: 'fr', label: 'French', native: 'Français'),
        PhraseLanguage(code: 'it', label: 'Italian', native: 'Italiano'),
        PhraseLanguage(code: 'de', label: 'German', native: 'Deutsch'),
      ];
    }
    return List<PhraseLanguage>.unmodifiable(out);
  }

  /// Parse the decoded asset document into a list of phrases, dropping any row
  /// that is missing a required field or any target translation. Static + pure
  /// so the parse is unit-testable without constructing a service.
  static List<EmergencyPhrase> parseEntries(
    Map<String, dynamic> decoded,
    List<String> targetCodes,
  ) {
    final Object? raw = decoded['phrases'];
    if (raw is! List) return const <EmergencyPhrase>[];
    final List<EmergencyPhrase> out = <EmergencyPhrase>[];
    for (final Object? row in raw) {
      if (row is Map<String, dynamic>) {
        final EmergencyPhrase? e = EmergencyPhrase.fromMap(row, targetCodes);
        if (e != null) out.add(e);
      }
    }
    return out;
  }

  /// Look up a single phrase by id, or `null` when absent.
  EmergencyPhrase? byId(String id) {
    for (final EmergencyPhrase e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Group [entries] (default: all) by `category`, ordered by first appearance
  /// in the file (which reproduces the curated category sequence, since each
  /// category's phrases are contiguous). Phrases keep their file order within
  /// each group. Empty categories are omitted.
  List<PhraseGroup> grouped([List<EmergencyPhrase>? entries]) {
    final List<EmergencyPhrase> source = entries ?? _entries;

    final Map<String, List<EmergencyPhrase>> buckets =
        <String, List<EmergencyPhrase>>{};
    final List<String> order = <String>[];
    for (final EmergencyPhrase e in source) {
      final List<EmergencyPhrase> bucket = buckets.putIfAbsent(e.category, () {
        order.add(e.category);
        return <EmergencyPhrase>[];
      });
      bucket.add(e);
    }

    return <PhraseGroup>[
      for (final String c in order)
        PhraseGroup(category: c, phrases: buckets[c]!),
    ];
  }

  /// Case-insensitive substring search across every language string and the id.
  /// A whitespace-only or empty query returns all phrases (in file order) so the
  /// screen shows the full set before the user types. Results preserve file
  /// order so grouping stays stable. Searching all languages (not just the
  /// displayed columns) means a user can find a phrase by typing it in any of
  /// the five languages regardless of which target column is currently shown.
  List<EmergencyPhrase> search(String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return _entries;
    return _entries.where((EmergencyPhrase e) {
      if (e.english.toLowerCase().contains(q)) return true;
      if (e.id.toLowerCase().contains(q)) return true;
      for (final String value in e.translations.values) {
        if (value.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }
}
