// HomeScreen — the category landing grid with a global search field on top.
//
// IA redesign (mockups 01 / 05):
//   * a "Search all tools…" field above the grid that pushes /search (it is a
//     navigation trigger, not an inline filter — inline-as-you-type lives on the
//     search screen),
//   * richer category tiles: a tool-count badge (or a NEW pill / "~27" override
//     for the 6-category future) top-right, and a line of 2–3 example tool names
//     instead of the generic summary sentence.
//
// The grid is data-driven from kToolCategories, so it scales from the current 4
// categories to 6 automatically. Per Keith (2026-06-03) NOTHING sets isNew in
// this build (the app hasn't gone public, so nothing is "new to a user"); the
// NEW-pill capability is built and ready for the parked categories.
//
// Layout per GL-003 §8.7: 16px screen edge on mobile, 24px on tablet+ desktop,
// 16px grid gutter, tile titles at H3 / IBM Plex Sans 600.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/tool_catalog.dart';
import '../router/app_router.dart';
import '../theme/app_tokens.dart';
import '../widgets/centered_content.dart';
import 'category_screen.dart';
import 'tools/educational/educational_resources_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// Breakpoint for switching from mobile-edge to desktop-edge padding.
  static const double _desktopBreakpoint = 720;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Vera F-05 — drop the auto-focus the macOS embedder paints on the first
    // focusable widget at cold start (it reads as "selected").
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).unfocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WLAN Pros Toolbox'),
        toolbarHeight: 64,
        actions: <Widget>[
          // App-level "About" entry point. Icon-only IconButton inherits the
          // §8.3 lime focus ring globally from the app's iconButtonTheme.
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => Navigator.of(context).pushNamed(AppRouter.about),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Breakpoints are driven by the CONTENT-column width (capped by
            // CenteredContent), not the raw viewport.
            final double width =
                constraints.maxWidth > AppSpacing.contentMaxWidth
                ? AppSpacing.contentMaxWidth
                : constraints.maxWidth;
            final bool isDesktop = width >= HomeScreen._desktopBreakpoint;
            final double edge = isDesktop
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;
            final int crossAxisCount = _crossAxisCountFor(width);
            final double tileHeight = _tileHeightFor(width);

            return CenteredContent(
              child: CustomScrollView(
                slivers: <Widget>[
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      edge,
                      AppSpacing.sm,
                      edge,
                      AppSpacing.sm,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _HomeSearchField(
                        onTap: () => Navigator.of(context)
                            .pushNamed(AppRouter.search),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(edge, 0, edge, edge),
                    sliver: SliverGrid(
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: AppSpacing.sm,
                        mainAxisSpacing: AppSpacing.sm,
                        // Fixed tile HEIGHT (not aspect ratio): the tile content
                        // is top-aligned and compact, so a content-sized height
                        // keeps density identical at every width — no dead band
                        // when the column is narrow (the old aspect-ratio path
                        // made a 2-col tile ~308pt tall at the 680pt cap). Vera
                        // IA-redesign density gate.
                        mainAxisExtent: tileHeight,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final ToolCategory cat = kToolCategories[index];
                          return _CategoryTile(
                            category: cat,
                            onTap: () => _openCategory(cat),
                          );
                        },
                        childCount: kToolCategories.length,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _openCategory(ToolCategory cat) {
    // Most categories push the generic CategoryScreen (a list of ToolEntry
    // routes). The Educational Resources category is the exception: its tile is
    // intercepted to push the dedicated EducationalResourcesScreen directory,
    // because its entries are external learning resources with rich detail, not
    // in-app tool routes.
    final Route<void> route = cat.id == 'educational-resources'
        ? MaterialPageRoute<void>(
            builder: (_) => const EducationalResourcesScreen(),
          )
        : MaterialPageRoute<void>(
            builder: (_) => CategoryScreen(category: cat),
          );

    // Vera F-NEW-02 — drop focus once the home tree is reinstalled after pop, so
    // a returning tile doesn't repaint the lime tint as if "selected".
    Navigator.of(context).push(route).then((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        FocusManager.instance.primaryFocus?.unfocus();
      });
    });
  }

  int _crossAxisCountFor(double width) {
    if (width >= 1100) return 4;
    if (width >= 720) return 3;
    if (width >= _singleColumnBreakpoint) return 2;
    return 1;
  }

  /// Below this width the grid drops from 2 columns to 1 (Vera web-demo gate).
  static const double _singleColumnBreakpoint = 440;

  /// Fixed tile HEIGHT per layout. The tile content is TOP-ALIGNED with a fixed
  /// icon→title gap (no Spacer), so the height is sized to the compact content —
  /// icon+badge row, up-to-2-line H3 title, up-to-2-line examples — with no
  /// large empty band in the middle (Vera IA-redesign density gate).
  ///
  /// A fixed pixel height (rather than an aspect ratio) keeps the density
  /// identical at every width. The old aspect-ratio path coupled height to the
  /// column width, so a 2-col tile ballooned to ~308pt tall at the 680pt content
  /// cap (the dead band Vera flagged) yet was too short at 440pt.
  ///
  /// Height budget (IBM Plex Sans tokens, incl. 1px tile border each side):
  /// border(1)+pad sm(16) top + icon row (28) + icon→title gap sm(16) + 2-line
  /// H3 (22×1.25×2 ≈ 55) + title→examples gap xs(8) + 2-line examples
  /// (13×1.35×2 ≈ 35) + pad sm(16)+border(1) bottom ≈ 176pt. Measured worst case
  /// (narrow 2-col column wrapping BOTH the title and the examples) needs 178;
  /// 180 clears it with a margin and no RenderFlex overflow at any width
  /// (320–1440). The common 1-line-title case top-aligns with a thin bottom
  /// margin — matching the approved 01-home-phone / 05-home-desktop density (no
  /// dead band in the middle). Same height single- and multi-column because the
  /// worst-case content is identical; the narrower multi-column tile just hits
  /// the 2-line title more often.
  double _tileHeightFor(double width) => 180;
}

/// The home "Search all tools…" trigger (mockups 01/05). A tap target styled
/// like the §8.4 input, but it navigates to /search rather than editing inline.
class _HomeSearchField extends StatefulWidget {
  const _HomeSearchField({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_HomeSearchField> createState() => _HomeSearchFieldState();
}

class _HomeSearchFieldState extends State<_HomeSearchField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    // §8.4 input look: input-fill, border-strong idle, lime 2px on focus, 48dp.
    final Border border = _focused
        ? Border.all(color: AppColors.primary, width: 2)
        : Border.all(color: AppColors.borderStrong, width: 1);

    return Semantics(
      button: true,
      label: 'Search all tools',
      excludeSemantics: true,
      child: Material(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (bool f) {
            if (f != _focused) setState(() => _focused = f);
          },
          child: Container(
            height: AppSpacing.minTouchTarget, // 48dp §8.4
            decoration: BoxDecoration(
              border: border,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: <Widget>[
                const Icon(Icons.search, color: AppColors.textTertiary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Search all tools…',
                  style: text.bodyLarge?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The 28px home-grid category glyph. Renders the category's bespoke Tier-2 SVG
/// (GL-003 §8.6.1, `currentColor`, runtime-tinted) when [ToolCategory.iconAsset]
/// is set, and falls back to the Material [ToolCategory.icon] otherwise. The size
/// (28, the §8.6 `--app-icon-grid` token) and the live/placeholder color logic
/// (primary vs textTertiary) are identical across both paths, so the swap is a
/// drop-in that does not disturb the IA-redesign tile layout.
class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.category, required this.isPlaceholder});

  final ToolCategory category;
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) {
    final Color color =
        isPlaceholder ? AppColors.textTertiary : AppColors.primary;
    final String? asset = category.iconAsset;
    if (asset != null) {
      return SvgPicture.asset(
        asset,
        width: 28,
        height: 28,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        // Decorative: the tile's Semantics already announces the category.
        excludeFromSemantics: true,
        placeholderBuilder: (_) => const SizedBox(width: 28, height: 28),
      );
    }
    return Icon(category.icon, size: 28, color: color);
  }
}

class _CategoryTile extends StatefulWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final ToolCategory category;
  final VoidCallback onTap;

  @override
  State<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<_CategoryTile> {
  bool _focused = false;

  /// 2–3 example tool names for the tile preview. Curated when set; otherwise
  /// the first few tool titles in display order (never an empty preview).
  String _examplesLine() {
    final List<String> titles = widget.category.exampleToolTitles.isNotEmpty
        ? widget.category.exampleToolTitles
        : orderedCategoryTools(widget.category)
              .take(3)
              .map((ToolEntry t) => t.title)
              .toList();
    return titles.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ToolCategory cat = widget.category;
    final bool isPlaceholder = !cat.hasLiveTool;

    final Border tileBorder = _focused
        ? Border.all(color: AppColors.primary, width: 2)
        : Border.all(color: AppColors.borderStrong, width: 1);

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${cat.title}. '
          '${isPlaceholder ? "Coming soon. " : ""}'
          '${_badgeSemanticLabel()}'
          '${_examplesLine()}',
      button: true,
      child: Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (bool hasFocus) {
            if (hasFocus != _focused) setState(() => _focused = hasFocus);
          },
          child: Container(
            decoration: BoxDecoration(
              border: tileBorder,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _CategoryIcon(category: cat, isPlaceholder: isPlaceholder),
                    _badge(text, isPlaceholder),
                  ],
                ),
                // Fixed gap (not a Spacer): keep the icon row, title, and
                // examples grouped at the top so taller tiles don't open a dead
                // band in the middle (Vera IA-redesign density gate).
                const SizedBox(height: AppSpacing.sm),
                Text(
                  cat.title,
                  style: text.headlineSmall?.copyWith(
                    color: isPlaceholder
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _examplesLine(),
                  style: text.labelMedium?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Top-right tile badge. Priority: placeholder "SOON" → NEW pill (if isNew) →
  /// count override → exact live count. Per Keith (2026-06-03) isNew is false on
  /// everything in this build, so the NEW pill never renders today.
  Widget _badge(TextTheme text, bool isPlaceholder) {
    if (isPlaceholder) {
      return _pillBadge(
        text,
        'SOON',
        fill: AppColors.surface2,
        textColor: AppColors.textTertiary,
        border: AppColors.border,
      );
    }
    if (widget.category.isNew) {
      // §8.3 primary-button pairing: charcoal on lime, AA-cleared.
      return _pillBadge(
        text,
        'NEW',
        fill: AppColors.primary,
        textColor: AppColors.secondary,
      );
    }
    final String label =
        widget.category.countLabelOverride ??
        '${_liveCount(widget.category)}';
    return _pillBadge(
      text,
      label,
      fill: AppColors.surface2,
      textColor: AppColors.textTertiary,
    );
  }

  Widget _pillBadge(
    TextTheme text,
    String label, {
    required Color fill,
    required Color textColor,
    Color? border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: border == null ? null : Border.all(color: border, width: 1),
      ),
      child: Text(
        label,
        style: text.labelLarge?.copyWith(
          fontSize: AppTextSize.caption,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4,
          color: textColor,
        ),
      ),
    );
  }

  String _badgeSemanticLabel() {
    if (!widget.category.hasLiveTool) return '';
    if (widget.category.isNew) return 'New. ';
    final String count =
        widget.category.countLabelOverride ??
        '${_liveCount(widget.category)}';
    return '$count tools. ';
  }

  /// Number of LIVE tools in a category (the badge counts shippable tools, not
  /// coming-soon placeholders).
  int _liveCount(ToolCategory c) => c.tools.where((ToolEntry t) => t.isLive).length;
}
