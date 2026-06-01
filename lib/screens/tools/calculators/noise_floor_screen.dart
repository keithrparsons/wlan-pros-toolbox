// Noise Floor calculator.
//
// Enter channel bandwidth, receiver noise figure, and temperature; read the
// thermal noise floor (kTB), the receiver noise floor (kTB + NF), and the
// quick -174 dBm/Hz rule-of-thumb value. Formula matches the RF Tools PWA
// reference (app.js calcNoise, line 1188):
//   T(K)     = tempC + 273.15
//   bwHz     = bw_MHz × 1e6
//   thermal  = 10·log10(k · T · bwHz) + 30      (dBm, k = 1.380649e-23 J/K)
//   rxFloor  = thermal + nfDb
//   rule     = -174 + 10·log10(bwHz)            (kTB at ~0°C, dBm/Hz form)
//
// Input conventions mirror the PWA exactly:
//   Bandwidth — a select of 20 / 40 / 80 / 160 / 320 MHz (PWA noise-bw select).
//               4+ options → shared AppSelect.
//   Noise figure — dB, must be >= 0 (PWA noise-nf, default 7).
//   Temperature  — °C, defaults to 20 when blank (PWA noise-temp: the JS reads
//                  20 as the fallback when the field is non-numeric, even though
//                  the HTML input prefills 25). We mirror the JS fallback of 20.
// Output rounds to 1 decimal to match the PWA fmt(value, 1).
//
// Edge cases:
// - Noise figure empty / invalid / negative → blank all outputs (PWA showError).
// - Temperature blank → treated as 20°C (PWA fallback), outputs still compute.
// - Bandwidth always has a valid selection, so it never blanks on its own.
//
// Pure, no network, no platform APIs. Math lives in static functions on the
// public widget class so it is unit-testable against the PWA values.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// Channel bandwidth options in MHz, mirroring the PWA noise-bw select.
enum NoiseBandwidth {
  bw20(20, '20 MHz'),
  bw40(40, '40 MHz'),
  bw80(80, '80 MHz'),
  bw160(160, '160 MHz'),
  bw320(320, '320 MHz (Wi-Fi 7)');

  const NoiseBandwidth(this.mhz, this.label);

  /// Bandwidth in MHz.
  final int mhz;

  /// Display label for the selector.
  final String label;
}

class NoiseFloorScreen extends StatefulWidget {
  const NoiseFloorScreen({super.key});

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Mirrors app.js calcNoise.

  /// Boltzmann constant in J/K (PWA: 1.380649e-23).
  static const double kBoltzmann = 1.380649e-23;

  /// Default temperature in °C when the field is left blank (PWA fallback: 20).
  static const double defaultTempC = 20.0;

  /// Thermal noise floor in dBm: 10·log10(k · T · bwHz) + 30.
  /// [bwMhz] in MHz, [tempC] in °C.
  static double thermalDbm(double bwMhz, double tempC) {
    final double tKelvin = tempC + 273.15;
    final double bwHz = bwMhz * 1e6;
    return 10 * _log10(kBoltzmann * tKelvin * bwHz) + 30;
  }

  /// Receiver noise floor in dBm: thermal + noise figure.
  static double rxFloorDbm(double bwMhz, double tempC, double nfDb) {
    return thermalDbm(bwMhz, tempC) + nfDb;
  }

  /// Rule-of-thumb noise floor in dBm: -174 + 10·log10(bwHz).
  /// The -174 dBm/Hz constant is kTB at ~0°C (PWA calcNoise).
  static double ruleOfThumbDbm(double bwMhz) {
    final double bwHz = bwMhz * 1e6;
    return -174 + 10 * _log10(bwHz);
  }

  static double _log10(double x) => math.log(x) / math.ln10;

  @override
  State<NoiseFloorScreen> createState() => _NoiseFloorScreenState();
}

class _NoiseFloorScreenState extends State<NoiseFloorScreen> {
  final TextEditingController _nfCtrl = TextEditingController(text: '7');
  final TextEditingController _tempCtrl = TextEditingController(text: '20');

  final FocusNode _nfFocus = FocusNode();
  final FocusNode _tempFocus = FocusNode();

  NoiseBandwidth _bw = NoiseBandwidth.bw20;

  // Computed outputs in dBm, or null when input is invalid.
  double? _thermalDbm;
  double? _rxFloorDbm;
  double? _ruleDbm;

  // Field-level validation message for the noise figure. Set when the field is
  // non-empty but invalid or negative (was a silent blank — Vera finding #7).
  // Stays null for an empty field, which legitimately blanks the outputs.
  String? _nfError;

