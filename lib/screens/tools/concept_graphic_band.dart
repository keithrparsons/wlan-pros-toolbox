// Per-tool concept-graphic header band — GL-003 §8.6.2.
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
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/tool_assets.dart';
import '../../theme/app_tokens.dart';

/// Renders a tool's concept graphic as the §8.6.2 header band, or nothing when
/// the asset is not bundled. Drop it in as the first child of a tool screen's
/// `Column(stretch)`; it sizes itself and degrades to `SizedBox.shrink()` when
/// the tool has no built graphic.
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

  @override
  Widget build(BuildContext context) {
    // Graceful fallback: no bundled graphic → render nothing, layout unchanged.
    if (!ToolAssets.hasGraphic(toolId)) {
      return const SizedBox.shrink();
    }

    final double bandHeight =
        isDesktop ? _bandHeightDesktop : _bandHeightMobile;

    return ExcludeSemantics(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: SizedBox(
          height: bandHeight,
          width: double.infinity,
          child: Center(
            child: SvgPicture.asset(
              ToolAssets.graphicPath(toolId),
              // Scale to width, capped at band height, never crop (§8.6.2).
              fit: BoxFit.contain,
              width: double.infinity,
              height: bandHeight,
              // Decorative — AT skips it (§8.6.2 a11y rule 2).
              excludeFromSemantics: true,
              // A bundled-but-unparseable SVG should never surface a broken
              // box either — collapse to nothing, same as a missing asset.
              placeholderBuilder: (_) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
