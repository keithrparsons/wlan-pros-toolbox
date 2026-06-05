// Convention-based per-connector diagram resolution with graceful degradation.
//
// The Antenna Connectors reference is designed to accept per-connector SVG line
// diagrams (RP-SMA-vs-SMA cutaway, RP-TNC-vs-TNC, N-Type, DART, U.FL/MHF, the
// snap-on family) WITHOUT blocking on them. Charta authors these later and Larry
// wires the final SVGs in before merge. This resolver is the integration point:
//   * diagrams live at assets/connector-diagrams/<connector-id>.svg, keyed on
//     the connector's stable catalog id (e.g. `rp-sma`, `dart`, `ufl`).
//   * a missing file NEVER throws and NEVER renders a broken-image box.
//
// It mirrors ToolAssets (the proven per-tool icon/graphic resolver): read the
// build-time AssetManifest once, cache the set of files Flutter actually
// bundled, and answer `has(id)` with zero I/O thereafter. The screen gates on
// `has(id)` before ever handing `SvgPicture.asset` a path, so flutter_svg never
// hits a missing-asset error. Until the SVGs land in the bundle (and pubspec),
// `has(id)` is false for every connector and the diagram slot renders nothing —
// the data screen ships fully working today.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves per-connector diagram SVGs by connector id, gated on the build-time
/// asset manifest so missing files degrade silently.
class ConnectorDiagrams {
  ConnectorDiagrams._();

  static const String _dir = 'assets/connector-diagrams';

  /// Built diagram paths, populated once from the AssetManifest. `null` until
  /// the first [ensureLoaded] completes; treated as "nothing built" until then.
  static Set<String>? _bundled;

  /// Conventional diagram path for [connectorId]. No existence guarantee — gate
  /// on [has] before handing this to `SvgPicture.asset`.
  static String path(String connectorId) => '$_dir/$connectorId.svg';

  /// `true` only when the build actually bundled this connector's diagram SVG.
  static bool has(String connectorId) =>
      _bundled?.contains(path(connectorId)) ?? false;

  /// Load and cache the asset manifest once. Safe to call repeatedly. Call
  /// during app startup so the synchronous [has] checks have data; if it has
  /// not run yet, [has] returns `false` and the diagram slot is simply omitted,
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

  /// Test-only override so widget tests can assert the diagram slot renders
  /// when present and is omitted when absent. Pass exact bundled paths (e.g.
  /// 'assets/connector-diagrams/rp-sma.svg'); pass an empty set for "none".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
