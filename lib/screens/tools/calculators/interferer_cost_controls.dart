// Controls for the Wi-Fi Classroom tool What an Interferer Costs.
//
//   - InterfererCostControls: the source, your channel and width, the oven's
//     mains frequency, the neighbor's airtime, the path-loss exponent for the
//     distances, reset. The source's level, the lesson's main control, sits
//     on the stage.
//   - IcQuestionCard: predict, then reveal.
//
// Each takes an InterfererCostController and none knows about the stage.
//
// PRESENTER: inside a PresenterLayout the controls drop their prose and fold
// the settings set once per lesson behind disclosures, so the panel fits at
// 1920x1080 and 1440x900 without scrolling.
//
// THEME: context.colors (dark §8 / light §8.20). ASCII copy (GL-004).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/interferer_cost_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'interferer_cost_controller.dart';
import 'rate_vs_range_parts.dart';

/// One line on each source, for the controls.
String icSourceNote(IcSource s) => switch (s) {
  IcSource.wifiNeighbor =>
    'Another network on your channel. Your radio can decode its preamble, so '
        'it waits for it down to preamble detect. Its airtime is '
        'illustrative.',
  IcSource.microwave =>
    'On for about half of every mains cycle, strongest around 2.45 to 2.47 '
        'GHz, which is channels 9 to 11. Channel 1 is largely spared.',
  IcSource.bluetooth =>
    'Hops 1,600 times a second across 79 channels of 1 MHz; about 20 of '
        'them fall inside a 20 MHz channel. How often it sends is '
        'illustrative.',
  IcSource.videoSender =>
    'An analog sender that never stops. Under energy detect nobody waits '
        'for it, and it ruins frames anyway.',
};

class InterfererCostControls extends StatelessWidget {
  const InterfererCostControls({super.key, required this.controller});

  final InterfererCostController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        if (PresenterMode.isActive(context)) return _presenter(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            RvrCard(child: _source(context, prose: true)),
            const SizedBox(height: AppSpacing.sm),
            RvrCard(child: _channel(context, prose: true)),
            const SizedBox(height: AppSpacing.sm),
            RvrCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const RvrSectionLabel('Settings'),
                  _airtime(context),
                  _exponent(context, prose: true),
                  const SizedBox(height: AppSpacing.xs),
                  _resetButton(context),
                ],
              ),
            ),
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
        _source(context, prose: false),
        const SizedBox(height: AppSpacing.xs),
        _channel(context, prose: false),
        PresenterDisclosure(
          title: 'Neighbor airtime, path loss, reset',
          children: <Widget>[
            _airtime(context),
            _exponent(context, prose: false),
            _resetButton(context),
          ],
        ),
        PresenterDisclosure(
          title: 'Opening question',
          children: <Widget>[IcQuestionCard(controller: controller)],
        ),
      ],
    );
  }

  // ── Source ────────────────────────────────────────────────────────────────

  Widget _source(BuildContext context, {required bool prose}) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final IcConfig cfg = controller.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (prose) const RvrSectionLabel('Interferer'),
        if (prose) const SizedBox(height: AppSpacing.xs),
        // Four segments truncate on a phone; a menu there, with full names.
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            if (box.maxWidth >= 440) {
              return AppToggle<IcSource>(
                label: 'Source',
                value: cfg.source,
                expand: true,
                items: <AppToggleItem<IcSource>>[
                  for (final IcSource s in IcSource.values) (s, s.short),
                ],
                onChanged: (IcSource s) => controller.source = s,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Source',
                  style: text.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xxs),
                AppSelect<IcSource>(
                  value: cfg.source,
                  semanticLabel: 'Source',
                  items: <AppSelectItem<IcSource>>[
                    for (final IcSource s in IcSource.values) (s, s.label),
                  ],
                  onChanged: (IcSource s) => controller.source = s,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          icSourceNote(cfg.source),
          style: text.bodySmall?.copyWith(
            color: prose ? colors.textSecondary : colors.textTertiary,
          ),
        ),
        if (cfg.source == IcSource.microwave) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          AppToggle<IcMains>(
            label: 'Mains power',
            value: cfg.mains,
            expand: true,
            items: <AppToggleItem<IcMains>>[
              for (final IcMains m in IcMains.values) (m, m.label),
            ],
            onChanged: (IcMains m) => controller.mains = m,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'ON ${IcFormat.n(icMicrowaveOnMs(cfg.mains), 1)} ms of every '
            '${IcFormat.n(icMicrowavePeriodMs(cfg.mains), 2)} ms cycle.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ],
    );
  }

  // ── Your channel ──────────────────────────────────────────────────────────

  Widget _channel(BuildContext context, {required bool prose}) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final IcConfig cfg = controller.config;
    final double? off = icMicrowaveOffsetDb(cfg.channel);
    final String ovenNote = off == null
        ? 'No oven and no Bluetooth on 5 GHz.'
        : off == 0
        ? 'The oven\'s peak lands in this channel.'
        : 'The oven is ${off.round()} dB weaker here than at its peak '
              '(illustrative).';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (prose) const RvrSectionLabel('Your channel'),
        if (prose) const SizedBox(height: AppSpacing.xs),
        AppToggle<IcChannel>(
          label: 'Your AP\'s channel',
          value: cfg.channel,
          expand: true,
          items: <AppToggleItem<IcChannel>>[
            for (final IcChannel c in IcChannel.values) (c, c.label),
          ],
          onChanged: (IcChannel c) => controller.channel = c,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          ovenNote,
          style: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
        if (controller.widths.length > 1) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          AppToggle<int>(
            label: 'Channel width (MHz)',
            value: cfg.widthMHz,
            expand: true,
            items: <AppToggleItem<int>>[
              for (final int w in controller.widths) (w, '$w'),
            ],
            onChanged: (int w) => controller.widthMHz = w,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Preamble detect for a ${cfg.widthMHz} MHz PPDU (physical layer '
            'protocol data unit): ${IcFormat.dbm(controller.result.preambleDetectDbm)}. '
            'This widening applies to 5 GHz: the gap narrows 3 dB each '
            'time the width doubles. Past 20 MHz the values come from one '
            'source. 6 GHz works differently and is not modeled here.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ] else if (prose) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Wider channels are a 5 GHz setting here; 2.4 GHz stays at 20 '
            'MHz.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ],
    );
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  Widget _airtime(BuildContext context) {
    final double a = controller.config.neighborAirtime;
    return _slider(
      context,
      label: 'Neighbor airtime (illustrative)',
      valueText: '${(a * 100).round()}%',
      value: a,
      min: kIcNeighborAirtimeMin,
      max: kIcNeighborAirtimeMax,
      divisions: 14,
      onChanged: (double v) => controller.neighborAirtime = v,
      semantic: (double v) =>
          'Neighbor airtime ${(v * 100).round()} percent, illustrative',
    );
  }

  Widget _exponent(BuildContext context, {required bool prose}) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: AppSpacing.xs),
        AppToggle<double>(
          label: 'Path-loss exponent, for the distances',
          value: controller.config.exponent,
          expand: true,
          items: const <AppToggleItem<double>>[
            (2.0, '2.0 free'),
            (3.0, '3.0 indoor'),
            (3.5, '3.5 walls'),
          ],
          onChanged: (double n) => controller.exponent = n,
        ),
        if (prose) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '2.0 is free space; 3.0 typical indoors; 3.5 dense walls. The '
            'exponent changes only the distances, never the thresholds.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ],
    );
  }

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

