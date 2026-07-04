// Point-to-Point (PtP) Link Check calculator.
//
// Full microwave / Wi-Fi backhaul link budget: from Tx power through antenna
// gains, cable losses, free-space path loss, and rain fade to the received
// signal, then compared against receiver sensitivity for a fade margin and a
// pass/fail verdict.
//
// Math matches the RF Tools PWA reference (app.js calcPtP, line 1336) exactly:
//   eirp     = txPow + txGain - txLoss
//   fspl     = 20·log10(d_km) + 20·log10(f_GHz) + 92.45
//   rainFade = γ · L_eff   (0 when rainRate == 0; ITU-R P.838-3 + P.530)
//   rxLevel  = eirp - fspl - rainFade + rxGain - rxLoss
//   margin   = rxLevel - rxSens
//   pass     = margin >= reqMargin
//
// The rain-fade leg reuses the same ITU-R P.838-3 coefficient table and
// log-log interpolation as the Rain Fade calculator (interpolateITU), kept
// here as a verbatim copy so this screen is self-contained and unit-testable.
//
// Unit / default conventions mirror the PWA inputs exactly:
//   Frequency  — GHz (fixed; PWA has no toggle).
//   Distance   — km (default) or mi; mi ×1.60934 to km (PWA toKm).
//   Tx power, Rx sensitivity — dBm (signed; sensitivity is typically negative).
//   Antenna gains — dBi. Cable losses — dB.
//   Tx/Rx loss default 0, rain rate default 0, required margin default 10
//     (PWA's isFinite(...) ? value : default fallbacks).
//   Polarization — Horizontal or Vertical (PWA H / V select).
//
// Outputs match the PWA fmt() decimals:
//   EIRP             — dBm, 1 decimal
//   Free space loss  — dB,  1 decimal
//   Rain fade        — dB,  2 decimals
//   Received signal  — dBm, 1 decimal
//   Link margin      — dB,  1 decimal
//
// Verdict thresholds are owned by this calculator (the PWA is binary PASS/FAIL
// on margin >= reqMargin). Three-state status, always paired with words, never
// color alone (GL-003 §8.13):
//   margin >= reqMargin           → PASS     (statusSuccess)
//   0 <= margin < reqMargin       → MARGINAL (statusWarning) — link closes but
//                                    below the required fade margin
//   margin < 0                    → FAIL     (statusDanger)  — link does not
//                                    close
// The binary pass field still mirrors the PWA exactly (margin >= reqMargin).
//
// Edge cases (PWA guards the six required fields finite; freq/dist > 0):
// - Any required field empty / invalid, or freq <= 0 / dist <= 0 → blank all
//   outputs and the verdict (no crash).
// - Optional fields (losses, rain, margin) blank → treated as their defaults.
//
// Pure, no network, no platform APIs. Math lives in static functions on the
// public class so it is unit-testable against the PWA values.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../utils/decimal_input.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/field_unit_row.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// Distance input units, mirroring the PWA ptp-dist-unit select (km / mi).
enum PtpDistUnit { km, mi }

/// Wave polarization, mirroring the PWA ptp-pol select (H / V).
enum PtpPolarization { horizontal, vertical }

/// Link verdict band. PASS / FAIL mirror the PWA's binary check; MARGINAL is
/// this calculator's added warning band (link closes but below the required
/// fade margin).
enum PtpVerdict { pass, marginal, fail }

/// The full computed link budget, mirroring the PWA's five result rows plus the
/// verdict. Null is never used here — callers compute this only with valid input
/// and otherwise hold a null `PtpResult?`.
class PtpResult {
  const PtpResult({
    required this.eirp,
    required this.fspl,
    required this.rainFade,
    required this.rxLevel,
    required this.margin,
    required this.pass,
  });

  /// Effective isotropic radiated power, dBm.
  final double eirp;

  /// Free space path loss, dB.
  final double fspl;

  /// Rain attenuation, dB (0 when rain rate is 0).
  final double rainFade;

  /// Received signal level at the far end, dBm.
  final double rxLevel;

  /// Link fade margin (rxLevel - rxSens), dB.
  final double margin;

  /// PWA-exact binary pass: margin >= requiredMargin.
  final bool pass;
}

