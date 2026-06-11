// Convention-based resolution for the single "where you test throughput along
// the path changes the result" reference diagram, with graceful degradation.
//
// This is a Vera-passed, DARK-BAKED RASTER diagram (a white WLAN Pros logo on
// the §8 dark canvas), embedded on the Speed Test Services reference screen to
// illustrate the screen's whole thesis: a speed-test number depends on WHERE
// along the client → Wi-Fi → router → ISP → CDN-edge → distant-server path you
// measure. It directly reinforces the screen's three teaching callouts
// (CDN-edge vs. real internet; single vs. multi-stream; bufferbloat).
//
// Unlike the §8.6.2 SVG concept graphics and the Antenna Fundamentals SVGs,
// this is a PRE-RENDERED PNG: it cannot take the §8.20.7 runtime light-mode
// per-mark color swap (you cannot recolor a raster's individual strokes). It is
// therefore presented on an ALWAYS-DARK surface card in both themes — the
// #222222 surface it was authored against (§8.6.2) — so it never reads inverted
// on a light canvas. The call site (ThroughputWhereDiagramCard) owns that
// always-dark backing; this resolver only answers "is the file bundled?".
//
// Mirrors AntennaFundamentalsDiagrams / ToolAssets (the proven per-asset
// resolvers): read the AssetManifest once, cache the set of files Flutter
// actually bundled, and answer `has()` with zero I/O thereafter. The screen
// gates on `has()` before ever handing `Image.asset` a path, so a missing or
// unbundled file NEVER throws and NEVER renders a broken-image box — the
// screen's hero, caveats, callouts, and service cards still read end-to-end.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves the single throughput-testing-where reference diagram PNG, gated on
/// the build-time asset manifest so a missing file degrades silently.
class ThroughputWhereDiagram {
  ThroughputWhereDiagram._();

  /// The one bundled diagram path. Single asset, so no per-slug math is needed.
  static const String assetPath =
      'assets/tool-diagrams/throughput-testing-where/'
      'throughput-testing-where-dark.png';

  /// Built diagram paths, populated once from the AssetManifest. `null` until
  /// the first [ensureLoaded] completes; treated as "nothing built" until then.
  static Set<String>? _bundled;

  /// `true` only when the build actually bundled the diagram PNG. Gate on this
  /// before handing [assetPath] to `Image.asset`.
  static bool get isBundled => _bundled?.contains(assetPath) ?? false;

  /// Load and cache the asset manifest once. Safe to call repeatedly. Call
  /// during app startup so the synchronous [isBundled] check has data; if it has
  /// not run yet, [isBundled] returns `false` and the diagram card is simply
  /// omitted, so a race only delays a diagram, never crashes.
  static Future<void> ensureLoaded() async {
    if (_bundled != null) return;
    WidgetsFlutterBinding.ensureInitialized();
    final AssetManifest manifest =
        await AssetManifest.loadFromAssetBundle(rootBundle);
    _bundled = manifest
        .listAssets()
        .where((String p) => p == assetPath)
        .toSet();
  }

  /// Test-only override so widget tests can assert the card renders when the
  /// asset is present and is omitted when absent. Pass {assetPath} for "bundled"
  /// or an empty set for "not bundled".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
