// Metric (length) Conversion.
//
// Convert a length value from one unit to another across the seven units the
// RF Tools PWA supports (app.js calcMetric, line 544): m, km, mi, ft, cm, in,
// nmi. The PWA pivots every value through meters with this factor table:
//   toM = { m:1, km:1000, mi:1609.344, ft:0.3048, cm:0.01, in:0.0254, nm:1852 }
// then renders each target unit as meters / toM[target]. We mirror those exact
// factors so the native app and PWA agree to the decimal. (The PWA keyed
// nautical miles as "nm"; we name the enum `nmi` to avoid colliding with the
// nanometer symbol, same 1852 m factor.)
//
// UI shape: a single from-unit and to-unit selection with one live result,
// rather than the PWA's "show all seven at once" panel — the Toolbox tool
// screens are single-output by convention (see fspl_screen.dart). The full
// seven-unit factor set still lives in the public static math so it is faithful
// to the PWA and unit-testable.
//
// Per-unit output precision mirrors the PWA fmt() decimals: m=4, km=6, mi=6,
// ft=4, cm=2, in=4, nmi=6.
//
// Edge cases:
// - Empty / partial input → blank result (no crash), matching the PWA isFinite
//   guard which bails before writing any output.
// - Negative or zero is valid arithmetic here (a length delta can be negative);
//   the PWA only guards isFinite, so we do the same and let the math through.
//
// Pure, no network, no platform APIs. Math lives in static functions on the
// public widget class so tests call MetricConversionScreen.<fn> directly.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// Length units, mirroring the PWA mc-unit select options exactly.
enum LengthUnit { m, km, mi, ft, cm, inch, nmi }

class MetricConversionScreen extends StatefulWidget {
  const MetricConversionScreen({super.key});

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Mirrors app.js calcMetric: pivot through meters with the PWA toM factors.

  /// Meters per one unit — the PWA `toM` table, exactly.
  static double metersPerUnit(LengthUnit unit) {
    switch (unit) {
      case LengthUnit.m:
        return 1.0;
      case LengthUnit.km:
        return 1000.0;
      case LengthUnit.mi:
        return 1609.344;
      case LengthUnit.ft:
        return 0.3048;
      case LengthUnit.cm:
        return 0.01;
      case LengthUnit.inch:
        return 0.0254;
      case LengthUnit.nmi:
        return 1852.0;
    }
  }

  /// Normalize a value in [unit] to meters (PWA: val * toM[unit]).
  static double toMeters(double value, LengthUnit unit) =>
      value * metersPerUnit(unit);

  /// Convert meters to [unit] (PWA: m / toM[unit]).
  static double fromMeters(double meters, LengthUnit unit) =>
      meters / metersPerUnit(unit);

  /// Convert [value] from [from] to [to], pivoting through meters like the PWA.
  static double convert(double value, LengthUnit from, LengthUnit to) =>
      fromMeters(toMeters(value, from), to);

  /// Per-unit display precision, matching the PWA fmt() decimal counts in
  /// calcMetric (m=4, km=6, mi=6, ft=4, cm=2, in=4, nmi=6).
  static int decimalsFor(LengthUnit unit) {
    switch (unit) {
      case LengthUnit.m:
        return 4;
      case LengthUnit.km:
        return 6;
      case LengthUnit.mi:
        return 6;
      case LengthUnit.ft:
        return 4;
      case LengthUnit.cm:
        return 2;
      case LengthUnit.inch:
        return 4;
      case LengthUnit.nmi:
        return 6;
    }
  }

  /// Short symbol shown in selectors / hints.
  static String symbolFor(LengthUnit unit) {
    switch (unit) {
      case LengthUnit.m:
        return 'm';
      case LengthUnit.km:
        return 'km';
      case LengthUnit.mi:
        return 'mi';
      case LengthUnit.ft:
        return 'ft';
      case LengthUnit.cm:
        return 'cm';
      case LengthUnit.inch:
        return 'in';
      case LengthUnit.nmi:
        return 'nmi';
    }
  }

  @override
  State<MetricConversionScreen> createState() => _MetricConversionScreenState();
}

class _MetricConversionScreenState extends State<MetricConversionScreen> {
  final TextEditingController _valueCtrl = TextEditingController();
  final FocusNode _valueFocus = FocusNode();

