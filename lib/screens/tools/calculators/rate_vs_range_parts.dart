// Shared small widgets for the Wi-Fi Classroom Rate vs Range tool: card, section
// label, note row and the MCS ring palette. Used by both the stage and the
// controls, so neither imports the other.
//
// THEME: context.colors (dark §8 / light §8.20), plus RvrPalette below, the
// one place the per-MCS hues live (GL-003 §8.15.2). ASCII copy (GL-004).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/rate_vs_range_math.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'calc_parts.dart';

typedef RvrCard = CalcCard;

typedef RvrSectionLabel = CalcSectionLabel;

typedef RvrNote = CalcNote;

/// One hue per MCS ring, the single home of this tool's palette.
///
/// GL-003 §8.15.2 (Keith, 2026-09-25): a Wi-Fi Classroom teaching simulator may use
/// extra hues from one harmonious family when telling categories apart by
/// color is part of the lesson. Here it is: the student must see coverage as
/// a set of nested rings, one per MCS, and watch every ring shrink together.
///
/// The family is the one the 6 GHz Power and PSD tool already proved out
/// (PsdPalette): lavender for MCS 0 at the cell edge, through teal, to the
/// brand lime for MCS 13 next to the AP, blended evenly in between. Dark and
/// light each use their own stops. Every stop and every blend of them clears
/// the WCAG 2.2 SC 1.4.11 3:1 floor for graphics on surface2 (the stops
/// measure 5.2:1 to 7.7:1 per PsdPalette). No §8.13 status hue, and no ring
/// is a verdict. Color never carries meaning alone: every ring is labeled on
/// the stage where it fits and always in the legend.
abstract final class RvrPalette {
  static const List<Color> _dark = <Color>[
    Color(0xFFB89AF0), // lavender, MCS 0
    Color(0xFF4CC9C0), // teal
    Color(0xFFA1CC3A), // brand lime, MCS 13
  ];

  static const List<Color> _light = <Color>[
    Color(0xFF6B48B8),
    Color(0xFF0F7A73),
    Color(0xFF5A7A1C),
  ];

  /// The hue of [mcs] (0 to 13).
  static Color of(int mcs, AppColorScheme colors) {
    final List<Color> stops = colors.isLight ? _light : _dark;
    final double t = (mcs / RateVsRangeMath.maxMcs).clamp(0.0, 1.0) * 2;
    final int i = t >= 2 ? 1 : t.floor();
    return Color.lerp(stops[i], stops[i + 1], t - i)!;
  }
}

/// A filled swatch for one MCS in legends.
class RvrSwatch extends StatelessWidget {
  const RvrSwatch({super.key, required this.mcs});
  final int mcs;

  @override
  Widget build(BuildContext context) {
    final double k = PresenterMode.scaleOf(context).marker;
    return Container(
      width: 12 * k,
      height: 12 * k,
      decoration: BoxDecoration(
        color: RvrPalette.of(mcs, context.colors),
        shape: BoxShape.circle,
      ),
    );
  }
}
