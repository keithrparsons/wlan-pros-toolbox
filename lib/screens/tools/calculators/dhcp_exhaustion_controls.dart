// Controls for Conference Wi-Fi Runs Out of Addresses (Wi-Fi Classroom):
// play the morning, the one main control (lease time), the pool (subnet and
// reserved addresses), the crowd, private-address rotation with its two
// assumptions, predict then reveal, and the notes with links to the
// Association, Frame by Frame ladder (one DHCP exchange) and the Subnet
// Planner.
//
// States (SOP-007 §5):
//   - loading     -> none: pure on-device arithmetic, no I/O
//   - empty       -> none: there is always a crowd and a pool
//   - error       -> none reachable: every input is a bounded slider, toggle
//                    or switch; a pool smaller than zero clamps to zero
//   - success     -> the chart, the pool, the readouts
//   - disabled    -> Step at 13:00; the two rotation assumptions while
//                    rotation is off, with the reason in words
//   - interactive -> themed Material controls with the global focus ring
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'band_steering_parts.dart' show BsChoiceButton, BsSlider, BsSwitchRow;
import 'dhcp_exhaustion_controller.dart';

class DhcpExhaustionControls extends StatelessWidget {
  const DhcpExhaustionControls({super.key, required this.controller});

  final DhcpExhaustionController controller;

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
              _Main(controller: controller, compact: true),
              gap,
              _Predict(controller: controller, compact: true),
              PresenterDisclosure(
                title: 'Time, assumptions, pool and crowd',
                children: <Widget>[
                  _TimeSlider(controller: controller),
                  _RotationAssumptions(controller: controller),
                  _PoolAndCrowd(controller: controller, compact: true),
                ],
              ),
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
            _Main(controller: controller, compact: false),
            gap,
            _PoolAndCrowd(controller: controller, compact: false),
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

// ── Play the morning ───────────────────────────────────────────────────────

class _Transport extends StatelessWidget {
  const _Transport({required this.controller, required this.compact});

  final DhcpExhaustionController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final DhcpExhaustionController c = controller;
    ButtonStyle style() => OutlinedButton.styleFrom(
      minimumSize: const Size(0, AppSpacing.minTouchTarget),
      foregroundColor: colors.textPrimary,
    );
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: c.togglePlay,
                style: style(),
                icon: Icon(
                  c.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(c.playing ? 'Pause' : 'Play the morning'),
              ),
              OutlinedButton.icon(
                onPressed: c.atEnd ? null : c.stepOnce,
                style: style(),
                icon: const Icon(Icons.skip_next_rounded),
                label: const Text('+10 min'),
              ),
              OutlinedButton.icon(
                onPressed: c.reset,
                style: style(),
                icon: const Icon(Icons.replay_rounded),
                label: const Text('Reset'),
              ),
            ],
          ),
          if (!compact) const SizedBox(height: AppSpacing.xs),
          if (!compact) _TimeSlider(controller: c),
        ],
      ),
    );
  }
}

/// The playhead as a slider (in the presenter's disclosure; Space and the
/// Right arrow move time there).
class _TimeSlider extends StatelessWidget {
  const _TimeSlider({required this.controller});

  final DhcpExhaustionController controller;

  @override
  Widget build(BuildContext context) {
    final DhcpExhaustionController c = controller;
    return BsSlider(
      label: 'Time',
      valueText: dxClock(c.minute),
      value: c.minute.toDouble(),
      min: 0,
      max: kDxMinutes.toDouble(),
      divisions: kDxMinutes ~/ 5,
      onChanged: (double v) => c.minute = (v / 5).round() * 5,
      semanticValue: (double v) => dxClock(v.round()),
    );
  }
}

// ── The main control: lease time, and rotation ─────────────────────────────

class _Main extends StatelessWidget {
  const _Main({required this.controller, required this.compact});

