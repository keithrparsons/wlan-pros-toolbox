// Per-tool concept-graphic header band — GL-003 §8.6.2 / §8.20.7.
//
// The concept graphic is a larger line-diagram that illustrates *what a tool
// does* (the geometry / relationship / sequence), distinct from the §8.6.1
// list icon. It renders as the FIRST child of a tool screen's existing
// `SingleChildScrollView > Column(stretch)`, above the first input card, in a
// container styled exactly like the screen's other cards.
//
// SIZING (reworked 2026-06-08 on Keith's feedback — the old fixed 140/160dp
// band shrank every graphic into a short strip with large side whitespace):
//   The band now FILLS the full content width and derives its height from the
//   graphic's OWN viewBox aspect ratio, so horizontal whitespace collapses to
//   nothing for the common 2:1 / wide graphics. Height is then clamped:
//     * floor `_minBandHeight` so a very wide graphic still reads;
//     * ceiling = `min(viewport * _heightFraction, _maxBandHeight)` so a tall
//       (near-square connector-style) graphic can't eat the screen and the
//       page still scrolls sensibly on a phone.
//   When a tall graphic hits the height ceiling, BoxFit.contain re-letterboxes
//   it (intended — the cap is doing its job); wide graphics fill edge-to-edge.
//   The aspect ratio is parsed from the SVG viewBox once per toolId and cached;
//   until it resolves we assume the dominant 2:1 ratio so the very first frame
//   is already large and correct for the common case, then corrects on settle
//   for the few non-2:1 outliers.
//
// Placement (GL-003 §8.6.2, binding on Felix):
//   * card-styled container: surface1 fill, 12px card radius, 1px decorative
//     border, 8px (--space-xs) internal padding around the SVG (tightened from
//     16px so the graphic uses more of the card)
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
import 'zoomable_graphic.dart';

/// Renders a tool's concept graphic as the §8.6.2 header band, or nothing when
/// the asset is not bundled. Drop it in as the first child of a tool screen's
/// `Column(stretch)`; it sizes itself (full content width, height from the
/// graphic's own aspect ratio, clamped) and degrades to `SizedBox.shrink()`
/// when the tool has no built graphic. Recolors for light per §8.20.7.
class ConceptGraphicBand extends StatelessWidget {
  const ConceptGraphicBand({
    super.key,
    required this.toolId,
    this.isDesktop = false,
  });

  /// Catalog id (kebab-case). Resolves to `assets/tool-graphics/<id>.svg`.
  final String toolId;

  /// Tablet/desktop layout — retained for call-site compatibility and to nudge
  /// the height ceiling up a touch on a large window so a graphic on desktop
  /// reads as generously as on a phone. The dominant driver is now the graphic
  /// aspect ratio and the viewport, not this flag.
  final bool isDesktop;

  // ── New aspect-ratio sizing constants (replace the old 140/160 band) ───────
  // Floor: a very wide graphic (e.g. a 3:1 banner) constrained to the content
  // width is still tall enough to read. Well above the retired 140/160 strip.
  static const double _minBandHeight = 180;

  // Ceiling pieces: the band targets a share of the viewport height, capped by
  // an absolute max so a desktop window does not blow a near-square graphic up
  // past a usable size, and floored above [_minBandHeight] so the page stays
  // scrollable on a phone. 0.40 of viewport keeps the page scrolling sensibly
  // while making the graphic the dominant element above the fold.
  static const double _heightFraction = 0.40;
  static const double _maxBandHeightMobile = 320;
  static const double _maxBandHeightDesktop = 420;

