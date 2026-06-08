// Convention-based connector-diagram resolution for the IEC Power Connectors
// reference, with graceful degradation.
//
// The IEC Power Connectors reference page leaves ONE named graphic slot — a
// later graphics pass adds connector-face diagrams (the C13/C14 vs C15/C16
// keying notch, the IEC 60309 clock-position earth-pin layout). Charta authors
// that SVG in parallel; Larry wires the final in before merge. This resolver is
// the integration point so the page builds and ships fully working WITHOUT
// blocking on the asset:
//   * the diagram lives at assets/tool-graphics/<asset-name>.svg, named
//     explicitly (NOT keyed on the catalog tool id, so the page and tests share
//     one verbatim source of truth and cannot drift).
//   * a missing file NEVER throws and NEVER renders a broken-image box.
//
// It mirrors PowerPhasingDiagrams / ConnectorDiagrams / ToolAssets (the proven
// manifest-gated resolvers): read the build-time AssetManifest once, cache the
// set of files Flutter actually bundled, and answer `has(assetName)` with zero
// I/O thereafter. The screen gates on `has(...)` before ever handing
// `SvgPicture.asset` a path, so flutter_svg never hits a missing-asset error.
// Until the SVG lands in the bundle, `has(...)` is false and the diagram band
// renders nothing — the data page (the tables) ships fully working today.
//
// The asset name is fixed by the build brief and referenced verbatim by the
// screen; it is exposed as a named const so the screen and tests share one
// source of truth and cannot drift.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves the IEC Power Connectors diagram by explicit asset name, gated on
/// the build-time asset manifest so a missing file degrades silently.
class IecConnectorsDiagrams {
  IecConnectorsDiagrams._();

  static const String _dir = 'assets/tool-graphics';

  /// The single connector-face diagram for this page (IEC 60320 keying notch +
  /// IEC 60309 clock-position earth pin). One named slot; a later graphics pass.
  static const String connectors = 'iec-connectors';

  /// All diagram asset names for this page, for tests and iteration. One entry.
  static const List<String> all = <String>[connectors];

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
