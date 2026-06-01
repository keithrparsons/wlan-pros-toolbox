// EIRP (Effective Isotropic Radiated Power) calculator.
//
// EIRP = TX power (dBm) − cable/connector loss (dB) + antenna gain (dBi).
// TX power accepts dBm, W, or mW via a unit selector; W/mW are converted to
// dBm first, then the dB arithmetic runs in the log domain. Behavior and
// formatting match the RF Tools PWA reference calcEIRP() in app.js, so the
// native app and PWA agree to the decimal:
//   pwr_dbm  = (unit==W) ? wattsTodBm(pwr) : (unit==mW) ? wattsTodBm(pwr/1000) : pwr
//   eirp_dbm = pwr_dbm - loss + gain
//   eirp_w   = dBmToWatts(eirp_dbm)
// Output: EIRP in dBm (1 decimal). Secondary line mirrors the PWA's mixed
// unit: W with 2 decimals when >= 1 W, else mW with 1 decimal.
//
// Edge cases (match PWA — calcEIRP returns early on any non-finite input):
// - Any field empty or invalid → blank both outputs (no crash).
// - W <= 0 / mW <= 0 → wattsTodBm yields a non-finite log; outputs blank.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_toggle.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// TX power input unit. Mirrors the PWA `eirp-power-unit` select options
/// (order: dBm, W, mW; dBm is the default).
enum EirpPowerUnit { dBm, w, mW }

class EirpScreen extends StatefulWidget {
  const EirpScreen({super.key});

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Mirrors app.js: dBmToWatts, wattsTodBm, calcEIRP.

  static double _dbmToWatts(double dbm) =>
      math.pow(10, dbm / 10).toDouble() / 1000.0;

  static double _wattsTodBm(double w) => 10 * (math.log(w * 1000) / math.ln10);

  /// Normalize a TX power reading to dBm. W and mW route through wattsTodBm
  /// exactly as the PWA does; dBm passes through untouched.
  static double _powerToDbm(double power, EirpPowerUnit unit) {
    switch (unit) {
      case EirpPowerUnit.w:
        return _wattsTodBm(power);
      case EirpPowerUnit.mW:
        return _wattsTodBm(power / 1000.0);
      case EirpPowerUnit.dBm:
        return power;
    }
  }

  /// EIRP in dBm, or null if the result is not finite (e.g. W/mW <= 0).
  /// Pure: takes raw numerics + unit, returns the single source-of-truth value
  /// the UI and tests both read.
  static double? eirpDbm({
    required double power,
    required EirpPowerUnit unit,
    required double lossDb,
    required double gainDbi,
  }) {
    final double pwrDbm = _powerToDbm(power, unit);
    final double result = pwrDbm - lossDb + gainDbi;
    return result.isFinite ? result : null;
  }

  /// EIRP in watts, derived from the dBm result. Pure.
  static double eirpWatts(double eirpDbm) => _dbmToWatts(eirpDbm);

  @override
  State<EirpScreen> createState() => _EirpScreenState();
}

class _EirpScreenState extends State<EirpScreen> {
  final TextEditingController _powerCtrl = TextEditingController();
  final TextEditingController _lossCtrl = TextEditingController();
  final TextEditingController _gainCtrl = TextEditingController();

  final FocusNode _powerFocus = FocusNode();
  final FocusNode _lossFocus = FocusNode();
  final FocusNode _gainFocus = FocusNode();

  EirpPowerUnit _powerUnit = EirpPowerUnit.dBm;

  // Computed result, or null when any input is empty / invalid.
  double? _eirpDbm;

