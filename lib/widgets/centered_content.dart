// CenteredContent — the shared centered-content wrapper for every app surface.
//
// Why this exists (Vera web-demo gate, 2026-06-02 — "inconsistent content
// width"): the calculators and reference tables capped their content at a
// centered 480px while HomeScreen and CategoryScreen ran full-bleed. Navigating
// from a category list into a tool snapped the content column from edge-to-edge
// to a narrow centered band — the "sprawl-then-snap" Keith reported. The fix is
// one shared constraint, applied through one widget, so every surface centers
// its content at the same GL-003 token width.
//
// Contract: wrap a screen body in CenteredContent and it is Center-ed and capped
// at AppSpacing.contentMaxWidth (680 by default, tunable in app_tokens.dart).
// Below that width the child gets the full available width (the ConstrainedBox
// only bites once the viewport exceeds the cap), so phones are unaffected and
// only desktop/tablet gain the centered column.
//
// This is presentation-only: it adds no padding (each screen keeps its own
// GL-003 §8.7 edge padding inside the wrapper) and no scrolling.

import 'package:flutter/widgets.dart';

import '../theme/app_tokens.dart';

/// Centers [child] horizontally and caps its width at [maxWidth]
/// (default [AppSpacing.contentMaxWidth]) so every screen shares one content
/// column. Use [alignment] to control vertical placement of the capped column
/// inside the available space — calculators pass
/// [AppSpacing.calculatorVerticalAlignment] so a short (landscape) viewport
/// top-aligns the column while a tall viewport centers it.
class CenteredContent extends StatelessWidget {
  const CenteredContent({
    super.key,
    required this.child,
    this.maxWidth = AppSpacing.contentMaxWidth,
    this.alignment = Alignment.topCenter,
  });

  /// The screen body to center and cap.
  final Widget child;

  /// Maximum content-column width. Defaults to the shared
  /// [AppSpacing.contentMaxWidth] token; pass a different value only with a
  /// documented reason.
  final double maxWidth;

  /// Vertical/horizontal placement of the capped column within the available
  /// space. Horizontal centering is the point of the widget; the vertical axis
  /// is exposed so calculators can top-align on short viewports.
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
