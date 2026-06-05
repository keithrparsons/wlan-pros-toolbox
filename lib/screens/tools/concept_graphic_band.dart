// Per-tool concept-graphic header band — GL-003 §8.6.2 / §8.20.7.
//
// The concept graphic is a larger line-diagram that illustrates *what a tool
// does* (the geometry / relationship / sequence), distinct from the §8.6.1
// list icon. It renders as the FIRST child of a tool screen's existing
// `SingleChildScrollView > Column(stretch)`, above the first input card, in a
// container styled exactly like the screen's other cards.
//
// Placement (GL-003 §8.6.2, binding on Felix):
//   * card-styled container: surface1 fill, 12px card radius, 1px decorative
//     border, 16px (--space-sm) internal padding around the SVG
//   * band height: 140dp mobile / 160dp tablet-desktop (--app-tool-graphic-
//     band-height), SVG vertically centered, scaled to width, never cropped
//   * caller adds the 24px (--space-md) gap to the first content card, matching
//     the existing card-to-card rhythm
//
// LIGHT-MODE TREATMENT (GL-003 §8.20.7 — Iris spec, Phase 2C):
//   The 60 SVGs are authored DARK-BAKED (§8.6.2) for the #1A1A1A surfaces.
//   `SvgPicture.asset` cannot recolor baked hexes (its colorFilter only touches
//   `currentColor`, which these SVGs do not use). So:
//     * DARK / System-dark: render the unmodified asset via SvgPicture.asset —
//       ZERO change to the dark render (dark goldens unaffected).
//     * LIGHT / System-light: load the SVG source string, apply the §8.20.7
//       ALLOW-LIST hex swap (8 entries — scaffold, muted, lime foreground,
//       faint hatch, three status hues, lime wash), then render via
//       SvgPicture.string.
//   The swap is an explicit allow-list keyed on the known scaffold/lime/status
//   hexes. The five §1d domain-canonical DATA colors (copper #C9A227 and the
//   T568 orange/green/blue/brown pair colors) and the #1A1A1A anchor dot are
//   NOT in the map and pass through UNCHANGED — the color is the information
//   (T568 pinout), so they must survive onto light. A blanket replace would
//   corrupt the pinout data; this never does.
//   The light hexes are sourced from `AppColorScheme.light()` token fields so
//   the map cannot drift from §8.20.1 (same discipline as §8.20.6: no literal
//   hex in widgets, except the dark KEYS which are the baked SVG values).
//   The swapped string is cached per toolId so the replace runs once, not on
//   every rebuild.
//
// Graceful degradation (per the build brief): if the tool has no bundled
// concept graphic — true for most of the ~60 tools until Charta authors them —
// this returns `SizedBox.shrink()`, so the screen layout is unchanged and no
// broken-image box ever appears. The gate is the build-time asset manifest
// (ToolAssets.hasGraphic), so flutter_svg is only ever handed a path that is
// confirmed in the bundle.
//
// Accessibility (GL-003 §8.6.2): the graphic is decorative/illustrative and
// never the sole carrier of meaning — every fact it depicts is also in the
// screen's text (formula card, labeled inputs, result row). It is therefore
// marked decorative for screen readers via `ExcludeSemantics` +
// `excludeFromSemantics: true`; VoiceOver / TalkBack skip it and land on the
// screen title and content. No verbose alt text (that would double the content).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/tool_assets.dart';
import '../../theme/app_color_scheme.dart';
import '../../theme/app_tokens.dart';

/// Renders a tool's concept graphic as the §8.6.2 header band, or nothing when
/// the asset is not bundled. Drop it in as the first child of a tool screen's
/// `Column(stretch)`; it sizes itself and degrades to `SizedBox.shrink()` when
/// the tool has no built graphic. Recolors for light per §8.20.7.
class ConceptGraphicBand extends StatelessWidget {
  const ConceptGraphicBand({
    super.key,
    required this.toolId,
    this.isDesktop = false,
  });

  /// Catalog id (kebab-case). Resolves to `assets/tool-graphics/<id>.svg`.
  final String toolId;

  /// Tablet/desktop layout → 160dp band; mobile → 140dp (§8.6.2 band-height
  /// token). The host screens already compute this from `LayoutBuilder`.
  final bool isDesktop;

  // §8.6.2 --app-tool-graphic-band-height: 140dp mobile / 160dp tablet-desktop.
  static const double _bandHeightMobile = 140;
  static const double _bandHeightDesktop = 160;

