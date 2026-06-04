// Downtilt Coverage calculator.
//
// Multi-output calculator: enter antenna height (AGL), mechanical downtilt
// angle, and antenna vertical beamwidth, read the near edge, far edge, and
// coverage depth on the ground. Formula matches the RF Tools PWA reference
// (app.js calcDtCoverage, line 462):
//   farAngle  = tilt - beamwidth/2   (smaller angle → reaches farther)
//   nearAngle = tilt + beamwidth/2   (larger angle  → lands closer)
//   edge      = height / tan(angle)
//   depth     = farEdge - nearEdge
// All angles in radians for the tan. If farAngle <= 0 the upper beam edge is at
// or above the horizon, so the far edge is unbounded — the PWA prints
// "∞ (beam above horizon)" and blanks depth; we mirror that.
//
// Unit conventions mirror the PWA dropdowns exactly:
//   Height    — m (default) or ft; ft ×0.3048 to m (toMeters).
//   Tilt      — degrees, no unit conversion.
//   Beamwidth — degrees, no unit conversion.
// Height normalizes to meters before the math. Edge / depth outputs are shown
// in both m and ft (×3.28084), rounded to 0 decimals to match the PWA
// fmt(value, 0).
//
// Edge cases:
// - Empty / partial input on any field → blank all outputs (no crash).
// - Height <= 0 → undefined geometry; blank.
// - Beamwidth <= 0 or >= 180 → out of range; blank (PWA guards the same band).
// - farAngle <= 0 → far edge "∞ (beam above horizon)", depth blank.
//
// Pure, no network, no platform APIs. Math lives in static functions on the
// public DowntiltCoverageScreen class so it is unit-testable against the PWA.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/field_unit_row.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/tool_help_action.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// Antenna height input units, mirroring the PWA dtc-height-unit select.
enum HeightUnit { m, ft }

/// Result of a downtilt-coverage computation, all distances in meters.
///
/// [farEdge] is null when the upper beam edge is at or above the horizon
/// (farAngle <= 0), in which case the far edge is unbounded and [depth] is
/// also null. [nearEdge] is always finite for valid inputs.
class DtCoverage {
  const DtCoverage({
    required this.nearEdge,
    required this.farEdge,
    required this.depth,
    required this.beamAboveHorizon,
  });

  /// Ground distance to the near edge of the beam, meters.
  final double nearEdge;

  /// Ground distance to the far edge of the beam, meters; null when unbounded.
  final double? farEdge;

  /// Coverage depth (far - near), meters; null when the far edge is unbounded.
  final double? depth;

  /// True when farAngle <= 0 (upper beam edge at or above the horizon).
  final bool beamAboveHorizon;
}

class DowntiltCoverageScreen extends StatefulWidget {
  const DowntiltCoverageScreen({super.key});

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Mirrors app.js: toMeters, calcDtCoverage.

  /// Normalize a height value to meters (PWA toMeters).
  static double heightToMeters(double value, HeightUnit unit) {
    switch (unit) {
      case HeightUnit.ft:
        return value * 0.3048;
      case HeightUnit.m:
        return value;
    }
  }

  /// Beam coverage geometry on the ground (PWA calcDtCoverage).
  ///
  /// [heightMeters] antenna AGL in meters, [tiltDeg] mechanical downtilt in
  /// degrees, [beamwidthDeg] antenna vertical beamwidth in degrees. Returns
  /// null when inputs are degenerate (height <= 0, or beamwidth outside the
  /// open 0..180 band) so the screen can blank, matching the PWA guards.
  static DtCoverage? coverage(
    double heightMeters,
    double tiltDeg,
    double beamwidthDeg,
  ) {
    if (heightMeters <= 0) return null;
    if (beamwidthDeg <= 0 || beamwidthDeg >= 180) return null;

    final double tiltR = tiltDeg * math.pi / 180;
    final double bwR = beamwidthDeg * math.pi / 180;

    final double farAngle = tiltR - bwR / 2;
    final double nearAngle = tiltR + bwR / 2;

    final double nearEdge = heightMeters / math.tan(nearAngle);

    if (farAngle <= 0) {
      // Upper beam edge at or above horizon → far edge unbounded.
      return DtCoverage(
        nearEdge: nearEdge,
        farEdge: null,
        depth: null,
        beamAboveHorizon: true,
      );
    }

    final double farEdge = heightMeters / math.tan(farAngle);
    return DtCoverage(
      nearEdge: nearEdge,
      farEdge: farEdge,
      depth: farEdge - nearEdge,
      beamAboveHorizon: false,
    );
  }

