// Distance and Bearing — great-circle distance and initial bearing between two
// latitude/longitude points in decimal degrees.
//
// Math matches the RF Tools PWA reference (app.js calcDistBearing, line 571),
// which uses the spherical-earth haversine and the standard initial-bearing
// formula:
//   haversineKm: EARTH_KM = 6371 (km mean radius)
//     a = sin²(Δφ/2) + cos φ1 · cos φ2 · sin²(Δλ/2)
//     d = 6371 · 2 · atan2(√a, √(1−a))
//   bearingDeg (initial / forward):
//     y = sin Δλ · cos φ2
//     x = cos φ1 · sin φ2 − sin φ1 · cos φ2 · cos Δλ
//     θ = (atan2(y, x) in degrees + 360) mod 360
//   reverse bearing = (forward + 180) mod 360
//
// Output units mirror the PWA exactly:
//   km  = haversineKm                 (fmt 4 decimals)
//   mi  = km × 0.621371               (fmt 4 decimals)
//   m   = km × 1000                   (fmt 1 decimal)
//   ft  = km × 1000 × 3.28084         (fmt 1 decimal)
//   bearing forward / reverse in degrees (fmt 1 decimal, "°" suffix)
//
// Validation mirrors the PWA guards: |lat| ≤ 90, |lon| ≤ 180; any non-finite or
// out-of-range field blanks the outputs (no crash). The PWA surfaces these as
// inline error text; here the result rows blank to "—" with a single inline
// validity note, which fits the live-recompute tool pattern on this app.
//
// Pure, no network, no platform APIs. Math lives in static functions on the
// PUBLIC DistBearingScreen class so it is unit-testable against the PWA values.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

class DistBearingScreen extends StatefulWidget {
  const DistBearingScreen({super.key});

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Mirrors app.js: EARTH_KM, toRad, toDeg, haversineKm, bearingDeg.

  /// Mean earth radius in km. PWA const EARTH_KM.
  static const double earthKm = 6371;

  static double _toRad(double deg) => deg * math.pi / 180.0;
  static double _toDeg(double rad) => rad * 180.0 / math.pi;

  /// Great-circle distance in km between two decimal-degree points (haversine).
  /// Mirrors PWA haversineKm.
  static double haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final double dLat = _toRad(lat2 - lat1);
    final double dLon = _toRad(lon2 - lon1);
    final double a =
        math.pow(math.sin(dLat / 2), 2).toDouble() +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.pow(math.sin(dLon / 2), 2).toDouble();
    return earthKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Initial (forward) bearing in degrees, normalized to [0, 360).
  /// Mirrors PWA bearingDeg.
  static double bearingDeg(double lat1, double lon1, double lat2, double lon2) {
    final double dLon = _toRad(lon2 - lon1);
    final double y = math.sin(dLon) * math.cos(_toRad(lat2));
    final double x =
        math.cos(_toRad(lat1)) * math.sin(_toRad(lat2)) -
        math.sin(_toRad(lat1)) * math.cos(_toRad(lat2)) * math.cos(dLon);
    return (_toDeg(math.atan2(y, x)) + 360) % 360;
  }

  /// Reverse bearing = (forward + 180) mod 360. PWA bRev.
  static double reverseBearingDeg(double forward) => (forward + 180) % 360;

  @override
  State<DistBearingScreen> createState() => _DistBearingScreenState();
}

class _DistBearingScreenState extends State<DistBearingScreen> {
  final TextEditingController _lat1Ctrl = TextEditingController();
  final TextEditingController _lon1Ctrl = TextEditingController();
  final TextEditingController _lat2Ctrl = TextEditingController();
  final TextEditingController _lon2Ctrl = TextEditingController();

  final FocusNode _lat1Focus = FocusNode();
  final FocusNode _lon1Focus = FocusNode();
  final FocusNode _lat2Focus = FocusNode();
  final FocusNode _lon2Focus = FocusNode();

  // Computed distance in km and forward bearing in degrees, or null when input
  // is empty / invalid / out of range. Derived display values come from these.
  double? _km;
  double? _bearingFwd;

  // Set when input is present but a coordinate is out of the valid range, so we
  // can show one honest validity note instead of silently blanking.
  String? _rangeNote;

  // Latitude / longitude are signed decimals. Allow digits, dot, and a leading
  // minus; reject scientific notation since coordinates are typed by hand.
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

