// HomeScreen — the 8-category landing grid.
//
// Layout per GL-003 §8.7: 16px screen edge on mobile, 24px on tablet+ desktop,
// 16px grid gutter, tile titles at H3 / IBM Plex Sans 600.

import 'package:flutter/material.dart';

import '../data/tool_catalog.dart';
import '../theme/app_tokens.dart';
import 'category_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// Breakpoint for switching from mobile-edge to desktop-edge padding.
  /// Tablet portrait ~768px+ gets the wider gutter per §8.7.
  static const double _desktopBreakpoint = 720;

  /// Phone-vs-larger breakpoint. Below this we drop tile aspect ratio so the
  /// icon + 2-line title + 2-line summary fit without RenderFlex overflow at
  /// 375pt iPhone widths. (Vera F-01.)
  static const double _phoneBreakpoint = 480;

  /// Narrow-phone breakpoint — covers iPhone SE 1st-gen (320pt) and other
  /// sub-375pt logical widths. Drops tile aspect a second step so content
  /// still clears at 320×900. (Vera F-NEW-03.)
  static const double _narrowPhoneBreakpoint = 360;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Vera F-05 — at macOS cold start Flutter focuses the first focusable
    // widget, painting the lime hover tint on the first tile. That reads
    // visually as "selected" rather than "keyboard-focused". Drop focus once
    // after first frame; Tab still works normally to walk focus through tiles.
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
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double width = constraints.maxWidth;
            final bool isDesktop = width >= HomeScreen._desktopBreakpoint;
            final double edge = isDesktop
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;
            final int crossAxisCount = _crossAxisCountFor(width);
            final double aspect = _aspectRatioFor(width);

            return Padding(
              padding: EdgeInsets.fromLTRB(edge, AppSpacing.sm, edge, edge),
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: AppSpacing.sm,
                  mainAxisSpacing: AppSpacing.sm,
                  childAspectRatio: aspect,
                ),
                itemCount: kToolCategories.length,
                itemBuilder: (context, index) {
                  final ToolCategory cat = kToolCategories[index];
                  return _CategoryTile(
                    category: cat,
                    onTap: () {
                      // Vera F-NEW-02 — the `initState` unfocus only fires on
                      // first mount. When the user pops back from a category,
                      // Flutter's focus traversal can leave a tile holding
                      // primary focus, repainting the lime tint as if it were
                      // "selected". Hook the route future so we can drop
                      // focus once the home tree has been re-installed after
                      // pop. Schedule the unfocus on the next frame so it
                      // runs after Flutter rebuilds the focus tree.
                      Navigator.of(context)
                          .push(
                            MaterialPageRoute<void>(
                              builder: (_) => CategoryScreen(category: cat),
                            ),
                          )
                          .then((_) {
                            if (!mounted) return;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              FocusManager.instance.primaryFocus?.unfocus();
                            });
                          });
                    },
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  int _crossAxisCountFor(double width) {
    if (width >= 1100) return 4;
    if (width >= 720) return 3;
    if (width >= 480) return 2;
    return 2; // phones — keep 2-up so tiles stay tappable.
  }

  /// Tile vertical room scales with viewport. Phones (<480px) get a taller
  /// tile so the 28px icon row + 2-line H3 title (22px/1.4) + 2-line caption
  /// (13px/1.5) fit without RenderFlex overflow at 375pt. Narrow phones
  /// (<360px, iPhone SE 1st-gen) drop a second step so the same content
  /// clears at 320pt. (Vera F-01, F-NEW-03.)
  double _aspectRatioFor(double width) {
    if (width < HomeScreen._narrowPhoneBreakpoint) return 0.75;
    if (width < HomeScreen._phoneBreakpoint) return 0.85;
    return 1.05;
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.onTap,
  });

  final ToolCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool isPlaceholder = !category.hasLiveTool;

    // Vera F-04 — `container: true, excludeSemantics: true` collapses the
    // child Text semantic nodes so VoiceOver hears only the curated label
    // once instead of label + each visible Text.
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${category.title}. '
          '${isPlaceholder ? "Coming soon. " : ""}'
          '${category.summary}',
      button: true,
      child: Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.borderStrong, width: 1),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(
                      category.icon,
                      size: 28,
                      color: isPlaceholder
                          ? AppColors.textTertiary
                          : AppColors.primary,
                    ),
                    if (isPlaceholder)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppColors.border,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          'SOON',
                          style: text.labelSmall?.copyWith(
                            color: AppColors.textTertiary,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  category.title,
                  style: text.headlineSmall?.copyWith(
                    color: isPlaceholder
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  category.summary,
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
}
