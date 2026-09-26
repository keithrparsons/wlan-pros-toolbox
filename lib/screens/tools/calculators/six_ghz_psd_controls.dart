// Controls and readouts for the Wi-Fi Lab 6 GHz Power and PSD tool.
//
// Everything that is not the plot: region, the classes to show, distance,
// extra loss, noise figure and the AP authorized powers
// (SixGhzPsdControls); the per-class numbers at the selected width with the
// plain-language PSD-limited or cap-limited line (SixGhzPsdReadouts); and
// the three lessons with the formulas (SixGhzPsdExplainer). Each takes a
// SixGhzPsdModel and none knows about SixGhzPsdStage, so a screen composes
// them in whatever arrangement it needs.
//
// PRESENTER: SixGhzPsdControls keeps the region and the class list open
// (one line per class) and folds the link and the AP grants into
// PresenterDisclosures, with no phone prose, so the panel fits a projector;
// the per-class numbers move onto the stage.
//
// THEME: context.colors (dark §8 / light §8.20), class hues from PsdPalette
// (§8.15.2) on the class samples only. No status hues: PSD-limited and
// cap-limited are descriptions, not pass/fail verdicts (§8.13 rule 6).
// ASCII copy, no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/fspl_math.dart';
import '../../../services/wifi_lab/six_ghz_psd_math.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'six_ghz_psd_model.dart';
import 'six_ghz_psd_parts.dart';

// ── Controls ──────────────────────────────────────────────────────────────

