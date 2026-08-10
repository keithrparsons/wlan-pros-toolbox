// Guards the bundled SVGs against a font-family that flutter_svg cannot resolve.
//
// THE DEFECT THIS EXISTS TO STOP (found 2026-08-09):
// `font-family` in an SVG is a CSS font STACK — an ordered fallback list. The
// flutter_svg pipeline does not treat it as one. The compiler stores the raw
// attribute string verbatim (`vector_graphics_compiler-1.2.5`,
// `lib/src/svg/parser.dart:1657`) and the runtime hands that whole string to
// `ui.TextStyle(fontFamily: ...)` with `fontFamilyFallback` left null
// (`vector_graphics-1.2.2`, `lib/src/listener.dart:740-749`). Flutter's
// `fontFamily` is ONE family name, so `"DM Mono, monospace"` is looked up as a
// family literally called `DM Mono, monospace`, matches nothing, and silently
// falls back to the platform face — Roboto on Android, San Francisco on
// iOS/macOS. The graphic still draws, which is what made this survive review:
// nothing throws, nothing is blank, the type is simply not ours.
//
// The check is run through the REAL decoder rather than a regex over the
// source, so inheritance from an ancestor `<svg>` or `<g>` is resolved exactly
// as the runtime resolves it. That matters: at the time this was written, 132
// of the 143 affected files declared the stack ONCE on the root element and
// most of their text nodes carried no `font-family` of their own, so a
// per-element grep understates the affected surface by roughly half.
//
// TWO ASSERTIONS:
//   1. No resolved font family contains a comma.
//   2. Every resolved font family is one of the families pubspec actually
//      bundles, so a typo ("DM-Mono", "IBMPlexSans") fails here rather than
//      shipping as a silent substitution.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';

/// The families declared under `flutter: fonts:` in pubspec.yaml. A resolved
/// family outside this set cannot render as authored on any platform.
const Set<String> _bundledFamilies = <String>{
  'IBM Plex Sans',
  'DM Mono',
  'Roboto Mono',
};

/// Third-party artwork we did not author — vendor logotypes and regulator
/// marks traced from the owner's own files. Their type is part of the mark, we
/// do not restyle it, and GL-003 §9 keeps our hands off it. Excluded by
/// directory, never by individual filename, so a new vendor asset inherits the
/// exclusion and a new asset of OURS cannot land inside one by accident.
const List<String> _vendorDirs = <String>[
  'assets/vendor-src/',
  'assets/standards-body-logos/',
  'assets/regulator-logos/',
];

bool _isVendor(String path) => _vendorDirs.any(path.startsWith);

void main() {
  final List<File> svgs = Directory('assets')
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.svg'))
      .where((File f) => !_isVendor(f.path))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));

  test('every bundled SVG carries at least one asset to check', () {
    expect(svgs, isNotEmpty);
  });

  test('no <text> resolves to a CSS font stack flutter_svg cannot match', () {
    final List<String> offenders = <String>[];
    for (final File f in svgs) {
      final VectorInstructions vi =
          parseWithoutOptimizers(f.readAsStringSync(), key: f.path);
      for (final TextConfig t in vi.text) {
        final String? fam = t.fontFamily;
        if (fam != null && fam.contains(',')) {
          offenders.add('${f.path}: "$fam"  (text: "${t.text}")');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'flutter_svg resolves ONE family name, never a CSS stack. These '
          'render in the platform fallback face, not the authored face:\n'
          '${offenders.take(40).join('\n')}\n'
          '(${offenders.length} total)',
    );
  });

  test('every resolved font family is one pubspec actually bundles', () {
    final Map<String, Set<String>> unknown = <String, Set<String>>{};
    for (final File f in svgs) {
      final VectorInstructions vi =
          parseWithoutOptimizers(f.readAsStringSync(), key: f.path);
      for (final TextConfig t in vi.text) {
        final String? fam = t.fontFamily;
        if (fam == null) continue;
        if (!_bundledFamilies.contains(fam)) {
          unknown.putIfAbsent(f.path, () => <String>{}).add(fam);
        }
      }
    }
    expect(
      unknown,
      isEmpty,
      reason: 'These resolve to a family the app does not bundle, so the '
          'platform substitutes its own face:\n'
          '${unknown.entries.map((MapEntry<String, Set<String>> e) => '${e.key}: ${e.value}').join('\n')}',
    );
  });
}
