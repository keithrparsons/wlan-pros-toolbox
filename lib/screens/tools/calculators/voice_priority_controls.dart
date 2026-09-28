// Controls for Voice Priority, End to End (Wi-Fi Classroom): send the packet
// hop by hop, predict then reveal, the one main control (where the marking
// is lost), the AP mapping, the download, the illustrative queue depth, and
// the notes with links to the Medium Access Simulator (EDCA itself) and the
// DSCP / QoS Markings card (the full mapping table).
//
// States (SOP-007 §5):
//   - loading     -> none: pure on-device arithmetic over a precomputed
//                    engine table, no I/O
//   - empty       -> none: there is always one packet and one path
//   - error       -> none reachable: every input is a bounded toggle, switch
//                    or slider
//   - success     -> the queue, the path, the lanes and the waits
//   - disabled    -> Step at the phone; the frames-ahead slider when the
//                    call is not in Best effort or no download runs, with
//                    the reason in words
//   - interactive -> themed Material controls with the global focus ring
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../labeled_field.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'band_steering_parts.dart' show BsChoiceButton, BsSlider, BsSwitchRow;
import 'voice_priority_controller.dart';

class VoicePriorityControls extends StatelessWidget {
  const VoicePriorityControls({super.key, required this.controller});

  final VoicePriorityController controller;

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
              _Transport(controller: controller),
              gap,
              _Inputs(controller: controller, compact: true),
              gap,
              _Predict(controller: controller, compact: true),
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
            _Transport(controller: controller),
            gap,
            _Inputs(controller: controller, compact: false),
            gap,
            _Predict(controller: controller, compact: false),
            gap,
            _Notes(controller: controller),
          ],
        );
      },
    );
  }
}

// ── Send, step, reset ──────────────────────────────────────────────────────

class _Transport extends StatelessWidget {
  const _Transport({required this.controller});

