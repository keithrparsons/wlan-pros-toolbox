// Every bundled SVG is UTF-8 with no byte-order mark (Keith, 2026-08-09).
//
// WHY THIS EXISTS, and it is the only defect this repo has ever carried that no
// other check could see. assets/regulator-logos/regulator-komdigi.svg shipped
// UTF-16-encoded with a BOM. flutter_svg hands the bytes to
// vector_graphics_compiler's XML parser, which throws
//
//   XmlParserException: name expected at 1:4
//
// on the real macOS embedder, so Indonesia's regulator logo rendered ZERO
// pixels and the screen fell back to its abbreviation badge. Measured
// 2026-08-09 via SvgPicture.asset on `flutter test -d macos`.
//
// It passed every static sweep this team owns. The GL-003 §11.7 CSS grep reads
// the file as text and finds nothing meaningful in UTF-16. The §11.8 geometry
// sweep finds no viewBox and reports SKIP. A browser opens it perfectly,
// because browsers honor the encoding declaration. Nothing in either clause
// looks at bytes, so a UTF-16 asset is invisible to all of it while rendering
// nothing on device.
//
// Keith chose a standalone assertion over folding this into the vendor-CSS
// flatten, and the reason is the scope: this assertion protects every bundled
// SVG, ours and third-party alike, while a flatten only protects what passes
// through it.
//
// THE FILE SET IS DERIVED FROM pubspec.yaml, NOT HARDCODED. A hardcoded
// directory list is a second copy of the asset manifest, and two copies of the
// same list are how the copies drift. `scripts/analyze.sh` already discovers
// its package list for exactly this reason and the CI config says so. Add a
// bundled asset directory tomorrow and it is covered here with nobody
// remembering to edit this file.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Asset entries declared under `flutter:` `assets:` in pubspec.yaml.
///
/// Flutter treats an entry ending in `/` as a directory of files and does NOT
/// recurse into its subdirectories; a subdirectory is bundled only by its own
/// entry. This walk mirrors that exactly, so "bundled" here means the same
/// thing it means to the build, and the test never asserts against a file that
/// does not ship.
List<File> _bundledSvgs() {
  final List<String> lines = File('pubspec.yaml').readAsLinesSync();

  // Find the `flutter:` top-level block, then the `assets:` key inside it.
  int i = lines.indexWhere((String l) => l.trimRight() == 'flutter:');
  expect(i, isNot(-1), reason: 'pubspec.yaml has no top-level `flutter:` block');

  final List<String> entries = <String>[];
  bool inAssets = false;
  for (i++; i < lines.length; i++) {
    final String line = lines[i];
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    // A non-indented line ends the `flutter:` block.
    if (!line.startsWith(' ')) break;
    final String trimmed = line.trim();
    if (trimmed == 'assets:') {
      inAssets = true;
      continue;
    }
    if (inAssets) {
      if (trimmed.startsWith('- ')) {
        entries.add(trimmed.substring(2).trim());
      } else if (!trimmed.startsWith('-')) {
        // Another key at the same level as `assets:` closes the list.
        inAssets = false;
      }
    }
  }
  expect(entries, isNotEmpty,
      reason: 'parsed no asset entries out of pubspec.yaml, so the parser broke '
          'and a test that inspects nothing cannot fail');

  final Set<String> paths = <String>{};
  for (final String e in entries) {
    if (e.endsWith('/')) {
      final Directory d = Directory(e);
      if (!d.existsSync()) continue;
      // listSync without recursion: Flutter's own directory-entry semantics.
      for (final FileSystemEntity f in d.listSync()) {
        if (f is File && f.path.endsWith('.svg')) paths.add(f.path);
      }
    } else if (e.endsWith('.svg') && File(e).existsSync()) {
      paths.add(e);
    }
  }
  return <File>[for (final String p in (paths.toList()..sort())) File(p)];
}

/// The BOMs that reach us in practice, and what each one does to the parser.
const Map<String, List<int>> _boms = <String, List<int>>{
  'UTF-8 BOM': <int>[0xEF, 0xBB, 0xBF],
  'UTF-16 LE BOM': <int>[0xFF, 0xFE],
  'UTF-16 BE BOM': <int>[0xFE, 0xFF],
};

String? _bomIn(Uint8List b) {
  for (final MapEntry<String, List<int>> e in _boms.entries) {
    if (b.length < e.value.length) continue;
    bool match = true;
    for (int i = 0; i < e.value.length; i++) {
      if (b[i] != e.value[i]) {
        match = false;
        break;
      }
    }
    if (match) return e.key;
  }
  return null;
}

void main() {
  group('every bundled SVG is UTF-8 with no BOM', () {
    test('no bundled SVG carries a byte-order mark', () {
      final List<String> offenders = <String>[];
      for (final File f in _bundledSvgs()) {
        final String? bom = _bomIn(f.readAsBytesSync());
        if (bom != null) {
          offenders.add('${f.path}: starts with a $bom');
        }
      }
      expect(offenders, isEmpty,
          reason: 'A BOM makes flutter_svg throw XmlParserException and the '
              'asset renders zero pixels on device, while passing every text '
              'sweep we own and opening perfectly in a browser. Transcode to '
              'UTF-8 without a BOM.\n${offenders.join('\n')}');
    });

    test('every bundled SVG decodes as strict UTF-8', () {
      final List<String> offenders = <String>[];
      for (final File f in _bundledSvgs()) {
        try {
          const Utf8Decoder(allowMalformed: false).convert(f.readAsBytesSync());
        } on FormatException catch (e) {
          offenders.add('${f.path}: not valid UTF-8 (${e.message})');
        }
      }
      expect(offenders, isEmpty,
          reason: 'The XML parser reads these bytes as UTF-8 whatever the '
              'encoding declaration says.\n${offenders.join('\n')}');
    });

    // Non-vacuity. If the pubspec walk silently stops resolving directories the
    // two assertions above pass over an empty list and the gate reports green
    // across the whole bundle.
    test('the pubspec walk resolves a non-trivial number of bundled SVGs', () {
      expect(_bundledSvgs().length, greaterThan(300),
          reason: 'The bundled-SVG walk found too few files to be reading the '
              'real asset manifest.');
    });
  });
}
