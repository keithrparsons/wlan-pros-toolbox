// Block colors for the Wi-Fi Classroom PHY Preamble Reference (phy-preamble). THE
// ONE PLACE these hues live.
//
// GL-003 §8.15.2 (Keith, 2026-09-25): a Wi-Fi Classroom teaching simulator may use
// extra hues when telling categories apart by color is part of the lesson.
// Here it is: the student must see that the first 20 µs (L-STF, L-LTF, L-SIG)
// is the same in every PHY, and what each newer PHY adds after it.
//
// Two hues from one family, the sand and the blue of the Wi-Fi Classroom AP family
// (the same values as eap_ladder_palette.dart, kept away from lime and from
// the §8.13 amber and red). Sand = the legacy preamble every PHY sends; blue =
// fields this PHY adds. Signal fields are FILLED (bits you can read); training
// fields are OUTLINED (a known pattern). Lime, a fill (§8.20.2), marks the
// Data field as in Airtime Anatomy. No hue carries meaning alone: every block
// is labeled, the legend names each style in words, and the block list under
// the bar repeats every name and duration (§8.13 rule 2, WCAG 1.4.1).
//
// Contrast, measured per §8.12 (WCAG relative luminance), 2026-09-25:
//   dark, hue on surface1 #222222:  blue 8.02, sand 7.80 (outline and text)
//   dark, #1A1A1A text on the fill: blue 8.78, sand 8.53
//   light, hue on surface1 #FFFFFF: blue 5.48, sand 5.64
//   light, #FFFFFF text on the fill: blue 5.48, sand 5.64
// Every pair clears 4.5:1, so the hues are legal for text as well as fills.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/phy_preamble.dart';
import '../../../theme/app_color_scheme.dart';

/// How one block is drawn.
class PreambleBlockStyle {
  const PreambleBlockStyle({
    required this.hue,
    required this.fill,
    required this.border,
    required this.label,
  });

  /// The role hue (sand, blue or lime).
  final Color hue;

  /// Block fill: the hue for signal fields and data, the card surface for
  /// training fields.
  final Color fill;

  final Color border;

  /// Text drawn on the block.
  final Color label;
}

/// Sand (legacy) or blue (added) in the current theme.
Color preambleRoleHue(BlockRole role, AppColorScheme colors) {
  switch (role) {
    case BlockRole.legacy:
      return colors.isLight ? const Color(0xFF885E41) : const Color(0xFFDBAC8D);
    case BlockRole.added:
      return colors.isLight ? const Color(0xFF1F6CB0) : const Color(0xFF80BDFB);
    case BlockRole.data:
      return colors.primary;
  }
}

/// Text on a sand or blue fill.
Color _onHue(AppColorScheme colors) =>
    colors.isLight ? const Color(0xFFFFFFFF) : const Color(0xFF1A1A1A);

/// The style for [b]. [masked] draws it neutral with no hue, for a mystery
/// PPDU whose added fields are not yet named.
PreambleBlockStyle preambleBlockStyle(
  PreambleBlock b,
  AppColorScheme colors, {
  bool masked = false,
}) {
  if (masked) {
    return PreambleBlockStyle(
      hue: colors.borderStrong,
      fill: colors.surface2,
      border: colors.borderStrong,
      label: colors.textSecondary,
    );
  }
  final Color hue = preambleRoleHue(b.role, colors);
  switch (b.form) {
    case BlockForm.signal:
      return PreambleBlockStyle(
        hue: hue,
        fill: hue,
        border: hue,
        label: _onHue(colors),
      );
    case BlockForm.training:
      return PreambleBlockStyle(
        hue: hue,
        fill: colors.surface1,
        border: hue,
        label: hue,
      );
    case BlockForm.data:
      return PreambleBlockStyle(
        hue: hue,
        fill: colors.primary,
        border: colors.primary,
        label: colors.onPrimary,
      );
  }
}
