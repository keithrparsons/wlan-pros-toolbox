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

import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
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
  static final List<TextInputFormatter> _unsignedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

  @override
  void dispose() {
    _distCtrl.dispose();
    _distFocus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    final double? dist = _tryParseDouble(_distCtrl.text);
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
    setState(() => _bulgeM = EarthCurvatureScreen.bulgeMeters(d, _kFactor.value));
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  static double? _tryParseDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '.') return null;
    return double.tryParse(s);
  }

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
      ),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: LabeledField(
            label: 'Path Length',
            hint: '(${_pathUnitLabel(_pathUnit)})',
            semanticLabel: 'Path length in ${_pathUnitLabel(_pathUnit)}',
            field: TextField(
              controller: _distCtrl,
              focusNode: _distFocus,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _unsignedDecimal,
              onChanged: (_) => _recompute(),
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              style: mono.outputLarge.copyWith(fontSize: 20),
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(hintText: '20'),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _UnitToggle<PathUnit>(
          value: _pathUnit,
          options: const [
            (PathUnit.km, 'km'),
            (PathUnit.mi, 'mi'),
          ],
          onChanged: (u) {
            setState(() => _pathUnit = u);
            _recompute();
          },
        ),
      ],
    );
  }

  Widget _kFactorRow(TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'K-Factor (effective earth radius)',
          style: text.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          decoration: BoxDecoration(
            color: AppColors.inputFill,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: AppColors.borderStrong, width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<KFactor>(
              value: _kFactor,
              isExpanded: true,
              dropdownColor: AppColors.surface2,
              borderRadius: BorderRadius.circular(AppRadius.control),
              iconEnabledColor: AppColors.textSecondary,
              style: text.bodyLarge?.copyWith(color: AppColors.textPrimary),
              items: KFactor.values.map((k) {
                return DropdownMenuItem<KFactor>(
                  value: k,
                  child: Text(k.label),
                );
              }).toList(),
              onChanged: (k) {
                if (k == null) return;
                setState(() => _kFactor = k);
                _recompute();
              },
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Use 4/3 for typical planning. Lower k means more bulge.',
          style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }

  Widget _resultRow(TextTheme text, AppMonoText mono) {
    final double? bulgeFt = _bulgeM == null
        ? null
        : EarthCurvatureScreen.metersToFeet(_bulgeM!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Earth bulge at midpoint',
          style: text.labelMedium?.copyWith(
            color: AppColors.textSecondary,
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
                    ? AppColors.textTertiary
                    : AppColors.primary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'm',
              style: text.labelLarge?.copyWith(color: AppColors.textSecondary),
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
                    ? AppColors.textTertiary
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'ft',
              style: text.labelLarge?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ],
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
            'h(m) = d² · 1000 / (8 · Rₑ)',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          SelectableText(
            'Rₑ   = 6371 · k',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'd in km, Rₑ is the effective earth radius in km. h is the bulge '
            'at the path midpoint. The K-factor scales the radius for '
            'atmospheric refraction.',
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
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
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reference points (k = 4/3)',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...refs.map((row) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      row[0],
                      style: mono.inlineCode.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row[1],
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

/// Segmented unit toggle for an input row. Holds to the §8.3 minimum touch
/// target and uses ChoiceChip-style selection without inventing new tokens.
class _UnitToggle<T> extends StatelessWidget {
  const _UnitToggle({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.borderStrong, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final bool selected = opt.$1 == value;
          return Semantics(
            button: true,
            selected: selected,
            label: opt.$2,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.control),
              onTap: () => onChanged(opt.$1),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: AppSpacing.minTouchTarget,
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Text(
                  opt.$2,
                  style: text.labelLarge?.copyWith(
                    color: selected
                        ? AppColors.secondary
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