  // Fallback aspect ratio used before the viewBox parse resolves (and if a
  // viewBox is somehow unreadable). 2.0 == the dominant 320×160 author ratio,
  // so the very first frame is already large and right for ~85% of graphics.
  static const double _fallbackAspect = 2.0;

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
      // status success (#5BD68A)  → statusSuccess   #1B7340 (5.4:1)
      '#5BD68A': hex(light.statusSuccess),
      // lime region wash — tint of the darkened lime, alpha nudged 0.08 → 0.10
      // so it stays perceptible on white (§8.20.7). No token field for the
      // wash; it is the textAccent rgb at 0.10 alpha.
      'rgba(162,204,58,0.08)': 'rgba(90,122,28,0.10)',
    };
  }

  // The swap map is theme-independent (light targets only), so build it once.
  static final Map<String, String> _lightSwap = _buildLightSwap();

  /// Applies the §8.20.7 allow-list light-mode swap to an SVG source string,
  /// exactly as the light render path does. The single source of truth for the
  /// §8.20.7 recolor: the concept-graphic band uses it for the §8.6.2 tool
  /// graphics, and the Antenna Connectors per-connector diagram slot reuses it
  /// for its dark-baked diagrams (same scaffold/lime hexes, same light targets),
  /// so the two cannot drift. Recolors scaffold/lime/status and PRESERVES the
  /// §1d canonical data colors and the #1A1A1A anchor dot (they are not in the
  /// allow-list and pass through unchanged).
  static String applyLightSwap(String raw) {
    String swapped = raw;
    _lightSwap.forEach((String darkHex, String lightHex) {
      swapped = swapped.replaceAll(darkHex, lightHex);
    });
    return swapped;
  }

  /// Test alias for [applyLightSwap]. Retained so existing tests that asserted
  /// the swap via the old name keep compiling; new call sites use the public
  /// [applyLightSwap].
  @visibleForTesting
  static String debugApplyLightSwap(String raw) => applyLightSwap(raw);

  /// Test-only: clears the per-toolId SVG-source, aspect, and in-flight-future
  /// caches so one test's bundled-asset setup cannot leak into the next.
  @visibleForTesting
  static void debugClearCaches() {
    _lightSvgCache.clear();
    _aspectCache.clear();
    _swappedFutures.clear();
    _aspectFutures.clear();
  }

  /// Test-only: synchronously seeds the aspect and (optional) swapped-light
  /// source caches for [toolId] with literal values, so a build paints the
  /// SvgPicture without any real bundle I/O — keeping widget tests fully
  /// synchronous (no runAsync, no real-async timeout risk).
  @visibleForTesting
  static void debugSeedCaches(
    String toolId, {
    required double aspect,
    String? lightSvg,
  }) {
    _aspectCache[toolId] = aspect;
    if (lightSvg != null) _lightSvgCache[toolId] = lightSvg;
  }

  // Per-toolId cache of the already-swapped light SVG source, so the string
  // replace runs once per tool, not on every rebuild.
  static final Map<String, String> _lightSvgCache = <String, String>{};

  // Per-toolId cache of the parsed viewBox aspect ratio (width / height). Built
  // once from the SVG source so the height-from-width math has the real shape.
  static final Map<String, double> _aspectCache = <String, double>{};

  // Memoized in-flight futures, keyed by toolId, so a rebuild reuses the SAME
  // Future instance instead of kicking off a fresh load (which would restart
  // the FutureBuilders every frame and never settle).
  static final Map<String, Future<String>> _swappedFutures =
      <String, Future<String>>{};
  static final Map<String, Future<double>> _aspectFutures =
      <String, Future<double>>{};

  /// Parses `width / height` from an SVG source string's `viewBox` (preferred)
  /// or its `width`/`height` attributes. Returns the [_fallbackAspect] when the
  /// shape can't be read, so sizing never produces a zero/NaN height.
  @visibleForTesting
  static double parseAspectRatio(String svg) {
    // viewBox="minX minY width height" — the authoritative intrinsic shape.
    final RegExpMatch? vb =
        RegExp(r'viewBox\s*=\s*"([^"]+)"').firstMatch(svg);
    if (vb != null) {
      final List<String> parts = vb
          .group(1)!
          .trim()
          .split(RegExp(r'[\s,]+'))
          .where((String s) => s.isNotEmpty)
          .toList();
      if (parts.length == 4) {
        final double? w = double.tryParse(parts[2]);
        final double? h = double.tryParse(parts[3]);
        if (w != null && h != null && w > 0 && h > 0) return w / h;
      }
    }
    // Fall back to explicit width/height attributes if no usable viewBox.
    final double? w = _attr(svg, 'width');
    final double? h = _attr(svg, 'height');
    if (w != null && h != null && w > 0 && h > 0) return w / h;
    return _fallbackAspect;
  }

  static double? _attr(String svg, String name) {
    final RegExpMatch? m =
        RegExp('$name\\s*=\\s*"([0-9.]+)').firstMatch(svg);
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  /// Memoized future that loads the asset SVG source, applies the §8.20.7
  /// allow-list swap, caches the result per toolId, and seeds the aspect-ratio
  /// cache from the same source (so we never load the file twice). The Future
  /// itself is memoized so a rebuild reuses it rather than restarting the load.
  Future<String> _loadSwappedSvg() {
    final String warm = _lightSvgCache[toolId] ?? '';
    if (warm.isNotEmpty) return Future<String>.value(warm);
    return _swappedFutures.putIfAbsent(toolId, () async {
      final String cached = _lightSvgCache[toolId] ?? '';
      if (cached.isNotEmpty) return cached;
      final String raw =
          await rootBundle.loadString(ToolAssets.graphicPath(toolId));
      _aspectCache[toolId] ??= parseAspectRatio(raw);
      // Replace on the literal token only. The hex KEYS in the SVGs are
      // uppercase 6-digit; the wash uses the exact authored rgba() string. §1d
      // canonical data hexes and #1A1A1A are not in the map → pass through.
      final String swapped = applyLightSwap(raw);
      _lightSvgCache[toolId] = swapped;
      return swapped;
    });
  }

  /// Memoized future that loads the raw SVG source only to seed the aspect-ratio
  /// cache (dark path, which renders via SvgPicture.asset and never needs the
  /// source otherwise). The Future is memoized so rebuilds reuse it.
  Future<double> _loadAspect() {
    final double? cached = _aspectCache[toolId];
    if (cached != null) return Future<double>.value(cached);
    return _aspectFutures.putIfAbsent(toolId, () async {
      final String raw =
          await rootBundle.loadString(ToolAssets.graphicPath(toolId));
      final double aspect = parseAspectRatio(raw);
      _aspectCache[toolId] = aspect;
      return aspect;
    });
  }

  /// Computes the band height for a given available width, aspect ratio, and
  /// viewport height. Fills the width (`width / aspect`), then clamps to the
  /// floor and the viewport-fraction/absolute ceiling so a tall graphic can't
  /// dominate and the page still scrolls on a phone.
  @visibleForTesting
  static double bandHeightFor({
    required double availableWidth,
    required double aspectRatio,
    required double viewportHeight,
    required bool isDesktop,
  }) {
    final double maxAbsolute =
        isDesktop ? _maxBandHeightDesktop : _maxBandHeightMobile;
    final double ceiling =
        (viewportHeight * _heightFraction).clamp(_minBandHeight, maxAbsolute);
    final double natural =
        aspectRatio > 0 ? availableWidth / aspectRatio : availableWidth;
    return natural.clamp(_minBandHeight, ceiling);
  }

  @override
  Widget build(BuildContext context) {
    // Graceful fallback: no bundled graphic → render nothing, layout unchanged.
    if (!ToolAssets.hasGraphic(toolId)) {
      return const SizedBox.shrink();
    }

    final AppColorScheme colors = context.colors;
    final double viewportHeight = MediaQuery.sizeOf(context).height;

    return ExcludeSemantics(
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        // Tightened from --space-sm (16) to --space-xs (8) so the graphic uses
        // more of the card and reads bigger (Keith's "too much whitespace").
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            // Width available to the SVG inside the card padding.
            final double availableWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
            return _ConceptSvg(
              toolId: toolId,
              isLight: colors.isLight,
              availableWidth: availableWidth,
              viewportHeight: viewportHeight,
              isDesktop: isDesktop,
              aspectFuture: _loadAspect(),
              swappedFuture: colors.isLight ? _loadSwappedSvg() : null,
              // Seeded synchronously when a prior frame already parsed it, so a
              // revisit paints at the exact final size on the first frame.
              seededAspect: _aspectCache[toolId],
            );
          },
        ),
      ),
    );
  }
}

