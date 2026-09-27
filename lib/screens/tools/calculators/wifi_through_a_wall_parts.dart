// Shared pieces for the Wi-Fi Classroom "Wi-Fi Through a Wall" tool
// (wifi-through-a-wall): the immutable wall configuration the screen owns,
// the number formatting every panel uses, and the small themed building
// blocks (card, section label, readout row, note) that match the sibling
// Wi-Fi Classroom screens.
//
// The stage (wifi_through_a_wall_stage.dart) and the controls
// (wifi_through_a_wall_controls.dart) are separate widgets that both read a
// WallConfig, so a later presenter layout can place them side by side
// without either one owning the other.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../widgets/presenter/presenter_mode.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/wall_slab_physics.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';

/// Stable catalog tool id: backs the route, the help entry and the tests.
const String kWifiThroughAWallToolId = 'wifi-through-a-wall';

/// Thickness bounds, mm (spec).
const double kWallMinMm = 10;
const double kWallMaxMm = 1000;

/// Incidence angle bound, degrees (spec).
const double kWallMaxAngle = 80;

/// Above this, a loss is shown as "more than" rather than a number: past it
/// the figure only says "nothing gets through" and the digits are noise.
const double kLossDisplayCapDb = 150;

/// Tx power bounds and default, dBm (Keith, 2026-09-27: "can we add a Tx
/// power setting"). The level at the front face is taken as the Tx power:
/// the tool has no distance, so free-space loss is not included.
const double kWallTxMinDbm = 0;
const double kWallTxMaxDbm = 30;
const double kWallDefaultTxDbm = 20;

/// Noise floor the drawing measures height from, dBm. Thermal noise kTB at
/// 290 K is -174 dBm/Hz; over a 20 MHz channel that is -174 + 10 log10(20e6)
/// = -101.0 dBm; a typical client receiver adds about a 6 dB noise figure,
/// giving -95 dBm. Only the drawing uses it; every number is exact.
const double kThermalNoiseDbmPerHz = -174;
const double kWallNoiseBandwidthHz = 20e6;
const double kWallNoiseFigureDb = 6;
const double kWallNoiseFloorDbm = -95;

/// Loss tangent above which the material is treated as a conductor for the
/// readouts (no meaningful wavelength inside; the skin depth is shown).
const double kConductorLossTangent = 10;

/// Default channel per band (spec: 6, 100, 117).
int defaultChannelFor(WifiBand band) {
  switch (band) {
    case WifiBand.band24:
      return 6;
    case WifiBand.band5:
      return 100;
    case WifiBand.band6:
      return 117;
  }
}

/// Everything the user sets. Immutable; the screen holds one and replaces it.
@immutable
class WallConfig {
  const WallConfig({
    this.band = WifiBand.band5,
    this.channel = 100,
    this.material = WallMaterial.concrete,
    this.thicknessMm = 102,
    this.angleDeg = 0,
    this.polarization = Polarization.te,
    this.txPowerDbm = kWallDefaultTxDbm,
  });

  final WifiBand band;
  final int channel;
  final WallMaterial material;
  final double thicknessMm;
  final double angleDeg;
  final Polarization polarization;

  /// Transmit power, dBm: the level the wave arrives at the front face with.
  /// It moves no number in the physics, only the drawn heights and the level
  /// behind the wall.
  final double txPowerDbm;

  /// Level just behind the wall, dBm: Tx power minus the transmission loss.
  /// Free-space loss is not included.
  double levelBehindDbm(SlabResult r) => txPowerDbm - r.transmissionLossDb;

  /// Channel center frequency, MHz.
  int get centerMHz => centerFrequencyMHzForBand(band, channel)!;

  double get fGhz => centerMHz / 1000;

  double get thicknessM => thicknessMm / 1000;

  /// The P.2040 result at the selected channel.
  SlabResult get result => resultAt(fGhz);

  /// The same wall at another frequency (the three-band card).
  SlabResult resultAt(double fGhz, {double? thicknessM}) => WallSlab.compute(
    material: material,
    fGhz: fGhz,
    thicknessM: thicknessM ?? this.thicknessM,
    angleDeg: angleDeg,
    polarization: polarization,
  );

  WallConfig copyWith({
    WifiBand? band,
    int? channel,
    WallMaterial? material,
    double? thicknessMm,
    double? angleDeg,
    Polarization? polarization,
    double? txPowerDbm,
  }) => WallConfig(
    band: band ?? this.band,
    channel: channel ?? this.channel,
    material: material ?? this.material,
    thicknessMm: thicknessMm ?? this.thicknessMm,
    angleDeg: angleDeg ?? this.angleDeg,
    polarization: polarization ?? this.polarization,
    txPowerDbm: txPowerDbm ?? this.txPowerDbm,
  );

  @override
  bool operator ==(Object other) =>
      other is WallConfig &&
      other.band == band &&
      other.channel == channel &&
      other.material == material &&
      other.thicknessMm == thicknessMm &&
      other.angleDeg == angleDeg &&
      other.polarization == polarization &&
      other.txPowerDbm == txPowerDbm;

