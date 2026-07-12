// Cable Loss calculator.
//
// Coax attenuation for a run of a known length at a known frequency. Pick a
// cable type, enter frequency and length, read total loss in dB plus the
// per-100ft loss coefficient at that frequency.
//
// ─── WHY THIS IS AN EQUATION AND NOT A LOOKUP TABLE ────────────────────────
//
// This screen previously carried a table of [freq_MHz, dB/100ft] knots and
// interpolated between them. That table was COLUMN-SHIFTED: it served Times
// Microwave's 900 MHz value (3.9 dB/100 ft for LMR-400) at 2400 MHz. Real
// LMR-400 at 2.4 GHz is ~6.6 dB/100 ft, so the app under-reported cable loss by
// 41% — and it erred in the dangerous direction, making every link budget look
// better than it was.
//
// The bug survived review because a column-shifted copy of a correct table is
// STILL monotonic in frequency and STILL correctly ordered by cable thickness.
// Internal consistency was preserved by the very nature of the defect. No
// self-check could catch it; only a comparison against the manufacturer at a
// named frequency could.
//
// So we no longer read rows. Times Microwave publishes an attenuation EQUATION
// on every LMR datasheet, and we implement it directly:
//
//     dB/100 ft = k1 · √(F_MHz) + k2 · F_MHz        (VSWR 1.0, +25 °C ambient)
//
// It reproduces Times' own tabulated values at every frequency they publish
// (within the datasheets' 0.1 dB rounding), it is exact at frequencies they
// never tabulated — 2400 MHz among them — and it deletes the entire
// read-the-wrong-row failure class. There is no table left to misread.
//
// ─── WHY THE RG TYPES ARE GONE (Keith's call) ──────────────────────────────
//
// "RG" is not one cable. It is a family of loose mil-spec designations that
// different manufacturers implement differently:
//
//   Belden 8259 and Belden 9201 are BOTH stamped "RG-58" and differ by 54% at
//   900 MHz (21.1 vs 13.7 dB/100 ft) — one manufacturer, one designation, two
//   materially different cables.
//
// Worse: no manufacturer publishes RG attenuation at Wi-Fi frequencies at all.
// Belden's RG tables stop at 1000 MHz. Any 2.4 GHz number this app ever showed
// for an RG type was invented — a curve-fit through a gap the manufacturer
// declined to fill. Two defensible fits to Belden's own published points
// disagree by 14% at 2.4 GHz, so there is no honest number to pick.
//
// We therefore offer only LMR cables, where the physics is clean and the
// manufacturer publishes an equation, and we tell the user plainly to read their
// actual cable's datasheet. See [rgOmissionNote].
//
// ─── WHY LMR-1200 IS GONE TOO (Keith's call, 2026-07-11) ───────────────────
//
// The shipped set is FIVE cables: LMR-100A, LMR-200, LMR-400, LMR-600, LMR-900.
// Times tabulates all five out to 5800 MHz, so the equation is only ever
// evaluated inside its validated range. LMR-1200 is the exception: Times stops
// tabulating it at 2500 MHz, and the two-term model under-predicts a cable that
// large as it approaches mode cutoff. The equation gives 3.774 dB/100 ft at
// 5800 MHz; the real figure is ~4.7-5.5. Shipping 3.774 would have introduced a
// brand-new wrong number on the very day we fixed the old ones — and in the same
// flattering direction as the original bug. And nobody runs LMR-1200 at 6 GHz
// anyway (FCC rules make outdoor 6 GHz standard-power a non-starter without AFC;
// low-power is indoor-only), so the only frequency where the disputed value
// mattered is a deployment that does not exist. See [lmr1200OmissionNote].
//
// THE GENERAL RULE THIS ESTABLISHES: a model is trustworthy only inside the range
// its source validated it in. Above 5800 MHz the calculator does not silently
// extrapolate — it labels the result (see [aboveValidatedRangeNote]), the same
// discipline as returning null for Noise on Windows rather than inventing a
// figure. An honest "outside validated range" beats a confident wrong number.
//
// Reference: Deliverables/2026-07-11-calculator-verification/CABLE-AND-RAIN-DATA.md
//
// ─── Conventions ───────────────────────────────────────────────────────────
//   Frequency — GHz (default) or MHz; GHz ×1000 to MHz.
//   Length    — ft (default) or m; m ×3.28084 to ft before the / 100 math.
//   totalLoss(dB) = per100ft × length_ft / 100. Output rounds to 2 decimals.
//
// Edge cases:
// - Empty / partial input on either field → blank the dB outputs (no crash).
// - Frequency or length <= 0 → outputs blank to "—" rather than render a
//   meaningless value.
//
// Pure, no network, no platform APIs. Math lives in static functions on the
// public widget class so it is unit-testable against the manufacturer's data.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../utils/decimal_input.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/field_unit_row.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// Frequency input units, mirroring the PWA cable-freq-unit select.
enum CableFreqUnit { ghz, mhz }

