// Guards the GL-003 §8.6.1 rule: concept-graphic <text> elements must contain
// ASCII only; symbols (arrows, Greek letters, and any glyph a bundled font may
// not carry) are drawn as vector <path>, never as <text>. flutter_svg does not
// reliably resolve the bundled font for <text> on the web/headless render path,
// so a non-ASCII glyph drops to a missing-glyph "tofu box" there even when the
// font nominally contains it. Precedent: the FSPL "loss ↑" up-arrow tofu'd on
// the web build (caught 2026-06-17 in a Play Store screenshot).
//
// This test has two halves:
//   1. STRUCTURAL: across every tool-graphic SVG, no arrow / Greek letter /
//      known-missing symbol glyph may appear inside a <text> element. This is
//      the regression guard for the glyph-tofu sweep.
//   2. RENDER: every graphic touched by the sweep parses and renders in
//      flutter_svg (SvgPicture.string — the same parser the app uses) with no
//      parse exception.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

// Glyphs that MUST be vector <path>, never <text>, per GL-003 §8.6.1.
// Arrows (any bundled mono font lacks them), Greek letters (DM Mono lacks all
// Greek), and the specific symbols no bundled font carries (U+21D2 ⇒, U+22A5 ⊥)
// plus the superscript digits DM Mono lacks (U+2070 ⁰, U+2076 ⁶, U+2079 ⁹).
const Set<int> _forbiddenInText = <int>{
  0x2190, 0x2191, 0x2192, 0x2193, 0x2194, // ← ↑ → ↓ ↔
  0x21D0, 0x21D1, 0x21D2, 0x21D3, // ⇐ ⇑ ⇒ ⇓
  0x21D4, // ⇔
  0x0391, 0x0392, 0x0393, 0x0394, 0x0395, 0x0396, 0x0397, 0x0398, // Α..Θ
  0x0399, 0x039A, 0x039B, 0x039C, 0x039D, 0x039E, 0x039F, 0x03A0, // Ι..Π
  0x03A1, 0x03A3, 0x03A4, 0x03A5, 0x03A6, 0x03A7, 0x03A8, 0x03A9, // Ρ..Ω
  0x03B1, 0x03B2, 0x03B3, 0x03B4, 0x03B5, 0x03B6, 0x03B7, 0x03B8, // α..θ
  0x03B9, 0x03BA, 0x03BB, 0x03BC, 0x03BD, 0x03BE, 0x03BF, 0x03C0, // ι..π
  0x03C1, 0x03C3, 0x03C4, 0x03C5, 0x03C6, 0x03C7, 0x03C8, 0x03C9, // ρ..ω
  0x22A5, // ⊥
  0x2070, 0x2076, 0x2079, // ⁰ ⁶ ⁹ (missing from DM Mono)
};

final RegExp _textEl = RegExp(r'<text\b[^>]*>(.*?)</text>', dotAll: true);
final RegExp _tag = RegExp(r'<[^>]+>');
final RegExp _numEntity = RegExp(r'&#(\d+);');
final RegExp _hexEntity = RegExp(r'&#x([0-9a-fA-F]+);');

String _decode(String inner) {
  String s = inner.replaceAll(_tag, '');
  s = s.replaceAllMapped(
      _numEntity, (Match m) => String.fromCharCode(int.parse(m.group(1)!)));
  s = s.replaceAllMapped(_hexEntity,
      (Match m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
  return s;
}

List<File> _graphics() {
  final Directory dir = Directory('assets/tool-graphics');
  return dir
      .listSync()
      .whereType<File>()
      .where((File f) => f.path.endsWith('.svg'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
}

void main() {
  group('GL-003 §8.6.1 — no symbol glyph in concept-graphic <text>', () {
    test('no arrow / Greek / missing-glyph symbol appears inside any <text>',
        () {
      final List<String> offenders = <String>[];
      for (final File f in _graphics()) {
        final String svg = f.readAsStringSync();
        for (final Match m in _textEl.allMatches(svg)) {
          final String decoded = _decode(m.group(1)!);
          for (final int cp in decoded.runes) {
            if (_forbiddenInText.contains(cp)) {
              offenders.add(
                  '${f.path}: U+${cp.toRadixString(16).toUpperCase().padLeft(4, '0')} '
                  'in <text>${decoded.trim()}</text>');
            }
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'These symbol glyphs must be vector <path>, not <text> '
              '(GL-003 §8.6.1):\n${offenders.join('\n')}');
    });
  });

  group('glyph-tofu sweep graphics render in flutter_svg', () {
    for (final File f in _graphics()) {
      testWidgets(f.path, (WidgetTester tester) async {
        final String svg = f.readAsStringSync();
        Object? caught;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SvgPicture.string(
                  svg,
                  width: 320,
                  height: 160,
                  errorBuilder: (BuildContext c, Object e, StackTrace? s) {
                    caught = e;
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle(const Duration(seconds: 1));
        expect(caught, isNull,
            reason: 'flutter_svg failed to parse ${f.path}: $caught');
        expect(find.byType(SvgPicture), findsOneWidget, reason: f.path);
      });
    }
  });
}
