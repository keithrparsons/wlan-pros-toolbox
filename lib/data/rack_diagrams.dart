// Convention-based concept-graphic resolution for the Rack Units & Mounting
// Hardware reference, with graceful degradation.
//
// The page carries TWO large concept graphics, each rendered through the shared
// LargeGraphic primitive:
//   * rack-1u-dimension — the highest-value visual: a 1U dimension diagram
//     showing the 1.75-in height, the three holes at 0.5 / 0.625 / 0.625 in, and
//     the U boundary line landing mid-gap (the irregular EIA-310 pattern that
//     installers count wrong).
//   * rack-cage-nut — a cage-nut illustration: a square hole, the spring-steel
//     cage nut clipping in, a screw threading through; the modern strip-proof,
//     thread-agnostic mounting default.
// Charta authors these SVGs in parallel; Larry wires the finals in before merge.
// This resolver is the integration point so the page builds and ships fully
// working WITHOUT blocking on the assets:
//   * each graphic lives at assets/tool-graphics/<asset-name>.svg, named
//     explicitly (NOT keyed on the catalog tool id — one page carries several
//     graphics, so the page and tests share one verbatim source of truth and
//     cannot drift).
//   * a missing file NEVER throws and NEVER renders a broken-image box; the
//     relevant section reads as tables + text alone until its graphic lands.
//
// It mirrors IecConnectorsDiagrams / PowerPhasingDiagrams / ConnectorDiagrams
// (the proven manifest-gated resolvers): read the build-time AssetManifest once,
// cache the set of files Flutter actually bundled, and answer `has(assetName)`
// with zero I/O thereafter. The screen gates on `has(...)` before ever handing
// `SvgPicture.asset` a path, so flutter_svg never hits a missing-asset error.
//
// The asset names are fixed by the build brief and referenced verbatim by the
// screen; they are exposed as named consts so the screen and tests share one
// source of truth and cannot drift.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves the Rack Units concept graphics by explicit asset name, gated on the
/// build-time asset manifest so a missing file degrades silently.
class RackDiagrams {
  RackDiagrams._();

  static const String _dir = 'assets/tool-graphics';

  /// 1U dimension diagram: the 1.75-in (44.45 mm) height, the three holes at
  /// 0.5 / 0.625 / 0.625 in, and the U boundary line landing in the middle of
  /// the 0.5-in gap. The page's highest-value visual.
  static const String rack1u = 'rack-1u-dimension';

  /// Cage-nut illustration: a square hole, the spring-steel cage nut clipping
  /// in, and a screw threading through it. The modern strip-proof,
  /// thread-agnostic mounting default.
  static const String cageNut = 'rack-cage-nut';

  /// All concept-graphic asset names for this page, in render order, for tests
  /// and iteration.
  static const List<String> all = <String>[rack1u, cageNut];

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

  /// Test-only override so widget tests can assert the graphic renders when
  /// present and is omitted when absent. Pass exact bundled paths (e.g.
  /// 'assets/tool-graphics/rack-1u-dimension.svg'); pass an empty set for "none
  /// built".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