/// Length input units, mirroring the PWA cable-length-unit select.
enum CableLengthUnit { ft, m }

class CableLossScreen extends StatefulWidget {
  const CableLossScreen({super.key});

  // ─── Cable data (pure) ──────────────────────────────────────────────────

  /// Selectable cable types, thinnest → thickest.
  ///
  /// FIVE LMR cables. No RG types (see [rgOmissionNote]) and no LMR-1200 (see
  /// [lmr1200OmissionNote]). Every cable here is tabulated by Times Microwave
  /// out to 5800 MHz, so the equation below is only ever evaluated inside the
  /// range the manufacturer validated it in.
  static const List<String> cableTypes = <String>[
    'LMR-100A',
    'LMR-200',
    'LMR-400',
    'LMR-600',
    'LMR-900',
  ];

  /// Default cable type.
  static const String defaultCable = 'LMR-400';

  /// The frequency, in MHz, to which Times Microwave tabulates every cable this
  /// tool offers. The attenuation equation is validated against their own
  /// published values up to here — above it we are extrapolating, and we say so
  /// rather than quietly returning a number. See [aboveValidatedRangeNote].
  static const double validatedMaxFreqMHz = 5800.0;

  /// Times Microwave attenuation coefficients, read from the datasheets.
  ///
  ///     dB/100 ft = k1 · √(F_MHz) + k2 · F_MHz
  ///
  /// Datasheet conditions: VSWR = 1.0, ambient +25 °C. Attenuation rises with
  /// temperature, so an outdoor run on a hot roof loses more than this — a
  /// real second-order effect this calculator does not model.
  ///
  /// Sources: Times Microwave LMR-100A p.9, LMR-200, LMR-400 p.23, LMR-600
  /// p.29, LMR-900 p.33. Each is tabulated by Times out to 5800 MHz.
  static const Map<String, (double k1, double k2)> cableCoefficients =
      <String, (double, double)>{
    'LMR-100A': (0.709140, 0.001740),
    'LMR-200': (0.320900, 0.000330),
    'LMR-400': (0.122290, 0.000260),
    'LMR-600': (0.075550, 0.000260),
    'LMR-900': (0.051770, 0.000160),
  };

  /// The honest note shown on-screen explaining why no RG type is offered.
  static const String rgOmissionNote =
      '"RG" is not one cable. Belden 8259 and Belden 9201 are both stamped '
      'RG-58 and differ by 54% at 900 MHz, and no manufacturer publishes RG '
      'attenuation at Wi-Fi frequencies at all: Belden\'s tables stop at '
      '1000 MHz. Rather than invent a number, this tool omits RG types. For an '
      'RG run, read the dB/100 ft figure off your actual cable\'s datasheet by '
      'part number.';

