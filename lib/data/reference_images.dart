// Convention-based resolution for the Tier-1 reference RASTER images, with
// graceful degradation.
//
// These are DARK-BAKED RASTER plates (Charta-rendered, GL-003 §8 dark App Mode)
// whose VISUAL is the content and cannot be reproduced cleanly as native text:
//   * time-zone-maps     — the schematic world UTC-offset map (orientation).
//   * phonetic-alphabet  — the semaphore arm dials + maritime signal-flag plate.
//   * diffie-hellman     — the paint-mixing key-exchange diagram with the math.
//
// Unlike the §8.6.2 SVG concept graphics, these are PRE-RENDERED PNGs: they
// cannot take the §8.20.7 runtime light-mode per-mark color swap (you cannot
// recolor a raster's individual strokes). They are therefore presented on an
// ALWAYS-DARK surface card in both themes via DarkRasterDiagramCard — the
// #1A1A1A canvas they were authored against (§8.6.2) — so they never read
// inverted on a light canvas. Every fact each plate carries is ALSO present in
// the screen's native text tables, so the image is decorative for screen
// readers and never the sole carrier of meaning.
//
// Mirrors ModulationDiagrams / ToolAssets (the proven per-asset resolvers): read
// the AssetManifest once, cache the set of files Flutter actually bundled, and
// answer `isBundled(id)` with zero I/O thereafter. The screen gates on
// `isBundled` before ever handing `Image.asset` a path, so a missing or
// unbundled file NEVER throws and NEVER renders a broken-image box — the
// screen's text tables still read end-to-end.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves the Tier-1 reference raster PNGs (`assets/reference/<id>.png`),
/// gated on the build-time asset manifest so a missing file degrades silently.
class ReferenceImages {
  ReferenceImages._();

  static const String _dir = 'assets/reference';

  /// Conventional asset path for [id] (a catalog tool id). No existence
  /// guarantee — gate on [isBundled] before handing this to `Image.asset`.
  static String pathFor(String id) => '$_dir/$id.png';

  /// Subdirectory holding the per-letter Phonetic Alphabet blocks (the
  /// semaphore dial + maritime flag + Morse for ONE letter, re-rendered
  /// standalone from the plate's own SVG builders onto a baked dark surface).
  static const String _phoneticBlocksDir = '$_dir/phonetic-blocks';

  /// Conventional asset path for the per-letter Phonetic block for [letter]
  /// (case-insensitive; e.g. `A` -> `assets/reference/phonetic-blocks/a.png`).
  /// No existence guarantee — gate on [isPhoneticBlockBundled] before handing
  /// this to `Image.asset`.
  static String phoneticBlockPathFor(String letter) =>
      '$_phoneticBlocksDir/${letter.toLowerCase()}.png';

  /// `true` only when the build actually bundled this letter's block PNG. Gate
  /// on this before handing [phoneticBlockPathFor] to `Image.asset`, so a
  /// missing block simply omits the row thumbnail and never renders a broken
  /// box. The A-Z table text (letter, word, Morse) reads end-to-end regardless.
  static bool isPhoneticBlockBundled(String letter) =>
      _bundled?.contains(phoneticBlockPathFor(letter)) ?? false;

  /// Built reference-image paths, populated once from the AssetManifest. `null`
  /// until the first [ensureLoaded] completes; treated as "nothing built".
  static Set<String>? _bundled;

  /// `true` only when the build actually bundled this id's PNG. Gate on this
  /// before handing [pathFor] to `Image.asset`.
  static bool isBundled(String id) => _bundled?.contains(pathFor(id)) ?? false;

  /// Load and cache the asset manifest once. Safe to call repeatedly. Call
  /// during app startup so the synchronous [isBundled] check has data; if it has
  /// not run yet, [isBundled] returns `false` and the image card is simply
  /// omitted, so a race only delays an image, never crashes.
  static Future<void> ensureLoaded() async {
    if (_bundled != null) return;
    WidgetsFlutterBinding.ensureInitialized();
    final AssetManifest manifest = await AssetManifest.loadFromAssetBundle(
      rootBundle,
    );
    _bundled = manifest
        .listAssets()
        .where((String p) => p.startsWith('$_dir/'))
        .toSet();
  }

  /// Test-only override so widget tests can assert the image card renders when
  /// the asset is present and is omitted when absent. Pass the exact bundled
  /// paths, or an empty set for "nothing built".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
