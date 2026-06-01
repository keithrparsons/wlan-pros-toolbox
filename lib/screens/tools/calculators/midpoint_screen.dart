// Midpoint (geographic) calculator.
//
// Given two coordinate pairs in decimal degrees, returns the great-circle
// midpoint — the point on the sphere halfway along the shortest path between
// them. This is NOT the naive average of the two lat/long pairs; that breaks
// near the poles and across the antimeridian.
//
// Formula matches the RF Tools PWA reference (app.js sphereMidpoint, called by
// calcMidpoint, line 592):
//   Bx = cos(φ2)·cos(Δλ)
//   By = cos(φ2)·sin(Δλ)
//   φm = atan2( sin(φ1) + sin(φ2), √((cos(φ1) + Bx)² + By²) )
//   λm = λ1 + atan2( By, cos(φ1) + Bx )
//   lon normalized to (−180, 180] via ((deg + 540) mod 360) − 180
// φ are latitudes in radians, λ longitudes in radians, Δλ = λ2 − λ1.
//
// Inputs are decimal degrees, exactly like the PWA (its `num()` reads a raw
// parseFloat with no unit conversion). Output is decimal degrees rounded to 6
// places to match the PWA fmtCoord `dd.toFixed(6)`.
//
// Edge cases:
// - Any of the four fields empty / invalid → blank both outputs (no crash).
//   Mirrors the PWA guard `[lat1,lon1,lat2,lon2].some(v => !isFinite(v))`.
// - Identical points → that point (the formula degenerates cleanly).
// - Across the antimeridian → longitude wraps correctly via the normalization.
//
// Pure, no network, no platform APIs. Math lives in static functions on the
// public class so it is unit-testable against the PWA values.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// Great-circle midpoint result in decimal degrees.
class MidpointResult {
  const MidpointResult({required this.lat, required this.lon});

  final double lat;
  final double lon;
}

class MidpointScreen extends StatefulWidget {
  const MidpointScreen({super.key});

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Mirrors app.js: toRad, toDeg, sphereMidpoint.

  static double _toRad(double deg) => deg * math.pi / 180.0;
  static double _toDeg(double rad) => rad * 180.0 / math.pi;

  /// Great-circle midpoint of two points in decimal degrees (PWA
  /// sphereMidpoint). Returns the midpoint in decimal degrees, longitude
  /// normalized to the (−180, 180] range.
  static MidpointResult sphereMidpoint(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final double phi1 = _toRad(lat1);
    final double phi2 = _toRad(lat2);
    final double dLambda = _toRad(lon2 - lon1);

    final double bx = math.cos(phi2) * math.cos(dLambda);
    final double by = math.cos(phi2) * math.sin(dLambda);

    final double phiM = math.atan2(
      math.sin(phi1) + math.sin(phi2),
      math.sqrt(math.pow(math.cos(phi1) + bx, 2) + by * by),
    );
    final double lambdaM = _toRad(lon1) + math.atan2(by, math.cos(phi1) + bx);

    return MidpointResult(
      lat: _toDeg(phiM),
      // PWA: ((toDeg(λm) + 540) % 360) - 180 → wrap into (−180, 180].
      lon: ((_toDeg(lambdaM) + 540) % 360) - 180,
    );
  }

  @override
  State<MidpointScreen> createState() => _MidpointScreenState();
}

class _MidpointScreenState extends State<MidpointScreen> {
  final TextEditingController _lat1Ctrl = TextEditingController();
  final TextEditingController _lon1Ctrl = TextEditingController();
  final TextEditingController _lat2Ctrl = TextEditingController();
  final TextEditingController _lon2Ctrl = TextEditingController();

  final FocusNode _lat1Focus = FocusNode();
  final FocusNode _lon1Focus = FocusNode();
  final FocusNode _lat2Focus = FocusNode();
  final FocusNode _lon2Focus = FocusNode();

  // Computed midpoint, or null when any input is empty / invalid.
  MidpointResult? _mid;