  LengthUnit _fromUnit = LengthUnit.m;
  LengthUnit _toUnit = LengthUnit.ft;

  /// Value→symbol pairs for the from/to unit `AppSelect`s, in enum order.
  static final List<AppSelectItem<LengthUnit>> _unitItems = LengthUnit.values
      .map((LengthUnit u) => (u, MetricConversionScreen.symbolFor(u)))
      .toList();

  // Computed result in `_toUnit`, or null when input is empty / invalid.
  double? _result;

  // Signed-decimal: a length delta can be negative, and the PWA only guards
  // isFinite, so allow a leading minus. No scientific notation — these are
  // hand-typed lengths.
  static final List<TextInputFormatter> _signedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
  ];

  @override
  void dispose() {
    _valueCtrl.dispose();
    _valueFocus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    final double? value = _tryParseDouble(_valueCtrl.text);
    if (value == null) {
      setState(() => _result = null);
      return;
    }
    setState(() {
      _result = MetricConversionScreen.convert(value, _fromUnit, _toUnit);
    });
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  static double? _tryParseDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '-' || s == '.' || s == '-.') return null;
    return double.tryParse(s);
  }

  /// PWA fmt(): fixed decimals, "—" when not finite.
  static String _formatResult(double? value, LengthUnit unit) {
    if (value == null || !value.isFinite) return '—';
    return value.toStringAsFixed(MetricConversionScreen.decimalsFor(unit));
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(title: const Text('Metric Conversion'), toolbarHeight: 64),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isDesktop = constraints.maxWidth >= 720;
            final double edge = isDesktop
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;

            return Center(
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
                        toolId: 'metric-conversion',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('metric-conversion'))
                        const SizedBox(height: AppSpacing.md),
                      _converterCard(text, mono),
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

  Widget _converterCard(TextTheme text, AppMonoText mono) {
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
          // From: value + source unit.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: LabeledField(
                  label: 'Value',
                  hint: '(${MetricConversionScreen.symbolFor(_fromUnit)})',
                  semanticLabel:
                      'Value in ${MetricConversionScreen.symbolFor(_fromUnit)}',
                  field: TextField(
                    controller: _valueCtrl,
                    focusNode: _valueFocus,
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
                    decoration: const InputDecoration(hintText: '1'),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: AppSelect<LengthUnit>(
                  value: _fromUnit,
                  items: _unitItems,
                  semanticLabel: 'From unit',
                  minWidth: 88,
                  onChanged: (u) {
                    setState(() => _fromUnit = u);
                    _recompute();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // To: result + target unit.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _resultBlock(text, mono)),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: AppSelect<LengthUnit>(
                  value: _toUnit,
                  items: _unitItems,
                  semanticLabel: 'To unit',
                  minWidth: 88,
                  onChanged: (u) {
                    setState(() => _toUnit = u);
                    _recompute();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultBlock(TextTheme text, AppMonoText mono) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Result',
          style: text.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // One SR node: "Result: 1.609 km" (or "not calculated"), instead of
        // value and unit symbol as separate fragments (Vera finding #6).
        Semantics(
          label: 'Result',
          value: _result == null
              ? 'not calculated'
              : '${_formatResult(_result, _toUnit)} '
                    '${MetricConversionScreen.symbolFor(_toUnit)}',
          excludeSemantics: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: SelectableText(
                  _formatResult(_result, _toUnit),
                  maxLines: 1,
                  style: mono.outputXL.copyWith(
                    color: _result == null
                        ? AppColors.textTertiary
                        : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                MetricConversionScreen.symbolFor(_toUnit),
                style: text.labelLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
    // Anchor conversions to meters — the PWA toM factors, made visible so a
    // field tech can sanity-check a result against a known constant.
    final List<List<String>> refs = const [
      ['1 km', '1,000 m'],
      ['1 mi', '1,609.344 m'],
      ['1 nmi', '1,852 m'],
      ['1 ft', '0.3048 m'],
      ['1 in', '0.0254 m'],
      ['1 cm', '0.01 m'],
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
                  // Column width snaps to the 8px base unit (GL-003 §4).
                  SizedBox(
                    width: 80,
                    child: Text(
                      row[0],
                      style: mono.inlineCode.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row[1],
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
