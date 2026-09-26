// Controls and readouts for "Wi-Fi Through a Wall". Separate widgets from
// the stage (wifi_through_a_wall_stage.dart): each takes the WallConfig the
// screen's WallSlabController holds and reports changes through a callback,
// so the phone layout stacks them and the presenter layout puts them beside
// the stage. In presenter mode WallSlabControls drops its explanatory prose
// and folds the angle and polarization into a PresenterDisclosure.
//
//   WallSlabControls   band, channel, material, thickness, angle, TE/TM
//   WallSlabReadouts   loss (split into absorption and reflection),
//                      reflection, attenuation rate, wavelengths
//   WallBandsCard      the same wall at 2.4, 5.5 and 6.5 GHz
//   WallMeasuredCard   brief §6.4 measurements beside the P.2040 model,
//                      source named, disagreement stated, never averaged
//
// THEME: GL-003 §8. AppSelect for 4+ options (§8.14), AppToggle for 2-3.
// Lime only on the loss (the quantity the tool is about). No categorical
// hues (§8.15 case 3); no status hues, because model-versus-measurement is
// stated in words and is not a pass or fail verdict. ASCII copy, no em
// dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/wall_slab_physics.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../utils/decimal_input.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../labeled_field.dart';
import 'wifi_through_a_wall_parts.dart';

// ── Controls ──────────────────────────────────────────────────────────────

class WallSlabControls extends StatefulWidget {
  const WallSlabControls({
    super.key,
    required this.config,
    required this.onChanged,
  });

  final WallConfig config;
  final ValueChanged<WallConfig> onChanged;

  @override
  State<WallSlabControls> createState() => _WallSlabControlsState();
}

class _WallSlabControlsState extends State<WallSlabControls> {
  late final TextEditingController _mmCtrl;
  String? _mmError;

  static final double _logMax = _log10(kWallMaxMm);

  @override
  void initState() {
    super.initState();
    _mmCtrl = TextEditingController(text: fmtMm(widget.config.thicknessMm));
  }

  @override
  void didUpdateWidget(WallSlabControls old) {
    super.didUpdateWidget(old);
    // Thickness set from elsewhere (slider, a measured row): mirror it into
    // the field unless the field already says the same number.
    final double? typed = tryParseFlexibleDouble(_mmCtrl.text);
    if (typed != widget.config.thicknessMm &&
        old.config.thicknessMm != widget.config.thicknessMm) {
      _mmCtrl.text = fmtMm(widget.config.thicknessMm);
      _mmError = null;
    }
  }

  @override
  void dispose() {
    _mmCtrl.dispose();
    super.dispose();
  }

  static double _log10(double v) => math.log(v) / math.ln10;

  void _emit(WallConfig c) => widget.onChanged(c);

  void _onBand(WifiBand b) =>
      _emit(widget.config.copyWith(band: b, channel: defaultChannelFor(b)));

  void _onMmText(String raw) {
    final double? v = tryParseFlexibleDouble(raw);
    if (v == null || v < kWallMinMm || v > kWallMaxMm) {
      setState(
        () => _mmError =
            'Enter a thickness from ${kWallMinMm.toStringAsFixed(0)} to '
            '${kWallMaxMm.toStringAsFixed(0)} mm',
      );
      return;
    }
    setState(() => _mmError = null);
    _emit(widget.config.copyWith(thicknessMm: v));
  }

  /// Slider position 0..1 on a log scale from 1 to 500 mm.
  double _toSlider(double mm) => (_log10(mm) / _logMax).clamp(0.0, 1.0);

