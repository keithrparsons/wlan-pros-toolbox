// ITU Rain Fade calculator.
//
// Estimates rain attenuation on a microwave Wi-Fi backhaul link. Matters most
// above 10 GHz, where rain absorbs and scatters the signal.
//
// Math matches the RF Tools PWA reference (app.js calcRainFade, line 514) and
// the ITU_RAIN coefficient table (app.js line 79). Two ITU recommendations:
//   ITU-R P.838-3 — specific attenuation:   gamma = k · R^alpha   (dB/km)
//   ITU-R P.530   — path-length reduction:   L_eff = L / (1 + L/d0)
//                   with d0 = 35 · e^(-0.015·R)
//   Rain attenuation = gamma · L_eff   (dB)
//
// k and alpha come from the P.838-3 [freq, kH, alphaH, kV, alphaV] table,
// reproduced verbatim from the PWA's ITU_RAIN constant. Off-table frequencies
// use the PWA's log-log interpolation on frequency (log-linear on alpha);
// frequencies at or beyond the table ends clamp to the nearest node.
//
// Unit conventions mirror the PWA inputs exactly:
//   Frequency  — GHz (fixed; PWA has no toggle here).
//   Rain rate  — mm/hr.
//   Path length — km (default) or mi; mi ×1.60934 to km (PWA toKm).
//   Polarization — Horizontal or Vertical (PWA H / V select).
//
// Outputs match the PWA fmt() decimals:
//   Rain attenuation       — dB,    2 decimals  (fmt(attenuation, 2))
//   Specific attenuation γ — dB/km, 4 decimals  (fmt(gamma, 4))
//   Effective path length  — km,    2 decimals  (fmt(L_eff, 2))
//
// Edge cases (PWA guards f/R/L all finite and > 0):
// - Empty / partial input on any field → blank all outputs (no crash).
// - Any of frequency, rain rate, path length <= 0 → blank outputs, show "—".
//
// Pure, no network, no platform APIs. Math lives in static functions on the
// public class so it is unit-testable against the PWA values.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/field_unit_row.dart';
import '../../../widgets/app_toggle.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// Path-length input units, mirroring the PWA rf-dist-unit select (km / mi).
enum PathUnit { km, mi }

/// Wave polarization, mirroring the PWA rf-pol select (H / V).
enum Polarization { horizontal, vertical }

class RainFadeScreen extends StatefulWidget {
  const RainFadeScreen({super.key});

  // ─── Coefficient table (ITU-R P.838-3) ─────────────────────────────────────
  // Reproduced verbatim from the PWA ITU_RAIN constant (app.js line 79).
  // Each row: [freqGHz, kH, alphaH, kV, alphaV].
  static const List<List<double>> ituRain = [
    [1, 0.0000387, 0.912, 0.0000352, 0.880],
    [2, 0.000154, 0.963, 0.000138, 0.923],
    [4, 0.000650, 1.121, 0.000591, 1.075],
    [6, 0.00175, 1.308, 0.00155, 1.265],
    [7, 0.00301, 1.332, 0.00265, 1.312],
    [8, 0.00454, 1.327, 0.00395, 1.310],
    [10, 0.0101, 1.276, 0.00887, 1.264],
    [12, 0.0188, 1.217, 0.0168, 1.200],
    [15, 0.0367, 1.154, 0.0335, 1.128],
    [20, 0.0751, 1.099, 0.0691, 1.065],
    [25, 0.124, 1.061, 0.113, 1.030],
    [30, 0.187, 1.021, 0.167, 1.000],
    [35, 0.263, 0.979, 0.233, 0.963],
    [40, 0.350, 0.939, 0.310, 0.929],
    [50, 0.536, 0.873, 0.479, 0.868],
    [60, 0.707, 0.826, 0.642, 0.824],
    [80, 0.975, 0.769, 0.906, 0.769],
    [100, 1.12, 0.743, 1.06, 0.744],
  ];

  // ─── Math (pure) ────────────────────────────────────────────────────────────
  // Mirrors app.js: toKm, interpolateITU, calcRainFade.