  /// Why LMR-1200 is not offered (Keith's call, 2026-07-11).
  ///
  /// THE TRAP THIS AVOIDS, in full, because it nearly cost us a fresh wrong
  /// number on the same day we fixed the old ones:
  ///
  /// Times tabulates every other LMR out to 5800 MHz. They stop LMR-1200 at
  /// 2500 MHz. That is not an oversight — the two-term model (k1·√f + k2·f)
  /// extrapolates badly for a cable that large, because loss climbs faster than
  /// the model predicts as the cross-section approaches mode cutoff. Evaluating
  /// the equation at 5800 MHz yields 3.774 dB/100 ft; Keith puts the real figure
  /// at ~4.7-5.5. That is a 25-45% error, and it is in the dangerous direction
  /// (it flatters the link budget) — the exact failure mode of the original
  /// column-shifted table.
  ///
  /// And the use case does not exist: nobody runs LMR-1200 at 6 GHz. FCC rules
  /// make outdoor 6 GHz standard-power a non-starter without AFC, and low-power
  /// is indoor-only. The only frequency where the disputed value mattered is a
  /// deployment nobody does. So the cable is removed rather than shipped with a
  /// number we cannot stand behind.
  static const String lmr1200OmissionNote =
      'LMR-1200 is not offered. Times Microwave tabulates it only to 2500 MHz '
      '(every other LMR runs to 5800 MHz), and the published equation '
      'under-predicts its loss when extrapolated to Wi-Fi frequencies. Rather '
      'than show a number we cannot stand behind, it is omitted - and in '
      'practice nobody runs LMR-1200 at 6 GHz anyway.';

  /// Shown when the user asks for a frequency past the validated range.
  ///
  /// Same discipline as returning null for Noise on Windows rather than
  /// inventing a figure: the equation is trustworthy where Times tabulates it,
  /// and past that we say so instead of silently extrapolating.
  static const String aboveValidatedRangeNote =
      'Above 5800 MHz this is an extrapolation, not a manufacturer-validated '
      'figure. Times Microwave tabulates these cables to 5800 MHz; past that '
      'the equation tends to under-predict loss. Treat the result as a lower '
      'bound and confirm against your cable\'s datasheet.';

  // ─── Math (pure) ────────────────────────────────────────────────────────

  /// Normalize a frequency value to MHz.
  static double freqToMHz(double value, CableFreqUnit unit) {
    switch (unit) {
      case CableFreqUnit.ghz:
        return value * 1000.0;
      case CableFreqUnit.mhz:
        return value;
    }
  }

  /// Normalize a length value to feet (m ×3.28084, ft passthrough).
  static double lengthToFeet(double value, CableLengthUnit unit) {
    switch (unit) {
      case CableLengthUnit.m:
        return value * 3.28084;
      case CableLengthUnit.ft:
        return value;
    }
  }

  /// Loss per 100 ft at [freqMHz] for [cableType], from Times Microwave's own
  /// published attenuation equation:
  ///
  ///     dB/100 ft = k1 · √(F_MHz) + k2 · F_MHz
  ///
  /// Evaluated, never interpolated — there is no table to read off by a row.
  /// Returns null when the cable type is unknown (including any RG designation,
  /// which this tool deliberately does not model; see [rgOmissionNote]).
  static double? cableLossPer100ft(String cableType, double freqMHz) {
    final (double, double)? coeff = cableCoefficients[cableType];
    if (coeff == null) return null;
    final (double k1, double k2) = coeff;
    return k1 * math.sqrt(freqMHz) + k2 * freqMHz;
  }

  /// True when [freqMHz] is past the range Times Microwave tabulates, so the
  /// equation is being extrapolated rather than evaluated inside its validated
  /// band. The result is still shown — but it is labelled, never presented as a
  /// manufacturer-backed figure.
  static bool isAboveValidatedRange(double freqMHz) =>
      freqMHz > validatedMaxFreqMHz;

