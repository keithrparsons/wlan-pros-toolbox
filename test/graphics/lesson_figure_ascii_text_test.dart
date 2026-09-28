// Guided Lesson figures: every SVG <text> is ASCII only.
//
// GL-003 §8.6.1: flutter_svg does not reliably resolve the bundled font for
// <text> on the web render path, so a non-ASCII glyph (an ellipsis, a
// chevron, a degree sign) draws as a missing-glyph box there, even when the
// font has it. Such glyphs are drawn as <path> geometry instead.
//
// The Starlink screen test already checks its own folder. This one covers
// every folder the four redrawn Guided Lessons ship, so a lesson that lacks
// its own guard (Find My shipped "7F3A…" and "Items › your tag › paste" as
// <text>) is caught here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const List<String> _lessonFolders = <String>[
  'assets/tool-diagrams/starlink',
  'assets/tool-diagrams/home-internet',
  'assets/tool-diagrams/wifi-calling',
  'assets/tool-diagrams/find-my',
];

void main() {
  for (final String folder in _lessonFolders) {
    final List<File> svgs =
        Directory(folder)
            .listSync()
            .whereType<File>()
            .where((File f) => f.path.endsWith('.svg'))
            .toList()
          ..sort((File a, File b) => a.path.compareTo(b.path));

    test('$folder ships figures', () {
      expect(svgs, isNotEmpty, reason: folder);
    });

    for (final File f in svgs) {
      test('${f.path} has ASCII-only <text>', () {
        final String svg = f.readAsStringSync();
        for (final Match m in RegExp(
          r'<text[^>]*>([^<]*)</text>',
        ).allMatches(svg)) {
          final String t = m.group(1)!;
          expect(
            t.runes.every((int r) => r < 128),
            isTrue,
            reason: '${f.path} text "$t" is not ASCII',
          );
        }
      });
    }
  }
}