  // Noise figure: unsigned decimal (PWA min=0). Temperature: signed decimal so
  // negative °C is allowed (PWA min=-40).
  static final List<TextInputFormatter> _unsignedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];
  static final List<TextInputFormatter> _signedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
  ];

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void dispose() {
    _nfCtrl.dispose();
    _tempCtrl.dispose();
    _nfFocus.dispose();
    _tempFocus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    final String nfRaw = _nfCtrl.text.trim();
    final double? nf = _tryParseDouble(_nfCtrl.text);
    // PWA: nf must be finite and >= 0, else showError (blank outputs). An empty
    // field stays silent (a legitimate not-yet-entered state); a non-empty but
    // invalid or negative value gets a visible field-level message instead of a
    // silent blank (Vera finding #7).
    if (nf == null || nf < 0) {
      setState(() {
        _thermalDbm = null;
        _rxFloorDbm = null;
        _ruleDbm = null;
        _nfError = nfRaw.isEmpty
            ? null
            : 'Noise figure must be 0 dB or higher.';
      });
      return;
    }
    // PWA: temperature falls back to 20°C when the field is non-numeric.
    final double? tempParsed = _tryParseDouble(_tempCtrl.text);
    final double tempC = tempParsed ?? NoiseFloorScreen.defaultTempC;

    final double bwMhz = _bw.mhz.toDouble();
    setState(() {
      _nfError = null;
      _thermalDbm = NoiseFloorScreen.thermalDbm(bwMhz, tempC);
      _rxFloorDbm = NoiseFloorScreen.rxFloorDbm(bwMhz, tempC, nf);
      _ruleDbm = NoiseFloorScreen.ruleOfThumbDbm(bwMhz);
    });
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  static double? _tryParseDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '.' || s == '-') return null;
    return double.tryParse(s);
  }

  /// PWA fmt(value, 1): fixed 1-decimal, "—" when not finite.
  static String _formatDbm(double? value) {
    if (value == null || !value.isFinite) return '—';
    return value.toStringAsFixed(1);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(title: const Text('Noise Floor'), toolbarHeight: 64),
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
                        toolId: 'noise-floor',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('noise-floor'))
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
          // Bandwidth: 5 options → AppSelect (full-width inside LabeledField).
          LabeledField(
            label: 'Channel bandwidth',
            hint: '(MHz)',
            semanticLabel: 'Channel bandwidth in MHz',
            field: AppSelect<NoiseBandwidth>(
              value: _bw,
              semanticLabel: 'Channel bandwidth',
              items: NoiseBandwidth.values
                  .map((b) => (b, b.label))
                  .toList(growable: false),
              onChanged: (b) {
                setState(() => _bw = b);
                _recompute();
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Receiver noise figure',
            hint: '(dB)',
            semanticLabel: 'Receiver noise figure in dB',
            field: TextField(
              controller: _nfCtrl,
              focusNode: _nfFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: _unsignedDecimal,
              onChanged: (_) => _recompute(),
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              style: mono.outputLarge.copyWith(
                fontSize: AppTextSize.fieldNumeric,
              ),
              cursorColor: AppColors.primary,
              decoration: InputDecoration(hintText: '7', errorText: _nfError),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Temperature',
            hint: '(°C)',
            semanticLabel: 'Temperature in degrees Celsius',
            field: TextField(
              controller: _tempCtrl,
              focusNode: _tempFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              inputFormatters: _signedDecimal,
              onChanged: (_) => _recompute(),
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              style: mono.outputLarge.copyWith(
                fontSize: AppTextSize.fieldNumeric,
              ),
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(hintText: '20'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _resultRow(
            text,
            mono,
            label: 'Thermal noise (kTB)',
            value: _thermalDbm,
            primary: false,
          ),
          const SizedBox(height: AppSpacing.sm),
          _resultRow(
            text,
            mono,
            label: 'Rx noise floor',
            value: _rxFloorDbm,
            primary: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          _resultRow(
            text,
            mono,
            label: 'Rule of thumb',
            value: _ruleDbm,
            primary: false,
          ),
        ],
      ),
    );
  }

  Widget _resultRow(
    TextTheme text,
    AppMonoText mono, {
    required String label,
    required double? value,
    required bool primary,
  }) {
    final bool blank = value == null || !value.isFinite;
    // One SR node: "Rx noise floor: -94.0 dBm" (or "not calculated"), instead
    // of value/unit/label as separate fragments (Vera finding #6).
    return Semantics(
      label: label,
      value: blank ? 'not calculated' : '${_formatDbm(value)} dBm',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
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
                _formatDbm(value),
                style: (primary ? mono.outputXL : mono.outputLarge).copyWith(
                  color: blank
                      ? AppColors.textTertiary
                      : (primary ? AppColors.primary : AppColors.textPrimary),
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'dBm',
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
            'N(dBm) = 10·log₁₀(k·T·B) + 30 + NF',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'k = 1.380649×10⁻²³ J/K, T = °C + 273.15 K, B in Hz. NF is the '
            'receiver noise figure. The rule of thumb uses -174 dBm/Hz + '
            '10·log₁₀(B).',
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
    // Thermal noise floor (kTB, no noise figure) at 20°C for each bandwidth,
    // computed from the same formula this screen uses.
    final List<List<String>> refs = const [
      ['20 MHz', '-100.9 dBm'],
      ['40 MHz', '-97.9 dBm'],
      ['80 MHz', '-94.9 dBm'],
      ['160 MHz', '-91.9 dBm'],
      ['320 MHz', '-88.9 dBm'],
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
            'Thermal floor at 20°C',
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
                  // Column width snaps to the 8px base unit (GL-003 §4).
                  SizedBox(
                    width: 96,
                    child: Text(
                      row[0],
                      style: mono.inlineCode.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row[1],
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
