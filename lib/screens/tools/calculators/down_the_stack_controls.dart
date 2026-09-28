// The controls for Down the Stack, Across the Air, Up the Other Side (Wi-Fi
// Classroom): play, back, step and reset with the journey slider, the
// predict-then-reveal question, the scene (direction, where the server is),
// the frame (TCP or UDP, payload, QoS or textbook header), the view and the
// To DS / From DS case, and the model notes. Reads and writes a
// [DownTheStackController]; owns no state.
//
// ILLUSTRATIVE VALUES, each labeled on screen: every MAC address, the
// laptop's port 51000, the starting TTL of 64, the 100 and 500 byte payloads.
//
// States (SOP-007 §5):
//   - fresh       -> laptop to server on another subnet, TCP, 1460 bytes,
//                    step 1 (application data on the laptop)
//   - empty       -> not reachable: every step carries data
//   - error       -> not reachable: the model is pure and total
//   - disabled    -> Back at the first step and Step at the last; Reveal
//                    shows only once the question is asked
//   - loading     -> not reachable: the journey is computed synchronously
//   - interactive -> themed Material controls with the global focus ring
//
// PRESENTER (PresenterMode.isActive): the step and the addresses are on the
// stage; notes fold into a PresenterDisclosure and short inputs pair up, so
// the panel fits at 1440x900 with no scroll.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/frame_journey_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../labeled_field.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'down_the_stack_controller.dart';
import 'frame_journey_parts.dart';

class DownTheStackControls extends StatelessWidget {
  const DownTheStackControls({super.key, required this.controller});

  final DownTheStackController controller;

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
              _Transport(controller: controller, compact: true),
              gap,
              _Predict(controller: controller, compact: true),
              gap,
              _View(controller: controller, compact: true),
              gap,
              _Scene(controller: controller, compact: true),
              PresenterDisclosure(
                title: 'Model notes',
                children: <Widget>[_Notes(controller: controller)],
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Transport(controller: controller, compact: false),
            gap,
            _Predict(controller: controller, compact: false),
            gap,
            _View(controller: controller, compact: false),
            gap,
            _Scene(controller: controller, compact: false),
            gap,
            _Notes(controller: controller),
          ],
        );
      },
    );
  }
}

// ── Play, back, step, reset and the journey slider ─────────────────────────

class _Transport extends StatelessWidget {
  const _Transport({required this.controller, required this.compact});

  final DownTheStackController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final DownTheStackController c = controller;
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FjTransportRow(
            playing: c.playing,
            atStart: c.atStart,
            atEnd: c.atEnd,
            onPlay: c.togglePlay,
            onBack: c.stepBack,
            onStep: c.stepOnce,
            onReset: c.reset,
            compact: compact,
          ),
          const SizedBox(height: AppSpacing.xs),
          FjSlider(
            label: 'Journey step',
            valueText: '${c.index + 1} of ${c.stepCount}',
            value: c.index.toDouble(),
            min: 0,
            max: (c.stepCount - 1).toDouble(),
            divisions: c.stepCount - 1,
            onChanged: (double v) => c.index = v.round(),
            semanticValue: (double v) =>
                'step ${v.round() + 1} of ${c.stepCount}: '
                '${c.journey[v.round().clamp(0, c.stepCount - 1)].title}',
          ),
        ],
      ),
    );
  }
}

// ── Predict, then reveal ────────────────────────────────────────────────────

class _Predict extends StatelessWidget {
  const _Predict({required this.controller, required this.compact});

  final DownTheStackController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final DtsQuestion q = controller.question;
    final TextStyle body =
        text.bodyMedium?.copyWith(color: colors.textPrimary) ??
        TextStyle(color: colors.textPrimary);
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);

    final List<Widget> children = <Widget>[
      Row(
        children: <Widget>[
          const Expanded(child: AirtimeSectionTitle('Predict, then reveal')),
          if (compact && q == DtsQuestion.asking)
            FilledButton.icon(
              onPressed: controller.reveal,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Reveal'),
            )
          else if (q != DtsQuestion.idle)
            IconButton(
              onPressed: controller.dismissQuestion,
              tooltip: 'Close the question',
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(kDtsQuestionText, style: body),
    ];

    switch (q) {
      case DtsQuestion.idle:
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
              'Loads the scene: laptop to a server on another subnet. Reveal '
              'jumps to the step where the laptop fills in the 802.11 header.',
              style: note,
            ),
          ],
        ]);
      case DtsQuestion.asking:
        children.addAll(<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final DtsGuess g in DtsGuess.values)
                FjChoiceButton(
                  label: g.label,
                  selected: controller.guess == g,
                  onPressed: () => controller.guess = g,
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
      case DtsQuestion.revealed:
        final DtsGuess? g = controller.guess;
        children.addAll(<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The router\'s LAN MAC.',
            style: body.copyWith(fontWeight: FontWeight.w600),
          ),
          if (g != null)
            Text(
              g == DtsGuess.router
                  ? 'The class picked "${g.label}": right.'
                  : 'The class picked "${g.label}".',
              style: body,
            ),
          if (!compact) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Why: the server is not on the laptop\'s subnet, so the laptop '
              'hands the packet to its default gateway. Address 3 is the next '
              'layer 2 stop past the AP, and that is the router. The '
              'server\'s address is only in the IP header. Switch the server '
              'to the laptop\'s own subnet and Address 3 becomes the server.',
              style: note,
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

// ── The view and the To DS / From DS case ───────────────────────────────────

class _View extends StatelessWidget {
  const _View({required this.controller, required this.compact});

  final DownTheStackController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final DownTheStackController c = controller;
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppToggle<DtsView>(
            label: compact ? null : 'Show',
            semanticLabel: 'Show',
            value: c.view,
            expand: true,
            items: <AppToggleItem<DtsView>>[
              for (final DtsView v in DtsView.values) (v, v.label),
            ],
            onChanged: (DtsView v) => c.view = v,
          ),
          SizedBox(height: compact ? AppSpacing.xxs : AppSpacing.xs),
          Text(
            compact
                ? 'To DS / From DS'
                : 'To DS / From DS (DS: the distribution system, the network '
                      'behind the APs)',
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final DsCase d in DsCase.values)
                Semantics(
                  label: d.label,
                  excludeSemantics: false,
                  child: FjChoiceButton(
                    label: '${d.toDsBit} ${d.fromDsBit}',
                    selected: c.dsCase == d,
                    onPressed: () {
                      c.dsCase = d;
                      c.view = DtsView.addresses;
                    },
                  ),
                ),
            ],
          ),
          if (!compact) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Two bits in the 802.11 Frame Control field, To DS first. Each '
              'button shows the pair.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