  double _fromSlider(double p) {
    final double mm = math.pow(10, p * _logMax).toDouble();
    final double rounded = mm < 10
        ? (mm * 10).roundToDouble() / 10
        : mm.roundToDouble();
    return rounded.clamp(kWallMinMm, kWallMaxMm);
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final WallConfig c = widget.config;
    final MaterialProperties p = c.result.props;
    final bool presenter = PresenterMode.isActive(context);

    final List<Widget> angle = <Widget>[
      Row(
        children: <Widget>[
          const WallSectionLabel('Angle of arrival'),
          const Spacer(),
          Text(
            '${c.angleDeg.toStringAsFixed(0)} deg',
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
      Slider(
        value: c.angleDeg,
        max: kWallMaxAngle,
        // Whole degrees, rounded here rather than with `divisions`, which
        // would paint 80 tick dots along the track.
        onChanged: (double v) => _emit(c.copyWith(angleDeg: v.roundToDouble())),
        activeColor: colors.primary,
        inactiveColor: colors.disabledFill,
        label: '${c.angleDeg.toStringAsFixed(0)} deg',
        semanticFormatterCallback: (double v) =>
            'Angle of arrival ${v.toStringAsFixed(0)} degrees',
      ),
      if (!presenter)
        Text(
          '0 deg hits the wall head on. 80 deg nearly skims along it.',
          style: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      const SizedBox(height: AppSpacing.sm),
      AppToggle<Polarization>(
        label: 'Polarization',
        value: c.polarization,
        expand: true,
        items: const <AppToggleItem<Polarization>>[
          (Polarization.te, 'TE'),
          (Polarization.tm, 'TM'),
        ],
        onChanged: (Polarization v) => _emit(c.copyWith(polarization: v)),
      ),
      if (!presenter) ...<Widget>[
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'TE: the electric field lies along the wall face. TM: it tilts '
          'with the angle of arrival. Head on (0 deg) they are the same.',
          style: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      ],
    ];

    return WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const WallSectionLabel('The signal'),
          const SizedBox(height: AppSpacing.xs),
          AppToggle<WifiBand>(
            label: 'Band',
            value: c.band,
            expand: true,
            items: <AppToggleItem<WifiBand>>[
              for (final WifiBand b in WifiBand.values) (b, b.label),
            ],
            onChanged: _onBand,
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Channel',
            semanticLabel: 'Channel',
            field: AppSelect<int>(
              value: c.channel,
              semanticLabel: 'Channel',
              items: <AppSelectItem<int>>[
                for (final int ch in channelsFor(c.band))
                  (
                    ch,
                    'Channel $ch  (${centerFrequencyMHzForBand(c.band, ch)} '
                        'MHz)',
                  ),
              ],
              onChanged: (int ch) => _emit(c.copyWith(channel: ch)),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const WallSectionLabel('The wall'),
          const SizedBox(height: AppSpacing.xs),
          // Ten materials: GL-003 §8.14 routes 4+ options to AppSelect.
          LabeledField(
            label: 'Material (ITU-R P.2040 Table 3)',
            semanticLabel: 'Material',
            field: AppSelect<WallMaterial>(
              value: c.material,
              semanticLabel: 'Material',
              items: <AppSelectItem<WallMaterial>>[
                for (final WallMaterial m in WallMaterial.values) (m, m.label),
              ],
              onChanged: (WallMaterial m) => _emit(c.copyWith(material: m)),
            ),
          ),
          if (!presenter) const SizedBox(height: AppSpacing.xxs),
          if (!presenter)
            Text(
              'At ${c.centerMHz} MHz: relative permittivity '
              '${_eps(p.epsReal)}, conductivity ${_sigma(p.sigma)} S/m. '
              'Table 3 range ${_ghz(c.material.minGhz)} to '
              '${_ghz(c.material.maxGhz)} GHz.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Thickness',
            hint: '(mm, 1 to 500)',
            semanticLabel: 'Thickness in millimeters',
            field: TextField(
              controller: _mmCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: unsignedDecimalFormatters,
              onChanged: _onMmText,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              style: mono.inlineCode.copyWith(
                fontSize: AppTextSize.fieldNumeric,
              ),
              cursorColor: colors.textAccent,
              decoration: InputDecoration(
                errorText: _mmError,
                suffixText: 'mm',
              ),
            ),
          ),
          Slider(
            value: _toSlider(c.thicknessMm),
            onChanged: (double v) {
              setState(() => _mmError = null);
              _emit(c.copyWith(thicknessMm: _fromSlider(v)));
            },
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            semanticFormatterCallback: (double v) =>
                'Thickness ${fmtMm(_fromSlider(v))} millimeters',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: ExcludeSemantics(
              child: Row(
                children: <Widget>[
                  Text('1 mm', style: _tick(text, colors)),
                  const Spacer(),
                  Text('500 mm', style: _tick(text, colors)),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (presenter)
            // Set once per lesson: folded so the panel fits a projector.
            PresenterDisclosure(
              title: 'Angle of arrival and polarization',
              children: angle,
            )
          else
            ...angle,
        ],
      ),
    );
  }

  TextStyle? _tick(TextTheme text, AppColorScheme colors) =>
      text.bodySmall?.copyWith(color: colors.textTertiary);

  static String _eps(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  static String _sigma(double v) {
    if (v >= 1000) return '${(v / 1e6).toStringAsFixed(0)} million';
    if (v >= 0.1) return v.toStringAsFixed(2);
    return v.toStringAsFixed(3);
  }

  static String _ghz(double v) => v < 1 ? v.toString() : v.toStringAsFixed(0);
}

// ── Readouts ──────────────────────────────────────────────────────────────

class WallSlabReadouts extends StatelessWidget {
  const WallSlabReadouts({super.key, required this.config});

  final WallConfig config;

  @override
  Widget build(BuildContext context) {
    final SlabResult r = config.result;
    final MaterialProperties p = r.props;
    final bool conductor = p.lossTangent > kConductorLossTangent;
    final double ripple = r.standingWaveRippleDb;

    final String rate = conductor
        ? '${fmtRate(p.attenuationExact)} (a conductor, not a dielectric)'
        : p.eq27aValid
        ? '${fmtRate(p.attenuationEq27a)} (P.2040 Eq. 27a)'
        : '${fmtRate(p.attenuationExact)} (exact: loss tangent '
              '${fmt1(p.lossTangent)} is past Eq. 27a\'s 0.5 limit)';

    final String inside = conductor
        ? 'none: the field dies within microns (skin depth '
              '${fmtLength(p.skinDepth)})'
        : p.eq27aValid
        ? fmtLength(p.lambdaInMaterial)
        : '${fmtLength(p.lambdaInMaterialExact)} (exact index; '
              'the simple formula gives ${fmtLength(p.lambdaInMaterial)})';

    return WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const WallSectionLabel('Readouts'),
          const SizedBox(height: AppSpacing.xs),
          WallRow(
            label: 'Frequency',
            value: '${config.centerMHz} MHz (ch ${config.channel})',
          ),
          WallRow(
            label: 'Transmission loss',
            value: fmtLossDb(r.transmissionLossDb),
            emphasize: true,
          ),
          WallRow(
            label: 'from absorption',
            value: fmtLossDb(r.absorptionDb),
            indent: true,
          ),
          WallRow(
            label: 'from reflection',
            value: fmtLossDb(r.reflectionPartDb),
            indent: true,
          ),
          WallRow(
            label: 'Reflection',
            value: r.reflectedPower <= 0
                ? 'none (no power reflected)'
                : '${fmt1(r.reflectionDb)} dB (${fmtPct(r.reflectedPower)} '
                      'of the power)',
          ),
          WallRow(label: 'Attenuation rate', value: rate),
          WallRow(label: 'Wavelength in air', value: fmtLength(p.lambdaAir)),
          WallRow(label: 'Wavelength inside', value: inside),
          WallRow(
            label: 'Ripple in front',
            value: ripple <= 40
                ? '${fmt1(ripple)} dB, peaks every '
                      '${fmtLength(p.lambdaAir / 2)}'
                : 'full nulls, every ${fmtLength(p.lambdaAir / 2)}',
          ),
          const SizedBox(height: AppSpacing.xs),
          const WallNote(
            icon: Icons.info_outline,
            message:
                'Absorption is the decay along the path inside the wall. '
                'Reflection is what the two faces send back, including the '
                'way their echoes add or cancel in a thin wall. The two add '
                'up to the total before rounding.',
          ),
        ],
      ),
    );
  }
}

// ── All three bands ───────────────────────────────────────────────────────

class WallBandsCard extends StatelessWidget {
  const WallBandsCard({super.key, required this.config});

  final WallConfig config;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final List<SlabResult> rs = <SlabResult>[
      for (final double f in kComparisonGhz) config.resultAt(f),
    ];
    final double lo = rs.first.transmissionLossDb;
    final double hi = rs.last.transmissionLossDb;
    final bool capped = lo > kLossDisplayCapDb;

    final String story;
    if (capped) {
      story =
          'Nothing measurable gets through this wall in any band, so the '
          'bands cannot be told apart.';
    } else if (hi >= lo + 0.05) {
      final double absShare = rs.last.absorptionDb - rs.first.absorptionDb;
      story =
          'Here 6.5 GHz loses ${fmt1(hi - lo)} dB more than 2.4 GHz. '
          '${fmt1(absShare)} dB of that difference is absorption: the '
          'material soaks up more energy per centimeter at higher frequency.';
    } else if (hi <= lo - 0.05) {
      story =
          'Here 6.5 GHz loses ${fmt1(lo - hi)} dB LESS than 2.4 GHz. That is '
          'thin-slab resonance: when the wall is close to a whole number of '
          'half wavelengths thick inside, the echoes from its two faces '
          'cancel and more gets through. Thin panels do not always lose more '
          'at higher frequency.';
    } else {
      story = 'Here the three bands lose about the same.';
    }

    TextStyle head = text.labelMedium!.copyWith(color: colors.textTertiary);
    TextStyle cell = mono.inlineCode.copyWith(color: colors.textPrimary);

    // Presenter mode scales the band column with its text.
    final double bandCol = 72 * PresenterMode.scaleOf(context).text;
    Widget row(List<Widget> cells) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: <Widget>[
          SizedBox(width: bandCol, child: cells[0]),
          for (final Widget w in cells.skip(1))
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: w),
            ),
        ],
      ),
    );

    String cap(double v) => v > kLossDisplayCapDb ? '>150' : fmt1(v);

    return WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const WallSectionLabel('All three bands, same wall'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${config.material.label}, ${fmtMm(config.thicknessMm)} mm, '
            '${config.angleDeg.toStringAsFixed(0)} deg, '
            '${config.polarization.name.toUpperCase()}. Loss in dB.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          ExcludeSemantics(
            child: row(<Widget>[
              Text('Band', style: head),
              Text('Total', style: head),
              Text('Absorb', style: head),
              Text('Reflect', style: head),
            ]),
          ),
          Divider(height: 1, color: colors.border),
          for (int i = 0; i < rs.length; i++)
            Semantics(
              label:
                  '${kComparisonGhz[i]} gigahertz: total '
                  '${fmtLossDb(rs[i].transmissionLossDb)}, absorption '
                  '${fmtLossDb(rs[i].absorptionDb)}, reflection '
                  '${fmtLossDb(rs[i].reflectionPartDb)}',
              excludeSemantics: true,
              child: row(<Widget>[
                Text('${kComparisonGhz[i]} GHz', style: cell),
                Text(
                  cap(rs[i].transmissionLossDb),
                  style: cell.copyWith(
                    color: colors.textAccent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(cap(rs[i].absorptionDb), style: cell),
                Text(cap(rs[i].reflectionPartDb), style: cell),
              ]),
            ),
          const SizedBox(height: AppSpacing.xs),
          WallNote(icon: Icons.stacked_line_chart, message: story),
        ],
      ),
    );
  }
}

