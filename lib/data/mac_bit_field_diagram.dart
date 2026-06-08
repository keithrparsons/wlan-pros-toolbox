// Convention-based resolution for the single named MAC bit-field diagram on the
// Naming & Addressing Conventions reference page, with graceful degradation.
//
// The Naming & Addressing Conventions page renders one named SVG that depicts
// the first octet of a MAC/EUI address and the U/L and I/G bit positions. Charta
// authors this SVG (assets/tool-graphics/mac-bit-field.svg) in parallel; Larry
// wires the final in and adds the asset to pubspec during the integration pass.
// This resolver is the integration point so the page builds and ships fully
// working WITHOUT blocking on the asset:
//   * the diagram lives at assets/tool-graphics/<asset-name>.svg, named
//     explicitly (NOT keyed on the catalog tool id), matching the multi-graphic
//     resolver pattern PowerPhasingDiagrams established for named diagrams.
//   * a missing file NEVER throws and NEVER renders a broken-image box.
//
// It mirrors PowerPhasingDiagrams / ToolAssets (the proven manifest-gated
// resolvers): read the build-time AssetManifest once, cache the set of files
// Flutter actually bundled, and answer `has(assetName)` with zero I/O
// thereafter. The screen gates on `has(...)` before ever handing
// `SvgPicture.asset` a path, so flutter_svg never hits a missing-asset error.
// Until the SVG lands in the bundle, `has(...)` is false and the diagram band
// renders nothing — the data page ships fully working today.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves the MAC bit-field diagram by explicit asset name, gated on the
/// build-time asset manifest so a missing file degrades silently.
class MacBitFieldDiagram {
  MacBitFieldDiagram._();

  static const String _dir = 'assets/tool-graphics';

  /// First-octet MAC/EUI bit-field diagram (U/L and I/G bit positions).
  static const String macBitField = 'mac-bit-field';

  /// All named diagrams for this page (currently one), for tests and iteration.
  static const List<String> all = <String>[macBitField];

  /// Built diagram paths, populated once from the AssetManifest. `null` until
  /// the first [ensureLoaded] completes; treated as "nothing built" until then.
  static Set<String>? _bundled;

  /// Conventional diagram path for [assetName]. No existence guarantee — gate on
  /// [has] before handing this to `SvgPicture.asset`.
  static String path(String assetName) => '$_dir/$assetName.svg';

  /// `true` only when the build actually bundled this diagram SVG.
  static bool has(String assetName) =>
      _bundled?.contains(path(assetName)) ?? false;

  /// Load and cache the asset manifest once. Safe to call repeatedly. Call
  /// during app startup so the synchronous [has] checks have data; if it has not
  /// run yet, [has] returns `false` and the diagram band is simply omitted, so a
  /// race only delays the diagram, never crashes.
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
  /// 'assets/tool-graphics/mac-bit-field.svg'); pass an empty set for "none".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
