// The controls for A Frame's Journey (Wi-Fi Classroom): play, back, step and
// reset with the hop slider, the predict-then-reveal question, the band and
// the distance, the corrupt-a-bit switch and which bit, the capturing switch,
// the frame (TCP or UDP, payload) and the model notes. Reads and writes a
// [FrameJourneyController]; owns no state.
//
// ILLUSTRATIVE VALUES, each labeled: the 20 dBm EIRP behind the signal
// level, the radiotap MCS and timer value, every MAC address.
//
// States (SOP-007 §5):
//   - fresh       -> 5 GHz, 8 m, sent clean, receiver capturing, step 1
//   - empty       -> the radiotap card says "not capturing" when off
//   - error       -> not reachable: the model is pure and total
//   - disabled    -> the bit slider is disabled until Corrupt one bit is on;
//                    Back and Step at the ends
//   - loading     -> not reachable: the hop is computed synchronously
//   - interactive -> themed Material controls with the global focus ring
//
// PRESENTER: notes fold into a PresenterDisclosure; inputs pair up.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/frame_journey_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../units/length_format.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../labeled_field.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'frame_journey_controller.dart';
import 'frame_journey_parts.dart';

class FrameJourneyControls extends StatelessWidget {
  const FrameJourneyControls({super.key, required this.controller});

  final FrameJourneyController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final bool presenting = PresenterMode.isActive(context);
        final SizedBox gap = SizedBox(
          height: presenting ? AppSpacing.xs : AppSpacing.sm,
        );
        final List<Widget> body = <Widget>[
          _Transport(controller: controller),
          gap,
          _Predict(controller: controller, compact: presenting),
          gap,
          _Inputs(controller: controller, compact: presenting),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ...body,
            if (presenting)
              PresenterDisclosure(
                title: 'Model notes',
                children: <Widget>[_Notes(controller: controller)],
              )
            else ...<Widget>[gap, _Notes(controller: controller)],
          ],
        );
      },
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.controller});

  final FrameJourneyController controller;

  @override
  Widget build(BuildContext context) {
    final FrameJourneyController c = controller;
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
            compact: PresenterMode.isActive(context),
          ),
          const SizedBox(height: AppSpacing.xs),
          FjSlider(
            label: 'Step',
            valueText: '${c.index + 1} of ${c.stepCount}',
            value: c.index.toDouble(),
            min: 0,
            max: (c.stepCount - 1).toDouble(),
            divisions: c.stepCount - 1,
            onChanged: (double v) => c.index = v.round(),
            semanticValue: (double v) =>
                'step ${v.round() + 1} of ${c.stepCount}: '
                '${c.hop[v.round().clamp(0, c.stepCount - 1)].title}',
          ),
        ],
      ),
    );
  }
}

class _Predict extends StatelessWidget {
  const _Predict({required this.controller, required this.compact});

  final FrameJourneyController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final FhQuestion q = controller.question;
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
          if (compact && q == FhQuestion.asking)
            FilledButton.icon(
              onPressed: controller.reveal,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Reveal'),
            )
          else if (q != FhQuestion.idle)
            IconButton(
              onPressed: controller.dismissQuestion,
              tooltip: 'Close the question',
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(kFhQuestionText, style: body),
    ];

