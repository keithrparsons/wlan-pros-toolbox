// The controls for Multicast at the Basic Rate (Wi-Fi Classroom): readouts,
// the predict-then-reveal question, the stream, the channel and basic rate,
// which lanes to show, the listeners, and DTIM power save. Reads and writes a
// [MulticastBasicRateController]; owns no state, so a presenter layout can
// place it beside [MulticastBasicRateStage].
//
// ILLUSTRATIVE VALUES (spec 30). The stream presets, the default bit rate
// (4 Mb/s), the default packet size (1,316 bytes), the listeners' rate
// spread and the unicast radio settings are illustrative, and each is
// labeled so where it is set.
//
// States (SOP-007 §5):
//   - fresh       -> 4 Mb/s video, 5 GHz, basic rate 6 Mb/s, five listeners
//                    spread across the MCS range, compare both lanes
//   - empty       -> not reachable: the stream is never below 0.064 Mb/s
//                    and there is always at least one listener
//   - error       -> a stream that needs more than the whole channel: the
//                    busy bar's "Does not fit" verdict, in danger with an
//                    icon and words, on the stage
//   - disabled    -> Reveal before the question is asked is not shown; the
//                    DTIM period stays live with power save off, with a note
//                    that it only matters when a client dozes
//   - loading     -> not reachable: the model is synchronous and pure
//   - interactive -> themed Material controls with the global focus ring
//
// PRESENTER (PresenterMode.isActive): the headline numbers are on the stage;
// the readouts table folds into a PresenterDisclosure, and short inputs pair
// up two per row, so the panel fits at 1440x900 with no scroll.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/multicast_basic_rate_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../labeled_field.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'multicast_basic_rate_controller.dart';
import 'multicast_basic_rate_stage.dart' show mcMs, mcPct, mcUs;

/// The question, word for word (spec 30).
const String kMcQuestionText =
    'A 4 Mb/s video stream on a Wi-Fi 6 AP. How much of the channel does it '
    'use?';

class MulticastBasicRateControls extends StatelessWidget {
  const MulticastBasicRateControls({super.key, required this.controller});

  final MulticastBasicRateController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final bool presenting = PresenterMode.isActive(context);
        final SizedBox gap = SizedBox(
          height: presenting ? AppSpacing.xs : AppSpacing.sm,
        );
        if (presenting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Predict(controller: controller, compact: true),
              gap,
              _Inputs(controller: controller, compact: true),
              PresenterDisclosure(
                title: 'All readouts',
                children: <Widget>[_Readouts(controller: controller)],
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Readouts(controller: controller),
            gap,
            _Predict(controller: controller, compact: false),
            gap,
            _Inputs(controller: controller, compact: false),
          ],
        );
      },
    );
  }
}

// ── Readouts ────────────────────────────────────────────────────────────────

class _Readouts extends StatelessWidget {
  const _Readouts({required this.controller});

  final MulticastBasicRateController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final McResult r = controller.result;
    final McConfig c = r.config;
    final bool masked = controller.masked;
    final TextStyle label =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final TextStyle value = mono.inlineCode.copyWith(color: colors.textPrimary);