class PtpLinkScreen extends StatefulWidget {
  const PtpLinkScreen({super.key});

  // ─── Coefficient table (ITU-R P.838-3) ─────────────────────────────────────
  // Verbatim copy of the PWA ITU_RAIN constant (app.js line 79), shared with the
  // Rain Fade calculator. Each row: [freqGHz, kH, alphaH, kV, alphaV].
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
  // Mirrors app.js: toKm, interpolateITU, calcPtP.

  /// Normalize a distance to km (PWA toKm). km / mi only here, matching the PWA
  /// ptp-dist-unit options. mi ×1.60934.
  static double distToKm(double value, PtpDistUnit unit) {
    switch (unit) {
      case PtpDistUnit.mi:
        return value * 1.60934;
      case PtpDistUnit.km:
        return value;
    }
  }

  static double _log10(double x) => math.log(x) / math.ln10;

  /// Free space path loss in dB (PWA: 20·log10(d) + 20·log10(f) + 92.45).
  static double fsplDb(double freqGHz, double distKm) {
    return 20 * _log10(distKm) + 20 * _log10(freqGHz) + 92.45;
  }

  /// (k, alpha) for [freqGHz] at the given polarization, PWA interpolateITU.
  /// Log-log on frequency, log-linear on alpha; clamps outside the table.
  static (double k, double alpha) interpolateITU(
    double freqGHz,
    PtpPolarization pol,
  ) {
    final int polIdx = pol == PtpPolarization.horizontal ? 0 : 1;
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
    return (last[ki], last[ai]);
  }

  /// Rain fade in dB (PWA calcPtP rain block). Returns 0 when [rainRateMmHr]
  /// is not > 0, matching the PWA `if (rainRate > 0)` guard.
  static double rainFadeDb(
    double freqGHz,
    double rainRateMmHr,
    double distKm,
    PtpPolarization pol,
  ) {
    if (!(rainRateMmHr > 0)) return 0;
    final (double k, double alpha) = interpolateITU(freqGHz, pol);
    final double gamma = k * math.pow(rainRateMmHr, alpha).toDouble();
    final double d0 = 35 * math.exp(-0.015 * rainRateMmHr);
    final double leff = distKm / (1 + distKm / d0);
    return gamma * leff;
  }

  /// The full link budget (PWA calcPtP). All inputs already in their canonical
  /// units: freq GHz, dist km, powers/gains/losses/sensitivity dB(m), rain
  /// mm/hr. [requiredMargin] only affects [PtpResult.pass].
  static PtpResult linkBudget({
    required double freqGHz,
    required double distKm,
    required double txPow,
    required double txGain,
    required double rxGain,
    required double txLoss,
    required double rxLoss,
    required double rainRateMmHr,
    required PtpPolarization pol,
    required double rxSens,
    required double requiredMargin,
  }) {
    final double eirp = txPow + txGain - txLoss;
    final double fspl = fsplDb(freqGHz, distKm);
    final double rainFade = rainFadeDb(freqGHz, rainRateMmHr, distKm, pol);
    final double rxLevel = eirp - fspl - rainFade + rxGain - rxLoss;
    final double margin = rxLevel - rxSens;
    return PtpResult(
      eirp: eirp,
      fspl: fspl,
      rainFade: rainFade,
      rxLevel: rxLevel,
      margin: margin,
      pass: margin >= requiredMargin,
    );
  }

  /// Three-state verdict band for the status readout. Thresholds owned here.
  static PtpVerdict verdictFor(double margin, double requiredMargin) {
    if (margin >= requiredMargin) return PtpVerdict.pass;
    if (margin >= 0) return PtpVerdict.marginal;
    return PtpVerdict.fail;
  }

  @override
  State<PtpLinkScreen> createState() => _PtpLinkScreenState();
}