  /// Normalize a path length to km (PWA toKm). Only km / mi here, matching the
  /// PWA rf-dist-unit options. mi ×1.60934.
  static double pathToKm(double value, PathUnit unit) {
    switch (unit) {
      case PathUnit.mi:
        return value * 1.60934;
      case PathUnit.km:
        return value;
    }
  }

  /// Look up (k, alpha) for [freqGHz] at the given polarization, with the PWA's
  /// log-log frequency interpolation (PWA interpolateITU). Returns a record
  /// `(k, alpha)`. Clamps to the nearest node outside the table range.
  static (double k, double alpha) interpolateITU(
    double freqGHz,
    Polarization pol,
  ) {
    // polIdx 0 → H columns (kH=1, alphaH=2); 1 → V columns (kV=3, alphaV=4).
    final int polIdx = pol == Polarization.horizontal ? 0 : 1;
    final int ki = 1 + polIdx * 2;
    final int ai = 2 + polIdx * 2;

    final List<List<double>> t = ituRain;
    if (freqGHz <= t[0][0]) return (t[0][ki], t[0][ai]);
    final List<double> last = t[t.length - 1];
    if (freqGHz >= last[0]) return (last[ki], last[ai]);

    for (int i = 0; i < t.length - 1; i++) {
      final double f1 = t[i][0];
      final double f2 = t[i + 1][0];
      if (freqGHz >= f1 && freqGHz <= f2) {
        // log-log interpolation on frequency; log-linear on alpha.
        final double frac =
            (math.log(freqGHz) - math.log(f1)) / (math.log(f2) - math.log(f1));
        final double k = math.exp(
          math.log(t[i][ki]) +
              frac * (math.log(t[i + 1][ki]) - math.log(t[i][ki])),
        );
        final double a = t[i][ai] + frac * (t[i + 1][ai] - t[i][ai]);
        return (k, a);
      }
    }
    // Unreachable given the clamps above; satisfies the return contract.
    return (last[ki], last[ai]);
  }

  /// Specific attenuation gamma in dB/km (ITU-R P.838-3): k · R^alpha.
  static double specificAttenuation(
    double freqGHz,
    double rainRateMmHr,
    Polarization pol,
  ) {
    final (double k, double alpha) = interpolateITU(freqGHz, pol);
    return k * math.pow(rainRateMmHr, alpha).toDouble();
  }

  /// Effective path length in km (simplified ITU-R P.530-17):
  /// L / (1 + L/d0), d0 = 35 · e^(-0.015·R).
  static double effectivePathKm(double pathKm, double rainRateMmHr) {
    final double d0 = 35 * math.exp(-0.015 * rainRateMmHr);
    return pathKm / (1 + pathKm / d0);
  }

  /// Total rain attenuation in dB: gamma · L_eff (PWA calcRainFade).
  static double rainAttenuationDb(
    double freqGHz,
    double rainRateMmHr,
    double pathKm,
    Polarization pol,
  ) {
    final double gamma = specificAttenuation(freqGHz, rainRateMmHr, pol);
    final double leff = effectivePathKm(pathKm, rainRateMmHr);
    return gamma * leff;
  }

  @override
  State<RainFadeScreen> createState() => _RainFadeScreenState();
}

class _RainFadeScreenState extends State<RainFadeScreen> {
  final TextEditingController _freqCtrl = TextEditingController();
  final TextEditingController _rainCtrl = TextEditingController();
  final TextEditingController _pathCtrl = TextEditingController();

  final FocusNode _freqFocus = FocusNode();
  final FocusNode _rainFocus = FocusNode();
  final FocusNode _pathFocus = FocusNode();

  PathUnit _pathUnit = PathUnit.km;
  Polarization _pol = Polarization.horizontal;

  // Computed outputs, or null when input is empty / invalid / non-positive.
  double? _attenDb;
  double? _gamma;
  double? _leffKm;

  // Unsigned-decimal only. Frequency, rain rate, and path length are positive
  // values typed by hand, so no sign and no scientific notation here.
  static final List<TextInputFormatter> _unsignedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