// ── Measured values ───────────────────────────────────────────────────────

class WallMeasuredCard extends StatelessWidget {
  const WallMeasuredCard({
    super.key,
    required this.config,
    required this.onUseThickness,
  });

  final WallConfig config;

  /// Sets the wall to a specimen's thickness.
  final ValueChanged<double> onUseThickness;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final List<MeasuredSpecimen> specimens = measuredFor(config.material);

    return WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const WallSectionLabel('Measured values beside the model'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            specimens.isEmpty
                ? 'The research behind this tool found no published '
                      'measurement for ${config.material.label.toLowerCase()} '
                      'in these bands, so only the P.2040 model is shown.'
                : 'Each source on its own, never averaged. P.2040 is '
                      'computed for the same thickness, head on. NIST\'s '
                      'lowest point is 2.0 GHz: it has no data from 2.0 to '
                      '3.0 GHz.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          for (final MeasuredSpecimen s in specimens) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: AppSpacing.sm),
            _Specimen(
              specimen: s,
              config: config,
              onUseThickness: onUseThickness,
            ),
          ],
        ],
      ),
    );
  }
}

class _Specimen extends StatelessWidget {
  const _Specimen({
    required this.specimen,
    required this.config,
    required this.onUseThickness,
  });

  final MeasuredSpecimen specimen;
  final WallConfig config;
  final ValueChanged<double> onUseThickness;

