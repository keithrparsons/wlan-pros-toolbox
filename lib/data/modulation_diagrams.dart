// Convention-based resolution for the eight Modulation reference diagrams, with
// graceful degradation.
//
// These are Vera-passed, DARK-BAKED RASTER cards (white WLAN Pros logo on the §8
// dark canvas): six constellation diagrams (BPSK, QPSK, 16/64/256/1024-QAM), an
// Error Vector Magnitude explainer, and an order -> bits -> SNR/EVM summary
// capstone. They form the visual body of the Modulation Quick Reference screen.
//
// Unlike the §8.6.2 SVG concept graphics and the Antenna Fundamentals SVGs,
// these are PRE-RENDERED PNGs: they cannot take the §8.20.7 runtime light-mode
// per-mark color swap (you cannot recolor a raster's individual strokes). They
// are therefore presented on an ALWAYS-DARK surface card in both themes — the
// #1A1A1A canvas they were authored against (§8.6.2) — so they never read
// inverted on a light canvas. The call site (DarkRasterDiagramCard) owns that
// always-dark backing; this resolver only answers "is the file bundled?".
//
// Mirrors ThroughputWhereDiagram / ConnectorDiagrams / ToolAssets (the proven
// per-asset resolvers): read the AssetManifest once, cache the set of files
// Flutter actually bundled, and answer `isBundled(slug)` with zero I/O
// thereafter. The screen gates on `isBundled` before ever handing `Image.asset`
// a path, so a missing or unbundled file NEVER throws and NEVER renders a
// broken-image box — the screen's intro and every other card still read.

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// One modulation diagram: its stable slug (asset filename stem) and the human
/// title spoken to screen readers / shown as the zoom label.
class ModulationDiagram {
  const ModulationDiagram({required this.slug, required this.title});

  /// Asset filename stem, e.g. `constellation-16-qam`. Resolves to
  /// `assets/tool-diagrams/modulation/<slug>.png`.
  final String slug;

  /// Spoken / zoom-view label for this diagram, e.g. "16-QAM constellation".
  final String title;
}

/// Resolves the eight bundled Modulation reference diagram PNGs, gated on the
/// build-time asset manifest so a missing file degrades silently.
class ModulationDiagrams {
  ModulationDiagrams._();

  static const String _dir = 'assets/tool-diagrams/modulation';

  /// The ordered diagram set rendered on the Modulation screen. Order is the
  /// teaching order: rising constellation density, then the EVM explainer, then
  /// the summary capstone. Each `title` is the screen-reader / zoom label.
  static const List<ModulationDiagram> all = <ModulationDiagram>[
    ModulationDiagram(slug: 'constellation-bpsk', title: 'BPSK constellation'),
    ModulationDiagram(slug: 'constellation-qpsk', title: 'QPSK constellation'),
    ModulationDiagram(
        slug: 'constellation-16-qam', title: '16-QAM constellation'),
    ModulationDiagram(
        slug: 'constellation-64-qam', title: '64-QAM constellation'),
    ModulationDiagram(
        slug: 'constellation-256-qam', title: '256-QAM constellation'),
    ModulationDiagram(
        slug: 'constellation-1024-qam', title: '1024-QAM constellation'),
    ModulationDiagram(
        slug: 'evm-error-vector-magnitude',
        title: 'Error Vector Magnitude explainer'),
    ModulationDiagram(
        slug: 'summary-order-bits-snr-evm',
        title: 'Modulation order, bits per symbol, SNR and EVM summary'),
  ];

  /// Conventional asset path for [slug]. No existence guarantee — gate on
  /// [isBundled] before handing this to `Image.asset`.
  static String pathFor(String slug) => '$_dir/$slug.png';

  /// Built diagram paths, populated once from the AssetManifest. `null` until
  /// the first [ensureLoaded] completes; treated as "nothing built" until then.
  static Set<String>? _bundled;

  /// `true` only when the build actually bundled this diagram's PNG. Gate on
  /// this before handing [pathFor] to `Image.asset`.
  static bool isBundled(String slug) =>
      _bundled?.contains(pathFor(slug)) ?? false;

  /// Load and cache the asset manifest once. Safe to call repeatedly. Call
  /// during app startup so the synchronous [isBundled] check has data; if it has
  /// not run yet, [isBundled] returns `false` and the diagram card is simply
  /// omitted, so a race only delays a diagram, never crashes.
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

  /// Test-only override so widget tests can assert the gallery renders when the
  /// assets are present and omits cards when absent. Pass the exact bundled
  /// paths, or an empty set for "nothing built".
  static void debugSetBundled(Set<String> paths) {
    _bundled = paths;
  }

  /// Test-only reset back to the unloaded state.
  static void debugReset() {
    _bundled = null;
  }
}
