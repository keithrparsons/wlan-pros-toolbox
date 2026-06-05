// Convention-based resolution for the Antenna Connectors EDITORIAL SECTION
// diagrams, with graceful degradation. Distinct from per-connector diagrams
// (lib/data/connector_diagrams.dart): these are full-width teaching diagrams
// that illustrate a concept across connectors, rendered below the table.
//
// Charta authored two (Vera-pending) section diagrams:
//   * polarity-explained — standard vs reverse-polarity center-contact swap.
//   * size-comparison     — connectors drawn to true relative scale, largest to
//                           smallest, with mm callouts.
// They live at assets/connector-sections/<key>.svg and share the dark-baked
// concept-graphic palette (#E5E5E5 / #9C9C9C / #A2CC3A), so the §8.20.7 light
// swap (ConceptGraphicBand.applyLightSwap) recolors them for light mode exactly
// as it does the per-connector diagrams.
//
// Resolution mirrors ConnectorDiagrams: read the build-time AssetManifest once,
// cache the bundled set, answer has(key) with zero I/O. A missing file never
// throws and never shows a broken-image box — the section simply omits its
// diagram (its text content still renders).

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves the editorial-section SVG diagrams by a stable section key, gated on
/// the build-time asset manifest so missing files degrade silently.
class ConnectorSections {
  ConnectorSections._();

  static const String _dir = 'assets/connector-sections';

  /// Stable section keys (also the file basenames).
  static const String polarityExplained = 'polarity-explained';
  static const String sizeComparison = 'size-comparison';

  static Set<String>? _bundled;

  /// Conventional SVG path for [key]. Gate on [has] before handing to flutter_svg.
  static String path(String key) => '$_dir/$key.svg';

  /// `true` only when the build actually bundled this section's diagram SVG.
  static bool has(String key) => _bundled?.contains(path(key)) ?? false;

  /// Load and cache the asset manifest once. Safe to call repeatedly. A race
  /// only delays a diagram, never crashes — [has] returns `false` until loaded.
  static Future<void> ensureLoaded() async {
    if (_bundled != null) return;
    WidgetsFlutterBinding.ensureInitialized();
    final AssetManifest manifest =
        await AssetManifest.loadFromAssetBundle(rootBundle);
    _bundled = manifest
        .listAssets()
        .where((String p) => p.startsWith('$_dir/'))
        .toSet();
  }

  /// Test-only override. Pass exact bundled paths; pass an empty set for "none".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