/// Resolves the band height from the graphic's aspect ratio (async-parsed,
/// cached) and renders the SVG at full content width to that height. For light
/// mode it additionally awaits the §8.20.7-swapped source and draws via
/// `SvgPicture.string`; for dark it draws the unmodified asset (dark goldens
/// unaffected). Collapses to nothing on a parse/load failure — the same
/// graceful-degradation contract as before; no broken-image box ever appears.
class _ConceptSvg extends StatelessWidget {
  const _ConceptSvg({
    required this.toolId,
    required this.isLight,
    required this.availableWidth,
    required this.viewportHeight,
    required this.isDesktop,
    required this.aspectFuture,
    required this.swappedFuture,
    required this.seededAspect,
  });

  final String toolId;
  final bool isLight;
  final double availableWidth;
  final double viewportHeight;
  final bool isDesktop;
  final Future<double> aspectFuture;
  final Future<String>? swappedFuture;
  final double? seededAspect;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<double>(
      future: aspectFuture,
      // Until the parse resolves, assume the dominant 2:1 ratio so the first
      // frame is already large and correct for ~85% of graphics; the few
      // non-2:1 outliers re-lay-out one frame later. A revisit is seeded
      // synchronously from the cache so it never flashes.
      initialData: seededAspect ?? ConceptGraphicBand._fallbackAspect,
      builder: (BuildContext context, AsyncSnapshot<double> aspectSnap) {
        final double aspect =
            aspectSnap.data ?? ConceptGraphicBand._fallbackAspect;
        final double bandHeight = ConceptGraphicBand.bandHeightFor(
          availableWidth: availableWidth,
          aspectRatio: aspect,
          viewportHeight: viewportHeight,
          isDesktop: isDesktop,
        );

        final Widget svg;
        if (isLight) {
          svg = _LightConceptSvg(future: swappedFuture!, bandHeight: bandHeight);
        } else {
          // Dark: the in-page render is the unmodified asset (dark goldens
          // unaffected). Wrap it in ZoomableGraphic so a tap opens the §8.6.2
          // full-screen pinch-zoom view, re-rendering the SAME asset large
          // (crisp — vector). The decorative ExcludeSemantics lives on the
          // SvgPicture; ZoomableGraphic adds the labeled zoom button.
          final Widget inPage = SvgPicture.asset(
            ToolAssets.graphicPath(toolId),
            // Fill the width; height is the aspect-driven band height. A wide
            // graphic fills edge-to-edge; a tall one that hit the height
            // ceiling is contained (never cropped — §8.6.2).
            fit: BoxFit.contain,
            width: double.infinity,
            height: bandHeight,
            excludeFromSemantics: true,
            placeholderBuilder: (_) => const SizedBox.shrink(),
          );
          svg = ZoomableGraphic(
            svgBuilder: (BuildContext _, Size canvas) => SvgPicture.asset(
              ToolAssets.graphicPath(toolId),
              fit: BoxFit.contain,
              width: canvas.width,
              height: canvas.height,
              excludeFromSemantics: true,
              placeholderBuilder: (_) => const SizedBox.shrink(),
            ),
            child: inPage,
          );
        }

        return SizedBox(
          height: bandHeight,
          width: double.infinity,
          child: Center(child: svg),
        );
      },
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
        // Wrap the recolored in-page render in ZoomableGraphic; the zoom view
        // re-renders the SAME §8.20.7-swapped source large via SvgPicture.string
        // (crisp — vector), so the zoomed light graphic matches the in-page one
        // exactly and never reverts to a raw lime stroke on white.
        return ZoomableGraphic(
          svgBuilder: (BuildContext _, Size canvas) => SvgPicture.string(
            data,
            fit: BoxFit.contain,
            width: canvas.width,
            height: canvas.height,
            excludeFromSemantics: true,
            placeholderBuilder: (_) => const SizedBox.shrink(),
          ),
          child: SvgPicture.string(
            data,
            fit: BoxFit.contain,
            width: double.infinity,
            height: bandHeight,
            excludeFromSemantics: true,
            placeholderBuilder: (_) => const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