class _PtpLinkScreenState extends State<PtpLinkScreen> {
  // Required inputs.
  final TextEditingController _freqCtrl = TextEditingController();
  final TextEditingController _distCtrl = TextEditingController();
  final TextEditingController _txPowCtrl = TextEditingController();
  final TextEditingController _txGainCtrl = TextEditingController();
  final TextEditingController _rxGainCtrl = TextEditingController();
  final TextEditingController _sensCtrl = TextEditingController();
  // Optional inputs (defaulted when blank).
  final TextEditingController _txLossCtrl = TextEditingController();
  final TextEditingController _rxLossCtrl = TextEditingController();
  final TextEditingController _rainCtrl = TextEditingController();
  final TextEditingController _reqMarginCtrl = TextEditingController();

  final FocusNode _freqFocus = FocusNode();
  final FocusNode _distFocus = FocusNode();
  final FocusNode _txPowFocus = FocusNode();
  final FocusNode _txGainFocus = FocusNode();
  final FocusNode _rxGainFocus = FocusNode();
  final FocusNode _sensFocus = FocusNode();
  final FocusNode _txLossFocus = FocusNode();
  final FocusNode _rxLossFocus = FocusNode();
  final FocusNode _rainFocus = FocusNode();
  final FocusNode _reqMarginFocus = FocusNode();

  PtpDistUnit _distUnit = PtpDistUnit.km;
  PtpPolarization _pol = PtpPolarization.horizontal;

  // Computed budget, or null when required input is empty / invalid.
  PtpResult? _result;
  // Required margin actually used (for verdict banding). Tracks the PWA default.
  double _reqMarginUsed = 10;

  // Unsigned decimal for positive-only fields (freq, dist, gains, losses, rain,
  // required margin).
  static final List<TextInputFormatter> _unsignedDecimal = unsignedDecimalFormatters;

