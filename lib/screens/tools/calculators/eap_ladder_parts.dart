// Small building blocks shared by EapLadderStage and EapLadderControls
// (Wi-Fi Classroom 802.1X and EAP Ladder). Same card, label, row, slider header and switch
// idiom as the other Wi-Fi Classroom simulators, kept local so this tool does not
// reach into a sibling's private parts. Theme tokens only.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';

/// A surface-1 card with the calculator border and padding.
class ElCard extends StatelessWidget {
  const ElCard({super.key, required this.child});

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

/// Text that wraps only between words. When the widest single word (or
/// hyphen-ended part, like "4-") is wider than the space it has, the text
/// scales down until that word fits, so a narrow phone never breaks
/// "Deauthentication" inside the word (Keith, 2026-09-29, at 390 px). At
/// widths where every word fits, it is a plain [Text] in [style].
class ElWholeWordText extends StatelessWidget {
  const ElWholeWordText(this.data, {super.key, this.style, this.textAlign});

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;

  static final RegExp _words = RegExp(r'[^\s-]+-?');

  /// Head room under the measured fit: glyph widths do not scale exactly
  /// linearly with the font size.
  static const double _margin = 0.98;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final TextStyle base = DefaultTextStyle.of(context).style.merge(style);
        final double? size = base.fontSize;
        double factor = 1;
        if (box.hasBoundedWidth && size != null) {
          final TextScaler scaler = MediaQuery.textScalerOf(context);
          final TextDirection dir = Directionality.of(context);
          double widest = 0;
          for (final RegExpMatch m in _words.allMatches(data)) {
            final TextPainter tp = TextPainter(
              text: TextSpan(text: m[0], style: base),
              textDirection: dir,
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            widest = math.max(widest, tp.width);
            tp.dispose();
          }
          if (widest > box.maxWidth && widest > 0) {
            factor = box.maxWidth / widest * _margin;
          }
        }
        return Text(
          data,
          textAlign: textAlign,
          style: factor == 1
              ? style
              : (style ?? const TextStyle()).copyWith(
                  fontSize: size! * factor,
                  letterSpacing: base.letterSpacing == null
                      ? null
                      : base.letterSpacing! * factor,
                ),
        );
      },
    );
  }
}

/// Section heading inside a card.
class ElSectionLabel extends StatelessWidget {
  const ElSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Semantics(
      header: true,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.textSecondary,
          letterSpacing: 0.4,
          fontWeight: colors.isLight ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}

/// Label on the left, DM Mono value on the right.
class ElRow extends StatelessWidget {
  const ElRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
    this.valueColor,
    this.icon,
  });

  final String label;
  final String value;

  /// Lime: the measured quantity.
  final bool emphasize;

  /// A verdict color (§8.13); overrides [emphasize].
  final Color? valueColor;

  /// A verdict glyph shown before the value, colored like it.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final Color vc =
        valueColor ?? (emphasize ? colors.textAccent : colors.textPrimary);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 5,
              child: Text(
                label,
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              flex: 6,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    ExcludeSemantics(child: Icon(icon, size: 16, color: vc)),
                    const SizedBox(width: AppSpacing.xxs),
                  ],
                  Expanded(
                    child: Text(
                      value,
                      style: mono.inlineCode.copyWith(
                        color: vc,
                        fontWeight: emphasize
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon plus a small explanatory sentence.
class ElNote extends StatelessWidget {
  const ElNote({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ExcludeSemantics(
          child: Icon(icon, size: 16, color: colors.textTertiary),
        ),
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

/// A label with its current value on the right, above a slider.
class ElSliderHeader extends StatelessWidget {
  const ElSliderHeader({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return ExcludeSemantics(
      child: Row(
        children: <Widget>[
          Expanded(child: ElSectionLabel(label)),
          const SizedBox(width: AppSpacing.xs),
          Text(
            value,
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// A labelled slider: header, then a themed Slider whose screen-reader value
/// is worded.
class ElSlider extends StatelessWidget {
  const ElSlider({
    super.key,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.semanticValue,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;

  /// Null disables the slider.
  final ValueChanged<double>? onChanged;
  final String Function(double v) semanticValue;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ElSliderHeader(label: label, value: valueText),
        Semantics(
          label: label,
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            semanticFormatterCallback: semanticValue,
          ),
        ),
      ],
    );
  }
}

/// An outlined button in the calculator style (Back, Step, Reset, Show all).
class ElOutlineButton extends StatelessWidget {
  const ElOutlineButton({
    super.key,
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
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
}
