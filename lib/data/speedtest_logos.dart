// Manifest-gated logo resolver for the Speed Test Services reference page.
//
// Mirrors the `ToolAssets` idiom (lib/data/tool_assets.dart): the screen never
// hands an image widget a path that is not confirmed to be in the build's asset
// bundle, so a missing logo NEVER throws and NEVER renders a broken-image box.
//
// Logos are looked up by a service slug (kebab-case) in two formats, SVG first
// (wordmarks are vector), then PNG:
//   assets/speedtest-logos/<slug>.svg   (preferred — vector wordmark)
//   assets/speedtest-logos/<slug>.png   (raster fallback)
//
// A parallel agent is fetching the logo files, so MOST may be absent when this
// ships. The screen calls [hasLogo] before rendering and falls back to a plain
// name-label when it is false, so the page renders cleanly with zero, some, or
// all logos present.
//
// WORDMARKS ONLY (per the build brief and GL-005): the resolver carries no
// "certified" seal concept — it resolves a single wordmark file per slug. The
// asset producer must supply wordmarks, never endorsement/certification marks.
//
// Like `ToolAssets`, this reads the build-time AssetManifest ONCE and caches the
// set of bundled logo paths; the synchronous `has*` / `pathFor` checks then do
// zero I/O. If the manifest has not loaded yet, `hasLogo` returns false and the
// screen falls back — a race only delays a logo, it never crashes.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// The file format of a resolved logo asset, so the screen picks the right
/// widget (`SvgPicture.asset` for [svg], `Image.asset` for [png]).
enum SpeedtestLogoFormat { svg, png }

/// A resolved logo: the bundle path and its format.
class SpeedtestLogo {
  const SpeedtestLogo(this.path, this.format);

  /// Bundle path confirmed present in the AssetManifest.
  final String path;

  /// SVG or PNG — picks the render widget.
  final SpeedtestLogoFormat format;
}

/// Resolves Speed Test Service wordmark logos by slug, gated on the build-time
/// asset manifest so missing files degrade silently to a name-label fallback.
class SpeedtestLogos {
  SpeedtestLogos._();

  static const String _dir = 'assets/speedtest-logos';

  /// Built logo paths, populated once from the AssetManifest. `null` until the
  /// first [ensureLoaded] completes; treated as "nothing built" until then.
  static Set<String>? _bundled;

  /// Conventional SVG path for [slug]. No existence guarantee — gate on
  /// [hasLogo] / use [logoFor] which returns null when absent.
  static String svgPath(String slug) => '$_dir/$slug.svg';

  /// Conventional PNG path for [slug]. No existence guarantee.
  static String pngPath(String slug) => '$_dir/$slug.png';

  /// `true` when the build bundled an SVG or PNG wordmark for [slug].
  static bool hasLogo(String slug) => logoFor(slug) != null;

  /// The resolved logo for [slug] (SVG preferred over PNG), or `null` when no
  /// wordmark file is bundled — the screen falls back to a name-label.
  static SpeedtestLogo? logoFor(String slug) {
    final Set<String>? bundled = _bundled;
    if (bundled == null) return null;
    final String svg = svgPath(slug);
    if (bundled.contains(svg)) {
      return SpeedtestLogo(svg, SpeedtestLogoFormat.svg);
    }
    final String png = pngPath(slug);
    if (bundled.contains(png)) {
      return SpeedtestLogo(png, SpeedtestLogoFormat.png);
    }
    return null;
  }

  /// Load and cache the logo manifest once. Safe to call repeatedly. Call during
  /// app startup (alongside `ToolAssets.ensureLoaded()`); if it has not run yet,
  /// `hasLogo` returns false and the screen falls back, so a race only delays a
  /// logo, never crashes.
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

  /// Test-only override so widget tests can assert both the rendered-logo and
  /// the missing-logo fallback without a real bundle. Pass the exact bundled
  /// paths (e.g. 'assets/speedtest-logos/ookla.svg'); pass an empty set to
  /// simulate "no logos built yet".
  static void debugSetBundledAssets(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
