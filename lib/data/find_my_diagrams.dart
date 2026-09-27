// Convention-based diagram resolution for the Find My, Explained Guided Lesson,
// with graceful degradation. Mirrors AntennaFundamentalsDiagrams exactly.
//
// The nine figures (the cover art and Figures 1 to 8 of the approved print
// guide) live at assets/tool-diagrams/find-my/<slug>.svg. They are generated
// by tool/find_my_diagrams.py, authored DARK-BAKED on the GL-003 §8.20.7
// allow-list hexes, and recolored for light through the single source-of-truth
// swap ConceptGraphicBand.applyLightSwap.
//
// Resolved through the build-time asset manifest so a missing or unbundled
// file NEVER throws and NEVER renders a broken-image box: `has(slug)` is false
// and the screen simply omits the figure.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves the Find My, Explained figure SVGs by slug, gated on the build-time
/// asset manifest so a missing file degrades silently.
class FindMyDiagrams {
  FindMyDiagrams._();

  static const String _dir = 'assets/tool-diagrams/find-my';

  /// Built diagram paths, populated once from the AssetManifest. `null` until
  /// the first [ensureLoaded] completes; treated as "nothing built" until then.
  static Set<String>? _bundled;

  /// Conventional diagram path for [slug] (e.g. `f3-where-the-dot-comes-from`).
  /// No existence guarantee: gate on [has] before handing it to flutter_svg.
  static String path(String slug) => '$_dir/$slug.svg';

  /// `true` only when the build actually bundled this diagram's SVG.
  static bool has(String slug) => _bundled?.contains(path(slug)) ?? false;

  /// Load and cache the asset manifest once. Safe to call repeatedly. Called
  /// during app startup; until it completes [has] returns `false` and the
  /// figure is omitted, so a race only delays a figure, never crashes.
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

  /// Test-only override: pass exact bundled paths, or an empty set for "none".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
