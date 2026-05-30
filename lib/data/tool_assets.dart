// Convention-based per-tool asset resolution with graceful degradation.
//
// Two asset classes are looked up by a tool's catalog id (kebab-case), per the
// locked Iris spec:
//   GL-003 §8.6 / §8.6.1  — Tier-2 icon    = assets/tool-icons/<id>.svg
//   GL-003 §8.6.2         — concept graphic = assets/tool-graphics/<id>.svg
//
// Most of the ~60 assets are not built yet (Charta mass-produces them later).
// This module exists so a missing file NEVER throws and NEVER renders a
// broken-image box:
//   * `ToolAssets.ensureLoaded()` reads the build-time AssetManifest once and
//     caches the set of files Flutter actually bundled.
//   * `hasIcon` / `hasGraphic` answer "does this tool have a built asset?" with
//     zero I/O after the one-time manifest load.
//   * `iconPath` / `graphicPath` return the conventional path string (pure id
//     math, no existence guarantee) for callers that already gated on `has*`.
//
// The manifest check is the safety net: we only ever hand `SvgPicture.asset`
// a path we have confirmed is in the bundle, so flutter_svg never hits a
// missing-asset error. Callers fall back (icon → category IconData; graphic →
// render nothing) when `has*` is false.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves per-tool icon and concept-graphic assets by catalog id, gated on
/// the build-time asset manifest so missing files degrade silently.
class ToolAssets {
  ToolAssets._();

  static const String _iconDir = 'assets/tool-icons';
  static const String _graphicDir = 'assets/tool-graphics';

  /// Built-asset paths, populated once from the AssetManifest. `null` until the
  /// first `ensureLoaded` completes; treated as "nothing built" until then.
  static Set<String>? _bundled;

  /// Conventional icon path for [toolId]. No existence guarantee — gate on
  /// [hasIcon] before handing this to `SvgPicture.asset`.
  static String iconPath(String toolId) => '$_iconDir/$toolId.svg';

  /// Conventional concept-graphic path for [toolId]. No existence guarantee —
  /// gate on [hasGraphic] before rendering.
  static String graphicPath(String toolId) => '$_graphicDir/$toolId.svg';

  /// `true` only when the build actually bundled this tool's icon SVG.
  static bool hasIcon(String toolId) =>
      _bundled?.contains(iconPath(toolId)) ?? false;

  /// `true` only when the build actually bundled this tool's concept graphic.
  static bool hasGraphic(String toolId) =>
      _bundled?.contains(graphicPath(toolId)) ?? false;

  /// Load and cache the asset manifest once. Safe to call repeatedly — the
  /// manifest is read on the first call and reused thereafter. Call during app
  /// startup (before the first screen that resolves an asset paints) so the
  /// synchronous `has*` checks have data; if it has not run yet, `has*` returns
  /// `false` and callers fall back, so a race only delays an asset, never
  /// crashes.
  static Future<void> ensureLoaded() async {
    if (_bundled != null) return;
    WidgetsFlutterBinding.ensureInitialized();
    final AssetManifest manifest =
        await AssetManifest.loadFromAssetBundle(rootBundle);
    _bundled = manifest
        .listAssets()
        .where((String p) => p.startsWith('$_iconDir/') ||
            p.startsWith('$_graphicDir/'))
        .toSet();
  }

  /// Test-only override so widget tests can assert the fallback path without a
  /// real bundle. Pass the exact bundled paths (e.g. 'assets/tool-graphics/
  /// fspl.svg'); pass an empty set to simulate "nothing built".
  static void debugSetBundledAssets(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
