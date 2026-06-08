// Convention-based face-diagram resolution for the NEMA Connectors reference,
// with graceful degradation.
//
// The NEMA Connectors reference page carries ONE graphic slot — a connector
// face-diagram plate. Charta authors the plate SVG later (face diagrams are a
// deferred pass); Larry wires the final in before merge. This resolver is the
// integration point so the page builds and ships fully working WITHOUT blocking
// on the asset:
//   * the diagram lives at assets/tool-graphics/<asset-name>.svg, named
//     explicitly (the same explicit-name convention PowerPhasingDiagrams uses),
//     because the deferred face plate is a page-specific graphic distinct from
//     the per-tool concept graphic resolved by ToolAssets.graphicPath.
//   * a missing file NEVER throws and NEVER renders a broken-image box.
//
// It mirrors PowerPhasingDiagrams / ConnectorDiagrams / ToolAssets (the proven
// manifest-gated resolvers): read the build-time AssetManifest once, cache the
// set of files Flutter actually bundled, and answer `has(assetName)` with zero
// I/O thereafter. The screen gates on `has(...)` before ever handing
// `SvgPicture.asset` a path, so flutter_svg never hits a missing-asset error.
// Until the SVG lands in the bundle, `has(...)` is false and the diagram band
// renders nothing — the data page ships fully working today.
//
// The asset name is fixed by the build brief and referenced verbatim by the
// screen; it is exposed as a named const so the screen and tests share one
// source of truth and cannot drift.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves the NEMA Connectors face-diagram plate by explicit asset name,
/// gated on the build-time asset manifest so a missing file degrades silently.
class NemaConnectorDiagrams {
  NemaConnectorDiagrams._();

  static const String _dir = 'assets/tool-graphics';

  /// The connector face-diagram plate for the NEMA Connectors reference.
  static const String facePlate = 'nema-connectors';

  /// All asset names, in render order, for tests and iteration.
  static const List<String> all = <String>[facePlate];

  /// Built diagram paths, populated once from the AssetManifest. `null` until
  /// the first [ensureLoaded] completes; treated as "nothing built" until then.
  static Set<String>? _bundled;

  /// Conventional diagram path for [assetName]. No existence guarantee — gate on
  /// [has] before handing this to `SvgPicture.asset`.
  static String path(String assetName) => '$_dir/$assetName.svg';

  /// `true` only when the build actually bundled this face-diagram SVG.
  static bool has(String assetName) =>
      _bundled?.contains(path(assetName)) ?? false;

  /// Load and cache the asset manifest once. Safe to call repeatedly. Call
  /// during app startup so the synchronous [has] checks have data; if it has not
  /// run yet, [has] returns `false` and the diagram band is simply omitted, so a
  /// race only delays a diagram, never crashes.
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

  /// Test-only override so widget tests can assert the band renders when present
  /// and is omitted when absent. Pass exact bundled paths (e.g.
  /// 'assets/tool-graphics/nema-connectors.svg'); pass an empty set for "none
  /// built".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
