// Controls, readouts and explainer for the Wi-Fi Classroom Rate vs Range tool.
//
// Everything that is not the ring view: band, width, spatial streams, the
// link (AP EIRP, client antenna gain, path-loss exponent, margin) and the
// beacon settings (minimum basic rate, SSID count) in RateVsRangeControls;
// what the client reads in RateVsRangeReadouts; and the four lessons with
// the formulas in RateVsRangeExplainer. Each takes a RateVsRangeModel and
// none knows about RateVsRangeStage, so a screen composes them in whatever
// arrangement it needs.
//
// PRESENTER: RateVsRangeControls drops its explanatory prose inside a
// PresenterLayout (the instructor says it), so every input fits the panel;
// what the client reads moves onto the stage.
//
// THEME: context.colors (dark §8 / light §8.20), MCS hues from RvrPalette
// (§8.15.2) on the swatches only. No status hues: an MCS is a description,
// not a pass/fail verdict (§8.13 rule 6). ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/rate_vs_range_math.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'rate_vs_range_model.dart';
import 'rate_vs_range_parts.dart';

// ── Controls ──────────────────────────────────────────────────────────────

class RateVsRangeControls extends StatelessWidget {
  const RateVsRangeControls({super.key, required this.model});
  final RateVsRangeModel model;

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
    final RateVsRangeModel m = model;
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);
    final String Function(double, [int]) n = RvrFormat.n;
    // Presenter: phone prose goes; every control stays.
    final bool prose = !PresenterMode.isActive(context);
    final Widget clientGain = _slider(
      context,
      label: 'Client antenna gain',
      valueText: '${n(m.clientGainDbi, 0)} dBi',
      value: m.clientGainDbi,
      min: RateVsRangeModel.gainMin,
      max: RateVsRangeModel.gainMax,
      divisions: 11,
      onChanged: m.setClientGain,
      semantic: (double v) => 'Client antenna gain ${v.round()} dBi',
    );
    final Widget margin = _slider(
      context,
      label: 'Margin',
      valueText: '${n(m.marginDb, 0)} dB',
      value: m.marginDb,
      min: 0,
      max: RateVsRangeModel.marginMax,
      divisions: 20,
      onChanged: m.setMargin,
      semantic: (double v) => 'Margin ${v.round()} dB',
    );

    return <Widget>[
      AppToggle<WifiBand>(
        label: 'Band',
        value: m.band,
        expand: true,
        items: <AppToggleItem<WifiBand>>[
          for (final WifiBand b in WifiBand.values) (b, b.label),
        ],
        onChanged: m.setBand,
      ),
      const SizedBox(height: AppSpacing.sm),
      AppToggle<int>(
        label: 'Channel width (MHz)',
        value: m.widthMHz,
        expand: true,
        items: <AppToggleItem<int>>[
          for (final int w in m.bandWidths) (w, '$w'),
        ],
        onChanged: m.setWidth,
      ),
      const SizedBox(height: AppSpacing.sm),
      AppToggle<int>(
        label: 'Spatial streams (rate labels only)',
        value: m.streams,
        expand: true,
        items: <AppToggleItem<int>>[
          for (int s = 1; s <= RateVsRangeModel.streamsMax; s++) (s, '$s'),
        ],
        onChanged: m.setStreams,
      ),
      if (prose) const SizedBox(height: AppSpacing.xs),
      if (prose)
        Text(
          'Path loss is taken at ${m.band.label} channel ${m.channel} '
          '(${m.freqMHz.round()} MHz). Rates are 802.11be (Wi-Fi 7) with an '
          '800 ns guard interval, from the MCS Index tool; MCS 0 to 11 match '
          '802.11ax.',
          style: small(),
        ),
      SizedBox(height: prose ? AppSpacing.md : AppSpacing.sm),
      const RvrSectionLabel('Link'),
      _slider(
        context,
        label: 'AP EIRP',
        valueText: '${n(m.eirpDbm, 0)} dBm',
        value: m.eirpDbm,
        min: RateVsRangeModel.eirpMin,
        max: RateVsRangeModel.eirpMax,
        divisions: 36,
        onChanged: m.setEirp,
        semantic: (double v) => 'AP EIRP ${v.round()} dBm',
      ),
      if (prose) clientGain,
      _slider(
        context,
        label: 'Path-loss exponent (model)',
        valueText: 'n = ${n(m.exponent)}',
        value: m.exponent,
        min: RateVsRangeModel.exponentMin,
        max: RateVsRangeModel.exponentMax,
        divisions: 20,
        onChanged: m.setExponent,
        semantic: (double v) => 'Path-loss exponent ${n(v)}',
      ),
      if (prose)
        Text(
          'n = 2 is free space. Indoors is usually 3 to 4. This is a model '
          'with a chosen exponent, not a measurement.',
          style: small(),
        ),
      if (prose)
        margin
      else
        // Set once per lesson: folded so the panel fits a projector.
        PresenterDisclosure(
          title: 'Client antenna gain and margin',
          children: <Widget>[clientGain, margin],
        ),
      SizedBox(height: prose ? AppSpacing.md : AppSpacing.sm),
      const RvrSectionLabel('Beacons'),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Minimum basic rate',
        style: text.bodyMedium?.copyWith(color: colors.textSecondary),
      ),
      const SizedBox(height: AppSpacing.xxs),
      AppSelect<RvrBasicRate>(
        value: m.basicRate,
        semanticLabel: 'Minimum basic rate',
        maxLines: 2,
        items: <AppSelectItem<RvrBasicRate>>[
          for (final RvrBasicRate r in RvrBasicRate.values)
            (r, basicRateLabel(r)),
        ],
        onChanged: m.setBasicRate,
      ),
      _slider(
        context,
        label: 'SSIDs on this AP',
        valueText: '${m.ssids}',
        value: m.ssids.toDouble(),
        min: RateVsRangeModel.ssidMin.toDouble(),
        max: RateVsRangeModel.ssidMax.toDouble(),
        divisions: RateVsRangeModel.ssidMax - RateVsRangeModel.ssidMin,
        onChanged: (double v) => m.setSsids(v.round()),
        semantic: (double v) => '${v.round()} SSIDs',
      ),
      if (prose)
        Text(
          'Only 6 Mbps has a published floor of its own (-82 dBm, equal to '
          'MCS 0). 12 to 54 Mbps use the floor of the MCS with the same '
          'modulation and coding, so they are MCS-equivalent. 9 Mbps and the '
          '2.4 GHz DSSS rates (1, 2, 5.5, 11) have no sourced floor here and '
          'are not offered.',
          style: small(),
        ),
    ];
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
                  style: text.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ),
              Text(
                valueText,
                style: mono.inlineCode.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          activeColor: colors.primary,
          inactiveColor: colors.disabledFill,
          label: valueText,
          semanticFormatterCallback: semantic,
        ),
      ],
    );
  }
}

