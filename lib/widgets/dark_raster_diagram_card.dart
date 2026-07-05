// Reusable tap-to-zoom card for a DARK-BAKED RASTER reference diagram — the
// raster sibling of ZoomableGraphic (which is SVG-only via an svgBuilder).
//
// WHY A SEPARATE WIDGET: the §8.6.2 SVG concept graphics recolor for light via
// the §8.20.7 runtime per-mark swap. A pre-rendered PNG cannot — you cannot
// recolor a raster's individual strokes. Vera-passed dark-baked diagrams (a
// white WLAN Pros logo on the §8 #1A1A1A canvas) are therefore mounted on an
// ALWAYS-DARK surface card in BOTH themes — the dark surface they were authored
// against — so they never read inverted on a light canvas. The always-dark
// backing comes from [AppColorScheme.dark], the same "render on the always-dark
// scrim/chip" idiom the zoom badge and the logo chips already use.
//
// PROVENANCE: the geometry and the always-dark + tap-to-zoom behavior are lifted
// from `ThroughputWhereDiagramCard` (speedtest_services_screen.dart), which
// pioneered the dark-baked-PNG-on-the-Speed-Test-screen pattern. This widget
// generalizes that one-off into a parameterized card (asset path, aspect ratio,
// label, optional caption) so a multi-diagram gallery — the Modulation
// reference's eight cards — reuses one implementation instead of cloning the
// 240-line one-off eight times.
//
// INTERACTION: tap (or keyboard-activate) the diagram to open a full-screen
// pinch-zoom + pan view (raster `InteractiveViewer`, minScale 1, maxScale 5) —
// these detail-dense diagrams are hard to read inline on a phone. The whole
// plate is the tap target; a magnifier + "Tap to enlarge" hint sits in a row
// BELOW the plate (never overlaid on it). These full-bleed reference plates bake
// a logo / eyebrow / footer marks into every corner, so an on-plate badge always
// collides with baked art; keeping the affordance off the image removes the
// collision by construction for every plate the set clones.
//
// A11Y (§8.6.2): the image itself is decorative (every fact it depicts is in the
// screen's prose and in the diagram's own baked-in labels, which a screen reader
// cannot read out of a raster anyway), so it is `ExcludeSemantics` /
// `excludeFromSemantics`. The TAP TARGET is a real labeled
// `Semantics(button: true, label: 'Zoom <name>')` so screen readers announce an
// operable control and Enter/Space activate it. An optional caption below
// carries a one-line teaching point as real text.
//
// GRACEFUL DEGRADATION: the call site gates on its resolver's `isBundled` before
// constructing this card, so it is only ever handed a path confirmed in the
// bundle; the inner `Image.asset` additionally carries an `errorBuilder` that
// collapses to `SizedBox.shrink()` so a decode fault never shows a broken box.
//
// Tokens: AppColorScheme.dark surfaces/scrim/border/text, AppRadius, AppSpacing,
// AppMotion only. No hardcoded color, size, spacing, or duration literal
// (GL-003 §4 / §8.1).

import 'package:flutter/material.dart';

import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';

/// A dark-baked raster reference diagram, mounted on an always-dark card with
/// tap-to-zoom. Pass the bundled [assetPath], the image's true [aspectRatio]
/// (width / height) so the inline render is the right shape without measuring,
/// a [semanticLabel] for the zoom tap target, and an optional one-line
/// [caption] shown beneath the card on the live theme surface.
class DarkRasterDiagramCard extends StatelessWidget {
  const DarkRasterDiagramCard({
    super.key,
    required this.assetPath,
    required this.aspectRatio,
    required this.semanticLabel,
    this.caption,
  });

  /// Bundled asset path, e.g. `assets/tool-diagrams/modulation/<slug>.png`.
  final String assetPath;

  /// The diagram's true aspect ratio (width / height). Pinned by the call site
  /// so the inline card is the right shape with no letterbox gutters and no
  /// distortion.
  final double aspectRatio;

  /// Accessible label for the zoom tap target, e.g. "Zoom 16-QAM constellation".
  /// The widget prefixes "Zoom " is the caller's job; pass the full phrase.
  final String semanticLabel;

  /// Optional one-line teaching caption shown below the card on the live theme
  /// surface. Omitted (no gap) when null.
  final String? caption;

