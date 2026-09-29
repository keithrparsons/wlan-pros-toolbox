// The controls for the Channel Utilization Meter (Wi-Fi Classroom): the
// transport, predict-then-reveal, the traffic (senders, offered load, rate,
// frame size, idle associated stations), the measurement (window, reserved
// time), other energy on the channel (a neighbor network, non-Wi-Fi bursts),
// the formula with the live numbers, the readouts, and the many-sender
// curve. Reads and writes a [ChannelUtilizationController]; owns no state,
// so a presenter layout can place it beside [ChannelUtilizationStage].
//
// LABELED VALUES (spec 37). The window's default of 50 intervals rests on one
// secondary source and is labeled "default (one secondary source)". The
// neighbor's share and the non-Wi-Fi pattern are illustrative and labeled
// so. The published many-sender points carry the spec's caption.
//
// States (SOP-007 §5):
//   - fresh       -> one saturated sender, 54 Mb/s, 1500 bytes, paused, the
//                    meter "collecting the first beacon interval"
//   - loading     -> the window filling: "window filling, k of N intervals"
//                    until N intervals exist
//   - empty       -> not reachable: at least one sender always exists
//   - error       -> not reachable: every input is bounded and the model is
//                    pure
//   - disabled    -> the neighbor's share slider is disabled while the
//                    neighbor is off; Reveal only appears once asked
//   - interactive -> themed Material controls with the global focus ring
//
// PRESENTER (PresenterMode.isActive): short inputs pair up two per row, and
// the formula, readouts and many-sender curve fold into PresenterDisclosures,
// so the panel fits at 1440x900 with no scroll.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/channel_utilization_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../labeled_field.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'channel_utilization_controller.dart';
import 'multicast_basic_rate_controls.dart'
    show McChoiceButton, McSlider, McSwitchRow;

/// The window slider's label (spec 37: "default (one secondary source)").
const String kCuWindowLabel =
    'Averaging window, beacon intervals (default 50: one secondary source)';

class ChannelUtilizationControls extends StatelessWidget {
  const ChannelUtilizationControls({super.key, required this.controller});

  final ChannelUtilizationController controller;

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
              // The transport sits on the stage in presenter mode, beside
              // the headline, so this panel fits without scrolling.
              _Predict(controller: controller, compact: true),
              gap,
              _Inputs(controller: controller, compact: true),
              PresenterDisclosure(
                title: 'Formula, readouts and many senders',
                children: <Widget>[
                  _Formula(controller: controller),
                  gap,
                  _Readouts(controller: controller),
                  gap,
                  _ManySenders(controller: controller),
                ],
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Formula(controller: controller),
            gap,
            _Readouts(controller: controller),
            gap,
            _Predict(controller: controller, compact: false),
            gap,
            _Inputs(controller: controller, compact: false),
            gap,
            _ManySenders(controller: controller),
          ],
        );
      },
    );
  }
}

// ── Transport ───────────────────────────────────────────────────────────────

/// Run, step, reset, skip a window, add a burst. Buttons with words on the
/// normal screen; icon buttons with tooltips in the presenter panel.
class CuTransport extends StatelessWidget {
  const CuTransport({
    super.key,
    required this.controller,
    required this.compact,
  });

  final ChannelUtilizationController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final bool playing = controller.playing;
        final List<(IconData, String, VoidCallback)> actions =
            <(IconData, String, VoidCallback)>[
              (
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                playing ? 'Pause' : 'Run the channel',
                controller.togglePlay,
              ),
              (
                Icons.skip_next_rounded,
                'Next beacon interval',
                controller.stepInterval,
              ),
              (
                Icons.fast_forward_rounded,
                'Skip one window',
                controller.skipWindow,
              ),
              (
                Icons.bolt_outlined,
                'Add a 1-second non-Wi-Fi burst',
                controller.addBurst,
              ),
              (Icons.replay_rounded, 'Reset', controller.reset),
            ];
        if (compact) {
          return Row(
            children: <Widget>[
              for (final (IconData icon, String label, VoidCallback onTap)
                  in actions)
                IconButton(
                  onPressed: onTap,
                  tooltip: label,
                  icon: Icon(icon, color: colors.textPrimary),
                ),
            ],
          );
        }
        return Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            for (final (IconData icon, String label, VoidCallback onTap)
                in actions)
              OutlinedButton.icon(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppSpacing.minTouchTarget),
                  foregroundColor: colors.textPrimary,
                ),
                icon: Icon(icon),
                label: Text(label),
              ),
          ],
        );
      },
    );
  }
}