    switch (q) {
      case FhQuestion.idle:
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
              'Turns on Corrupt one bit and starts the hop over. Reveal jumps '
              'to the moment after the FCS check.',
              style: note,
            ),
          ],
        ]);
      case FhQuestion.asking:
        children.addAll(<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final FhGuess g in FhGuess.values)
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
      case FhQuestion.revealed:
        final FhGuess? g = controller.guess;
        children.addAll(<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text('Nothing.', style: body.copyWith(fontWeight: FontWeight.w600)),
          if (g != null)
            Text(
              g == FhGuess.nothing
                  ? 'The class picked "${g.label}": right.'
                  : 'The class picked "${g.label}".',
              style: body,
            ),
          if (!compact) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Why: the receiver cannot trust any part of a frame that fails '
              'its FCS, not even the address of who sent it, so it throws the '
              'frame away and stays silent. The sender learns only from the '
              'ACK that never comes, and sends the frame again.',
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

class _Inputs extends StatelessWidget {
  const _Inputs({required this.controller, required this.compact});

  final FrameJourneyController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final FrameJourneyController c = controller;
    final FhConfig cfg = c.config;
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final LengthFormat lf = LengthFormat(c.units);
    final SizedBox gap = SizedBox(
      height: compact ? AppSpacing.xs : AppSpacing.sm,
    );
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);
    final SifsTiming sifs = c.sifs;
    final AirFrame frame = c.step.frame;
    final int flip = cfg.flipBit.clamp(0, frame.bitCount - 1);

    final Widget band = AppToggle<FjBand>(
      label: compact ? null : 'Band',
      semanticLabel: 'Band',
      value: cfg.band,
      expand: true,
      items: <AppToggleItem<FjBand>>[
        for (final FjBand b in FjBand.values) (b, b.label),
      ],
      onChanged: (FjBand b) => c.band = b,
    );
    final Widget distance = FjSlider(
      label: 'Distance',
      valueText: lf.dist(cfg.distanceM, decimals: 0),
      value: cfg.distanceM,
      min: kFjMinDistanceM,
      max: kFjMaxDistanceM,
      divisions: (kFjMaxDistanceM - kFjMinDistanceM).round(),
      onChanged: (double v) => c.distanceM = v,
      semanticValue: (double v) => lf.distSpoken(v, decimals: 0),
    );
    final Widget corrupt = FjSwitchRow(
      title: 'Corrupt one bit on the first attempt',
      value: cfg.corrupt,
      onChanged: (bool v) => c.corrupt = v,
    );
    final Widget bit = FjSlider(
      label: 'Which bit',
      valueText: 'bit $flip',
      value: flip.toDouble(),
      min: 0,
      max: (frame.bitCount - 1).toDouble(),
      divisions: null,
      onChanged: cfg.corrupt ? (double v) => c.flipBit = v.round() : null,
      semanticValue: (double v) => 'bit ${v.round()}',
    );
    final Widget bitWhere = Text(
      cfg.corrupt
          ? 'In ${frame.fieldAtBit(flip).name}. Any single bit fails the '
                'check, even one inside the FCS itself.'
          : 'Turn on the switch to pick a bit.',
      style: note,
    );
    final Widget capture = FjSwitchRow(
      title: 'Receiver is capturing (radiotap)',
      value: cfg.capturing,
      onChanged: (bool v) => c.capturing = v,
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
          for (final int n in kFjPayloadChoices) (n, '$n bytes'),
        ],
        onChanged: (int n) => c.payload = n,
        semanticLabel: 'Data size',
      ),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AirtimeCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[band, distance, corrupt, bit],
            ),
          ),
          PresenterDisclosure(
            title: 'The receiver and the frame',
            children: <Widget>[
              capture,
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(child: transport),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: payload),
                ],
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
              const AirtimeSectionTitle('The air'),
              const SizedBox(height: AppSpacing.xs),
              band,
              const SizedBox(height: AppSpacing.xxs),
              Text(
                sifs.signalExtensionUs > 0
                    ? 'SIFS (short interframe space) on 2.4 GHz is '
                          '${sifs.sifsUs} \u00B5s, after a '
                          '${sifs.signalExtensionUs} \u00B5s signal extension '
                          'that follows an OFDM (orthogonal frequency division '
                          'multiplexing) frame there, so the gap is '
                          '${sifs.gapUs} \u00B5s.'
                    : 'SIFS (short interframe space) on ${cfg.band.label} is '
                          '${sifs.sifsUs} \u00B5s.',
                style: note,
              ),
              gap,
              distance,
              Text(
                'The signal level assumes 20 dBm EIRP (effective isotropic '
                'radiated power, illustrative) and free-space loss. Distance '
                'lowers the wave\'s height; its frequency never changes.',
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
              const AirtimeSectionTitle('Corrupt a bit'),
              const SizedBox(height: AppSpacing.xs),
              corrupt,
              bit,
              bitWhere,
            ],
          ),
        ),
        gap,
        AirtimeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const AirtimeSectionTitle('The receiver and the frame'),
              const SizedBox(height: AppSpacing.xs),
              capture,
              gap,
              transport,
              gap,
              payload,
            ],
          ),
        ),
      ],
    );
  }
}

class _Notes extends StatelessWidget {
  const _Notes({required this.controller});

  final FrameJourneyController controller;

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
            'The FCS is a real CRC-32 computed over this frame\'s bytes; '
            'flipping a bit changes the result. The frame\'s Duration, '
            'sequence number, MAC addresses and data are illustrative.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Left out: the preamble (see PHY Preamble), how bits are coded '
            'onto subcarriers, the ACK timeout value, the backoff before the '
            'retry, retry limits, block acknowledgment for aggregated frames, '
            'and encryption. Airtime is not to scale.',
            style: body,
          ),
        ],
      ),
    );
  }
}
