// Convention-based per-face connector-diagram resolution for the NEMA Connectors
// reference, with graceful degradation.
//
// BIG-graphic redesign (Keith, 2026-06-08): the page no longer carries one small
// combined face plate. It now renders one LARGE per-connector FACE graphic per
// card (the reusable LargeFaceCard pattern the IEC page established) — so this
// resolver exposes the named per-face assets the redesigned screen references
// verbatim, one per common NEMA device type the page surfaces as a big card:
//   nema-5-15, nema-5-20, nema-6-15, nema-6-20, nema-6-50,
//   nema-14-30, nema-14-50, nema-l5-30, nema-l6-30, nema-l14-30, nema-l21-30.
// Charta authors these SVGs in parallel; Larry wires the finals in before merge.
// This resolver is the integration point so the page builds and ships fully
// working WITHOUT blocking on the assets:
//   * each face lives at assets/tool-graphics/<asset-name>.svg, named explicitly
//     (NOT keyed on the catalog tool id — one page carries many face graphics, so
//     the page and tests share one verbatim source of truth and cannot drift).
//   * a missing file NEVER throws and NEVER renders a broken-image box; the card
//     reads as title + specs + note alone until its face lands.
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
// source of truth and cannot drift. The legacy single-plate `facePlate` name is
// retained as a deprecated alias only so any straggler reference keeps compiling.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Resolves the NEMA Connectors per-face diagrams by explicit asset name, gated
/// on the build-time asset manifest so a missing file degrades silently.
class NemaConnectorDiagrams {
  NemaConnectorDiagrams._();

  static const String _dir = 'assets/tool-graphics';

  /// NEMA 5-15 face — 125V 1-phase 15A grounded (the ubiquitous US outlet).
  static const String n515 = 'nema-5-15';

  /// NEMA 5-20 face — 125V 1-phase 20A grounded (T-slot).
  static const String n520 = 'nema-5-20';

  /// NEMA 6-15 face — 250V 1-phase 15A grounded.
  static const String n615 = 'nema-6-15';

  /// NEMA 6-20 face — 250V 1-phase 20A grounded.
  static const String n620 = 'nema-6-20';

  /// NEMA 6-50 face — 250V 1-phase 50A grounded (welders).
  static const String n650 = 'nema-6-50';

  /// NEMA 14-30 face — 125/250V 1-phase split 30A (dryer / range).
  static const String n1430 = 'nema-14-30';

  /// NEMA 14-50 face — 125/250V 1-phase split 50A (range / EV charger).
  static const String n1450 = 'nema-14-50';

  /// NEMA L5-30 face — 125V 1-phase 30A twist-lock.
  static const String l530 = 'nema-l5-30';

  /// NEMA L6-30 face — 250V 1-phase 30A twist-lock.
  static const String l630 = 'nema-l6-30';

  /// NEMA L14-30 face — 125/250V 1-phase split 30A twist-lock.
  static const String l1430 = 'nema-l14-30';

  /// NEMA L21-30 face — 120/208V 3-phase wye 30A twist-lock (4P/5W).
  static const String l2130 = 'nema-l21-30';

  /// NEMA 1-15 face — 125V 1-phase 15A, 2P/2W ungrounded (the polarized
  /// two-blade plug; wider blade = neutral).
  static const String n115 = 'nema-1-15';

  /// NEMA 5-30 face — 125V 1-phase 30A grounded.
  static const String n530 = 'nema-5-30';

  /// NEMA L5-15 face — 125V 1-phase 15A twist-lock.
  static const String l515 = 'nema-l5-15';

  /// NEMA L5-20 face — 125V 1-phase 20A twist-lock.
  static const String l520 = 'nema-l5-20';

  /// NEMA L6-20 face — 250V 1-phase 20A twist-lock.
  static const String l620 = 'nema-l6-20';

  /// NEMA L14-20 face — 125/250V 1-phase split 20A twist-lock.
  static const String l1420 = 'nema-l14-20';

  /// NEMA L21-20 face — 120/208V 3-phase wye 20A twist-lock (4P/5W).
  static const String l2120 = 'nema-l21-20';

  /// NEMA 6-30 face — 250V 1-phase 30A grounded (straight horizontal blades +
  /// D-ground, per Pax WD-6 verification — NOT angled).
  static const String n630 = 'nema-6-30';

  /// California Standard CS8364 face — Non-NEMA 250V 50A 3-phase connector
  /// (female); 3 power (X/Y/Z) + offset ground, no neutral.
  static const String cs8364 = 'nema-cs8364';

  /// California Standard CS8365 face — Non-NEMA 250V 50A 3-phase plug (male);
  /// mating mirror of CS8364.
  static const String cs8365 = 'nema-cs8365';

  /// Legacy single combined face-plate slot. Deprecated by the per-face redesign
  /// (2026-06-08); retained only so any straggler reference keeps compiling. Not
  /// in [all]; the redesigned screen does not render it.
  @Deprecated('Use the per-face assets (n515/.../l2130) instead.')
  static const String facePlate = 'nema-connectors';

  /// All per-face asset names for this page, in render order, for tests and
  /// iteration.
  static const List<String> all = <String>[
    n115,
    n515,
    n520,
    n530,
    l515,
    l520,
    l530,
    n615,
    n620,
    n630,
    n650,
    l620,
    l630,
    n1430,
    n1450,
    l1420,
    l1430,
    l2120,
    l2130,
    cs8364,
    cs8365,
  ];

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
  /// 'assets/tool-graphics/nema-5-15.svg'); pass an empty set for "none built".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
