// Auto-discovered by `flutter test` and run once before the whole suite.
//
// Job: load the three bundled typefaces (IBM Plex Sans, DM Mono, Roboto Mono)
// into the test engine under their bare family names so golden snapshots
// (test/screens/reference/) render real glyphs, not the test-runner fallback
// box font. Without real glyphs the baselines would not match what ships and
// would be useless for catching visual regressions.
//
// Since the theme now sources type from bundled Flutter font families
// (pubspec `flutter: fonts:`) via plain `fontFamily` — no google_fonts runtime
// resolution — we register each family under its PLAIN family name and add
// every weight TTF we ship to that family. The engine picks the correct face
// by `fontWeight` at render time, exactly as it does in the running app. The
// per-variant "<Family>_<variant>" registration the old google_fonts path
// required is gone.
//
// The family-name strings below must match the `fontFamily` values the theme
// requests ('IBM Plex Sans', 'DM Mono', 'Roboto Mono'). If a family name
// changes in lib/theme/ or pubspec.yaml, the golden fonts silently fall back —
// regenerate the baselines and confirm glyphs render.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Family name the formula-glyph fallback subset registers under. The book-
/// figure harness adds this to `ThemeData.fontFamilyFallback` so the render
/// engine consults it PER-GLYPH for codepoints the primary faces miss.
///
/// Why a fallback family and not extra `FontLoader.addFont` calls on the
/// primary family: multiple `addFont`s under one family select ONE face per
/// (weight, style) — they are NOT a per-glyph fallback chain, so a glyph absent
/// from the chosen face still renders `.notdef`. Per-glyph fallback only works
/// through the engine's `fontFamilyFallback` mechanism. See [kFormulaFallback].
const String kFormulaFallbackFamily = 'FormulaFallback';

/// The glyph-complete subset (OFL STIX Two Text) carrying the formula glyphs the
/// bundled faces lack — Greek lambda (U+03BB), sub/superscript digits and signs
/// (U+2080–U+208B, U+2070–U+207B), middle dot, multiply, degree, minus. DM Mono
/// has none of the sub/superscripts or lambda; IBM Plex Sans lacks the
/// superscript-minus (U+207B). On a real device the OS font-fallback chain
/// supplies these, so `dBm = 10·log₁₀(mW)`, `λ`, and `10⁻²³` render correctly;
/// the headless test engine has NO such chain — so the book-figure harness wires
/// this family into `fontFamilyFallback` to stand in for it. Test-only: never
/// declared under pubspec `flutter: fonts:`, so it is not in the shipped binary.
const String _formulaFallbackAsset = 'assets/fonts/test/FormulaFallback.ttf';

Future<void> _loadFont(String family, List<String> assetPaths) async {
  final FontLoader loader = FontLoader(family);
  for (final String path in assetPaths) {
    loader.addFont(rootBundle.load(path));
  }
  await loader.load();
}

Future<void> _loadBundledFonts() async {
  // Register each family under its plain name with all the weights it ships.
  // Mirrors the pubspec `flutter: fonts:` declaration so the test engine and
  // the running app resolve identical faces.
  const Map<String, List<String>> faces = <String, List<String>>{
    // IBM Plex Sans — theme uses 400/500/600/700 (all normal).
    'IBM Plex Sans': <String>[
      'assets/fonts/IBMPlexSans-Regular.ttf',
      'assets/fonts/IBMPlexSans-Medium.ttf',
      'assets/fonts/IBMPlexSans-SemiBold.ttf',
      'assets/fonts/IBMPlexSans-Bold.ttf',
    ],
    // DM Mono — theme uses 400/500 (all normal).
    'DM Mono': <String>[
      'assets/fonts/DMMono-Regular.ttf',
      'assets/fonts/DMMono-Medium.ttf',
    ],
    // Roboto Mono — theme uses 400 (normal).
    'Roboto Mono': <String>['assets/fonts/RobotoMono-Regular.ttf'],
  };
  for (final MapEntry<String, List<String>> e in faces.entries) {
    await _loadFont(e.key, e.value);
  }
  // Register the formula-glyph subset under its own family so the book-figure
  // harness can add it to `ThemeData.fontFamilyFallback` for per-glyph fallback
  // (λ, log₁₀, 10⁻²³). The capture harness opts in; the rest of the suite is
  // unaffected because nothing else lists this family in its fallback chain.
  await _loadFont(kFormulaFallbackFamily, const <String>[_formulaFallbackAsset]);
}