    TableRow row(String name, String v, {bool accent = false}) => TableRow(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Text(name, style: label),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Text(
            v,
            textAlign: TextAlign.end,
            style: accent ? value.copyWith(color: colors.textAccent) : value,
          ),
        ),
      ],
    );

    final String breakEven = r.breakEven == null
        ? 'over $kMcMaxListeners'
        : '${r.breakEven} listener${r.breakEven == 1 ? '' : 's'}';

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('Readouts'),
          const SizedBox(height: AppSpacing.xs),
          Table(
            columnWidths: const <int, TableColumnWidth>{
              0: FlexColumnWidth(1.6),
              1: FlexColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: <TableRow>[
              row('Packets per second', r.packetsPerSecond.toStringAsFixed(1)),
              row('Multicast, per packet', mcUs(r.multicast.totalUs)),
              row(
                'Unicast copies, per packet',
                mcUs(r.unicastPerPacketTenths / 10),
              ),
              row(
                'Multicast airtime share',
                masked ? '?' : mcPct(r.multicastShare),
                accent: true,
              ),
              row(
                'Unicast airtime share',
                masked ? '?' : mcPct(r.unicastShare),
                accent: true,
              ),
              row('Break-even listener count', breakEven),
              row(
                'Added DTIM delay',
                c.powerSave
                    ? 'up to ${mcMs(r.maxDtimDelayUs)}'
                    : 'none (nobody dozing)',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            r.breakEven == null
                ? 'Unicast copies stay cheaper than one multicast frame all '
                      'the way to $kMcMaxListeners listeners at this basic '
                      'rate.'
                : r.breakEven == 1
                ? 'Even one unicast copy takes as long as the multicast '
                      'frame here: converting only adds airtime.'
                : 'Below ${r.breakEven} listeners, converting to unicast '
                      'uses less airtime than multicast; from '
                      '${r.breakEven} up it uses more.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ── Predict, then reveal ────────────────────────────────────────────────────

class _Predict extends StatelessWidget {
  const _Predict({required this.controller, required this.compact});

  final MulticastBasicRateController controller;

  /// The presenter arrangement: the stage carries the numbers, so the notes
  /// that repeat them are left out.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final McQuestion q = controller.question;
    final TextStyle body =
        text.bodyMedium?.copyWith(color: colors.textPrimary) ??
        TextStyle(color: colors.textPrimary);
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);

    final List<Widget> children = <Widget>[
      if (compact && q == McQuestion.asking)
        Row(
          children: <Widget>[
            const Expanded(child: AirtimeSectionTitle('Predict, then reveal')),
            FilledButton.icon(
              onPressed: controller.reveal,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Reveal'),
            ),
          ],
        )
      else if (compact && q == McQuestion.revealed)
        Row(
          children: <Widget>[
            const Expanded(child: AirtimeSectionTitle('Predict, then reveal')),
            IconButton(
              onPressed: controller.dismissQuestion,
              tooltip: 'Close the question',
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        )
      else
        const AirtimeSectionTitle('Predict, then reveal'),
      const SizedBox(height: AppSpacing.xxs),
      Text(kMcQuestionText, style: body),
    ];

    switch (q) {
      case McQuestion.idle:
        children.addAll(<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: controller.ask,
              icon: const Icon(Icons.help_outline_rounded),
              label: const Text('Ask the class'),
            ),
          ),
          if (!compact) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Loads the question\'s settings (5 GHz, basic rate 6 Mb/s) and '
              'hides the airtime answers until you reveal them.',
              style: note,
            ),
          ],
        ]);
      case McQuestion.asking:
        children.addAll(<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final McGuess g in McGuess.values)
                McChoiceButton(
                  label: g.label,
                  selected: controller.guess == g,
                  onPressed: () => controller.guess = g,
                  dense: compact,
                ),
            ],
          ),
          if (!compact) const SizedBox(height: AppSpacing.xs),
          if (!compact)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: controller.reveal,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Reveal'),
              ),
            ),
        ]);
      case McQuestion.revealed:
        final McResult r = controller.result;
        final McConfig c = r.config;
        final McGuess? g = controller.guess;
        final double share = r.multicastShare;
        final McResult fast = computeMulticast(
          c.copyWith(basicRate: BasicRate.r24),
        );
        children.addAll(<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'At a ${c.basicRate.label} basic rate it uses ${mcPct(share)} of '
            'the channel.',
            style: body.copyWith(fontWeight: FontWeight.w600),
          ),
          if (g != null)
            Text(
              g.contains(share)
                  ? 'The class picked ${g.label}: right.'
                  : 'The class picked ${g.label}. The answer is in '
                        '${McGuess.values.firstWhere((McGuess x) => x.contains(share)).label}.',
              style: body,
            ),
          if (!compact) const SizedBox(height: AppSpacing.xxs),
          if (!compact)
            Text(
              'Why: every client must decode it, so it goes at a low basic '
              'rate with no acknowledgment. At 24 Mb/s the same stream would '
              'use ${mcPct(fast.multicastShare)}; converted to unicast for '
              '${c.listeners} listeners, ${mcPct(r.unicastShare)}.',
              style: note,
            ),
          if (!compact) const SizedBox(height: AppSpacing.xs),
          if (!compact)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: controller.dismissQuestion,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppSpacing.minTouchTarget),
                ),
                child: const Text('Done'),
              ),
            ),
        ]);
    }

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

// ── Inputs ──────────────────────────────────────────────────────────────────

class _Inputs extends StatelessWidget {
  const _Inputs({required this.controller, required this.compact});

  final MulticastBasicRateController controller;

