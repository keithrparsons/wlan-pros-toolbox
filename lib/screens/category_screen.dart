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

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.tool});

  final ToolEntry tool;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool live = tool.isLive;

    // Vera F-04 — collapse child semantic nodes so VoiceOver hears only the
    // curated label once.
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: live
          ? '${tool.title}. ${tool.description}'
          : '${tool.title}. Coming soon. ${tool.description}',
      button: true,
      enabled: live,
      child: Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: live
              ? () => Navigator.of(context).pushNamed(tool.routeName)
              : null,
          child: Container(
            decoration: BoxDecoration(
              // Live rows are focusable UI components → borderStrong (3:1+
              // per SC 1.4.11). Disabled rows are non-interactive, so the
              // decorative `border` is fine.
              border: Border.all(
                color: live ? AppColors.borderStrong : AppColors.border,
                width: 1,
              ),
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
                              tool.title,
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
                        tool.description,
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
