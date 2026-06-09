// Convention-based regulator-logo resolution for the Regulatory Domains
// reference page, with graceful degradation.
//
// Each jurisdiction row in the Regulatory Domains screen wants its regulator's
// logo. Mack is fetching the logo files in parallel; this resolver is the
// integration seam so the page builds and ships FULLY WORKING without blocking
// on the assets:
//   * each logo lives at assets/regulator-logos/<key>.svg, keyed
//     `regulator-<abbrev-lowercased>` (see RegulatoryDomain.logoKey), with a
//     short jurisdiction suffix where an abbreviation collides (e.g.
//     regulator-tra-om vs regulator-tra-bh, regulator-ncc-tw vs
//     regulator-ncc-ng) so two regulators that share an abbreviation never
//     collide on one asset.
//   * a missing file NEVER throws and NEVER renders a broken-image box; the row
//     degrades to a styled abbreviation badge instead. The page reads fully as
//     badge + jurisdiction + regulator + link + docs + notes until each logo
//     lands.
//
// It mirrors IecConnectorsDiagrams / PowerPhasingDiagrams / ToolAssets (the
// proven manifest-gated resolvers): read the build-time AssetManifest once,
// cache the set of files Flutter actually bundled, and answer `has(key)` with
// zero I/O thereafter. The screen gates on `has(...)` before ever handing
// `SvgPicture.asset` a path, so flutter_svg never hits a missing-asset error.
//
// Supports both .svg and .png logo files: official regulator logos arrive in
// mixed formats. `has(key)` is true when EITHER extension is bundled; `path(key)`
// returns the bundled path (preferring SVG when both exist), or null when none
// is bundled — the screen treats null as "show the badge".

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves a regulator logo by its `regulator-<abbrev>` key, gated on the
/// build-time asset manifest so a missing file degrades silently to a badge.
class RegulatoryLogos {
  RegulatoryLogos._();

  static const String _dir = 'assets/regulator-logos';

  /// The extensions checked, in preference order. SVG first (vector, crisp at
  /// any badge size), PNG as the fallback for logos only available as raster.
  static const List<String> _exts = <String>['svg', 'png'];

  /// Built logo paths, populated once from the AssetManifest. `null` until the
  /// first [ensureLoaded] completes; treated as "nothing built" until then, so a
  /// race only delays a logo (badge shows meanwhile), never crashes.
  static Set<String>? _bundled;

  /// Conventional candidate paths for [key], in preference order (svg, png). No
  /// existence guarantee — use [has] / [path] which gate on the manifest.
  static List<String> candidatePaths(String key) =>
      <String>[for (final String ext in _exts) '$_dir/$key.$ext'];

  /// `true` only when the build actually bundled a logo (any supported
  /// extension) for [key].
  static bool has(String key) {
    final Set<String>? bundled = _bundled;
    if (bundled == null) return false;
    for (final String candidate in candidatePaths(key)) {
      if (bundled.contains(candidate)) return true;
    }
    return false;
  }

  /// The bundled logo path for [key], preferring SVG when both are present, or
  /// `null` when no logo is bundled (the screen shows the abbreviation badge).
  static String? path(String key) {
    final Set<String>? bundled = _bundled;
    if (bundled == null) return null;
    for (final String candidate in candidatePaths(key)) {
      if (bundled.contains(candidate)) return candidate;
    }
    return null;
  }

  /// `true` when the bundled logo for [key] is an SVG (render with
  /// `SvgPicture.asset`); `false` for a PNG or no logo (render with
  /// `Image.asset`, or the badge when [path] is null).
  static bool isSvg(String key) => path(key)?.endsWith('.svg') ?? false;

  /// Load and cache the asset manifest once. Safe to call repeatedly. Call
  /// during app startup (RegulatoryLogos.ensureLoaded() in main.dart) so the
  /// synchronous [has] / [path] checks have data; if it has not run yet, [has]
  /// returns `false` and the row simply shows its abbreviation badge, so a race
  /// only delays a logo, never crashes.
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

  /// Test-only override so widget tests can assert the logo slot renders when a
  /// logo is present and degrades to the badge when absent. Pass exact bundled
  /// paths (e.g. 'assets/regulator-logos/regulator-fcc.svg'); pass an empty set
  /// for "none built".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