  final DhcpExhaustionController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final DhcpExhaustionController c = controller;
    final DxConfig cfg = c.config;
    final TextStyle? note = text.bodySmall?.copyWith(
      color: colors.textTertiary,
    );
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          BsSlider(
            label: 'Lease time',
            valueText: dxLeaseLabel(cfg.leaseMinutes),
            value: c.leaseIndex.toDouble(),
            min: 0,
            max: (kDxLeaseChoices.length - 1).toDouble(),
            divisions: kDxLeaseChoices.length - 1,
            onChanged: (double v) =>
                c.leaseMinutes = kDxLeaseChoices[v.round()],
            semanticValue: (double v) =>
                dxLeaseLabel(kDxLeaseChoices[v.round()]),
          ),
          if (!compact)
            Text(
              'A device that stays renews at half the lease. One that '
              'leaves sends nothing, so its address stays taken until the '
              'lease runs out.',
              style: note,
            ),
          const SizedBox(height: AppSpacing.xs),
          BsSwitchRow(
            title: 'Devices rotate their private address on this open network',
            value: cfg.rotation,
            onChanged: (bool v) => c.rotation = v,
          ),
          if (!compact) _RotationAssumptions(controller: c),
          if (!compact)
            Text(
              cfg.rotation
                  ? 'No device maker publishes how often it rotates, so '
                        'both numbers are assumptions.'
                  : 'Only used while rotation is on.',
              style: note,
            ),
        ],
      ),
    );
  }
}

/// The two rotation numbers, both assumptions; live only with rotation on.
class _RotationAssumptions extends StatelessWidget {
  const _RotationAssumptions({required this.controller});

  final DhcpExhaustionController controller;

  @override
  Widget build(BuildContext context) {
    final DhcpExhaustionController c = controller;
    final DxConfig cfg = c.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        BsSlider(
          label: 'Share of devices that rotate (assumption)',
          valueText: '${(cfg.rotatingShare * 100).round()}%',
          value: cfg.rotatingShare,
          min: 0,
          max: 1,
          divisions: 20,
          onChanged: cfg.rotation ? (double v) => c.rotatingShare = v : null,
          semanticValue: (double v) => '${(v * 100).round()} percent',
        ),
        BsSlider(
          label: 'A rotating device comes back as new every (assumption)',
          valueText: '${cfg.rotationMinutes} min',
          value: cfg.rotationMinutes.toDouble(),
          min: kDxMinRotation.toDouble(),
          max: kDxMaxRotation.toDouble(),
          divisions: (kDxMaxRotation - kDxMinRotation) ~/ 15,
          onChanged: cfg.rotation
              ? (double v) => c.rotationMinutes = v.round()
              : null,
          semanticValue: (double v) => '${v.round()} minutes',
        ),
      ],
    );
  }
}

// ── Pool and crowd ─────────────────────────────────────────────────────────

class _PoolAndCrowd extends StatelessWidget {
  const _PoolAndCrowd({required this.controller, required this.compact});

  final DhcpExhaustionController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final DhcpExhaustionController c = controller;
    final DxConfig cfg = c.config;
    final List<Widget> children = <Widget>[
      if (!compact) ...<Widget>[
        const AirtimeSectionTitle('Pool and crowd'),
        const SizedBox(height: AppSpacing.xs),
      ],
      AppToggle<int>(
        label: 'Subnet',
        semanticLabel: 'Subnet prefix length',
        value: cfg.prefix,
        expand: true,
        items: <AppToggleItem<int>>[
          for (final int p in kDxPrefixChoices) (p, '/$p'),
        ],
        onChanged: (int p) => c.prefix = p,
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        '${cfg.usableHosts} usable addresses, ${cfg.reserved} reserved: '
        '${cfg.poolSize} in the pool.',
        style: text.bodySmall?.copyWith(color: colors.textSecondary),
      ),
      const SizedBox(height: AppSpacing.xs),
      BsSlider(
        label: 'Reserved: gateway, servers, printers (illustrative)',
        valueText: '${cfg.reserved}',
        value: cfg.reserved.toDouble(),
        min: 0,
        max: kDxMaxReserved.toDouble(),
        divisions: kDxMaxReserved,
        onChanged: (double v) => c.reserved = v.round(),
        semanticValue: (double v) => '${v.round()} addresses',
      ),
      BsSlider(
        label: 'People over the morning (illustrative)',
        valueText: '${cfg.people}',
        value: cfg.people.toDouble(),
        min: kDxMinPeople.toDouble(),
        max: kDxMaxPeople.toDouble(),
        divisions: (kDxMaxPeople - kDxMinPeople) ~/ 50,
        onChanged: (double v) => c.people = (v / 50).round() * 50,
        semanticValue: (double v) => '${v.round()} people',
      ),
      BsSlider(
        label: 'Devices each person puts on the Wi-Fi (illustrative)',
        valueText: cfg.devicesPerPerson.toStringAsFixed(1),
        value: cfg.devicesPerPerson,
        min: 1,
        max: 3,
        divisions: 4,
        onChanged: (double v) => c.devicesPerPerson = (v * 2).round() / 2,
        semanticValue: (double v) => '${v.toStringAsFixed(1)} devices',
      ),
      BsSlider(
        label: 'Average stay (illustrative)',
        valueText: '${cfg.stayMinutes} min',
        value: cfg.stayMinutes.toDouble(),
        min: 15,
        max: kDxMinutes.toDouble(),
        divisions: (kDxMinutes - 15) ~/ 15,
        onChanged: (double v) => c.stayMinutes = (v / 15).round() * 15,
        semanticValue: (double v) => '${v.round()} minutes',
      ),
    ];
    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    return compact ? body : AirtimeCard(child: body);
  }
}

