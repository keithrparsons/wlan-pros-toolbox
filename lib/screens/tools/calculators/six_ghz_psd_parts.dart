// Shared small widgets for the Wi-Fi Lab 6 GHz Power and PSD tool: card,
// section label, note row and the per-class stroke sample. Used by both the
// stage and the controls, so neither imports the other.
//
// THEME: context.colors (dark §8 / light §8.20), plus PsdPalette below, the
// one place the per-class hues live (GL-003 §8.15.2). ASCII copy (GL-004).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/six_ghz_psd_math.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'fspl_simulator_chart.dart';
import 'six_ghz_psd_model.dart';

class PsdCard extends StatelessWidget {
  const PsdCard({super.key, required this.child});
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

class PsdSectionLabel extends StatelessWidget {
  const PsdSectionLabel(this.label, {super.key});
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

class PsdNote extends StatelessWidget {
  const PsdNote(this.icon, this.message, {super.key});
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

/// The stroke-and-marker sample for one class, matching the chart exactly.
class PsdClassSample extends StatelessWidget {
  const PsdClassSample({super.key, required this.powerClass});
  final PowerClass powerClass;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final (CurveStroke stroke, CurveMarker marker) = kPsdClassLook[powerClass]!;
    return CustomPaint(
      painter: FsplStrokeSamplePainter(
        stroke: stroke,
        marker: marker,
        color: PsdPalette.of(powerClass, colors),
        surface: colors.surface1,
        scale: PresenterMode.scaleOf(context).marker,
      ),
    );
  }
}

/// One hue per power class, the single home of this tool's palette.
///
/// GL-003 §8.15.2 (Keith, 2026-09-25): a Wi-Fi Lab teaching simulator may use
/// extra hues from one harmonious family when telling categories apart by
/// color is part of the lesson. Here it is: the student must follow each
/// power class across the EIRP-vs-width chart and see which lines rise and
/// which lie flat.
///
/// The family: four soft hues of matched lightness, the brand lime plus
/// teal, lavender and rose, re-derived darker for light mode. None is a
/// §8.13 status hue, and none is used as a verdict. Contrast (WCAG 2.2
/// SC 1.4.11 needs 3:1 for graphics; all clear 4.5:1):
///   dark on surface2 #2A2A2A: SP 7.66, LPI 7.12, GVP 6.10, VLP 7.58
///   light on surface1/2 #FFFFFF: SP 4.96, LPI 5.18, GVP 6.47, VLP 5.52
/// Color never carries meaning alone: each class also has its own stroke,
/// marker shape and text label (kPsdClassLook, legend, readouts).
abstract final class PsdPalette {
  static const Map<PowerFamily, Color> dark = <PowerFamily, Color>{
    PowerFamily.sp: Color(0xFFA1CC3A),
    PowerFamily.lpi: Color(0xFF4CC9C0),
    PowerFamily.gvp: Color(0xFFB89AF0),
    PowerFamily.vlp: Color(0xFFF2A7C3),
  };

  static const Map<PowerFamily, Color> light = <PowerFamily, Color>{
    PowerFamily.sp: Color(0xFF5A7A1C),
    PowerFamily.lpi: Color(0xFF0F7A73),
    PowerFamily.gvp: Color(0xFF6B48B8),
    PowerFamily.vlp: Color(0xFFB0406E),
  };

  static Color of(PowerClass c, AppColorScheme colors) =>
      (colors.isLight ? light : dark)[psdFamilyOf(c)]!;
}
