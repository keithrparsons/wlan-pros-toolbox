// Wavelength calculator.
//
// Single-input calculator: enter a frequency, read the wavelength in four
// units. Formula matches the RF Tools PWA reference (app.js calcWavelength,
// line 431):
//   lambda_m  = 300 / f_MHz        (c form: c=3e8 m/s, f in MHz)
//   lambda_cm = lambda_m * 100
//   lambda_ft = lambda_m * 3.28084
//   lambda_in = lambda_ft * 12
//
// Frequency unit mirrors the PWA wl-freq-unit select exactly: MHz (default)
// or GHz; GHz is multiplied by 1000 to MHz (toMHz). Output formatting mirrors
// the PWA fmt() calls: m → 4 decimals, cm → 2, ft → 4, in → 3.
//
// Edge cases:
// - Empty / partial input → blank every output (no crash).
// - Frequency <= 0 or non-finite → division yields a non-positive/infinite
//   result; show "—". PWA guards f <= 0 before computing.
//
// Pure, no network, no platform APIs. Math lives in static functions on the
// public WavelengthScreen class so it is unit-testable against the PWA values.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../labeled_field.dart';

/// Frequency input units, mirroring the PWA wl-freq-unit select.
enum WlFreqUnit { mhz, ghz }

class WavelengthScreen extends StatefulWidget {
  const WavelengthScreen({super.key});

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Mirrors app.js: toMHz, calcWavelength.

  /// Normalize a frequency value to MHz (PWA toMHz).
  static double freqToMHz(double value, WlFreqUnit unit) {
    switch (unit) {
      case WlFreqUnit.ghz:
        return value * 1000.0;
      case WlFreqUnit.mhz:
        return value;
    }
  }

  /// Wavelength in meters given frequency in MHz. 300 / f (PWA calcWavelength).
  static double wavelengthMeters(double freqMHz) => 300.0 / freqMHz;

  /// Wavelength in centimeters (meters * 100).
  static double wavelengthCm(double freqMHz) => wavelengthMeters(freqMHz) * 100.0;

  /// Wavelength in feet (meters * 3.28084).
  static double wavelengthFeet(double freqMHz) =>
      wavelengthMeters(freqMHz) * 3.28084;

  /// Wavelength in inches (feet * 12).
  static double wavelengthInches(double freqMHz) =>
      wavelengthFeet(freqMHz) * 12.0;

  @override
  State<WavelengthScreen> createState() => _WavelengthScreenState();
}

class _WavelengthScreenState extends State<WavelengthScreen> {
  final TextEditingController _freqCtrl = TextEditingController();
  final FocusNode _freqFocus = FocusNode();

  WlFreqUnit _freqUnit = WlFreqUnit.mhz;

  // Frequency normalized to MHz, or null when input is empty/invalid/<=0.
  double? _freqMHz;

  // Unsigned-decimal only. Frequency is always a positive value typed by hand.
  static final List<TextInputFormatter> _unsignedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

