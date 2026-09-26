// Small building blocks shared by the Modulation Simulator's stage and
// controls (moved from the screen's State on 2026-09-26, unchanged in look).
//
// THEME: context.colors only (dark §8 / light §8.20); numerics in DM Mono
// (AppMonoText). ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';

/// Theme lookups and the tool's repeated widgets, bound to one context.
class ModUi {
  ModUi.of(this.context)
    : text = Theme.of(context).textTheme,
      mono =
          Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults(),
      colors = context.colors;

  final BuildContext context;
  final TextTheme text;
  final AppMonoText mono;
  final AppColorScheme colors;

  Widget card({required Widget child}) => Container(
    decoration: BoxDecoration(
      color: colors.surface1,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: colors.border, width: colors.isLight ? 1.5 : 1),
    ),
    padding: const EdgeInsets.all(AppSpacing.sm),
    child: child,
  );

  Widget sectionLabel(String label) => Text(
    label,
    style: text.labelMedium?.copyWith(
      color: colors.textSecondary,
      letterSpacing: 0.4,
      fontWeight: colors.isLight ? FontWeight.w600 : FontWeight.w500,
    ),
  );

  /// A label and a mono value. [labelWidth] is the phone's fixed column;
  /// presenter panels pass a wider one for the scaled text.
  Widget row({
    required String label,
    required String value,
    bool emphasize = false,
    Color? valueColor,
    TextStyle? valueStyle,
    double labelWidth = 136,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              value,
              style: (valueStyle ?? mono.inlineCode).copyWith(
                color:
                    valueColor ??
                    (emphasize ? colors.textAccent : colors.textPrimary),
                fontWeight: emphasize ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget note(IconData icon, String message, {Color? tint}) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Icon(icon, size: 16, color: tint ?? colors.textTertiary),
      const SizedBox(width: AppSpacing.xs),
      Expanded(
        child: Text(
          message,
          style: text.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      ),
    ],
  );

  Widget legend(List<Widget> items) => ExcludeSemantics(
    child: Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      children: items,
    ),
  );

  Widget legendItem(Widget swatch, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      SizedBox(width: 20, child: Center(child: swatch)),
      const SizedBox(width: AppSpacing.xxs),
      Text(label, style: text.bodySmall?.copyWith(color: colors.textSecondary)),
    ],
  );

  Widget dot(Color c, double r) => Container(
    width: r * 2,
    height: r * 2,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );

  Widget lineSample(Color c, double w, {bool dashed = false}) {
    if (!dashed) return Container(width: 20, height: w, color: c);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(width: 5, height: w, color: c),
        const SizedBox(width: AppSpacing.xxs),
        Container(width: 5, height: w, color: c),
      ],
    );
  }

  Widget outlined({
    required String label,
    required IconData icon,
    required String semantic,
    required bool enabled,
    required VoidCallback onTap,
    EdgeInsetsGeometry? padding,
    bool showIcon = true,
  }) {
    final Color fg = enabled ? colors.textAccent : colors.textDisabled;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semantic,
      excludeSemantics: true,
      child: OutlinedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: showIcon ? Icon(icon, color: fg) : null,
        label: Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: text.labelLarge?.copyWith(
            color: fg,
            fontWeight: enabled ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: padding,
          foregroundColor: colors.textAccent,
          disabledForegroundColor: colors.textDisabled,
          disabledBackgroundColor: colors.disabledFill,
          side: BorderSide(
            color: enabled ? colors.borderStrong : colors.disabledFill,
            width: 1.5,
          ),
          minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
        ),
      ),
    );
  }
}
