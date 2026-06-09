// Reusable tap-to-zoom wrapper for tool concept graphics — GL-003 §8.6.2 /
// §8.20.7.
//
// Keith's request (2026-06-08): the tool graphics are too small to read and
// pinch-zoom does not work in-page. This widget makes any concept graphic
// tappable: a tap opens a FULL-SCREEN view with pinch-to-zoom + pan
// (Flutter `InteractiveViewer`, minScale 1, maxScale 5), a dark scrim, and
// three dismissal affordances (an X button, tap-the-scrim, and swipe-down).
// Because the graphics are SVG (vector) they stay crisp at any zoom level — the
// zoom view re-renders the SAME SVG large, so there is no rasterization blur.
//
// ONE reusable helper, two call sites:
//   * ConceptGraphicBand (the §8.6.2 header band on ~80 tool pages) wraps its
//     rendered SVG in a [ZoomableGraphic] so every tool graphic becomes
//     tap-to-zoom.
//   * LargeGraphic (the big IEC / Ohm's-wheel / NEMA / International face cards)
//     wraps its rendered SVG the same way.
// Both pass the SAME [svgBuilder] they use for the in-page render (asset for
// dark, §8.20.7-swapped string for light), so the zoom view inherits the exact
// recolor and never drifts from the in-page graphic.
//
// DISCOVERABILITY: a small, subtle magnifier glyph sits in the bottom-right
// corner of the graphic (a translucent pill) so the tap-to-zoom affordance is
// findable without shouting. It is the accessible control: the whole graphic is
// a button (so a tap anywhere zooms), and the magnifier badge is its visible
// affordance.
//
// GRACEFUL DEGRADATION: when there is no graphic (the child is null / collapsed)
// the call site simply does not wrap — this widget is only ever handed a real,
// rendered graphic. It never paints a zoom affordance over empty space.
//
// ACCESSIBILITY (GL-003 §8.6.2):
//   * The decorative graphic itself stays ExcludeSemantics at the call site (no
//     verbose alt text — every fact it depicts is in the screen's text).
//   * The TAP TARGET is a real, labeled `Semantics(button: true, label: 'Zoom
//     graphic')` so VoiceOver / TalkBack announce an operable control rather
//     than a decorative image, and it is keyboard-activatable (InkWell → Enter /
//     Space). It clears the §8.3 minimum-touch-target via the badge size + the
//     full-graphic tap area.
//   * The full-screen view's close button is a real labeled button; Escape /
//     back / swipe-down / scrim-tap all dismiss.
//
// Tokens: scrim / surface / textPrimary / AppRadius / AppSpacing / AppMotion
// only. No hardcoded color, size, spacing, or duration literal (GL-003 §4/§8.1).

import 'package:flutter/material.dart';

import '../../theme/app_color_scheme.dart';
import '../../theme/app_tokens.dart';

/// Wraps a rendered graphic [child] and makes it tap-to-zoom: a tap opens a
/// full-screen pinch-zoom + pan view that re-renders the graphic via
/// [svgBuilder] at large size (crisp, since it is vector). Shows a subtle
/// magnifier affordance in the corner.
///
/// The call site passes the SAME builder it uses for the in-page render, so the
/// zoom view inherits the in-page recolor (dark asset vs §8.20.7-swapped light
/// string) and cannot drift.
class ZoomableGraphic extends StatelessWidget {
  const ZoomableGraphic({
    super.key,
    required this.child,
    required this.svgBuilder,
    this.semanticLabel = 'Zoom graphic',
  });

  /// The in-page rendered graphic (the SvgPicture the call site already builds).
  /// Shown at its normal size; tapping it opens the zoom view.
  final Widget child;

  /// Builds the graphic for the FULL-SCREEN zoom view. Given the available
  /// [Size] of the zoom canvas, returns the (large) SVG widget. The call site
  /// reuses its own dark-asset / light-string render path here so the zoomed
  /// graphic matches the in-page one exactly. Vector → crisp at any scale.
  final Widget Function(BuildContext context, Size canvas) svgBuilder;

  /// Accessible label for the tap target announced by screen readers. Defaults
  /// to a generic "Zoom graphic"; a call site may pass a more specific label
  /// (e.g. the connector name) so the control reads meaningfully.
  final String semanticLabel;