  // Power/gain accept a sign (dBm and dBi can be negative); loss accepts a
  // sign too so a negative-loss paste fails cleanly rather than being coerced.
  // `e/E/+` ride along so a scientific paste like "1e2" parses or fails whole.
  static final List<TextInputFormatter> _signedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.eE+\-]')),
  ];

  @override
  void dispose() {
    _powerCtrl.dispose();
    _lossCtrl.dispose();
    _gainCtrl.dispose();
    _powerFocus.dispose();
    _lossFocus.dispose();
    _gainFocus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    final double? power = _tryParseDouble(_powerCtrl.text);
    final double? loss = _tryParseDouble(_lossCtrl.text);
    final double? gain = _tryParseDouble(_gainCtrl.text);

    if (power == null || loss == null || gain == null) {
      setState(() => _eirpDbm = null);
      return;
    }

    setState(() {
      _eirpDbm = EirpScreen.eirpDbm(
        power: power,
        unit: _powerUnit,
        lossDb: loss,
        gainDbi: gain,
      );
    });
  }

  void _onUnitChanged(EirpPowerUnit unit) {
    setState(() => _powerUnit = unit);
    _recompute();
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  static double? _tryParseDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '-' || s == '.' || s == '-.') return null;
    return double.tryParse(s);
  }

  /// Mirrors app.js `fmt(eirp_dbm, 1)`.
  static String _formatDbm(double dbm) =>
      dbm.isFinite ? dbm.toStringAsFixed(1) : '—';

  /// Mirrors the PWA secondary line: `>= 1 W` shows watts at 2 decimals,
  /// otherwise milliwatts at 1 decimal.
  static String _formatPower(double eirpDbm) {
    final double w = EirpScreen._dbmToWatts(eirpDbm);
    if (!w.isFinite) return '—';
    return w >= 1
        ? '${w.toStringAsFixed(2)} W'
        : '${(w * 1000).toStringAsFixed(1)} mW';
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('EIRP'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until a valid
        // EIRP is computed; copies the result as a labeled text block.
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
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
                      ConceptGraphicBand(toolId: 'eirp', isDesktop: isDesktop),
                      if (ToolAssets.hasGraphic('eirp'))
                        const SizedBox(height: AppSpacing.md),
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _resultCard(text, mono),
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

  /// §8.16 copy payload — the EIRP result as a labeled text block.
  ///
  /// Returns null (→ disabled affordance) whenever there is no valid result:
  /// any empty / invalid field, or a non-finite log from W/mW <= 0. Field order
  /// and values match the on-screen inputs and [_resultCard].
  String? _buildCopyText() {
    final double? dbm = _eirpDbm;
    if (dbm == null) return null;

    final String powerUnit = switch (_powerUnit) {
      EirpPowerUnit.dBm => 'dBm',
      EirpPowerUnit.w => 'W',
      EirpPowerUnit.mW => 'mW',
    };

    return (StringBuffer()
          ..writeln('EIRP')
          ..writeln('TX power: ${_powerCtrl.text.trim()} $powerUnit')
          ..writeln('Cable loss: ${_lossCtrl.text.trim()} dB')
          ..writeln('Antenna gain: ${_gainCtrl.text.trim()} dBi')
          ..writeln('EIRP: ${_formatDbm(dbm)} dBm')
          ..writeln('EIRP power: ${_formatPower(dbm)}'))
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
          // TX power: numeric field + unit selector on one row, matching the
          // PWA's input-row (number input + dBm/W/mW select).
          LabeledField(
            label: 'TX Power',
            semanticLabel: 'TX power value',
            field: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _powerCtrl,
                    focusNode: _powerFocus,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    inputFormatters: _signedDecimal,
                    onChanged: (_) => _recompute(),
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: mono.outputLarge.copyWith(
                      fontSize: AppTextSize.fieldNumeric,
                    ),
                    cursorColor: AppColors.primary,
                    decoration: const InputDecoration(hintText: '20'),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                _unitSelector(),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ConverterField(
            label: 'Cable Loss',
            unitHint: 'dB',
            controller: _lossCtrl,
            focusNode: _lossFocus,
            formatters: _signedDecimal,
            onChanged: (_) => _recompute(),
            monoStyle: mono.outputLarge,
            hint: '1.5',
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ConverterField(
            label: 'Antenna Gain',
            unitHint: 'dBi',
            controller: _gainCtrl,
            focusNode: _gainFocus,
            formatters: _signedDecimal,
            onChanged: (_) => _recompute(),
            monoStyle: mono.outputLarge,
            hint: '14',
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _unitSelector() {
    // dBm / W / mW is three short options — a segmented Toggle, not a Select
    // (§8.14: "Use a segmented Toggle for 2–3 short options"). This matches the
    // Link Budget TX-power selector exactly so the two calculators stay
    // consistent. (Replaces the former 3-option DropdownButton.)
    return AppToggle<EirpPowerUnit>(
      value: _powerUnit,
      items: const [
        (EirpPowerUnit.dBm, 'dBm'),
        (EirpPowerUnit.w, 'W'),
        (EirpPowerUnit.mW, 'mW'),
      ],
      onChanged: _onUnitChanged,
    );
  }

  Widget _resultCard(TextTheme text, AppMonoText mono) {
    final bool hasResult = _eirpDbm != null;
    final String dbmText = hasResult ? _formatDbm(_eirpDbm!) : '—';
    final String powerText = hasResult ? _formatPower(_eirpDbm!) : '—';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      // One SR node for the readout: "EIRP: 36.0 dBm, 4.0 W" (or "not
      // calculated"), instead of value/unit fragments across two lines (Vera
      // finding #6).
      child: Semantics(
        label: 'EIRP',
        value: hasResult ? '$dbmText dBm, $powerText' : 'not calculated',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EIRP',
              style: text.labelMedium?.copyWith(
                color: AppColors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            // Primary result, dBm. Mono so decimals align; "—" in the empty /
            // invalid state so the field reads as "no input yet", never blank.
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SelectableText(
                  dbmText,
                  style: mono.outputXL.copyWith(
                    color: hasResult
                        ? AppColors.primary
                        : AppColors.textTertiary,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'dBm',
                    style: text.labelLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            SelectableText(
              powerText,
              style: mono.outputMedium.copyWith(
                color: hasResult
                    ? AppColors.textSecondary
                    : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
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
            'EIRP = TX power − cable loss + antenna gain',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          SelectableText(
            'dBm  = dBm − dB + dBi',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
    // Compact regulatory EIRP ceilings, common Wi-Fi planning anchors. Figures
    // are widely-cited band maxima for point-to-multipoint client access; exact
    // limits vary by sub-band, channel width, and power-control rules. ASCII
    // hyphen-minus (U+002D) to match the converter's rendered output (Vera F-08).
    final List<List<String>> refs = const [
      ['2.4 GHz', '+36 dBm', 'FCC PtMP, 4 W EIRP'],
      ['2.4 GHz', '+20 dBm', 'ETSI, 100 mW EIRP'],
      ['5 GHz', '+30 dBm', 'FCC U-NII-1, 1 W EIRP (typ.)'],
      ['5 GHz', '+30 dBm', 'ETSI 5.8 GHz, 1 W EIRP'],
      ['6 GHz', '+36 dBm', 'FCC 6 GHz SP, 4 W EIRP'],
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
            'Regulatory EIRP limits',
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
                  // 8px-grid column widths (GL-003 §4), matching the converter's
                  // reference card.
                  SizedBox(
                    width: 72,
                    child: Text(
                      row[0],
                      style: mono.inlineCode.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 80,
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
                      style: text.labelMedium?.copyWith(
                        color: AppColors.textTertiary,
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

/// Single label + input row with an inline unit hint. Mirrors the dBm/Watt
/// converter's `_ConverterField` so the two screens stay visually identical.
class _ConverterField extends StatelessWidget {
  const _ConverterField({
    required this.label,
    required this.unitHint,
    required this.controller,
    required this.focusNode,
    required this.formatters,
    required this.onChanged,
    required this.monoStyle,
    required this.keyboardType,
    required this.hint,
  });

  final String label;
  final String unitHint;
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<TextInputFormatter> formatters;
  final ValueChanged<String> onChanged;
  final TextStyle monoStyle;
  final TextInputType keyboardType;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      label: label,
      hint: '($unitHint)',
      semanticLabel: '$label in $unitHint',
      field: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        inputFormatters: formatters,
        onChanged: onChanged,
        textInputAction: TextInputAction.next,
        autocorrect: false,
        enableSuggestions: false,
        style: monoStyle.copyWith(fontSize: AppTextSize.fieldNumeric),
        cursorColor: AppColors.primary,
        decoration: InputDecoration(hintText: hint),
      ),
    );
  }
}