  /// Model thickness: the specimen's, or the user's wall when the source
  /// states none (3GPP).
  double get _modelM => specimen.thicknessM ?? config.thicknessM;

  double _model(double fGhz) => WallSlab.compute(
    material: specimen.material,
    fGhz: fGhz,
    thicknessM: _modelM,
  ).transmissionLossDb;

  String _measured(MeasuredPoint p) {
    // As printed: a plot reading of 15 is "~15", not "~15.0".
    final String v = _trim(p.lossDb);
    switch (p.qualifier) {
      case MeasuredQualifier.approx:
        return '~$v';
      case MeasuredQualifier.upperBound:
        return '<$v';
      case MeasuredQualifier.exact:
        return v;
    }
  }

  String _gap(MeasuredPoint p, double model) {
    if (model > kLossDisplayCapDb) return '-';
    if (p.qualifier == MeasuredQualifier.upperBound) {
      return model <= p.lossDb ? 'within' : 'above';
    }
    final double g = p.lossDb - model;
    return g >= 0 ? '+${fmt1(g)}' : fmt1(g);
  }

  /// "Disagrees" when the model claims to describe the specimen; "Differs"
  /// when it does not (a stud wall, a hollow block, coated glass).
  String get _differs =>
      specimen.modelComparable ? 'Disagrees' : 'Differs, as expected';

