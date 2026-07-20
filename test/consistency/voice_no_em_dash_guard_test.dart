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
//   1. lib/**/*.dart  -> STRING LITERALS only, INCLUDING nested string literals
//      inside ${...} interpolation. A stack-based tokenizer strips line/block/
//      doc comments and recurses through interpolation, so the ~4,000 em dashes
//      that legitimately live in code COMMENTS are never flagged, while a dash
//      hiding in `'a ${cond ? 'x — y' : 'z'}'` IS caught.
//   2. assets/guides/*.md            -> all prose.
//   3. assets/**/*.json              -> every JSON string VALUE (all bundled
//      data, not a hardcoded subset).
//   4. assets/**/*.svg               -> rendered markup (XML comments stripped;
//      UTF-16 files are decoded, and an undecodable asset FAILS the gate rather
//      than being silently skipped).
//
// EXEMPT (data, not prose):
//   - The null-value glyph literal: a string whose ENTIRE content is '—' (or
//     '–'), exactly. It means "not applicable"; changing it changes MEANING.
//     The match is exact, so a ' — ' separator ('space em space') is NOT exempt.
//   - The DOCUMENTED glyph: a dash wrapped in quotes or parens, e.g. ("—"),
//     used by help copy to describe the blank marker on its own screen.
//   - En-dash RANGES (0–128, A–Z, 128–255): a tight en dash between two
//     non-spaces. Only a SPACE-flanked en dash (prose punctuation) is flagged.
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
final RegExp _quotedGlyph = RegExp('["\'(]\\s*[$_em$_en]\\s*["\')]');

/// Return the prose-dash offsets in [text]: every em dash, plus every
/// SPACE-flanked en dash, after removing documented-glyph wrappers. Range en
/// dashes and the bare glyph are not returned.
List<int> _proseDashOffsets(String text) {
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
// Dart tokenizer (stack-based). Em/en dashes are not valid Dart identifier or
// operator characters, so any dash the tokenizer sees inside a STRING literal is
// user-facing copy. Interpolation `${...}` is entered as CODE, so nested string
// literals inside it are scanned exactly like top-level ones.
// ---------------------------------------------------------------------------
class _Frame {
  _Frame.code({required this.interp}) : isString = false;
  _Frame.string({required this.delim, required this.raw, required this.startLine})
      : isString = true,
        interp = false;

  final bool isString;
  // string:
  String delim = '';
  bool raw = false;
  int startLine = 0;
  final StringBuffer buf = StringBuffer();
  // interpolation code frame:
  final bool interp;
  int braceDepth = 1; // the '{' of the enclosing '${'
}

void _emit(String path, String content, int line, List<_Hit> hits) {
  if (content == _em || content == _en) return; // exact bare null glyph
  if (_proseDashOffsets(content).isNotEmpty) hits.add(_Hit(path, 'L$line', content));
}

List<_Hit> _scanDart(String path, String src) {
  final List<_Hit> hits = <_Hit>[];
  final List<_Frame> stack = <_Frame>[_Frame.code(interp: false)];
  int i = 0;
  final int n = src.length;
  int line = 1;

  void countNewlines(int from, int to) {
    for (int k = from; k < to && k < n; k++) {
      if (src.codeUnitAt(k) == 0x0A) line++;
    }
  }

  while (i < n) {
    final _Frame f = stack.last;
    final String c = src[i];
    final String nx = i + 1 < n ? src[i + 1] : '';

    if (f.isString) {
      if (c == '\n') {
        line++;
        f.buf.write(c);
        i++;
        continue;
      }
      if (!f.raw && c == r'\') {
        f.buf.write(c);
        if (nx.isNotEmpty) {
          f.buf.write(nx);
          if (nx == '\n') line++;
        }
        i += 2;
        continue;
      }
      if (!f.raw && c == r'$' && nx == '{') {
        stack.add(_Frame.code(interp: true)); // braceDepth starts at 1
        i += 2;
        continue;
      }
      if (src.startsWith(f.delim, i)) {
        _emit(path, f.buf.toString(), f.startLine, hits);
        stack.removeLast();
        i += f.delim.length;
        continue;
      }
      f.buf.write(c);
      i++;
      continue;
    }

    // CODE frame (top-level or interpolation body).
    if (c == '\n') {
      line++;
      i++;
      continue;
    }
    if (c == '/' && nx == '/') {
      int j = src.indexOf('\n', i);
      if (j < 0) j = n;
      i = j;
      continue;
    }
    if (c == '/' && nx == '*') {
      int j = src.indexOf('*/', i + 2);
      j = j < 0 ? n : j + 2;
      countNewlines(i, j);
      i = j;
      continue;
    }
    String? delim;
    bool raw = false;
    for (final String pfx in const <String>['r', '']) {
      for (final String d in const <String>["'''", '"""', "'", '"']) {
        if (src.startsWith(pfx + d, i)) {
          raw = pfx == 'r';
          delim = d;
          break;
        }
      }
      if (delim != null) break;
    }
    if (delim != null) {
      stack.add(_Frame.string(delim: delim, raw: raw, startLine: line));
      i += (raw ? 1 : 0) + delim.length;
      continue;
    }
    if (f.interp) {
      if (c == '{') {
        f.braceDepth++;
        i++;
        continue;
      }
      if (c == '}') {
        f.braceDepth--;
        if (f.braceDepth == 0) stack.removeLast(); // back to enclosing string
        i++;
        continue;
      }
    }
    i++;
  }
  return hits;
}

// ---------------------------------------------------------------------------
// Bundled-text readers: UTF-8, or UTF-16 by BOM. Null = undecodable.
// ---------------------------------------------------------------------------
String _decodeUtf16(List<int> bytes) {
  int start = 0;
  bool little = true;
  if (bytes.length >= 2) {
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
      little = true;
      start = 2;
    } else if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
      little = false;
      start = 2;
    }
  }
  final List<int> units = <int>[];
  for (int k = start; k + 1 < bytes.length; k += 2) {
    units.add(little ? bytes[k] | (bytes[k + 1] << 8) : (bytes[k] << 8) | bytes[k + 1]);
  }
  return String.fromCharCodes(units); // BMP glyphs (em/en) decode 1:1
}

