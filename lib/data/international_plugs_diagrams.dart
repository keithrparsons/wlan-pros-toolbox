// Convention-based per-face plug-diagram resolution for the International Power
// Plugs reference, with graceful degradation.
//
// BIG-graphic redesign (Keith, 2026-06-08): the page no longer carries one small
// combined concept graphic borrowed from the power-phasing resolver. It now
// renders one LARGE per-type FACE graphic per card (the reusable LargeFaceCard
// pattern the IEC page established) — so this page gets its OWN dedicated
// resolver (cloned from IecConnectorsDiagrams) rather than reusing
// PowerPhasingDiagrams. It exposes the named per-face assets the redesigned
// screen references verbatim, one per IEC World Plugs letter the page surfaces as
// a big card:
//   intl-a, intl-c, intl-d, intl-e, intl-f, intl-g, intl-i, intl-j, intl-l,
//   intl-m.
// (Type B shares the NEMA 5-15 face shown on the NEMA page, so it has no separate
// intl-b face; the Type I single face stands for the whole not-interchangeable
// cluster, with the polarity caveat carried by the prominent warning callout.)
// Charta authors these SVGs in parallel; Larry wires the finals in before merge.
// This resolver is the integration point so the page builds and ships fully
// working WITHOUT blocking on the assets:
//   * each face lives at assets/tool-graphics/<asset-name>.svg, named explicitly
//     (NOT keyed on the catalog tool id — one page carries many face graphics, so
//     the page and tests share one verbatim source of truth and cannot drift).
//   * a missing file NEVER throws and NEVER renders a broken-image box; the card
//     reads as title + specs alone until its face lands.
//
// It mirrors IecConnectorsDiagrams / PowerPhasingDiagrams / ToolAssets (the
// proven manifest-gated resolvers): read the build-time AssetManifest once, cache
// the set of files Flutter actually bundled, and answer `has(assetName)` with
// zero I/O thereafter. The screen gates on `has(...)` before ever handing
// `SvgPicture.asset` a path, so flutter_svg never hits a missing-asset error.
// Until the SVGs land in the bundle, `has(...)` is false and each face card
// renders no graphic — the data page ships fully working today.
//
// The asset names are fixed by the build brief and referenced verbatim by the
// screen; they are exposed as named consts so the screen and tests share one
// source of truth and cannot drift.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves the International Power Plugs per-face diagrams by explicit asset
/// name, gated on the build-time asset manifest so a missing file degrades
/// silently.
class InternationalPlugsDiagrams {
  InternationalPlugsDiagrams._();

  static const String _dir = 'assets/tool-graphics';

  /// Type A face — NEMA 1-15 ungrounded, 120V (US/Canada/Japan/Mexico).
  static const String a = 'intl-a';

  /// Type C face — CEE 7/16 Europlug, 230V unearthed (continental Europe).
  static const String c = 'intl-c';

  /// Type D face — BS 546 5A, 230V (India and ~40 countries).
  static const String d = 'intl-d';

  /// Type E face — CEE 7/5 French, 230V earthed (France, Belgium, Poland).
  static const String e = 'intl-e';

  /// Type F face — CEE 7/4 Schuko, 230V earthed (Germany and most of Europe).
  static const String f = 'intl-f';

  /// Type G face — BS 1363, 230V 13A fused (UK, Ireland, ~50 countries).
  static const String g = 'intl-g';

  /// Type I face — AS/NZS 3112 / GB 2099 / IRAM 2073, 230V (the
  /// not-safely-interchangeable cluster; the polarity caveat rides the warning).
  static const String i = 'intl-i';

  /// Type J face — SEV 1011, 230V (Switzerland, Liechtenstein).
  static const String j = 'intl-j';

  /// Type L face — CEI 23-50, 230V (Italy, Chile).
  static const String l = 'intl-l';

  /// Type M face — BS 546 15A, 230V (South Africa).
  static const String m = 'intl-m';

  /// All per-face asset names, in letter order, for tests and iteration.
  static const List<String> all = <String>[a, c, d, e, f, g, i, j, l, m];

  /// Built diagram paths, populated once from the AssetManifest. `null` until
  /// the first [ensureLoaded] completes; treated as "nothing built" until then.
  static Set<String>? _bundled;

  /// Conventional diagram path for [assetName]. No existence guarantee — gate on
  /// [has] before handing this to `SvgPicture.asset`.
  static String path(String assetName) => '$_dir/$assetName.svg';

  /// `true` only when the build actually bundled this face SVG.
  static bool has(String assetName) =>
      _bundled?.contains(path(assetName)) ?? false;

  /// Load and cache the asset manifest once. Safe to call repeatedly. Call
  /// during app startup so the synchronous [has] checks have data; if it has not
  /// run yet, [has] returns `false` and the face graphic is simply omitted, so a
  /// race only delays a graphic, never crashes.
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

  /// Test-only override so widget tests can assert a face card renders when its
  /// asset is present and is omitted when absent. Pass exact bundled paths (e.g.
  /// 'assets/tool-graphics/intl-g.svg'); pass an empty set for "none built".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
