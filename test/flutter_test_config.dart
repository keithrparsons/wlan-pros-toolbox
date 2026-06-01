// Auto-discovered by `flutter test` and run once before the whole suite.
//
// Two jobs:
//
// 1) Disable google_fonts runtime network fetching during tests, mirroring what
//    main.dart does for the running app (GoogleFonts.config.allowRuntimeFetching
//    = false). main() does not run under `flutter test`, so without this a font
//    that is not already cached (e.g. the newly added Roboto Mono) is fetched
//    over the network on first use; in the test sandbox that throws "There is no
//    current invoker", which fails the loading phase and cascades to unrelated
//    tests. With fetching off, google_fonts uses whatever family the engine has
//    already loaded (see job 2) and otherwise falls back deterministically.
//
// 2) Load the three bundled typefaces (IBM Plex Sans, DM Mono, Roboto Mono)
//    into the test engine under the family names google_fonts resolves to.
//    Real golden snapshots (test/screens/reference/) need real glyphs, not the
//    test-runner fallback box font, or the baselines would not match what ships
//    and would be useless for catching visual regressions. We register each
//    weight we ship under the google_fonts family name so that when the theme
//    asks GoogleFonts.ibmPlexSans()/.dmMono()/.robotoMono() (fetching disabled)
//    the engine already has that family. Loading is idempotent and runs once
//    for the whole suite, so non-golden tests pay a negligible one-time cost.
//
// The family-name strings below must match the names google_fonts assigns
// (the PascalCase font name). If google_fonts changes a family name, the golden
// fonts silently fall back — regenerate the baselines and confirm glyphs render.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> _loadFont(String family, List<String> assetPaths) async {
  final FontLoader loader = FontLoader(family);
  for (final String path in assetPaths) {
    loader.addFont(rootBundle.load(path));
  }
  await loader.load();
}

Future<void> _loadBundledFonts() async {
  // google_fonts (6.3.3) does NOT register a font under its bare family name.
  // It registers each weight/style under a per-variant family string of the
  // form "<Family>_<variant>" (see GoogleFontsFamilyWithVariant.toString):
  //   weight 400 normal -> "<Family>_regular"
  //   weight 500 normal -> "<Family>_500"
  //   weight 600 normal -> "<Family>_600"
  //   weight 700 normal -> "<Family>_700"
  // GoogleFonts.ibmPlexSans(fontWeight: w600) therefore asks the engine for the
  // family "IBM Plex Sans_600", not "IBM Plex Sans". The earlier registration
  // under the bare names never matched, so golden text fell back to the box
  // font. We register each ttf under the exact variant name the theme requests.
  // The bare-name entries are kept as a harmless belt-and-suspenders fallback.
  const Map<String, List<String>> faces = <String, List<String>>{
    // IBM Plex Sans — theme uses 400/500/600/700 (all normal).
    'IBM Plex Sans_regular': <String>['assets/fonts/IBMPlexSans-Regular.ttf'],
    'IBM Plex Sans_500': <String>['assets/fonts/IBMPlexSans-Medium.ttf'],
    'IBM Plex Sans_600': <String>['assets/fonts/IBMPlexSans-SemiBold.ttf'],
    'IBM Plex Sans_700': <String>['assets/fonts/IBMPlexSans-Bold.ttf'],
    // DM Mono — theme uses 400/500 (all normal).
    'DM Mono_regular': <String>['assets/fonts/DMMono-Regular.ttf'],
    'DM Mono_500': <String>['assets/fonts/DMMono-Medium.ttf'],
    // Roboto Mono — theme uses 400 (normal).
    'Roboto Mono_regular': <String>['assets/fonts/RobotoMono-Regular.ttf'],
    // Bare-name fallbacks (harmless if unreferenced).
    'IBM Plex Sans': <String>[
      'assets/fonts/IBMPlexSans-Regular.ttf',
      'assets/fonts/IBMPlexSans-Medium.ttf',
      'assets/fonts/IBMPlexSans-SemiBold.ttf',
      'assets/fonts/IBMPlexSans-Bold.ttf',
    ],
    'DM Mono': <String>[
      'assets/fonts/DMMono-Regular.ttf',
      'assets/fonts/DMMono-Medium.ttf',
    ],
    'Roboto Mono': <String>['assets/fonts/RobotoMono-Regular.ttf'],
  };
  for (final MapEntry<String, List<String>> e in faces.entries) {
    await _loadFont(e.key, e.value);
  }
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await _loadBundledFonts();
  await testMain();
}
