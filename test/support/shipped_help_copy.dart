// ============================================================================
// SHARED TEST HELPER: the SHIPPED help copy for one tool, as flat strings.
// ============================================================================
//
// WHY THIS EXISTS (Vera, 2026-07-25, M-01 on the Batteries / SD screens).
//
// Every reference screen test carries a DO-NOT-PRINT list: phrases the research
// brief flagged as unsourced, which must never reach a shipped surface. Those
// sweeps iterated a hand-written `_allProse()` that enumerated the screen's Dart
// data constants and NOTHING ELSE. `assets/help/tool_help.json` is also shipped
// user-facing copy - it renders in the help sheet under every tool - and no test
// scanned it. So a banned phrase living in the help JSON passed every guard, and
// one did: the "B size was skipped to avoid clashing with the radio B battery"
// folklore shipped verbatim in the Batteries help sheet while the guard three
// files away asserted it was absent.
//
// That is a test that cannot fail. This helper is the missing half: it hands a
// screen test the same flat list of strings for the HELP surface that
// `_allProse()` gives it for the DATA surface, so one sweep covers both.
//
// USE IT. Any screen test with a DO-NOT-PRINT list must run its negative
// assertions over `_allProse() + shippedHelpProse('<tool-id>')`. The mechanical
// reminder lives in test/consistency/help_copy_guard_test.dart.
//
// TWO DESIGN CHOICES THAT ARE LOAD-BEARING - do not "simplify" either:
//
//   1. THE WALK IS RECURSIVE AND FIELD-BLIND. It collects every string VALUE
//      anywhere under the entry rather than naming `purpose`, `fieldNotes`, etc.
//      A hand-enumerated field list is the exact defect this file exists to fix,
//      one level down: add `caveats` to the help schema tomorrow and a named
//      list goes quietly blind to it. Keys are not collected - a key is a schema
//      name, not copy a reader sees.
//
//   2. IT THROWS RATHER THAN RETURNING EMPTY. A missing tool id or a
//      near-empty entry raises StateError instead of yielding `[]`, because
//      every caller uses this list for ABSENCE assertions. An empty list makes
//      `expect(s.contains(banned), isFalse)` pass vacuously for all s - green,
//      meaningless, and indistinguishable from real coverage. Failing loud on a
//      renamed id is the whole point.
//
// Reads the file from disk (dart:io) rather than through rootBundle, matching
// test/consistency/voice_no_em_dash_guard_test.dart: no async, no binding, and
// it works in a plain `test()` body.

import 'dart:convert';
import 'dart:io';

/// The shipped help asset, relative to the package root.
const String kToolHelpAssetPath = 'assets/help/tool_help.json';

/// Fewest strings a real help entry can plausibly yield (name, category,
/// purpose, whyHere, source + at least one howToUse / fieldNote). Below this,
/// something is structurally wrong and the caller's absence assertions would be
/// vacuous, so [shippedHelpProse] throws instead.
const int kMinHelpProseStrings = 6;

/// Every user-facing string under a decoded help [entry], recursively.
///
/// Pure: takes already-decoded JSON, so it can be unit-tested against a
/// fixture without touching the bundled asset.
List<String> proseFromEntry(Object? entry) {
  final List<String> out = <String>[];
  void walk(Object? node) {
    if (node is String) {
      out.add(node);
    } else if (node is Map) {
      // Values only. Keys are schema names, not copy.
      for (final Object? v in node.values) {
        walk(v);
      }
    } else if (node is List) {
      for (final Object? v in node) {
        walk(v);
      }
    }
    // Numbers, bools and nulls carry no prose.
  }

  walk(entry);
  return out;
}

/// The full decoded `tools` map from the shipped help asset.
Map<String, dynamic> shippedHelpTools() {
  final File f = File('${helpPackageRoot()}/$kToolHelpAssetPath');
  if (!f.existsSync()) {
    throw StateError(
      'Shipped help asset not found at ${f.path}. The do-not-print guards read '
      'it directly from disk; if it moved, update kToolHelpAssetPath.',
    );
  }
  final Object? root = jsonDecode(f.readAsStringSync());
  if (root is! Map<String, dynamic>) {
    throw StateError('$kToolHelpAssetPath did not decode to a JSON object.');
  }
  final Object? tools = root['tools'];
  if (tools is! Map<String, dynamic>) {
    throw StateError('$kToolHelpAssetPath has no "tools" object.');
  }
  return tools;
}

/// Every shipped user-facing string in the help entry for [toolId].
///
/// Throws [StateError] when the id is absent or the entry is too thin to be a
/// real entry, so a renamed key fails loud instead of turning a caller's
/// absence sweep into a green no-op.
List<String> shippedHelpProse(String toolId) {
  final Map<String, dynamic> tools = shippedHelpTools();
  if (!tools.containsKey(toolId)) {
    throw StateError(
      'No help entry for tool id "$toolId" in $kToolHelpAssetPath. Either the '
      'id was renamed or the entry was dropped. This throws rather than '
      'returning an empty list because callers use it for DO-NOT-PRINT '
      'assertions, which would all pass vacuously against nothing.',
    );
  }
  final List<String> prose = proseFromEntry(tools[toolId]);
  if (prose.length < kMinHelpProseStrings) {
    throw StateError(
      'Help entry "$toolId" yielded only ${prose.length} strings (minimum '
      '$kMinHelpProseStrings). A do-not-print sweep over this would be '
      'vacuous. Check the entry shape in $kToolHelpAssetPath.',
    );
  }
  return prose;
}

/// Climb to the package root (the directory holding pubspec.yaml and lib/).
/// Same walk as the em-dash guard; duplicated deliberately so this helper has
/// no dependency on a test file.
String helpPackageRoot() {
  Directory dir = Directory.current;
  for (int i = 0; i < 6; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/lib').existsSync()) {
      return dir.path;
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.path;
}
