// Controls for the Wi-Fi Classroom Adjacent Channels and AP Stacking tool.
//
//   - AdjacentChannelControls: channels (band, mask, width, separation),
//     radios (who listens, powers, wanted distance, path-loss exponent) and
//     the receiver (illustrative rejection per MCS group, energy-detect
//     threshold, reset). The neighbor distance, the lesson's main control,
//     sits on the stage.
//   - AciQuestionCard: predict, then reveal (spec 29).
//
// Each takes an AdjacentChannelController and none knows about the stage.
//
// PRESENTER: inside a PresenterLayout the controls drop their prose and fold
// the settings set once per lesson behind disclosures, so the panel fits at
// 1920x1080 and 1440x900 without scrolling.
//
// THEME: context.colors (dark §8 / light §8.20). ASCII copy (GL-004).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/adjacent_channel_model.dart';
import '../../../services/wifi_lab/fspl_math.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'adjacent_channel_controller.dart';
import 'rate_vs_range_parts.dart';

/// The spec's wording for every rejection value (spec 29).
const String kAciIllustrativeNote =
    'Illustrative; real receivers vary; no primary per-rate table was read.';

class AdjacentChannelControls extends StatelessWidget {
  const AdjacentChannelControls({super.key, required this.controller});

  final AdjacentChannelController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        if (PresenterMode.isActive(context)) return _presenter(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            RvrCard(child: _channels(context, prose: true)),
            const SizedBox(height: AppSpacing.sm),
            RvrCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const RvrSectionLabel('Radios'),
                  _listener(context),
                  _neighborPower(context),
                  ..._radios(context, prose: true),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            RvrCard(child: _receiver(context, prose: true)),
          ],
        );
      },
    );
  }

  // ── Presenter panel ───────────────────────────────────────────────────────

  Widget _presenter(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _channels(context, prose: false),
        _neighborPower(context),
        _wantedDistance(context),
        PresenterDisclosure(
          title: 'Adjacent-channel rejection (ACR), illustrative',
          children: <Widget>[_rejection(context, prose: false)],
        ),
        PresenterDisclosure(
          title: 'Who listens, wanted power, path loss, CCA',
          children: <Widget>[
            _listener(context),
            _wantedPower(context),
            _exponent(context),
            _cca(context),
            _resetButton(context),
          ],
        ),
        PresenterDisclosure(
          title: 'Opening question',
          children: <Widget>[AciQuestionCard(controller: controller)],
        ),
      ],
    );
  }

  // ── Channels ──────────────────────────────────────────────────────────────

  Widget _channels(BuildContext context, {required bool prose}) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AdjacentChannelController c = controller;
    final AciConfig cfg = c.config;
    final TextStyle small =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (prose) const RvrSectionLabel('Channels'),
        if (prose) const SizedBox(height: AppSpacing.xs),
        AppToggle<WifiBand>(
          label: 'Band',
          value: cfg.band,
          expand: true,
          items: <AppToggleItem<WifiBand>>[
            for (final WifiBand b in WifiBand.values) (b, b.label),
          ],
          onChanged: (WifiBand b) => c.band = b,
        ),
        const SizedBox(height: AppSpacing.xs),
        if (prose) ...<Widget>[
          Text(
            'OFDM is orthogonal frequency-division multiplexing (802.11a/g); '
            'HE/EHT is High Efficiency and Extremely High Throughput '
            '(802.11ax/be).',
            style: small,
          ),
          const SizedBox(height: AppSpacing.xxs),
        ],
        if (c.families.length > 1)
          AppToggle<AciMaskFamily>(
            label: 'Neighbor transmit mask',
            value: cfg.family,
            expand: true,
            items: <AppToggleItem<AciMaskFamily>>[
              for (final AciMaskFamily f in c.families) (f, f.label),
            ],
            onChanged: (AciMaskFamily f) => c.family = f,
          )
        else
          Text(
            'Neighbor transmit mask: ${cfg.family.label}',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        if (c.widths.length > 1) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          AppToggle<int>(
            label: 'Neighbor width (MHz)',
            value: cfg.neighborWidthMHz,
            expand: true,
            items: <AppToggleItem<int>>[
              for (final int w in c.widths) (w, '$w'),
            ],
            onChanged: (int w) => c.neighborWidthMHz = w,
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Channel separation',
          style: text.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        AppSelect<AciSeparation>(
          value: cfg.separation,
          semanticLabel: 'Channel separation',
          items: <AppSelectItem<AciSeparation>>[
            for (final AciSeparation s in c.separations) (s, s.label),
          ],
          onChanged: (AciSeparation s) => c.separation = s,
        ),
        if (prose) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'You listen on one 20 MHz channel. The masks are the transmit '
            'masks, the worst case allowed: real radios run at or below them.'
            '${cfg.band == WifiBand.band24 ? ' The 2.4 GHz pairs come from the 1/6/11 and 1/4/8/11 plans.' : ''}',
            style: small,
          ),
        ],
      ],
    );
  }

  // ── Radios ────────────────────────────────────────────────────────────────

  Widget _listener(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xs),
    child: AppToggle<AciListener>(
      label: 'Who is listening',
      value: controller.config.listener,
      expand: true,
      items: <AppToggleItem<AciListener>>[
        for (final AciListener l in AciListener.values) (l, l.label),
      ],
      onChanged: (AciListener l) => controller.listener = l,
    ),
  );

  Widget _neighborPower(BuildContext context) => _slider(
    context,
    label: 'Neighbor power',
    valueText: '${controller.config.neighborPowerDbm.round()} dBm',
    value: controller.config.neighborPowerDbm,
    min: AciLimits.powerMin,
    max: AciLimits.powerMax,
    divisions: 30,
    onChanged: (double v) => controller.neighborPowerDbm = v,
    semantic: (double v) => 'Neighbor power ${v.round()} dBm',
  );

  Widget _wantedPower(BuildContext context) {
    final String who = controller.config.listener.wantedName;
    return _slider(
      context,
      label: '$who power',
      valueText: '${controller.config.wantedPowerDbm.round()} dBm',
      value: controller.config.wantedPowerDbm,
      min: AciLimits.powerMin,
      max: AciLimits.powerMax,
      divisions: 30,
      onChanged: (double v) => controller.wantedPowerDbm = v,
      semantic: (double v) => '$who power ${v.round()} dBm',
    );
  }

  Widget _wantedDistance(BuildContext context) {
    final double lo = FsplMath.log10(AciLimits.wantedDistanceMin);
    final double hi = FsplMath.log10(AciLimits.wantedDistanceMax);
    final double d = controller.config.wantedDistanceM;
    final String who = controller.config.listener.wantedName;
    return _slider(
      context,
      label: '$who distance',
      valueText: AciFormat.dist(d),
      value: FsplMath.log10(d),
      min: lo,
      max: hi,
      divisions: 120,
      onChanged: (double v) =>
          controller.wantedDistanceM = math.pow(10, v).toDouble(),
      semantic: (double v) =>
          '$who distance ${AciFormat.dist(math.pow(10, v).toDouble())}',
    );
  }

  Widget _exponent(BuildContext context) => _slider(
    context,
    label: 'Path-loss exponent (model)',
    valueText: 'n = ${AciFormat.n(controller.config.pathLossExponent)}',
    value: controller.config.pathLossExponent,
    min: AciLimits.exponentMin,
    max: AciLimits.exponentMax,
    divisions: 20,
    onChanged: (double v) => controller.pathLossExponent = v,
    semantic: (double v) => 'Path-loss exponent ${AciFormat.n(v)}',
  );

  List<Widget> _radios(BuildContext context, {required bool prose}) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return <Widget>[
      _wantedPower(context),
      _wantedDistance(context),
      _exponent(context),
      if (prose)
        Text(
          'Powers include antenna gain. Path loss is free-space loss at 1 m '
          'plus 10 n log10(d); below 1 m it is taken as free space, and at '
          '30 cm the antennas are only a few wavelengths apart, so treat '
          'that as a rough figure.',
          style: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
    ];
  }

  // ── Receiver ──────────────────────────────────────────────────────────────

  Widget _rejection(BuildContext context, {required bool prose}) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          kAciIllustrativeNote,
          style: text.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        for (final AciRateGroup g in AciRateGroup.values)
          _slider(
            context,
            label: '${g.label} (illustrative)',
            valueText:
                '${AciFormat.n(controller.config.rejectionFor(g), 0)} dB',
            value: controller.config.rejectionFor(g),
            min: AciLimits.rejectionMin,
            max: AciLimits.rejectionMax,
            divisions: 50,
            onChanged: (double v) => controller.setRejection(g, v),
            semantic: (double v) =>
                'Rejection at ${g.label} ${v.round()} dB, illustrative',
          ),
        if (prose) ...<Widget>[
          Text(
            'Effective interference = leakage - rejection',
            style: mono.inlineCode.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Higher rates need more signal over the interference, so they '
            'tolerate less: the defaults fall from 16 dB at the lowest rates '
            'to -1 dB at the highest.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ],
    );
  }

  Widget _cca(BuildContext context) => _slider(
    context,
    label: 'CCA energy-detect threshold',
    valueText: '${controller.config.ccaThresholdDbm.round()} dBm',
    value: controller.config.ccaThresholdDbm,
    min: AciLimits.ccaMin,
    max: AciLimits.ccaMax,
    divisions: 30,
    onChanged: (double v) => controller.ccaThresholdDbm = v,
    semantic: (double v) => 'CCA energy-detect threshold ${v.round()} dBm',
  );

  Widget _resetButton(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: controller.reset,
        icon: const Icon(Icons.restart_alt),
        label: const Text('Reset to defaults'),
        style: TextButton.styleFrom(
          foregroundColor: colors.textAccent,
          minimumSize: const Size(0, AppSpacing.minTouchTarget),
        ),
      ),
    );
  }

  Widget _receiver(BuildContext context, {required bool prose}) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const RvrSectionLabel('Receiver'),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Adjacent-channel rejection (ACR): how much of the neighbor this '
          'receiver copes with, per MCS group.',
          style: text.bodyMedium?.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        _rejection(context, prose: prose),
        const SizedBox(height: AppSpacing.sm),
        _cca(context),
        if (prose)
          Text(
            'Energy detect: the radio calls the air busy when this much '
            'energy sits in its 20 MHz, whatever sent it. The usual value is '
            '-62 dBm.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        const SizedBox(height: AppSpacing.xs),
        _resetButton(context),
      ],
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