  @override
  void dispose() {
    _freqCtrl.dispose();
    _rainCtrl.dispose();
    _pathCtrl.dispose();
    _freqFocus.dispose();
    _rainFocus.dispose();
    _pathFocus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    final double? freq = _tryParseDouble(_freqCtrl.text);
    final double? rain = _tryParseDouble(_rainCtrl.text);
    final double? path = _tryParseDouble(_pathCtrl.text);
    if (freq == null || rain == null || path == null) {
      _blank();
      return;
    }
    final double pathKm = RainFadeScreen.pathToKm(path, _pathUnit);
    // PWA guards f <= 0 || R <= 0 || L <= 0 before computing.
    if (freq <= 0 || rain <= 0 || pathKm <= 0) {
      _blank();
      return;
    }
    final double gamma = RainFadeScreen.specificAttenuation(freq, rain, _pol);
    final double leff = RainFadeScreen.effectivePathKm(pathKm, rain);
    setState(() {
      _gamma = gamma;
      _leffKm = leff;
      _attenDb = gamma * leff;
    });
  }

  void _blank() {
    setState(() {
      _attenDb = null;
      _gamma = null;
      _leffKm = null;
    });
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  static double? _tryParseDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '.') return null;
    return double.tryParse(s);
  }

  /// PWA fmt(n, decimals): fixed decimals, "—" when not finite or null.
  static String _fmt(double? n, int decimals) {
    if (n == null || !n.isFinite) return '—';
    return n.toStringAsFixed(decimals);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rain Fade'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until frequency,
        // rain rate, and path length are all valid and > 0 (no attenuation);
        // copies the rain-fade breakdown as a labeled text block. Copy leads;
        // no help icon here.
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
                      ConceptGraphicBand(
                        toolId: 'rain-fade',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('rain-fade'))
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

  /// §8.16 copy payload — the rain-fade breakdown as a labeled text block.
  ///
  /// Returns null (→ disabled affordance) until frequency, rain rate, and path
  /// length are all valid and > 0, so there is no attenuation to keep. Inputs
  /// (path with its unit, polarization word) and outputs match the on-screen
  /// result rows.
  String? _buildCopyText() {
    final double? atten = _attenDb;
    if (atten == null || !atten.isFinite) return null;

    final String pathUnit = _pathUnit == PathUnit.km ? 'km' : 'mi';
    final String pol = _pol == Polarization.horizontal
        ? 'Horizontal'
        : 'Vertical';

    return (StringBuffer()
          ..writeln('Rain Fade')
          ..writeln('Frequency: ${_freqCtrl.text.trim()} GHz')
          ..writeln('Rain rate: ${_rainCtrl.text.trim()} mm/hr')
          ..writeln('Path length: ${_pathCtrl.text.trim()} $pathUnit')
          ..writeln('Polarization: $pol')
          ..writeln('Rain attenuation: ${_fmt(atten, 2)} dB')
          ..writeln('Specific attenuation (γ): ${_fmt(_gamma, 4)} dB/km')
          ..writeln('Effective path length: ${_fmt(_leffKm, 2)} km'))
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
          // Frequency — GHz, no unit toggle (PWA fixes this at GHz).
          LabeledField(
            label: 'Frequency',
            hint: '(GHz)',
            semanticLabel: 'Frequency in GHz',
            field: _numberField(
              controller: _freqCtrl,
              focusNode: _freqFocus,
              hintText: '11',
              monoStyle: mono.outputLarge,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Rain rate — mm/hr, no unit toggle.
          LabeledField(
            label: 'Rain rate',
            hint: '(mm/hr)',
            semanticLabel: 'Rain rate in millimeters per hour',
            field: _numberField(
              controller: _rainCtrl,
              focusNode: _rainFocus,
              hintText: '25',
              monoStyle: mono.outputLarge,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Typical: light 2, moderate 12, heavy 25, extreme 50 mm/hr.',
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Path length — km / mi toggle.
          _pathRow(mono),
          const SizedBox(height: AppSpacing.sm),
          // Polarization — H / V toggle, full width.
          _polRow(text),
          const SizedBox(height: AppSpacing.md),
          _resultRow(text, mono),
        ],
      ),
    );
  }

  TextField _numberField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required TextStyle monoStyle,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: _unsignedDecimal,
      onChanged: (_) => _recompute(),
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      style: monoStyle.copyWith(fontSize: AppTextSize.fieldNumeric),
      cursorColor: AppColors.primary,
      decoration: InputDecoration(hintText: hintText),
    );
  }

  Widget _pathRow(AppMonoText mono) {
    // FieldUnitRow reflows the unit selector beneath the field below 440px so
    // it never clips at phone widths (Vera web-demo gate, 2026-06-02).
    return FieldUnitRow(
      field: LabeledField(
        label: 'Path length',
        hint: _pathUnit == PathUnit.km ? '(km)' : '(mi)',
        semanticLabel:
            'Path length in ${_pathUnit == PathUnit.km ? 'kilometers' : 'miles'}',
        field: _numberField(
          controller: _pathCtrl,
          focusNode: _pathFocus,
          hintText: '10',
          monoStyle: mono.outputLarge,
        ),
      ),
      unit: AppToggle<PathUnit>(
        value: _pathUnit,
        items: const [(PathUnit.km, 'km'), (PathUnit.mi, 'mi')],
        onChanged: (u) {
          setState(() => _pathUnit = u);
          _recompute();
        },
      ),
    );
  }

  Widget _polRow(TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Polarization',
          style: text.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppToggle<Polarization>(
          value: _pol,
          items: const [
            (Polarization.horizontal, 'Horizontal'),
            (Polarization.vertical, 'Vertical'),
          ],
          onChanged: (p) {
            setState(() => _pol = p);
            _recompute();
          },
        ),
      ],
    );
  }

  Widget _resultRow(TextTheme text, AppMonoText mono) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rain attenuation',
          style: text.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // One SR node for the headline: "Rain attenuation: 12.50 dB" (or "not
        // calculated"), instead of value/unit fragments (Vera finding #6).
        Semantics(
          label: 'Rain attenuation',
          value: _attenDb == null
              ? 'not calculated'
              : '${_fmt(_attenDb, 2)} dB',
          excludeSemantics: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SelectableText(
                _fmt(_attenDb, 2),
                style: mono.outputXL.copyWith(
                  color: _attenDb == null
                      ? AppColors.textTertiary
                      : AppColors.primary,
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
        ),
        const SizedBox(height: AppSpacing.sm),
        // Secondary outputs, matching the PWA's gamma / L_eff result rows.
        _secondaryRow(
          text,
          mono,
          label: 'Specific attenuation (γ)',
          value: _fmt(_gamma, 4),
          unit: 'dB/km',
        ),
        const SizedBox(height: AppSpacing.xs),
        _secondaryRow(
          text,
          mono,
          label: 'Effective path length',
          value: _fmt(_leffKm, 2),
          unit: 'km',
        ),
      ],
    );
  }

  Widget _secondaryRow(
    TextTheme text,
    AppMonoText mono, {
    required String label,
    required String value,
    required String unit,
  }) {
    // One SR node per row: "Specific attenuation (γ): 0.0123 dB/km" (or "not
    // calculated"), instead of label/value/unit fragments (Vera finding #6).
    return Semantics(
      label: label,
      value: value == '—' ? 'not calculated' : '$value $unit',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              label,
              style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SelectableText(
            value,
            style: mono.inlineCode.copyWith(
              color: value == '—'
                  ? AppColors.textTertiary
                  : AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            unit,
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
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
            'γ = k · R^α            (dB/km)',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          SelectableText(
            'L_eff = L / (1 + L/d₀)  (km)',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          SelectableText(
            'A = γ · L_eff          (dB)',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'k and α from ITU-R P.838-3 by frequency and polarization. '
            'd₀ = 35 · e^(-0.015·R) per the simplified ITU-R P.530 path '
            'reduction. R is rain rate in mm/hr.',
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
    // Anchor values computed from the same coefficients this screen uses, at a
    // 10 km horizontal path. Shows how rain fade explodes with frequency.
    final List<List<String>> refs = const [
      ['6 GHz', '25 mm/hr', '0.83 dB'],
      ['11 GHz', '25 mm/hr', '5.43 dB'],
      ['18 GHz', '25 mm/hr', '14.97 dB'],
      ['11 GHz', '50 mm/hr', '11.36 dB'],
      ['23 GHz', '50 mm/hr', '42.99 dB'],
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
          Text(
            '10 km horizontal path.',
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
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
                    width: 80,
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
