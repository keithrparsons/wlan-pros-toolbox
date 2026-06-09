// Convention-based concept-graphic resolution for the Screw Drives & Driver
// Bits reference, with graceful degradation.
//
// The Screw Drives page carries THREE large concept graphics, each rendered by
// the shared LargeGraphic primitive (lib/screens/tools/reference/large_face_card.dart):
//   * screw-drives-faces        — the drive-head FACE silhouettes an installer
//                                 meets daily (slotted, Phillips, Pozidriv, hex,
//                                 Torx, Robertson) laid out as one recognition
//                                 chart.
//   * screw-security-drives     — the tamper/security drive faces (pin-Torx,
//                                 pin-hex, one-way/clutch, tri-wing, spanner) for
//                                 outdoor AP enclosures.
//   * screw-phillips-vs-pozidriv — the highest field-value graphic: a Phillips
//                                 face beside a Pozidriv face, calling out the
//                                 four 45-degree tick marks that distinguish Pozi.
//
// Charta authors these SVGs in parallel; Larry wires the finals in before merge.
// This resolver is the integration point so the page builds and ships fully
// working WITHOUT blocking on the assets:
//   * each face lives at assets/tool-graphics/<asset-name>.svg, named explicitly
//     (NOT keyed on the catalog tool id — one page carries many graphics, so the
//     page and tests share one verbatim source of truth and cannot drift);
//   * a missing file NEVER throws and NEVER renders a broken-image box; the
//     relevant section reads as text alone until its graphic lands.
//
// It mirrors IecConnectorsDiagrams / PowerPhasingDiagrams / ToolAssets (the
// proven manifest-gated resolvers): read the build-time AssetManifest once,
// cache the set of files Flutter actually bundled, and answer `has(assetName)`
// with zero I/O thereafter. The screen gates on `has(...)` before ever handing
// `SvgPicture.asset` a path, so flutter_svg never hits a missing-asset error.
//
// The asset names are fixed by the build brief and referenced verbatim by the
// screen; they are exposed as named consts so the screen and tests share one
// source of truth and cannot drift.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves the Screw Drives concept graphics by explicit asset name, gated on
/// the build-time asset manifest so a missing file degrades silently.
class ScrewDrivesDiagrams {
  ScrewDrivesDiagrams._();

  static const String _dir = 'assets/tool-graphics';

  /// The common drive-head FACE silhouettes (slotted, Phillips, Pozidriv, hex,
  /// Torx, Robertson) as one recognition chart.
  static const String faces = 'screw-drives-faces';

  /// The security / tamper-resistant drive faces (pin-Torx, pin-hex,
  /// one-way/clutch, tri-wing, spanner) for outdoor AP enclosures.
  static const String security = 'screw-security-drives';

  /// The Phillips-vs-Pozidriv distinguisher: a clean Phillips cross beside a
  /// Pozidriv cross with the four 45-degree tick marks called out. The single
  /// highest field-value graphic on the page.
  static const String phillipsVsPozidriv = 'screw-phillips-vs-pozidriv';

  /// All concept-graphic asset names for this page, in render order, for tests
  /// and iteration.
  static const List<String> all = <String>[
    faces,
    phillipsVsPozidriv,
    security,
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
  /// 'assets/tool-graphics/screw-drives-faces.svg'); pass an empty set for
  /// "none built".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
