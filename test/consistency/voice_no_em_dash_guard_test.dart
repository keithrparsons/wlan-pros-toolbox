// ============================================================================
// VOICE GUARD: no em dash in shipped user-facing copy (GL-004 P0, app-wide).
// ============================================================================
//
// Keith's no-em-dash rule extends to the Toolbox's user-facing UI strings and
// bundled content (scope confirmed 2026-07-13). This guard makes that rule
// mechanical so a future em dash FAILS `flutter test` instead of reaching a
// device screenshot, which is exactly how it slipped through before.
//
// WHY PURE DART (no python subprocess). The sibling leakage guard shells out to
// python3 and degrades to a no-op when python3 is absent. A P0 voice gate must
// never be silently skipped, so this guard is self-contained Dart: it always
// runs, on every runner, and can always fail.
//
// WHAT IT SCANS (the reader, not the grep hit, per GL-005):
//   1. lib/**/*.dart  -> STRING LITERALS only. A char-state tokenizer strips
//      line/block/doc comments and raw/triple/single/double strings, so the
//      ~4,000 em dashes that legitimately live in code COMMENTS are never
//      flagged; only dashes that compile into a rendered string are.
//   2. assets/guides/*.md            -> all prose.
//   3. assets/help/*.json, assets/data/*.json -> every JSON string VALUE.
//   4. assets/**/*.svg               -> rendered markup (XML comments stripped).
//
// EXEMPT (data, not prose):
//   - The null-value glyph literal: a string that is just '—' (or '–')
//     after trimming. It means "not applicable" and changing it changes MEANING.
//   - The DOCUMENTED glyph: a dash wrapped in quotes or parens, e.g. ("—"),
//     used by help copy to describe the blank marker on its own screen. Stripping
//     it would make the help factually wrong.
//   - En-dash RANGES (0–128, A–Z, 128–255): a tight en dash between
//     two non-spaces. Only a SPACE-flanked en dash (prose punctuation) is flagged.
//
// The glyphs are built from code points so THIS file stays em-dash-free and can
// never false-positive against its own text.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const int _kEm = 0x2014; // em dash
const int _kEn = 0x2013; // en dash
const int _kSpace = 0x20;
final String _em = String.fromCharCode(_kEm);
final String _en = String.fromCharCode(_kEn);

/// A flagged occurrence.
class _Hit {
  _Hit(this.file, this.where, this.snippet);
  final String file;
  final String where; // line number or JSON path
  final String snippet;
  @override
  String toString() => '  $file:$where  ${_short(snippet)}';
}

String _short(String s) {
  final String one = s.replaceAll('\n', ' ');
  return one.length <= 120 ? one : '${one.substring(0, 117)}...';
}

/// Allowlist: a dash wrapped in a quote or paren on both sides (the documented
/// null-value glyph, e.g. ("—"), '—', "–").
final RegExp _quotedGlyph =
    RegExp('["\'(]\\s*[$_em$_en]\\s*["\')]');

/// Return the prose dashes in [text]: every em dash, plus every SPACE-flanked
/// en dash, after removing documented-glyph wrappers. Range en dashes and the
/// bare glyph are not returned.
List<int> _proseDashOffsets(String text) {
  // Blank out documented-glyph wrappers so they are not flagged, preserving
  // length/offsets by replacing with same-length spaces.
  final String scrubbed = text.replaceAllMapped(
    _quotedGlyph,
    (Match m) => ' ' * m.group(0)!.length,
  );
  final List<int> hits = <int>[];
  final List<int> units = scrubbed.codeUnits;
  for (int i = 0; i < units.length; i++) {
    final int c = units[i];
    if (c == _kEm) {
      hits.add(i);
    } else if (c == _kEn) {
      final bool spaceBefore = i > 0 && units[i - 1] == _kSpace;
      final bool spaceAfter = i + 1 < units.length && units[i + 1] == _kSpace;
      if (spaceBefore || spaceAfter) hits.add(i);
    }
  }
  return hits;
}

int _lineAt(String text, int offset) =>
    '\n'.allMatches(text.substring(0, offset)).length + 1;

// ---------------------------------------------------------------------------
// Dart string-literal tokenizer. Em/en dashes are not valid Dart identifier or
// operator characters, so after comments and delimiters are accounted for, any
// dash the tokenizer sees inside a string is user-facing copy.
// ---------------------------------------------------------------------------
const int _code = 0, _lineC = 1, _blockC = 2, _str = 3;

List<_Hit> _scanDart(String path, String src) {
  final List<_Hit> hits = <_Hit>[];
  int i = 0;
  final int n = src.length;
  int line = 1;
  int mode = _code;
  String delim = '';
  bool raw = false;
  int strLine = 1;
  final StringBuffer buf = StringBuffer();

  bool at(String t) => src.startsWith(t, i);

  while (i < n) {
    final String c = src[i];
    final String nx = i + 1 < n ? src[i + 1] : '';
    if (c == '\n') line++;
    switch (mode) {
      case _code:
        if (c == '/' && nx == '/') {
          mode = _lineC;
          i += 2;
          continue;
        }
        if (c == '/' && nx == '*') {
          mode = _blockC;
          i += 2;
          continue;
        }
        String? q;
        bool isRaw = false;
        for (final String pfx in const <String>['r', '']) {
          for (final String d in const <String>["'''", '"""', "'", '"']) {
            if (at(pfx + d)) {
              isRaw = pfx == 'r';
              q = d;
              break;
            }
          }
          if (q != null) break;
        }
        if (q != null) {
          raw = isRaw;
          delim = q;
          mode = _str;
          strLine = line;
          buf.clear();
          i += (isRaw ? 1 : 0) + q.length;
          continue;
        }
        i++;
        break;
      case _lineC:
        if (c == '\n') mode = _code;
        i++;
        break;
      case _blockC:
        if (c == '*' && nx == '/') {
          mode = _code;
          i += 2;
          continue;
        }
        i++;
        break;
      case _str:
        if (!raw && c == r'\') {
          buf.write(c);
          if (nx.isNotEmpty) {
            buf.write(nx);
            if (nx == '\n') line++;
          }
          i += 2;
          continue;
        }
        if (at(delim)) {
          final String content = buf.toString();
          final String trimmed = content.trim();
          if (trimmed != _em && trimmed != _en) {
            for (final int off in _proseDashOffsets(content)) {
              hits.add(_Hit(path, 'L$strLine', content));
              break; // one hit per literal is enough to fail + point
            }
            // still surface count via all offsets? one is sufficient
          }
          mode = _code;
          buf.clear();
          i += delim.length;
          continue;
        }
        buf.write(c);
        i++;
        break;
    }
  }
  return hits;
}