  @override
  State<DowntiltCoverageScreen> createState() => _DowntiltCoverageScreenState();
}

class _DowntiltCoverageScreenState extends State<DowntiltCoverageScreen> {
  final TextEditingController _heightCtrl = TextEditingController();
  final TextEditingController _tiltCtrl = TextEditingController();
  final TextEditingController _bwCtrl = TextEditingController();

  final FocusNode _heightFocus = FocusNode();
  final FocusNode _tiltFocus = FocusNode();
  final FocusNode _bwFocus = FocusNode();

  HeightUnit _heightUnit = HeightUnit.m;

  // Computed coverage, or null when input is empty / invalid / out of range.
  DtCoverage? _result;

  // Unsigned-decimal only. Height, tilt, and beamwidth are positive values a
  // human types by hand, so no sign and no scientific notation here.
  static final List<TextInputFormatter> _unsignedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

  @override
  void dispose() {
    _heightCtrl.dispose();
    _tiltCtrl.dispose();
    _bwCtrl.dispose();
    _heightFocus.dispose();
    _tiltFocus.dispose();
    _bwFocus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    final double? height = _tryParseDouble(_heightCtrl.text);
    final double? tilt = _tryParseDouble(_tiltCtrl.text);
    final double? bw = _tryParseDouble(_bwCtrl.text);
    if (height == null || tilt == null || bw == null) {
      setState(() => _result = null);
      return;
    }
    final double h = DowntiltCoverageScreen.heightToMeters(height, _heightUnit);
    setState(() => _result = DowntiltCoverageScreen.coverage(h, tilt, bw));
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  static double? _tryParseDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '.') return null;
    return double.tryParse(s);
  }

  /// `<m> m / <ft> ft` at 0 decimals (PWA fmt(value, 0)); "—" when null /
  /// non-finite.
  static String _formatDual(double? meters) {
    if (meters == null || !meters.isFinite) return '—';
    final String m = meters.toStringAsFixed(0);
    final String ft = (meters * 3.28084).toStringAsFixed(0);
    return '$m m / $ft ft';
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downtilt Coverage'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until a valid
        // coverage geometry is computed; copies the result as a labeled text
        // block (the beam-above-horizon verdict copies as its word).
        actions: <Widget>[
          // §8.16 order: copy LEADS, help TRAILS.
          AppCopyAction(textBuilder: _buildCopyText),
          ToolHelpAction(toolId: 'downtilt-coverage'),
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
                        toolId: 'downtilt-coverage',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('downtilt-coverage'))
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

  /// §8.16 copy payload — the coverage geometry as a labeled text block.
  ///
  /// Returns null (→ disabled affordance) whenever there is no valid coverage:
  /// any empty field, non-positive height, or out-of-band beamwidth. When the
  /// upper beam edge reaches the horizon the far edge copies as its verdict word
  /// ("Unbounded (beam above horizon)", §8.16) and depth as "Unbounded", since
  /// neither has a finite value — matching the on-screen [_resultBlock]. Field
  /// order and values match the on-screen inputs and result rows.
  String? _buildCopyText() {
    final DtCoverage? r = _result;
    if (r == null) return null;

    final String hUnit = _heightUnitLabel(_heightUnit);
    final String far = r.beamAboveHorizon
        ? 'Unbounded (beam above horizon)'
        : _formatDual(r.farEdge);
    final String depth = r.beamAboveHorizon
        ? 'Unbounded'
        : _formatDual(r.depth);

    return (StringBuffer()
          ..writeln('Downtilt Coverage')
          ..writeln('Antenna height (AGL): ${_heightCtrl.text.trim()} $hUnit')
          ..writeln('Downtilt angle: ${_tiltCtrl.text.trim()}°')
          ..writeln('Vertical beamwidth: ${_bwCtrl.text.trim()}°')
          ..writeln('Near edge: ${_formatDual(r.nearEdge)}')
          ..writeln('Far edge: $far')
          ..writeln('Coverage depth: $depth'))
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
            label: 'Downtilt angle',
            unitHint: '°',
            semanticLabel: 'Downtilt angle in degrees',
            controller: _tiltCtrl,
            focusNode: _tiltFocus,
            hintText: '6',
            monoStyle: mono.outputLarge,
            unitSelector: _degreeUnitChip(text),
          ),
          const SizedBox(height: AppSpacing.sm),
          _inputRow(
            label: 'Vertical beamwidth',
            unitHint: '°',
            semanticLabel: 'Antenna vertical beamwidth in degrees',
            controller: _bwCtrl,
            focusNode: _bwFocus,
            hintText: '15',
            monoStyle: mono.outputLarge,
            unitSelector: _degreeUnitChip(text),
          ),
          const SizedBox(height: AppSpacing.md),
          _resultBlock(text, mono),
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
    // FieldUnitRow reflows the unit selector beneath the field below 440px so
    // it never clips at phone widths (Vera web-demo gate, 2026-06-02).
    return FieldUnitRow(
      field: LabeledField(
        label: label,
        hint: '($unitHint)',
        semanticLabel: semanticLabel,
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
      unit: unitSelector,
    );
  }

  // Three outputs stacked: near edge, far edge, depth. Each shows m / ft.
  Widget _resultBlock(TextTheme text, AppMonoText mono) {
    final DtCoverage? r = _result;
    final String near = r == null ? '—' : _formatDual(r.nearEdge);
    final String far = r == null
        ? '—'
        : r.beamAboveHorizon
        ? '∞ (beam above horizon)'
        : _formatDual(r.farEdge);
    final String depth = r == null ? '—' : _formatDual(r.depth);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _resultRow(text, mono, 'Near edge', near, primary: r != null),
        const SizedBox(height: AppSpacing.sm),
        _resultRow(
          text,
          mono,
          'Far edge',
          far,
          primary: r != null && !r.beamAboveHorizon,
        ),
        const SizedBox(height: AppSpacing.sm),
        _resultRow(
          text,
          mono,
          'Coverage depth',
          depth,
          primary: r != null && r.depth != null,
        ),
      ],
    );
  }

  Widget _resultRow(
    TextTheme text,
    AppMonoText mono,
    String label,
    String value, {
    required bool primary,
  }) {
    // One SR node per row: "Near edge: 12.4 m" (or "not calculated"), instead
    // of label and value as separate fragments (Vera finding #6).
    return Semantics(
      label: label,
      value: value == '—' ? 'not calculated' : value,
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
          SelectableText(
            value,
            style: mono.outputLarge.copyWith(
              color: primary ? AppColors.primary : AppColors.textTertiary,
            ),
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

  // Degrees has no alternate unit, so render a static chip that matches the
  // toggle footprint rather than inventing a one-option toggle.
  Widget _degreeUnitChip(TextTheme text) {
    return Container(
      constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.borderStrong, width: 1),
      ),
      child: Text(
        '°',
        style: text.labelLarge?.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
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
            'edge = height / tan(tilt ∓ beamwidth/2)',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Height in meters, angles in degrees. The far edge uses '
            'tilt - beamwidth/2 and the near edge tilt + beamwidth/2. If the '
            'upper beam edge reaches the horizon the far edge is unbounded.',
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
    // Compact anchor values. Each row is a mount height, downtilt, and vertical
    // beamwidth against the near / far edge, computed from the same formula
    // this screen uses (rounded to 0 decimals, meters).
    final List<List<String>> refs = const [
      ['30 m', '10° / 15°', '95 / 687 m'],
      ['30 m', '12° / 10°', '98 / 244 m'],
      ['15 m', '12° / 8°', '52 / 107 m'],
      ['10 m', '10° / 6°', '43 / 81 m'],
      ['30 m', '6° / 15°', '125 m / ∞'],
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
                  width: 64,
                  child: Text(
                    'Height',
                    style: text.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    'Tilt / BW',
                    style: text.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Near / Far',
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
                    width: 64,
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