/// Select label for a basic rate: 6 Mbps names its own floor; the rest say
/// they are MCS-equivalent.
String basicRateLabel(RvrBasicRate r) {
  final String floor = RvrFormat.n(
    RateVsRangeMath.basicRateSensitivityDbm(r),
    0,
  );
  return r.isSourcedDirectly
      ? '${r.label} ($floor dBm)'
      : '${r.label} (MCS-equivalent: MCS ${r.equivalentMcs}, $floor dBm)';
}

// ── Readouts ──────────────────────────────────────────────────────────────

/// What the client dot reads: received power, noise floor, SNR, MCS and rate,
/// and whether it can still hear beacons.
class RateVsRangeReadouts extends StatelessWidget {
  const RateVsRangeReadouts({super.key, required this.model});
  final RateVsRangeModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final String Function(double, [int]) n = RvrFormat.n;
    final RvrClientReading c = model.client;

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

    final String mcsLine = c.mcs == null
        ? 'Below MCS 0 at ${model.widthMHz} MHz: the signal is under the '
              '${n(RateVsRangeMath.sensitivityDbm(0, model.widthMHz), 0)} dBm '
              'floor${model.marginDb > 0 ? ' plus the ${n(model.marginDb, 0)} dB margin' : ''}.'
        : '${model.mcsLabel(c.mcs!)}: needs '
              '${n(RateVsRangeMath.sensitivityDbm(c.mcs!, model.widthMHz), 0)} dBm '
              'at ${model.widthMHz} MHz'
              '${model.marginDb > 0 ? ' + ${n(model.marginDb, 0)} dB margin' : ''}.';
    final String cellLine = c.insideCell
        ? 'Inside the cell: it can decode ${model.basicRate.label} beacons.'
        : 'Outside the cell: too weak for ${model.basicRate.label} beacons, '
              'so it will not associate here.';

