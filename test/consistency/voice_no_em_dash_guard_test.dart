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
//      XML character ENTITIES for the em/en dash are decoded, because the SVG
//      renderer decodes them and the user reads the glyph; UTF-16 files are
//      decoded, and an undecodable asset FAILS the gate rather than being
//      silently skipped).
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
// The glyphs are built from code points so THIS file's STRING LITERALS stay
// dash-free and can never false-positive against the guard's own text.
//
// To be precise about what that does and does not claim: this file's COMMENTS
// do contain em and en dashes (prose written for the next engineer), and that
// is fine on two independent grounds. First, the Dart tokenizer below strips
// comments before scanning, so comment prose is invisible to the scan. Second,
// `test/` is never a scan root at all - the gate walks lib/ and assets/ only.
// The earlier wording here claimed the whole FILE was em-dash-free, which was
// simply untrue and invited a reader to "verify" it with a grep that fails.
// The honest and load-bearing claim is the one about string literals.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const int _kEm = 0x2014; // em dash
const int _kEn = 0x2013; // en dash
const int _kSpace = 0x20;
final String _em = String.fromCharCode(_kEm);
final String _en = String.fromCharCode(_kEn);

/// A backslash, and the TEXT of a Dart unicode escape (not the character it
/// denotes). Built from code points for the same reason the glyphs above are:
/// a test that means to plant the SPELLING must never accidentally contain the
/// real dash, or it passes for a reason unrelated to what it claims to prove.
final String _bs = String.fromCharCode(0x5C);
String _uEsc(int cp) => '${_bs}u${cp.toRadixString(16).padLeft(4, '0')}';

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
/// A decoded Dart `\u` escape: the character it produces, and how many source
/// characters it occupied.
class _UnicodeEscape {
  const _UnicodeEscape(this.rune, this.consumed);
  final int rune;
  final int consumed;
}

/// Parse a Dart unicode escape starting at [i] (which must point at the `\`).
/// Returns null if this is not a well-formed `\u` escape, in which case the
/// caller falls back to copying the escape pair verbatim.
_UnicodeEscape? _readUnicodeEscape(String src, int i) {
  if (i + 1 >= src.length || src[i + 1] != 'u') return null;
  final int n = src.length;

  // Braced form: \u{1F600} - 1..6 hex digits.
  if (i + 2 < n && src[i + 2] == '{') {
    final int close = src.indexOf('}', i + 3);
    if (close < 0 || close == i + 3 || close - (i + 3) > 6) return null;
    final int? v = _strictHex(src.substring(i + 3, close));
    if (v == null || v > 0x10FFFF) return null;
    return _UnicodeEscape(v, close - i + 1);
  }

  // Fixed form: backslash-u followed by EXACTLY four hex digits.
  if (i + 6 > n) return null;
  final int? v = _strictHex(src.substring(i + 2, i + 6));
  if (v == null) return null;
  return _UnicodeEscape(v, 6);
}

/// Parse [s] as hex, rejecting anything int.tryParse would tolerate but Dart's
/// escape grammar does not. int.tryParse TRIMS WHITESPACE and accepts a leading
/// sign, so it would happily read '+20' or ' 14' as a valid escape body and let
/// the tokenizer consume characters that are not part of any escape. Every
/// character must be a hex digit and nothing else.
int? _strictHex(String s) {
  if (s.isEmpty) return null;
  for (final int u in s.codeUnits) {
    final bool isHex = (u >= 0x30 && u <= 0x39) || // 0-9
        (u >= 0x41 && u <= 0x46) || // A-F
        (u >= 0x61 && u <= 0x66); // a-f
    if (!isHex) return null;
  }
  return int.parse(s, radix: 16);
}

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
        // A `\u` escape is decoded to the character the COMPILER will produce,
        // so a dash spelled as a backslash-u escape is caught. The guard must
        // see what SHIPS, not what the source happens to spell. Both Dart forms
        // are handled: the fixed four-hex-digit form and the braced form.
        //
        // Doing this HERE rather than with a regex over the finished buffer is
        // what keeps it honest: the tokenizer already consumes escape pairs
        // left to right, so an escaped backslash ('\\u2014' - a literal
        // backslash followed by the text u2014, which the compiler does NOT
        // turn into a dash) is consumed as a pair and can never be misread as
        // the start of an escape. A post-hoc regex would flag it wrongly.
        final _UnicodeEscape? decoded = _readUnicodeEscape(src, i);
        if (decoded != null) {
          f.buf.writeCharCode(decoded.rune);
          i += decoded.consumed;
          continue;
        }
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
// SVG: strip XML comments, decode dash entities, scan the rendered markup.
// ---------------------------------------------------------------------------
final RegExp _xmlComment = RegExp(r'<!--.*?-->', dotAll: true);