  /// Total cable loss in dB given per-100ft loss and run length in feet:
  /// lossPer100 × len_ft / 100.
  static double totalLossDb(double lossPer100, double lengthFt) {
    return (lossPer100 * lengthFt) / 100.0;
  }

  @override
  State<CableLossScreen> createState() => _CableLossScreenState();
}

class _CableLossScreenState extends State<CableLossScreen> {
  final TextEditingController _freqCtrl = TextEditingController();
  final TextEditingController _lengthCtrl = TextEditingController();

  final FocusNode _freqFocus = FocusNode();
  final FocusNode _lengthFocus = FocusNode();

  String _cable = CableLossScreen.defaultCable;
  CableFreqUnit _freqUnit = CableFreqUnit.ghz;
  CableLengthUnit _lengthUnit = CableLengthUnit.ft;

  // Computed total loss / per-100ft, or null when input is empty / invalid /
  // non-positive.
  double? _totalLossDb;
  double? _lossPer100;

  // True when the requested frequency sits above the range Times Microwave
  // tabulates (5800 MHz). The result still renders — but it renders LABELLED as
  // an extrapolation, because a confident number outside a model's validated
  // range is exactly the class of defect this whole audit wave exists to fix.
  bool _aboveValidatedRange = false;

  // Unsigned-decimal only. Frequency and length are always positive values a
  // human types by hand, so no sign and no scientific notation here.
  static final List<TextInputFormatter> _unsignedDecimal = unsignedDecimalFormatters;