// ── The formula ─────────────────────────────────────────────────────────────

class _Formula extends StatelessWidget {
  const _Formula({required this.controller});

  final ChannelUtilizationController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final CuReading? r = controller.reading;
    final bool masked = controller.masked;
    final TextStyle code = mono.inlineCode.copyWith(color: colors.textPrimary);
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);

    final String live;
    if (masked) {
      live = '= hidden until Reveal';
    } else if (r == null) {
      live = '= waiting for the first beacon interval';
    } else {
      final String busy = _us(r.busyTenths / 10);
      live =
          '= floor(255 × $busy ÷ (${r.intervalsUsed} × 100 × 1024))\n'
          '= ${r.byte};  ${r.byte} ÷ 255 = ${cuPct(r.share)}';
    }

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const AirtimeSectionTitle('The formula'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Channel Utilization = floor(255 × busy µs ÷ (window × beacon '
            'period × 1024))',
            style: code,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(live, style: code.copyWith(color: colors.textAccent)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Window in beacon intervals, beacon period in TU (time units of '
            '1024 µs). Busy = ${controller.countReserved ? 'listener view: the radio heard a signal, or a frame\'s Duration field reserved the time (physical or virtual carrier sense)' : 'what the access point reports: the radio heard a signal or was transmitting (physical carrier sense)'}. '
            '255 means 100%; each step is about 0.39%.',
            style: note,
          ),
          if (r != null && r.filling && !masked) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'The window is still filling, so this averages the '
              '${r.intervalsUsed} intervals there are.',
              style: note,
            ),
          ],
        ],
      ),
    );
  }
}

String _us(double us) {
  final String fixed = us.toStringAsFixed(1);
  final List<String> parts = fixed.split('.');
  final String whole = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (Match m) => '${m[1]},',
  );
  return '$whole.${parts[1]} µs';
}

// ── Readouts ────────────────────────────────────────────────────────────────

class _Readouts extends StatelessWidget {
  const _Readouts({required this.controller});

  final ChannelUtilizationController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final CuReading? r = controller.reading;
    final bool masked = controller.masked;
    final CuConfig c = controller.config;
    final CuCycle cy = controller.cycle;
    final TextStyle label =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final TextStyle value = mono.inlineCode.copyWith(color: colors.textPrimary);
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);

    final Map<CuSplit, double>? shares = r == null || masked
        ? null
        : cuSplitShares(r, countReserved: controller.countReserved);
    String share(CuSplit s) =>
        masked ? '?' : (shares == null ? '…' : cuPct(shares[s]!));

    TableRow row(String name, String v) => TableRow(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Text(name, style: label),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Text(v, textAlign: TextAlign.end, style: value),
        ),
      ],
    );

    final double seconds = r == null
        ? 0
        : r.intervalsUsed * kCuIntervalTenths / 1e7;
    final String throughput = masked || r == null || seconds == 0
        ? (masked ? '?' : '…')
        : '${(r.totals[CuSpan.payload] / 10 * c.rateMbps / (seconds * 1e6)).toStringAsFixed(1)} Mb/s';

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const AirtimeSectionTitle('Readouts'),
          const SizedBox(height: AppSpacing.xs),
          Table(
            columnWidths: const <int, TableColumnWidth>{
              0: FlexColumnWidth(),
              1: IntrinsicColumnWidth(),
            },
            children: <TableRow>[
              row(
                controller.viewLabel,
                masked
                    ? '?'
                    : r == null
                    ? '…'
                    : '${r.byte} of 255, ${cuPct(r.share)}',
              ),
              row('Station count (associated)', '${c.stationCount}'),
              row('Payload share', share(CuSplit.payload)),
              row('Overhead share', share(CuSplit.overhead)),
              row('Collision share', share(CuSplit.collision)),
              if (c.neighbor) row('Other network', share(CuSplit.neighbor)),
              if (c.nonWifi || (shares?[CuSplit.nonWifi] ?? 0) > 0)
                row('Non-Wi-Fi', share(CuSplit.nonWifi)),
              row('Required idle', share(CuSplit.requiredIdle)),
              row('Truly spare', share(CuSplit.spare)),
              row('Delivered payload', throughput),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'One sender alone at ${c.rateMbps} Mb/s with ${c.payloadBytes}-byte '
            'frames: a cycle of ${cy.cycleUs.toStringAsFixed(1)} µs, '
            '${cuPct(cy.physicalShare)} busy as the access point reports it, '
            '${cuPct(cy.virtualShare)} in the listener view, payload '
            '${cuPct(cy.payloadShare)}. That channel is full there, not at '
            '100%.',
            style: note,
          ),
        ],
      ),
    );
  }
}