/// Loads the REAL MaterialIcons glyph outlines so app-bar / chrome `Icons.*`
/// render as their actual icon instead of `.notdef` boxes.
///
/// `flutter test` does NOT ship the real MaterialIcons font into the test
/// engine — `Icons.copy_outlined`, `Icons.help_outline`, etc. render as empty
/// boxes in a headless capture. The real OTF lives in the Flutter SDK cache at
/// `bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf`. We locate the
/// SDK from the running Dart executable (`<sdk>/bin/cache/dart-sdk/bin/dart`)
/// and register the font under the `MaterialIcons` family. Best-effort: if the
/// SDK layout changes the icons fall back to boxes (the prior behavior) rather
/// than crashing the capture run.
Future<void> _loadMaterialIcons() async {
  final File? otf = _findMaterialIconsOtf();
  if (otf == null) {
    // ignore: avoid_print
    print(
      'WARN: MaterialIcons-Regular.otf not found in the Flutter SDK cache — '
      'app-bar icons will render as boxes. Set FLUTTER_ROOT or run from a '
      'normal Flutter checkout.',
    );
    return;
  }
  final Uint8List bytes = await otf.readAsBytes();
  final FontLoader loader = FontLoader('MaterialIcons')
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

/// Resolves the bundled MaterialIcons OTF from the active Flutter SDK. Tries
/// `FLUTTER_ROOT` first, then derives the SDK root from the Dart executable
/// path (`<flutter>/bin/cache/dart-sdk/bin/dart`).
File? _findMaterialIconsOtf() {
  const String rel =
      'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';

  final List<String> roots = <String>[];

  final String? flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) roots.add(flutterRoot);

  // dartExe = <flutterRoot>/bin/cache/dart-sdk/bin/dart → climb 4 segments.
  final String dartExe = Platform.resolvedExecutable;
  final List<String> parts = dartExe.split(Platform.pathSeparator);
  if (parts.length > 5) {
    final int cacheIdx = parts.lastIndexOf('cache');
    if (cacheIdx >= 2) {
      // <root>/bin/cache/... → root is two segments above 'cache'.
      roots.add(parts.sublist(0, cacheIdx - 1).join(Platform.pathSeparator));
    }
  }

  for (final String root in roots) {
    final File f = File('$root${Platform.pathSeparator}$rel');
    if (f.existsSync()) return f;
  }
  return null;
}

/// Pixel-diff ratio tolerated as cross-host anti-aliasing / font-hinting noise
/// before a golden is treated as a real failure. Observed jitter on this suite
/// between the baseline-author machine and another renderer (incl. Linux CI) is
/// 0.04–0.12%; a genuine layout regression (clipped column, overflow, wrong
/// weight) changes whole regions and lands far above 1%. 0.5% sits well clear of
/// the noise and well below any real break.
const double _goldenDiffTolerance = 0.005;

/// Golden comparator that passes a mismatch within [_goldenDiffTolerance] and
/// fails anything larger with the normal diff output. Without this, rendered
/// goldens fail on every host but the one that generated the baselines (pure
/// sub-pixel font hinting), which is why they previously had to be excluded from
/// CI. Baselines are still authored on a known-good render; this only absorbs
/// cross-host jitter, so genuine visual regressions are still caught.
class _TolerantGoldenComparator extends LocalFileComparator {
  _TolerantGoldenComparator(Uri testFile) : super(testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final ComparisonResult result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= _goldenDiffTolerance) {
      return true;
    }
    final String error = await generateFailureOutput(result, golden, basedir);
    throw FlutterError(error);
  }
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadBundledFonts();
  await _loadMaterialIcons();
  // Tolerate sub-pixel cross-host rendering jitter so goldens run in CI instead
  // of being skipped. Preserve the default comparator's basedir so each test
  // file's relative golden paths still resolve.
  if (goldenFileComparator is LocalFileComparator) {
    final LocalFileComparator previous =
        goldenFileComparator as LocalFileComparator;
    goldenFileComparator = _TolerantGoldenComparator(
      previous.basedir.resolve('flutter_test_config.dart'),
    );
  }
  await testMain();
}
