// Antenna Downtilt calculator.
//
// Single-output calculator: enter antenna height (AGL) and target coverage
// distance, read the mechanical downtilt angle in degrees. Formula matches the
// RF Tools PWA reference (app.js calcDowntilt, line 447):
//   angle(deg) = atan(height_m / coverage_m) · (180 / π)
// The angle aims the beam center at the coverage radius on the ground.
//
// Unit conventions mirror the PWA dropdowns exactly (toMeters):
//   Height   — m (default) or ft; ft ×0.3048 to m.
//   Coverage — m (default), ft, or km; ft ×0.3048, km ×1000 to m.
// Both inputs normalize to meters before the math. Output is rounded to 2
// decimals to match the PWA fmt(angle, 2).
//
// Edge cases:
// - Empty / partial input on either field → blank the output (no crash).
// - Height or coverage <= 0 → undefined geometry; show "—".
//
// Pure, no network, no platform APIs. Math lives in static functions on the
// public DowntiltScreen class so it is unit-testable against the PWA values.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_toggle.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// Antenna height input units, mirroring the PWA dt-height-unit select.
enum HeightUnit { m, ft }

/// Coverage distance input units, mirroring the PWA dt-coverage-unit select.
enum CoverageUnit { m, ft, km }

class DowntiltScreen extends StatefulWidget {
  const DowntiltScreen({super.key});

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Mirrors app.js: toMeters, calcDowntilt.

  /// Normalize a height value to meters (PWA toMeters).
  static double heightToMeters(double value, HeightUnit unit) {
    switch (unit) {
      case HeightUnit.ft:
        return value * 0.3048;
      case HeightUnit.m:
        return value;
    }
  }

  /// Normalize a coverage distance value to meters (PWA toMeters).
  static double coverageToMeters(double value, CoverageUnit unit) {
    switch (unit) {
      case CoverageUnit.km:
        return value * 1000.0;
      case CoverageUnit.ft:
        return value * 0.3048;
      case CoverageUnit.m:
        return value;
    }
  }

  /// Downtilt angle in degrees so the beam center hits the coverage radius at
  /// ground level. atan(height / coverage) · 180/π (PWA calcDowntilt).
  static double downtiltDeg(double heightMeters, double coverageMeters) {
    return math.atan(heightMeters / coverageMeters) * (180 / math.pi);
  }

  @override
  State<DowntiltScreen> createState() => _DowntiltScreenState();
}

class _DowntiltScreenState extends State<DowntiltScreen> {
  final TextEditingController _heightCtrl = TextEditingController();
  final TextEditingController _coverageCtrl = TextEditingController();

  final FocusNode _heightFocus = FocusNode();
  final FocusNode _coverageFocus = FocusNode();

  HeightUnit _heightUnit = HeightUnit.m;
  CoverageUnit _coverageUnit = CoverageUnit.m;

  // Computed angle in degrees, or null when input is empty / invalid /
  // non-positive.
  double? _angleDeg;

  // Unsigned-decimal only. Height and coverage are always positive values a
  // human types by hand, so no sign and no scientific notation here.
  static final List<TextInputFormatter> _unsignedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

  @override
  void dispose() {
    _heightCtrl.dispose();
    _coverageCtrl.dispose();
    _heightFocus.dispose();
    _coverageFocus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    final double? height = _tryParseDouble(_heightCtrl.text);
    final double? coverage = _tryParseDouble(_coverageCtrl.text);
    if (height == null || coverage == null) {
      setState(() => _angleDeg = null);
      return;
    }
    final double h = DowntiltScreen.heightToMeters(height, _heightUnit);
    final double c = DowntiltScreen.coverageToMeters(coverage, _coverageUnit);
    // PWA guards height <= 0 || coverage <= 0 before computing; do the same so
    // we never divide by zero or render a degenerate angle.
    if (h <= 0 || c <= 0) {
      setState(() => _angleDeg = null);
      return;
    }
    setState(() => _angleDeg = DowntiltScreen.downtiltDeg(h, c));
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  static double? _tryParseDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '.') return null;
    return double.tryParse(s);
  }

  /// PWA fmt(angle, 2): fixed 2-decimal, "—" when not finite.
  static String _formatAngle(double? angle) {
    if (angle == null || !angle.isFinite) return '—';
    return angle.toStringAsFixed(2);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(title: const Text('Downtilt'), toolbarHeight: 64),
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
                        toolId: 'downtilt',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('downtilt'))
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
            label: 'Antenna height (AGL)',
            unitHint: _heightUnitLabel(_heightUnit),
            semanticLabel: 'Antenna height above ground level',
            controller: _heightCtrl,
            focusNode: _heightFocus,
            hintText: '30',
            monoStyle: mono.outputLarge,
            unitSelector: _heightUnitSelector(text),
          ),
          const SizedBox(height: AppSpacing.sm),
          _inputRow(
            label: 'Target coverage distance',
            unitHint: _coverageUnitLabel(_coverageUnit),
            semanticLabel: 'Target coverage distance',
            controller: _coverageCtrl,
            focusNode: _coverageFocus,
            hintText: '200',
            monoStyle: mono.outputLarge,
            unitSelector: _coverageUnitSelector(text),
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
    // One SR node: "Downtilt angle: 3.2 degrees" (or "not calculated"), instead
    // of value/unit/label fragments (Vera finding #6).
    final bool blank = _angleDeg == null;
    return Semantics(
      label: 'Downtilt angle',
      value: blank ? 'not calculated' : '${_formatAngle(_angleDeg)} degrees',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Downtilt angle',
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
                _formatAngle(_angleDeg),
                style: mono.outputXL.copyWith(
                  color: blank ? AppColors.textTertiary : AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                '°',
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

  Widget _heightUnitSelector(TextTheme text) {
    return AppToggle<HeightUnit>(
      value: _heightUnit,
      items: const [(HeightUnit.m, 'm'), (HeightUnit.ft, 'ft')],
      onChanged: (u) {
        setState(() => _heightUnit = u);
        _recompute();
      },
    );
  }

  Widget _coverageUnitSelector(TextTheme text) {
    return AppToggle<CoverageUnit>(
      value: _coverageUnit,
      items: const [
        (CoverageUnit.m, 'm'),
        (CoverageUnit.ft, 'ft'),
        (CoverageUnit.km, 'km'),
      ],
      onChanged: (u) {
        setState(() => _coverageUnit = u);
        _recompute();
      },
    );
  }

  static String _heightUnitLabel(HeightUnit u) {
    switch (u) {
      case HeightUnit.m:
        return 'm';
      case HeightUnit.ft:
        return 'ft';
    }
  }

  static String _coverageUnitLabel(CoverageUnit u) {
    switch (u) {
      case CoverageUnit.m:
        return 'm';
      case CoverageUnit.ft:
        return 'ft';
      case CoverageUnit.km:
        return 'km';
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
            'tilt(°) = atan(height / coverage) · 180/π',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Height and coverage in meters. The angle aims the beam center at '
            'the coverage radius on the ground.',
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
    // Compact anchor values. Each is the downtilt angle for a common ceiling /
    // mount height against a target coverage radius, computed from the same
    // formula this screen uses.
    final List<List<String>> refs = const [
      ['3 m', '10 m', '16.70°'],
      ['5 m', '20 m', '14.04°'],
      ['10 m', '50 m', '11.31°'],
      ['30 m', '200 m', '8.53°'],
      ['30 m', '500 m', '3.43°'],
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
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    'Height',
                    style: text.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    'Coverage',
                    style: text.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Tilt',
                    style: text.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
