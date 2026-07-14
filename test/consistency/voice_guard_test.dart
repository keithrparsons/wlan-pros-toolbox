// ============================================================================
// VOICE GUARD — shipped user-facing copy obeys the HARD brand-voice rules.
// ============================================================================
//
// WHY THIS TEST EXISTS (the miss it closes). The brand-voice linter has gated
// every article, post, and newsletter for months. It was never once pointed at
// the PRODUCT. The app's user-facing copy is published in Keith's voice too, and
// it had drifted: 249 shipped Dart strings carried an em dash, including the
// About screen title and the company description. It surfaced only by accident —
// a graphic quoted an app string verbatim, and we checked whether the GRAPHIC
// was wrong. It wasn't. The app was.
//
// The sweep fixed the strings. This test is the durable half: the rules that
// gate the prose now gate the product, on every `flutter test` and every CI run
// (exactly like version_consistency_guard_test.dart and leakage_guard_test.dart).
//
// It shells out to scripts/voice-guard.sh → scripts/voice_guard.py, which scans
// only USER-FACING copy: Dart string literals (a tokenizer strips comments — a
// raw grep for an em dash returns 4,147 hits in lib/, almost all of them in
// comments that never ship), the help corpus, the guides, and the rendered value
// keys of the shipped data sets.
//
// It deliberately does NOT flag:
//   - the null marker `'—'` (`v == null ? '—' : ...`) — that is DATA, the "not
//     applicable" glyph in a results table, and rewriting it changes meaning;
//   - help text that QUOTES that glyph to document it;
//   - an en dash inside a range (0–32, A–Z, 128–255) — correct typography;
//   - lib/data/tool_keywords.dart — search-match tokens the user types, never
//     rendered;
//   - third-party brands styled "WiFi", and the IEEE terms "Robust Management
//     Frame" / "Robust Security Network".
//
// A green run means every string the user can actually read obeys the HARD
// rules. A red run prints the file, the line, the rule, and the offending text.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shipped user-facing copy obeys the HARD brand-voice rules', () {
    final String root = _packageRoot();
    final String script = '$root/scripts/voice-guard.sh';

    expect(
      File(script).existsSync(),
      isTrue,
      reason: 'voice-guard.sh missing at $script',
    );

    final ProcessResult r = Process.runSync(
      'bash',
      <String>[script],
      workingDirectory: root,
    );

    // Exit 0 = clean; exit 1 = a HARD voice rule is broken in shipped copy.
    // Rewrite the sentence — never find-and-replace the character.
    expect(
      r.exitCode,
      0,
      reason: 'Voice guard FAILED — shipped user-facing copy breaks a HARD '
          'brand-voice rule.\nSTDOUT:\n${r.stdout}\nSTDERR:\n${r.stderr}',
    );
  });
}

/// Resolve the package root whether the test runs from the package dir or a
/// nested working directory.
String _packageRoot() {
  Directory dir = Directory.current;
  for (int i = 0; i < 6; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        File('${dir.path}/scripts/voice-guard.sh').existsSync()) {
      return dir.path;
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.path;
}
