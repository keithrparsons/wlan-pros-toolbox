// Small shared view pieces and formatters for the Wi-Fi Lab "Fourier and
// FFT" tool (fourier-fft). Used by both the stage and the controls, so the
// two stay visually identical to each other and to the Wi-Fi Lab siblings
// (same card, row, note and legend treatment as the Modulation Simulator).
// Theme tokens only.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/fourier_dsp.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';

// ── Formatters ──────────────────────────────────────────────────────────────

String _trim(String s) {
  if (!s.contains('.')) return s;
  final String t = s.replaceFirst(RegExp(r'0+$'), '');
  return t.endsWith('.') ? t.substring(0, t.length - 1) : t;
}

/// 312500 -> "312.5 kHz", 20e6 -> "20 MHz", 3.125 -> "3.125 Hz".
String fmtHz(double hz) {
  if (hz >= 1e6) return '${_trim((hz / 1e6).toStringAsFixed(4))} MHz';
  if (hz >= 1000) return '${_trim((hz / 1000).toStringAsFixed(4))} kHz';
  return '${_trim(hz.toStringAsFixed(3))} Hz';
}

/// 3.2e-6 -> "3.2 us" (with the micro sign), 0.01 -> "10 ms".
String fmtTime(double s) {
  if (s >= 1) return '${_trim(s.toStringAsFixed(3))} s';
  if (s >= 1e-3) return '${_trim((s * 1e3).toStringAsFixed(3))} ms';
  return '${_trim((s * 1e6).toStringAsFixed(3))} µs';
}

/// One decimal, no "-0.0"; -infinity reads "below floor".
String fmtDb(double v) {
  if (!v.isFinite) return 'below floor';
  final String s = v.toStringAsFixed(1);
  return s == '-0.0' ? '0.0' : s;
}

String fmtAmp(double a) => a.toStringAsFixed(2);

String fmtAmpWithDb(SineComponent p) => p.amplitude <= 0
    ? '0.00 (off)'
    : '${fmtAmp(p.amplitude)} (${fmtDb(p.levelDb)} dB)';

String fmtDeg(double d) => '${d.toStringAsFixed(0)}°';

// ── Pieces ──────────────────────────────────────────────────────────────────

AppMonoText labMono(BuildContext context) =>
    Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

class LabCard extends StatelessWidget {
  const LabCard({super.key, required this.child});
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

class LabSectionLabel extends StatelessWidget {
  const LabSectionLabel(this.label, {super.key});
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

/// Quiet explanatory text under a control or plot.
class LabCaption extends StatelessWidget {
  const LabCaption(this.message, {super.key});
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
class LabReadoutRow extends StatelessWidget {
  const LabReadoutRow({
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
    final AppMonoText mono = labMono(context);
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
              style: mono.inlineCode.copyWith(
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
class LabNote extends StatelessWidget {
  const LabNote({super.key, required this.icon, required this.message});
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

/// A legend row. Decorative (the plots carry worded Semantics), so it is
/// hidden from screen readers.
class LabLegend extends StatelessWidget {
  const LabLegend({super.key, required this.items});
  final List<(Widget swatch, String label)> items;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return ExcludeSemantics(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          for (final (Widget swatch, String label) in items)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(width: 20, child: Center(child: swatch)),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

Widget labDot(Color c, double r) => Container(
  width: r * 2,
  height: r * 2,
  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
);

Widget labLineSample(Color c, double w, {bool dashed = false}) {
  if (!dashed) return Container(width: 20, height: w, color: c);
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Container(width: 5, height: w, color: c),
      const SizedBox(width: AppSpacing.xxs),
      Container(width: 5, height: w, color: c),
    ],
  );
}

/// Full-width outlined action with a worded semantic label, matching the
/// sibling simulators' transport buttons.
class LabOutlinedAction extends StatelessWidget {
  const LabOutlinedAction({
    super.key,
    required this.label,
    required this.icon,
    required this.semantic,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final String semantic;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semantic,
      excludeSemantics: true,
      child: OutlinedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          side: BorderSide(
            color: enabled ? colors.borderStrong : colors.disabledFill,
            width: 1.5,
          ),
          minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
        ),
      ),
    );
  }
}
