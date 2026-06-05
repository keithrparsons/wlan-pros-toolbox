// Cable Loss calculator.
//
// Coax attenuation for a run of a known length at a known frequency. Pick a
// cable type, enter frequency and length, read total loss in dB plus the
// per-100ft loss coefficient at that frequency.
//
// Formula and data match the RF Tools PWA reference (app.js calcCable +
// cableLossPer100ft + CABLE_DATA, lines 39-75 / 348-367):
//   per100ft(f) interpolated across manufacturer [freq_MHz, dB/100ft] points
//                on a sqrt(f) axis; clamped at the low end, sqrt-extrapolated
//                above the top knot.
//   totalLoss(dB) = per100ft × length_ft / 100
//
// Unit conventions mirror the PWA selects exactly:
//   Frequency — GHz (default) or MHz; GHz ×1000 to MHz (toMHz).
//   Length    — ft (default) or m; m ×3.28084 to ft before the / 100 math.
// Cable list and per-100ft point sets are a verbatim port of CABLE_DATA so the
// native app and PWA agree to the decimal. Output rounds to 2 decimals to match
// the PWA fmt(x, 2).
//
// Edge cases:
// - Empty / partial input on either field → blank the dB outputs (no crash).
// - Frequency or length <= 0 → PWA shows an error; here the outputs blank to
//   "—" rather than render a meaningless value.
//
// Pure, no network, no platform APIs. Math lives in static functions on the
// public widget class so it is unit-testable against the PWA values.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/field_unit_row.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
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
  // Verbatim port of PWA CABLE_DATA. Each entry is a list of
  // [freq_MHz, loss_dB_per_100ft] knots from manufacturer specs. Order is the
  // same as the PWA select so the default (LMR-400) and list match.

  /// Cable type keys in PWA select order. First entry is not the default; the
  /// PWA marks LMR-400 selected (see [defaultCable]).
  static const List<String> cableTypes = <String>[
    'LMR-100A',
    'LMR-200',
    'LMR-400',
    'LMR-600',
    'LMR-900',
    'LMR-1200',
    'RG-58',
    'RG-8/U',
    'RG-213',
    'RG-214',
  ];

  /// PWA-selected default cable type.
  static const String defaultCable = 'LMR-400';

  /// [freq_MHz, dB/100ft] knot sets, verbatim from PWA CABLE_DATA.
  static const Map<String, List<List<double>>> cableData =
      <String, List<List<double>>>{
        'LMR-100A': [
          [100, 3.3],
          [450, 7.0],
          [900, 10.3],
          [1500, 13.6],
          [2400, 17.5],
          [5800, 28.5],
        ],
        'LMR-200': [
          [100, 1.7],
          [450, 3.9],
          [900, 5.6],
          [1500, 7.3],
          [2400, 9.4],
          [5800, 15.3],
        ],
        'LMR-400': [
          [100, 0.7],
          [450, 1.5],
          [900, 2.2],
          [1500, 2.9],
          [2400, 3.9],
          [5800, 6.3],
        ],
        'LMR-600': [
          [100, 0.45],
          [450, 1.0],
          [900, 1.4],
          [1500, 1.9],
          [2400, 2.5],
          [5800, 4.1],
        ],
        'LMR-900': [
          [100, 0.29],
          [450, 0.65],
          [900, 0.93],
          [1500, 1.2],
          [2400, 1.6],
          [5800, 2.7],
        ],
        'LMR-1200': [
          [100, 0.22],
          [450, 0.49],
          [900, 0.70],
          [1500, 0.92],
          [2400, 1.2],
          [5800, 2.0],
        ],
        'RG-58': [
          [100, 4.5],
          [450, 7.5],
          [900, 11.0],
          [1500, 15.0],
          [2400, 20.0],
        ],
        'RG-8/U': [
          [100, 1.3],
          [450, 2.8],
          [900, 4.1],
          [1500, 5.5],
          [2400, 7.2],
        ],
        'RG-213': [
          [100, 1.3],
          [450, 2.8],
          [900, 4.1],
          [1500, 5.5],
          [2400, 7.2],
        ],
        'RG-214': [
          [100, 1.1],
          [450, 2.5],
          [900, 3.8],
          [1500, 5.0],
          [2400, 6.6],
        ],
      };

  // ─── Math (pure) ────────────────────────────────────────────────────────
  // Mirrors app.js: toMHz, cableLossPer100ft, calcCable.

  /// Normalize a frequency value to MHz (PWA toMHz).
  static double freqToMHz(double value, CableFreqUnit unit) {
    switch (unit) {
      case CableFreqUnit.ghz:
        return value * 1000.0;
      case CableFreqUnit.mhz:
        return value;
    }
  }

  /// Normalize a length value to feet (PWA: m ×3.28084, ft passthrough).
  static double lengthToFeet(double value, CableLengthUnit unit) {
    switch (unit) {
      case CableLengthUnit.m:
        return value * 3.28084;
      case CableLengthUnit.ft:
        return value;
    }
  }

  /// Loss per 100ft at [freqMHz] for [cableType], interpolated on a sqrt(f)
  /// axis across the manufacturer knots (PWA cableLossPer100ft). Returns null
  /// when the cable type is unknown. Clamps to the lowest knot below the first
  /// frequency; sqrt-extrapolates above the top knot.
  static double? cableLossPer100ft(String cableType, double freqMHz) {
    final List<List<double>>? pts = cableData[cableType];
    if (pts == null || pts.isEmpty) return null;

    if (freqMHz <= pts.first[0]) return pts.first[1];

    if (freqMHz >= pts.last[0]) {
      // Extrapolate using the last two knots on a sqrt(f) axis.
      final double f1 = pts[pts.length - 2][0];
      final double l1 = pts[pts.length - 2][1];
      final double f2 = pts.last[0];
      final double l2 = pts.last[1];
      final double slope = (l2 - l1) / (math.sqrt(f2) - math.sqrt(f1));
      return l2 + slope * (math.sqrt(freqMHz) - math.sqrt(f2));
    }

    for (int i = 0; i < pts.length - 1; i++) {
      final double f1 = pts[i][0];
      final double l1 = pts[i][1];
      final double f2 = pts[i + 1][0];
      final double l2 = pts[i + 1][1];
      if (freqMHz >= f1 && freqMHz <= f2) {
        final double t =
            (math.sqrt(freqMHz) - math.sqrt(f1)) /
            (math.sqrt(f2) - math.sqrt(f1));
        return l1 + t * (l2 - l1);
      }
    }
    return null;
  }

  /// Total cable loss in dB given per-100ft loss and run length in feet
  /// (PWA calcCable: lossPer100 × len_ft / 100).
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

  // Unsigned-decimal only. Frequency and length are always positive values a
  // human types by hand, so no sign and no scientific notation here.
  static final List<TextInputFormatter> _unsignedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

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
    final double? freq = _tryParseDouble(_freqCtrl.text);
    final double? length = _tryParseDouble(_lengthCtrl.text);
    if (freq == null || length == null) {
      setState(() {
        _totalLossDb = null;
        _lossPer100 = null;
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
      });
      return;
    }
    final double? per100 = CableLossScreen.cableLossPer100ft(_cable, fMHz);
    if (per100 == null) {
      setState(() {
        _totalLossDb = null;
        _lossPer100 = null;
      });
      return;
    }
    final double lenFt = CableLossScreen.lengthToFeet(length, _lengthUnit);
    setState(() {
      _lossPer100 = per100;
      _totalLossDb = CableLossScreen.totalLossDb(per100, lenFt);
    });
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  static double? _tryParseDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '.') return null;
    return double.tryParse(s);
  }

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
        ],
      ),
    );
  }

  Widget _cableSelectorField() {
    // Full-width Select (10 cable types, long labels) — §8.14 takes the row
    // width and ellipsizes inside the bounded control via `isExpanded`.
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
            'Loss(dB) = (dB/100ft × length_ft) / 100',
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'dB/100ft is interpolated from manufacturer spec points on a '
            'sqrt(frequency) axis. Lengths in meters convert at 3.28084 ft/m '
            'before the math.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    // Per-100ft loss at 2.4 GHz for a few common runs, read straight off the
    // CABLE_DATA 2400 MHz knot this screen uses. Anchors the user's intuition
    // for "thicker cable, less loss" without a second computation.
    final List<List<String>> refs = const [
      ['LMR-400', '2.4 GHz', '3.90 dB'],
      ['LMR-600', '2.4 GHz', '2.50 dB'],
      ['LMR-100A', '2.4 GHz', '17.50 dB'],
      ['RG-58', '2.4 GHz', '20.00 dB'],
      ['RG-213', '2.4 GHz', '7.20 dB'],
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