// ── Predict, then reveal ────────────────────────────────────────────────────

class _Predict extends StatelessWidget {
  const _Predict({required this.controller, required this.compact});

  final ChannelUtilizationController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final CuQuestion q = controller.question;
    final TextStyle body =
        text.bodyMedium?.copyWith(color: colors.textPrimary) ??
        TextStyle(color: colors.textPrimary);
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);

    final List<Widget> children = <Widget>[
      if (compact && q == CuQuestion.asking)
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
      else if (compact && q == CuQuestion.revealed)
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
      Text(kCuQuestionText, style: body),
    ];

    switch (q) {
      case CuQuestion.idle:
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
              'Loads one sender at 54 Mb/s with 1500-byte frames and nothing '
              'else on the channel, and hides the meter until you reveal it.',
              style: note,
            ),
          ],
        ]);
      case CuQuestion.asking:
        children.addAll(<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final CuGuess g in CuGuess.values)
                McChoiceButton(
                  label: g.label,
                  selected: controller.guess == g,
                  onPressed: () => controller.guess = g,
                  dense: compact,
                ),
            ],
          ),
          if (!compact) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: controller.reveal,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Reveal'),
              ),
            ),
          ],
        ]);
      case CuQuestion.revealed:
        final CuCycle cy = controller.cycle;
        // The question is about the meter the AP reports, in either view.
        final CuReading? r = controller.apReading;
        final CuGuess? g = controller.guess;
        final double answer = r?.share ?? cy.physicalShare;
        final CuGuess right = CuGuess.values.firstWhere(
          (CuGuess x) => x.contains(answer),
        );
        children.addAll(<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            compact
                ? 'Meter: ${cuPct(answer)}, not 100%. The AP sees one sender '
                      'fill it at ${cuPct(cy.physicalShare)}.'
                : 'The meter reads ${cuPct(answer)}'
                      '${r == null ? '' : ' (${r.byte} of 255)'}, not 100%. '
                      'As the access point reports it, one sender fills this '
                      'channel at ${cuPct(cy.physicalShare)} busy; a listener '
                      'outside the exchange sees '
                      '${cuPct(cy.virtualShare)}.',
            style: body.copyWith(fontWeight: FontWeight.w600),
          ),
          if (g != null)
            Text(
              g == right
                  ? 'The class picked ${g.label}: right.'
                  : 'The class picked ${g.label}. The answer is '
                        '${right.label}.',
              style: body,
            ),
          if (!compact) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Why: before every frame the sender must wait a DIFS '
              '(distributed interframe space) and a random backoff, and the '
              'AP waits a SIFS (short interframe space) before its ACK '
              '(acknowledgment). That silence is the protocol, not spare '
              'room, so a meter reading 50% here means about two-thirds of '
              'what this channel can carry is in use.',
              style: note,
            ),
            const SizedBox(height: AppSpacing.xs),
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
          ],
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

  final ChannelUtilizationController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final ChannelUtilizationController m = controller;
    final CuConfig c = m.config;
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

    final Widget senders = McSlider(
      label: 'Senders',
      valueText: '${c.senders}',
      value: c.senders.toDouble(),
      min: kCuMinSenders.toDouble(),
      max: kCuMaxSenders.toDouble(),
      divisions: kCuMaxSenders - kCuMinSenders,
      onChanged: (double v) => m.senders = v.round(),
      semanticValue: (double v) => '${v.round()} sending stations',
    );

    final Widget load = McSlider(
      label: 'Offered load, each',
      valueText: c.saturated ? 'saturated' : '${c.loadPercent}%',
      value: c.loadPercent.toDouble(),
      min: kCuMinLoadPercent.toDouble(),
      max: kCuMaxLoadPercent.toDouble(),
      divisions: (kCuMaxLoadPercent - kCuMinLoadPercent) ~/ 5,
      onChanged: (double v) => m.loadPercent = (v / 5).round() * 5,
      semanticValue: (double v) {
        final int p = (v / 5).round() * 5;
        return p >= kCuMaxLoadPercent
            ? 'saturated, always a frame waiting'
            : '$p percent of what one sender alone can carry';
      },
    );

    final Widget rate = _select<int>(
      label: 'Data rate',
      value: c.rateMbps,
      items: <AppSelectItem<int>>[
        for (final int r in ChannelUtilizationController.rates) (r, '$r Mb/s'),
      ],
      onChanged: (int r) => m.rateMbps = r,
    );

    final Widget basic = _select<CuBasicRates>(
      label: 'Basic rates',
      value: c.basicRates,
      items: <AppSelectItem<CuBasicRates>>[
        for (final CuBasicRates b in CuBasicRates.values) (b, b.label),
      ],
      onChanged: (CuBasicRates b) => m.basicRates = b,
    );

    final String basicNote =
        'ACKs here go at '
        '${cuControlRateFor(c.rateMbps, basicRates: c.basicRates)} Mb/s: '
        'the highest basic rate not faster than the frame they answer; if '
        'none fits, the fastest of 6, 12 or 24 that is not faster.';

    final Widget size = _select<int>(
      label: 'Frame payload',
      value: c.payloadBytes,
      items: <AppSelectItem<int>>[
        for (final int b in kCuPayloadSizes) (b, '${_thousands(b)} bytes'),
      ],
      onChanged: (int b) => m.payloadBytes = b,
    );

    final Widget idle = McSlider(
      label: 'Associated but idle',
      valueText: '${c.idleStations}',
      value: c.idleStations.toDouble(),
      min: 0,
      max: kCuMaxIdleStations.toDouble(),
      divisions: kCuMaxIdleStations,
      onChanged: (double v) => m.idleStations = v.round(),
      semanticValue: (double v) => '${v.round()} idle associated stations',
    );

    final Widget window = McSlider(
      label: compact
          ? 'Window (default 50: one secondary source)'
          : kCuWindowLabel,
      valueText: '${m.window} = ${m.windowSeconds.toStringAsFixed(2)} s',
      value: m.window.toDouble(),
      min: kCuMinWindow.toDouble(),
      max: kCuMaxWindow.toDouble(),
      divisions: kCuMaxWindow - kCuMinWindow,
      onChanged: (double v) => m.window = v.round(),
      semanticValue: (double v) =>
          '${v.round()} beacon intervals, '
          '${(v.round() * 0.1024).toStringAsFixed(2)} seconds',
    );

    final Widget reserved = McSwitchRow(
      title: ChannelUtilizationController.listenerViewLabel,
      value: m.countReserved,
      onChanged: (bool on) => m.countReserved = on,
    );

    final Widget neighbor = McSwitchRow(
      title: 'A neighbor network on this channel',
      value: c.neighbor,
      onChanged: (bool on) => m.neighbor = on,
    );

    final Widget neighborShare = Opacity(
      opacity: c.neighbor ? 1 : 0.5,
      child: IgnorePointer(
        ignoring: !c.neighbor,
        child: Semantics(
          enabled: c.neighbor,
          child: McSlider(
            label: 'Neighbor\'s airtime (illustrative)',
            valueText: '${c.neighborPercent}%',
            value: c.neighborPercent.toDouble(),
            min: kCuMinNeighborPercent.toDouble(),
            max: kCuMaxNeighborPercent.toDouble(),
            divisions: (kCuMaxNeighborPercent - kCuMinNeighborPercent) ~/ 5,
            onChanged: (double v) => m.neighborPercent = (v / 5).round() * 5,
            semanticValue: (double v) =>
                '${(v / 5).round() * 5} percent of the channel offered by '
                'the neighbor',
          ),
        ),
      ),
    );

    final Widget nonWifi = McSwitchRow(
      title: 'Non-Wi-Fi bursts (illustrative)',
      value: c.nonWifi,
      onChanged: (bool on) => m.nonWifi = on,
    );

    final Widget speed = _select<CuSpeed>(
      label: 'Speed',
      value: m.speed,
      items: <AppSelectItem<CuSpeed>>[
        for (final CuSpeed s in CuSpeed.values) (s, s.label),
      ],
      onChanged: (CuSpeed s) => m.speed = s,
    );

    const String reservedNote =
        'Off: what the access point reports, the time its radio heard a '
        'signal or was transmitting. On: a device outside the exchange, '
        'which honors the reservation a frame\'s Duration field sets (the '
        'NAV, network allocation vector), so the SIFS (short interframe '
        'space) before each ACK (acknowledgment) counts as busy too.';

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AirtimeCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                pair(senders, load),
                gap,
                pair(rate, size),
                gap,
                window,
                _CompactSwitch(
                  title: ChannelUtilizationController.listenerViewLabel,
                  value: m.countReserved,
                  onChanged: (bool on) => m.countReserved = on,
                ),
                _CompactSwitch(
                  title: 'A neighbor network on this channel',
                  value: c.neighbor,
                  onChanged: (bool on) => m.neighbor = on,
                ),
                _CompactSwitch(
                  title: 'Non-Wi-Fi bursts (illustrative)',
                  value: c.nonWifi,
                  onChanged: (bool on) => m.nonWifi = on,
                ),
              ],
            ),
          ),
          PresenterDisclosure(
            title: 'More settings',
            children: <Widget>[
              AirtimeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    pair(idle, speed),
                    gap,
                    neighborShare,
                    gap,
                    basic,
                  ],
                ),
              ),
            ],
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
              const AirtimeSectionTitle('This network\'s traffic'),
              const SizedBox(height: AppSpacing.xs),
              senders,
              gap,
              load,
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Offered load is a share of what one sender alone can carry '
                'at this rate. Saturated means a frame is always waiting.',
                style: note,
              ),
              gap,
              rate,
              gap,
              basic,
              const SizedBox(height: AppSpacing.xxs),
              Text(basicNote, style: note),
              gap,
              size,
              gap,
              idle,
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Idle stations count in the Station Count but send nothing: '
                'forty idle phones and one busy video stream look very '
                'different on the count and alike on the meter.',
                style: note,
              ),
            ],
          ),
        ),
        gap,
        AirtimeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const AirtimeSectionTitle('How the AP measures'),
              const SizedBox(height: AppSpacing.xs),
              window,
              gap,
              reserved,
              const SizedBox(height: AppSpacing.xxs),
              Text(reservedNote, style: note),
              gap,
              speed,
            ],
          ),
        ),
        gap,
        AirtimeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const AirtimeSectionTitle('Other energy on the channel'),
              const SizedBox(height: AppSpacing.xs),
              neighbor,
              gap,
              neighborShare,
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'The neighbor\'s frames are busy time the AP hears, but its '
                'stations are not in this AP\'s Station Count.',
                style: note,
              ),
              gap,
              nonWifi,
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Illustrative pattern: 4 ms bursts, about 20% of the time, '
                'loud enough to make the channel read busy. Add a 1-second '
                'burst to see how little one burst moves a 5-second average.',
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