// ---------------------------------------------------------------------------
// JSON: walk every string value.
// ---------------------------------------------------------------------------
List<_Hit> _scanJson(String path, String src) {
  final List<_Hit> hits = <_Hit>[];
  final dynamic root = jsonDecode(src);
  void walk(dynamic node, String p) {
    if (node is String) {
      if (_proseDashOffsets(node).isNotEmpty) hits.add(_Hit(path, p, node));
    } else if (node is Map) {
      node.forEach((dynamic k, dynamic v) => walk(v, '$p/$k'));
    } else if (node is List) {
      for (int i = 0; i < node.length; i++) {
        walk(node[i], '$p[$i]');
      }
    }
  }

  walk(root, r'$');
  return hits;
}

// ---------------------------------------------------------------------------
// SVG: strip XML comments, scan the rendered markup.
// ---------------------------------------------------------------------------
final RegExp _xmlComment = RegExp(r'<!--.*?-->', dotAll: true);

List<_Hit> _scanSvg(String path, String src) {
  final String noComments = src.replaceAll(_xmlComment, '');
  return _proseDashOffsets(noComments)
      .map((int o) => _Hit(path, 'L${_lineAt(noComments, o)}', noComments))
      .take(1)
      .toList();
}

List<File> _files(String dir, bool Function(String) match) {
  final Directory d = Directory(dir);
  if (!d.existsSync()) return <File>[];
  return d
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => match(f.path))
      .toList();
}

String _rel(String root, String path) =>
    path.startsWith('$root/') ? path.substring(root.length + 1) : path;

void main() {
  // ---- The scanner must be able to FAIL (guard against a green no-op). ----
  group('voice guard self-test (proves the guard has teeth)', () {
    test('detects an em dash in a Dart string literal', () {
      final String planted = "final s = 'Term ${_em} gloss';";
      expect(_scanDart('x.dart', planted), isNotEmpty);
    });
    test('ignores an em dash in a Dart comment', () {
      final String comment = '// a comment ${_em} with a dash\nfinal s = 1;';
      expect(_scanDart('x.dart', comment), isEmpty);
    });
    test('allows the bare null-value glyph literal', () {
      final String glyph = "String ms() => '${_em}';";
      expect(_scanDart('x.dart', glyph), isEmpty);
    });
    test('allows a documented quoted glyph', () {
      expect(_proseDashOffsets('stays blank ("${_em}") until set'), isEmpty);
    });
    test('allows an en-dash numeric range but flags prose en dash', () {
      expect(_proseDashOffsets('bytes 0${_en}255'), isEmpty);
      expect(_proseDashOffsets('one thing ${_en} another'), isNotEmpty);
    });
  });

  // ---- The real gate. ----
  test('GL-004 P0: no em dash in shipped user-facing copy (app-wide)', () {
    final String root = _packageRoot();
    final List<_Hit> hits = <_Hit>[];

    for (final File f in _files('$root/lib', (String p) => p.endsWith('.dart'))) {
      hits.addAll(_scanDart(_rel(root, f.path), f.readAsStringSync()));
    }
    for (final File f
        in _files('$root/assets/guides', (String p) => p.endsWith('.md'))) {
      final String text = f.readAsStringSync();
      hits.addAll(_proseDashOffsets(text)
          .map((int o) => _Hit(_rel(root, f.path), 'L${_lineAt(text, o)}', text))
          .take(1));
    }
    for (final String sub in const <String>['assets/help', 'assets/data']) {
      for (final File f in _files('$root/$sub', (String p) => p.endsWith('.json'))) {
        hits.addAll(_scanJson(_rel(root, f.path), f.readAsStringSync()));
      }
    }
    for (final File f in _files('$root/assets', (String p) => p.endsWith('.svg'))) {
      String src;
      try {
        src = f.readAsStringSync();
      } on FileSystemException {
        continue; // a few icon SVGs are UTF-16/binary; skip undecodable
      }
      hits.addAll(_scanSvg(_rel(root, f.path), src));
    }

    expect(
      hits,
      isEmpty,
      reason: 'Em dash (or prose en dash) found in shipped user-facing copy. '
          'Per GL-004 the no-em-dash rule extends to app UI strings and bundled '
          'content. Restructure into two sentences, a colon, or a comma. '
          '(Code comments, the bare null glyph, documented quoted glyphs, and '
          'en-dash ranges are exempt and already excluded.)\n'
          '${hits.join('\n')}',
    );
  });
}

String _packageRoot() {
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
