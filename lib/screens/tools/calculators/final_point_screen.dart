// Final Point (Destination) calculator.
//
// Given a start point (lat/lon in decimal degrees), an initial bearing, and a
// distance, compute the destination point along the great-circle path. Mirrors
// the RF Tools PWA reference (app.js destinationPt / calcFinalPoint):
//
//   δ  = dist_km / R          θ = bearing (rad)
//   φ2 = asin(sinφ1·cosδ + cosφ1·sinδ·cosθ)
//   λ2 = λ1 + atan2(sinθ·sinδ·cosφ1, cosδ - sinφ1·sinφ2)
//
// Earth radius constant is the PWA EARTH_KM = 6371 (spherical mean radius).
// Distance units mirror the PWA fp-dist-unit select exactly: km (default), mi
// (×1.60934), m (÷1000), normalized to km before the math (PWA toKm).
// Longitude is wrapped to (-180, 180] via the PWA `((deg + 540) % 360) - 180`
// expression. Output latitude / longitude are rounded to 6 decimals to match
// the PWA fmtCoord `dd.toFixed(6)`.
//
// Validation mirrors calcFinalPoint:
// - Any field empty / non-finite → blank both outputs (no crash).
// - |lat| > 90 or |lon| > 180 → invalid, blank outputs.
// - distance <= 0 → invalid, blank outputs.
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
import '../../../widgets/app_toggle.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// Distance input units, mirroring the PWA fp-dist-unit select.
enum FpDistUnit { km, mi, m }

/// A destination latitude / longitude pair in decimal degrees.
typedef DestinationPoint = ({double latitude, double longitude});

class FinalPointScreen extends StatefulWidget {
  const FinalPointScreen({super.key});

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Mirrors app.js: EARTH_KM, toKm, destinationPt.

  /// Spherical earth radius in km — PWA EARTH_KM.
  static const double earthRadiusKm = 6371;

  /// Normalize a distance value to km (PWA toKm).
  static double distToKm(double value, FpDistUnit unit) {
    switch (unit) {
      case FpDistUnit.mi:
        return value * 1.60934;
      case FpDistUnit.m:
        return value / 1000.0;
      case FpDistUnit.km:
        return value;
    }
  }

  /// Destination point given a start lat/lon (decimal degrees), an initial
  /// bearing (degrees), and a distance in km. Direct great-circle solution,
  /// matching PWA destinationPt. Longitude wrapped to (-180, 180].
  static DestinationPoint destination(
    double lat,
    double lon,
    double bearingDeg,
    double distKm,
  ) {
    final double delta = distKm / earthRadiusKm;
    final double theta = _toRad(bearingDeg);
    final double phi1 = _toRad(lat);
    final double lambda1 = _toRad(lon);

    final double phi2 = math.asin(
      math.sin(phi1) * math.cos(delta) +
          math.cos(phi1) * math.sin(delta) * math.cos(theta),
    );
    final double lambda2 =
        lambda1 +
        math.atan2(
          math.sin(theta) * math.sin(delta) * math.cos(phi1),
          math.cos(delta) - math.sin(phi1) * math.sin(phi2),
        );

    final double outLat = _toDeg(phi2);
    final double outLon = ((_toDeg(lambda2) + 540) % 360) - 180;
    return (latitude: outLat, longitude: outLon);
  }

  static double _toRad(double d) => d * math.pi / 180.0;
  static double _toDeg(double r) => r * 180.0 / math.pi;

  @override
  State<FinalPointScreen> createState() => _FinalPointScreenState();
}

class _FinalPointScreenState extends State<FinalPointScreen> {
  final TextEditingController _latCtrl = TextEditingController();
  final TextEditingController _lonCtrl = TextEditingController();
  final TextEditingController _bearingCtrl = TextEditingController();
  final TextEditingController _distCtrl = TextEditingController();

  final FocusNode _latFocus = FocusNode();
  final FocusNode _lonFocus = FocusNode();
  final FocusNode _bearingFocus = FocusNode();
  final FocusNode _distFocus = FocusNode();

