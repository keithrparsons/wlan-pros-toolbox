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

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadBundledFonts();
  await testMain();
}
