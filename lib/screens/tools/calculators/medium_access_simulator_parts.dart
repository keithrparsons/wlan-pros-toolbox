// Small building blocks shared by the Medium Access Simulator's stage and
// controls (moved from the screen's State on 2026-09-26, unchanged in look).
//
// THEME: context.colors only (dark §8 / light §8.20); numerics in DM Mono.

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../labeled_field.dart';
import 'medium_access_timeline.dart';

/// Theme lookups and the tool's repeated widgets, bound to one context.
class MaUi {
  MaUi.of(this.context)
    : text = Theme.of(context).textTheme,
      mono =
          Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults(),
      colors = context.colors;

  final BuildContext context;
  final TextTheme text;
  final AppMonoText mono;
  final AppColorScheme colors;

  TextStyle get labelStyle =>
      text.labelMedium?.copyWith(color: colors.textSecondary) ??
      TextStyle(color: colors.textSecondary);

  Widget card({required Widget child}) => Container(
    decoration: BoxDecoration(
      color: colors.surface1,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: colors.border, width: colors.isLight ? 1.5 : 1),
    ),
    padding: const EdgeInsets.all(AppSpacing.sm),
    child: child,
  );

  Widget sectionTitle(String title) => Semantics(
    header: true,
    child: Text(
      title,
      style: text.titleMedium?.copyWith(
        color: colors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget statRow(String label, String value) => MergeSemantics(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: mono.inlineCode.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    ),
  );

  Widget outlineButton({
    required IconData icon,
    required String label,
    required String semanticLabel,
    required VoidCallback? onPressed,
  }) {
    final bool enabled = onPressed != null;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      enabled: enabled,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textAccent,
          disabledForegroundColor: colors.textDisabled,
          side: BorderSide(
            color: enabled ? colors.borderStrong : colors.disabledFill,
            width: colors.isLight ? 1.5 : 1,
          ),
          minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  /// A §8.14 Select under its §8.4 label line.
  Widget labeledSelect<T>({
    required String label,
    String? semanticLabel,
    required T value,
    required List<AppSelectItem<T>> items,
    required ValueChanged<T> onChanged,
    bool enabled = true,
  }) {
    return LabeledField(
      label: label,
      field: AppSelect<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        enabled: enabled,
        semanticLabel: semanticLabel ?? label,
      ),
    );
  }

  /// [subtitle] null drops the second line (the presenter panel, where the
  /// instructor says it and the stage shows it).
  Widget switchRow({
    required String title,
    required String? subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    final bool enabled = onChanged != null;
    // The whole row toggles on tap (a label that ignores taps is a dead
    // zone); keyboard focus stays on the Switch, which paints the ring.
    return MergeSemantics(
      child: InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        canRequestFocus: false,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: text.bodyLarge?.copyWith(
                        color: enabled
                            ? colors.textPrimary
                            : colors.textDisabled,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: text.bodySmall?.copyWith(
                          color: enabled
                              ? colors.textTertiary
                              : colors.textDisabled,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: colors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A legend swatch: one timeline block, painted.
class MaSwatchPainter extends CustomPainter {
  MaSwatchPainter({required this.style, required this.colors});

  final BlockStyle style;
  final AppColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    paintTimelineBlock(canvas, Offset.zero & size, style, colors);
  }

  @override
  bool shouldRepaint(MaSwatchPainter old) =>
      old.style != style || old.colors != colors;
}