  @override
  int get hashCode => Object.hash(
    band,
    channel,
    material,
    thicknessMm,
    angleDeg,
    polarization,
    txPowerDbm,
  );
}

// ── Formatting ────────────────────────────────────────────────────────────

/// One decimal, no "-0.0".
String fmt1(double v) {
  final String s = v.toStringAsFixed(1);
  return s == '-0.0' ? '0.0' : s;
}

/// A loss in dB, capped at [kLossDisplayCapDb].
String fmtLossDb(double v) {
  if (!v.isFinite || v > kLossDisplayCapDb) {
    return 'more than ${kLossDisplayCapDb.toStringAsFixed(0)} dB';
  }
  return '${fmt1(v)} dB';
}

/// A level in dBm, one decimal.
String fmtDbm(double v) => '${fmt1(v)} dBm';

/// Thickness in mm: one decimal below 20 mm when it has one, else whole.
String fmtMm(double mm) {
  if (mm < 20 && mm != mm.roundToDouble()) return mm.toStringAsFixed(1);
  return mm.toStringAsFixed(0);
}

/// Wall thickness for display, with its unit: cm in metric (Keith,
/// 2026-09-27: "most walls are measured in cm"), inches in imperial.
/// "10.2 cm", "0.25 cm", "4 in", "19.7 in".
String fmtThickness(double mm, UnitSystem u) => LengthFormat(u).smallFromMm(mm);

/// A length in metres, in the unit a student reads easily. Imperial shows
/// inches down to a tenth of an inch; below that (a metal's skin depth)
/// there is no inch a student reads, so it stays in mm, µm or nm.
String fmtLength(double m, [UnitSystem u = UnitSystem.metric]) {
  if (!u.isMetric && m >= LengthUnits.inchesToMetres(0.1)) {
    return LengthFormat(u).small(m);
  }
  if (m >= 0.1) return '${(m * 100).toStringAsFixed(1)} cm';
  if (m >= 0.01) return '${(m * 100).toStringAsFixed(2)} cm';
  if (m >= 0.001) return '${(m * 1000).toStringAsFixed(1)} mm';
  if (m >= 1e-6) return '${(m * 1e6).toStringAsFixed(1)} µm';
  return '${(m * 1e9).toStringAsFixed(0)} nm';
}

/// Whole number with thousands separators.
String fmtThousands(double v) {
  final String digits = v.round().toString();
  final StringBuffer b = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
    b.write(digits[i]);
  }
  return b.toString();
}

/// A rate given in dB/m: one decimal below 1000, grouped above, in millions
/// past a million (metal). Imperial shows dB/ft (the rate times 0.3048).
String fmtRate(double v, [UnitSystem u = UnitSystem.metric]) {
  final String unit = u.isMetric ? 'dB/m' : 'dB/ft';
  final double r = u.isMetric ? v : v * LengthUnits.metresPerFoot;
  if (r < 1000) return '${fmt1(r)} $unit';
  if (r < 1e6) return '${fmtThousands(r)} $unit';
  return 'about ${fmt1(r / 1e6)} million $unit';
}

/// Percent with sensible precision.
String fmtPct(double fraction) {
  final double p = fraction * 100;
  if (p >= 10) return '${p.toStringAsFixed(0)}%';
  if (p >= 1) return '${p.toStringAsFixed(1)}%';
  if (p >= 0.01) return '${p.toStringAsFixed(2)}%';
  return 'under 0.01%';
}

/// Free-space loss difference between two frequencies, dB: 20·log10(f2/f1).
double fsplDeltaDb(double f1Ghz, double f2Ghz) =>
    20 * math.log(f2Ghz / f1Ghz) / math.ln10;

// ── Building blocks ───────────────────────────────────────────────────────

/// Card surface matching the sibling Wi-Fi Classroom screens.
class WallCard extends StatelessWidget {
  const WallCard({super.key, required this.child});

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

/// Section label, exposed to screen readers as a header.
class WallSectionLabel extends StatelessWidget {
  const WallSectionLabel(this.label, {super.key});

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

/// Label on the left, mono value on the right; wraps rather than clips.
class WallRow extends StatelessWidget {
  const WallRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
    this.indent = false,
  });

  final String label;
  final String value;

  /// Lime value: the one quantity the tool is about.
  final bool emphasize;

  /// A sub-row (the parts of a total).
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final double labelScale = PresenterMode.isActive(context)
        ? PresenterMode.scaleOf(context).text
        : 1;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (indent) const SizedBox(width: AppSpacing.sm),
            SizedBox(
              // Presenter mode scales the label column with its text.
              width: (indent ? 136 - AppSpacing.sm : 136) * labelScale,
              child: Text(
                label,
                style: text.bodyMedium?.copyWith(
                  color: indent ? colors.textTertiary : colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                value,
                style: mono.inlineCode.copyWith(
                  color: emphasize ? colors.textAccent : colors.textPrimary,
                  fontWeight: emphasize ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon plus a muted sentence.
class WallNote extends StatelessWidget {
  const WallNote({super.key, required this.icon, required this.message});

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