  // Signed decimal — coordinates carry a sign (S / W are negative). No
  // scientific notation; humans type plain decimal degrees by hand.
  static final List<TextInputFormatter> _signedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
  ];

  @override
  void dispose() {
    _lat1Ctrl.dispose();
    _lon1Ctrl.dispose();
    _lat2Ctrl.dispose();
    _lon2Ctrl.dispose();
    _lat1Focus.dispose();
    _lon1Focus.dispose();
    _lat2Focus.dispose();
    _lon2Focus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    final double? lat1 = _tryParseDouble(_lat1Ctrl.text);
    final double? lon1 = _tryParseDouble(_lon1Ctrl.text);
    final double? lat2 = _tryParseDouble(_lat2Ctrl.text);
    final double? lon2 = _tryParseDouble(_lon2Ctrl.text);
    // PWA guards `.some(v => !isFinite(v))` — any blank/invalid blanks output.
    if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) {
      setState(() => _mid = null);
      return;
    }
    setState(
      () => _mid = MidpointScreen.sphereMidpoint(lat1, lon1, lat2, lon2),
    );
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  static double? _tryParseDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '-' || s == '.' || s == '-.') return null;
    return double.tryParse(s);
  }

  /// PWA fmtCoord `dd.toFixed(6)`: fixed 6-decimal, "—" when not finite.
  static String _formatCoord(double? dd) {
    if (dd == null || !dd.isFinite) return '—';
    return dd.toStringAsFixed(6);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(title: const Text('Midpoint'), toolbarHeight: 64),
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
                        toolId: 'midpoint',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('midpoint'))
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
          _pointGroup(
            text: text,
            mono: mono,
            heading: 'Point A',
            latLabel: 'Latitude A',
            lonLabel: 'Longitude A',
            latCtrl: _lat1Ctrl,
            lonCtrl: _lon1Ctrl,
            latFocus: _lat1Focus,
            lonFocus: _lon1Focus,
          ),
          const SizedBox(height: AppSpacing.md),
          _pointGroup(
            text: text,
            mono: mono,
            heading: 'Point B',
            latLabel: 'Latitude B',
            lonLabel: 'Longitude B',
            latCtrl: _lat2Ctrl,
            lonCtrl: _lon2Ctrl,
            latFocus: _lat2Focus,
            lonFocus: _lon2Focus,
          ),
          const SizedBox(height: AppSpacing.md),
          _resultBlock(text, mono),
        ],
      ),
    );
  }

  // One labeled point: heading + lat row + lon row.
  Widget _pointGroup({
    required TextTheme text,
    required AppMonoText mono,
    required String heading,
    required String latLabel,
    required String lonLabel,
    required TextEditingController latCtrl,
    required TextEditingController lonCtrl,
    required FocusNode latFocus,
    required FocusNode lonFocus,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          heading,
          style: text.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _coordField(
          label: latLabel,
          semanticLabel: latLabel,
          controller: latCtrl,
          focusNode: latFocus,
          hintText: '40.6413',
          monoStyle: mono.outputLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        _coordField(
          label: lonLabel,
          semanticLabel: lonLabel,
          controller: lonCtrl,
          focusNode: lonFocus,
          hintText: '-73.7781',
          monoStyle: mono.outputLarge,
        ),
      ],
    );
  }

  Widget _coordField({
    required String label,
    required String semanticLabel,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required TextStyle monoStyle,
  }) {
    return LabeledField(
      label: label,
      hint: '(°)',
      semanticLabel: '$semanticLabel in decimal degrees',
      field: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        inputFormatters: _signedDecimal,
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

  Widget _resultBlock(TextTheme text, AppMonoText mono) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Great-circle midpoint',
          style: text.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _resultRow(text, mono, 'Lat', _formatCoord(_mid?.lat)),
        const SizedBox(height: AppSpacing.xs),
        _resultRow(text, mono, 'Lon', _formatCoord(_mid?.lon)),
      ],
    );
  }

  Widget _resultRow(
    TextTheme text,
    AppMonoText mono,
    String tag,
    String value,
  ) {
    final bool blank = _mid == null;
    // One SR node per row: "Lat: 37.401900" (or "not calculated"), instead of
    // tag and value as separate fragments (Vera finding #6).
    final String spoken = tag == 'Lat' ? 'Latitude' : 'Longitude';
    return Semantics(
      label: spoken,
      value: blank ? 'not calculated' : value,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              tag,
              style: text.labelLarge?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: mono.outputXL.copyWith(
                fontSize: 28,
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
            'Bx = cos(φ₂)·cos(Δλ)',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          SelectableText(
            'By = cos(φ₂)·sin(Δλ)',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          SelectableText(
            'φm = atan2(sin φ₁ + sin φ₂, √((cos φ₁ + Bx)² + By²))',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          SelectableText(
            'λm = λ₁ + atan2(By, cos φ₁ + Bx)',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Great-circle midpoint on a sphere. Decimal degrees in, decimal '
            'degrees out. This is the halfway point on the shortest path, not '
            'the average of the two coordinates.',
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
    // Anchor pairs computed from this screen's own formula so the values agree
    // with the live output to the decimal.
    final List<List<String>> refs = const [
      ['0, 0', '0, 90', '0.000000, 45.000000'],
      ['40, -75', '40, -75', '40.000000, -75.000000'],
      ['10, 170', '10, -170', '10.151082, -180.000000'],
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A ${row[0]}  •  B ${row[1]}',
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    'Mid ${row[2]}',
                    style: mono.inlineCode.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
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
