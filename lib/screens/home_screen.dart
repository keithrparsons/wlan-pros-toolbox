// HomeScreen — the consumer front-door (mockup "Option A"):
//   * a "Check My Connection" hero card at the TOP that pushes the existing
//     Test My Connection tool — the prominent consumer entry point,
//   * richer category tiles: a tool-count badge (or a NEW pill / "~27" override
//     for the 6-category future) top-right, and a line of 2–3 example tool names
//     instead of the generic summary sentence,
//   * a "Search all tools…" field at the BOTTOM that pushes /search (it is a
//     navigation trigger, not an inline filter — inline-as-you-type lives on the
//     search screen).
//
// Order (Option A front door, 2026-06-03): hero card → category grid → search.
//
// The grid is data-driven from kToolCategories, so it scales from the current 4
// categories to 6 automatically. Per Keith (2026-06-03) NOTHING sets isNew in
// this build (the app hasn't gone public, so nothing is "new to a user"); the
// NEW-pill capability is built and ready for the parked categories.
//
// Tiles are tightened for iOS density (2026-06-03, Keith): the hero card adds
// height up top, so the tiles drop to a ~150pt footprint with xs (8px) vertical
// grid spacing so more categories stay above the fold on a phone.
//
// Layout per GL-003 §8.7: 16px screen edge on mobile, 24px on tablet+ desktop,
// 16px grid gutter, tile titles at H3 / IBM Plex Sans 600.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/tool_catalog.dart';
import '../router/app_router.dart';
import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';
import '../widgets/centered_content.dart';
import 'category_screen.dart';
import 'guides/guide_reader_screen.dart';
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
            final double tileHeight =
                _tileHeightFor(width, light: context.colors.isLight);

            return CenteredContent(
              child: CustomScrollView(
                slivers: <Widget>[
                  // 1. Consumer hero — "Check My Connection" (Option A front door).
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      edge,
                      AppSpacing.sm,
                      edge,
                      AppSpacing.md,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _ConnectionHeroCard(
                        // Auto-run the check on arrival so the consumer hero is
                        // a single tap (not "tap here, then tap again"). The
                        // route reads this argument to set autoStart; the plain
                        // tool tile pushes without it and stays tap-to-run.
                        onTap: () => Navigator.of(context).pushNamed(
                          AppRouter.testMyConnection,
                          arguments: true,
                        ),
                      ),
                    ),
                  ),
                  // 1b. Small "A Guide for Everyone" entry (help-embed,
                  //     2026-06-07). Keith's decision: keep it SMALL — a compact
                  //     single-row card near the Check My Connection front door,
                  //     NOT a second hero. Opens the consumer guide in the
                  //     in-app reader (offline, themed).
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(edge, 0, edge, AppSpacing.md),
                    sliver: SliverToBoxAdapter(
                      child: _UserGuideEntry(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const GuideReaderScreen(
                              assetPath: kUserGuideAsset,
                              title: 'A Guide for Everyone',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 2. Category grid — tightened density for iOS (2026-06-03).
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(edge, 0, edge, AppSpacing.md),
                    sliver: SliverGrid(
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        // Cross-axis stays at sm (16px) so side-by-side tiles
                        // read as separate; main-axis tightens to xs (8px) to
                        // recover vertical room for more tiles above the fold.
                        crossAxisSpacing: AppSpacing.sm,
                        mainAxisSpacing: AppSpacing.xs,
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
                  // 3. Search trigger — moved to the bottom (Option A, 2026-06-03)
                  //    so the consumer hero leads and the grid is denser up top.
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      edge,
                      0,
                      edge,
                      AppSpacing.md,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _HomeSearchField(
                        onTap: () => Navigator.of(context)
                            .pushNamed(AppRouter.search),
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
  /// Tightened for iOS density (2026-06-03, Keith): the consumer hero card adds
  /// height up top, so the phone tiles drop their footprint to keep more
  /// categories above the fold. The recovered room comes from the icon→title gap
  /// (sm 16 → xs 8) plus the smaller box.
  ///
  /// The height is width-aware so the SINGLE-column phone (320/375/390, below the
  /// 440 two-column breakpoint) gets the tight density target while the wider
  /// MULTI-column layouts still clear the worst-case wrap:
  ///
  ///   * Phone (1-column, width < 440): a full-width tile keeps the H3 title on
  ///     ONE line for every catalog category, but a long examples line (joined
  ///     with " · ") can still wrap to TWO lines at the narrow 320–390 widths.
  ///     Height budget (IBM Plex Sans tokens, incl. 1px tile border each side):
  ///     border(1)+pad sm(16) + icon row(28) + icon→title gap xs(8) + 1-line H3
  ///     (22×1.25 ≈ 27.5) + title→examples gap xs(8) + 2-line examples
  ///     (13×1.35×2 ≈ 35.1) + pad sm(16)+border(1) ≈ 140.6. **144** clears that
  ///     worst case with a thin margin and removes the dead band the old 150
  ///     opened on the many short-examples categories (Vera flagged the gap at
  ///     ~360–440), while keeping the density win over the old 180.
  ///
  ///   * Multi-column (width ≥ 440): a narrow column can wrap BOTH the title AND
  ///     the examples to two lines at once. Height budget (IBM Plex Sans tokens,
  ///     incl. 1px tile border each side): border(1)+pad sm(16) + icon row(28) +
  ///     icon→title gap xs(8) + 2-line H3 (22×1.25×2 ≈ 55) + title→examples gap
  ///     xs(8) + 2-line examples (13×1.35×2 ≈ 35.1) + pad sm(16)+border(1) ≈ 168.
  ///     **172** clears it with margin and no RenderFlex overflow at 440–1440
  ///     (verified by the no-overflow gate). Still tighter than the old 180.
  ///   * LIGHT (§8.20.3-C item 1): the category icon becomes a 40×40 lime
  ///     knockout chip (vs the bare 28px glyph in dark), so the icon row grows
  ///     by 12px. The tile budget gains the same 12px in light to preserve the
  ///     same margin and keep the no-overflow gate green (144 → 156 phone,
  ///     172 → 184 multi-column). Dark is unchanged.
  double _tileHeightFor(double width, {required bool light}) {
    final double base = width < _singleColumnBreakpoint ? 144 : 172;
    return light ? base + 12 : base;
  }
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
    final AppColorScheme colors = context.colors;

    // §8.4 / §8.20.3-B input look: input-fill, border-strong idle (1.5px light),
    // focus ring on focus (2.5px darkened-lime light / 2px lime dark), 48dp.
    final Border border = _focused
        ? Border.all(
            color: colors.isLight ? colors.textAccent : colors.primary,
            width: colors.isLight ? 2.5 : 2,
          )
        : Border.all(
            color: colors.borderStrong,
            width: colors.isLight ? 1.5 : 1,
          );

    return Semantics(
      button: true,
      label: 'Search all tools',
      excludeSemantics: true,
      child: Material(
        color: colors.inputFill,
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
                Icon(Icons.search, color: colors.textTertiary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Search all tools…',
                  style: text.bodyLarge?.copyWith(
                    color: colors.textTertiary,
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

/// The small "A Guide for Everyone" entry (help-embed, 2026-06-07). A compact
/// single-row card — leading book glyph, title + one-line subtitle, trailing
/// chevron — that opens the consumer guide in the in-app [GuideReaderScreen].
/// Deliberately understated (Keith: keep it small) so it sits under the
/// "Check My Connection" hero without competing with it. Matches the category
/// tile / resource-row visual register: surface1, card radius, borderStrong
/// hairline, §8.3 lime focus ring on keyboard focus, §8.20.2 light shadow.
class _UserGuideEntry extends StatefulWidget {
  const _UserGuideEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_UserGuideEntry> createState() => _UserGuideEntryState();
}

class _UserGuideEntryState extends State<_UserGuideEntry> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;

    final Border border = _focused
        ? Border.all(
            color: colors.isLight ? colors.textAccent : colors.primary,
            width: colors.isLight ? 3 : 2,
          )
        : Border.all(
            color: colors.borderStrong,
            width: colors.isLight ? 1.5 : 1,
          );

    final List<BoxShadow>? shadow = (colors.isLight && !_focused)
        ? const <BoxShadow>[
            BoxShadow(
              color: Color(0x14000000), // rgba(0,0,0,0.08)
              offset: Offset(0, 2),
              blurRadius: 8,
            ),
          ]
        : null;

    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: 'New here? A Guide for Everyone. A plain-language tour of the app. '
          'Opens the guide.',
      child: Material(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            boxShadow: shadow,
          ),
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (bool f) {
              if (f != _focused) setState(() => _focused = f);
            },
            child: Container(
              decoration: BoxDecoration(
                border: border,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.rowPadding,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.menu_book_outlined,
                    color: colors.textAccent,
                    size: 24,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'New here? A Guide for Everyone',
                          style: text.bodyLarge?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'A plain-language tour of the app',
                          style: text.labelMedium?.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.xs),
                    child: Icon(
                      Icons.chevron_right,
                      color: colors.textTertiary,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The consumer front-door hero (mockup "Option A"). A prominent additive card
/// at the top of the home content that routes to the existing Test My Connection
/// tool. Per GL-003: H2 headline (§8.5 headlineMedium, one step above the
/// category-tile titles) above a full-width §8.3 primary (lime / charcoal-text)
/// CTA with a leading network glyph. The former lime "START HERE" eyebrow and
/// the descriptive subline were removed (2026-06-04) to reclaim iOS vertical
/// space — the headline + CTA carry the front door on their own.
///
/// The card surface/border/radius match the category tiles (`surface1`,
/// `AppRadius.card`, a `borderStrong` hairline). Accessibility: the CTA is a real
/// [FilledButton] with a clear semantic label and inherits the §8.3 lime focus
/// ring from the app theme; the heading reads first, then the CTA.
class _ConnectionHeroCard extends StatelessWidget {
  const _ConnectionHeroCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;

    // §8.20.2 elevation: the hero sits on the gray canvas, so in light it gets a
    // resting drop shadow (white card elevated by shadow). Dark stays flat.
    final List<BoxShadow>? shadow = colors.isLight
        ? const <BoxShadow>[
            BoxShadow(
              color: Color(0x14000000), // rgba(0,0,0,0.08)
              offset: Offset(0, 2),
              blurRadius: 8,
            ),
          ]
        : null;

    final Widget card = Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.borderStrong,
          width: colors.isLight ? 1.5 : 1,
        ),
        boxShadow: shadow,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Headline — H2 bold (§8.5 headlineMedium / h2 = 28). Sits one step
          // above the category-tile titles (headlineSmall / h3 = 22) so the
          // front-door hero reads as primary without the former display-scale
          // headlineLarge (h1 = 36) dominating the iOS viewport. Keeps the
          // hero's bold w700 (already at the §8.20.3-A ceiling for H1/hero).
          Text(
            'Is it your Wi-Fi or your Internet?',
            style: text.headlineMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Full-width §8.3 primary CTA: lime FILL, dark text + icon (lime as a
          // fill is sanctioned on light, §8.20.2). Label bumps to 700 in light
          // via the filledButtonTheme.
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.network_check),
              label: const Text('Check My Connection'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // §8.20.3-C #4 — the hero gets a generous 8px vivid lime #A1CC3A FILL band
    // (an AREA, full brand green) across the top of the card in light. Because
    // the band is a fill area (not a hairline on canvas), it reads vivid at full
    // brand lime; it is a decorative brand area clearing the 3:1 graphical floor.
    // No band in dark.
    if (!colors.isLight) return card;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Stack(
        children: <Widget>[
          card,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(height: 8, color: colors.primary),
          ),
        ],
      ),
    );
  }
}

/// The 28px home-grid category glyph. Renders the category's bespoke Tier-2 SVG
/// (GL-003 §8.6.1, `currentColor`, runtime-tinted) when [ToolCategory.iconAsset]
/// is set, and falls back to the Material [ToolCategory.icon] otherwise.
///
/// DARK (§8.6.1): a 28px lime (#A1CC3A) glyph sitting bare on the tile — the
/// original treatment, unchanged.
/// LIGHT (§8.20.3-C item 1, the headline pop change): a 40×40 vivid lime
/// #A1CC3A filled chip at card radius (12px) with the 28px glyph knocked out in
/// charcoal #30302F (`onPrimary`), 7.05:1. Replaces the prior dull-olive #5A7A1C
/// bare line glyph on light. Placeholder categories keep the neutral tertiary
/// glyph (no lime chip) in both themes.
class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.category, required this.isPlaceholder});

  final ToolCategory category;
  final bool isPlaceholder;

  /// §8.20.3-C item 1: category-tile knockout chip ≈40×40, card radius (12px).
  static const double _chipSize = 40;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool limeChip = colors.isLight && !isPlaceholder;
    // Glyph tint: charcoal #30302F (onPrimary) knocked out of the lime chip on
    // light; otherwise the original foreground tint (brand lime on the dark
    // tile via textAccent, or tertiary gray for a placeholder in either theme).
    final Color color =
        limeChip ? colors.onPrimary : (isPlaceholder ? colors.textTertiary : colors.textAccent);

    final String? asset = category.iconAsset;
    final Widget glyph = asset != null
        ? SvgPicture.asset(
            asset,
            width: 28,
            height: 28,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            // Decorative: the tile's Semantics already announces the category.
            excludeFromSemantics: true,
            placeholderBuilder: (_) => const SizedBox(width: 28, height: 28),
          )
        : Icon(category.icon, size: 28, color: color);

    if (!limeChip) return glyph;
    return Container(
      width: _chipSize,
      height: _chipSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primary, // vivid brand lime #A1CC3A FILL
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: glyph,
    );
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
    final AppColorScheme colors = context.colors;
    final ToolCategory cat = widget.category;
    final bool isPlaceholder = !cat.hasLiveTool;

    // §8.20.3-B — focus/selection ring: 3px darkened-lime in light (4.8:1, needs
    // the extra px over dark's 2px lime at 9.3:1); 1.5px borderStrong idle in
    // light. Dark keeps 2px lime focus / 1px borderStrong idle.
    final Border tileBorder = _focused
        ? Border.all(
            color: colors.isLight ? colors.textAccent : colors.primary,
            width: colors.isLight ? 3 : 2,
          )
        : Border.all(
            color: colors.borderStrong,
            width: colors.isLight ? 1.5 : 1,
          );

    // §8.20.2 — resting tile shadow in light (white card on gray canvas).
    final List<BoxShadow>? shadow = (colors.isLight && !_focused)
        ? const <BoxShadow>[
            BoxShadow(
              color: Color(0x14000000), // rgba(0,0,0,0.08)
              offset: Offset(0, 2),
              blurRadius: 8,
            ),
          ]
        : null;

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${cat.title}. '
          '${isPlaceholder ? "Coming soon. " : ""}'
          '${_badgeSemanticLabel()}'
          '${_examplesLine()}',
      button: true,
      child: Material(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            boxShadow: shadow,
          ),
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
                      _CategoryIcon(
                        category: cat,
                        isPlaceholder: isPlaceholder,
                      ),
                      _badge(text, colors, isPlaceholder),
                    ],
                  ),
                  // Fixed gap (not a Spacer): keep the icon row, title, and
                  // examples grouped at the top so taller tiles don't open a
                  // dead band in the middle (Vera IA-redesign density gate).
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    cat.title,
                    style: text.headlineSmall?.copyWith(
                      color: isPlaceholder
                          ? colors.textSecondary
                          : colors.textPrimary,
                      // §8.20.3-A home grid category labels bump 600 → 700.
                      fontWeight:
                          colors.isLight ? FontWeight.w700 : FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _examplesLine(),
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Top-right tile badge. Priority: placeholder "SOON" → NEW pill (if isNew) →
  /// count override → exact live count. Per Keith (2026-06-03) isNew is false on
  /// everything in this build, so the NEW pill never renders today.
  Widget _badge(TextTheme text, AppColorScheme colors, bool isPlaceholder) {
    if (isPlaceholder) {
      // On light, surface2 is white (same as the tile), so the SOON pill needs
      // a fill that reads as recessed against the white card — the gray canvas
      // (surface0) does that and keeps a perceivable hairline border.
      return _pillBadge(
        text,
        'SOON',
        fill: colors.isLight ? colors.surface0 : colors.surface2,
        textColor: colors.textTertiary,
        border: colors.border,
      );
    }
    if (widget.category.isNew) {
      // §8.3 primary-button pairing: dark text on lime FILL (sanctioned on
      // light, §8.20.2), AA-cleared.
      return _pillBadge(
        text,
        'NEW',
        fill: colors.primary,
        textColor: colors.onPrimary,
      );
    }
    final String label =
        widget.category.countLabelOverride ??
        '${_liveCount(widget.category)}';
    return _pillBadge(
      text,
      label,
      fill: colors.isLight ? colors.surface0 : colors.surface2,
      textColor: colors.textTertiary,
      border: colors.isLight ? colors.border : null,
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
