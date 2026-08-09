// GL-003 §11.7: a bundled SVG carries its styling inline, never in CSS.
//
// flutter_svg ignores <style> blocks and class selectors outright, and says so
// itself while rendering: `unhandled element <style/>`. A graphic authored as
// `<style>.a{fill:#CA992C}</style>` plus `class="a"` therefore renders
// correctly in a browser and BROKEN on the device, because every classed fill
// falls back to the SVG default, which is black.
//
// A PASSING BROWSER RENDER IS NOT EVIDENCE AGAINST THIS FINDING. Chrome applies
// the CSS the app's renderer drops, so the headless-Chrome render that §8.6.1
// requires for stroke fidelity is silent here and returns a clean pass over a
// broken asset. That is the entire reason this clause is a grep and not a
// review. Measured on the real macOS embedder 2026-08-09: the FCC seal rendered
// as a featureless black disc at 78.2% black on its #2A2A2A chip.
//
// SCOPE WIDENED BEYOND §11.7's WORDING, and deliberately. The clause as written
// binds SVGs "we author" and carves out third-party vendor marks as not ours to
// re-author. Keith closed that carve-out on 2026-08-09: we ship a flattened copy
// and keep the pristine original alongside, unbundled, in assets/vendor-src/.
// With the originals preserved, nothing in the BUNDLE needs the exemption any
// more, so this guard binds every bundled SVG. That is what makes it able to
// stop the twelfth vendor mark arriving broken, which a guard scoped to our own
// directories could never do.
//
// THE REMEDY IS ONE COMMAND, not a hand edit:
//     tool/flatten_vendor_svg_css.py <the failing file>
// It refuses anything outside the one CSS shape it is willing to rewrite rather
// than guessing, so a refusal is a real answer and not a bug.
//
// WHAT THIS GUARD DOES NOT CHECK, stated so nobody reads it as wider than it
// is. It does not verify that the bundled file is byte-for-byte what the tool
// produces from its preserved original. That is the reproducibility half and it
// lives in `tool/flatten_vendor_svg_css.py --check`, run by a human. A Dart
// reimplementation of the flatten would be a second copy of the transform, and
// two copies of the same logic is how the copies drift.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Bundled SVGs, resolved from pubspec.yaml exactly as the encoding guard does.
///
/// Flutter treats an entry ending in `/` as a directory of files and does NOT
/// recurse, so a subdirectory ships only under its own entry. This mirrors that,
/// which is what makes "bundled" mean the same thing here as it means to the
/// build. `assets/vendor-src/` is absent from pubspec by design and is therefore
/// absent from this list, which is the point: the originals keep their CSS.
List<File> _bundledSvgs() {
  final List<String> lines = File('pubspec.yaml').readAsLinesSync();
  int i = lines.indexWhere((String l) => l.trimRight() == 'flutter:');
  expect(i, isNot(-1), reason: 'pubspec.yaml has no top-level `flutter:` block');

  final List<String> entries = <String>[];
  bool inAssets = false;
  for (i++; i < lines.length; i++) {
    final String line = lines[i];
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
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
      for (final FileSystemEntity f in d.listSync()) {
        if (f is File && f.path.endsWith('.svg')) paths.add(f.path);
      }
    } else if (e.endsWith('.svg') && File(e).existsSync()) {
      paths.add(e);
    }
  }
  return <File>[for (final String p in (paths.toList()..sort())) File(p)];
}

const String _vendorSrc = 'assets/vendor-src';

List<File> _preservedOriginals() {
  final Directory d = Directory(_vendorSrc);
  if (!d.existsSync()) return <File>[];
  return d
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.svg'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
}

void main() {
  group('GL-003 §11.7: bundled SVGs carry styling inline, never in CSS', () {
    test('no bundled SVG carries a class attribute or a <style> block', () {
      final List<String> offenders = <String>[];
      for (final File f in _bundledSvgs()) {
        final String s = f.readAsStringSync();
        final int classes = RegExp(r'\sclass="').allMatches(s).length;
        final int styles = RegExp(r'<style\b').allMatches(s).length;
        if (classes > 0 || styles > 0) {
          offenders.add('${f.path}: $classes class attributes, '
              '$styles <style> blocks');
        }
      }
      expect(offenders, isEmpty,
          reason: 'flutter_svg drops CSS, so these render broken on device and '
              'clean in a browser. Preserve the original under '
              '$_vendorSrc/ and run tool/flatten_vendor_svg_css.py on the '
              'bundled copy.\n${offenders.join('\n')}');
    });

    // Keith's provenance ruling, made mechanical: we ship a modified copy only
    // where the pristine original is kept. An original with no bundled
    // counterpart means a mark was renamed or dropped and its preserved source
    // was orphaned, which is how a preserved original quietly stops describing
    // anything.
    test('every preserved original has a bundled counterpart', () {
      final Set<String> bundled =
          _bundledSvgs().map((File f) => f.path).toSet();
      final List<String> orphans = <String>[
        for (final File f in _preservedOriginals())
          if (!bundled.contains('assets/${f.path.substring(_vendorSrc.length + 1)}'))
            '${f.path}: no bundled counterpart at '
                'assets/${f.path.substring(_vendorSrc.length + 1)}',
      ];
      expect(orphans, isEmpty, reason: orphans.join('\n'));
    });

    // The originals still carry the CSS that makes them unrenderable, so
    // bundling them would ship the exact defect the flatten removed, twice over.
    test('the preserved originals are NOT bundled', () {
      final Set<String> bundled =
          _bundledSvgs().map((File f) => f.path).toSet();
      final List<String> shipped = <String>[
        for (final File f in _preservedOriginals())
          if (bundled.contains(f.path)) f.path,
      ];
      expect(shipped, isEmpty,
          reason: '$_vendorSrc must stay out of the pubspec assets block. '
              'These originals still carry the CSS the flatten removed:\n'
              '${shipped.join('\n')}');
    });

    test('the sweep resolves a non-trivial number of bundled SVGs', () {
      expect(_bundledSvgs().length, greaterThan(300),
          reason: 'The bundled-SVG walk found too few files to be reading the '
              'real asset manifest, and a test that inspects nothing cannot '
              'fail.');
    });
  });
}
