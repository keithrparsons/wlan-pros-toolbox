// CategoryScreen — generic listing for a single category.
//
// Live tools route via `Navigator.pushNamed`. Non-live tools render as a
// disabled "Coming soon" row that does nothing on tap (no SnackBar noise —
// the disabled affordance is the message).

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/tool_assets.dart';
import '../data/tool_catalog.dart';
import '../theme/app_tokens.dart';

/// The id of the one category with a hand-pinned tool order.
const String _networkingCategoryId = 'networking';

/// Tool ids pinned to the top of Networking Tools, in this exact order
/// (Keith's ordering): Wi-Fi Information first, Network Quality second.
const List<String> kNetworkingPinnedToolIds = <String>[
  'wifi-vs-internet',
  'wifi-info',
  'net-quality',
];

/// Display order for a category's tools: alphabetical by title, EXCEPT the
/// Networking Tools category, which pins [kNetworkingPinnedToolIds] to the top
/// (in that order) and sorts the remainder alphabetically. The catalog stays
/// the data source-of-truth; this is purely presentation order.
List<ToolEntry> orderedCategoryTools(ToolCategory category) {
  int byTitle(ToolEntry a, ToolEntry b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase());

  if (category.id != _networkingCategoryId) {
    return <ToolEntry>[...category.tools]..sort(byTitle);
  }

  final List<ToolEntry> pinned = <ToolEntry>[];
  for (final String id in kNetworkingPinnedToolIds) {
    final int i = category.tools.indexWhere((ToolEntry t) => t.id == id);
    if (i != -1) pinned.add(category.tools[i]);
  }
  final List<ToolEntry> rest =
      category.tools
          .where((ToolEntry t) => !kNetworkingPinnedToolIds.contains(t.id))
          .toList()
        ..sort(byTitle);
  return <ToolEntry>[...pinned, ...rest];
}

class CategoryScreen extends StatelessWidget {
  const CategoryScreen({super.key, required this.category});

  final ToolCategory category;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<ToolEntry> tools = orderedCategoryTools(category);

    return Scaffold(
      appBar: AppBar(
        title: Text(category.title),
        toolbarHeight: 64,
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double edge = constraints.maxWidth >= 720
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;

            if (tools.isEmpty) {
              return _EmptyState(text: text, edge: edge);
            }

            return ListView.separated(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              itemCount: tools.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                return _ToolRow(tool: tools[index]);
              },
            );
          },
        ),
      ),
    );
  }
}

class _ToolRow extends StatefulWidget {
  const _ToolRow({required this.tool});

  final ToolEntry tool;

  @override
  State<_ToolRow> createState() => _ToolRowState();
}

class _ToolRowState extends State<_ToolRow> {
  // §8.9 — keyboard focus must stay visible. The app-wide §8.3 pass cleared
  // the global `focusColor` to transparent, which stripped the ambient focus
  // affordance off this bare InkWell. Only live rows are focusable (non-live
  // rows pass a null onTap). Track focus locally and swap the row border to
  // the 2px primary ring on keyboard focus, matching the button/chip §8.3
  // treatment. (Restores SC 2.4.7 / GL-003 §8.9.)
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool live = widget.tool.isLive;

    // §8.3 focus ring (live + focused) vs §8.1 interactive boundary.
    // Lime 2px on focus (8.59:1 on surface1 — clears SC 1.4.11);
    // borderStrong 1px for live-at-rest; decorative border for non-live.
    final Border rowBorder = (live && _focused)
        ? Border.all(color: AppColors.primary, width: 2)
        : Border.all(
            color: live ? AppColors.borderStrong : AppColors.border,
            width: 1,
          );

    // Vera F-04 — collapse child semantic nodes so VoiceOver hears only the
    // curated label once.
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: live
          ? '${widget.tool.title}. ${widget.tool.description}'
          : '${widget.tool.title}. Coming soon. ${widget.tool.description}',
      button: true,
      enabled: live,
      child: Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: live
              ? () => Navigator.of(context).pushNamed(widget.tool.routeName)
              : null,
          onFocusChange: live
              ? (bool hasFocus) {
                  if (hasFocus != _focused) {
                    setState(() => _focused = hasFocus);
                  }
                }
              : null,
          child: Container(
            decoration: BoxDecoration(
              // Live rows are focusable UI components → borderStrong (3:1+
              // per SC 1.4.11) at rest, 2px primary ring on focus. Disabled
              // rows are non-interactive, so the decorative `border` is fine.
              border: rowBorder,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 14,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  // Per-tool Tier-2 icon (GL-003 §8.6.1): a single-color SVG
                  // tinted to the row's foreground via BlendMode.srcIn. Live
                  // rows render the tool's own glyph in lime; non-live rows show
                  // the lock. Falls back to Icons.bolt only if the icon SVG was
                  // not bundled for this tool id, so a missing asset never shows
                  // a broken box.
                  child: !live
                      ? Icon(
                          Icons.lock_clock_outlined,
                          color: AppColors.textTertiary,
                          size: 20,
                        )
                      : ToolAssets.hasIcon(widget.tool.id)
                          ? SvgPicture.asset(
                              ToolAssets.iconPath(widget.tool.id),
                              width: 20,
                              height: 20,
                              colorFilter: const ColorFilter.mode(
                                AppColors.primary,
                                BlendMode.srcIn,
                              ),
                              excludeFromSemantics: true,
                              placeholderBuilder: (_) => const SizedBox.shrink(),
                            )
                          : Icon(
                              Icons.bolt,
                              color: AppColors.primary,
                              size: 20,
                            ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.tool.title,
                              style: text.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: live
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                          if (!live)
                            Text(
                              'Coming soon',
                              style: text.labelSmall?.copyWith(
                                color: AppColors.textTertiary,
                                letterSpacing: 0.4,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.tool.description,
                        style: text.labelMedium?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (live)
                  const Padding(
                    padding: EdgeInsets.only(left: AppSpacing.xs),
                    child: Icon(
                      Icons.chevron_right,
                      color: AppColors.textTertiary,
                      size: 20,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text, required this.edge});

  final TextTheme text;
  final double edge;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(edge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.construction_outlined,
              size: 48,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No tools in this category yet',
              style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