String? _readText(File f) {
  final List<int> bytes = f.readAsBytesSync();
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xFF && bytes[1] == 0xFE) ||
          (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
    return _decodeUtf16(bytes);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    try {
      return _decodeUtf16(bytes);
    } catch (_) {
      return null;
    }
  }
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
      expect(_scanDart('x.dart', "final s = 'Term $_em gloss';"), isNotEmpty);
    });
    test('detects an em dash in a NESTED string inside interpolation', () {
      // Builds: final s = 'status: ${x ? 'on — off' : 'idle'}';
      // One literal, no concatenation. The \$ escape keeps the planted
      // "${x ? ...}" as literal payload text (it is the code being SCANNED,
      // not code to run), while $_em interpolates the em dash so this source
      // file never contains the glyph it hunts for. Verified byte-identical to
      // the previous concatenated form.
      final String planted = "final s = 'status: \${x ? 'on $_em off' : 'idle'}';";
      expect(_scanDart('x.dart', planted), isNotEmpty);
    });
    test('ignores an em dash in a Dart comment', () {
      expect(_scanDart('x.dart', '// a comment $_em dash\nfinal s = 1;'), isEmpty);
    });
    test('allows the bare null glyph, but flags a spaced separator', () {
      expect(_scanDart('x.dart', "String ms() => '$_em';"), isEmpty);
      // ' — ' (space em space) is a separator, NOT the null glyph.
      expect(_scanDart('x.dart', "final s = parts.join(' $_em ');"), isNotEmpty);
    });
    test('allows a documented quoted glyph', () {
      expect(_proseDashOffsets('stays blank ("$_em") until set'), isEmpty);
    });
    test('allows an en-dash numeric range but flags a prose en dash', () {
      // Braces are REQUIRED here: '0$_en255' would parse as the identifier
      // `_en255`, not `_en` followed by "255". Do not "simplify" this one.
      expect(_proseDashOffsets('bytes 0${_en}255'), isEmpty);
      expect(_proseDashOffsets('one thing $_en another'), isNotEmpty);
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
    for (final File f in _files('$root/assets', (String p) => p.endsWith('.json'))) {
      hits.addAll(_scanJson(_rel(root, f.path), f.readAsStringSync()));
    }
    for (final File f in _files('$root/assets', (String p) => p.endsWith('.svg'))) {
      final String? src = _readText(f);
      if (src == null) {
        // Fail loud: a P0 gate must never silently skip an asset it cannot read.
        hits.add(_Hit(_rel(root, f.path), 'file',
            'UNDECODABLE asset (not UTF-8 or UTF-16) - the guard cannot verify it'));
        continue;
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