  final VoicePriorityController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final VoicePriorityController c = controller;
    ButtonStyle style() => OutlinedButton.styleFrom(
      minimumSize: const Size(0, AppSpacing.minTouchTarget),
      foregroundColor: colors.textPrimary,
    );
    return AirtimeCard(
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: <Widget>[
          OutlinedButton.icon(
            onPressed: c.togglePlay,
            style: style(),
            icon: Icon(
              c.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
            label: Text(c.playing ? 'Pause' : 'Send the packet'),
          ),
          OutlinedButton.icon(
            onPressed: c.atEnd ? null : c.stepOnce,
            style: style(),
            icon: const Icon(Icons.skip_next_rounded),
            label: const Text('Next hop'),
          ),
          OutlinedButton.icon(
            onPressed: c.reset,
            style: style(),
            icon: const Icon(Icons.replay_rounded),
            label: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

// ── Inputs ──────────────────────────────────────────────────────────────────

class _Inputs extends StatelessWidget {
  const _Inputs({required this.controller, required this.compact});

  final VoicePriorityController controller;

  /// Presenter: the notes under the controls are left out; the stage's
  /// headline already says why the call is where it is.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final VoicePriorityController c = controller;
    final VpConfig cfg = c.config;
    final bool framesLive = c.trip.framesAheadMatters && !c.hidingAnswer;
    final TextStyle? note = text.bodySmall?.copyWith(
      color: colors.textTertiary,
    );
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!compact) ...<Widget>[
            const AirtimeSectionTitle('Settings'),
            const SizedBox(height: AppSpacing.xs),
          ],
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              // Four segments truncate on a phone; the select shows the full
              // label there.
              if (box.maxWidth >= 440 || compact) {
                return AppToggle<MarkLoss>(
                  label: 'Where the marking is lost',
                  semanticLabel: 'Where the marking is lost',
                  value: cfg.loss,
                  expand: true,
                  enabled: !c.hidingAnswer,
                  items: <AppToggleItem<MarkLoss>>[
                    for (final MarkLoss l in MarkLoss.values) (l, l.short),
                  ],
                  onChanged: (MarkLoss l) => c.loss = l,
                );
              }
              return LabeledField(
                label: 'Where the marking is lost',
                field: AppSelect<MarkLoss>(
                  semanticLabel: 'Where the marking is lost',
                  value: cfg.loss,
                  enabled: !c.hidingAnswer,
                  items: <AppSelectItem<MarkLoss>>[
                    for (final MarkLoss l in MarkLoss.values) (l, l.label),
                  ],
                  onChanged: (MarkLoss l) => c.loss = l,
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<ApMapping>(
            label: 'How the AP maps DSCP to user priority',
            semanticLabel: 'How the AP maps DSCP to user priority',
            value: cfg.mapping,
            expand: true,
            enabled: !c.hidingAnswer,
            items: const <AppToggleItem<ApMapping>>[
              (ApMapping.rfc8325, 'RFC 8325'),
              (ApMapping.topThreeBits, 'Top three bits'),
            ],
            onChanged: (ApMapping m) => c.mapping = m,
          ),
          if (!compact) const SizedBox(height: AppSpacing.xxs),
          if (!compact)
            Text(
              cfg.mapping == ApMapping.rfc8325
                  ? 'RFC 8325 recommends EF to UP 6, the Voice queue.'
                  : 'The older default copies the top three bits: EF (46) '
                        'becomes UP 5, the Video queue.',
              style: note,
            ),
          const SizedBox(height: AppSpacing.xs),
          BsSwitchRow(
            title: 'A download is running',
            value: cfg.downloadRunning,
            onChanged: (bool v) => c.downloadRunning = v,
          ),
          const SizedBox(height: AppSpacing.xs),
          BsSlider(
            label: 'Download frames ahead in Best effort (illustrative)',
            valueText: '${cfg.framesAhead}',
            value: cfg.framesAhead.toDouble(),
            min: kVpMinFramesAhead.toDouble(),
            max: kVpMaxFramesAhead.toDouble(),
            divisions: (kVpMaxFramesAhead - kVpMinFramesAhead) ~/ 8,
            onChanged: framesLive
                ? (double v) => c.framesAhead = v.round()
                : null,
            semanticValue: (double v) => '${v.round()} frames',
          ),
          if (!framesLive && !compact)
            Text(
              c.hidingAnswer
                  ? 'Locked while the class predicts.'
                  : !cfg.downloadRunning
                  ? 'Only used while a download runs.'
                  : 'Only used when the call lands in Best effort.',
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

  final VoicePriorityController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final VpQuestion q = controller.question;
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
          if (compact && q == VpQuestion.idle)
            FilledButton.icon(
              onPressed: controller.ask,
              icon: const Icon(Icons.help_outline_rounded),
              label: const Text('Ask the class'),
            )
          else if (compact && q == VpQuestion.asking)
            FilledButton.icon(
              onPressed: controller.reveal,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Reveal'),
            )
          else if (q != VpQuestion.idle)
            IconButton(
              onPressed: controller.dismissQuestion,
              tooltip: 'Close the question',
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      if (!(compact && q == VpQuestion.idle)) ...<Widget>[
        const SizedBox(height: AppSpacing.xxs),
        Text(kVpQuestionText, style: body),
      ],
    ];

    switch (q) {
      case VpQuestion.idle:
        if (compact) break;
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
              'Loads the question and hides the answer on the stage. '
              'Reveal shows it.',
              style: note,
            ),
          ],
        ]);
      case VpQuestion.asking:
        children.addAll(<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final VpGuess g in VpGuess.values)
                BsChoiceButton(
                  label: g.label,
                  selected: controller.guess == g,
                  onPressed: () => controller.guess = g,
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
      case VpQuestion.revealed:
        final VpGuess right = controller.rightAnswer;
        final VpGuess? g = controller.guess;
        children.addAll(<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${right.label}.',
            style: body.copyWith(fontWeight: FontWeight.w600),
          ),
          if (g != null)
            Text(
              g == right
                  ? 'The class picked "${g.label}": right.'
                  : 'The class picked "${g.label}".',
              style: body,
            ),
          if (!compact) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Why: WMM gives the AP four queues, but the AP picks the queue '
              'from the marking it receives. Once any hop resets EF to 0, '
              'the AP sees an ordinary packet and puts the call in Best '
              'effort, behind the download. WMM being on changes nothing.',
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

// ── Notes ───────────────────────────────────────────────────────────────────

class _Notes extends StatelessWidget {
  const _Notes({required this.controller});

  final VoicePriorityController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final TextStyle? body = text.bodySmall?.copyWith(
      color: colors.textSecondary,
    );
    final List<String> lines = <String>[
      'DSCP (Differentiated Services Code Point) is the priority mark in '
          'the IP header. EF (Expedited Forwarding, 46) is the mark for '
          'voice. The AP turns it into an 802.11 user priority (UP), and '
          'the UP picks one of the four WMM (Wi-Fi Multimedia) queues.',
      'A tunnel wraps the packet in a new header. Whether it copies EF to '
          'the outside is up to the device (RFC 4301); if it does not, no '
          'hop can see the mark.',
      'A network you do not run, such as your provider\'s, may reset or '
          'ignore the mark. Priority set on your own network cannot be '
          'relied on past it.',
      'The Wi-Fi hop\'s waits come from the Medium Access Simulator\'s '
          'engine, unchanged. That simulator shows the contention itself, '
          'slot by slot. Its simplifications apply here: legacy 54 Mbps '
          'timing, one frame size, and the client\'s default EDCA settings '
          '(an AP\'s own can differ).',
      'Illustrative: a voice packet every 20 ms, and how many download '
          'frames sit ahead in the queue. Real depth depends on the AP.',
    ];
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('What this shows, and leaves out'),
          const SizedBox(height: AppSpacing.xs),
          for (final String l in lines) ...<Widget>[
            Text(l, style: body),
            const SizedBox(height: AppSpacing.xs),
          ],
          Wrap(
            spacing: AppSpacing.xs,
            children: <Widget>[
              TextButton.icon(
                onPressed: () => Navigator.of(
                  context,
                ).pushNamed(AppRouter.mediumAccessSimulator),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Medium Access Simulator'),
              ),
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRouter.dscpQos),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open DSCP / QoS Markings'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
