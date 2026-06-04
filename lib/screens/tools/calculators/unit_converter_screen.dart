// Unit Converter — Batch 4a.
//
// The general-purpose sibling of metric_conversion_screen.dart (which is
// distance-only). One tool, a category `AppSelect` (data rate / storage /
// length / power / metric prefix / speed / temperature / time), then a
// from-unit / to-unit pair with one live result. Math + factor tables live in
// lib/data/unit_conversion.dart (pure, unit-tested); this screen is the UI.
//
// Reuses the calculator pattern exactly (ConceptGraphicBand header,
// AppSpacing.calculatorVerticalAlignment, content-max-width column,
// LabeledField + AppSelect + AppCopyAction + ToolHelpFooter), so it sits as a
// sibling of every other tool screen with zero new layout primitives.
//
// Decimal-vs-binary correctness (storage / rate) is the model's job
// (UnitConversion); this screen only renders. Power's dBm and temperature's
// affine conversions are handled in the model too — the UI is unit-agnostic.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../data/unit_conversion.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

class UnitConverterScreen extends StatefulWidget {
  const UnitConverterScreen({super.key});

  @override
  State<UnitConverterScreen> createState() => _UnitConverterScreenState();
}

class _UnitConverterScreenState extends State<UnitConverterScreen> {
  final TextEditingController _valueCtrl = TextEditingController();
  final FocusNode _valueFocus = FocusNode();

  UnitCategory _category = UnitCategory.dataRate;
  late Unit _fromUnit;
  late Unit _toUnit;

  double? _result;

  // Signed decimal + scientific input. A temperature can be negative; an RF
  // power can be entered as a pasted scientific value; so accept digits, a dot,
  // a sign, and e/E. (The model guards non-finite results downstream.)
  static final List<TextInputFormatter> _signedDecimal = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.eE+\-]')),
  ];

  @override
  void initState() {
    super.initState();
    _resetUnitsForCategory();
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    _valueFocus.dispose();
    super.dispose();
  }

  /// Default from/to to the first two units in the active category.
  void _resetUnitsForCategory() {
    final List<Unit> units = UnitConversion.unitsFor(_category);
    _fromUnit = units.first;
    _toUnit = units.length > 1 ? units[1] : units.first;
  }

  // ─── Category / unit selector items ─────────────────────────────────────────

  static final List<AppSelectItem<UnitCategory>> _categoryItems =
      UnitCategory.values
          .map((UnitCategory c) => (c, categoryLabel(c)))
          .toList();

  List<AppSelectItem<Unit>> get _unitItems => UnitConversion.unitsFor(_category)
      .map((Unit u) => (u, u.symbol))
      .toList();

  // ─── Handlers ───────────────────────────────────────────────────────────────

  void _onCategoryChanged(UnitCategory c) {
    setState(() {
      _category = c;
      _resetUnitsForCategory();
    });
    _recompute();
  }

  void _recompute() {
    final double? value = _tryParseDouble(_valueCtrl.text);
    if (value == null) {
      setState(() => _result = null);
      return;
    }
    setState(() {
      _result = UnitConversion.convert(value, _category, _fromUnit, _toUnit);
    });
  }

  static double? _tryParseDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '-' || s == '.' || s == '-.' || s == '+') return null;
    return double.tryParse(s);
  }

  String _resultText() => UnitConversion.formatResult(_result ?? double.nan);

  /// §8.16 copy payload — the conversion as a labeled text block, or null
  /// (→ disabled affordance) when there is no valid finite result.
  String? _buildCopyText() {
    final double? r = _result;
    if (r == null || !r.isFinite) return null;
    return (StringBuffer()
          ..writeln('Unit Converter — ${categoryLabel(_category)}')
          ..writeln('From: ${_valueCtrl.text.trim()} ${_fromUnit.symbol}')
          ..writeln('To: ${_resultText()} ${_toUnit.symbol}'))
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
        title: const Text('Unit Converter'),
        toolbarHeight: 64,
        // §8.16 — copy the conversion. Disabled until a valid result exists.
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
                    children: <Widget>[
                      ConceptGraphicBand(
                        toolId: 'unit-converter',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('unit-converter'))
                        const SizedBox(height: AppSpacing.md),
                      _categoryCard(),
                      const SizedBox(height: AppSpacing.md),
                      _converterCard(text, mono),
                      ToolHelpFooter(toolId: 'unit-converter'),
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

  Widget _categoryCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: LabeledField(
        label: 'Category',
        semanticLabel: 'Conversion category',
        field: AppSelect<UnitCategory>(
          value: _category,
          items: _categoryItems,
          semanticLabel: 'Conversion category',
          onChanged: _onCategoryChanged,
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
        children: <Widget>[
          // From: value + source unit.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: LabeledField(
                  label: 'Value',
                  hint: '(${_fromUnit.symbol})',
                  semanticLabel: 'Value in ${_fromUnit.symbol}',
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
                child: AppSelect<Unit>(
                  value: _fromUnit,
                  items: _unitItems,
                  semanticLabel: 'From unit',
                  minWidth: 96,
                  onChanged: (Unit u) {
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
            children: <Widget>[
              Expanded(child: _resultBlock(text, mono)),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: AppSelect<Unit>(
                  value: _toUnit,
                  items: _unitItems,
                  semanticLabel: 'To unit',
                  minWidth: 96,
                  onChanged: (Unit u) {
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
    final bool hasResult = _result != null && _result!.isFinite;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Result',
          style: text.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // One SR node: "Result: <value> <unit>" or "not calculated".
        Semantics(
          label: 'Result',
          value: hasResult
              ? '${_resultText()} ${_toUnit.symbol}'
              : 'not calculated',
          excludeSemantics: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(
                child: SelectableText(
                  _resultText(),
                  maxLines: 1,
                  style: mono.outputXL.copyWith(
                    color: hasResult
                        ? AppColors.primary
                        : AppColors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                _toUnit.symbol,
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
}