  @override
  void dispose() {
    _freqCtrl.dispose();
    _lengthCtrl.dispose();
    _freqFocus.dispose();
    _lengthFocus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    final double? freq = tryParseFlexibleDouble(_freqCtrl.text);
    final double? length = tryParseFlexibleDouble(_lengthCtrl.text);
    if (freq == null || length == null) {
      setState(() {
        _totalLossDb = null;
        _lossPer100 = null;
        _aboveValidatedRange = false;
      });
      return;
    }
    final double fMHz = CableLossScreen.freqToMHz(freq, _freqUnit);
    // PWA guards freq <= 0 || length <= 0 before computing; do the same so we
    // never render a meaningless or extrapolated-from-zero result.
    if (fMHz <= 0 || length <= 0) {
      setState(() {
        _totalLossDb = null;
        _lossPer100 = null;
        _aboveValidatedRange = false;
      });
      return;
    }
    final double? per100 = CableLossScreen.cableLossPer100ft(_cable, fMHz);
    if (per100 == null) {
      setState(() {
        _totalLossDb = null;
        _lossPer100 = null;
        _aboveValidatedRange = false;
      });
      return;
    }
    final double lenFt = CableLossScreen.lengthToFeet(length, _lengthUnit);
    setState(() {
      _lossPer100 = per100;
      _totalLossDb = CableLossScreen.totalLossDb(per100, lenFt);
      _aboveValidatedRange = CableLossScreen.isAboveValidatedRange(fMHz);
    });
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  /// PWA fmt(x, 2): fixed 2-decimal, "—" when not finite.
  static String _format2(double? value) {
    if (value == null || !value.isFinite) return '—';
    return value.toStringAsFixed(2);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cable Loss'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until a valid
        // total loss is computed; copies the run as a labeled text block.
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
                        toolId: 'cable-loss',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('cable-loss'))
                        const SizedBox(height: AppSpacing.md),
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _formulaCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _referenceCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _rgNoteCard(text),
                      ToolHelpFooter(toolId: 'cable-loss'),
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

  /// §8.16 copy payload — the cable run as a labeled text block.
  ///
  /// Returns null (→ disabled affordance) whenever there is no valid total
  /// loss: empty / partial / non-positive frequency or length. Field order and
  /// values match the on-screen inputs and [_resultRow].
  String? _buildCopyText() {
    final double? total = _totalLossDb;
    if (total == null) return null;

    final String freqUnit = _freqUnit == CableFreqUnit.ghz ? 'GHz' : 'MHz';
    final String lenUnit = _lengthUnit == CableLengthUnit.ft ? 'ft' : 'm';

    return (StringBuffer()
          ..writeln('Cable Loss')
          ..writeln('Cable type: $_cable')
          ..writeln('Frequency: ${_freqCtrl.text.trim()} $freqUnit')
          ..writeln('Cable length: ${_lengthCtrl.text.trim()} $lenUnit')
          ..writeln('Total loss: ${_format2(total)} dB')
          ..writeln('Loss per 100 ft: ${_format2(_lossPer100)} dB'))
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
          _cableSelectorField(),
          const SizedBox(height: AppSpacing.sm),
          _inputRow(
            label: 'Frequency',
            unitHint: _freqUnit == CableFreqUnit.ghz ? 'GHz' : 'MHz',
            semanticLabel: 'Frequency',
            controller: _freqCtrl,
            focusNode: _freqFocus,
            hintText: '2.4',
            monoStyle: mono.outputLarge,
            unitSelector: _freqUnitSelector(),
          ),
          const SizedBox(height: AppSpacing.sm),
          _inputRow(
            label: 'Cable length',
            unitHint: _lengthUnit == CableLengthUnit.ft ? 'ft' : 'm',
            semanticLabel: 'Cable length',
            controller: _lengthCtrl,
            focusNode: _lengthFocus,
            hintText: '25',
            monoStyle: mono.outputLarge,
            unitSelector: _lengthUnitSelector(),
          ),
          const SizedBox(height: AppSpacing.md),
          _resultRow(text, mono),
          // Honest-extrapolation banner. The equation is validated only where
          // Times tabulates (to 5800 MHz). Past that we do NOT silently
          // extrapolate a confident-looking figure — we label it, the same way
          // the app returns null for Noise on Windows rather than inventing one.
          if (_aboveValidatedRange) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _ExtrapolationNotice(
              text: text,
              message: CableLossScreen.aboveValidatedRangeNote,
            ),
          ],
        ],
      ),
    );
  }

  Widget _cableSelectorField() {
    // Full-width Select (six LMR cable types, long labels) — §8.14 takes the
    // row width and ellipsizes inside the bounded control via `isExpanded`.
    return LabeledField(
      label: 'Cable type',
      field: AppSelect<String>(
        value: _cable,
        semanticLabel: 'Cable type',
        items: CableLossScreen.cableTypes
            .map((String type) => (type, type))
            .toList(),
        onChanged: (String value) {
          setState(() => _cable = value);
          _recompute();
        },
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
    final AppColorScheme colors = context.colors;
    // FieldUnitRow reflows the unit selector beneath the field below 440px so
    // it never clips at phone widths (Vera web-demo gate, 2026-06-02).
    return FieldUnitRow(
      field: LabeledField(
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
          cursorColor: colors.textAccent,
          decoration: InputDecoration(hintText: hintText),
        ),
      ),
      unit: unitSelector,
    );
  }

  Widget _resultRow(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    // One SR node for the readout: "Total cable loss: 3.42 dB, 1.71 dB per 100
    // feet" (or "not calculated"), instead of value/unit/label fragments
    // across two lines (Vera finding #6).
    final bool blank = _totalLossDb == null;
    final String per100 = _lossPer100 == null
        ? ''
        : ', ${_format2(_lossPer100)} dB per 100 feet';
    return Semantics(
      label: 'Total cable loss',
      value: blank ? 'not calculated' : '${_format2(_totalLossDb)} dB$per100',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total cable loss',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SelectableText(
                _format2(_totalLossDb),
                style: mono.outputXL.copyWith(
                  color: _totalLossDb == null
                      ? colors.textTertiary
                      : colors.textAccent,
                ),
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
          const SizedBox(height: AppSpacing.sm),
          // Per-100ft coefficient — the PWA's second output line. Secondary so it
          // reads as supporting detail beneath the headline total.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Loss per 100 ft',
                style: text.labelMedium?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              SelectableText(
                _format2(_lossPer100),
                style: mono.inlineCode.copyWith(
                  color: _lossPer100 == null
                      ? colors.textTertiary
                      : colors.textSecondary,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'dB',
                style: text.labelMedium?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _freqUnitSelector() {
    return AppToggle<CableFreqUnit>(
      value: _freqUnit,
      items: const [(CableFreqUnit.ghz, 'GHz'), (CableFreqUnit.mhz, 'MHz')],
      onChanged: (u) {
        setState(() => _freqUnit = u);
        _recompute();
      },
    );
  }

  Widget _lengthUnitSelector() {
    return AppToggle<CableLengthUnit>(
      value: _lengthUnit,
      items: const [(CableLengthUnit.ft, 'ft'), (CableLengthUnit.m, 'm')],
      onChanged: (u) {
        setState(() => _lengthUnit = u);
        _recompute();
      },
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
            'Loss(dB) = (dB/100ft × length_ft) / 100\n'
            'dB/100ft  = k1 × √f_MHz + k2 × f_MHz',
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'dB/100ft comes from Times Microwave\'s published attenuation '
            'equation, evaluated at your exact frequency (k1 and k2 are '
            'per-cable datasheet constants; VSWR 1.0 at +25 °C). Nothing is '
            'interpolated between table rows. Lengths in meters convert at '
            '3.28084 ft/m before the math.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  /// The honest "why is there no RG-58 here" card. A user who came looking for
  /// RG must leave knowing why it is absent and what to do instead — not
  /// wondering whether the tool forgot.
  Widget _rgNoteCard(TextTheme text) {
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: colors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Why there is no RG-58, RG-8, RG-213, RG-214 or LMR-1200 here',
                  style: text.labelMedium?.copyWith(
                    color: colors.textSecondary,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            CableLossScreen.rgOmissionNote,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            CableLossScreen.lmr1200OmissionNote,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    // Per-100ft loss at 2.4 GHz for every cable offered, COMPUTED from the same
    // equation the calculator uses. Previously this card carried hardcoded
    // strings, which is how it came to display 3.90 dB for LMR-400 — a number
    // that disagreed with reality and could drift from the calculator silently.
    // Deriving it means the card cannot lie independently of the math.
    final List<List<String>> refs = CableLossScreen.cableTypes.map((String c) {
      final double per100 = CableLossScreen.cableLossPer100ft(c, 2400)!;
      return <String>[c, '2.4 GHz', '${_format2(per100)} dB'];
    }).toList();

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
            'Loss per 100 ft at 2.4 GHz',
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
                  // Column widths snap to the 8px base unit (GL-003 §4).
                  SizedBox(
                    width: 96,
                    child: Text(
                      row[0],
                      style: mono.inlineCode.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 80,
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
                      style: mono.inlineCode.copyWith(
                        color: colors.textAccent,
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

/// The out-of-validated-range notice, shown under the result when the requested
/// frequency exceeds 5800 MHz.
///
/// This is a warning about the MODEL, not about the user's input — the number
/// above it is still the best available estimate, it simply is not
/// manufacturer-validated at that frequency. Rendered as a warning-tinted card
/// with the verdict word in text (§8.13: color is never the only signal), and
/// announced to assistive tech as one node.
class _ExtrapolationNotice extends StatelessWidget {
  const _ExtrapolationNotice({required this.text, required this.message});

  final TextTheme text;
  final String message;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Semantics(
      container: true,
      label: 'Outside validated range. $message',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.statusWarning, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.warning_amber_outlined,
              size: 18,
              color: colors.statusWarning,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Outside validated range',
                    style: text.labelMedium?.copyWith(
                      color: colors.statusWarning,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    message,
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
