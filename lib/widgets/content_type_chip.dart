// ContentTypeChip — the one neutral category/format chip (GL-003 §8.17).
//
// Source of truth: GL-003 §8.17 ("Content-type chip (neutral category chip)").
// A content-type chip labels WHAT KIND of thing a row is (Table / Checklist /
// CLI / Diagram / Card) or a cross-category SOURCE tag in search results. Per
// §8.15 case-3 + §8.17 it is ALWAYS NEUTRAL — never a §8.13 status hue. Types are
// differentiated by the WORD (and an optional neutral glyph), never by color.
//
// The THREE roles are never crossed (§8.17):
//   * selected/active filter chip  → lime (§8.3)  — NOT this widget
//   * content TYPE / source tag    → neutral      — THIS widget
//   * computed verdict             → §8.13 status  — NOT this widget
//
// Treatment (§8.17 table):
//   fill   --app-surface-2 (chips sit one step above the surface-1 card)
//   text   --app-text-secondary, --text-caption (13px) / IBM Plex Sans 500
//   icon   optional, --app-icon-sm (16px), same neutral text token
//   radius control (8px) by default; pass pill for an all-pills screen (§8.11)
//   pad    4px vertical (--space-xxs) / 8px horizontal (--space-xs)

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

class ContentTypeChip extends StatelessWidget {
  const ContentTypeChip({
    required this.label,
    this.icon,
    this.pill = false,
    this.showBorder = false,
    super.key,
  });

  /// The type/format/source word — e.g. 'Table', 'Checklist', 'CLI', 'Card',
  /// or a category source tag like 'Quick Reference'.
  final String label;

  /// Optional leading neutral glyph (16px). Tinted with the same neutral text
  /// token — never a status hue (§8.17).
  final IconData? icon;

  /// Render as a fully-rounded pill instead of the control radius. Pick ONE chip
  /// shape per screen and hold it (§8.11).
  final bool pill;

  /// Draw the optional 1px borderStrong outline (§8.17). A fill-only chip needs
  /// no border; pass true only where the screen wants extra definition.
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs, // 8px §4
        vertical: AppSpacing.xxs, // 4px §4 half-step
      ),
      decoration: BoxDecoration(
        color: AppColors.surface2, // §8.17 fill
        borderRadius: BorderRadius.circular(
          pill ? AppRadius.pill : AppRadius.control,
        ),
        border: showBorder
            ? Border.all(color: AppColors.borderStrong, width: 1)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(
              icon,
              size: 16, // --app-icon-sm
              color: AppColors.textSecondary, // neutral, never status (§8.17)
            ),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Text(
            label,
            style: text.labelLarge?.copyWith(
              fontSize: AppTextSize.caption, // 13px §8.17
              fontWeight: FontWeight.w500, // IBM Plex Sans 500
              color: AppColors.textSecondary, // §8.17 label text
            ),
          ),
        ],
      ),
    );
  }
}