// ── Predict, then reveal ────────────────────────────────────────────────────

/// The opening question (spec 29): two APs on 36 and 44, 30 cm apart.
const String kAciQuestion =
    'Two APs on channels 36 and 44, 30 cm apart on the same ceiling. Any '
    'problem?';

class AciQuestionCard extends StatelessWidget {
  const AciQuestionCard({super.key, required this.controller});

  final AdjacentChannelController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AdjacentChannelController c = controller;
    final AciPrediction? p = c.prediction;

    Widget choice(AciPrediction v, String label) => Expanded(
      child: Semantics(
        selected: p == v,
        child: OutlinedButton(
          onPressed: () => c.prediction = v,
          style: OutlinedButton.styleFrom(
            foregroundColor: p == v ? colors.onPrimary : colors.textAccent,
            backgroundColor: p == v ? colors.primary : null,
            side: BorderSide(
              color: p == v ? colors.primary : colors.borderStrong,
              width: colors.isLight ? 1.5 : 1,
            ),
            minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
          ),
          child: Text(label, textAlign: TextAlign.center),
        ),
      ),
    );

    return RvrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const RvrSectionLabel('Predict, then reveal'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            kAciQuestion,
            style: text.bodyLarge?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              choice(AciPrediction.problem, 'Yes, a problem'),
              const SizedBox(width: AppSpacing.xs),
              choice(AciPrediction.noProblem, 'No, they do not overlap'),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (!c.revealed)
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Reveal loads that scene into the tool.',
                    style: text.bodySmall?.copyWith(color: colors.textTertiary),
                  ),
                ),
                TextButton(
                  onPressed: c.reveal,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textAccent,
                    minimumSize: const Size(0, AppSpacing.minTouchTarget),
                  ),
                  child: const Text('Reveal'),
                ),
              ],
            )
          else
            _answer(context, p),
        ],
      ),
    );
  }

  Widget _answer(BuildContext context, AciPrediction? p) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    // Always the question's own scene, whatever the student changes after.
    final AciResult r = aciQuestionResult;
    final TextStyle body =
        text.bodyMedium?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            p == AciPrediction.problem
                ? 'Right: they do not overlap, and it still hurts.'
                : p == AciPrediction.noProblem
                ? 'They do not overlap on paper, and it still hurts.'
                : 'Yes: they do not overlap, and it still hurts.',
            style: text.bodyLarge?.copyWith(
              color: colors.textAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Channel 36 does not stop at its edge. At 30 cm its leakage into '
            'channel 44 is ${AciFormat.dbm(r.leakageDbm)}, '
            '${r.ccaBusy ? 'above' : 'below'} the '
            '${r.config.ccaThresholdDbm.round()} dBm energy-detect '
            'threshold${r.ccaBusy ? ', so the AP on 44 hears the air as busy and waits, as if the two shared a channel' : ''}.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Its own client, ${AciFormat.dist(r.config.wantedDistanceM)} '
            'away, arrives at ${AciFormat.dbm(r.wantedDbm)}. Alone, the best '
            'modulation and coding scheme (MCS) it supports is '
            '${r.mcsWithout == null ? 'below MCS 0' : '${r.mcsWithout}'}; with '
            'the neighbor it drops to ${AciFormat.mcs(r.mcsWith)}.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Move the neighbor away with the Neighbor distance slider and '
            'watch the leakage fall. A second empty channel buys nothing '
            'more here: past 30 MHz from its center a 20 MHz mask stays flat '
            'at -40 dB below its in-channel level, so distance is what helps. '
            'The mask is a ceiling, so this is the worst case the rule '
            'allows.',
            style: body,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: controller.askAgain,
              style: TextButton.styleFrom(
                foregroundColor: colors.textAccent,
                minimumSize: const Size(0, AppSpacing.minTouchTarget),
              ),
              child: const Text('Ask again'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The opening question's scene, computed once.
final AciResult aciQuestionResult = computeAci(kAciQuestionScene);
