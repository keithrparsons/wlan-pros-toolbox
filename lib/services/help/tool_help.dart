// ToolHelp — the in-app help model + loader for every catalog tool.
//
// SOURCE OF TRUTH: assets/help/tool_help.json (declared in pubspec.yaml),
// generated from FIELD-MANUAL.md. The document shape is:
//
//   {
//     "version": "1.0",
//     "generatedFrom": "...",
//     "tools": {
//       "<catalog-tool-id>": {
//         "name": String,
//         "category": String,
//         "purpose": String,
//         "whyHere": String,
//         "howToUse": [String, ...],
//         "inputs": [ { "name": String, "unit": String, "range": String }, ... ],
//         "algorithm": String | null,
//         "example": String | null,
//         "fieldNotes": [String, ...],
//         "source": String
//       },
//       ...
//     }
//   }
//
// Each entry is keyed by the STABLE catalog tool id (ToolEntry.id), so a screen
// or browse row can look up its help by the same id it uses for routes, icons,
// and tests.
//
// OFFLINE / NO NETWORK: the JSON is a bundled asset, loaded and parsed ONCE and
// cached in memory for the process lifetime. Parsing is pure Dart (no Flutter
// imports here) so it is unit-testable from an in-memory string; the async
// asset load is a thin wrapper in [ToolHelpStore.ensureLoaded].
//
// HONESTY (GL-005): the parser preserves every field-note caveat verbatim. It
// never drops, paraphrases, or fabricates content. A tool with no entry returns
// null from [helpForId] — the help affordance is hidden, never faked.

import 'dart:convert';

/// One input field a tool accepts, as documented for help. All three parts are
/// plain text taken verbatim from the source; `unit` / `range` may be empty
/// strings when the source left them blank.
class ToolHelpInput {
  const ToolHelpInput({
    required this.name,
    required this.unit,
    required this.range,
  });

  /// Field name (e.g. "Frequency").
  final String name;

  /// Unit hint (e.g. "GHz (default) or MHz"). May be empty.
  final String unit;

  /// Valid range / constraint (e.g. "must be > 0"). May be empty.
  final String range;

  /// Build from a decoded JSON map. Returns null when the row has no usable
  /// `name`, so a malformed input row is dropped rather than rendering blank.
  static ToolHelpInput? fromMap(Map<String, dynamic> map) {
    final Object? rawName = map['name'];
    final String name = rawName is String ? rawName.trim() : '';
    if (name.isEmpty) return null;
    final Object? rawUnit = map['unit'];
    final Object? rawRange = map['range'];
    return ToolHelpInput(
      name: name,
      unit: rawUnit is String ? rawUnit.trim() : '',
      range: rawRange is String ? rawRange.trim() : '',
    );
  }
}

/// The complete help entry for one tool. Sections that are absent in the source
/// resolve to empty lists or null, and the help sheet skips them — the sheet
/// renders only the sections that carry content.
class ToolHelp {
  const ToolHelp({
    required this.id,
    required this.name,
    required this.category,
    required this.purpose,
    required this.whyHere,
    required this.howToUse,
    required this.inputs,
    required this.algorithm,
    required this.example,
    required this.fieldNotes,
    required this.source,
  });

  /// Stable catalog tool id this help belongs to (the JSON map key).
  final String id;

  /// Display name (matches the tool's title intent).
  final String name;

  /// The catalog category this tool belongs to (used to group the browse
  /// screen). Verbatim from the source.
  final String category;

  /// What the tool computes / shows.
  final String purpose;

  /// Why the tool is in the toolbox — when to reach for it.
  final String whyHere;

  /// Step-by-step usage. Empty when the source had no steps.
  final List<String> howToUse;

  /// Documented inputs. Empty for tools with no inputs (reference tables).
  final List<ToolHelpInput> inputs;

  /// Algorithm / formula, or null when the tool has no computation to document.
  final String? algorithm;

  /// Worked example, or null when the source had none.
  final String? example;

  /// Field notes / caveats. Rendered verbatim and never dropped (GL-005).
  final List<String> fieldNotes;

  /// Provenance string (where the help / implementation comes from).
  final String source;