  FpDistUnit _distUnit = FpDistUnit.km;

  // Computed destination, or null when input is empty / invalid.
  DestinationPoint? _result;

  // Set when input is present but a value is out of range, so we show one honest
  // validity note instead of silently blanking (Vera finding #10 — matches the
  // Distance & Bearing screen's range-note pattern). Null in the cold state.
  String? _rangeNote;

  // Lat/lon/bearing can be negative; allow a leading minus and decimal point.
  static final List<TextInputFormatter> _signedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
  ];
  // Distance is always positive — unsigned decimal only.
  static final List<TextInputFormatter> _unsignedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

  @override
  void dispose() {
    _latCtrl.dispose();
    _lonCtrl.dispose();
    _bearingCtrl.dispose();
    _distCtrl.dispose();
    _latFocus.dispose();
    _lonFocus.dispose();
    _bearingFocus.dispose();
    _distFocus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    final double? lat = _tryParseDouble(_latCtrl.text);
    final double? lon = _tryParseDouble(_lonCtrl.text);
    final double? brng = _tryParseDouble(_bearingCtrl.text);
    final double? dist = _tryParseDouble(_distCtrl.text);

    // Any field empty / non-numeric → blank, no note (cold state).
    if (lat == null || lon == null || brng == null || dist == null) {
      setState(() {
        _result = null;
        _rangeNote = null;
      });
      return;
    }

    final double distKm = FinalPointScreen.distToKm(dist, _distUnit);

    // Validation mirrors PWA calcFinalPoint. All fields present but out of
    // range → blank + a visible note rather than a silent blank (finding #10).
    if (lat.abs() > 90) {
      setState(() {
        _result = null;
        _rangeNote = 'Latitude must be −90 to 90.';
      });
      return;
    }
    if (lon.abs() > 180) {
      setState(() {
        _result = null;
        _rangeNote = 'Longitude must be −180 to 180.';
      });
      return;
    }
    if (distKm <= 0) {
      setState(() {
        _result = null;
        _rangeNote = 'Distance must be greater than 0.';
      });
      return;
    }

    setState(() {
      _result = FinalPointScreen.destination(lat, lon, brng, distKm);
      _rangeNote = null;
    });
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  static double? _tryParseDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '-' || s == '.' || s == '-.') return null;
    final double? v = double.tryParse(s);
    if (v == null || !v.isFinite) return null;
    return v;
  }

  /// PWA fmtCoord dd.toFixed(6): fixed 6-decimal, "—" when no result.
  static String _formatCoord(double? value) {
    if (value == null || !value.isFinite) return '—';
    return value.toStringAsFixed(6);
  }

  /// §8.16 copy payload — the great-circle destination as a labeled text block.
  ///
  /// Returns null (→ disabled affordance) whenever there is no valid result:
  /// an empty/invalid field or an out-of-range input (the on-screen note carries
  /// nothing to copy). Echoes the start point, bearing, and distance with the
  /// currently-selected unit, then the computed destination lat/long.
  String? _buildCopyText() {
    final DestinationPoint? r = _result;
    if (r == null) return null;

    final String unit = _distUnitLabel(_distUnit);
    return (StringBuffer()
          ..writeln('Final Point')
          ..writeln('Start latitude: ${_latCtrl.text.trim()}°')
          ..writeln('Start longitude: ${_lonCtrl.text.trim()}°')
          ..writeln('Bearing: ${_bearingCtrl.text.trim()}°')
          ..writeln('Distance: ${_distCtrl.text.trim()} $unit')
          ..writeln('Destination latitude: ${_formatCoord(r.latitude)}°')
          ..writeln('Destination longitude: ${_formatCoord(r.longitude)}°'))
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
        title: const Text('Final Point'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until a valid
        // destination is computed; copies the start point, bearing, distance,
        // and the destination lat/long as a labeled text block.
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
                        toolId: 'final-point',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('final-point'))
                        const SizedBox(height: AppSpacing.md),
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _formulaCard(text, mono),
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
          _field(
            label: 'Start latitude',
            unitHint: 'decimal degrees',
            controller: _latCtrl,
            focusNode: _latFocus,
            hintText: '34.052',
            formatters: _signedDecimal,
            signed: true,
            monoStyle: mono.outputLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          _field(
            label: 'Start longitude',
            unitHint: 'decimal degrees',
            controller: _lonCtrl,
            focusNode: _lonFocus,
            hintText: '-118.243',
            formatters: _signedDecimal,
            signed: true,
            monoStyle: mono.outputLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          _field(
            label: 'Bearing',
            unitHint: 'degrees',
            controller: _bearingCtrl,
            focusNode: _bearingFocus,
            hintText: '45',
            formatters: _signedDecimal,
            signed: true,
            monoStyle: mono.outputLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          _distanceRow(text, mono),
          if (_rangeNote != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _rangeNote!,
              style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _resultRow(text, mono),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required String unitHint,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required List<TextInputFormatter> formatters,
    required bool signed,
    required TextStyle monoStyle,
  }) {
    return LabeledField(
      label: label,
      hint: '($unitHint)',
      semanticLabel: '$label in $unitHint',
      field: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.numberWithOptions(
          decimal: true,
          signed: signed,
        ),
        inputFormatters: formatters,
        onChanged: (_) => _recompute(),
        textInputAction: TextInputAction.done,
        autocorrect: false,
        enableSuggestions: false,
        style: monoStyle.copyWith(fontSize: AppTextSize.fieldNumeric),
        cursorColor: AppColors.primary,
        decoration: InputDecoration(hintText: hintText),
      ),
    );
  }

  Widget _distanceRow(TextTheme text, AppMonoText mono) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: LabeledField(
            label: 'Distance',
            hint: '(${_distUnitLabel(_distUnit)})',
            semanticLabel: 'Distance in ${_distUnitLabel(_distUnit)}',
            field: TextField(
              controller: _distCtrl,
              focusNode: _distFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: _unsignedDecimal,
              onChanged: (_) => _recompute(),
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              style: mono.outputLarge.copyWith(
                fontSize: AppTextSize.fieldNumeric,
              ),
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(hintText: '10'),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        AppToggle<FpDistUnit>(
          value: _distUnit,
          items: const [
            (FpDistUnit.km, 'km'),
            (FpDistUnit.mi, 'mi'),
            (FpDistUnit.m, 'm'),
          ],
          onChanged: (u) {
            setState(() => _distUnit = u);
            _recompute();
          },
        ),
      ],
    );
  }

  static String _distUnitLabel(FpDistUnit u) {
    switch (u) {
      case FpDistUnit.km:
        return 'km';
      case FpDistUnit.mi:
        return 'mi';
      case FpDistUnit.m:
        return 'm';
    }
  }

  Widget _resultRow(TextTheme text, AppMonoText mono) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Destination',
          style: text.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _coordLine('Latitude', _result?.latitude, text, mono),
        const SizedBox(height: AppSpacing.xs),
        _coordLine('Longitude', _result?.longitude, text, mono),
      ],
    );
  }

  Widget _coordLine(
    String label,
    double? value,
    TextTheme text,
    AppMonoText mono,
  ) {
    final bool blank = value == null || !value.isFinite;
    // One SR node per coordinate: "Latitude: 34.052360" (or "not calculated"),
    // instead of label and value as separate fragments (Vera finding #6).
    return Semantics(
      label: label,
      value: blank ? 'not calculated' : _formatCoord(value),
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: text.labelLarge?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: SelectableText(
              _formatCoord(value),
              style: mono.outputLarge.copyWith(
                color: blank ? AppColors.textTertiary : AppColors.primary,
              ),
            ),
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
            'φ₂ = asin(sinφ₁·cosδ + cosφ₁·sinδ·cosθ)',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          SelectableText(
            'λ₂ = λ₁ + atan2(sinθ·sinδ·cosφ₁, cosδ − sinφ₁·sinφ₂)',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'δ = distance / R, θ = bearing. Great-circle destination on a '
            'sphere of radius R = 6371 km.',
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