  /// The disagreement, in words, computed from the rows.
  String _verdict(List<double> models) {
    final List<MeasuredPoint> pts = specimen.points;
    if (models.any((double m) => m > kLossDisplayCapDb)) {
      return 'The model\'s seamless sheet lets through nothing measurable '
          '(over ${kLossDisplayCapDb.toStringAsFixed(0)} dB); the real '
          'specimen measured ${fmt1(pts.first.lossDb)} dB.';
    }
    final List<String> bounds = <String>[];
    final List<double> gaps = <double>[];
    final List<double> ratios = <double>[];
    for (int i = 0; i < pts.length; i++) {
      final MeasuredPoint p = pts[i];
      if (p.qualifier == MeasuredQualifier.upperBound) {
        bounds.add(
          models[i] <= p.lossDb
              ? 'at ${p.fGhz} GHz the model (${fmt1(models[i])} dB) is within '
                    'the measured bound of under ${fmt1(p.lossDb)} dB'
              : 'at ${p.fGhz} GHz the model (${fmt1(models[i])} dB) is above '
                    'the measured bound of under ${fmt1(p.lossDb)} dB',
        );
        continue;
      }
      gaps.add(p.lossDb - models[i]);
      if (models[i] >= 0.5) ratios.add(p.lossDb / models[i]);
    }
    final StringBuffer b = StringBuffer();
    if (gaps.isNotEmpty) {
      final double lo = gaps.reduce((double a, double c) => a < c ? a : c);
      final double hi = gaps.reduce((double a, double c) => a > c ? a : c);
      if (lo.abs() <= 1 && hi.abs() <= 1) {
        b.write('Agrees with the model within 1 dB.');
      } else if (lo > 0) {
        b.write(
          '$_differs: measured is ${_range(lo, hi)} dB higher than the '
          'model',
        );
        b.write(_ratioText(ratios));
        b.write('.');
      } else if (hi < 0) {
        b.write(
          '$_differs: measured is ${_range(-hi, -lo)} dB lower than the '
          'model',
        );
        b.write(_ratioText(ratios));
        b.write('.');
      } else {
        b.write(
          'Mixed: measured runs from ${fmt1(-lo)} dB below to ${fmt1(hi)} dB '
          'above the model.',
        );
      }
    }
    if (bounds.isNotEmpty) {
      if (b.isNotEmpty) b.write(' ');
      final String joined = bounds.join('; ');
      b.write('${joined[0].toUpperCase()}${joined.substring(1)}.');
    }
    return b.toString();
  }

