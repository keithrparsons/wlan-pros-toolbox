// Shared small widgets for the Wi-Fi Classroom Rate Adaptation tool: card, section
// label, note, slider, outlined button and the per-MCS palette. Used by both
// the stage and the controls, so neither imports the other.
//
// THEME: context.colors (dark §8 / light §8.20). Per-MCS hues come from
// RvrPalette (rate_vs_range_parts.dart), so an MCS is the same color here and
// in Rate vs Range (GL-003 §8.15.2: one harmonious family, 3:1 on the
// surfaces, always paired with a label). statusDanger marks a failed attempt,
// a verdict with an "x" and a word (§8.13). ASCII copy (GL-004).

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import 'rate_vs_range_parts.dart' show RvrPalette;

/// The hue of an MCS: the Rate vs Range family, so the two tools agree.
abstract final class RaPalette {
  static Color of(int mcs, AppColorScheme colors) => RvrPalette.of(mcs, colors);
}

class RaCard extends StatelessWidget {
  const RaCard({super.key, required this.child});
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

class RaSectionLabel extends StatelessWidget {
  const RaSectionLabel(this.label, {super.key});
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

/// A small tertiary note line.
class RaNote extends StatelessWidget {
  const RaNote(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: context.colors.textTertiary),
    );
  }
}

/// A filled swatch for one MCS in legends and the table.
class RaSwatch extends StatelessWidget {
  const RaSwatch({super.key, required this.mcs});
  final int mcs;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: RaPalette.of(mcs, context.colors),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// A labelled slider: label and value on one line, then a themed Slider
/// whose screen-reader value is worded.
class RaSlider extends StatelessWidget {
  const RaSlider({
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
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: AppSpacing.xs),
        ExcludeSemantics(
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: text.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                valueText,
                style: mono.inlineCode.copyWith(color: colors.textPrimary),
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

/// An outlined button in the calculator style (Step, Restart).
class RaOutlineButton extends StatelessWidget {
  const RaOutlineButton({
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
