// Convention-based concept-graphic resolution for the Fiber Optic reference
// page's CONNECTORS + POLISH half, with graceful degradation.
//
// The Fiber Optic page (fiber_optic_screen.dart) covers fiber TYPES, jacket
// COLOR codes, and distances. The 2026-06-08 extension adds the missing half —
// CONNECTORS and POLISH / endface — and renders three LARGE concept graphics
// through the shared LargeGraphic primitive. This resolver exposes the THREE
// named assets that the extended screen references verbatim:
//   fiber-connectors-faces  — LC / SC / ST / FC / MPO form-factor silhouettes.
//   fiber-apc-endface       — the APC 8-degree angled-ferrule endface diagram.
//   fiber-two-color-systems — jacket vs connector-body color split (green/aqua
//                             collision called out).
// Charta authors these SVGs in parallel; Larry wires the finals in before merge.
// This resolver is the integration point so the page builds and ships fully
// working WITHOUT blocking on the assets:
//   * each graphic lives at assets/tool-graphics/<asset-name>.svg, named
//     explicitly (NOT keyed on the catalog tool id — one page carries several
//     graphics), so the page and tests share one verbatim source of truth and
//     cannot drift.
//   * a missing file NEVER throws and NEVER renders a broken-image box; the
//     section reads as its tables alone until the graphic lands.
//
// It mirrors IecConnectorsDiagrams / PowerPhasingDiagrams / ToolAssets (the
// proven manifest-gated resolvers): read the build-time AssetManifest once,
// cache the set of files Flutter actually bundled, and answer `has(assetName)`
// with zero I/O thereafter. The screen gates on `has(...)` before ever handing
// `SvgPicture.asset` a path, so flutter_svg never hits a missing-asset error.
//
// SELF-LOADING NOTE: unlike the IEC/NEMA resolvers, this one is NOT wired into
// main.dart's startup ensureLoaded() chain (that file is central and off-limits
// for this extension). The extended screen therefore kicks off [ensureLoaded]
// itself on first build and rebuilds when it resolves (a FutureBuilder), so the
// synchronous [has] checks have data without a startup-chain edit. A race only
// delays a graphic by one frame, never crashes — `has` returns `false` until
// the manifest is read, exactly the graceful-degradation contract above.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves the Fiber Optic page's connector/polish concept graphics by explicit
/// asset name, gated on the build-time asset manifest so a missing file degrades
/// silently.
class FiberConnectorsDiagrams {
  FiberConnectorsDiagrams._();

  static const String _dir = 'assets/tool-graphics';

  /// LC / SC / ST / FC / MPO form-factor silhouettes — the #1 reason an
  /// installer opens the page (form-factor recognition).
  static const String connectorFaces = 'fiber-connectors-faces';

  /// The APC 8-degree angled-ferrule endface diagram — explains WHY APC reaches
  /// the lowest return loss and WHY it can never mate a flat UPC ferrule.
  static const String apcEndface = 'fiber-apc-endface';

  /// The two-color-systems split: cable-jacket color (TIA-598-D) vs
  /// connector-body color (TIA-568/598 convention), with the green/aqua
  /// collision called out so the page never conflates the two.
  static const String twoColorSystems = 'fiber-two-color-systems';

  /// All concept-graphic asset names for this page, in render order, for tests
  /// and iteration.
  static const List<String> all = <String>[
    connectorFaces,
    apcEndface,
    twoColorSystems,
  ];

  /// Built graphic paths, populated once from the AssetManifest. `null` until
  /// the first [ensureLoaded] completes; treated as "nothing built" until then.
  static Set<String>? _bundled;

  /// In-flight load, so concurrent first-frame callers share one manifest read
  /// instead of racing several. Cleared on [debugReset].
  static Future<void>? _loading;

  /// Conventional graphic path for [assetName]. No existence guarantee — gate on
  /// [has] before handing this to `SvgPicture.asset`.
  static String path(String assetName) => '$_dir/$assetName.svg';

  /// `true` only when the build actually bundled this graphic SVG.
  static bool has(String assetName) =>
      _bundled?.contains(path(assetName)) ?? false;

  /// `true` once the manifest has been read (whether or not any graphic was
  /// found). Lets the screen show its tables immediately and fold a graphic in
  /// only after the one-shot load resolves.
  static bool get isLoaded => _bundled != null;

  /// Load and cache the asset manifest once. Safe to call repeatedly and from
  /// several callers at once (they share one in-flight future). Because this
  /// resolver is not in main.dart's startup chain, the extended screen awaits
  /// this itself on first build; if it has not run yet, [has] returns `false`
  /// and the graphic is simply omitted, so a race only delays a graphic.
  static Future<void> ensureLoaded() {
    if (_bundled != null) return Future<void>.value();
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    WidgetsFlutterBinding.ensureInitialized();
    final AssetManifest manifest =
        await AssetManifest.loadFromAssetBundle(rootBundle);
    _bundled = manifest
        .listAssets()
        .where((String p) => p.startsWith('$_dir/'))
        .toSet();
    _loading = null;
  }

  /// Test-only override so widget tests can assert a section renders its graphic
  /// when present and omits it when absent. Pass exact bundled paths (e.g.
  /// 'assets/tool-graphics/fiber-apc-endface.svg'); pass an empty set for "none
  /// built".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
    _loading = null;
  }
}