  /// The presenter arrangement: pairs, no hints.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final MulticastBasicRateController m = controller;
    final McConfig c = m.config;
    final McResult r = m.result;
    final SizedBox gap = SizedBox(
      height: compact ? AppSpacing.xs : AppSpacing.sm,
    );
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);

    Widget pair(Widget a, Widget b) => compact
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: a),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: b),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[a, gap, b],
          );

    int rateIndex = kMcStreamRatesMbps.indexOf(c.streamMbps);
    if (rateIndex < 0) rateIndex = kMcStreamRatesMbps.indexOf(4);

    final Widget presets = Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        for (final StreamPreset p in StreamPreset.values)
          McChoiceButton(
            label: p.label,
            selected: m.preset == p,
            onPressed: () => m.applyPreset(p),
          ),
      ],
    );

    final Widget rate = McSlider(
      label: 'Stream bit rate (illustrative)',
      valueText: compact
          ? '${fmtMbps(c.streamMbps)} Mb/s'
          : '${fmtMbps(c.streamMbps)} Mb/s, '
                '${r.packetsPerSecond.toStringAsFixed(r.packetsPerSecond < 100 ? 1 : 0)} '
                'packets/s',
      value: rateIndex.toDouble(),
      min: 0,
      max: (kMcStreamRatesMbps.length - 1).toDouble(),
      divisions: kMcStreamRatesMbps.length - 1,
      onChanged: (double v) => m.streamMbps = kMcStreamRatesMbps[v.round()],
      semanticValue: (double v) =>
          '${fmtMbps(kMcStreamRatesMbps[v.round()])} megabits per second',
    );

    final Widget packet = _select<int>(
      label: 'Packet size (illustrative)',
      value: c.packetBytes,
      items: <AppSelectItem<int>>[
        for (final int b in kMcPacketSizes) (b, '${_thousands(b)} bytes'),
      ],
      onChanged: (int b) => m.packetBytes = b,
    );

    final Widget band = AppToggle<McBand>(
      label: 'Band',
      semanticLabel: 'Band',
      value: c.band,
      expand: true,
      items: <AppToggleItem<McBand>>[
        for (final McBand b in McBand.values) (b, b.label),
      ],
      onChanged: (McBand b) => m.band = b,
    );

    final Widget basic = _select<BasicRate>(
      label: 'Basic rate',
      value: c.basicRate,
      items: <AppSelectItem<BasicRate>>[
        for (final BasicRate b in BasicRate.on(c.band))
          (b, '${b.label} (${b.phyLabel})'),
      ],
      onChanged: (BasicRate b) => m.basicRate = b,
    );

    final Widget viewSelect = _select<McView>(
      label: 'Show',
      value: m.view,
      items: <AppSelectItem<McView>>[
        for (final McView v in McView.values) (v, v.label),
      ],
      onChanged: (McView v) => m.view = v,
    );

    final Widget view = AppToggle<McView>(
      label: compact ? null : 'Show',
      semanticLabel: 'Show',
      value: m.view,
      expand: true,
      items: <AppToggleItem<McView>>[
        (McView.multicast, 'Multicast'),
        (McView.unicast, 'Unicast'),
        (McView.compare, 'Both'),
      ],
      onChanged: (McView v) => m.view = v,
    );

    final Widget listeners = McSlider(
      label: 'Listening clients',
      valueText: '${c.listeners}',
      value: c.listeners.toDouble(),
      min: kMcMinListeners.toDouble(),
      max: kMcMaxListeners.toDouble(),
      divisions: kMcMaxListeners - kMcMinListeners,
      onChanged: (double v) => m.listeners = v.round(),
      semanticValue: (double v) => '${v.round()} listening clients',
    );

    final Widget rates = _select<ListenerRates>(
      label: 'Listener rates (illustrative)',
      value: c.rates,
      items: <AppSelectItem<ListenerRates>>[
        for (final ListenerRates x in ListenerRates.values) (x, x.label),
      ],
      onChanged: (ListenerRates x) => m.rates = x,
    );

    final Widget dtim = McSlider(
      label: 'DTIM period',
      valueText: compact
          ? '${c.dtimPeriod} (${mcMs(r.dtimIntervalUs)})'
          : 'every ${c.dtimPeriod} beacon${c.dtimPeriod == 1 ? '' : 's'}, '
                '${mcMs(r.dtimIntervalUs)}',
      value: c.dtimPeriod.toDouble(),
      min: kMcMinDtim.toDouble(),
      max: kMcMaxDtim.toDouble(),
      divisions: kMcMaxDtim - kMcMinDtim,
      onChanged: (double v) => m.dtimPeriod = v.round(),
      semanticValue: (double v) =>
          'every ${v.round()} beacons, '
          '${(v.round() * 102.4).toStringAsFixed(1)} milliseconds',
    );

    final Widget powerSave = McSwitchRow(
      title: 'A client is in power save',
      value: c.powerSave,
      onChanged: (bool on) => m.powerSave = on,
    );

    final String unicastNote =
        'Unicast copies: Wi-Fi 6, 20 MHz, 2 spatial streams, one frame and '
        'one ACK (acknowledgment) each (illustrative).';

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AirtimeCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                rate,
                gap,
                pair(packet, basic),
                gap,
                pair(band, viewSelect),
                gap,
                pair(listeners, rates),
                gap,
                pair(dtim, powerSave),
              ],
            ),
          ),
          PresenterDisclosure(
            title: 'Stream presets (illustrative)',
            children: <Widget>[presets],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AirtimeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const AirtimeSectionTitle('Stream'),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Presets (illustrative)',
                style: text.labelMedium?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xs),
              presets,
              gap,
              rate,
              gap,
              packet,
            ],
          ),
        ),
        gap,
        AirtimeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const AirtimeSectionTitle('Channel'),
              const SizedBox(height: AppSpacing.xs),
              band,
              gap,
              basic,
              const SizedBox(height: AppSpacing.xs),
              Text(
                'A basic rate is one every client must support, so group '
                'frames go at it. 1, 2, 5.5 and 11 Mb/s are 802.11b rates, '
                '2.4 GHz only.',
                style: note,
              ),
              gap,
              view,
            ],
          ),
        ),
        gap,
        AirtimeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const AirtimeSectionTitle('Converted to unicast'),
              const SizedBox(height: AppSpacing.xs),
              listeners,
              gap,
              rates,
              const SizedBox(height: AppSpacing.xs),
              Text(
                'MCS (modulation and coding scheme) per listener: '
                '${r.copies.map((UnicastCopy u) => u.mcs).join(', ')}.',
                style: note,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(unicastNote, style: note),
            ],
          ),
        ),
        gap,
        AirtimeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const AirtimeSectionTitle('Power save'),
              const SizedBox(height: AppSpacing.xs),
              powerSave,
              gap,
              dtim,
              const SizedBox(height: AppSpacing.xs),
              Text(
                c.powerSave
                    ? 'The AP holds multicast until the next DTIM (delivery '
                          'traffic indication message) beacon, so it arrives '
                          'late and in bursts.'
                    : 'The DTIM (delivery traffic indication message) period '
                          'only matters once a client dozes: turn on power '
                          'save to see multicast held.',
                style: note,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _select<T>({
    required String label,
    required T value,
    required List<AppSelectItem<T>> items,
    required ValueChanged<T> onChanged,
  }) => LabeledField(
    label: label,
    field: AppSelect<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      semanticLabel: label,
    ),
  );
}