// ── The scene and the frame ─────────────────────────────────────────────────

class _Scene extends StatelessWidget {
  const _Scene({required this.controller, required this.compact});

  final DownTheStackController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final DownTheStackController c = controller;
    final FjConfig cfg = c.config;
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final SizedBox gap = SizedBox(
      height: compact ? AppSpacing.xs : AppSpacing.sm,
    );
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);

    final Widget direction = AppToggle<FjDirection>(
      label: compact ? null : 'Direction',
      semanticLabel: 'Direction',
      value: cfg.direction,
      expand: true,
      items: const <AppToggleItem<FjDirection>>[
        (FjDirection.toServer, 'To the server'),
        (FjDirection.reply, 'The reply'),
      ],
      onChanged: (FjDirection d) => c.direction = d,
    );
    final Widget server = AppToggle<FjServerLocation>(
      label: compact ? null : 'Server',
      semanticLabel: 'Where the server is',
      value: cfg.server,
      expand: true,
      items: const <AppToggleItem<FjServerLocation>>[
        (FjServerLocation.otherSubnet, 'Another subnet'),
        (FjServerLocation.sameSubnet, 'Same subnet'),
      ],
      onChanged: (FjServerLocation s) => c.server = s,
    );
    final Widget transport = AppToggle<FjTransport>(
      label: compact ? null : 'Transport',
      semanticLabel: 'Transport protocol',
      value: cfg.transport,
      expand: true,
      items: <AppToggleItem<FjTransport>>[
        for (final FjTransport t in FjTransport.values) (t, t.label),
      ],
      onChanged: (FjTransport t) => c.transport = t,
    );
    final Widget payload = LabeledField(
      label: 'Data',
      field: AppSelect<int>(
        value: cfg.payload,
        items: <AppSelectItem<int>>[
          for (final int n in kFjPayloadChoices)
            (n, n == 1460 ? '$n bytes (fills 1500 with TCP)' : '$n bytes'),
        ],
        onChanged: (int n) => c.payload = n,
        semanticLabel: 'Data size',
      ),
    );
    final Widget qos = FjSwitchRow(
      title: 'QoS (quality of service) Data header, 26 bytes',
      value: cfg.qos,
      onChanged: (bool v) => c.qos = v,
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PresenterDisclosure(
            title:
                'Scene: ${cfg.direction == FjDirection.toServer ? 'to the server' : 'the reply'}, '
                '${cfg.throughRouter ? 'another subnet' : 'same subnet'}, '
                '${cfg.transport.label}',
            children: <Widget>[
              direction,
              gap,
              server,
              gap,
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(child: transport),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: payload),
                ],
              ),
              qos,
            ],
          ),
        ],
      );
    }

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('The scene'),
          const SizedBox(height: AppSpacing.xs),
          direction,
          gap,
          server,
          const SizedBox(height: AppSpacing.xxs),
          Text(
            cfg.throughRouter
                ? 'Server 198.51.100.20 on another subnet: the path is Laptop, '
                      'AP, Router, Server.'
                : 'Server 192.0.2.20 on the laptop\'s subnet: the path is '
                      'Laptop, AP, Server, and no router.',
            style: note,
          ),
          gap,
          const AirtimeSectionTitle('The frame'),
          const SizedBox(height: AppSpacing.xs),
          transport,
          gap,
          payload,
          gap,
          qos,
          Text(
            'Nearly every data frame on a modern network is a QoS Data frame, '
            'with a 26-byte header. Off shows the 24-byte Data header most '
            'textbooks draw.',
            style: note,
          ),
        ],
      ),
    );
  }
}

// ── Model notes ─────────────────────────────────────────────────────────────

class _Notes extends StatelessWidget {
  const _Notes({required this.controller});

  final DownTheStackController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final TextStyle body =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('What this models, and what it leaves out'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'No NAT (network address translation). Most home routers do '
            'translate addresses, and then the source IP changes at the '
            'router. Here the IP addresses stay the same end to end; only the '
            'TTL (time to live) and the header checksum change at the router.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Illustrative: every MAC address, the laptop\'s port 51000 and the '
            'starting TTL of 64 (operating systems differ). The IP addresses '
            'come from the ranges reserved for documentation (RFC 5737). The '
            'drawing shows the OSI (Open Systems Interconnection) layers 7, 4, '
            '3, 2 and 1 and leaves out 5 and 6.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Left out: address resolution (ARP) traffic, the ACK, the PHY '
            'preamble, encryption, aggregation, VLAN tags and IPv6. A mesh '
            'network (802.11s) can carry up to six addresses in its Mesh '
            'Control field; the four-address case here is the plain one.',
            style: body,
          ),
        ],
      ),
    );
  }
}
