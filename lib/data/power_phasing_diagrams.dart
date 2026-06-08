// Convention-based waveform-diagram resolution for the Power Phasing reference,
// with graceful degradation.
//
// The Power Phasing reference page renders three named waveform SVGs — one per
// phasing topology (single-phase 120V, split-phase 120/240V, three-phase wye
// 208V). Charta authors these SVGs in parallel; Larry wires the finals in before
// merge. This resolver is the integration point so the page builds and ships
// fully working WITHOUT blocking on the assets:
//   * diagrams live at assets/tool-graphics/<asset-name>.svg, named explicitly
//     (NOT keyed on the catalog tool id, because one tool page carries three
//     distinct waveform graphics — unlike the single per-tool concept graphic
//     resolved by ToolAssets.graphicPath).
//   * a missing file NEVER throws and NEVER renders a broken-image box.
//
// It mirrors ConnectorDiagrams / ToolAssets (the proven manifest-gated
// resolvers): read the build-time AssetManifest once, cache the set of files
// Flutter actually bundled, and answer `has(assetName)` with zero I/O
// thereafter. The screen gates on `has(...)` before ever handing
// `SvgPicture.asset` a path, so flutter_svg never hits a missing-asset error.
// Until the SVGs land in the bundle, `has(...)` is false for each and the
// diagram band renders nothing — the data page ships fully working today.
//
// The three asset names are fixed by the build brief and referenced verbatim by
// the screen; they are exposed as named consts so the screen and tests share one
// source of truth and cannot drift.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves the three Power Phasing waveform diagrams by explicit asset name,
/// gated on the build-time asset manifest so missing files degrade silently.
class PowerPhasingDiagrams {
  PowerPhasingDiagrams._();

  static const String _dir = 'assets/tool-graphics';

  /// Single-phase 120V waveform (one hot + neutral).
  static const String single120v = 'power-phasing-single-120v';

  /// Split-phase 120/240V waveform (two hots 180 degrees apart).
  static const String split240v = 'power-phasing-split-240v';

  /// Three-phase wye 208V waveform (three hots 120 degrees apart).
  static const String three208v = 'power-phasing-three-208v';

  /// All three asset names, in render order, for tests and iteration.
  static const List<String> all = <String>[single120v, split240v, three208v];

  /// Built diagram paths, populated once from the AssetManifest. `null` until
  /// the first [ensureLoaded] completes; treated as "nothing built" until then.
  static Set<String>? _bundled;

  /// Conventional diagram path for [assetName]. No existence guarantee — gate on
  /// [has] before handing this to `SvgPicture.asset`.
  static String path(String assetName) => '$_dir/$assetName.svg';

  /// `true` only when the build actually bundled this waveform SVG.
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
  /// 'assets/tool-graphics/power-phasing-single-120v.svg'); pass an empty set
  /// for "none built".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
