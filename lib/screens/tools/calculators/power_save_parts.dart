// Small building blocks shared by PowerSaveStage and PowerSaveControls
// (Wi-Fi Lab Power Save), and the one place this tool's state hues live.
// Same card, label, row, slider and button idiom as the other Wi-Fi Lab
// simulators, kept local so this tool does not reach into a sibling's parts.
// Theme tokens only.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/power_save_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/wifi_lab_client_palette.dart';

/// One hue per radio state, the single home of this tool's palette.
///
/// GL-003 §8.15.2 (Keith, 2026-09-25): a Wi-Fi Lab teaching simulator may use
/// extra hues from one harmonious family when telling categories apart by
/// color is part of the lesson. Here it is: the student must see at a glance
/// how the awake time splits into listening for beacons, moving frames,
/// sending, and sitting in a TWT service period, and how much of the bar is
/// doze. The hues are four stops of the shared, measured Wi-Fi Lab family
/// (WifiLabClientPalette: one OKLCH lightness and chroma per theme, every
/// fill at least 4.6:1 on the card surfaces). Doze is no hue at all: a thin
/// neutral line. No §8.13 status hue; none of these is a verdict. Every state
/// is named in the legend and in the timeline's screen-reader text.
abstract final class PsPalette {
  static Color of(AwakeKind kind, AppColorScheme colors) {
    final int i = switch (kind) {
      AwakeKind.listen => 6, // blue
      AwakeKind.frames => 4, // teal
      AwakeKind.send => 8, // rose
      AwakeKind.twtSp => 7, // violet
    };
    return WifiLabClientPalette.of(i, colors).hue;
  }

  static String label(AwakeKind kind) => switch (kind) {
    AwakeKind.listen => 'Awake, listening',
    AwakeKind.frames => 'Receiving frames',
    AwakeKind.send => 'Sending',
    AwakeKind.twtSp => 'TWT service period',
  };
}

/// A surface-1 card with the calculator border and padding.
class PsCard extends StatelessWidget {
  const PsCard({super.key, required this.child});

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
class PsSectionLabel extends StatelessWidget {
  const PsSectionLabel(this.label, {super.key});

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

/// A small explanatory sentence in tertiary ink.
class PsHint extends StatelessWidget {
  const PsHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: context.colors.textTertiary),
    );
  }
}

/// Icon plus a small explanatory sentence.
class PsNote extends StatelessWidget {
  const PsNote({
    super.key,
    required this.icon,
    required this.message,
    this.color,
  });

  final IconData icon;
  final String message;

  /// Icon hue; a §8.13 status hue only when the note is a verdict.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ExcludeSemantics(
          child: Icon(icon, size: 16, color: color ?? colors.textTertiary),
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

/// A labelled slider: header with the value on the right, then a themed
/// Slider whose screen-reader value is worded.
class PsSlider extends StatelessWidget {
  const PsSlider({
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
  final ValueChanged<double> onChanged;
  final String Function(double v) semanticValue;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: PsSectionLabel(label)),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  valueText,
                  textAlign: TextAlign.right,
                  style: mono.inlineCode.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
        ),
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

/// An outlined button in the calculator style.
class PsOutlineButton extends StatelessWidget {
  const PsOutlineButton({
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

/// A legend swatch: a small filled bar in [color] and its label.
class PsSwatch extends StatelessWidget {
  const PsSwatch({super.key, required this.label, this.color, this.child});

  final String label;
  final Color? color;

  /// A custom mark instead of the filled bar.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 16,
          height: 12,
          child:
              child ??
              DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
        ),
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