/// The opening question, Keith's words (2026-09-27 brief).
const String kIcQuestion =
    'A microwave oven and a neighbor\'s AP on your channel, both at the same '
    'received level of -70 dBm. Which one costs your Wi-Fi more airtime?';

class IcQuestionCard extends StatelessWidget {
  const IcQuestionCard({super.key, required this.controller});

  final InterfererCostController controller;

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
    final InterfererCostController c = controller;
    final IcPrediction? p = c.prediction;

    Widget choice(IcPrediction v, String label) => Expanded(
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
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
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
            kIcQuestion,
            style: text.bodyLarge?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              choice(IcPrediction.microwave, 'The oven'),
              const SizedBox(width: AppSpacing.xs),
              choice(IcPrediction.neighbor, 'The neighbor\'s AP'),
              const SizedBox(width: AppSpacing.xs),
              choice(IcPrediction.same, 'The same'),
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

  Widget _answer(BuildContext context, IcPrediction? p) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    // Always the question's own scene, whatever the student changes after.
    final IcResult r = icQuestionResult;
    final IcSourceResult n = r.sources[IcSource.wifiNeighbor]!;
    final IcSourceResult m = r.sources[IcSource.microwave]!;
    final TextStyle body =
        text.bodyMedium?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            p == IcPrediction.neighbor
                ? 'Right: the neighbor\'s AP.'
                : 'The neighbor\'s AP, by a wide margin.',
            style: text.bodyLarge?.copyWith(
              color: colors.textAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'At -70 dBm the neighbor is ${n.marginDb!.round()} dB above the '
            '-82 dBm preamble-detect threshold, so your radio waits every '
            'time it transmits: ${IcFormat.pct(n.deferralShare)} of your '
            'airtime, its whole (illustrative) share.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'The oven at -70 dBm is ${(-m.marginDb!).round()} dB below the '
            '-62 dBm energy-detect threshold, so your radio never waits for '
            'it. It sends straight through the oven\'s ON half, and at that '
            'level almost every frame survives: '
            '${IcFormat.pct(m.corruptionShare)} lost (illustrative).',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Your radio holds off for Wi-Fi it can decode at a level 100 '
            'times weaker than it needs from anything else. Try the video '
            'sender at -70 next: it is the case where non-Wi-Fi energy does '
            'real harm.',
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
final IcResult icQuestionResult = computeInterfererCost(kIcQuestionScene);