// ── Predict, then reveal ────────────────────────────────────────────────────

class _Predict extends StatelessWidget {
  const _Predict({required this.controller, required this.compact});

  final DhcpExhaustionController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final DxQuestion q = controller.question;
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
          if (compact && q == DxQuestion.idle)
            FilledButton.icon(
              onPressed: controller.ask,
              icon: const Icon(Icons.help_outline_rounded),
              label: const Text('Ask the class'),
            )
          else if (compact && q == DxQuestion.asking)
            FilledButton.icon(
              onPressed: controller.reveal,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Reveal'),
            )
          else if (q != DxQuestion.idle)
            IconButton(
              onPressed: controller.dismissQuestion,
              tooltip: 'Close the question',
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      if (!(compact && q == DxQuestion.idle)) ...<Widget>[
        const SizedBox(height: AppSpacing.xxs),
        Text(kDxQuestionText, style: body),
      ],
    ];

    switch (q) {
      case DxQuestion.idle:
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
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Loads the defaults and stops at the first device with no '
            'address. Reveal gives the answer.',
            style: note,
          ),
        ]);
      case DxQuestion.asking:
        children.addAll(<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final DxGuess g in DxGuess.values)
                BsChoiceButton(
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
      case DxQuestion.revealed:
        final DxGuess? g = controller.guess;
        const DxGuess right = DxGuess.leaseOrPool;
        final DxMorning short = controller.shortLeaseMorning;
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
          const SizedBox(height: AppSpacing.xxs),
          Text(
            short.held
                ? 'With a lease of 30 min the same morning holds: at most '
                      '${short.peakBound} of ${short.poolSize} addresses '
                      'taken.'
                : 'With a lease of 30 min this crowd still runs dry at '
                      '${dxClock(short.firstDryMinute!)}; it needs a bigger '
                      'pool.',
            style: compact ? note : body,
          ),
          if (!compact) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Why: the radio link is fine. Devices associate, get no '
              'address, and show full bars with nothing loading. More APs '
              'or a faster line add no addresses. The pool has to cover '
              'everyone who arrived within one lease time.',
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

  final DhcpExhaustionController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final TextStyle? body = text.bodySmall?.copyWith(
      color: colors.textSecondary,
    );
    final List<String> lines = <String>[
      'Lease rules from RFC (Request for Comments) 2131: a device renews '
          'before its lease ends, the server keys each lease to the '
          'device\'s hardware address, and a device that just leaves does '
          'not hand its address back.',
      'A device with a new private address is a new client to the server, '
          'so it gets a second address while the first is still held.',
      'Illustrative: the crowd, the arrival rush, how long people stay and '
          'the reserved addresses. Assumptions: how many devices rotate and '
          'how often.',
      'Not modeled: devices that do hand their address back when they '
          'leave, servers that give short leases to new clients, captive '
          'sign-in pages, and IPv6 (Internet Protocol version 6) addressing.',
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
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRouter.joinLadder),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Association, Frame by Frame'),
              ),
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRouter.subnetPlanner),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Subnet Planner'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
