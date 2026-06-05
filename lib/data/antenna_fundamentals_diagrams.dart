// Convention-based diagram resolution for the Antenna Fundamentals teaching
// reference, with graceful degradation.
//
// Antenna Fundamentals is a read-along teaching screen (verbatim Penn copy +
// seven Charta line diagrams). Unlike the data-driven references, the seven
// diagrams are FIRST-CLASS content, not optional decoration: each one illustrates
// the section it sits in. They are still resolved through the build-time asset
// manifest so a missing or unbundled file NEVER throws and NEVER renders a
// broken-image box — the prose still reads end-to-end if a diagram is absent.
//
// Mirrors ToolAssets / ConnectorDiagrams (the proven per-asset resolvers): read
// the AssetManifest once, cache the set of files Flutter actually bundled, and
// answer `has(slug)` with zero I/O thereafter. The screen gates on `has(slug)`
// before ever handing `SvgPicture` a path, so flutter_svg never hits a
// missing-asset error.
//
// Diagrams live at assets/tool-diagrams/antenna-fundamentals/<slug>.svg, keyed
// on the graphics-plan slug (g1…g7). LIGHT/DARK: the SVGs are authored
// DARK-BAKED on the §8.20.7 allow-list hexes (#E5E5E5 / #9C9C9C / #A2CC3A /
// #F26E6E / the lime wash), so they recolor for light through the single
// source-of-truth swap `ConceptGraphicBand.applyLightSwap` — see
// AntennaDiagramBand.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves the seven Antenna Fundamentals diagram SVGs by slug, gated on the
/// build-time asset manifest so a missing file degrades silently.
class AntennaFundamentalsDiagrams {
  AntennaFundamentalsDiagrams._();

  static const String _dir = 'assets/tool-diagrams/antenna-fundamentals';

  /// Built diagram paths, populated once from the AssetManifest. `null` until
  /// the first [ensureLoaded] completes; treated as "nothing built" until then.
  static Set<String>? _bundled;

  /// Conventional diagram path for [slug] (e.g. `g3-polar-plot-anatomy`). No
  /// existence guarantee — gate on [has] before handing this to flutter_svg.
  static String path(String slug) => '$_dir/$slug.svg';

  /// `true` only when the build actually bundled this diagram's SVG.
  static bool has(String slug) => _bundled?.contains(path(slug)) ?? false;

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

  /// Test-only override so widget tests can assert the diagram band renders when
  /// present and is omitted when absent. Pass exact bundled paths (e.g.
  /// 'assets/tool-diagrams/antenna-fundamentals/g3-polar-plot-anatomy.svg');
  /// pass an empty set for "none".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
