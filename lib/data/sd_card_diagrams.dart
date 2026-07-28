// Convention-based concept-graphic resolution for the SD and microSD Cards
// reference, with graceful degradation.
//
// The SD Cards page carries named graphic slots, each rendered by the shared
// LargeGraphic primitive (lib/screens/tools/reference/large_face_card.dart):
//
//   * sd-card-face-marks   — THE HERO, and the one Charta is briefed to build
//                            first. The card face drawn to 24 x 32 mm
//                            proportions with numbered callouts to all seven
//                            mark positions (capacity standard, printed
//                            capacity, bus interface, Speed Class, UHS Speed
//                            Class, Video Speed Class, Application Performance
//                            Class), each with a one-line "this measures X",
//                            plus the headline MB/s figure flagged as NOT a
//                            class. The callout numbers 1 to 7 match
//                            kSdCardMarks in sd_card_reference_data.dart, so
//                            the graphic and the on-screen list read as one
//                            object. The reader's problem here is spatial,
//                            which is why a table cannot do it.
//                            Suggested canvas: 900 x 760 (near-square).
//   * sd-card-contact-rows — standard SD's 9 contacts beside UHS-II's 17, with
//                            pins 7 and 8 relabeled RCLK+ and RCLK- and a note
//                            that they change function. Not yet briefed.
//                            Suggested canvas: 1000 x 560.
//   * sd-card-two-axis     — sustained write against random IOPS, with the class
//                            marks plotted on their respective axes and the 10
//                            MB/s line where they intersect. This one carries
//                            the page's core insight in a single image. Not yet
//                            briefed. Suggested canvas: 900 x 720.
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

/// Resolves the SD Cards concept graphics by explicit asset name, gated on the
/// build-time asset manifest so a missing file degrades silently.
class SdCardDiagrams {
  SdCardDiagrams._();

  static const String _dir = 'assets/tool-graphics';

  /// HERO: the labeled card face with numbered callouts to all seven marks.
  static const String cardFace = 'sd-card-face-marks';

  /// Standard SD's 9 contacts beside UHS-II's 17, with pins 7 and 8 relabeled.
  static const String contactRows = 'sd-card-contact-rows';

  /// Sustained write against random IOPS, with the class marks on their axes.
  static const String twoAxis = 'sd-card-two-axis';

  /// All concept-graphic asset names for this page, in render order, for tests
  /// and iteration.
  static const List<String> all = <String>[
    cardFace,
    contactRows,
    twoAxis,
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
  /// 'assets/tool-graphics/sd-card-face-marks.svg'); pass an empty set for
  /// "none built".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
