// Convention-based diagram resolution for the Markdown Cheatsheet reference,
// with graceful degradation.
//
// The page renders ONE concept graphic at its top — a "you type / renders as"
// example pane (the `markdown-render-example` SVG) showing a small markdown
// snippet beside its rendered result, so the reader sees the core idea before
// the syntax tables. Charta authors the SVG in parallel; Larry wires the final
// in before merge. This resolver is the integration point so the page builds
// and ships fully working WITHOUT blocking on the asset:
//   * the graphic lives at assets/tool-graphics/markdown-render-example.svg,
//     named explicitly (NOT keyed on the catalog tool id) so the page and tests
//     share one verbatim source of truth and cannot drift;
//   * a missing file NEVER throws and NEVER renders a broken-image box; the page
//     reads as intro + syntax tables alone until the graphic lands.
//
// It mirrors IecConnectorsDiagrams / ToolAssets (the proven manifest-gated
// resolvers): read the build-time AssetManifest once, cache the set of files
// Flutter actually bundled, and answer `has(assetName)` with zero I/O
// thereafter. The screen gates on `has(...)` before ever handing
// `SvgPicture.asset` a path, so flutter_svg never hits a missing-asset error.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves the Markdown Cheatsheet concept graphic by explicit asset name,
/// gated on the build-time asset manifest so a missing file degrades silently.
class MarkdownDiagrams {
  MarkdownDiagrams._();

  static const String _dir = 'assets/tool-graphics';

  /// The "you type / renders as" example pane shown at the top of the page: a
  /// short markdown snippet beside its rendered result.
  static const String renderExample = 'markdown-render-example';

  /// All asset names this page references, in render order, for tests and
  /// iteration. One graphic today; the list keeps the test contract uniform
  /// with the other multi-asset resolvers.
  static const List<String> all = <String>[renderExample];

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
  /// run yet, [has] returns `false` and the graphic is simply omitted, so a race
  /// only delays the graphic, never crashes.
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
  /// 'assets/tool-graphics/markdown-render-example.svg'); pass an empty set for
  /// "none built".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