  /// True when this entry looks like a formula-bearing tool. Used by the sheet
  /// to decide whether [algorithm] renders in a mono code style. Heuristic:
  /// there is an algorithm AND it contains a recognizable formula token.
  bool get algorithmReadsAsFormula {
    final String? a = algorithm;
    if (a == null) return false;
    return a.contains('=') ||
        a.contains('·') ||
        a.contains('log') ||
        a.contains('√') ||
        a.contains('×') ||
        a.contains('÷');
  }

  /// Build from a decoded JSON map and its key. Tolerant: a missing string
  /// field becomes empty, a missing list becomes empty, algorithm/example stay
  /// null when absent or JSON null. Returns null only when there is no usable
  /// `name` (a structurally broken entry).
  static ToolHelp? fromMap(String id, Map<String, dynamic> map) {
    String str(String key) {
      final Object? v = map[key];
      return v is String ? v.trim() : '';
    }

    String? strOrNull(String key) {
      final Object? v = map[key];
      if (v is! String) return null;
      final String s = v.trim();
      return s.isEmpty ? null : s;
    }

    List<String> strList(String key) {
      final Object? v = map[key];
      if (v is! List) return const <String>[];
      return v
          .whereType<String>()
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList(growable: false);
    }

    final String name = str('name');
    if (name.isEmpty) return null;

    final List<ToolHelpInput> inputs = <ToolHelpInput>[];
    final Object? rawInputs = map['inputs'];
    if (rawInputs is List) {
      for (final Object? row in rawInputs) {
        if (row is Map<String, dynamic>) {
          final ToolHelpInput? i = ToolHelpInput.fromMap(row);
          if (i != null) inputs.add(i);
        }
      }
    }

    return ToolHelp(
      id: id,
      name: name,
      category: str('category'),
      purpose: str('purpose'),
      whyHere: str('whyHere'),
      howToUse: strList('howToUse'),
      inputs: List<ToolHelpInput>.unmodifiable(inputs),
      algorithm: strOrNull('algorithm'),
      example: strOrNull('example'),
      fieldNotes: strList('fieldNotes'),
      source: str('source'),
    );
  }
}

/// Parses and indexes the bundled help JSON, keyed by catalog tool id.
///
/// Pure: [ToolHelpStore.fromJson] takes the raw string and never touches
/// Flutter, so it is unit-testable from an in-memory fixture. The async asset
/// load + process-lifetime cache live in [ToolHelpStore.ensureLoaded].
class ToolHelpStore {
  ToolHelpStore._(this._byId);

  final Map<String, ToolHelp> _byId;

  /// Build from the raw asset JSON string. Tolerant of malformed entries: a
  /// structurally broken entry is skipped, never thrown. Returns an
  /// empty-but-valid store when the document has no usable `tools` object.
  factory ToolHelpStore.fromJson(String jsonString) {
    return ToolHelpStore._(parseEntries(jsonString));
  }

  /// Parse the asset JSON into an id→[ToolHelp] map. Static + pure so the parse
  /// is unit-testable without an asset load. Tolerant of a malformed document:
  /// invalid JSON (or a non-object root) yields an empty-but-valid map rather
  /// than throwing — a corrupt asset degrades to "no help", never a crash.
  static Map<String, ToolHelp> parseEntries(String jsonString) {
    Object? decoded;
    try {
      decoded = jsonDecode(jsonString);
    } on FormatException {
      return <String, ToolHelp>{};
    }
    if (decoded is! Map<String, dynamic>) return <String, ToolHelp>{};
    final Object? rawTools = decoded['tools'];
    if (rawTools is! Map) return <String, ToolHelp>{};

    final Map<String, ToolHelp> out = <String, ToolHelp>{};
    rawTools.forEach((Object? key, Object? value) {
      if (key is String && value is Map<String, dynamic>) {
        final ToolHelp? help = ToolHelp.fromMap(key, value);
        if (help != null) out[key] = help;
      }
    });
    return out;
  }

  /// Number of help entries loaded.
  int get count => _byId.length;

  /// Every loaded entry (unordered).
  Iterable<ToolHelp> get all => _byId.values;

  /// Look up help for a catalog tool id. Returns null when no entry exists —
  /// callers MUST treat null as "no help" (hide the affordance), never fake it.
  ToolHelp? forId(String id) => _byId[id];
}
