// Earth Curvature Bulge calculator.
//
// Single-input-plus-K-factor calculator: enter a path length and pick a
// K-factor, read the earth bulge at the path midpoint in meters and feet.
// Formula matches the RF Tools PWA reference (app.js calcEarth, line 497):
//   Re_eff(km) = 6371 · k                  (effective earth radius)
//   bulge(m)   = (d_km² · 1000) / (8 · Re_eff)
//   bulge(ft)  = bulge(m) · 3.28084
//
// Unit conventions mirror the PWA dropdowns exactly:
//   Path length — km (default) or mi; mi ×1.60934 to km (toKm).
//   K-factor    — 4/3 standard (1.333, default), 1.0 geometric,
//                 2/3 worst-case subrefraction (0.667), 2.0 superrefraction.
// Output rounds to 2 decimals to match the PWA fmt(bulge, 2).
//
// Edge cases:
// - Empty / non-numeric path length → blank both outputs (no crash).
// - Path length <= 0 → PWA rejects it; show "—".
//
// Pure, no network, no platform APIs. Math lives in static functions on the
// public class so it is unit-testable against the PWA values.

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

/// Path-length input units, mirroring the PWA ec-dist-unit select.
enum PathUnit { km, mi }

/// K-factor presets, mirroring the PWA ec-kfactor select. The double `value`
/// is the multiplier applied to the mean earth radius (6371 km).
enum KFactor {
  fourThirds(1.333, '4/3 standard (1.333)'),
  geometric(1.0, '1.0 geometric'),
  twoThirds(0.667, '2/3 worst-case'),
  superrefraction(2.0, '2.0 superrefraction');

  const KFactor(this.value, this.label);

  final double value;
  final String label;
}

class EarthCurvatureScreen extends StatefulWidget {
  const EarthCurvatureScreen({super.key});

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Mirrors app.js: toKm, calcEarth.

  /// Mean earth radius in km (PWA constant in calcEarth).
  static const double meanEarthRadiusKm = 6371.0;

  /// Meters-to-feet factor (PWA 3.28084).
  static const double feetPerMeter = 3.28084;

  /// Normalize a path length to km (PWA toKm, km/mi subset).
  static double pathToKm(double value, PathUnit unit) {
    switch (unit) {
      case PathUnit.mi:
        return value * 1.60934;
      case PathUnit.km:
        return value;
    }
  }

  /// Earth bulge at the path midpoint, in meters, for a path of distKm km and
  /// the given K-factor. (PWA calcEarth: d²·1000 / (8 · 6371·k).)
  static double bulgeMeters(double distKm, double kFactor) {
    final double reEffKm = meanEarthRadiusKm * kFactor;
    return (distKm * distKm * 1000.0) / (8.0 * reEffKm);
  }

  /// Earth bulge in feet (PWA bulge_ft = bulge_m · 3.28084).
  static double metersToFeet(double meters) => meters * feetPerMeter;

  @override
  State<EarthCurvatureScreen> createState() => _EarthCurvatureScreenState();
}

class _EarthCurvatureScreenState extends State<EarthCurvatureScreen> {
  final TextEditingController _distCtrl = TextEditingController();
  final FocusNode _distFocus = FocusNode();

  PathUnit _pathUnit = PathUnit.km;
  KFactor _kFactor = KFactor.fourThirds;

  // Computed bulge in meters, or null when input is empty / invalid / non-positive.
  double? _bulgeM;

  // Unsigned-decimal only. Path lengths are always positive and hand-typed.
  static final List<TextInputFormatter> _unsignedDecimal = unsignedDecimalFormatters;

