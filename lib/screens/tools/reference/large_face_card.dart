// Large face-card layout — the BIG-graphic reference primitive.
//
// Keith's feedback on the Power & Cooling reference graphics: the small recessed
// ConceptGraphicBand (140/160dp) is too small to be useful. The graphics need to
// be BIG — fill the content width and a large share of screen height so the
// graphic, not a tiny inset, is the primary element on the page.
//
// This file ships two reusable pieces:
//
//   * [LargeGraphic] — the sizing + recolor + graceful-degradation engine. Draws
//     one named SVG (resolved through any manifest-gated resolver via the
//     [path] + [has] callbacks) at LARGE size: it fills the card width and a
//     tunable fraction of the viewport height, capped so it never eats the whole
//     screen on a tall device. It reuses the §8.20.7 light-mode recolor path
//     (ConceptGraphicBand.applyLightSwap) exactly as the small bands do, so dark
//     goldens are unaffected and light renders never put a raw lime stroke on
//     white. Decorative for screen readers (every fact is in the adjacent text).
//     Degrades to SizedBox.shrink() when the SVG is not bundled.
//
//   * [LargeFaceCard] — a card = the big [LargeGraphic] PLUS a title and a specs
//     panel alongside (the IEC per-connector pattern). On a wide layout the specs
//     sit beside the graphic; on a narrow layout they stack beneath it. This is
//     the reusable card NEMA + International follow next.
//
// Sizing model (the "go bigger than power_phasing" requirement): power_phasing's
// _WaveformBand caps at 140/160dp. LargeGraphic instead sizes to
// `min(viewportHeight * heightFraction, maxHeight)` and stretches to the card
// width — an order of magnitude larger. heightFraction defaults to ~0.42 (a
// large share of screen height); maxHeight caps it so a desktop window does not
// blow the graphic up past a usable size.
//
// Tokens: surface1 card / surface2 graphic well / AppRadius.card / AppSpacing.*
// only. No hardcoded color, size, or spacing literal (GL-003 §4/§8.1).
//
// Accessibility (GL-003 §8.6.2): the graphic is decorative — ExcludeSemantics +
// excludeFromSemantics. The title and every spec are real Text the screen reader
// reads; the graphic adds no alt text (it would double the content).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../concept_graphic_band.dart';

/// One label/value spec pair shown beside (or beneath) a large face graphic.
/// The [accent] flag tints the value lime to draw the eye to a load-bearing
/// number (e.g. the rated current).
@immutable
class FaceSpec {
  const FaceSpec({
    required this.label,
    required this.value,
    this.accent = false,
  });

  /// Short label, e.g. `Current`.
  final String label;

  /// The value, e.g. `10 A`. Rendered in DM Mono so it aligns with the app's
  /// numeric register.
  final String value;

  /// Tints the value with `textAccent` (lime) when true.
  final bool accent;
}

/// A LARGE SVG render with the §8.20.7 light/dark recolor and graceful
/// degradation. Resolver-agnostic: pass the resolver's [assetName], its [path]
/// builder, and its [has] check, and this widget gates on [has] before ever
/// handing flutter_svg a path. Renders nothing (SizedBox.shrink) when absent —
/// so a page using it ships fully working before Charta's faces land.
class LargeGraphic extends StatelessWidget {
  const LargeGraphic({
    super.key,
    required this.assetName,
    required this.path,
    required this.has,
    this.heightFraction = 0.42,
    this.maxHeight = 460,
    this.minHeight = 220,
  });

  /// The explicit asset name (NOT the catalog tool id — one page carries many
  /// face graphics), e.g. `iec-c13`.
  final String assetName;

  /// Resolver path builder, e.g. `IecConnectorsDiagrams.path`.
  final String Function(String assetName) path;

  /// Resolver presence check, e.g. `IecConnectorsDiagrams.has`.
  final bool Function(String assetName) has;

  /// Share of the viewport height the graphic targets. ~0.42 makes a connector
  /// face a large, dominant element (Keith: "fill the screen"). Capped by
  /// [maxHeight] and floored by [minHeight].
  final double heightFraction;

  /// Hard cap so a tall desktop window does not blow the graphic up past a
  /// usable size.
  final double maxHeight;

  /// Floor so a short landscape viewport still renders a meaningfully large
  /// graphic.
  final double minHeight;

  // Per-asset cache of the already-swapped light SVG source, so the §8.20.7
  // string replace runs once per face, not on every rebuild. Shared across all
  // LargeGraphic instances (asset names are globally unique).
  static final Map<String, String> _lightSvgCache = <String, String>{};

  Future<String> _loadSwappedSvg() async {
    final String cached = _lightSvgCache[assetName] ?? '';
    if (cached.isNotEmpty) return cached;
    final String raw = await rootBundle.loadString(path(assetName));
    final String swapped = ConceptGraphicBand.applyLightSwap(raw);
    _lightSvgCache[assetName] = swapped;
    return swapped;
  }