class SixGhzPsdControls extends StatelessWidget {
  const SixGhzPsdControls({super.key, required this.model});
  final SixGhzPsdModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (BuildContext context, Widget? _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _children(context),
      ),
    );
  }

  List<Widget> _children(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final SixGhzPsdModel m = model;
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);
    final bool us = m.region == PsdRegion.us;
    if (PresenterMode.isActive(context)) {
      return <Widget>[
        _regionToggle(),
        const SizedBox(height: AppSpacing.sm),
        const PsdSectionLabel('Classes to show'),
        const SizedBox(height: AppSpacing.xxs),
        for (final PowerClass c in m.regionClasses)
          _classRow(context, c, compact: true),
        const SizedBox(height: AppSpacing.xs),
        PresenterDisclosure(
          title: 'Link: distance, walls, noise figure',
          children: _linkSliders(context),
        ),
        if (us)
          PresenterDisclosure(
            title: 'AP authorized power',
            children: _grantSliders(context),
          ),
      ];
    }

    return <Widget>[
      _regionToggle(),
      const SizedBox(height: AppSpacing.md),
      const PsdSectionLabel('Classes to show'),
      const SizedBox(height: AppSpacing.xxs),
      for (final PowerClass c in m.regionClasses) _classRow(context, c),
      const SizedBox(height: AppSpacing.md),
      const PsdSectionLabel('Link'),
      ..._linkSliders(context),
      Text(
        'Free-space loss at ${SixGhzPsdMath.referenceFreqMHz.round()} MHz '
        '(channel 31) for every width, so only the width changes. The '
        'receive antenna is 0 dBi.',
        style: small(),
      ),
      if (us) ...<Widget>[
        const SizedBox(height: AppSpacing.md),
        const PsdSectionLabel('AP authorized power'),
        ..._grantSliders(context),
        Text(
          'SP and GVP clients must stay 6 dB below their AP\'s authorized '
          'power, and the AP itself cannot exceed its grant. Turn on an SP '
          'or GVP class to use these.',
          style: small(),
        ),
      ] else ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        const PsdNote(
          Icons.info_outline,
          'The EU has no client offset: an LPI client may use the same '
          '23 dBm as the AP, so there is no AP power to set.',
        ),
      ],
    ];
  }

  Widget _regionToggle() => AppToggle<PsdRegion>(
    label: 'Region',
    value: model.region,
    expand: true,
    items: <AppToggleItem<PsdRegion>>[
      for (final PsdRegion r in PsdRegion.values) (r, r.label),
    ],
    onChanged: model.setRegion,
  );

  List<Widget> _linkSliders(BuildContext context) {
    final SixGhzPsdModel m = model;
    return <Widget>[
      _slider(
        context,
        label: 'Distance',
        valueText: PsdFormat.dist(m.distanceM),
        value: FsplMath.log10(m.distanceM),
        min: 0,
        max: 2,
        divisions: 100,
        onChanged: (double v) => m.setDistance(math.pow(10, v).toDouble()),
        semantic: (double v) =>
            'Distance ${PsdFormat.dist(math.pow(10, v).toDouble())}',
      ),
      _slider(
        context,
        label: 'Extra loss (walls)',
        valueText: '${PsdFormat.n(m.extraLossDb, 0)} dB',
        value: m.extraLossDb,
        min: 0,
        max: 40,
        divisions: 40,
        onChanged: m.setExtraLoss,
        semantic: (double v) => 'Extra loss ${v.round()} dB',
      ),
      _slider(
        context,
        label: 'Noise figure',
        valueText: '${PsdFormat.n(m.noiseFigureDb)} dB',
        value: m.noiseFigureDb,
        min: 3,
        max: 12,
        divisions: 18,
        onChanged: m.setNoiseFigure,
        semantic: (double v) => 'Noise figure ${PsdFormat.n(v)} dB',
      ),
    ];
  }

  List<Widget> _grantSliders(BuildContext context) {
    final SixGhzPsdModel m = model;
    return <Widget>[
      _slider(
        context,
        label: 'Standard Power AP (AFC)',
        valueText: '${PsdFormat.n(m.spAuthorizedDbm, 0)} dBm',
        value: m.spAuthorizedDbm,
        min: 0,
        max: 36,
        divisions: 36,
        enabled: m.spGrantInPlay,
        onChanged: m.setSpAuthorized,
        semantic: (double v) => 'Standard Power AP authorized ${v.round()} dBm',
      ),
      _slider(
        context,
        label: 'GVP AP (geofencing)',
        valueText: '${PsdFormat.n(m.gvpAuthorizedDbm, 0)} dBm',
        value: m.gvpAuthorizedDbm,
        min: 0,
        max: 24,
        divisions: 24,
        enabled: m.gvpGrantInPlay,
        onChanged: m.setGvpAuthorized,
        semantic: (double v) => 'GVP AP authorized ${v.round()} dBm',
      ),
    ];
  }

  /// One class with its checkbox. [compact] (presenter) drops the limits
  /// line under the name.
  Widget _classRow(BuildContext context, PowerClass c, {bool compact = false}) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool on = model.isShown(c);
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: () => model.setShown(c, !on),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
          ),
          child: Row(
            children: <Widget>[
              Checkbox(
                value: on,
                onChanged: (bool? v) => model.setShown(c, v ?? false),
              ),
              SizedBox(
                width: 28 * PresenterMode.scaleOf(context).marker,
                height: 14 * PresenterMode.scaleOf(context).marker,
                child: ExcludeSemantics(child: PsdClassSample(powerClass: c)),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      c.label,
                      style: text.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    if (!compact)
                      Text(
                        '${PsdFormat.n(c.psdDbmPerMHz, 0)} dBm/MHz, '
                        'max ${PsdFormat.n(c.maxEirpDbm, 0)} dBm',
                        style: text.bodySmall?.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slider(
    BuildContext context, {
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String Function(double) semantic,
    bool enabled = true,
  }) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: AppSpacing.xs),
        ExcludeSemantics(
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: text.bodyMedium?.copyWith(
                    color: enabled ? colors.textSecondary : colors.textDisabled,
                  ),
                ),
              ),
              Text(
                valueText,
                style: mono.inlineCode.copyWith(
                  color: enabled ? colors.textPrimary : colors.textDisabled,
                ),
              ),
            ],
          ),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: enabled ? onChanged : null,
          activeColor: colors.primary,
          inactiveColor: colors.disabledFill,
          label: valueText,
          semanticFormatterCallback: semantic,
        ),
      ],
    );
  }
}

// ── Readouts ──────────────────────────────────────────────────────────────