/// XML character-entity forms of the em and en dash: decimal (`&#8212;`), hex
/// (`&#x2014;`, any case, optional leading zeros), and named (`&mdash;`).
///
/// WHY THIS EXISTS (the bug this guard shipped with). SVG is XML, so the
/// renderer decodes these before drawing. Scanning the UNDECODED markup meant
/// an entity-encoded em dash rendered as prose on the user's screen while the
/// guard reported green - a gate that certified the exact thing it exists to
/// stop. Twelve bundled graphics carried 26 such dashes past it.
final RegExp _emEntity = RegExp(r'&(?:#0*8212|#[xX]0*2014|mdash);');
final RegExp _enEntity = RegExp(r'&(?:#0*8211|#[xX]0*2013|ndash);');

/// Replace each dash entity with the single character it renders as.
///
/// Two deliberate choices, both load-bearing - do not "optimize" either:
///
/// 1. COMPACT, NOT PADDED. Padding each entity out to its original width to
///    preserve byte offsets would insert a SPACE next to the glyph, which
///    would turn a legitimate numeric range (`100&#8211;130 V`) into a
///    space-flanked prose en dash and make the guard flag correct typography.
///    The range exemption in _proseDashOffsets only survives a compact decode.
/// 2. DASH ENTITIES ONLY. A general XML-entity decoder would also expand
///    `&#10;` into a real newline and shift every line number after it. Dashes
///    contain no newlines, so decoding only these keeps a decoded offset
///    mapping to the true SOURCE line.
///
/// Double-encoded text (`&amp;#8212;`, which renders as the literal characters
/// "&#8212;" and not a dash) is correctly left alone: the `&` is consumed by
/// `&amp;`, so no pattern above can match the remainder.
String _decodeDashEntities(String s) =>
    s.replaceAll(_emEntity, _em).replaceAll(_enEntity, _en);

/// Remove XML comments while PRESERVING the line structure around them.
///
/// Each comment collapses to the newlines it contained, so every line after a
/// multi-line comment keeps its true source line number. Deleting comments
/// outright (the original behaviour) silently shifted every later line: the
/// gate reported iec-60309.svg:L34 for a dash that actually lives on L40, and
/// a reported line that does not exist in the file sends the reader hunting.
String _stripXmlComments(String src) => src.replaceAllMapped(
      _xmlComment,
      (Match m) => '\n' * '\n'.allMatches(m.group(0)!).length,
    );

List<_Hit> _scanSvg(String path, String src) {
  final String text = _decodeDashEntities(_stripXmlComments(src));
  return _proseDashOffsets(text)
      .map((int o) => _Hit(path, 'L${_lineAt(text, o)}', _around(text, o)))
      .take(1)
      .toList();
}