  @override
  Widget build(BuildContext context) {
    // Graceful fallback: no bundled face → render nothing, layout unchanged.
    if (!has(assetName)) {
      return const SizedBox.shrink();
    }
    final AppColorScheme colors = context.colors;
    final double viewportHeight = MediaQuery.sizeOf(context).height;
    final double graphicHeight =
        (viewportHeight * heightFraction).clamp(minHeight, maxHeight);

    // DARK: unmodified asset (dark render unchanged). LIGHT: load + §8.20.7 swap
    // + render via string so no raw lime stroke ever hits a light surface.
    final Widget svg = colors.isLight
        ? _LightLargeSvg(future: _loadSwappedSvg(), height: graphicHeight)
        : SvgPicture.asset(
            path(assetName),
            fit: BoxFit.contain,
            width: double.infinity,
            height: graphicHeight,
            excludeFromSemantics: true,
            placeholderBuilder: (_) => const SizedBox.shrink(),
          );

    return ExcludeSemantics(
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: SizedBox(
          height: graphicHeight,
          width: double.infinity,
          child: Center(child: svg),
        ),
      ),
    );
  }
}

/// Light-mode large render: awaits the §8.20.7-swapped SVG source, then draws it
/// with `SvgPicture.string`. Collapses to nothing while loading or on any parse
/// failure — same graceful-degradation contract as the dark asset path. Mirrors
/// `_LightConceptSvg` in concept_graphic_band.dart.
class _LightLargeSvg extends StatelessWidget {
  const _LightLargeSvg({required this.future, required this.height});

  final Future<String> future;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<String> snap) {
        final String? data = snap.data;
        if (data == null || data.isEmpty) {
          return const SizedBox.shrink();
        }
        return SvgPicture.string(
          data,
          fit: BoxFit.contain,
          width: double.infinity,
          height: height,
          excludeFromSemantics: true,
          placeholderBuilder: (_) => const SizedBox.shrink(),
        );
      },
    );
  }
}

/// A reusable per-item card: a LARGE face graphic plus the item's title and
/// specs. On a wide layout ([isDesktop]) the specs sit in a column BESIDE the
/// graphic; on a narrow layout they stack BENEATH it. The IEC page renders one
/// per connector; NEMA + International follow the same pattern next.
///
/// The graphic degrades to nothing when its SVG is not bundled — the card then
/// reads as title + specs + note alone (Charta's faces are a parallel pass).
class LargeFaceCard extends StatelessWidget {
  const LargeFaceCard({
    super.key,
    required this.title,
    required this.specs,
    required this.assetName,
    required this.path,
    required this.has,
    required this.isDesktop,
    this.subtitle,
    this.note,
    this.heightFraction = 0.42,
  });

  /// The connector title, e.g. `C13 / C14`.
  final String title;

  /// An optional one-line subtitle under the title, e.g. a nickname.
  final String? subtitle;

  /// The label/value specs for this connector.
  final List<FaceSpec> specs;

  /// A longer clarifying note rendered at the foot of the card.
  final String? note;

  /// Asset name + resolver callbacks for the big face graphic.
  final String assetName;
  final String Function(String assetName) path;
  final bool Function(String assetName) has;

  /// Wide layout → specs beside the graphic; narrow → specs stacked beneath.
  final bool isDesktop;

  /// Forwarded to [LargeGraphic.heightFraction].
  final double heightFraction;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    final Widget graphic = LargeGraphic(
      assetName: assetName,
      path: path,
      has: has,
      heightFraction: heightFraction,
    );
    final bool hasGraphic = has(assetName);

    final Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: text.titleMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            subtitle!,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ],
    );

    final Widget specList = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final FaceSpec s in specs) ...<Widget>[
          _SpecRow(spec: s, colors: colors, text: text),
          const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );

    // The text column (title + specs + note) that sits beside or beneath the
    // graphic.
    final Widget infoColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        titleBlock,
        const SizedBox(height: AppSpacing.sm),
        specList,
        if (note != null && note!.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            note!,
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ],
      ],
    );

    final Widget content;
    if (isDesktop) {
      // Wide: graphic on the left (flex 3), info on the right (flex 2). The
      // graphic stays the dominant element; the specs read alongside.
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(flex: 3, child: graphic),
          if (hasGraphic) const SizedBox(width: AppSpacing.md),
          Expanded(flex: 2, child: infoColumn),
        ],
      );
    } else {
      // Narrow: big graphic on top, info beneath (the power_phasing per-card
      // stacking, but with the graphic an order of magnitude larger).
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          graphic,
          if (hasGraphic) const SizedBox(height: AppSpacing.md),
          infoColumn,
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: content,
    );
  }
}

/// One label-over-value spec line inside a [LargeFaceCard]. Value is DM Mono;
/// lime when the spec is accented.
class _SpecRow extends StatelessWidget {
  const _SpecRow({
    required this.spec,
    required this.colors,
    required this.text,
  });

  final FaceSpec spec;
  final AppColorScheme colors;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          spec.label,
          style: text.labelSmall?.copyWith(
            color: colors.textTertiary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          spec.value,
          style: mono.inlineCode.copyWith(
            color: spec.accent ? colors.textAccent : colors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
