// SectionHeader — a grouped-list section header with a tool-count chip.
//
// Used by the grouped category screen (mockup 02): the section title in the §8.5
// H3 heading register (--app-text-secondary) and a neutral count chip
// (--app-text-tertiary on --app-surface-2). The count chip is a quiet quantity
// label, not a verdict or a type — it reuses the neutral surface treatment
// (§8.17 family) but in the tertiary text token to read as metadata, not a chip
// a user would tap.

import 'package:flutter/material.dart';

import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, required this.count, super.key});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Semantics(
      header: true,
      label: '$title, $count ${count == 1 ? 'item' : 'items'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.md,
          bottom: AppSpacing.xs,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                // §8.5 H3 heading register for an in-screen group.
                // §8.20.3-A: category labels bump to 700 in light (projector
                // legibility). This header sits on the gray canvas, so no lime
                // underline (lime is only 1.7:1 on canvas, §8.20.3-C).
                style: text.headlineSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight:
                      colors.isLight ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: colors.isLight
                    ? Border.all(color: colors.border, width: 1)
                    : null,
              ),
              child: Text(
                '$count',
                style: text.labelLarge?.copyWith(
                  fontSize: AppTextSize.caption,
                  fontWeight: FontWeight.w500,
                  color: colors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