  @override
  void dispose() {
    _distCtrl.dispose();
    _distFocus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    final double? dist = tryParseFlexibleDouble(_distCtrl.text);
    if (dist == null) {
      setState(() => _bulgeM = null);
      return;
    }
    final double d = EarthCurvatureScreen.pathToKm(dist, _pathUnit);
    // PWA guards d <= 0 before computing; do the same so we never render 0 or
    // a meaningless result for an empty-ish path.
    if (d <= 0) {
      setState(() => _bulgeM = null);
      return;
    }
    setState(
      () => _bulgeM = EarthCurvatureScreen.bulgeMeters(d, _kFactor.value),
    );
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  /// PWA fmt(n, 2): fixed 2-decimal, "—" when not finite or null.
  static String _formatFixed(double? n) {
    if (n == null || !n.isFinite) return '—';
    return n.toStringAsFixed(2);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Earth Curvature'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until a valid
        // bulge is computed; copies the result as a labeled text block.
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
                        toolId: 'earth-curvature',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('earth-curvature'))
                        const SizedBox(height: AppSpacing.md),
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _formulaCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _referenceCard(text, mono),
                      ToolHelpFooter(toolId: 'earth-curvature'),
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

  /// §8.16 copy payload — the earth bulge as a labeled text block.
  ///
  /// Returns null (→ disabled affordance) whenever there is no valid bulge:
  /// empty / non-numeric / non-positive path length. Field order and values
  /// match the on-screen inputs and [_resultRow].
  String? _buildCopyText() {
    final double? bulgeM = _bulgeM;
    if (bulgeM == null) return null;

    final double bulgeFt = EarthCurvatureScreen.metersToFeet(bulgeM);
    final String pathUnit = _pathUnitLabel(_pathUnit);

    return (StringBuffer()
          ..writeln('Earth Curvature')
          ..writeln('Path length: ${_distCtrl.text.trim()} $pathUnit')
          ..writeln('K-factor: ${_kFactor.label}')
          ..writeln('Earth bulge at midpoint: ${_formatFixed(bulgeM)} m')
          ..writeln('Earth bulge at midpoint: ${_formatFixed(bulgeFt)} ft'))
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
          _pathRow(mono),
          const SizedBox(height: AppSpacing.sm),
          _kFactorRow(text),
          const SizedBox(height: AppSpacing.md),
          _resultRow(text, mono),
        ],
      ),
    );
  }

  Widget _pathRow(AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    // FieldUnitRow reflows the unit selector beneath the field below 440px so
    // it never clips at phone widths (Vera web-demo gate, 2026-06-02).
    return FieldUnitRow(
      field: LabeledField(
        label: 'Path Length',
        hint: '(${_pathUnitLabel(_pathUnit)})',
        semanticLabel: 'Path length in ${_pathUnitLabel(_pathUnit)}',
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
          cursorColor: colors.textAccent,
          decoration: const InputDecoration(hintText: '20'),
        ),
      ),
      unit: AppToggle<PathUnit>(
        value: _pathUnit,
        items: const [(PathUnit.km, 'km'), (PathUnit.mi, 'mi')],
        onChanged: (u) {
          setState(() => _pathUnit = u);
          _recompute();
        },
      ),
    );
  }

  Widget _kFactorRow(TextTheme text) {
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'K-Factor (effective earth radius)',
          style: text.labelMedium?.copyWith(
            color: colors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // Full-width Select — four long K-factor labels, §8.14 Select case.
        AppSelect<KFactor>(
          value: _kFactor,
          semanticLabel: 'K-factor',
          items: KFactor.values.map((KFactor k) => (k, k.label)).toList(),
          onChanged: (KFactor k) {
            setState(() => _kFactor = k);
            _recompute();
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Use 4/3 for typical planning. Lower k means more bulge.',
          style: text.labelMedium?.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }

  Widget _resultRow(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final double? bulgeFt = _bulgeM == null
        ? null
        : EarthCurvatureScreen.metersToFeet(_bulgeM!);
    // One SR node: "Earth bulge at midpoint: 1.23 meters, 4.04 feet" (or "not
    // calculated"), instead of value/unit fragments across two lines (Vera
    // finding #6).
    final bool blank = _bulgeM == null;
    return Semantics(
      label: 'Earth bulge at midpoint',
      value: blank
          ? 'not calculated'
          : '${_formatFixed(_bulgeM)} meters, ${_formatFixed(bulgeFt)} feet',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Earth bulge at midpoint',
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
                _formatFixed(_bulgeM),
                style: mono.outputXL.copyWith(
                  color: _bulgeM == null
                      ? colors.textTertiary
                      : colors.textAccent,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'm',
                style: text.labelLarge?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SelectableText(
                _formatFixed(bulgeFt),
                style: mono.outputLarge.copyWith(
                  color: _bulgeM == null
                      ? colors.textTertiary
                      : colors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'ft',
                style: text.labelLarge?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _pathUnitLabel(PathUnit u) {
    switch (u) {
      case PathUnit.km:
        return 'km';
      case PathUnit.mi:
        return 'mi';
    }
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
            // Re: the ₑ subscript is absent from every bundled face, so the
            // effective-radius symbol stays ASCII; d² uses the real superscript.
            'h(m) = d² · 1000 / (8 · Re)',
            style: mono.robotoMono.copyWith(color: colors.textPrimary),
          ),
          SelectableText(
            'Re   = 6371 · k',
            style: mono.robotoMono.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'd in km, Re is the effective earth radius in km. h is the bulge '
            'at the path midpoint. The K-factor scales the radius for '
            'atmospheric refraction.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    // Anchor values at the default 4/3 K-factor, computed from the same formula
    // this screen uses. Columns are path length → bulge in meters.
    final List<List<String>> refs = const [
      ['5 km', '0.37 m'],
      ['10 km', '1.47 m'],
      ['20 km', '5.89 m'],
      ['40 km', '23.55 m'],
      ['80 km', '94.20 m'],
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
            'Reference points (k = 4/3)',
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
                  SizedBox(
                    width: 96,
                    child: Text(
                      row[0],
                      style: mono.inlineCode.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row[1],
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