  void _openZoom(BuildContext context) {
    final AppColorScheme colors = context.colors;
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        // Opaque so the underlying page does NOT show through the zoom view —
        // Keith (build 21) saw the page graphic bleeding through the old
        // semi-transparent scrim. _ZoomView paints a solid dark lightbox.
        opaque: true,
        barrierColor: colors.scrim,
        barrierDismissible: true,
        // Spoken label for the modal barrier; "Zoomed graphic" reads cleaner
        // than the default and pairs with the close button below.
        barrierLabel: 'Zoomed graphic',
        transitionDuration: AppMotion.base,
        reverseTransitionDuration: AppMotion.fast,
        pageBuilder: (BuildContext context, Animation<double> a,
                Animation<double> b) =>
            _ZoomView(svgBuilder: svgBuilder),
        transitionsBuilder: (BuildContext context, Animation<double> anim,
            Animation<double> secondary, Widget child) {
          // Gentle fade-in on the standard ease — matches §8.8 motion.
          return FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: AppMotion.standardEase),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;

    return Semantics(
      button: true,
      label: semanticLabel,
      // a11y / keyboard activation lands here (screen-reader "activate").
      onTap: () => _openZoom(context),
      child: Stack(
        children: <Widget>[
          // The in-page graphic. Decorative; its own ExcludeSemantics at the
          // call site keeps it out of the a11y tree — the Semantics(button)
          // above is what the screen reader lands on.
          child,
          // Tap layer covers the whole graphic so a tap anywhere zooms. A
          // GestureDetector (not InkWell) fires on a SINGLE click on desktop —
          // the old InkWell grabbed focus on the first click and needed a
          // second click to activate on macOS (Keith, build 21). Opaque hit
          // behavior so a tap anywhere over the graphic registers.
          Positioned.fill(
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openZoom(context),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          // Subtle, discoverable magnifier badge in the bottom-right corner.
          Positioned(
            right: AppSpacing.xs,
            bottom: AppSpacing.xs,
            child: ExcludeSemantics(
              child: _ZoomBadge(colors: colors),
            ),
          ),
        ],
      ),
    );
  }
}

/// The subtle corner affordance: a translucent pill carrying a magnifier glyph,
/// signalling "tap to zoom" without competing with the graphic. Decorative —
/// the tap target's [Semantics] label carries the meaning for screen readers.
class _ZoomBadge extends StatelessWidget {
  const _ZoomBadge({required this.colors});

  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // Reuse the theme scrim as a translucent dark wash so the glyph reads on
        // both a light and a dark graphic without inventing a token.
        color: colors.scrim,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      padding: const EdgeInsets.all(AppSpacing.xxs),
      child: Icon(
        Icons.zoom_in,
        // White-on-scrim is high-contrast on both themes; onPrimary is the
        // app's "ink that sits on a dark fill" token in dark, and the scrim is
        // dark in both themes, so textPrimary-on-scrim would invert on light.
        // Use a fixed light glyph against the always-dark scrim: neutral0 via
        // the dark scheme's textPrimary is white; the scrim is opaque enough
        // (>=0.4 alpha) that white clears 3:1. Read from the dark scheme so the
        // glyph stays light on the always-dark scrim regardless of app theme.
        color: AppColorScheme.dark().textPrimary,
        size: AppSpacing.sm,
      ),
    );
  }
}

/// The full-screen zoom view: a dark scrim, a centered `InteractiveViewer`
/// (pinch-zoom + pan, minScale 1, maxScale 5), and a close affordance. Dismisses
/// on the X button, a tap on the empty scrim, a swipe-down, or system back /
/// Escape (the route pops). The graphic is re-rendered LARGE via the call site's
/// own builder, so it stays crisp (vector) at any zoom.
class _ZoomView extends StatelessWidget {
  const _ZoomView({required this.svgBuilder});

  final Widget Function(BuildContext context, Size canvas) svgBuilder;

  /// Pinch-zoom bounds per the brief: 1x (fit) to 5x.
  static const double _minScale = 1;
  static const double _maxScale = 5;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final MediaQueryData mq = MediaQuery.of(context);

    // The graphic fills the safe-area canvas minus a comfortable inset so it
    // does not collide with the close button or the screen edges at 1x.
    final EdgeInsets safe = mq.padding;

    return Scaffold(
      // Opaque dark lightbox so nothing of the underlying page shows through
      // (build 21 fix). Read from the dark scheme so the backdrop is a solid
      // dark canvas regardless of the app's light/dark mode — a conventional
      // lightbox, matching the always-dark close button + zoom badge.
      backgroundColor: AppColorScheme.dark().surface0,
      body: Stack(
        children: <Widget>[
          // Tap-the-empty-scrim to dismiss. The InteractiveViewer above
          // captures touches over the graphic, so this only fires on the
          // surrounding scrim. Excluded from semantics (the labeled close
          // button is the a11y dismissal path).
          Positioned.fill(
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                // Swipe-down to dismiss: a downward fling on the scrim pops.
                onVerticalDragEnd: (DragEndDetails d) {
                  if ((d.primaryVelocity ?? 0) > 0) {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
            ),
          ),
          // The zoomable graphic, centered, inset from the edges and the close
          // button. LayoutBuilder gives the exact canvas the SVG renders into.
          Padding(
            padding: EdgeInsets.fromLTRB(
              safe.left + AppSpacing.md,
              safe.top + AppSpacing.xxl,
              safe.right + AppSpacing.md,
              safe.bottom + AppSpacing.md,
            ),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Size canvas = Size(
                  constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : mq.size.width,
                  constraints.maxHeight.isFinite
                      ? constraints.maxHeight
                      : mq.size.height,
                );
                return Center(
                  child: InteractiveViewer(
                    minScale: _minScale,
                    maxScale: _maxScale,
                    // Let a panned graphic travel a little past the edges at
                    // high zoom so corners are reachable.
                    boundaryMargin: const EdgeInsets.all(AppSpacing.xxl),
                    child: ExcludeSemantics(
                      child: svgBuilder(context, canvas),
                    ),
                  ),
                );
              },
            ),
          ),
          // Close affordance — a real labeled button, top-right, on the scrim.
          Positioned(
            top: safe.top + AppSpacing.xs,
            right: safe.right + AppSpacing.xs,
            child: _CloseButton(colors: colors),
          ),
        ],
      ),
    );
  }
}

/// The X dismiss button for the zoom view: a real labeled button sized to the
/// §8.3 minimum touch target, a translucent dark backing so it reads on any
/// graphic, a light glyph for contrast on the scrim.
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.colors});

  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Close zoom',
      child: Material(
        color: colors.scrim,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.of(context).maybePop(),
          child: SizedBox(
            height: AppSpacing.minTouchTarget,
            width: AppSpacing.minTouchTarget,
            child: Icon(
              Icons.close,
              // Light glyph on the always-dark scrim (see _ZoomBadge note).
              color: AppColorScheme.dark().textPrimary,
              size: AppSpacing.md,
            ),
          ),
        ),
      ),
    );
  }
}
