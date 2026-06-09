// Convention-based connector-diagram resolution for the IEC Power Connectors
// reference, with graceful degradation.
//
// BIG-graphic redesign (Keith, 2026-06-08): the page no longer carries one small
// combined diagram. It now renders one LARGE per-connector FACE graphic per
// card — so this resolver exposes the SIX named per-face assets the redesigned
// screen references verbatim:
//   iec-c5, iec-c7, iec-c13, iec-c15, iec-c19 (the IEC 60320 coupler faces) and
//   iec-60309 (the industrial pin-and-sleeve face).
// Charta authors these SVGs in parallel; Larry wires the finals in before merge.
// This resolver is the integration point so the page builds and ships fully
// working WITHOUT blocking on the assets:
//   * each face lives at assets/tool-graphics/<asset-name>.svg, named explicitly
//     (NOT keyed on the catalog tool id — one page carries many face graphics,
//     so the page and tests share one verbatim source of truth and cannot drift).
//   * a missing file NEVER throws and NEVER renders a broken-image box; the card
//     reads as title + specs + note alone until its face lands.
//
// It mirrors PowerPhasingDiagrams / ConnectorDiagrams / ToolAssets (the proven
// manifest-gated resolvers): read the build-time AssetManifest once, cache the
// set of files Flutter actually bundled, and answer `has(assetName)` with zero
// I/O thereafter. The screen gates on `has(...)` before ever handing
// `SvgPicture.asset` a path, so flutter_svg never hits a missing-asset error.
//
// The asset names are fixed by the build brief and referenced verbatim by the
// screen; they are exposed as named consts so the screen and tests share one
// source of truth and cannot drift. The legacy single-slot `connectors` name is
// retained as a deprecated alias only so any straggler reference keeps compiling.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves the IEC Power Connectors diagram by explicit asset name, gated on
/// the build-time asset manifest so a missing file degrades silently.
class IecConnectorsDiagrams {
  IecConnectorsDiagrams._();

  static const String _dir = 'assets/tool-graphics';

  /// IEC 60320 C1/C2 "shaver/razor" Class-II 2.5A unearthed coupler face
  /// (unpolarized — two contacts, no earth).
  static const String c1 = 'iec-c1';

  /// IEC 60320 C5/C6 "cloverleaf" coupler face (laptop power bricks).
  static const String c5 = 'iec-c5';

  /// IEC 60320 C7/C8 "figure-8" coupler face (AV gear, small electronics).
  static const String c7 = 'iec-c7';

  /// IEC 60320 C13/C14 "PC cord" coupler face (cold-condition, 70 degC).
  static const String c13 = 'iec-c13';

  /// IEC 60320 C15/C16 "kettle cord" coupler face (hot-condition, 120 degC,
  /// notch-keyed).
  static const String c15 = 'iec-c15';

  /// IEC 60320 C19/C20 high-draw coupler face (16 A servers/PDUs).
  static const String c19 = 'iec-c19';

  /// IEC 60309 industrial pin-and-sleeve face (color = voltage band, earth-pin
  /// clock position = keying).
  static const String iec60309 = 'iec-60309';

  /// Legacy single combined-diagram slot. Deprecated by the per-face redesign
  /// (2026-06-08); retained only so any straggler reference keeps compiling. Not
  /// in [all]; the redesigned screen does not render it.
  @Deprecated('Use the per-face assets (c5/c7/c13/c15/c19/iec60309) instead.')
  static const String connectors = 'iec-connectors';

  /// All per-face asset names for this page, in render order, for tests and
  /// iteration. C5, C7, C13, C15, C19 (IEC 60320 faces) then IEC 60309.
  static const List<String> all = <String>[c1, c5, c7, c13, c15, c19, iec60309];

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
  /// 'assets/tool-graphics/iec-connectors.svg'); pass an empty set for "none
  /// built".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