  @override
  void dispose() {
    _freqCtrl.dispose();
    _freqFocus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    final double? freq = _tryParseDouble(_freqCtrl.text);
    if (freq == null) {
      setState(() => _freqMHz = null);
      return;
    }
    final double f = WavelengthScreen.freqToMHz(freq, _freqUnit);
    // PWA guards f <= 0 before computing; do the same so we never render a
    // non-finite or negative wavelength.
    if (f <= 0) {
      setState(() => _freqMHz = null);
      return;
    }
    setState(() => _freqMHz = f);
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  static double? _tryParseDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '.') return null;
    return double.tryParse(s);
  }

  /// PWA fmt(value, decimals): fixed-decimal, "—" when not finite.
  static String _fmt(double? value, int decimals) {
    if (value == null || !value.isFinite) return '—';
    return value.toStringAsFixed(decimals);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wavelength'),
        toolbarHeight: 64,
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isDesktop = constraints.maxWidth >= 720;
            final double edge = isDesktop
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.calculatorMaxWidth,
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    edge,
                    AppSpacing.sm,
                    edge,
                    edge + AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _formulaCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _referenceCard(text, mono),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _inputCard(TextTheme text, AppMonoText mono) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: LabeledField(
                  label: 'Frequency',
                  hint: _freqUnit == WlFreqUnit.mhz ? '(MHz)' : '(GHz)',
                  semanticLabel: _freqUnit == WlFreqUnit.mhz
                      ? 'Frequency in MHz'
                      : 'Frequency in GHz',
                  field: TextField(
                    controller: _freqCtrl,
                    focusNode: _freqFocus,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: _unsignedDecimal,
                    onChanged: (_) => _recompute(),
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: mono.outputLarge.copyWith(fontSize: 20),
                    cursorColor: AppColors.primary,
                    decoration: const InputDecoration(hintText: '2400'),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _UnitToggle<WlFreqUnit>(
                value: _freqUnit,
                options: const [
                  (WlFreqUnit.mhz, 'MHz'),
                  (WlFreqUnit.ghz, 'GHz'),
                ],
                onChanged: (u) {
                  setState(() => _freqUnit = u);
                  _recompute();
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _resultGrid(text, mono),
        ],
      ),
    );
  }

  Widget _resultGrid(TextTheme text, AppMonoText mono) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Wavelength',
          style: text.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _resultRow(
          _freqMHz == null ? null : WavelengthScreen.wavelengthMeters(_freqMHz!),
          4,
          'm',
          text,
          mono,
          large: true,
        ),
        const SizedBox(height: AppSpacing.xs),
        _resultRow(
          _freqMHz == null ? null : WavelengthScreen.wavelengthCm(_freqMHz!),
          2,
          'cm',
          text,
          mono,
        ),
        const SizedBox(height: AppSpacing.xs),
        _resultRow(
          _freqMHz == null ? null : WavelengthScreen.wavelengthFeet(_freqMHz!),
          4,
          'ft',
          text,
          mono,
        ),
        const SizedBox(height: AppSpacing.xs),
        _resultRow(
          _freqMHz == null ? null : WavelengthScreen.wavelengthInches(_freqMHz!),
          3,
          'in',
          text,
          mono,
        ),
      ],
    );
  }

  Widget _resultRow(
    double? value,
    int decimals,
    String unit,
    TextTheme text,
    AppMonoText mono, {
    bool large = false,
  }) {
    final TextStyle valueStyle = large ? mono.outputXL : mono.outputLarge;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        SelectableText(
          _fmt(value, decimals),
          style: valueStyle.copyWith(
            color: value == null ? AppColors.textTertiary : AppColors.primary,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          unit,
          style: text.labelLarge?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _formulaCard(TextTheme text, AppMonoText mono) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Formula',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(
            'λ(m) = 300 / f',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'f in MHz. The 300 constant is c (3·10⁸ m/s) scaled for the '
            'MHz/metre form. cm = m·100, ft = m·3.28084, in = ft·12.',
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
    // Wavelength at the three Wi-Fi band anchors, computed from the same
    // formula this screen uses (300 / f_MHz). Values shown to 4 decimals (m)
    // to match the live output.
    final List<List<String>> refs = const [
      ['2.4 GHz', '0.1250 m', '12.50 cm'],
      ['5 GHz', '0.0600 m', '6.00 cm'],
      ['6 GHz', '0.0500 m', '5.00 cm'],
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Wi-Fi band reference',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...refs.map((row) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Column widths snap to the 8px base unit (GL-003 §4).
                  SizedBox(
                    width: 96,
                    child: Text(
                      row[0],
                      style: mono.inlineCode.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    child: Text(
                      row[1],
                      style: mono.inlineCode.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row[2],
                      style: mono.inlineCode.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Segmented unit toggle for the frequency input. Holds the §8.3 minimum touch
/// target. Identical pattern to the FSPL screen toggle.
class _UnitToggle<T> extends StatelessWidget {
  const _UnitToggle({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.borderStrong, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final bool selected = opt.$1 == value;
          return Semantics(
            button: true,
            selected: selected,
            label: opt.$2,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.control),
              onTap: () => onChanged(opt.$1),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: AppSpacing.minTouchTarget,
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Text(
                  opt.$2,
                  style: text.labelLarge?.copyWith(
                    color: selected
                        ? AppColors.secondary
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
