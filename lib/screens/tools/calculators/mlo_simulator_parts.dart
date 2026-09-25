// Small building blocks shared by MloSimulatorStage and MloSimulatorControls
// (Wi-Fi Lab Multi-Link Operation). Same card, label, row, slider and switch
// idiom as the other Wi-Fi Lab simulators, kept local so this tool does not
// reach into a sibling's parts. Theme tokens only. ASCII copy (GL-004).
//
// LINK HUES (GL-003 §8.15.2, Keith 2026-09-25): each link is told apart by
// color because the lesson is WHICH link carried each frame. The hues are
// three members of the Wi-Fi Lab family (lib/theme/wifi_lab_client_palette
// .dart, equal OKLCH lightness, contrast measured there): the pink for
// 2.4 GHz, the sky for 5 GHz, the violet for 6 GHz. All three sit away from
// lime and from the §8.13 amber, red and green. Every use also prints the
// band's name.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/mlo_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/wifi_lab_client_palette.dart';

/// Palette slot per band.
int _slot(MloBand b) => switch (b) {
  MloBand.ghz24 => 8,
  MloBand.ghz5 => 5,
  MloBand.ghz6 => 7,
};

/// The link's hue and the text color on it.
WifiLabClientStyle mloLinkStyle(MloBand b, AppColorScheme colors) =>
    WifiLabClientPalette.of(_slot(b), colors);

/// A surface-1 card with the calculator border and padding.
class MloCard extends StatelessWidget {
  const MloCard({super.key, required this.child});

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
class MloSectionLabel extends StatelessWidget {
  const MloSectionLabel(this.label, {super.key});

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

/// Icon plus a small explanatory sentence.
class MloNote extends StatelessWidget {
  const MloNote({
    super.key,
    required this.icon,
    required this.message,
    this.color,
  });

  final IconData icon;
  final String message;

  /// A verdict hue (§8.13) for the icon; the text stays neutral.
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

/// A small filled swatch in a link's hue, with the band name beside it.
class MloLinkTag extends StatelessWidget {
  const MloLinkTag({super.key, required this.band, this.suffix});

  final MloBand band;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final WifiLabClientStyle s = mloLinkStyle(band, colors);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: s.hue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            suffix == null ? band.label : '${band.label} $suffix',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textPrimary),
          ),
        ),
      ],
    );
  }
}

/// A label with its current value on the right, above a slider.
class MloSlider extends StatelessWidget {
  const MloSlider({
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
            children: <Widget>[
              Expanded(child: MloSectionLabel(label)),
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

/// A title and subtitle with a Switch; the whole row toggles on tap, and
/// keyboard focus stays on the Switch, which paints the ring.
class MloSwitchRow extends StatelessWidget {
  const MloSwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.leading,
  });

  final String title;
  final String subtitle;
  final bool value;

  /// Null disables the row (the reason goes in [subtitle]).
  final ValueChanged<bool>? onChanged;

  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final ValueChanged<bool>? change = onChanged;
    return MergeSemantics(
      child: InkWell(
        onTap: change == null ? null : () => change(!value),
        canRequestFocus: false,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
          ),
          child: Row(
            children: <Widget>[
              if (leading != null) ...<Widget>[
                leading!,
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: text.bodyLarge?.copyWith(
                        color: change == null
                            ? colors.textDisabled
                            : colors.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Switch(
                value: value,
                onChanged: change,
                activeThumbColor: colors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An outlined button in the calculator style.
class MloOutlineButton extends StatelessWidget {
  const MloOutlineButton({
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

/// A percentage: "50%".
String mloPct(double f) => '${(f * 100).round()}%';