    return RvrCard(
      child: Semantics(
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            RvrSectionLabel('Client at ${RvrFormat.dist(c.distanceM)}'),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                value('Received', '${n(c.receivedDbm)} dBm', strong: true),
                value(
                  'MCS and rate',
                  c.mcs == null
                      ? 'below MCS 0'
                      : 'MCS ${c.mcs}, ${RvrFormat.rate(c.rateMbps)}',
                  strong: true,
                ),
                value('Noise floor', '${n(c.noiseFloorDbm)} dBm'),
                value('SNR', '${n(c.snrDb)} dB'),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              mcsLine,
              style: text.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              cellLine,
              style: text.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              'Noise floor = -174 dBm/Hz + '
              '${n(RateVsRangeMath.thermalNoiseDbm(model.widthMHz) + 174)} dB '
              'for ${model.widthMHz} MHz + ${n(model.noiseFigureDb, 0)} dB '
              'noise figure.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.sm),
            const RvrNote(
              Icons.info_outline,
              'These sensitivities are conformance floors, the least a '
              'radio must manage to pass. Real radios do several dB better, '
              'so real rings are larger.',
            ),
          ],
        ),
      ),
    );
  }
}

// ── Explainer ─────────────────────────────────────────────────────────────

class RateVsRangeExplainer extends StatelessWidget {
  const RateVsRangeExplainer({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    TextStyle body() => text.bodyMedium!.copyWith(color: colors.textPrimary);
    TextStyle formula() =>
        mono.inlineCode.copyWith(color: colors.textSecondary);
    return RvrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const RvrSectionLabel('What the rings say'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '1. Rate falls with distance in steps. Each MCS needs a minimum '
            'signal, so coverage is a set of rings, fastest in the middle.',
            style: body(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '2. Doubling the channel width raises the noise floor 3 dB, so '
            'every MCS needs 3 dB more signal and every ring shrinks.',
            style: body(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '3. Raising the minimum basic rate shrinks the cell edge and cuts '
            'beacon airtime. 6 to 24 Mbps moves the edge from -82 to -74 dBm '
            'and makes each beacon about 3.6 times shorter: the data part is '
            '4 times shorter, the 20 us preamble is not.',
            style: body(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '4. The sensitivities are conformance floors. Real radios beat '
            'them by several dB.',
            style: body(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Received = EIRP + client gain - FSPL(1 m) - 10 n log10(d)',
            style: formula(),
          ),
          Text(
            'Ring radius d = 10^((EIRP + G - FSPL(1 m) - sensitivity - '
            'margin) / 10n)',
            style: formula(),
          ),
          Text('Noise = -174 + 10 log10(BW Hz) + NF', style: formula()),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Sensitivities: minimum receiver sensitivity at 10% packet error, '
            '4096-byte frames, MCS 0 to 13 and 20 to 320 MHz, +3 dB per '
            'doubling of width. Beacon airtime from the SSID Airtime tool '
            '(802.11ax beacon size, one AP, no MBSSID). The width is held '
            'fixed: a real AP may drop to a narrower transmission for a far '
            'client.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
