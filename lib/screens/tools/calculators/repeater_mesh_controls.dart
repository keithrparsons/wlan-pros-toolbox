// The controls for Repeaters and Mesh Backhaul (Wi-Fi Classroom): readouts,
// the predict-then-reveal question, the relays and the backhaul, the band,
// every node's position, and the two illustrative factors. Reads and writes
// a [RepeaterMeshController]; owns no state, so a presenter layout can place
// it beside [RepeaterMeshStage].
//
// ILLUSTRATIVE VALUES (spec 36). The efficiency factor, the forwarding delay,
// every radio's power, the path-loss exponent and the channel widths are
// illustrative, and each is labeled so where it is set.
//
// States (SOP-007 §5):
//   - fresh       -> 5 GHz, one relay halfway to a client 36 m away, one
//                    channel: two equal hops, half of one hop end to end
//   - empty       -> not reachable: there is always at least one relay and
//                    one hop
//   - error       -> a hop the chain needs has no link: the stage and the
//                    readouts say "no link" in danger with an icon and words,
//                    and the end-to-end throughput is 0
//   - disabled    -> Reveal before the question is asked is not shown; the
//                    relay count stops at 1 and 3
//   - loading     -> not reachable: the model is synchronous and pure
//   - interactive -> themed Material controls with the global focus ring
//
// PRESENTER (PresenterMode.isActive): the headline numbers are on the stage;
// the readouts table and the position sliders fold into PresenterDisclosures
// (the nodes drag on the stage), and short inputs pair up, so the panel fits
// at 1440x900 with no scroll.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/repeater_mesh_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../labeled_field.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'multicast_basic_rate_controls.dart' show McChoiceButton, McSlider;
import 'repeater_mesh_controller.dart';

/// The question, word for word (spec 36).
const String kRmQuestionText =
    'Your repeater shows full bars to the laptop. Why is it slower than '
    'before?';

/// The assumptions every hop shares, in words.
const String kRmAssumptions =
    'Every radio: 20 dBm EIRP (equivalent isotropically radiated power), '
    'path-loss exponent 3.0, 802.11ax at 2 spatial streams, 80 MHz on 5 and '
    '6 GHz and 20 MHz on 2.4 GHz (illustrative).';

class RepeaterMeshControls extends StatelessWidget {
  const RepeaterMeshControls({super.key, required this.controller});

  final RepeaterMeshController controller;

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
                title: 'Positions',
                children: <Widget>[_Positions(controller: controller)],
              ),
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
            gap,
            AirtimeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const AirtimeSectionTitle('Positions'),
                  const SizedBox(height: AppSpacing.xs),
                  _Positions(controller: controller),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Readouts ────────────────────────────────────────────────────────────────

class _Readouts extends StatelessWidget {
  const _Readouts({required this.controller});

  final RepeaterMeshController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final RmResult r = controller.result;
    final RmConfig c = r.config;
    final bool masked = controller.masked;
    final TextStyle label =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final TextStyle value = mono.inlineCode.copyWith(color: colors.textPrimary);

