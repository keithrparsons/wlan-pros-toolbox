// Architectural Scale calculator.
//
// The pilot tool for the AEC & Documentation field-reference set. Two jobs a
// WLAN pro reaching for a plan set needs:
//
//   1. Scale ↔ ratio. Pick a named architectural, engineering, or metric scale
//      (e.g. 1/4" = 1'-0") and read its dimensionless ratio (1:48). The
//      reference card lists every scale with its ratio for the reverse lookup
//      (given 1:96, which named scale is that?).
//   2. Drawn ↔ real. "I measured X on the PDF — how far is that really?" and the
//      reverse. Drawn → real multiplies by the ratio; real → drawn divides.
//
// The math is pure, offline, and unit-agnostic once a scale is reduced to its
// ratio R (= real ÷ drawn, dimensionless). A drawn measurement of X in ANY unit
// maps to real = X × R in that SAME unit; the units layer only converts in and
// out through a millimetre base. This is the exact conversion Ekahau's scale-
// calibration step performs, which is why it belongs beside the Wi-Fi tools.
//
//   Imperial rule: ratio = 12 ÷ (inches-per-foot on the drawing).
//     1/8" = 1'  →  12 ÷ 0.125  = 96   → 1:96
//     1/4" = 1'  →  12 ÷ 0.25   = 48   → 1:48
//   Engineer's:  1" = 20'  →  240 in ÷ 1 in = 240 → 1:240
//   Metric scales are already ratios: 1:50, 1:100, …
//
// Edge cases:
// - Empty / partial / negative measurement → blank the result to "—" (no crash).
// - A scale is always selected (no null-scale state), so the ratio readout is
//   always valid; only the Measure card blanks on bad input.
//
// Pure, no network, no platform APIs. Math + formatting live in static methods
// on the public widget class so they are unit-testable to the decimal.

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
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// The three scale families the tool covers.
enum ScaleFamily { architectural, engineering, metric }

/// Which way the Measure card is converting.
enum MeasureDirection { drawnToReal, realToDrawn }

/// The unit a distance measured ON the drawing is entered in.
enum DrawnUnit { inches, mm, cm }

/// The unit a real-world distance is entered / shown in.
enum RealUnit { feet, meters }

/// A named drawing scale reduced to its dimensionless ratio.
@immutable
class DrawingScale {
  const DrawingScale({
    required this.id,
    required this.label,
    required this.family,
    required this.ratio,
  });

  /// Stable kebab-case key.
  final String id;

  /// Human label, e.g. `1/4" = 1'-0"` or `1:100`.
  final String label;

  final ScaleFamily family;

  /// real ÷ drawn, dimensionless. 1/4" = 1'-0" → 48.
  final double ratio;

  /// The `1:N` ratio string (integer when whole, else 2 decimals).
  String get ratioLabel => '1:${ArchitecturalScaleScreen.trimRatio(ratio)}';
}

class ArchitecturalScaleScreen extends StatefulWidget {
  const ArchitecturalScaleScreen({super.key});

  // ─── Scale data (pure) ──────────────────────────────────────────────────
  // US architectural + engineer's scales and the common metric ratios. Ratios
  // verified by the imperial rule (12 ÷ inches-per-foot) and the engineer's
  // rule (feet-per-inch × 12). Ordered largest scale (smallest ratio) first.