  // Signed decimal for dBm fields (Tx power can be set low, Rx sensitivity is
  // typically negative). Leading '-' allowed.
  static final List<TextInputFormatter> _signedDecimal = signedDecimalFormatters;

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _freqCtrl,
      _distCtrl,
      _txPowCtrl,
      _txGainCtrl,
      _rxGainCtrl,
      _sensCtrl,
      _txLossCtrl,
      _rxLossCtrl,
      _rainCtrl,
      _reqMarginCtrl,
    ]) {
      c.dispose();
    }
    for (final FocusNode f in <FocusNode>[
      _freqFocus,
      _distFocus,
      _txPowFocus,
      _txGainFocus,
      _rxGainFocus,
      _sensFocus,
      _txLossFocus,
      _rxLossFocus,
      _rainFocus,
      _reqMarginFocus,
    ]) {
      f.dispose();
    }
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    // Required fields (PWA: isFinite guard on each).
    final double? freq = tryParseFlexibleDouble(_freqCtrl.text);
    final double? dist = tryParseFlexibleDouble(_distCtrl.text);
    final double? txPow = tryParseFlexibleDouble(_txPowCtrl.text);
    final double? txGain = tryParseFlexibleDouble(_txGainCtrl.text);
    final double? rxGain = tryParseFlexibleDouble(_rxGainCtrl.text);
    final double? rxSens = tryParseFlexibleDouble(_sensCtrl.text);

    // Optional fields fall back to PWA defaults when blank/invalid.
    final double txLoss = tryParseFlexibleDouble(_txLossCtrl.text) ?? 0;
    final double rxLoss = tryParseFlexibleDouble(_rxLossCtrl.text) ?? 0;
    final double rainRate = tryParseFlexibleDouble(_rainCtrl.text) ?? 0;
    final double reqMargin = tryParseFlexibleDouble(_reqMarginCtrl.text) ?? 10;

    if (freq == null ||
        dist == null ||
        txPow == null ||
        txGain == null ||
        rxGain == null ||
        rxSens == null) {
      setState(() => _result = null);
      return;
    }

    final double distKm = PtpLinkScreen.distToKm(dist, _distUnit);
    // PWA guards freq <= 0 and dist <= 0 before computing.
    if (freq <= 0 || distKm <= 0) {
      setState(() => _result = null);
      return;
    }

    final PtpResult res = PtpLinkScreen.linkBudget(
      freqGHz: freq,
      distKm: distKm,
      txPow: txPow,
      txGain: txGain,
      rxGain: rxGain,
      txLoss: txLoss,
      rxLoss: rxLoss,
      rainRateMmHr: rainRate,
      pol: _pol,
      rxSens: rxSens,
      requiredMargin: reqMargin,
    );
    setState(() {
      _result = res;
      _reqMarginUsed = reqMargin;
    });
  }

  // ─── Parsing / formatting ───────────────────────────────────────────────────

  /// Parse a signed decimal; null on empty or non-numeric (e.g. "-", ".").

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
        title: const Text('PtP Link Check'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until every
        // required field is valid (no link budget); copies the link budget as a
        // labeled text block, carrying the §8.13 PASS / MARGINAL / FAIL verdict
        // WORD. Copy leads; no help icon here.
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
                      // bundled, so the 24px gap below it disappears too.
                      ConceptGraphicBand(
                        toolId: 'ptp-link',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('ptp-link'))
                        const SizedBox(height: AppSpacing.md),
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _resultCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _formulaCard(text, mono),
                      ToolHelpFooter(toolId: 'ptp-link'),
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

  /// §8.16 copy payload — the PtP link budget as a labeled text block.
  ///
  /// Returns null (→ disabled affordance) until every required field is valid
  /// (freq/dist/Tx power/gains/sensitivity present, freq & distance > 0), so
  /// there is no link budget to keep. The verdict line carries the §8.13
  /// PASS / MARGINAL / FAIL WORD plus its detail; the margin and the five
  /// result rows match the on-screen result card.
  String? _buildCopyText() {
    final PtpResult? r = _result;
    if (r == null) return null;

    final PtpVerdict verdict = PtpLinkScreen.verdictFor(
      r.margin,
      _reqMarginUsed,
    );
    final String word;
    final String detail;
    switch (verdict) {
      case PtpVerdict.pass:
        word = 'PASS';
        detail = '${_fmt(r.margin, 1)} dB margin';
        break;
      case PtpVerdict.marginal:
        word = 'MARGINAL';
        detail =
            '${_fmt(r.margin, 1)} dB, below the ${_fmt(_reqMarginUsed, 0)} dB required';
        break;
      case PtpVerdict.fail:
        word = 'FAIL';
        detail = '${_fmt(r.margin.abs(), 1)} dB short';
        break;
    }

    return (StringBuffer()
          ..writeln('PtP Link Check')
          ..writeln('Verdict: $word — $detail')
          ..writeln('Link margin: ${_fmt(r.margin, 1)} dB')
          ..writeln('EIRP: ${_fmt(r.eirp, 1)} dBm')
          ..writeln('Free space loss: ${_fmt(r.fspl, 1)} dB')
          ..writeln('Rain fade: ${_fmt(r.rainFade, 2)} dB')
          ..writeln('Received signal: ${_fmt(r.rxLevel, 1)} dBm'))
        .toString()
        .trimRight();
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
          // Frequency — GHz, no toggle (PWA fixes GHz).
          LabeledField(
            label: 'Frequency',
            hint: '(GHz)',
            semanticLabel: 'Frequency in GHz',
            field: _numberField(
              controller: _freqCtrl,
              focusNode: _freqFocus,
              hintText: '5.8',
              monoStyle: mono.outputLarge,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Distance — km / mi toggle.
          _distRow(mono),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Tx power',
            hint: '(dBm)',
            semanticLabel: 'Transmit power in dBm',
            field: _numberField(
              controller: _txPowCtrl,
              focusNode: _txPowFocus,
              hintText: '20',
              monoStyle: mono.outputLarge,
              signed: true,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Tx antenna gain',
            hint: '(dBi)',
            semanticLabel: 'Transmit antenna gain in dBi',
            field: _numberField(
              controller: _txGainCtrl,
              focusNode: _txGainFocus,
              hintText: '23',
              monoStyle: mono.outputLarge,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Rx antenna gain',
            hint: '(dBi)',
            semanticLabel: 'Receive antenna gain in dBi',
            field: _numberField(
              controller: _rxGainCtrl,
              focusNode: _rxGainFocus,
              hintText: '23',
              monoStyle: mono.outputLarge,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Tx cable + connector loss',
            hint: '(dB, default 0)',
            semanticLabel: 'Transmit cable and connector loss in dB',
            field: _numberField(
              controller: _txLossCtrl,
              focusNode: _txLossFocus,
              hintText: '0',
              monoStyle: mono.outputLarge,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Rx cable + connector loss',
            hint: '(dB, default 0)',
            semanticLabel: 'Receive cable and connector loss in dB',
            field: _numberField(
              controller: _rxLossCtrl,
              focusNode: _rxLossFocus,
              hintText: '0',
              monoStyle: mono.outputLarge,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Rain rate',
            hint: '(mm/hr, 0 = clear)',
            semanticLabel: 'Rain rate in millimeters per hour, 0 for clear',
            field: _numberField(
              controller: _rainCtrl,
              focusNode: _rainFocus,
              hintText: '0',
              monoStyle: mono.outputLarge,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Polarization — only consulted when rain rate > 0.
          _polRow(text),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Receiver sensitivity',
            hint: '(dBm)',
            semanticLabel: 'Receiver sensitivity in dBm',
            field: _numberField(
              controller: _sensCtrl,
              focusNode: _sensFocus,
              hintText: '-80',
              monoStyle: mono.outputLarge,
              signed: true,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Required fade margin',
            hint: '(dB, default 10)',
            semanticLabel: 'Required fade margin in dB',
            field: _numberField(
              controller: _reqMarginCtrl,
              focusNode: _reqMarginFocus,
              hintText: '10',
              monoStyle: mono.outputLarge,
            ),
          ),
        ],
      ),
    );
  }

  TextField _numberField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required TextStyle monoStyle,
    bool signed = false,
  }) {
    final AppColorScheme colors = context.colors;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: signed,
      ),
      inputFormatters: signed ? _signedDecimal : _unsignedDecimal,
      onChanged: (_) => _recompute(),
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      style: monoStyle.copyWith(fontSize: AppTextSize.fieldNumeric),
      cursorColor: colors.textAccent,
      decoration: InputDecoration(hintText: hintText),
    );
  }

  Widget _distRow(AppMonoText mono) {
    // FieldUnitRow reflows the unit selector beneath the field below 440px so
    // it never clips at phone widths (Vera web-demo gate, 2026-06-02).
    return FieldUnitRow(
      field: LabeledField(
        label: 'Distance',
        hint: _distUnit == PtpDistUnit.km ? '(km)' : '(mi)',
        semanticLabel:
            'Link distance in ${_distUnit == PtpDistUnit.km ? 'kilometers' : 'miles'}',
        field: _numberField(
          controller: _distCtrl,
          focusNode: _distFocus,
          hintText: '5',
          monoStyle: mono.outputLarge,
        ),
      ),
      unit: AppToggle<PtpDistUnit>(
        value: _distUnit,
        items: const [(PtpDistUnit.km, 'km'), (PtpDistUnit.mi, 'mi')],
        onChanged: (u) {
          setState(() => _distUnit = u);
          _recompute();
        },
      ),
    );
  }

  Widget _polRow(TextTheme text) {
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Polarization',
          style: text.labelMedium?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // Full-word labels ("Horizontal" / "Vertical") are wide; stretch the
        // segmented control to the row width so the two options share the
        // available space instead of overflowing at narrow phone widths.
        AppToggle<PtpPolarization>(
          value: _pol,
          expand: true,
          items: const [
            (PtpPolarization.horizontal, 'Horizontal'),
            (PtpPolarization.vertical, 'Vertical'),
          ],
          onChanged: (p) {
            setState(() => _pol = p);
            _recompute();
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Only applied when rain rate is above 0.',
          style: text.labelSmall?.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }

  // ─── Result + verdict ───────────────────────────────────────────────────────

  Widget _resultCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final PtpResult? r = _result;

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
          _verdictBlock(text, mono, r),
          const SizedBox(height: AppSpacing.md),
          _resultRow(
            text,
            mono,
            label: 'EIRP',
            value: _fmt(r?.eirp, 1),
            unit: 'dBm',
          ),
          const SizedBox(height: AppSpacing.xs),
          _resultRow(
            text,
            mono,
            label: 'Free space loss',
            value: _fmt(r?.fspl, 1),
            unit: 'dB',
          ),
          const SizedBox(height: AppSpacing.xs),
          _resultRow(
            text,
            mono,
            label: 'Rain fade',
            value: _fmt(r?.rainFade, 2),
            unit: 'dB',
          ),
          const SizedBox(height: AppSpacing.xs),
          _resultRow(
            text,
            mono,
            label: 'Received signal',
            value: _fmt(r?.rxLevel, 1),
            unit: 'dBm',
          ),
        ],
      ),
    );
  }

  Widget _verdictBlock(TextTheme text, AppMonoText mono, PtpResult? r) {
    final AppColorScheme colors = context.colors;
    // No valid input yet → neutral placeholder, no status color.
    if (r == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Link margin',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Empty-state readout: one SR node, "not calculated" (Vera finding
          // #6).
          Semantics(
            label: 'Link margin',
            value: 'not calculated',
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SelectableText(
                  '—',
                  style: mono.outputXL.copyWith(color: colors.textTertiary),
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  'dB',
                  style: text.labelLarge?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Enter the required fields to check the link.',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      );
    }

    final PtpVerdict verdict = PtpLinkScreen.verdictFor(
      r.margin,
      _reqMarginUsed,
    );
    final Color statusColor;
    final String word;
    final String detail;
    switch (verdict) {
      case PtpVerdict.pass:
        statusColor = colors.statusSuccess;
        word = 'PASS';
        detail = '${_fmt(r.margin, 1)} dB margin';
        break;
      case PtpVerdict.marginal:
        statusColor = colors.statusWarning;
        word = 'MARGINAL';
        detail =
            '${_fmt(r.margin, 1)} dB, below the ${_fmt(_reqMarginUsed, 0)} dB required';
        break;
      case PtpVerdict.fail:
        statusColor = colors.statusDanger;
        word = 'FAIL';
        detail = '${_fmt(r.margin.abs(), 1)} dB short';
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Link margin',
          style: text.labelMedium?.copyWith(
            color: colors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // Big margin number in the status color, paired with the word verdict
        // (never color alone — GL-003 §8.13). One SR node folds the verdict
        // word into the value so it never rides on color alone (finding #6):
        // "Link margin: 8.0 dB, MARGINAL".
        Semantics(
          label: 'Link margin',
          value: '${_fmt(r.margin, 1)} dB, $word',
          excludeSemantics: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SelectableText(
                _fmt(r.margin, 1),
                style: mono.outputXL.copyWith(color: statusColor),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'dB',
                style: text.labelLarge?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Verdict chip: status color + the word, with detail beside it.
        Semantics(
          label: 'Verdict: $word, $detail',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(color: statusColor, width: 1),
                ),
                child: Text(
                  word,
                  style: text.labelLarge?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  detail,
                  style: text.labelMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _resultRow(
    TextTheme text,
    AppMonoText mono, {
    required String label,
    required String value,
    required String unit,
  }) {
    final AppColorScheme colors = context.colors;
    // One SR node per row: "EIRP: 36.0 dBm" (or "not calculated"), instead of
    // label/value/unit fragments (Vera finding #6).
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
              style: text.labelMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SelectableText(
            value,
            style: mono.inlineCode.copyWith(
              color: value == '—'
                  ? colors.textTertiary
                  : colors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            unit,
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ],
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
            'EIRP   = Tx + Gtx - Ltx',
            style: mono.robotoMono.copyWith(color: colors.textPrimary),
          ),
          SelectableText(
            // log10 base stays ASCII (₁₀ subscript absent from Roboto Mono).
            'FSPL   = 20·log10(d) + 20·log10(f) + 92.45',
            style: mono.robotoMono.copyWith(color: colors.textPrimary),
          ),
          SelectableText(
            'Rx     = EIRP - FSPL - rain + Grx - Lrx',
            style: mono.robotoMono.copyWith(color: colors.textPrimary),
          ),
          SelectableText(
            'Margin = Rx - sensitivity',
            style: mono.robotoMono.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'f in GHz, d in km. PASS when margin meets the required fade '
            'margin; MARGINAL when the link closes but falls short of it; '
            'FAIL when the margin goes negative. Rain fade uses ITU-R '
            'P.838-3 with the simplified P.530 path reduction and only '
            'applies above 0 mm/hr.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