    TableRow row(
      String name,
      String v, {
      bool accent = false,
      bool danger = false,
    }) => TableRow(
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
            style: danger
                ? value.copyWith(color: colors.statusDanger)
                : accent
                ? value.copyWith(color: colors.textAccent)
                : value,
          ),
        ),
      ],
    );

    String hopValue(RmHop h) {
      if (h.wired) return 'cable';
      if (!h.link.hasLink) {
        return '${h.link.rxDbm.toStringAsFixed(1)} dBm, no link';
      }
      return '${h.link.rxDbm.toStringAsFixed(1)} dBm, MCS ${h.link.mcs}, '
          '${masked ? '?' : rmMbps(h.throughputMbps)}';
    }

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('Readouts'),
          const SizedBox(height: AppSpacing.xs),
          Table(
            columnWidths: const <int, TableColumnWidth>{
              0: FlexColumnWidth(1.2),
              1: FlexColumnWidth(1.4),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: <TableRow>[
              for (final RmHop h in r.hops)
                row(
                  'Hop ${h.from + 1}, ${rmNodeName(h.from, c.relayCount)} to '
                  '${rmNodeName(h.to, c.relayCount)}'
                  '${h.wired ? '' : ', ${rmMeters(h.link.distanceM)}'}',
                  hopValue(h),
                  danger: !h.wired && !h.link.hasLink,
                ),
              row(
                'End to end',
                masked ? '?' : rmMbps(r.endToEndMbps),
                accent: true,
              ),
              row(
                'Straight to the AP, same spot',
                masked
                    ? '?'
                    : r.direct.hasLink
                    ? 'MCS ${r.direct.mcs}, ${rmMbps(r.direct.throughputMbps)}'
                    : 'no link',
                accent: true,
              ),
              row(
                'Forwarding delay',
                '${rmMs(r.delayMs)} (${rmMs(r.directDelayMs)} straight)',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Hop throughput = PHY (physical layer) rate x efficiency. '
            '${c.backhaul.rule}',
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

  final RepeaterMeshController controller;

  /// The presenter arrangement: fewer notes.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final RmQuestion q = controller.question;
    final TextStyle body =
        text.bodyMedium?.copyWith(color: colors.textPrimary) ??
        TextStyle(color: colors.textPrimary);
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);

    final List<Widget> children = <Widget>[
      if (compact && q == RmQuestion.asking)
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
      else if (compact && q == RmQuestion.revealed)
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
      Text(kRmQuestionText, style: body),
    ];

    switch (q) {
      case RmQuestion.idle:
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
              'Loads the scene (a repeater 30 m down the corridor, the laptop '
              '2 m from it, one channel) and hides the throughputs until you '
              'reveal them.',
              style: note,
            ),
          ],
        ]);
      case RmQuestion.asking:
        children.addAll(<Widget>[
          const SizedBox(height: AppSpacing.xs),
          for (final RmGuess g in RmGuess.values)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: SizedBox(
                width: double.infinity,
                child: McChoiceButton(
                  label: g.label,
                  selected: controller.guess == g,
                  onPressed: () => controller.guess = g,
                  dense: compact,
                ),
              ),
            ),
          if (!compact) const SizedBox(height: AppSpacing.xxs),
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
      case RmQuestion.revealed:
        final RmResult r = controller.result;
        final RmGuess? g = controller.guess;
        final RmHop back = r.hops.first;
        final RmHop last = r.hops.last;
        children.addAll(<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Straight to the AP: ${rmMbps(r.direct.throughputMbps)}. Through '
            'the repeater: ${rmMbps(r.endToEndMbps)}.',
            style: body.copyWith(fontWeight: FontWeight.w600),
          ),
          if (g != null)
            Text(
              g.right
                  ? 'The class picked the right reason.'
                  : 'The class picked "${g.label}". The reason: every frame '
                        'crosses the air twice on one channel, and the '
                        'repeater\'s link back to the AP is weak.',
              style: body,
            ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'The bars measure only the laptop\'s hop '
            '(${rmMbps(last.throughputMbps)}). The repeater\'s hop back to '
            'the AP carries ${rmMbps(back.throughputMbps)}, and on one '
            'channel the two take turns: 1/T = 1/${back.throughputMbps.toStringAsFixed(1)} '
            '+ 1/${last.throughputMbps.toStringAsFixed(1)}. Drag the repeater '
            'toward the AP, or give it a dedicated backhaul radio.',
            style: compact ? body : note,
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

  final RepeaterMeshController controller;

  /// The presenter arrangement: pairs, fewer notes.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final RepeaterMeshController m = controller;
    final RmConfig c = m.config;
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

    final Widget relays = AppToggle<int>(
      label: 'Relays',
      semanticLabel: 'Number of relays',
      value: c.relayCount,
      expand: true,
      items: <AppToggleItem<int>>[
        for (int n = kRmMinRelays; n <= kRmMaxRelays; n++) (n, '$n'),
      ],
      onChanged: (int n) => m.relayCount = n,
    );

    final Widget backhaul = LabeledField(
      label: 'Backhaul',
      field: AppSelect<RmBackhaul>(
        value: c.backhaul,
        items: <AppSelectItem<RmBackhaul>>[
          for (final RmBackhaul b in RmBackhaul.values)
            (b, compact ? b.short : b.label),
        ],
        onChanged: (RmBackhaul b) => m.backhaul = b,
        semanticLabel: 'Backhaul',
      ),
    );

    final Widget band = AppToggle<RmBand>(
      label: 'Band',
      semanticLabel: 'Band',
      value: c.band,
      expand: true,
      items: <AppToggleItem<RmBand>>[
        for (final RmBand b in RmBand.values) (b, b.label),
      ],
      onChanged: (RmBand b) => m.band = b,
    );

    final Widget efficiency = McSlider(
      label: 'Efficiency (illustrative)',
      valueText: c.efficiency.toStringAsFixed(2),
      value: c.efficiency,
      min: kRmMinEfficiency,
      max: kRmMaxEfficiency,
      divisions: ((kRmMaxEfficiency - kRmMinEfficiency) * 20).round(),
      onChanged: (double v) => m.efficiency = v,
      semanticValue: (double v) => 'efficiency ${v.toStringAsFixed(2)}',
    );

    final Widget delay = McSlider(
      label: 'Forwarding delay per hop (illustrative)',
      valueText: rmMs(c.forwardingDelayMs),
      value: c.forwardingDelayMs,
      min: kRmMinDelayMs,
      max: kRmMaxDelayMs,
      divisions: ((kRmMaxDelayMs - kRmMinDelayMs) * 2).round(),
      onChanged: (double v) => m.forwardingDelayMs = v,
      semanticValue: (double v) =>
          '${(v * 2).round() / 2} milliseconds per hop',
    );

    if (compact) {
      return AirtimeCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            pair(relays, backhaul),
            gap,
            band,
            gap,
            pair(efficiency, delay),
          ],
        ),
      );
    }

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('Relays and backhaul'),
          const SizedBox(height: AppSpacing.xs),
          relays,
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Changing the count spaces the relays evenly between the AP and '
            'the client. Up and Down do the same in the presenter.',
            style: note,
          ),
          gap,
          backhaul,
          const SizedBox(height: AppSpacing.xxs),
          Text(c.backhaul.rule, style: note),
          gap,
          band,
          gap,
          efficiency,
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Turns each hop\'s PHY (physical layer) rate into what it carries '
            'after waits, headers and acknowledgments.',
            style: note,
          ),
          gap,
          delay,
          const SizedBox(height: AppSpacing.xxs),
          Text(kRmAssumptions, style: note),
        ],
      ),
    );
  }
}

// ── Positions ───────────────────────────────────────────────────────────────

/// A slider per movable node: the keyboard and screen-reader way to do what
/// dragging does on the stage.
class _Positions extends StatelessWidget {
  const _Positions({required this.controller});

  final RepeaterMeshController controller;

  @override
  Widget build(BuildContext context) {
    final RmConfig c = controller.config;
    final List<double> nodes = c.nodesM;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 1; i < nodes.length; i++)
          McSlider(
            label: '${rmNodeName(i, c.relayCount)} position',
            valueText: rmMeters(nodes[i]),
            value: nodes[i],
            min: 0,
            max: kRmCorridorM,
            divisions: (kRmCorridorM * 2).round(),
            onChanged: (double v) => controller.moveNode(i, v),
            semanticValue: (double v) =>
                '${rmMeters((v * 2).roundToDouble() / 2)} from the AP',
          ),
      ],
    );
  }
}
