// Fresnel Zone calculator.
//
// First Fresnel zone radius for a point-to-point link, plus the 60% clearance
// value planners use as the "keep it clear" threshold. Formula and behavior
// match the RF Tools PWA reference (app.js calcFresnel):
//   lambda = 0.3 / f_GHz            wavelength in meters (c/f, c = 3e8)
//   r(d1,d2) = sqrt(lambda * d1 * d2 / (d1 + d2))   d1,d2 in meters
//   r_mid    = r(D/2, D/2) = sqrt(lambda * D / 4)   maximum, at the midpoint
//   clearance60 = r * 0.6
//
// PWA inputs accept GHz/MHz for frequency and km/mi/m for distance, then
// normalize to GHz and meters before the math. This screen fixes the units to
// the PWA's normalized base — frequency in GHz, distances in meters, output in
// meters — so native and PWA agree to the decimal for the same physical input.
// Feet are shown alongside meters exactly as the PWA does (r * 3.28084).
//
// Inputs:
// - Frequency (GHz) — required.
// - Total path distance (m) — required.
// - Point from TX (m) — optional. Blank means midpoint only. When set inside
//   the path it adds an at-point radius using the asymmetric formula, mirroring
//   the PWA fz-d1 behavior.
//
// Edge cases (match PWA: it refuses to compute and the native screen blanks):
// - Empty / invalid frequency or distance -> blank all outputs (no crash).
// - Frequency <= 0 or distance <= 0 -> blank outputs (PWA shows an error).
// - Point outside (0, D) -> ignored, midpoint result still shown.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// Result of a Fresnel computation. All radii in meters. Null fields mean the
/// corresponding value is not computable from the current inputs.
@immutable
class FresnelResult {
  const FresnelResult({
    required this.radiusMid,
    required this.clearanceMid,
    this.radiusAtPoint,
    this.clearanceAtPoint,
  });

  /// First-zone radius at the midpoint (the maximum radius along the path).
  final double radiusMid;

  /// 60% clearance at the midpoint.
  final double clearanceMid;

  /// First-zone radius at the entered point from TX, when one is inside (0, D).
  final double? radiusAtPoint;

  /// 60% clearance at that point.
  final double? clearanceAtPoint;
}

class FresnelScreen extends StatefulWidget {
  const FresnelScreen({super.key});

  // ─── Math (pure) ────────────────────────────────────────────────────────────
  // Mirrors app.js calcFresnel. Frequency in GHz, distances in meters.

  /// Wavelength in meters from a frequency in GHz. lambda = c / f, c = 3e8.
  /// app.js writes this as 0.3 / f with f in GHz.
  static double wavelengthMeters(double freqGHz) => 0.3 / freqGHz;

  /// First Fresnel zone radius (n = 1) in meters at a point that splits the
  /// path into d1 and d2 (both meters). r = sqrt(lambda * d1 * d2 / (d1 + d2)).
  static double firstZoneRadius({
    required double freqGHz,
    required double d1Meters,
    required double d2Meters,
  }) {
    final double lambda = wavelengthMeters(freqGHz);
    final double sum = d1Meters + d2Meters;
    return math.sqrt(lambda * d1Meters * d2Meters / sum);
  }

  /// Full computation for the screen. Returns null when frequency or total
  /// distance is missing or non-positive, matching the PWA's refusal to render.
  static FresnelResult? compute({
    required double? freqGHz,
    required double? totalMeters,
    double? pointFromTxMeters,
  }) {
    if (freqGHz == null || totalMeters == null) return null;
    if (!freqGHz.isFinite || !totalMeters.isFinite) return null;
    if (freqGHz <= 0 || totalMeters <= 0) return null;

    // Midpoint is always shown: d1 = d2 = D/2.
    final double half = totalMeters / 2;
    final double rMid = firstZoneRadius(
      freqGHz: freqGHz,
      d1Meters: half,
      d2Meters: half,
    );

    double? rAt;
    double? clearAt;
    if (pointFromTxMeters != null &&
        pointFromTxMeters.isFinite &&
        pointFromTxMeters > 0) {
      final double d1 = pointFromTxMeters;
      final double d2 = totalMeters - d1;
      if (d1 > 0 && d2 > 0) {
        rAt = firstZoneRadius(freqGHz: freqGHz, d1Meters: d1, d2Meters: d2);
        clearAt = rAt * 0.6;
      }
    }

    return FresnelResult(
      radiusMid: rMid,
      clearanceMid: rMid * 0.6,
      radiusAtPoint: rAt,
      clearanceAtPoint: clearAt,
    );
  }

