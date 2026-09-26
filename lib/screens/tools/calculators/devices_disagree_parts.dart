// Shared small widgets for the Wi-Fi Classroom tool Why Two Devices Disagree
// (devices-disagree): card, section label, note row, the device hue and the
// device badge. Used by both the stage and the controls, so neither imports
// the other.
//
// THEME: context.colors (dark §8 / light §8.20). Device hues come from the
// shared WifiLabClientPalette (GL-003 §8.15.2: a Wi-Fi Classroom simulator
// may use extra hues from one family when telling categories apart by color
// is part of the lesson; here the student matches each device's card to its
// trace on the strip chart). Every use also carries the device's letter, so
// no meaning rests on color alone. ASCII copy (GL-004).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/devices_disagree_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/wifi_lab_client_palette.dart';
import '../../../widgets/presenter/presenter_mode.dart';

/// Which palette slot each device uses. Four hues spread around the family
/// and kept away from its green, so no device trace is mistaken for the
/// brand lime.
const List<int> _kPaletteSlot = <int>[5, 0, 2, 7];

/// The style for device [index] (0 = A).
WifiLabClientStyle ddDeviceStyle(int index, AppColorScheme colors) =>
    WifiLabClientPalette.of(
      _kPaletteSlot[index % _kPaletteSlot.length],
      colors,
    );

class DdCard extends StatelessWidget {
  const DdCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

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
      padding: padding ?? const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }
}

class DdSectionLabel extends StatelessWidget {
  const DdSectionLabel(this.label, {super.key});
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

class DdNote extends StatelessWidget {
  const DdNote(this.icon, this.message, {super.key});
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

/// The device's letter on its hue: the key that ties a card to its trace.
class DdDeviceBadge extends StatelessWidget {
  const DdDeviceBadge({super.key, required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final WifiLabClientStyle s = ddDeviceStyle(index, colors);
    final double size = PresenterMode.scaleOf(context).markerSize(24);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: s.hue, shape: BoxShape.circle),
        child: Text(
          deviceLetter(index),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: s.onHue,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// A title (and an optional line under it) with a Switch. The whole row
/// toggles on tap; keyboard focus stays on the Switch, which paints the ring.
class DdSwitchRow extends StatelessWidget {
  const DdSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;

  /// A line under the title; the presenter panel leaves it out.
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final bool presenting = PresenterMode.isActive(context);
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        canRequestFocus: false,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: presenting ? 0 : AppSpacing.xxs,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: text.bodyLarge?.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    if (subtitle case final String sub when !presenting)
                      Text(
                        sub,
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