/// Per-class EIRP, noise floor, SNR, MCS and channels at the selected width,
/// each with its PSD-limited or cap-limited line.
class SixGhzPsdReadouts extends StatelessWidget {
  const SixGhzPsdReadouts({super.key, required this.model});
  final SixGhzPsdModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final List<PowerClass> cs = model.classes;
    final int w = model.widthMHz;
    return PsdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PsdSectionLabel(
            'At $w MHz, ${PsdFormat.dist(model.distanceM)}'
            '${model.extraLossDb > 0 ? ' + ${PsdFormat.n(model.extraLossDb, 0)} dB' : ''}',
          ),
          const SizedBox(height: AppSpacing.xs),
          if (cs.isEmpty)
            const PsdNote(
              Icons.visibility_off_outlined,
              'No class is on. Turn one on to read its EIRP, noise floor and '
              'SNR.',
            )
          else ...<Widget>[
            _sharedLine(context),
            for (final PowerClass c in cs) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              _classBlock(context, model.reading(c)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _sharedLine(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String Function(double, [int]) n = PsdFormat.n;
    final double nf = SixGhzPsdMath.noiseFloorDbm(
      model.widthMHz,
      model.noiseFigureDb,
    );
    return Text(
      'Noise floor ${n(nf)} dBm (-174 dBm/Hz + '
      '${n(SixGhzPsdMath.bandwidthDb(model.widthMHz) + 60)} dB for '
      '${model.widthMHz} MHz + ${n(model.noiseFigureDb)} dB noise figure). '
      'Free-space loss ${n(model.pathLossDb)} dB.',
      style: text.bodySmall?.copyWith(color: colors.textSecondary),
    );
  }

  Widget _classBlock(BuildContext context, PsdClassReading r) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final String Function(double, [int]) n = PsdFormat.n;
    final PowerClass c = r.powerClass;

    Widget value(String label, String v, {bool strong = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: text.labelSmall?.copyWith(color: colors.textTertiary),
        ),
        Text(
          v,
          style: mono.inlineCode.copyWith(
            color: strong ? colors.textAccent : colors.textPrimary,
            fontWeight: strong ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ],
    );

    final String mcs = r.mcs == null
        ? 'Below the lowest MCS in the Signal Thresholds table.'
        : 'Typical highest MCS: ${r.mcs!.label} (Signal Thresholds table).';

    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 28,
                height: 14,
                child: ExcludeSemantics(child: PsdClassSample(powerClass: c)),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  c.label,
                  style: text.titleSmall?.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xxs,
            children: <Widget>[
              value('EIRP', '${n(r.eirpDbm)} dBm', strong: true),
              value('Received', '${n(r.receivedDbm)} dBm'),
              value('SNR', '${n(r.snrDb)} dB', strong: true),
              value('PSD', '${n(r.radiatedPsd)} dBm/MHz'),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            model.verdict(c),
            style: text.bodyMedium?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            '$mcs ${SixGhzPsdMath.subBandText(c)}: ${r.channels} '
            '${r.channels == 1 ? 'channel' : 'channels'} of ${r.widthMHz} MHz. '
            '${c.rule}.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ── Explainer ─────────────────────────────────────────────────────────────

class SixGhzPsdExplainer extends StatelessWidget {
  const SixGhzPsdExplainer({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    TextStyle body() => text.bodyMedium!.copyWith(color: colors.textPrimary);
    TextStyle formula() =>
        mono.inlineCode.copyWith(color: colors.textSecondary);
    return PsdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PsdSectionLabel('What the chart says'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '1. 6 GHz power is limited per MHz (power spectral density, PSD) '
            'as well as in total. While the PSD limit binds, doubling the '
            'width adds 3 dB of EIRP. The noise floor also rises 3 dB, so '
            'SNR holds.',
            style: body(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '2. Once a total cap binds (Standard Power, GVP, or any class at '
            'its maximum), EIRP stops growing. The same power is spread '
            'thinner and every doubling of width costs 3 dB of SNR.',
            style: body(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '3. The client -6 dB rule is narrower than it is usually taught. '
            'Only Standard Power and GVP clients are held 6 dB below their '
            'AP\'s authorized power. The LPI client is a flat 24 dBm that '
            'happens to sit 6 dB under the LPI AP. Fixed client devices are '
            'exempt, VLP has no client class, and the EU has no client '
            'offset at all.',
            style: body(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'EIRP = min(PSD + 10 log10(BW MHz), max EIRP)',
            style: formula(),
          ),
          Text('Noise = -174 + 10 log10(BW Hz) + NF', style: formula()),
          Text('SNR = EIRP - path loss - extra loss - noise', style: formula()),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Limits from 47 CFR 15.407 (US) and ETSI EN 303 687 V1.1.1 (EU). '
            'A real device often runs below its limit.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