  @override
  State<FresnelScreen> createState() => _FresnelScreenState();
}

class _FresnelScreenState extends State<FresnelScreen> {
  final TextEditingController _freqCtrl = TextEditingController();
  final TextEditingController _distCtrl = TextEditingController();
  final TextEditingController _pointCtrl = TextEditingController();

  final FocusNode _freqFocus = FocusNode();
  final FocusNode _distFocus = FocusNode();
  final FocusNode _pointFocus = FocusNode();

  // Unsigned decimal only — frequency and distances are never negative and are
  // typed by humans, not pasted from instruments (no scientific notation here).
  static final List<TextInputFormatter> _unsignedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

  FresnelResult? _result;

  @override
  void dispose() {
    _freqCtrl.dispose();
    _distCtrl.dispose();
    _pointCtrl.dispose();
    _freqFocus.dispose();
    _distFocus.dispose();
    _pointFocus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    setState(() {
      _result = FresnelScreen.compute(
        freqGHz: _tryParseDouble(_freqCtrl.text),
        totalMeters: _tryParseDouble(_distCtrl.text),
        pointFromTxMeters: _tryParseDouble(_pointCtrl.text),
      );
    });
  }

  // ─── Formatting ─────────────────────────────────────────────────────────────

  static double? _tryParseDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '.') return null;
    return double.tryParse(s);
  }

  /// app.js fmt(n, 1): 1-decimal fixed, em dash for non-finite. We use the same
  /// ASCII "—" the dBm/Watt screen settled on (Vera F-08) for empty results.
  static String _fmtMeters(double? n) {
    if (n == null || !n.isFinite) return '—';
    return n.toStringAsFixed(1);
  }

  /// Companion feet value, matching the PWA's r * 3.28084 second column.
  static String _fmtFeet(double? meters) {
    if (meters == null || !meters.isFinite) return '—';
    return (meters * 3.28084).toStringAsFixed(1);
  }

  /// §8.16 copy payload — the Fresnel radii as a labeled text block.
  ///
  /// Returns null (→ disabled affordance) whenever there is no valid result:
  /// a missing/non-positive frequency or total distance. Echoes the inputs, the
  /// midpoint first-zone radius + 60% clearance (m and ft, mirroring the
  /// on-screen pair), then the at-point pair when an in-path point was entered.
  String? _buildCopyText() {
    final FresnelResult? r = _result;
    if (r == null) return null;

    String line(double m) => '${_fmtMeters(m)} m (${_fmtFeet(m)} ft)';
    final StringBuffer buf = StringBuffer()
      ..writeln('Fresnel Zone')
      ..writeln('Frequency: ${_freqCtrl.text.trim()} GHz')
      ..writeln('Total path distance: ${_distCtrl.text.trim()} m');
    if (_pointCtrl.text.trim().isNotEmpty) {
      buf.writeln('Point from TX: ${_pointCtrl.text.trim()} m');
    }
    buf
      ..writeln('Midpoint first zone radius: ${line(r.radiusMid)}')
      ..writeln('Midpoint 60% clearance: ${line(r.clearanceMid)}');
    if (r.radiusAtPoint != null && r.clearanceAtPoint != null) {
      buf
        ..writeln('At-point first zone radius: ${line(r.radiusAtPoint!)}')
        ..writeln('At-point 60% clearance: ${line(r.clearanceAtPoint!)}');
    }
    return buf.toString().trimRight();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fresnel Zone'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until frequency
        // and total distance yield a valid midpoint radius; copies the inputs
        // and the midpoint (and at-point, when present) radii as a labeled block.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
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
                      // bundled (with the gap below it).
                      ConceptGraphicBand(
                        toolId: 'fresnel',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('fresnel'))
                        const SizedBox(height: AppSpacing.md),
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _resultCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _formulaCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _referenceCard(text, mono),
                      ToolHelpFooter(toolId: 'fresnel'),
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
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InputField(
            label: 'Frequency',
            unitHint: 'GHz',
            controller: _freqCtrl,
            focusNode: _freqFocus,
            formatters: _unsignedDecimal,
            onChanged: (_) => _recompute(),
            monoStyle: mono.outputLarge,
            hintText: '5.8',
          ),
          const SizedBox(height: AppSpacing.sm),
          _InputField(
            label: 'Total path distance',
            unitHint: 'm',
            controller: _distCtrl,
            focusNode: _distFocus,
            formatters: _unsignedDecimal,
            onChanged: (_) => _recompute(),
            monoStyle: mono.outputLarge,
            hintText: '10000',
          ),
          const SizedBox(height: AppSpacing.sm),
          _InputField(
            label: 'Point from TX',
            unitHint: 'm, optional',
            controller: _pointCtrl,
            focusNode: _pointFocus,
            formatters: _unsignedDecimal,
            onChanged: (_) => _recompute(),
            monoStyle: mono.outputLarge,
            hintText: 'midpoint',
          ),
        ],
      ),
    );
  }

  Widget _resultCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final FresnelResult? r = _result;
    final bool hasPoint = r?.radiusAtPoint != null;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'At midpoint',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _resultRow(
            text,
            mono,
            label: 'First zone radius',
            meters: r?.radiusMid,
          ),
          _resultRow(
            text,
            mono,
            label: '60% clearance',
            meters: r?.clearanceMid,
          ),
          if (hasPoint) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'At entered point',
              style: text.labelMedium?.copyWith(
                color: colors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            _resultRow(
              text,
              mono,
              label: 'First zone radius',
              meters: r?.radiusAtPoint,
            ),
            _resultRow(
              text,
              mono,
              label: '60% clearance',
              meters: r?.clearanceAtPoint,
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultRow(
    TextTheme text,
    AppMonoText mono, {
    required String label,
    required double? meters,
  }) {
    final AppColorScheme colors = context.colors;
    // One SR node per row: "First zone radius: 4.5 m, 14.8 ft" (or "not
    // calculated"), instead of label/value/unit fragments (Vera finding #6).
    final bool blank = meters == null || !meters.isFinite;
    return Semantics(
      label: label,
      value: blank
          ? 'not calculated'
          : '${_fmtMeters(meters)} m, ${_fmtFeet(meters)} ft',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: text.labelLarge?.copyWith(color: colors.textPrimary),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${_fmtMeters(meters)} m',
                  style: mono.outputMedium.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  '${_fmtFeet(meters)} ft',
                  style: mono.inlineCode.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _formulaCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Formula',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(
            'lambda = 0.3 / f(GHz)',
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
          SelectableText(
            'r = √(lambda · d1 · d2 / (d1 + d2))',
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
          SelectableText(
            'clearance = 0.6 · r',
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    // Compact anchor values: first-zone midpoint radius for common Wi-Fi
    // point-to-point bands over a 1 km path, computed from this screen's math.
    // Gives a quick sanity feel for the live result.
    final List<List<String>> refs = const [
      ['2.4 GHz', '5.6 m', 'r at midpoint, 1 km path'],
      ['5 GHz', '3.9 m', 'r at midpoint, 1 km path'],
      ['6 GHz', '3.5 m', 'r at midpoint, 1 km path'],
      ['60% rule', '0.6 · r', 'Minimum clearance for a reliable link'],
    ];

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reference points',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
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
                  SizedBox(
                    width: 96,
                    child: Text(
                      row[0],
                      style: mono.inlineCode.copyWith(
                        color: colors.textAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    child: Text(
                      row[1],
                      style: mono.inlineCode.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row[2],
                      style: text.labelMedium?.copyWith(
                        color: colors.textTertiary,
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

/// Single label + input row. Mirrors the dBm/Watt screen's _ConverterField so
/// the input fields stay visually and semantically consistent across tools.
class _InputField extends StatelessWidget {
  const _InputField({
    required this.label,
    required this.unitHint,
    required this.controller,
    required this.focusNode,
    required this.formatters,
    required this.onChanged,
    required this.monoStyle,
    required this.hintText,
  });

  final String label;
  final String unitHint;
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<TextInputFormatter> formatters;
  final ValueChanged<String> onChanged;
  final TextStyle monoStyle;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return LabeledField(
      label: label,
      hint: '($unitHint)',
      semanticLabel: '$label in $unitHint',
      field: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: formatters,
        onChanged: onChanged,
        textInputAction: TextInputAction.done,
        autocorrect: false,
        enableSuggestions: false,
        style: monoStyle.copyWith(fontSize: AppTextSize.fieldNumeric),
        cursorColor: colors.textAccent,
        decoration: InputDecoration(hintText: hintText),
      ),
    );
  }
}