  static const List<DrawingScale> scales = <DrawingScale>[
    // Architectural (fractional-inch) — ratio = 12 ÷ inches-per-foot.
    DrawingScale(id: '3in-1ft', label: '3" = 1\'-0"', family: ScaleFamily.architectural, ratio: 4),
    DrawingScale(id: '1-5in-1ft', label: '1-1/2" = 1\'-0"', family: ScaleFamily.architectural, ratio: 8),
    DrawingScale(id: '1in-1ft', label: '1" = 1\'-0"', family: ScaleFamily.architectural, ratio: 12),
    DrawingScale(id: '3-4in-1ft', label: '3/4" = 1\'-0"', family: ScaleFamily.architectural, ratio: 16),
    DrawingScale(id: '1-2in-1ft', label: '1/2" = 1\'-0"', family: ScaleFamily.architectural, ratio: 24),
    DrawingScale(id: '3-8in-1ft', label: '3/8" = 1\'-0"', family: ScaleFamily.architectural, ratio: 32),
    DrawingScale(id: '1-4in-1ft', label: '1/4" = 1\'-0"', family: ScaleFamily.architectural, ratio: 48),
    DrawingScale(id: '3-16in-1ft', label: '3/16" = 1\'-0"', family: ScaleFamily.architectural, ratio: 64),
    DrawingScale(id: '1-8in-1ft', label: '1/8" = 1\'-0"', family: ScaleFamily.architectural, ratio: 96),
    DrawingScale(id: '3-32in-1ft', label: '3/32" = 1\'-0"', family: ScaleFamily.architectural, ratio: 128),
    DrawingScale(id: '1-16in-1ft', label: '1/16" = 1\'-0"', family: ScaleFamily.architectural, ratio: 192),
    // Engineer's (decimal) — ratio = feet-per-inch × 12.
    DrawingScale(id: '1in-10ft', label: '1" = 10\'', family: ScaleFamily.engineering, ratio: 120),
    DrawingScale(id: '1in-20ft', label: '1" = 20\'', family: ScaleFamily.engineering, ratio: 240),
    DrawingScale(id: '1in-30ft', label: '1" = 30\'', family: ScaleFamily.engineering, ratio: 360),
    DrawingScale(id: '1in-40ft', label: '1" = 40\'', family: ScaleFamily.engineering, ratio: 480),
    DrawingScale(id: '1in-50ft', label: '1" = 50\'', family: ScaleFamily.engineering, ratio: 600),
    DrawingScale(id: '1in-60ft', label: '1" = 60\'', family: ScaleFamily.engineering, ratio: 720),
    DrawingScale(id: '1in-100ft', label: '1" = 100\'', family: ScaleFamily.engineering, ratio: 1200),
    // Metric — the ratio is the scale.
    DrawingScale(id: 'metric-1-20', label: '1:20', family: ScaleFamily.metric, ratio: 20),
    DrawingScale(id: 'metric-1-50', label: '1:50', family: ScaleFamily.metric, ratio: 50),
    DrawingScale(id: 'metric-1-100', label: '1:100', family: ScaleFamily.metric, ratio: 100),
    DrawingScale(id: 'metric-1-200', label: '1:200', family: ScaleFamily.metric, ratio: 200),
    DrawingScale(id: 'metric-1-500', label: '1:500', family: ScaleFamily.metric, ratio: 500),
    DrawingScale(id: 'metric-1-1000', label: '1:1000', family: ScaleFamily.metric, ratio: 1000),
  ];

  /// The default working scale — 1/4" = 1'-0", the most common US floor-plan
  /// working scale.
  static const String defaultScaleId = '1-4in-1ft';

  /// Look up a scale by id. Never null for an id from [scales]; the caller keeps
  /// [_scaleId] constrained to those ids.
  static DrawingScale scaleById(String id) =>
      scales.firstWhere((DrawingScale s) => s.id == id);

  /// Scales in a family, in [scales] order.
  static List<DrawingScale> scalesIn(ScaleFamily family) =>
      scales.where((DrawingScale s) => s.family == family).toList();

  /// The family's default (first-listed) scale id.
  static String defaultScaleFor(ScaleFamily family) =>
      scalesIn(family).first.id;

  // ─── Math (pure) ────────────────────────────────────────────────────────

  /// Millimetres per unit for a drawing-side measurement.
  static double drawnUnitMm(DrawnUnit unit) {
    switch (unit) {
      case DrawnUnit.inches:
        return 25.4;
      case DrawnUnit.mm:
        return 1.0;
      case DrawnUnit.cm:
        return 10.0;
    }
  }

