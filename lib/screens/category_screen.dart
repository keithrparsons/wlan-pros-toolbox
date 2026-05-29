// CategoryScreen — generic listing for a single category.
//
// Live tools route via `Navigator.pushNamed`. Non-live tools render as a
// disabled "Coming soon" row that does nothing on tap (no SnackBar noise —
// the disabled affordance is the message).

import 'package:flutter/material.dart';

import '../data/tool_catalog.dart';
import '../theme/app_tokens.dart';

class CategoryScreen extends StatelessWidget {
  const CategoryScreen({super.key, required this.category});

  final ToolCategory category;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<ToolEntry> tools = category.tools;

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
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Icon(
                    live ? Icons.bolt : Icons.lock_clock_outlined,
                    color: live ? AppColors.primary : AppColors.textTertiary,
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
