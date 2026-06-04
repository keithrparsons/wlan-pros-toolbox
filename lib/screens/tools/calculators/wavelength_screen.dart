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

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/field_unit_row.dart';
import '../../../widgets/tool_help_action.dart';
import '../concept_graphic_band.dart';
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
  static double wavelengthCm(double freqMHz) =>
      wavelengthMeters(freqMHz) * 100.0;

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
        // §8.16 — shared "Copy results" affordance. Disabled while the
        // frequency is empty/invalid/≤0 (no wavelength); copies the four-unit
        // wavelength breakdown as a labeled text block. Copy leads; no help
        // icon here.
        actions: <Widget>[
          // §8.16 order: copy LEADS, help TRAILS.
          AppCopyAction(textBuilder: _buildCopyText),
          ToolHelpAction(toolId: 'wavelength'),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isDesktop = constraints.maxWidth >= 720;
            final double edge = isDesktop
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;

            return Align(
              alignment: AppSpacing.calculatorVerticalAlignment(constraints),
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
                      // §8.6.2 concept-graphic header band — first child, above
                      // the input card. Self-collapses when no graphic is
                      // bundled, so the 24px gap below it disappears too.
                      ConceptGraphicBand(
                        toolId: 'wavelength',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('wavelength'))
                        const SizedBox(height: AppSpacing.md),
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

  /// §8.16 copy payload — the four-unit wavelength as a labeled text block.
  ///
  /// Returns null (→ disabled affordance) while the frequency is empty,
  /// invalid, or ≤ 0 (no wavelength). The frequency line echoes the raw entry
  /// with its selected unit; the four wavelength lines use the same per-unit
  /// decimals as the on-screen result grid.
  String? _buildCopyText() {
    final double? f = _freqMHz;
    if (f == null) return null;

    final String freqUnit = _freqUnit == WlFreqUnit.mhz ? 'MHz' : 'GHz';

    return (StringBuffer()
          ..writeln('Wavelength')
          ..writeln('Frequency: ${_freqCtrl.text.trim()} $freqUnit')
          ..writeln('λ: ${_fmt(WavelengthScreen.wavelengthMeters(f), 4)} m')
          ..writeln('λ: ${_fmt(WavelengthScreen.wavelengthCm(f), 2)} cm')
          ..writeln('λ: ${_fmt(WavelengthScreen.wavelengthFeet(f), 4)} ft')
          ..writeln('λ: ${_fmt(WavelengthScreen.wavelengthInches(f), 3)} in'))
        .toString()
        .trimRight();
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
          // Field + unit via the shared FieldUnitRow: reflows the unit beneath
          // the field below 440px so the toggle never clips (Vera web-demo
          // gate, 2026-06-02).
          FieldUnitRow(
            field: LabeledField(
              label: 'Frequency',
              hint: _freqUnit == WlFreqUnit.mhz ? '(MHz)' : '(GHz)',
              semanticLabel: _freqUnit == WlFreqUnit.mhz
                  ? 'Frequency in MHz'
                  : 'Frequency in GHz',
              field: TextField(
                controller: _freqCtrl,
                focusNode: _freqFocus,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: _unsignedDecimal,
                onChanged: (_) => _recompute(),
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                style: mono.outputLarge.copyWith(
                  fontSize: AppTextSize.fieldNumeric,
                ),
                cursorColor: AppColors.primary,
                decoration: const InputDecoration(hintText: '2400'),
              ),
            ),
            unit: AppToggle<WlFreqUnit>(
              value: _freqUnit,
              items: const [(WlFreqUnit.mhz, 'MHz'), (WlFreqUnit.ghz, 'GHz')],
              onChanged: (u) {
                setState(() => _freqUnit = u);
                _recompute();
              },
            ),
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
          _freqMHz == null
              ? null
              : WavelengthScreen.wavelengthMeters(_freqMHz!),
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
          _freqMHz == null
              ? null
              : WavelengthScreen.wavelengthInches(_freqMHz!),
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
    // One SR node per unit row: "Wavelength in meters: 0.1250 m" (or "not
    // calculated"), instead of value and unit as separate fragments under the
    // single "Wavelength" heading (Vera finding #6).
    final String unitName = _unitName(unit);
    return Semantics(
      label: 'Wavelength in $unitName',
      value: value == null
          ? 'not calculated'
          : '${_fmt(value, decimals)} $unit',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SelectableText(
            _fmt(value, decimals),
            style: valueStyle.copyWith(
              color: value == null ? AppColors.textTertiary : AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            unit,
            style: text.labelLarge?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  /// Spoken name for a wavelength unit symbol, so the screen reader announces
  /// "meters" rather than the bare "m" (Vera finding #6).
  static String _unitName(String unit) {
    switch (unit) {
      case 'm':
        return 'meters';
      case 'cm':
        return 'centimeters';
      case 'ft':
        return 'feet';
      case 'in':
        return 'inches';
      default:
        return unit;
    }
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
            'MHz/meter form. cm = m·100, ft = m·3.28084, in = ft·12.',
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
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
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
