// Resource metadata badges — neutral cost / level / tag chips.
//
// Cost and level are NEUTRAL metadata, not §8.13 status VERDICTS: "Free" or
// "Beginner" carries no pass/marginal/fail meaning, so it must NOT borrow a
// status hue (status color is a verdict, never decoration — GL-003 §8.13). These
// render as the neutral §8.17-style chip: surface-2 fill, secondary text, a
// borderStrong outline. Tags use the same quiet neutral chip a half-step
// smaller. Color is never the sole carrier — every chip carries its word.

import 'package:flutter/material.dart';

import '../../../services/educational/educational_resources_service.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';

/// The cost + level badge pair shown on a resource row and at the top of the
/// detail screen.
class ResourceMetaBadges extends StatelessWidget {
  const ResourceMetaBadges({
    super.key,
    required this.cost,
    required this.level,
  });

  final ResourceCost cost;
  final ResourceLevel level;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        _NeutralChip(label: cost.label, icon: Icons.payments_outlined),
        _NeutralChip(label: level.label, icon: Icons.school_outlined),
      ],
    );
  }
}

/// A neutral metadata chip: surface-2 fill, secondary text, borderStrong
/// outline, with an optional small leading glyph. Non-interactive (decorative
/// label), so it carries no focus ring.
class _NeutralChip extends StatelessWidget {
  const _NeutralChip({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.borderStrong, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14, color: colors.textSecondary),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Text(
            label,
            style: text.labelLarge?.copyWith(
              fontSize: AppTextSize.caption,
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A free-form tag chip — the quietest neutral chip (no border, surface-2 fill,
/// tertiary text). Decorative; carries its word as the carrier.
class ResourceTagChip extends StatelessWidget {
  const ResourceTagChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: text.labelLarge?.copyWith(
          fontSize: AppTextSize.caption,
          fontWeight: FontWeight.w500,
          color: colors.textTertiary,
        ),
      ),
    );
  }
}
