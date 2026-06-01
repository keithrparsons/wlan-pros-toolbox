// Free Space Path Loss (FSPL) calculator.
//
// Single-output calculator: enter frequency and distance, read loss in dB.
// Formula matches the RF Tools PWA reference (app.js calcFSPL, line 277):
//   loss(dB) = 20 · log10(f_GHz) + 20 · log10(d_km) + 92.45
//
// Unit conventions mirror the PWA dropdowns exactly:
//   Frequency — GHz (default) or MHz; MHz is divided by 1000 to GHz (toGHz).
//   Distance  — km (default), mi, or m; mi ×1.60934, m ÷1000 to km (toKm).
// The 92.45 constant is the km/GHz form of FSPL, so both inputs normalize to
// GHz and km before the math. Output is rounded to 1 decimal to match the PWA
// fmt(loss, 1).
//
// Edge cases:
// - Empty / partial input on either field → blank the dB output (no crash).
// - Frequency or distance <= 0 → log10 undefined / negative-infinite; show "—".
//
// Pure, no network, no platform APIs. Math lives in static functions so it is
// unit-testable against the PWA values.

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

/// Frequency input units, mirroring the PWA fspl-freq-unit select.
enum FreqUnit { ghz, mhz }

/// Distance input units, mirroring the PWA fspl-dist-unit select.
enum DistUnit { km, mi, m }

class FsplScreen extends StatefulWidget {
  const FsplScreen({super.key});

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Mirrors app.js: toGHz, toKm, calcFSPL.

  /// Normalize a frequency value to GHz (PWA toGHz).
  static double freqToGHz(double value, FreqUnit unit) {
    switch (unit) {
      case FreqUnit.mhz:
        return value / 1000.0;
      case FreqUnit.ghz:
        return value;
    }
  }

  /// Normalize a distance value to km (PWA toKm).
  static double distToKm(double value, DistUnit unit) {
    switch (unit) {
      case DistUnit.mi:
        return value * 1.60934;
      case DistUnit.m:
        return value / 1000.0;
      case DistUnit.km:
        return value;
    }
  }

  /// Free space path loss in dB given frequency in GHz and distance in km.
  /// 20·log10(f) + 20·log10(d) + 92.45 (PWA calcFSPL).
  static double fsplDb(double freqGHz, double distKm) {
    return 20 * _log10(freqGHz) + 20 * _log10(distKm) + 92.45;
  }

  static double _log10(double x) => math.log(x) / math.ln10;

  @override
  State<FsplScreen> createState() => _FsplScreenState();
}

class _FsplScreenState extends State<FsplScreen> {
  final TextEditingController _freqCtrl = TextEditingController();
  final TextEditingController _distCtrl = TextEditingController();

  final FocusNode _freqFocus = FocusNode();
  final FocusNode _distFocus = FocusNode();

  FreqUnit _freqUnit = FreqUnit.ghz;
  DistUnit _distUnit = DistUnit.km;

  // Computed loss in dB, or null when input is empty / invalid / non-positive.
  double? _lossDb;

  // Unsigned-decimal only. Frequency and distance are always positive humans
  // type by hand, so no sign and no scientific notation here.
  static final List<TextInputFormatter> _unsignedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

