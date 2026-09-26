// Small building blocks shared by MultipathStage and MultipathControls
// (Wi-Fi Lab Multipath Simulator). Same card, label, row and legend idiom as
// the Modulation and Medium Access simulators, lifted out so both halves of
// this screen draw them identically. Theme tokens only.

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';

/// A surface-1 card with the calculator border and padding.
class MpCard extends StatelessWidget {
  const MpCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }
}

/// Section heading inside a card.
class MpSectionLabel extends StatelessWidget {
  const MpSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: colors.textSecondary,
        letterSpacing: 0.4,
        fontWeight: colors.isLight ? FontWeight.w600 : FontWeight.w500,
      ),
    );
  }
}

/// Label on the left, DM Mono value on the right.
class MpRow extends StatelessWidget {
  const MpRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
    this.valueColor,
  });

  final String label;
  final String value;

  /// Lime: the measured quantity.
  final bool emphasize;

  /// A verdict color; overrides [emphasize].
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            // Presenter mode scales the label column with its text.
            width: 120 * PresenterMode.scaleOf(context).text,
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              value,
              style: mono.inlineCode.copyWith(
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
}

/// Icon plus a small explanatory sentence.
class MpNote extends StatelessWidget {
  const MpNote({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: colors.textTertiary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// A wrapping legend; hidden from screen readers because every painter
/// carries its own worded label.
class MpLegend extends StatelessWidget {
  const MpLegend({super.key, required this.items});

  final List<MpLegendItem> items;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      children: items,
    ),
  );
}

class MpLegendItem extends StatelessWidget {
  const MpLegendItem({super.key, required this.swatch, required this.label});

  /// A line sample: solid or dashed.
  factory MpLegendItem.line({
    required Color color,
    required double width,
    required String label,
    bool dashed = false,
  }) => MpLegendItem(
    swatch: dashed
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(width: 5, height: width, color: color),
              const SizedBox(width: AppSpacing.xxs),
              Container(width: 5, height: width, color: color),
            ],
          )
        : Container(width: 20, height: width, color: color),
    label: label,
  );

  final Widget swatch;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(width: 20, child: Center(child: swatch)),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// A label with its current value on the right, above a slider.
class MpSliderHeader extends StatelessWidget {
  const MpSliderHeader({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Row(
      children: <Widget>[
        Expanded(child: MpSectionLabel(label)),
        const SizedBox(width: AppSpacing.xs),
        Text(value, style: mono.inlineCode.copyWith(color: colors.textPrimary)),
      ],
    );
  }
}