  /// Millimetres per unit for a real-world measurement.
  static double realUnitMm(RealUnit unit) {
    switch (unit) {
      case RealUnit.feet:
        return 304.8;
      case RealUnit.meters:
        return 1000.0;
    }
  }

  /// Real-world length (in [realUnit]) for a [drawn] measurement in [drawnUnit]
  /// at [ratio]. real = drawn × ratio, computed through a millimetre base so the
  /// two ends can carry different units.
  static double drawnToReal(
    double drawn,
    DrawnUnit drawnUnit,
    double ratio,
    RealUnit realUnit,
  ) {
    final double drawnMm = drawn * drawnUnitMm(drawnUnit);
    final double realMm = drawnMm * ratio;
    return realMm / realUnitMm(realUnit);
  }

  /// Drawn length (in [drawnUnit]) that a [real] distance in [realUnit] draws at
  /// under [ratio]. drawn = real ÷ ratio.
  static double realToDrawn(
    double real,
    RealUnit realUnit,
    double ratio,
    DrawnUnit drawnUnit,
  ) {
    final double realMm = real * realUnitMm(realUnit);
    final double drawnMm = realMm / ratio;
    return drawnMm / drawnUnitMm(drawnUnit);
  }

  // ─── Formatting (pure) ──────────────────────────────────────────────────

  /// `1:N` ratio number — integer when whole, else 2 decimals.
  static String trimRatio(double ratio) {
    if ((ratio - ratio.roundToDouble()).abs() < 1e-9) {
      return ratio.round().toString();
    }
    return ratio.toStringAsFixed(2);
  }

  /// General length format — integer when whole, else 2 decimals; "—" when not
  /// finite.
  static String fmtLength(double? value) {
    if (value == null || !value.isFinite) return '—';
    if ((value - value.roundToDouble()).abs() < 1e-9) {
      return value.round().toString();
    }
    return value.toStringAsFixed(2);
  }

  /// Decimal feet → `F ft I in` (inches to the nearest whole inch, carrying at
  /// 12). Used as the friendly companion to a feet result.
  static String formatFeetInches(double feet) {
    final double abs = feet.abs();
    int ft = abs.floor();
    int inch = ((abs - ft) * 12).round();
    if (inch == 12) {
      ft += 1;
      inch = 0;
    }
    final String sign = feet < 0 ? '−' : '';
    return '$sign$ft ft $inch in';
  }

  /// Decimal inches → `W-n/d in` to the nearest 1/16", fraction reduced. Used as
  /// the friendly companion to an inches result (how a scale ruler reads).
  static String formatInchFraction(double inches) {
    final double abs = inches.abs();
    int whole = abs.floor();
    int sixteenths = ((abs - whole) * 16).round();
    if (sixteenths == 16) {
      whole += 1;
      sixteenths = 0;
    }
    final String sign = inches < 0 ? '−' : '';
    if (sixteenths == 0) return '$sign$whole in';
    int num = sixteenths;
    int den = 16;
    while (num.isEven && den.isEven) {
      num ~/= 2;
      den ~/= 2;
    }
    if (whole == 0) return '$sign$num/$den in';
    return '$sign$whole-$num/$den in';
  }

  @override
  State<ArchitecturalScaleScreen> createState() =>
      _ArchitecturalScaleScreenState();
}

class _ArchitecturalScaleScreenState extends State<ArchitecturalScaleScreen> {
  final TextEditingController _measureCtrl = TextEditingController();
  final FocusNode _measureFocus = FocusNode();

  ScaleFamily _family = ScaleFamily.architectural;
  String _scaleId = ArchitecturalScaleScreen.defaultScaleId;
  MeasureDirection _direction = MeasureDirection.drawnToReal;
  DrawnUnit _drawnUnit = DrawnUnit.inches;
  RealUnit _realUnit = RealUnit.feet;

