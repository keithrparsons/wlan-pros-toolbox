// Small shared view pieces and formatters for the Wi-Fi Classroom "Antenna
// Pattern" tool (antenna-pattern). Used by the stage and the controls so the
// two match each other and the Wi-Fi Classroom siblings (same card, row, note and
// slider treatment as Fourier and FFT). Theme tokens only.

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';

/// Stable catalog tool id: backs the route, the help entry and the tests.
const String kAntennaPatternToolId = 'antenna-pattern';

// ── Formatters ──────────────────────────────────────────────────────────────

/// One decimal, no "-0.0", and a true minus sign.
String fmtDb1(double v) {
  final String s = v.toStringAsFixed(1);
  final String t = s == '-0.0' ? '0.0' : s;
  return t.startsWith('-') ? '−${t.substring(1)}' : t;
}

String fmtDbi(double v) => '${fmtDb1(v)} dBi';
String fmtDbd(double v) => '${fmtDb1(v)} dBd';
String fmtDeg(double v) => '${v.toStringAsFixed(0)}°';
String fmtDeg1(double v) => '${v.toStringAsFixed(1)}°';

/// Degrees below (positive) or above (negative) the horizon, in words.
String fmtElevation(double belowDeg) {
  final double r = belowDeg.roundToDouble();
  if (r == 0) return 'at the horizon';
  return r > 0
      ? '${fmtDeg(r)} below the horizon'
      : '${fmtDeg(-r)} above the horizon';
}

/// Polarization loss, capped for display: the theory is unbounded at 90°.
String fmtPolarizationLoss(double db) {
  if (!db.isFinite || db > 40) return 'over 40 dB';
  if (db < 0.005) return '0.00 dB'; // −20·log10(1) is −0.0
  return '${db.toStringAsFixed(2)} dB';
}

// ── Pieces ──────────────────────────────────────────────────────────────────

AppMonoText patternMono(BuildContext context) =>
    Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

class PatternCard extends StatelessWidget {
  const PatternCard({super.key, required this.child});
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

class PatternSectionLabel extends StatelessWidget {
  const PatternSectionLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: colors.textSecondary,
        letterSpacing: 0.4,
        fontWeight: colors.isLight ? FontWeight.w600 : FontWeight.w500,
      ),
    );
  }
}

class PatternCaption extends StatelessWidget {
  const PatternCaption(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    style: Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: context.colors.textTertiary),
  );
}

/// Label on the left, mono value on the right. [emphasize] paints the value
/// lime: the quantity the card is about.
class PatternReadoutRow extends StatelessWidget {
  const PatternReadoutRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 136,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              value,
              style: patternMono(context).inlineCode.copyWith(
                color: emphasize ? colors.textAccent : colors.textPrimary,
                fontWeight: emphasize ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon plus a sentence.
class PatternNote extends StatelessWidget {
  const PatternNote({super.key, required this.icon, required this.message});
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

/// A labeled slider with its value in mono on the right.
class PatternSlider extends StatelessWidget {
  const PatternSlider({
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

  /// Spoken value for a slider position, e.g. "8 dBi".
  final String Function(double) semanticValue;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                valueText,
                style: patternMono(
                  context,
                ).inlineCode.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          activeColor: colors.primary,
          inactiveColor: colors.borderStrong,
          semanticFormatterCallback: (double v) => '$label ${semanticValue(v)}',
        ),
      ],
    );
  }
}