  // ── §8.20.7 light-mode swap map ──────────────────────────────────────────
  // Built once from the AppColorScheme.light() token fields. DARK SVG hexes
  // (keys) map to their light counterparts (values). The five §1d canonical
  // data hexes and the #1A1A1A anchor dot are deliberately absent (pass
  // through). Hex KEYS are the literal baked SVG values; the rgba wash uses the
  // exact authored string. Source the light values from tokens, not literals,
  // so the map cannot drift from §8.20.1.
  static Map<String, String> _buildLightSwap() {
    final AppColorScheme light = AppColorScheme.light();
    String hex(Color c) {
      // 0xAARRGGBB → "#RRGGBB" (the SVGs use uppercase 6-digit hex).
      final int rgb = c.toARGB32() & 0x00FFFFFF;
      return '#${rgb.toRadixString(16).toUpperCase().padLeft(6, '0')}';
    }

    return <String, String>{
      // scaffold (#E5E5E5)        → textSecondary  #4A4A4A (9.0:1)
      '#E5E5E5': hex(light.textSecondary),
      // muted geometry (#9C9C9C)  → textTertiary   #646464 (5.7:1)
      '#9C9C9C': hex(light.textTertiary),
      // lime foreground (#A2CC3A) → textAccent      #5A7A1C (§8.20.2 lime split)
      '#A2CC3A': hex(light.textAccent),
      // faint hatch (#3A3A3A)     → border          #E2E1E2 (decorative hairline)
      '#3A3A3A': hex(light.border),
      // status danger (#F26E6E)   → statusDanger    #C62D2D (5.4:1)
      '#F26E6E': hex(light.statusDanger),
      // status warning (#E0A23A)  → statusWarning   #8A5A00 bronze (6.0:1)
      '#E0A23A': hex(light.statusWarning),
      // status success (#5BD68A)  → statusSuccess   #1E7E45 (5.2:1)
      '#5BD68A': hex(light.statusSuccess),
      // lime region wash — tint of the darkened lime, alpha nudged 0.08 → 0.10
      // so it stays perceptible on white (§8.20.7). No token field for the
      // wash; it is the textAccent rgb at 0.10 alpha.
      'rgba(162,204,58,0.08)': 'rgba(90,122,28,0.10)',
    };
  }

  // The swap map is theme-independent (light targets only), so build it once.
  static final Map<String, String> _lightSwap = _buildLightSwap();

  /// Test-only: applies the §8.20.7 allow-list swap to an SVG source string,
  /// exactly as the light render path does. Lets a unit test assert the swap
  /// recolors scaffold/lime/status and PRESERVES the §1d canonical data colors
  /// and the #1A1A1A anchor dot, without needing a real asset bundle.
  @visibleForTesting
  static String debugApplyLightSwap(String raw) {
    String swapped = raw;
    _lightSwap.forEach((String darkHex, String lightHex) {
      swapped = swapped.replaceAll(darkHex, lightHex);
    });
    return swapped;
  }

  // Per-toolId cache of the already-swapped light SVG source, so the string
  // replace runs once per tool, not on every rebuild.
  static final Map<String, String> _lightSvgCache = <String, String>{};

  /// Loads the asset SVG source and applies the §8.20.7 allow-list swap, caching
  /// the result per toolId. Returns null until the async load completes.
  Future<String> _loadSwappedSvg() async {
    final String cached = _lightSvgCache[toolId] ?? '';
    if (cached.isNotEmpty) return cached;
    final String raw = await rootBundle.loadString(ToolAssets.graphicPath(toolId));
    // Replace on the literal token only. The hex KEYS in the SVGs are uppercase
    // 6-digit; the wash uses the exact authored rgba() string. §1d canonical
    // data hexes and #1A1A1A are not in the map → pass through.
    final String swapped = debugApplyLightSwap(raw);
    _lightSvgCache[toolId] = swapped;
    return swapped;
  }

  @override
  Widget build(BuildContext context) {
    // Graceful fallback: no bundled graphic → render nothing, layout unchanged.
    if (!ToolAssets.hasGraphic(toolId)) {
      return const SizedBox.shrink();
    }

    final AppColorScheme colors = context.colors;
    final double bandHeight =
        isDesktop ? _bandHeightDesktop : _bandHeightMobile;

    // DARK / System-dark: render the unmodified asset, byte-for-byte as before
    // (dark goldens unaffected). LIGHT: load + swap + render via string.
    final Widget svg = colors.isLight
        ? _LightConceptSvg(
            future: _loadSwappedSvg(),
            bandHeight: bandHeight,
          )
        : SvgPicture.asset(
            ToolAssets.graphicPath(toolId),
            // Scale to width, capped at band height, never crop (§8.6.2).
            fit: BoxFit.contain,
            width: double.infinity,
            height: bandHeight,
            // Decorative — AT skips it (§8.6.2 a11y rule 2).
            excludeFromSemantics: true,
            // A bundled-but-unparseable SVG should never surface a broken box
            // either — collapse to nothing, same as a missing asset.
            placeholderBuilder: (_) => const SizedBox.shrink(),
          );

    return ExcludeSemantics(
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: SizedBox(
          height: bandHeight,
          width: double.infinity,
          child: Center(child: svg),
        ),
      ),
    );
  }
}

/// Light-mode concept-graphic render: awaits the swapped SVG source, then draws
/// it with `SvgPicture.string`. Collapses to nothing while loading or on any
/// parse failure — same graceful-degradation contract as the dark asset path,
/// so no broken-image box or layout jump ever appears.
class _LightConceptSvg extends StatelessWidget {
  const _LightConceptSvg({
    required this.future,
    required this.bandHeight,
  });

  final Future<String> future;
  final double bandHeight;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<String> snap) {
        final String? data = snap.data;
        if (data == null || data.isEmpty) {
          // Loading or failed — render nothing (no broken box, no jump).
          return const SizedBox.shrink();
        }
        return SvgPicture.string(
          data,
          fit: BoxFit.contain,
          width: double.infinity,
          height: bandHeight,
          excludeFromSemantics: true,
          placeholderBuilder: (_) => const SizedBox.shrink(),
        );
      },
    );
  }
}