    // Any field empty / non-numeric → blank everything, no note (cold state).
    if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) {
      setState(() {
        _km = null;
        _bearingFwd = null;
        _rangeNote = null;
      });
      return;
    }

    // PWA range guards. All four present but out of range → blank + note.
    if (lat1.abs() > 90 || lat2.abs() > 90) {
      setState(() {
        _km = null;
        _bearingFwd = null;
        _rangeNote = 'Latitude must be −90 to 90.';
      });
      return;
    }
    if (lon1.abs() > 180 || lon2.abs() > 180) {
      setState(() {
        _km = null;
        _bearingFwd = null;
        _rangeNote = 'Longitude must be −180 to 180.';
      });
      return;
    }

    setState(() {
      _km = DistBearingScreen.haversineKm(lat1, lon1, lat2, lon2);
      _bearingFwd = DistBearingScreen.bearingDeg(lat1, lon1, lat2, lon2);
      _rangeNote = null;
    });
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  static double? _tryParseDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '-' || s == '.' || s == '-.') return null;
    return double.tryParse(s);
  }

  /// PWA fmt(n, decimals): fixed decimals, "—" when not finite / null.
  static String _fmt(double? n, int decimals) {
    if (n == null || !n.isFinite) return '—';
    return n.toStringAsFixed(decimals);
  }

  // Derived display values from the canonical km + forward bearing.
  String get _kmText => _fmt(_km, 4);
  String get _miText => _fmt(_km == null ? null : _km! * 0.621371, 4);
  String get _mText => _fmt(_km == null ? null : _km! * 1000, 1);
  String get _ftText => _fmt(_km == null ? null : _km! * 1000 * 3.28084, 1);
  String get _bFwdText =>
      _bearingFwd == null ? '—' : '${_fmt(_bearingFwd, 1)}°';
  String get _bRevText => _bearingFwd == null
      ? '—'
      : '${_fmt(DistBearingScreen.reverseBearingDeg(_bearingFwd!), 1)}°';

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Distance & Bearing'),
        toolbarHeight: 64,
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
                        toolId: 'dist-bearing',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('dist-bearing'))
                        const SizedBox(height: AppSpacing.md),
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _resultCard(text, mono),
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
          _pointHeader('Point 1', text),
          const SizedBox(height: AppSpacing.xs),
          _coordRow(
            latLabel: 'Latitude 1',
            lonLabel: 'Longitude 1',
            latController: _lat1Ctrl,
            lonController: _lon1Ctrl,
            latFocus: _lat1Focus,
            lonFocus: _lon1Focus,
            latHint: '40.7128',
            lonHint: '-74.0060',
            monoStyle: mono.outputLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          _pointHeader('Point 2', text),
          const SizedBox(height: AppSpacing.xs),
          _coordRow(
            latLabel: 'Latitude 2',
            lonLabel: 'Longitude 2',
            latController: _lat2Ctrl,
            lonController: _lon2Ctrl,
            latFocus: _lat2Focus,
            lonFocus: _lon2Focus,
            latHint: '34.0522',
            lonHint: '-118.2437',
            monoStyle: mono.outputLarge,
          ),
          if (_rangeNote != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _rangeNote!,
              style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pointHeader(String label, TextTheme text) {
    return Text(
      label,
      style: text.labelMedium?.copyWith(
        color: AppColors.textSecondary,
        letterSpacing: 0.4,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _coordRow({
    required String latLabel,
    required String lonLabel,
    required TextEditingController latController,
    required TextEditingController lonController,
    required FocusNode latFocus,
    required FocusNode lonFocus,
    required String latHint,
    required String lonHint,
    required TextStyle monoStyle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _coordField(
            label: latLabel,
            semanticLabel: '$latLabel in decimal degrees',
            controller: latController,
            focusNode: latFocus,
            hintText: latHint,
            monoStyle: monoStyle,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _coordField(
            label: lonLabel,
            semanticLabel: '$lonLabel in decimal degrees',
            controller: lonController,
            focusNode: lonFocus,
            hintText: lonHint,
            monoStyle: monoStyle,
          ),
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
      semanticLabel: semanticLabel,
      field: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        inputFormatters: _signedDecimal,
        onChanged: (_) => _recompute(),
        textInputAction: TextInputAction.next,
        autocorrect: false,
        enableSuggestions: false,
        style: monoStyle.copyWith(fontSize: AppTextSize.fieldNumeric),
        cursorColor: AppColors.primary,
        decoration: InputDecoration(hintText: hintText),
      ),
    );
  }

  Widget _resultCard(TextTheme text, AppMonoText mono) {
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
            'Great-circle distance',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Primary readout — km, mirroring the PWA's lead distance unit. One
          // SR node: "Great-circle distance: 3935.7460 km" (or "not
          // calculated"), instead of value/unit fragments (Vera finding #6).
          Semantics(
            label: 'Great-circle distance',
            value: _km == null ? 'not calculated' : '$_kmText km',
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SelectableText(
                  _kmText,
                  style: mono.outputXL.copyWith(
                    color: _km == null
                        ? AppColors.textTertiary
                        : AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  'km',
                  style: text.labelLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _dataRow('mi', _miText, mono, text),
          _dataRow('m', _mText, mono, text),
          _dataRow('ft', _ftText, mono, text),
          const SizedBox(height: AppSpacing.sm),
          Container(height: 1, color: AppColors.border),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Initial bearing',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _dataRow('Forward (1→2)', _bFwdText, mono, text, emphasize: true),
          _dataRow('Reverse (2→1)', _bRevText, mono, text),
        ],
      ),
    );
  }

  Widget _dataRow(
    String label,
    String value,
    AppMonoText mono,
    TextTheme text, {
    bool emphasize = false,
  }) {
    // One SR node per row: "Forward (1→2): 258.0°" (or "not calculated"),
    // instead of label and value fragments (Vera finding #6).
    return Semantics(
      label: label,
      value: value == '—' ? 'not calculated' : value,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label column snaps to 8px grid (GL-003 §4); 120px holds the widest
            // bearing label without truncating.
            SizedBox(
              width: 120,
              child: Text(
                label,
                style: text.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: mono.inlineCode.copyWith(
                  color: value == '—'
                      ? AppColors.textTertiary
                      : (emphasize ? AppColors.primary : AppColors.textPrimary),
                  fontWeight: emphasize ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
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
            'd = 2R · atan2(√a, √(1−a)),  R = 6371 km',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          SelectableText(
            'a = sin²(Δφ/2) + cos φ₁ · cos φ₂ · sin²(Δλ/2)',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Haversine great-circle distance and initial bearing on a sphere '
            'of mean radius 6371 km. Coordinates are decimal degrees.',
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
