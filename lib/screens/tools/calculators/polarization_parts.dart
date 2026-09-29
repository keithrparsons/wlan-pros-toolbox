// Small shared pieces for the Wi-Fi Classroom "Polarization" tool
// (polarization): the tool id, formatters, the component hues, and a switch
// row. Cards, labels, captions, readout rows, notes and sliders are Antenna
// Pattern's (antenna_pattern_parts.dart), so the two 3D tools match.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/polarization_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/wifi_lab_client_palette.dart';

/// Stable catalog tool id: backs the route, the help entry and the tests.
const String kPolarizationToolId = 'polarization';

/// One drawn cycle takes this many seconds (the real wave does billions).
const double kPolarizationSecondsPerCycle = 3;

// ── Component hues (GL-003 §8.15.2) ─────────────────────────────────────────
//
// The H and V component waves are told apart by color because that is the
// lesson (two waves adding to one). Two hues from the Classroom client
// palette's DARK row, because the 3D viewport is dark in both themes
// (AppGainRamp.viewport): each clears 8.89:1 against it (palette header).
// Each curve also carries its letter in paint, so color is never the only
// carrier. The resultant is lime, the one quantity the tool is about.

/// Horizontal component (client palette hue 5, a blue).
final Color kPolarizationHHue = WifiLabClientPalette.of(
  5,
  AppColorScheme.dark(),
).hue;

/// Vertical component (client palette hue 1, an orange).
final Color kPolarizationVHue = WifiLabClientPalette.of(
  1,
  AppColorScheme.dark(),
).hue;

// ── Formatters ──────────────────────────────────────────────────────────────

/// Axial ratio for a readout: "1.0", "2.0", or "infinite" for a line.
String fmtAxialRatio(PolarizationState s) {
  if (!s.hasField) return 'none';
  final double ar = s.axialRatio;
  if (ar.isInfinite) return 'infinite';
  return ar >= 100 ? 'over 100' : ar.toStringAsFixed(1);
}

/// Tilt of the long axis from horizontal, or a word where it has none.
String fmtTilt(PolarizationState s) {
  switch (s.kind) {
    case PolarizationKind.none:
      return 'none';
    case PolarizationKind.circular:
      return 'none (a circle)';
    case PolarizationKind.linear:
    case PolarizationKind.elliptical:
      final int t = s.tiltDeg.round();
      return t == 0 ? '0° (horizontal)' : '$t° from horizontal';
  }
}

/// Signed phase in degrees with a true minus sign.
String fmtPhase(double deg) {
  final int d = deg.round();
  return d < 0 ? '−${-d}°' : '$d°';
}

/// Amplitude, two decimals.
String fmtAmp(double a) => a.toStringAsFixed(2);

// ── Pieces ──────────────────────────────────────────────────────────────────

/// A switch with its title; the whole row toggles.
class PolSwitchRow extends StatelessWidget {
  const PolSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        canRequestFocus: false,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: text.bodyMedium?.copyWith(color: colors.textPrimary),
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
    );
  }
}
