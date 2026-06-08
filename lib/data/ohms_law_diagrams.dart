// Convention-based diagram resolution for the Ohm's Law & Power Wheel
// reference, with graceful degradation.
//
// The Ohm's Law page carries one named reference graphic — the 12-segment
// power wheel (V / I / R / P, each expressed in terms of any two of the
// others). Charta authors it in parallel; Larry wires the final in before
// merge. This resolver is the integration point so the page builds and ships
// fully working WITHOUT blocking on the asset:
//   * the diagram lives at assets/tool-graphics/<asset-name>.svg, named
//     explicitly through the SAME manifest-gated resolver pattern the Power
//     Phasing pilot uses (PowerPhasingDiagrams) rather than keying on the
//     catalog tool id, so the page reads from one shared source of truth and
//     the screen + test cannot drift on the asset name.
//   * a missing file NEVER throws and NEVER renders a broken-image box.
//
// It mirrors PowerPhasingDiagrams / ConnectorDiagrams / ToolAssets (the proven
// manifest-gated resolvers): read the build-time AssetManifest once, cache the
// set of files Flutter actually bundled, and answer `has(assetName)` with zero
// I/O thereafter. The screen gates on `has(...)` before ever handing
// `SvgPicture.asset` a path, so flutter_svg never hits a missing-asset error.
// Until the SVG lands in the bundle, `has(...)` is false and the diagram band
// renders nothing — the data page ships fully working today.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves the Ohm's Law power-wheel diagram by explicit asset name, gated on
/// the build-time asset manifest so a missing file degrades silently.
class OhmsLawDiagrams {
  OhmsLawDiagrams._();

  static const String _dir = 'assets/tool-graphics';

  /// The 12-segment Ohm's-law / power wheel (V, I, R, P each in terms of any
  /// two of the others).
  static const String wheel = 'ohms-law-wheel';

  /// All diagram asset names for this page, in render order, for tests and
  /// iteration. One today; kept a list so the screen and tests share one
  /// source of truth and the multi-graphic resolver pattern is preserved.
  static const List<String> all = <String>[wheel];

  /// Built diagram paths, populated once from the AssetManifest. `null` until
  /// the first [ensureLoaded] completes; treated as "nothing built" until then.
  static Set<String>? _bundled;

  /// Conventional diagram path for [assetName]. No existence guarantee — gate
  /// on [has] before handing this to `SvgPicture.asset`.
  static String path(String assetName) => '$_dir/$assetName.svg';

  /// `true` only when the build actually bundled this diagram SVG.
  static bool has(String assetName) =>
      _bundled?.contains(path(assetName)) ?? false;

  /// Load and cache the asset manifest once. Safe to call repeatedly. Call
  /// during app startup so the synchronous [has] checks have data; if it has
  /// not run yet, [has] returns `false` and the diagram band is simply omitted,
  /// so a race only delays a diagram, never crashes.
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
  /// 'assets/tool-graphics/ohms-law-wheel.svg'); pass an empty set for "none
  /// built".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