// ── Small parts ─────────────────────────────────────────────────────────────

/// A selectable outlined button, filled when selected.
class McChoiceButton extends StatelessWidget {
  const McChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  /// Tighter side padding, so a row of choices fits the presenter panel.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppSpacing.minTouchTarget),
          padding: dense
              ? const EdgeInsets.symmetric(horizontal: AppSpacing.xs)
              : null,
          backgroundColor: selected ? colors.primary : null,
          foregroundColor: selected ? colors.onPrimary : colors.textPrimary,
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

/// A labeled slider with its value on the right.
class McSlider extends StatelessWidget {
  const McSlider({
    super.key,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.semanticValue,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final String Function(double v) semanticValue;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final Widget valueWidget = Text(
      valueText,
      textAlign: TextAlign.right,
      style: mono.inlineCode.copyWith(color: colors.textPrimary),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: text.labelMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              // Presenter: the value keeps its own width so it never breaks
              // mid-number. Phone: it may wrap, so a narrow screen never
              // overflows.
              if (PresenterMode.isActive(context))
                valueWidget
              else
                Flexible(child: valueWidget),
            ],
          ),
        ),
        Semantics(
          label: label,
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            semanticFormatterCallback: semanticValue,
          ),
        ),
      ],
    );
  }
}

/// A switch with its title; the whole row toggles.
class McSwitchRow extends StatelessWidget {
  const McSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        canRequestFocus: false,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: text.bodyLarge?.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: colors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

String _thousands(int n) {
  final String s = '$n';
  if (s.length <= 3) return s;
  return '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
}