/// A readable window around [offset], for the failure message. The SVG scanner
/// used to hand the ENTIRE file to _Hit as its snippet, so a failing gate
/// printed twelve complete XML documents and buried the finding it had just
/// made. Report the offending text, not the document that contains it.
String _around(String text, int offset) {
  final int start = (offset - 60).clamp(0, text.length);
  final int end = (offset + 60).clamp(0, text.length);
  return text.substring(start, end).trim();
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
    // ---- SVG entity decoding (the 2026-07-20 blind spot). ----
    // The renderer decodes XML entities; the guard used to scan the raw
    // markup, so these all shipped green. Each form is planted and must fire.
    test('detects an em dash written as a DECIMAL entity in an SVG', () {
      expect(_scanSvg('g.svg', '<text>Yellow &#8212; 100 V</text>'), isNotEmpty);
    });
    test('detects an em dash written as a HEX entity in an SVG', () {
      expect(_scanSvg('g.svg', '<text>Yellow &#x2014; 100 V</text>'), isNotEmpty);
      expect(_scanSvg('g.svg', '<text>Yellow &#X2014; 100 V</text>'), isNotEmpty);
      // Leading zeros are legal XML and must not be an escape hatch.
      expect(_scanSvg('g.svg', '<text>Yellow &#x02014; 100 V</text>'), isNotEmpty);
      expect(_scanSvg('g.svg', '<text>Yellow &#08212; 100 V</text>'), isNotEmpty);
    });
    test('detects an em dash written as a NAMED entity in an SVG', () {
      expect(_scanSvg('g.svg', '<text>Yellow &mdash; 100 V</text>'), isNotEmpty);
    });
    test('detects a PROSE en dash written as an entity in an SVG', () {
      expect(_scanSvg('g.svg', '<text>one thing &#8211; another</text>'), isNotEmpty);
      expect(_scanSvg('g.svg', '<text>one thing &ndash; another</text>'), isNotEmpty);
      expect(_scanSvg('g.svg', '<text>one thing &#x2013; another</text>'), isNotEmpty);
    });

    // ---- The negative that matters most. ----
    // A tight en dash between two numbers is CORRECT typography. If decoding
    // ever pads entities to preserve offsets, a space lands beside the glyph
    // and this test goes red - which is the whole point of having it.
    test('does NOT flag an entity-encoded en dash inside a numeric range', () {
      expect(_scanSvg('g.svg', '<text>100&#8211;130 V</text>'), isEmpty);
      expect(_scanSvg('g.svg', '<text>bytes 0&#x2013;255</text>'), isEmpty);
      expect(_scanSvg('g.svg', '<text>A&ndash;Z</text>'), isEmpty);
    });
    test('reports the real SOURCE line after decoding shortens the text', () {
      // Three entities on line 1 shrink it by 18 characters. The dash on line 3
      // must still report L3, not a line shifted by the decode.
      const String svg = '<text>0&#8211;9 A&#8211;Z 1&#8211;5</text>\n'
          '<text>plain</text>\n'
          '<text>alpha &#8212; beta</text>';
      expect(_scanSvg('g.svg', svg).single.where, 'L3');
    });
    test('does not decode a DOUBLE-encoded entity (renders as literal text)', () {
      // &amp;#8212; draws the characters "&#8212;" on screen, not a dash.
      expect(_scanSvg('g.svg', '<text>type &amp;#8212; to get one</text>'), isEmpty);
    });
    test('still ignores a dash inside an XML comment', () {
      expect(_scanSvg('g.svg', '<!-- note &#8212; internal --><text>ok</text>'), isEmpty);
    });
    test('a MULTI-LINE comment does not shift the reported line number', () {
      const String svg = '<svg>\n'
          '<!-- a licence header\n'
          '     spanning three\n'
          '     whole lines -->\n'
          '<text>alpha &#8212; beta</text>';
      // The dash is on source line 5 and must be reported as such.
      expect(_scanSvg('g.svg', svg).single.where, 'L5');
    });

    // ---- Dart \u escape bypass (latent; zero live instances). ----
    //
    // These payloads are built with _uEsc, never typed as a literal. The first
    // draft of this block was typed by hand and silently acquired REAL dashes
    // where the escape SPELLING was the thing under test - which made the
    // detection cases pass for the wrong reason and inverted the raw-string
    // case entirely. Building the escape from code points makes that class of
    // mistake unrepresentable. Do not "simplify" these back into literals.
    test('detects an em dash spelled as a Dart unicode escape', () {
      expect(_scanDart('x.dart', "final s = 'Term ${_uEsc(_kEm)} gloss';"),
          isNotEmpty);
      expect(_scanDart('x.dart', "final s = 'Term ${_bs}u{2014} gloss';"),
          isNotEmpty);
    });
    test('a unicode escape in a RAW string is literal text, not a dash', () {
      // In a raw string the backslash is data; the compiler produces no dash,
      // so the guard must stay quiet.
      expect(_scanDart('x.dart', "final s = r'Term ${_uEsc(_kEm)} gloss';"),
          isEmpty);
    });
    test('an ESCAPED backslash before u2014 is not a unicode escape', () {
      // Compiles to a literal backslash followed by the text u2014. No dash.
      expect(_scanDart('x.dart', "final s = 'path $_bs${_bs}u2014 end';"),
          isEmpty);
    });
    // _readUnicodeEscape is pinned DIRECTLY here. Its strictness has no
    // dash-visible effect through _scanDart (a malformed escape produces no
    // dash either way), so an outcome-level test for it would be a test that
    // cannot fail. Testing the parser as a unit is the honest alternative.
    test('the escape parser accepts only well-formed escapes', () {
      final String em4 = _uEsc(_kEm); // backslash-u-2-0-1-4
      expect(_readUnicodeEscape(em4, 0)!.rune, _kEm);
      expect(_readUnicodeEscape(em4, 0)!.consumed, 6);
      expect(_readUnicodeEscape('${_bs}u{2014}', 0)!.rune, _kEm);
      // int.tryParse would tolerate all of these; the escape grammar does not.
      expect(_readUnicodeEscape('${_bs}u 014', 0), isNull);
      expect(_readUnicodeEscape('${_bs}u+014', 0), isNull);
      expect(_readUnicodeEscape('${_bs}u201', 0), isNull); // too short
      expect(_readUnicodeEscape('${_bs}n', 0), isNull); // not a u escape
      expect(_readUnicodeEscape('${_bs}u{}', 0), isNull); // empty braces
    });
    test('a Dart-escaped en dash in a numeric range is still not flagged', () {
      expect(_scanDart('x.dart', "final s = 'bytes 0${_uEsc(_kEn)}255';"),
          isEmpty);
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