  @override
  void dispose() {
    _freqCtrl.dispose();
    _distCtrl.dispose();
    _freqFocus.dispose();
    _distFocus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    final double? freq = _tryParseDouble(_freqCtrl.text);
    final double? dist = _tryParseDouble(_distCtrl.text);
    if (freq == null || dist == null) {
      setState(() => _lossDb = null);
      return;
    }
    final double f = FsplScreen.freqToGHz(freq, _freqUnit);
    final double d = FsplScreen.distToKm(dist, _distUnit);
    // PWA guards f <= 0 || d <= 0 before computing; do the same so we never
    // render a -Infinity or NaN result.
    if (f <= 0 || d <= 0) {
      setState(() => _lossDb = null);
      return;
    }
    setState(() => _lossDb = FsplScreen.fsplDb(f, d));
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  static double? _tryParseDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '.') return null;
    return double.tryParse(s);
  }

  /// PWA fmt(loss, 1): fixed 1-decimal, "—" when not finite.
  static String _formatLoss(double? loss) {
    if (loss == null || !loss.isFinite) return '—';
    return loss.toStringAsFixed(1);
  }

  /// §8.16 copy payload — the FSPL result as a labeled text block.
  ///
  /// Returns null (→ disabled affordance) whenever there is no valid result:
  /// an empty/invalid or non-positive frequency or distance. Echoes the inputs
  /// with the currently-selected units, then the computed loss in dB.
  String? _buildCopyText() {
    final double? loss = _lossDb;
    if (loss == null || !loss.isFinite) return null;

    final String freqUnit = _freqUnit == FreqUnit.ghz ? 'GHz' : 'MHz';
    final String distUnit = _distUnitLabel(_distUnit);
    return (StringBuffer()
          ..writeln('Free Space Path Loss')
          ..writeln('Frequency: ${_freqCtrl.text.trim()} $freqUnit')
          ..writeln('Distance: ${_distCtrl.text.trim()} $distUnit')
          ..writeln('Path loss: ${_formatLoss(loss)} dB'))
        .toString()
        .trimRight();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('FSPL'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until frequency
        // and distance yield a finite loss; copies the inputs with their
        // selected units and the path loss in dB as a labeled text block.
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
                      ConceptGraphicBand(toolId: 'fspl', isDesktop: isDesktop),
                      if (ToolAssets.hasGraphic('fspl'))
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
          _inputRow(
            label: 'Frequency',
            unitHint: _freqUnit == FreqUnit.ghz ? 'GHz' : 'MHz',
            semanticLabel: 'Frequency',
            controller: _freqCtrl,
            focusNode: _freqFocus,
            hintText: '2.4',
            monoStyle: mono.outputLarge,
            unitSelector: _freqUnitSelector(text),
          ),
          const SizedBox(height: AppSpacing.sm),
          _inputRow(
            label: 'Distance',
            unitHint: _distUnitLabel(_distUnit),
            semanticLabel: 'Distance',
            controller: _distCtrl,
            focusNode: _distFocus,
            hintText: '1',
            monoStyle: mono.outputLarge,
            unitSelector: _distUnitSelector(text),
          ),
          const SizedBox(height: AppSpacing.md),
          _resultRow(text, mono),
        ],
      ),
    );
  }

  Widget _inputRow({
    required String label,
    required String unitHint,
    required String semanticLabel,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required TextStyle monoStyle,
    required Widget unitSelector,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: LabeledField(
            label: label,
            hint: '($unitHint)',
            semanticLabel: '$semanticLabel in $unitHint',
            field: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: _unsignedDecimal,
              onChanged: (_) => _recompute(),
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              style: monoStyle.copyWith(fontSize: AppTextSize.fieldNumeric),
              cursorColor: AppColors.primary,
              decoration: InputDecoration(hintText: hintText),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        unitSelector,
      ],
    );
  }

  Widget _resultRow(TextTheme text, AppMonoText mono) {
    // Single SR node: "Free space path loss: 100.1 dB" (or "not calculated"),
    // instead of the value, unit, and label announcing as separate fragments
    // (Vera finding #6).
    final bool blank = _lossDb == null;
    return Semantics(
      label: 'Free space path loss',
      value: blank ? 'not calculated' : '${_formatLoss(_lossDb)} dB',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Free space path loss',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SelectableText(
                _formatLoss(_lossDb),
                style: mono.outputXL.copyWith(
                  color: blank ? AppColors.textTertiary : AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'dB',
                style: text.labelLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _freqUnitSelector(TextTheme text) {
    return AppToggle<FreqUnit>(
      value: _freqUnit,
      items: const [(FreqUnit.ghz, 'GHz'), (FreqUnit.mhz, 'MHz')],
      onChanged: (u) {
        setState(() => _freqUnit = u);
        _recompute();
      },
    );
  }

  Widget _distUnitSelector(TextTheme text) {
    return AppToggle<DistUnit>(
      value: _distUnit,
      items: const [
        (DistUnit.km, 'km'),
        (DistUnit.mi, 'mi'),
        (DistUnit.m, 'm'),
      ],
      onChanged: (u) {
        setState(() => _distUnit = u);
        _recompute();
      },
    );
  }

  static String _distUnitLabel(DistUnit u) {
    switch (u) {
      case DistUnit.km:
        return 'km';
      case DistUnit.mi:
        return 'mi';
      case DistUnit.m:
        return 'm';
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
            'FSPL(dB) = 20·log₁₀(f) + 20·log₁₀(d) + 92.45',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'f in GHz, d in km. The 92.45 constant folds in c and the '
            'unit conversion for the GHz/km form.',
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
    // Compact anchor values. Each is FSPL at 1 km for a common Wi-Fi band,
    // plus a short-range row, computed from the same formula this screen uses.
    final List<List<String>> refs = const [
      ['2.4 GHz', '1 km', '100.1 dB'],
      ['5 GHz', '1 km', '106.4 dB'],
      ['6 GHz', '1 km', '108.0 dB'],
      ['2.4 GHz', '100 m', '80.1 dB'],
      ['5 GHz', '100 m', '86.4 dB'],
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
            'Reference points',
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
                    width: 80,
                    child: Text(
                      row[1],
                      style: mono.inlineCode.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row[2],
                      style: mono.inlineCode.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
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
