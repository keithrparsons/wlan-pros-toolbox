// Convention-based concept-graphic resolution for the Cable Bend Radius & Pull
// Tension reference, with graceful degradation.
//
// The page carries two LARGE concept graphics rendered through the shared
// LargeGraphic primitive (lib/screens/tools/reference/large_face_card.dart):
//   bend-radius-arc-vs-kink  — the good gentle arc (>= 4x OD) vs the tight kink
//                              that permanently changes internal conductor
//                              spacing (the single most useful visual on the
//                              page, per Pax's research brief).
//   pull-tension-gauge       — a cable under a tension gauge reading 25 lbf /
//                              110 N at the limit line, with the over-pull
//                              consequence callout (stretched conductor ->
//                              attenuation -> NEXT).
// Charta authors these SVGs in parallel; Larry wires the finals in before merge.
// This resolver is the integration point so the page builds and ships fully
// working WITHOUT blocking on the assets:
//   * each graphic lives at assets/tool-graphics/<asset-name>.svg, named
//     explicitly (NOT keyed on the catalog tool id — one page carries two
//     graphics, so the page and tests share one verbatim source of truth and
//     cannot drift).
//   * a missing file NEVER throws and NEVER renders a broken-image box; the
//     section reads as text + tables alone until its graphic lands.
//
// It mirrors IecConnectorsDiagrams / PowerPhasingDiagrams / ToolAssets (the
// proven manifest-gated resolvers): read the build-time AssetManifest once,
// cache the set of files Flutter actually bundled, and answer `has(assetName)`
// with zero I/O thereafter. The screen gates on `has(...)` before ever handing
// `SvgPicture.asset` a path, so flutter_svg never hits a missing-asset error.
//
// The asset names are fixed by the build brief and referenced verbatim by the
// screen; they are exposed as named consts so the screen and tests share one
// source of truth and cannot drift.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves the Cable Bend Radius concept graphics by explicit asset name, gated
/// on the build-time asset manifest so a missing file degrades silently.
class BendDiagrams {
  BendDiagrams._();

  static const String _dir = 'assets/tool-graphics';

  /// The good arc (>= 4x OD) vs the tight kink concept graphic. Annotates that a
  /// kink permanently changes internal conductor spacing — the damage does not
  /// spring back.
  static const String arcVsKink = 'bend-radius-arc-vs-kink';

  /// The pull-tension gauge concept graphic: a cable under tension reading
  /// 25 lbf / 110 N at the limit line, with the over-pull consequence callout.
  static const String pullTensionGauge = 'pull-tension-gauge';

  /// Both concept-graphic asset names for this page, in render order, for tests
  /// and iteration.
  static const List<String> all = <String>[arcVsKink, pullTensionGauge];

  /// Built graphic paths, populated once from the AssetManifest. `null` until
  /// the first [ensureLoaded] completes; treated as "nothing built" until then.
  static Set<String>? _bundled;

  /// Conventional graphic path for [assetName]. No existence guarantee — gate on
  /// [has] before handing this to `SvgPicture.asset`.
  static String path(String assetName) => '$_dir/$assetName.svg';

  /// `true` only when the build actually bundled this graphic SVG.
  static bool has(String assetName) =>
      _bundled?.contains(path(assetName)) ?? false;

  /// Load and cache the asset manifest once. Safe to call repeatedly. Call
  /// during app startup so the synchronous [has] checks have data; if it has not
  /// run yet, [has] returns `false` and the graphic is simply omitted, so a race
  /// only delays a graphic, never crashes.
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

  /// Test-only override so widget tests can assert a graphic renders when present
  /// and is omitted when absent. Pass exact bundled paths (e.g.
  /// 'assets/tool-graphics/bend-radius-arc-vs-kink.svg'); pass an empty set for
  /// "none built".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