  void _openZoom(BuildContext context) {
    final AppColorScheme zoomColors = AppColorScheme.dark();
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        // Opaque so the underlying page does not bleed through; the dark-baked
        // raster wants an always-dark lightbox in both themes.
        opaque: true,
        barrierColor: zoomColors.scrim,
        barrierDismissible: true,
        barrierLabel: semanticLabel,
        transitionDuration: AppMotion.base,
        reverseTransitionDuration: AppMotion.fast,
        pageBuilder: (BuildContext context, Animation<double> a,
                Animation<double> b) =>
            _DarkRasterZoomView(assetPath: assetPath),
        transitionsBuilder: (BuildContext context, Animation<double> anim,
            Animation<double> secondary, Widget child) {
          return FadeTransition(
            opacity:
                CurvedAnimation(parent: anim, curve: AppMotion.standardEase),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ALWAYS-DARK surface for the dark-baked raster, regardless of app theme.
    final AppColorScheme dark = AppColorScheme.dark();
    final TextTheme t = Theme.of(context).textTheme;
    // The caption sits below the dark card on the SCREEN surface, so it uses the
    // live theme colors so it reads on both light and dark canvases.
    final AppColorScheme live = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          button: true,
          label: 'Zoom $semanticLabel',
          onTap: () => _openZoom(context),
          child: Container(
            decoration: BoxDecoration(
              color: dark.surface1,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: dark.border, width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: Stack(
              children: <Widget>[
                ExcludeSemantics(
                  // A minimum height guarantees the card (and its tap target)
                  // always has real layout even before the async image decodes
                  // or if a platform reports no intrinsic image size, so the
                  // whole-graphic tap region is never zero-size.
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(minHeight: AppSpacing.xxl),
                    child: AspectRatio(
                      aspectRatio: aspectRatio,
                      child: Image.asset(
                        assetPath,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                        errorBuilder:
                            (BuildContext _, Object _, StackTrace? _) =>
                                const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
                // Whole-graphic tap layer (single click on desktop) -> zoom.
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openZoom(context),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Off-image zoom affordance. The plate itself is the tap target (the
        // Semantics button above), so this row is a decorative discoverability
        // hint only (ExcludeSemantics keeps it out of the a11y tree — the plate
        // already announces one operable "Zoom <name>" control). It lives BELOW
        // the plate, never overlaid on it: these dense full-bleed reference
        // plates occupy every corner with baked logo / eyebrow / footer marks,
        // so any on-plate badge collides. Moving the affordance off the image
        // removes the collision by construction for every plate in the set.
        const SizedBox(height: AppSpacing.xs),
        ExcludeSemantics(
          child: Row(
            children: <Widget>[
              Icon(
                Icons.zoom_in,
                size: AppSpacing.sm,
                color: live.textTertiary,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Tap to enlarge',
                style: t.bodySmall?.copyWith(color: live.textTertiary),
              ),
            ],
          ),
        ),
        if (caption != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            caption!,
            style: t.bodySmall?.copyWith(color: live.textTertiary),
          ),
        ],
      ],
    );
  }
}

/// Full-screen pinch-zoom + pan view for a dark-baked raster reference diagram.
/// Always-dark backdrop in both themes — the diagram is dark-baked. Dismisses on
/// the X button, a tap on the empty backdrop, a swipe-down, or system back /
/// Escape. Raster sibling of ZoomableGraphic's `_ZoomView` (SVG-only).
class _DarkRasterZoomView extends StatelessWidget {
  const _DarkRasterZoomView({required this.assetPath});

  final String assetPath;

  static const double _minScale = 1;
  static const double _maxScale = 5;

  @override
  Widget build(BuildContext context) {
    // Always-dark lightbox for the dark-baked raster.
    final AppColorScheme dark = AppColorScheme.dark();
    final MediaQueryData mq = MediaQuery.of(context);
    final EdgeInsets safe = mq.padding;

    return Scaffold(
      backgroundColor: dark.surface0,
      body: Stack(
        children: <Widget>[
          // Tap / swipe-down the empty backdrop to dismiss.
          Positioned.fill(
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                onVerticalDragEnd: (DragEndDetails d) {
                  if ((d.primaryVelocity ?? 0) > 0) {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              safe.left + AppSpacing.md,
              safe.top + AppSpacing.xxl,
              safe.right + AppSpacing.md,
              safe.bottom + AppSpacing.md,
            ),
            child: Center(
              child: InteractiveViewer(
                minScale: _minScale,
                maxScale: _maxScale,
                boundaryMargin: const EdgeInsets.all(AppSpacing.xxl),
                child: ExcludeSemantics(
                  child: Image.asset(
                    assetPath,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                    errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
          // Close affordance — a real labeled button, top-right.
          Positioned(
            top: safe.top + AppSpacing.xs,
            right: safe.right + AppSpacing.xs,
            child: Semantics(
              button: true,
              label: 'Close zoom',
              child: Material(
                color: dark.scrim,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).maybePop(),
                  child: SizedBox(
                    height: AppSpacing.minTouchTarget,
                    width: AppSpacing.minTouchTarget,
                    child: Icon(
                      Icons.close,
                      color: dark.textPrimary,
                      size: AppSpacing.md,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
