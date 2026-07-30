// Convention-based concept-graphic resolution for the Batteries reference, with
// graceful degradation.
//
// The Batteries page carries named graphic slots, each rendered by the shared
// LargeGraphic primitive (lib/screens/tools/reference/large_face_card.dart):
//
//   * battery-code-exploded  — THE HERO, and the one Charta is briefed to build
//                              first. CR2032 split into its labeled parts (C =
//                              lithium manganese dioxide, R = round, 20 =
//                              20.0 mm diameter, 32 = 3.2 mm high) beside a
//                              cross-section that shows the 20.0 mm and 3.2 mm
//                              as real measurements, with the LR44 catalog-
//                              number counter-case set against it. This is a
//                              spatial problem a table cannot solve, which is
//                              why it is a graphic and not another row.
//                              Suggested canvas: 960 x 720 (4:3 landscape).
//   * battery-size-ladder    — the N / AAAA / AAA / AA / A / B / C / D
//                              silhouette drawn to scale, with A and B grayed
//                              and captioned "not retail". The grayed gaps do
//                              more work than a paragraph. Not yet briefed.
//                              Suggested canvas: 1200 x 480 (5:2 landscape).
//   * battery-discharge-curves — alkaline against NiMH on one axis, to make the
//                              flat-plateau fuel-gauge point visually. Not yet
//                              briefed. Suggested canvas: 960 x 600.
//
// This resolver is the integration point so the page builds and ships fully
// working WITHOUT blocking on the assets:
//   * each graphic lives at assets/tool-graphics/<asset-name>.svg, named
//     explicitly (NOT keyed on the catalog tool id — the page carries more than
//     one graphic, so the page and its tests share one verbatim source of truth
//     and cannot drift);
//   * a missing file NEVER throws and NEVER renders a broken-image box; the
//     relevant section reads as text alone until its graphic lands.
//
// It mirrors ScrewDrivesDiagrams / IecConnectorsDiagrams / ToolAssets (the
// proven manifest-gated resolvers): read the build-time AssetManifest once,
// cache the set of files Flutter actually bundled, and answer `has(assetName)`
// with zero I/O thereafter. The screen gates on `has(...)` before ever handing
// `SvgPicture.asset` a path, so flutter_svg never hits a missing-asset error.
//
// AUTHORING NOTE FOR THE GRAPHICS PASS (GL-003 section 8.20.7): author the SVGs
// DARK-BAKED on the swap-list hexes so the light-mode recolor path works with no
// extra asset: #E5E5E5 scaffold, #9C9C9C muted geometry, #A1CC3A lime
// foreground, #3A3A3A faint hatch, #F26E6E / #E0A23A / #5BD68A status hues. Any
// other hex passes through unchanged into light mode, so use one only where the
// color IS the data.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves the Batteries concept graphics by explicit asset name, gated on the
/// build-time asset manifest so a missing file degrades silently.
class BatteryDiagrams {
  BatteryDiagrams._();

  static const String _dir = 'assets/tool-graphics';

  /// HERO: the CR2032 code exploded into its labeled parts, with a cross-section
  /// showing 20.0 mm and 3.2 mm as real measurements, and LR44 shown beside it
  /// as the catalog-number counter-case.
  static const String codeExploded = 'battery-code-exploded';

  /// The size ladder drawn to scale, with A and B grayed as "not retail".
  static const String sizeLadder = 'battery-size-ladder';

  /// Alkaline against NiMH discharge curves on one axis.
  static const String dischargeCurves = 'battery-discharge-curves';

  /// All concept-graphic asset names for this page, in render order, for tests
  /// and iteration.
  static const List<String> all = <String>[
    codeExploded,
    sizeLadder,
    dischargeCurves,
  ];

  /// Built diagram paths, populated once from the AssetManifest. `null` until
  /// the first [ensureLoaded] completes; treated as "nothing built" until then.
  static Set<String>? _bundled;

  /// Conventional diagram path for [assetName]. No existence guarantee — gate on
  /// [has] before handing this to `SvgPicture.asset`.
  static String path(String assetName) => '$_dir/$assetName.svg';

  /// `true` only when the build actually bundled this graphic SVG.
  static bool has(String assetName) =>
      _bundled?.contains(path(assetName)) ?? false;

  /// Load and cache the asset manifest once. Safe to call repeatedly. Call
  /// during app startup so the synchronous [has] checks have data; if it has not
  /// run yet, [has] returns `false` and the graphic is simply omitted, so a race
  /// only delays a graphic, never crashes.
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

  /// Test-only override so widget tests can assert a graphic renders when
  /// present and is omitted when absent. Pass exact bundled paths (e.g.
  /// 'assets/tool-graphics/battery-code-exploded.svg'); pass an empty set for
  /// "none built".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