  // Computed converted length, or null when the measurement is empty / invalid
  // / negative.
  double? _measureOut;

  static final List<TextInputFormatter> _unsignedDecimal =
      unsignedDecimalFormatters;

  DrawingScale get _scale => ArchitecturalScaleScreen.scaleById(_scaleId);

  @override
  void dispose() {
    _measureCtrl.dispose();
    _measureFocus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _onFamilyChanged(ScaleFamily family) {
    setState(() {
      _family = family;
      _scaleId = ArchitecturalScaleScreen.defaultScaleFor(family);
      // Nudge the measure units to the family's conventional pair, without
      // locking the user out of switching afterward.
      if (family == ScaleFamily.metric) {
        _drawnUnit = DrawnUnit.mm;
        _realUnit = RealUnit.meters;
      } else {
        _drawnUnit = DrawnUnit.inches;
        _realUnit = RealUnit.feet;
      }
    });
    _recompute();
  }

  void _recompute() {
    final double? value = tryParseFlexibleDouble(_measureCtrl.text);
    // Negative measurements are meaningless here (a distance on a page), so
    // blank rather than render a negative real-world length.
    if (value == null || value < 0) {
      setState(() => _measureOut = null);
      return;
    }
    final double ratio = _scale.ratio;
    final double out = _direction == MeasureDirection.drawnToReal
        ? ArchitecturalScaleScreen.drawnToReal(
            value, _drawnUnit, ratio, _realUnit)
        : ArchitecturalScaleScreen.realToDrawn(
            value, _realUnit, ratio, _drawnUnit);
    setState(() => _measureOut = out.isFinite ? out : null);
  }

  // ─── Labels ────────────────────────────────────────────────────────────────

  static String _drawnUnitLabel(DrawnUnit u) {
    switch (u) {
      case DrawnUnit.inches:
        return 'in';
      case DrawnUnit.mm:
        return 'mm';
      case DrawnUnit.cm:
        return 'cm';
    }
  }

  static String _realUnitLabel(RealUnit u) {
    switch (u) {
      case RealUnit.feet:
        return 'ft';
      case RealUnit.meters:
        return 'm';
    }
  }

  static String _familyLabel(ScaleFamily f) {
    switch (f) {
      case ScaleFamily.architectural:
        return 'Architectural';
      case ScaleFamily.engineering:
        return 'Engineering';
      case ScaleFamily.metric:
        return 'Metric';
    }
  }

  /// The unit the current result is expressed in.
  String get _outUnitLabel => _direction == MeasureDirection.drawnToReal
      ? _realUnitLabel(_realUnit)
      : _drawnUnitLabel(_drawnUnit);

  /// The friendly secondary line for the current result (ft-in for a feet
  /// result, fractional inches for an inches result), or null when there is no
  /// nicer form to show.
  String? get _outSecondary {
    final double? out = _measureOut;
    if (out == null) return null;
    if (_direction == MeasureDirection.drawnToReal &&
        _realUnit == RealUnit.feet) {
      return ArchitecturalScaleScreen.formatFeetInches(out);
    }
    if (_direction == MeasureDirection.realToDrawn &&
        _drawnUnit == DrawnUnit.inches) {
      return ArchitecturalScaleScreen.formatInchFraction(out);
    }
    return null;
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Architectural Scale'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Always enabled here (a scale
        // is always selected); copies the ratio plus any live measurement.
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
                      ConceptGraphicBand(
                        toolId: 'architectural-scale',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('architectural-scale'))
                        const SizedBox(height: AppSpacing.md),
                      _scaleCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _measureCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _formulaCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _referenceCard(text, mono),
                      ToolHelpFooter(toolId: 'architectural-scale'),
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

  /// §8.16 copy payload — the selected scale, its ratio, and the live
  /// measurement conversion when one is present.
  String? _buildCopyText() {
    final DrawingScale s = _scale;
    final StringBuffer buf = StringBuffer()
      ..writeln('Architectural Scale')
      ..writeln('Scale: ${s.label}')
      ..writeln('Ratio: ${s.ratioLabel}')
      ..writeln('Scale factor: ${ArchitecturalScaleScreen.trimRatio(s.ratio)}×');

    final double? out = _measureOut;
    if (out != null) {
      final String input = _measureCtrl.text.trim();
      if (_direction == MeasureDirection.drawnToReal) {
        buf.writeln(
          'Measured $input ${_drawnUnitLabel(_drawnUnit)} on the drawing '
          '= ${ArchitecturalScaleScreen.fmtLength(out)} '
          '${_realUnitLabel(_realUnit)} real-world',
        );
      } else {
        buf.writeln(
          '$input ${_realUnitLabel(_realUnit)} real-world '
          'draws at ${ArchitecturalScaleScreen.fmtLength(out)} '
          '${_drawnUnitLabel(_drawnUnit)}',
        );
      }
      final String? secondary = _outSecondary;
      if (secondary != null) buf.writeln('  ($secondary)');
    }
    return buf.toString().trimRight();
  }

  Widget _cardShell(Widget child) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }

  Widget _scaleCard(TextTheme text, AppMonoText mono) {
    final List<DrawingScale> familyScales =
        ArchitecturalScaleScreen.scalesIn(_family);
    return _cardShell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledField(
            label: 'Scale family',
            field: AppSelect<ScaleFamily>(
              value: _family,
              semanticLabel: 'Scale family',
              items: ScaleFamily.values
                  .map((ScaleFamily f) => (f, _familyLabel(f)))
                  .toList(),
              onChanged: _onFamilyChanged,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Scale',
            field: AppSelect<String>(
              value: _scaleId,
              semanticLabel: 'Drawing scale',
              items: familyScales
                  .map((DrawingScale s) => (s.id, s.label))
                  .toList(),
              onChanged: (String id) {
                setState(() => _scaleId = id);
                _recompute();
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ratioReadout(text, mono),
        ],
      ),
    );
  }

  Widget _ratioReadout(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final DrawingScale s = _scale;
    return Semantics(
      label: 'Ratio',
      value: '${s.ratioLabel}, scale factor '
          '${ArchitecturalScaleScreen.trimRatio(s.ratio)}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ratio',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(
            s.ratioLabel,
            style: mono.outputXL.copyWith(color: colors.textAccent),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Scale factor ${ArchitecturalScaleScreen.trimRatio(s.ratio)}× — '
            '1 unit on the drawing = ${ArchitecturalScaleScreen.trimRatio(s.ratio)} '
            'of the same unit in the field.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _measureCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final bool drawnToReal = _direction == MeasureDirection.drawnToReal;
    final String inputUnit =
        drawnToReal ? _drawnUnitLabel(_drawnUnit) : _realUnitLabel(_realUnit);
    final String inputLabel =
        drawnToReal ? 'Measured on the drawing' : 'Real-world distance';
    final String resultLabel =
        drawnToReal ? 'Real-world distance' : 'Drawn length';

    return _cardShell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Measure',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppToggle<MeasureDirection>(
            value: _direction,
            semanticLabel: 'Conversion direction',
            expand: true,
            items: const [
              (MeasureDirection.drawnToReal, 'Drawn → Real'),
              (MeasureDirection.realToDrawn, 'Real → Drawn'),
            ],
            onChanged: (MeasureDirection d) {
              setState(() => _direction = d);
              _recompute();
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Drawing units',
            field: AppToggle<DrawnUnit>(
              value: _drawnUnit,
              semanticLabel: 'Drawing units',
              items: const [
                (DrawnUnit.inches, 'in'),
                (DrawnUnit.mm, 'mm'),
                (DrawnUnit.cm, 'cm'),
              ],
              onChanged: (DrawnUnit u) {
                setState(() => _drawnUnit = u);
                _recompute();
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Real-world units',
            field: AppToggle<RealUnit>(
              value: _realUnit,
              semanticLabel: 'Real-world units',
              items: const [
                (RealUnit.feet, 'ft'),
                (RealUnit.meters, 'm'),
              ],
              onChanged: (RealUnit u) {
                setState(() => _realUnit = u);
                _recompute();
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // The drawing/real unit is set by the interactive toggles above and
          // restated in the field hint "(unit)"; no static unit chip here — it
          // would sit in the slot cable-loss uses for a live unit selector and
          // read as a dead control (worse when it reflows full-width < 440px).
          LabeledField(
            label: inputLabel,
            hint: '($inputUnit)',
            semanticLabel: '$inputLabel in $inputUnit',
            field: TextField(
              controller: _measureCtrl,
              focusNode: _measureFocus,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _unsignedDecimal,
              onChanged: (_) => _recompute(),
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              style: mono.outputLarge
                  .copyWith(fontSize: AppTextSize.fieldNumeric),
              cursorColor: colors.textAccent,
              decoration: InputDecoration(
                hintText: drawnToReal ? '3.5' : '45',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _measureResult(text, mono, resultLabel),
        ],
      ),
    );
  }

  Widget _measureResult(TextTheme text, AppMonoText mono, String label) {
    final AppColorScheme colors = context.colors;
    final bool blank = _measureOut == null;
    final String? secondary = _outSecondary;
    return Semantics(
      label: label,
      value: blank
          ? 'not calculated'
          : '${ArchitecturalScaleScreen.fmtLength(_measureOut)} $_outUnitLabel'
              '${secondary == null ? '' : ', $secondary'}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
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
                ArchitecturalScaleScreen.fmtLength(_measureOut),
                style: mono.outputXL.copyWith(
                  color: blank ? colors.textTertiary : colors.textAccent,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                _outUnitLabel,
                style: text.labelLarge?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          if (!blank && secondary != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '≈ $secondary',
              style: mono.inlineCode.copyWith(color: colors.textTertiary),
            ),
          ],
          if (blank) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Enter a measurement to convert.',
              style: text.labelMedium?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _formulaCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return _cardShell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How it works',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(
            'ratio = real ÷ drawn   (1/8" = 1\'-0" → 12 ÷ 0.125 = 96 → 1:96)',
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          SelectableText(
            'real = drawn × ratio      drawn = real ÷ ratio',
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The ratio is dimensionless, so a distance measured on the page maps '
            'to the same value in the field once you scale it — the same '
            'calibration step Ekahau, Hamina, and iBwave ask for when you import '
            'a plan. If a PDF has no embedded scale, measure a known dimension (a '
            '3\'-0" door, a 2×4 ft ceiling tile) to confirm which scale it is.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    // Reverse-lookup table: given a ratio, find the named scale. Covers the
    // common architectural + engineer's + metric scales in one place.
    final List<DrawingScale> rows = const <String>[
      '1-4in-1ft',
      '1-8in-1ft',
      '1-2in-1ft',
      '1in-1ft',
      '1in-20ft',
      '1in-50ft',
      'metric-1-50',
      'metric-1-100',
    ].map(ArchitecturalScaleScreen.scaleById).toList();

    return _cardShell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Common scales → ratio',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...rows.map((DrawingScale s) {
            return Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      s.label,
                      style: mono.inlineCode
                          .copyWith(color: colors.textSecondary),
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    child: Text(
                      s.ratioLabel,
                      textAlign: TextAlign.right,
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
          const SizedBox(height: AppSpacing.xs),
          Text(
            'US-primary. Architectural scales use fractional inches; engineer\'s '
            'scales (site / civil) use decimal feet per inch.',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