/// A switch row for the presenter panel: body-size title, the whole row
/// toggles.
class _CompactSwitch extends StatelessWidget {
  const _CompactSwitch({
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
                style: text.bodyMedium?.copyWith(color: colors.textPrimary),
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

// ── Many senders ────────────────────────────────────────────────────────────

/// The published caption for the reference points (spec 37).
const String kCuBianchiCaption =
    'published curve, 1 Mbps parameters: the shape transfers, the exact '
    'numbers do not';

class _ManySenders extends StatelessWidget {
  const _ManySenders({required this.controller});

  final ChannelUtilizationController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final List<CuCurvePoint> curve = controller.curve;
    final CuConfig c = controller.config;
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);
    final CuCurvePoint p5 = curve.firstWhere(
      (CuCurvePoint p) => p.stations == 5,
    );
    final CuCurvePoint p50 = curve.last;

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const AirtimeSectionTitle(
            'Many senders: busy stays high, data falls',
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Every sender saturated, ${c.rateMbps} Mb/s, '
            '${c.payloadBytes}-byte frames, ten beacon intervals each.',
            style: note,
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            label:
                'Chart. This tool\'s run: at 5 senders the channel is '
                '${cuPct(p5.busyShare)} busy and ${cuPct(p5.payloadShare)} '
                'payload; at 50 senders ${cuPct(p50.busyShare)} busy and '
                '${cuPct(p50.payloadShare)} payload. Published points: about '
                '80% at 5 stations and 55% at 50 for basic access, about 83% '
                'with RTS/CTS; $kCuBianchiCaption.',
            excludeSemantics: true,
            child: SizedBox(
              height: AppSpacing.xxl * 3 * math.min(scale.text, 1.2),
              child: CustomPaint(
                painter: CuCurvePainter(
                  curve: curve,
                  colors: colors,
                  scale: scale,
                  labelStyle: text.bodySmall?.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xxs,
            children: <Widget>[
              _LineKey(kind: _CurveKind.busy, label: 'Busy (the meter)'),
              _LineKey(kind: _CurveKind.payload, label: 'Payload (your data)'),
              _LineKey(
                kind: _CurveKind.published,
                label: 'Published points, basic access',
              ),
              _LineKey(
                kind: _CurveKind.rtsCts,
                label: 'Published, RTS/CTS (request to send / clear to send)',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Published points: Bianchi (2000), IEEE Journal on Selected Areas '
            'in Communications 18(3), read off the paper\'s figure: '
            '$kCuBianchiCaption. Collisions are busy time, so the meter can '
            'sit near its ceiling while less of your data gets through.',
            style: note,
          ),
        ],
      ),
    );
  }
}

enum _CurveKind { busy, payload, published, rtsCts }

class _LineKey extends StatelessWidget {
  const _LineKey({required this.kind, required this.label});

  final _CurveKind kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(
          child: SizedBox(
            width: AppSpacing.md,
            height: AppSpacing.sm,
            child: CustomPaint(
              painter: _LineKeyPainter(kind: kind, colors: colors),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            label,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _LineKeyPainter extends CustomPainter {
  _LineKeyPainter({required this.kind, required this.colors});

  final _CurveKind kind;
  final AppColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset a = Offset(0, size.height / 2);
    final Offset b = Offset(size.width, size.height / 2);
    switch (kind) {
      case _CurveKind.busy:
        canvas.drawLine(a, b, _busyPaint(colors, 1));
        canvas.drawCircle(size.center(Offset.zero), 3, _busyPaint(colors, 1));
      case _CurveKind.payload:
        canvas.drawLine(a, b, _payloadPaint(colors, 1));
        canvas.drawRect(
          Rect.fromCenter(
            center: size.center(Offset.zero),
            width: 6,
            height: 6,
          ),
          Paint()..color = colors.primary,
        );
      case _CurveKind.published:
        _diamond(canvas, size.center(Offset.zero), 5, colors, 1);
      case _CurveKind.rtsCts:
        _dot(canvas, a, b, colors, 1);
    }
  }

  @override
  bool shouldRepaint(_LineKeyPainter old) =>
      old.kind != kind || old.colors != colors;
}

Paint _busyPaint(AppColorScheme c, double s) => Paint()
  ..color = c.textSecondary
  ..strokeWidth = 2 * s
  ..style = PaintingStyle.stroke;

Paint _payloadPaint(AppColorScheme c, double s) => Paint()
  ..color = c.primary
  ..strokeWidth = 2.5 * s
  ..style = PaintingStyle.stroke;

void _dot(Canvas canvas, Offset a, Offset b, AppColorScheme c, double s) {
  final Paint p = Paint()..color = c.textPrimary;
  final double len = (b - a).distance;
  final Offset dir = (b - a) / len;
  for (double d = 0; d <= len; d += 5 * s) {
    canvas.drawCircle(a + dir * d, 1.2 * s, p);
  }
}

void _diamond(
  Canvas canvas,
  Offset c,
  double r,
  AppColorScheme colors,
  double s,
) {
  final Path path = Path()
    ..moveTo(c.dx, c.dy - r)
    ..lineTo(c.dx + r, c.dy)
    ..lineTo(c.dx, c.dy + r)
    ..lineTo(c.dx - r, c.dy)
    ..close();
  canvas.drawPath(path, Paint()..color = colors.surface1);
  canvas.drawPath(
    path,
    Paint()
      ..color = colors.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * s,
  );
}

/// Share of the channel against sender count: this tool's busy and payload
/// runs as lines, the published points as diamonds, RTS/CTS as a dotted
/// line. Nothing is drawn between the published points.
class CuCurvePainter extends CustomPainter {
  CuCurvePainter({
    required this.curve,
    required this.colors,
    required this.scale,
    required this.labelStyle,
  });

  final List<CuCurvePoint> curve;
  final AppColorScheme colors;
  final PresenterScale scale;
  final TextStyle? labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final TextStyle style = (labelStyle ?? const TextStyle()).copyWith(
      fontSize: scale.paintFont(labelStyle?.fontSize ?? 12),
    );
    TextPainter tp(String s) => TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    final TextPainter yLabel = tp('100%');
    final double left = yLabel.width + 4;
    final double bottomAxis = style.fontSize! * 1.6;
    final Rect plot = Rect.fromLTRB(
      left,
      style.fontSize! * 0.6,
      size.width - 6,
      size.height - bottomAxis,
    );
    canvas.drawRect(plot, Paint()..color = colors.inputFill);

    double px(int n) => plot.left + (n - 1) / (kCuMaxSenders - 1) * plot.width;
    double py(double share) =>
        plot.bottom - share.clamp(0.0, 1.0) * plot.height;

    // Grid at 0, 50, 100%.
    final Paint grid = Paint()
      ..color = colors.border
      ..strokeWidth = 1;
    for (final double g in <double>[0, 0.5, 1]) {
      canvas.drawLine(
        Offset(plot.left, py(g)),
        Offset(plot.right, py(g)),
        grid,
      );
      final TextPainter l = tp('${(g * 100).round()}%');
      l.paint(canvas, Offset(left - 4 - l.width, py(g) - l.height / 2));
    }
    for (final int n in <int>[1, 10, 20, 30, 40, 50]) {
      final TextPainter l = tp('$n');
      l.paint(canvas, Offset(px(n) - l.width / 2, plot.bottom + 2));
    }

    // RTS/CTS published level.
    _dot(
      canvas,
      Offset(plot.left, py(kCuBianchiRtsCts)),
      Offset(plot.right, py(kCuBianchiRtsCts)),
      colors,
      scale.stroke,
    );

    // This tool's busy and payload.
    Path line(double Function(CuCurvePoint p) f) {
      final Path path = Path();
      for (int i = 0; i < curve.length; i++) {
        final Offset o = Offset(px(curve[i].stations), py(f(curve[i])));
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      return path;
    }

    final Paint busy = _busyPaint(colors, scale.stroke);
    canvas.drawPath(line((CuCurvePoint p) => p.busyShare), busy);
    canvas.drawPath(
      line((CuCurvePoint p) => p.payloadShare),
      _payloadPaint(colors, scale.stroke),
    );
    for (final CuCurvePoint p in curve) {
      canvas.drawCircle(
        Offset(px(p.stations), py(p.busyShare)),
        3 * scale.marker,
        busy,
      );
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(px(p.stations), py(p.payloadShare)),
          width: 6 * scale.marker,
          height: 6 * scale.marker,
        ),
        Paint()..color = colors.primary,
      );
    }

    // Published basic-access points only; no line between them. Each is
    // labeled with its value, and the RTS/CTS level with its own.
    for (final (int n, double s) in kCuBianchiBasic) {
      final Offset o = Offset(px(n), py(s));
      _diamond(canvas, o, 5 * scale.marker, colors, scale.stroke);
      final TextPainter l = tp('published ${(s * 100).round()}%');
      final double lx = (o.dx - l.width / 2).clamp(
        plot.left,
        math.max(plot.left, plot.right - l.width),
      );
      l.paint(canvas, Offset(lx, o.dy + 6 * scale.marker));
    }
    final TextPainter rts = tp(
      'published, RTS/CTS about ${(kCuBianchiRtsCts * 100).round()}%',
    );
    rts.paint(
      canvas,
      Offset(
        math.max(plot.left, plot.right - rts.width),
        py(kCuBianchiRtsCts) - rts.height - 2,
      ),
    );
  }

  @override
  bool shouldRepaint(CuCurvePainter old) =>
      old.curve != curve ||
      old.colors != colors ||
      old.scale != scale ||
      old.labelStyle != labelStyle;
}

String _thousands(int n) {
  final String s = '$n';
  if (s.length <= 3) return s;
  return '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
}