  static String _trim(double v) {
    String s = v.toStringAsFixed(2);
    while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static String _range(double a, double b) =>
      (b - a).abs() < 0.05 ? fmt1(a) : '${fmt1(a)} to ${fmt1(b)}';

  static String _ratioText(List<double> ratios) {
    if (ratios.isEmpty) return '';
    final double lo = ratios.reduce((double a, double c) => a < c ? a : c);
    final double hi = ratios.reduce((double a, double c) => a > c ? a : c);
    if (hi < 1.2 && lo > 0.83) return '';
    final String r = (hi - lo) < 0.05
        ? '${lo.toStringAsFixed(1)}x'
        : '${lo.toStringAsFixed(1)}x to ${hi.toStringAsFixed(1)}x';
    return ' ($r the model\'s dB)';
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final List<double> models = <double>[
      for (final MeasuredPoint p in specimen.points) _model(p.fGhz),
    ];
    final bool noThickness = specimen.thicknessM == null;
    final double? t = specimen.thicknessM;
    final bool canUse =
        t != null && (t * 1000 - config.thicknessMm).abs() > 1e-9;

    final TextStyle head = text.labelMedium!.copyWith(
      color: colors.textTertiary,
    );
    final TextStyle cell = mono.inlineCode.copyWith(color: colors.textPrimary);

    Widget row(List<Widget> cells) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs / 2),
      child: Row(
        children: <Widget>[
          SizedBox(width: 56, child: cells[0]),
          for (final Widget w in cells.skip(1))
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: w),
            ),
        ],
      ),
    );

    final String modelHead = noThickness
        ? 'P.2040 (${fmtMm(config.thicknessMm)} mm)'
        : 'P.2040';

    final StringBuffer sem = StringBuffer(
      '${specimen.source.label}: ${specimen.specimen}. ',
    );
    for (int i = 0; i < specimen.points.length; i++) {
      final MeasuredPoint p = specimen.points[i];
      sem.write(
        '${p.fGhz} gigahertz: measured ${_measured(p).replaceAll('~', 'about ').replaceAll('<', 'under ')} dB, '
        'model ${fmtLossDb(models[i])}. ',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: specimen.source.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: ': ${specimen.specimen}'),
            ],
          ),
          style: text.bodyMedium?.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Semantics(
          label: sem.toString(),
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              row(<Widget>[
                Text('GHz', style: head),
                // 3GPP is a formula, not a measurement.
                Text(
                  specimen.source == MeasurementSource.threeGpp38901
                      ? '3GPP'
                      : 'Measured',
                  style: head,
                ),
                Text(modelHead, style: head, textAlign: TextAlign.right),
                Text('Gap', style: head),
              ]),
              for (int i = 0; i < specimen.points.length; i++)
                row(<Widget>[
                  Text('${specimen.points[i].fGhz}', style: cell),
                  Text(_measured(specimen.points[i]), style: cell),
                  Text(
                    models[i] > kLossDisplayCapDb ? '>150' : fmt1(models[i]),
                    style: cell,
                  ),
                  Text(_gap(specimen.points[i], models[i]), style: cell),
                ]),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          noThickness
              ? '3GPP gives one loss per material class and no thickness, so '
                    'no model value is like-for-like. The P.2040 column is '
                    'your ${fmtMm(config.thicknessMm)} mm wall, for scale.'
              : _verdict(models),
          style: text.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        if (!specimen.modelComparable && !noThickness) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Not like-for-like. ${specimen.note ?? ''}',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ] else if (specimen.note != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            specimen.note!,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
        if (canUse)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => onUseThickness(t * 1000),
              style: TextButton.styleFrom(
                foregroundColor: colors.textAccent,
                minimumSize: const Size(0, AppSpacing.minTouchTarget),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              ),
              child: Text('Set the wall to ${fmtMm(t * 1000)} mm'),
            ),
          ),
      ],
    );
  }
}
