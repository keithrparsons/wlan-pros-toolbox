// DfsSimulatorControls: the inputs-and-readouts half of DFS and Radar.
//
// Takes the shared DfsSimulatorController and a set of parts to show, so the
// phone layout can put the clock and readouts right under the stage and the
// setup cards after them, while a presenter layout shows every part in one
// column beside the stage. No part draws the strip or the timeline;
// DfsSimulatorStage owns those.
//
// Control types follow GL-003 §8.14: region, new-channel policy are
// two-option AppToggles; width (four), starting channel, random radar rate,
// clock speed and EIRP are Selects. Status hues are verdicts only (§8.13
// rule 6), each with its word and an icon: amber for "not usable yet" (a CAC
// running, an outage so far), red for "blocked".
//
// PRESENTER (spec 00): inside a PresenterLayout the panel keeps the clock,
// Radar now and the setup a lesson changes (region, width, starting channel,
// what the AP does after radar) in view. The AP state, outage and clients
// are on the stage; the readouts in words, the radar log, random radar and
// the rules fold into PresenterDisclosures.

import 'package:flutter/material.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/dfs_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter.dart';
import '../labeled_field.dart';
import 'dfs_simulator_controller.dart';
import 'dfs_simulator_parts.dart';

/// The groups DfsSimulatorControls can show.
enum DfsControlPart {
  /// Play, radar now, step, restart, the clock slider and speed.
  transport,

  /// AP state, time to first transmission, last outage, blocked channels.
  readouts,

  /// One entry per radar event so far.
  log,

  /// Region, width, starting channel, policy, random radar.
  setup,

  /// The region's DFS rules and the detection threshold.
  rules,
}

class DfsSimulatorControls extends StatelessWidget {
  const DfsSimulatorControls({
    super.key,
    required this.controller,
    this.parts = const <DfsControlPart>{
      DfsControlPart.transport,
      DfsControlPart.readouts,
      DfsControlPart.log,
      DfsControlPart.setup,
      DfsControlPart.rules,
    },
  });

  final DfsSimulatorController controller;
  final Set<DfsControlPart> parts;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final DfsSimulatorController c = controller;
        if (PresenterMode.isActive(context)) return _PresenterPanel(c);
        final List<Widget> cards = <Widget>[
          if (parts.contains(DfsControlPart.transport)) _TransportCard(c),
          if (parts.contains(DfsControlPart.readouts)) _ReadoutsCard(c),
          if (parts.contains(DfsControlPart.log)) _LogCard(c),
          if (parts.contains(DfsControlPart.setup)) _SetupCard(c),
          if (parts.contains(DfsControlPart.rules)) _RulesCard(c),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < cards.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              cards[i],
            ],
          ],
        );
      },
    );
  }
}

// ── Presenter panel ─────────────────────────────────────────────────────────

class _PresenterPanel extends StatelessWidget {
  const _PresenterPanel(this.c);

  final DfsSimulatorController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool reducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final String? radarOff = c.radarDisabledReason;
    final DfsConfig cfg = c.config;
    final BondedChannel start = c.startPlacement;
    String startLabel(BondedChannel p) {
      final double cac = cacSecondsFor(cfg.region, p);
      return '${placementLabel(p)}'
          '${cac == 0 ? ', not DFS' : ', DFS, CAC ${fmtRule(cac)}'}';
    }

    final int hits = c.hitsSoFar.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DfsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: c.togglePlay,
                      icon: Icon(
                        c.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(
                        c.playing
                            ? 'Pause'
                            : c.atEnd
                            ? 'Play again'
                            : 'Play',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        minimumSize: const Size.fromHeight(
                          AppSpacing.minTouchTarget,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Tooltip(
                      message: 'Radar now (D)',
                      child: DfsOutlineButton(
                        icon: Icons.radar_rounded,
                        label: 'Radar now',
                        semanticLabel: radarOff == null
                            ? 'Radar now: the AP detects radar at '
                                  '${fmtClock(c.timeS)}'
                            : 'Radar now, unavailable. $radarOff',
                        onPressed: radarOff == null ? c.radarNow : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DfsOutlineButton(
                      icon: Icons.skip_next_rounded,
                      label: 'Step 10 s',
                      semanticLabel: 'Step the clock forward ten seconds',
                      onPressed: c.atEnd ? null : c.step,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: DfsOutlineButton(
                      icon: Icons.restart_alt_rounded,
                      label: 'Restart',
                      semanticLabel:
                          'Back to 0:00, clearing the radar you added',
                      onPressed: c.atStart ? null : c.restart,
                    ),
                  ),
                ],
              ),
              if (radarOff != null) ...<Widget>[
                const SizedBox(height: AppSpacing.xxs),
                ExcludeSemantics(
                  child: Text(
                    radarOff,
                    style: text.bodySmall?.copyWith(color: colors.textTertiary),
                  ),
                ),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: DfsSlider(
                      label: 'Clock',
                      valueText:
                          '${fmtClock(c.timeS)} of ${fmtClock(kDfsHorizonS)}',
                      value: c.timeS,
                      min: 0,
                      max: kDfsHorizonS,
                      divisions: (kDfsHorizonS / kDfsStepSeconds).round(),
                      onChanged: c.seek,
                      semanticValue: (double v) =>
                          '${fmtClock(v)} of ${fmtClock(kDfsHorizonS)}',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  SizedBox(
                    width: 130,
                    child: AppSelect<DfsClockSpeed>(
                      value: c.speed,
                      semanticLabel: 'Clock speed',
                      items: <AppSelectItem<DfsClockSpeed>>[
                        for (final DfsClockSpeed s in DfsClockSpeed.values)
                          (s, '${s.factor.round()}x'),
                      ],
                      onChanged: (DfsClockSpeed s) => c.speed = s,
                    ),
                  ),
                ],
              ),
              if (reducedMotion)
                Text(
                  'Reduced motion is on: the clock waits until you press '
                  'Play.',
                  style: text.bodySmall?.copyWith(color: colors.textTertiary),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        DfsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: AppToggle<DfsRegion>(
                      label: 'Region',
                      semanticLabel: 'Region',
                      value: cfg.region,
                      expand: true,
                      items: <AppToggleItem<DfsRegion>>[
                        for (final DfsRegion r in DfsRegion.values)
                          (r, r.label),
                      ],
                      onChanged: (DfsRegion r) => c.region = r,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  SizedBox(
                    width: 150,
                    child: LabeledField(
                      label: 'Width',
                      semanticLabel: 'Channel width',
                      field: AppSelect<int>(
                        value: cfg.widthMHz,
                        semanticLabel: 'Channel width',
                        items: <AppSelectItem<int>>[
                          for (final int w in kDfsWidths) (w, '$w MHz'),
                        ],
                        onChanged: (int w) => c.widthMHz = w,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              LabeledField(
                label: 'Starting channel',
                semanticLabel: 'Starting channel',
                // Keyed by the lowest 20 MHz channel: BondedChannel has no
                // value equality.
                field: AppSelect<int>(
                  value: start.components.first,
                  semanticLabel: 'Starting channel',
                  items: <AppSelectItem<int>>[
                    for (final BondedChannel p in c.startChoices)
                      (p.components.first, startLabel(p)),
                  ],
                  onChanged: (int first) => c.start = c.startChoices.firstWhere(
                    (BondedChannel p) => p.components.first == first,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              AppToggle<NewChannelPolicy>(
                label: 'After radar',
                semanticLabel: 'New channel after radar',
                value: cfg.policy,
                expand: true,
                items: <AppToggleItem<NewChannelPolicy>>[
                  for (final NewChannelPolicy p in NewChannelPolicy.values)
                    (p, p.label),
                ],
                onChanged: (NewChannelPolicy p) => c.policy = p,
              ),
            ],
          ),
        ),
        PresenterDisclosure(
          title: 'Radar log ($hits)',
          children: <Widget>[_LogCard(c)],
        ),
        PresenterDisclosure(
          title: 'Readouts in words, random radar',
          children: <Widget>[
            _ReadoutsCard(c),
            const SizedBox(height: AppSpacing.xs),
            LabeledField(
              label: 'Random radar',
              semanticLabel: 'Random radar rate',
              field: AppSelect<double>(
                value: cfg.radarPerHour,
                semanticLabel: 'Random radar rate',
                items: <AppSelectItem<double>>[
                  for (final double r in kRadarRates)
                    (r, r == 0 ? 'Off' : '${r.toStringAsFixed(0)} per hour'),
                ],
                onChanged: (double r) => c.radarPerHour = r,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            DfsOutlineButton(
              icon: Icons.shuffle_rounded,
              label: 'New random pattern',
              semanticLabel: 'New random radar pattern',
              onPressed: cfg.radarPerHour == 0 ? null : c.newRandomRadar,
            ),
          ],
        ),
        PresenterDisclosure(
          title: 'The rules, ${cfg.region.label}',
          children: <Widget>[_RulesCard(c)],
        ),
      ],
    );
  }
}

// ── Transport ───────────────────────────────────────────────────────────────

class _TransportCard extends StatelessWidget {
  const _TransportCard(this.c);

  final DfsSimulatorController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool reducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final String? radarOff = c.radarDisabledReason;
    return DfsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Semantics(
                  button: true,
                  label: c.playing
                      ? 'Pause the clock'
                      : c.atEnd
                      ? 'Run the hour again from the start'
                      : 'Start the clock',
                  excludeSemantics: true,
                  child: FilledButton.icon(
                    onPressed: c.togglePlay,
                    icon: Icon(
                      c.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    label: Text(
                      c.playing
                          ? 'Pause'
                          : c.atEnd
                          ? 'Play again'
                          : 'Play',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      minimumSize: const Size.fromHeight(
                        AppSpacing.minTouchTarget,
                      ),
                      textStyle: text.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: DfsOutlineButton(
                  icon: Icons.radar_rounded,
                  label: 'Radar now',
                  semanticLabel: radarOff == null
                      ? 'Radar now: the AP detects radar at '
                            '${fmtClock(c.timeS)}'
                      : 'Radar now, unavailable. $radarOff',
                  onPressed: radarOff == null ? c.radarNow : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Expanded(
                child: DfsOutlineButton(
                  icon: Icons.skip_next_rounded,
                  label: 'Step 10 s',
                  semanticLabel: 'Step the clock forward ten seconds',
                  onPressed: c.atEnd ? null : c.step,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: DfsOutlineButton(
                  icon: Icons.restart_alt_rounded,
                  label: 'Restart',
                  semanticLabel: 'Back to 0:00, clearing the radar you added',
                  onPressed: c.atStart ? null : c.restart,
                ),
              ),
            ],
          ),
          // Below both button rows, so Step never moves under a finger
          // when this line comes and goes.
          if (radarOff != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            ExcludeSemantics(
              child: Text(
                radarOff,
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          DfsSlider(
            label: 'Clock',
            valueText: '${fmtClock(c.timeS)} of ${fmtClock(kDfsHorizonS)}',
            value: c.timeS,
            min: 0,
            max: kDfsHorizonS,
            divisions: (kDfsHorizonS / kDfsStepSeconds).round(),
            onChanged: c.seek,
            semanticValue: (double v) =>
                '${fmtClock(v)} of ${fmtClock(kDfsHorizonS)}',
          ),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Clock speed',
            semanticLabel: 'Clock speed',
            field: AppSelect<DfsClockSpeed>(
              value: c.speed,
              semanticLabel: 'Clock speed',
              items: <AppSelectItem<DfsClockSpeed>>[
                for (final DfsClockSpeed s in DfsClockSpeed.values)
                  (s, s.label),
              ],
              onChanged: (DfsClockSpeed s) => c.speed = s,
            ),
          ),
          if (reducedMotion) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Reduced motion is on. The clock waits for you: use Step or '
              'drag the clock slider, or press Play.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Readouts ────────────────────────────────────────────────────────────────

class _ReadoutsCard extends StatelessWidget {
  const _ReadoutsCard(this.c);

  final DfsSimulatorController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final DfsRegion region = c.config.region;
    final double now = c.timeS;
    final ApSegment seg = c.segment;
    final bool dfs = placementIsDfs(region, seg.channel);
    final String chLabel =
        '${placementLabel(seg.channel)} at ${seg.channel.widthMHz} MHz'
        '${dfs ? ', DFS' : ''}';

    // AP state.
    final String apValue;
    Color? apColor;
    IconData? apIcon;
    switch (seg.phase) {
      case ApPhase.cac:
        apValue =
            'Listening (CAC) on $chLabel, '
            '${fmtSpan(seg.endS - now)} left';
        apColor = colors.statusWarning;
        apIcon = Icons.hourglass_top_rounded;
      case ApPhase.service:
        apValue = 'Serving on $chLabel';
      case ApPhase.moving:
        apValue = 'Radar: leaving ${placementLabel(seg.channel)}';
        apColor = colors.statusDanger;
        apIcon = Icons.block_rounded;
    }

    // Time to first transmission.
    final double? first = c.run.firstTxS;
    final String firstValue;
    if (first != null && first <= now) {
      firstValue = first == 0 ? '0 s, no CAC needed' : fmtSpan(first);
    } else {
      firstValue = first == null
          ? 'Not within the hour'
          : 'Not yet (CAC running)';
    }

    // Last radar.
    final RadarHit? last = c.lastHit;
    String outageValue = 'No radar yet';
    Color? outageColor;
    IconData? outageIcon;
    if (last != null) {
      final double? resume = last.resumeS;
      if (resume != null && resume <= now) {
        outageValue = '${fmtSpan(last.outageS!)} outage';
      } else {
        outageValue = '${fmtSpan(now - last.timeS)} so far, still out';
      }
      outageColor = colors.statusWarning;
      outageIcon = Icons.warning_amber_rounded;
    }

    // Blocked channels.
    final List<ChannelBlock> blocks = c.blocksNow;

    return DfsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DfsSectionLabel('At ${fmtClock(now)}'),
          const SizedBox(height: AppSpacing.xxs),
          DfsRow(
            label: 'AP',
            value: apValue,
            emphasize: seg.phase == ApPhase.service,
            valueColor: apColor,
            icon: apIcon,
          ),
          DfsRow(label: 'Time to first transmission', value: firstValue),
          DfsRow(label: 'Radar events', value: '${c.hitsSoFar.length}'),
          DfsRow(
            label: 'Outage, last radar',
            value: outageValue,
            valueColor: outageColor,
            icon: outageIcon,
          ),
          DfsRow(
            label: 'Blocked channels',
            value: blocks.isEmpty
                ? 'None'
                : <String>[
                    for (final ChannelBlock b in blocks)
                      '${b.channels.join(', ')}: blocked until '
                          '${fmtClock(b.untilS)} '
                          '(${fmtSpan(b.untilS - now)} left)',
                  ].join('\n'),
            valueColor: blocks.isEmpty ? null : colors.statusDanger,
            icon: blocks.isEmpty ? null : Icons.block_rounded,
          ),
          DfsRow(
            label: 'Clients connected',
            value:
                '${<int>[for (int i = 0; i < c.run.clients.length; i++)
                  if (c.run.clientConnectedAt(i, now)) i].length} '
                'of ${c.run.clients.length}',
          ),
        ],
      ),
    );
  }
}

// ── Log ─────────────────────────────────────────────────────────────────────

class _LogCard extends StatelessWidget {
  const _LogCard(this.c);

  final DfsSimulatorController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final List<RadarHit> hits = c.hitsSoFar;
    final DfsRules rules = c.config.region.rules;
    final double now = c.timeS;
    return DfsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const DfsSectionLabel('Radar log'),
          const SizedBox(height: AppSpacing.xs),
          if (hits.isEmpty)
            DfsNote(
              icon: Icons.radar_rounded,
              message: placementIsDfs(c.config.region, c.segment.channel)
                  ? 'No radar yet. Press Radar now, or set a random radar '
                        'rate below.'
                  : 'No radar yet. The AP is on a non-DFS channel, so it does '
                        'not listen for radar. Start on a DFS channel to try '
                        'it.',
            )
          else
            for (int i = hits.length - 1; i >= 0; i--) ...<Widget>[
              _HitEntry(hit: hits[i], rules: rules, now: now, index: i + 1),
              if (i > 0) Divider(height: AppSpacing.sm, color: colors.border),
            ],
          if (hits.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Newest first.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _HitEntry extends StatelessWidget {
  const _HitEntry({
    required this.hit,
    required this.rules,
    required this.now,
    required this.index,
  });

  final RadarHit hit;
  final DfsRules rules;
  final double now;
  final int index;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final RadarHit h = hit;
    final TextStyle body =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final String nextLabel =
        '${placementLabel(h.next)} at ${h.next.widthMHz} MHz';
    final List<String> lines = <String>[
      if (h.duringCac)
        'Detected during the CAC: the AP had not transmitted yet, so it '
            'left at once.'
      else ...<String>[
        'Normal traffic stopped within ${fmtRule(rules.closingS)} of the '
            'radar'
            '${rules.controlSignalsS != null ? ', plus up to ${fmtRule(rules.controlSignalsS!)} of control signals after' : ' (closing time, in aggregate)'}.',
        'Left the channel ${fmtSpan(h.moveS)} after the radar '
            '(the limit is ${fmtRule(rules.moveS)}).',
      ],
      'Channel ${placementLabel(h.channel)} blocked for '
          '${fmtRule(rules.nonOccupancyS)}, until '
          '${fmtClock(h.timeS + rules.nonOccupancyS)}.',
      if (h.narrowedFromMHz != null)
        'No ${h.narrowedFromMHz} MHz channel was free, so the AP narrowed '
            'to ${h.next.widthMHz} MHz.',
      if (h.noNonDfsAtWidth)
        'No non-DFS ${h.next.widthMHz} MHz channel exists here, so the AP '
            'took a DFS one.',
      h.nextCacS > 0
          ? 'Moved to $nextLabel, a DFS channel: ${fmtRule(h.nextCacS)} CAC '
                'before it can serve. Clients drop and rejoin after.'
          : 'Moved to $nextLabel, not DFS: it serves at once and clients '
                'follow the channel switch announcement.',
      if (h.resumeS != null && h.resumeS! <= now)
        'Service back at ${fmtClock(h.resumeS!)}: '
            '${fmtSpan(h.outageS!)} outage.'
      else
        'Service not back yet.',
    ];
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Radar $index at ${fmtClock(h.timeS)} on '
            '${placementLabel(h.channel)}'
            '${h.source == RadarSource.random ? ' (random)' : ''}',
            style: text.bodyMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          for (final String l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(l, style: body),
            ),
        ],
      ),
    );
  }
}

// ── Setup ───────────────────────────────────────────────────────────────────

class _SetupCard extends StatelessWidget {
  const _SetupCard(this.c);

  final DfsSimulatorController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final DfsConfig cfg = c.config;
    final BondedChannel start = c.startPlacement;
    String startLabel(BondedChannel p) {
      final double cac = cacSecondsFor(cfg.region, p);
      return '${placementLabel(p)}'
          '${cac == 0 ? ', not DFS' : ', DFS, CAC ${fmtRule(cac)}'}';
    }

    return DfsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const DfsSectionLabel('Setup'),
          const SizedBox(height: AppSpacing.xs),
          AppToggle<DfsRegion>(
            label: 'Region',
            semanticLabel: 'Region',
            value: cfg.region,
            expand: true,
            items: <AppToggleItem<DfsRegion>>[
              for (final DfsRegion r in DfsRegion.values) (r, r.label),
            ],
            onChanged: (DfsRegion r) => c.region = r,
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Channel width',
            semanticLabel: 'Channel width',
            field: AppSelect<int>(
              value: cfg.widthMHz,
              semanticLabel: 'Channel width',
              items: <AppSelectItem<int>>[
                for (final int w in kDfsWidths) (w, '$w MHz'),
              ],
              onChanged: (int w) => c.widthMHz = w,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Starting channel',
            semanticLabel: 'Starting channel',
            // Keyed by the lowest 20 MHz channel: BondedChannel has no
            // value equality.
            field: AppSelect<int>(
              value: start.components.first,
              semanticLabel: 'Starting channel',
              items: <AppSelectItem<int>>[
                for (final BondedChannel p in c.startChoices)
                  (p.components.first, startLabel(p)),
              ],
              onChanged: (int first) => c.start = c.startChoices.firstWhere(
                (BondedChannel p) => p.components.first == first,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Changing the setup reruns the hour from 0:00 with the same '
            'radar times.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<NewChannelPolicy>(
            label: 'After radar',
            semanticLabel: 'New channel after radar',
            value: cfg.policy,
            expand: true,
            items: <AppToggleItem<NewChannelPolicy>>[
              for (final NewChannelPolicy p in NewChannelPolicy.values)
                (p, p.label),
            ],
            onChanged: (NewChannelPolicy p) => c.policy = p,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            cfg.policy.description,
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Random radar',
            semanticLabel: 'Random radar rate',
            field: AppSelect<double>(
              value: cfg.radarPerHour,
              semanticLabel: 'Random radar rate',
              items: <AppSelectItem<double>>[
                for (final double r in kRadarRates)
                  (r, r == 0 ? 'Off' : '${r.toStringAsFixed(0)} per hour'),
              ],
              onChanged: (double r) => c.radarPerHour = r,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          DfsOutlineButton(
            icon: Icons.shuffle_rounded,
            label: 'New random pattern',
            semanticLabel: 'New random radar pattern',
            onPressed: cfg.radarPerHour == 0 ? null : c.newRandomRadar,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Random radar is acted on only while the AP is on a DFS channel.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ── Rules ───────────────────────────────────────────────────────────────────

class _RulesCard extends StatelessWidget {
  const _RulesCard(this.c);

  final DfsSimulatorController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final DfsConfig cfg = c.config;
    final DfsRegion region = cfg.region;
    final DfsRules r = region.rules;
    final bool us = region == DfsRegion.us;
    final double thr = detectionThresholdDbm(region, cfg.eirpDbm, cfg.widthMHz);
    final double psd = eirpPsdDbmPerMHz(cfg.eirpDbm, cfg.widthMHz);
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);
    return DfsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DfsSectionLabel('The rules, ${region.label}'),
          const SizedBox(height: AppSpacing.xxs),
          DfsRow(
            label: 'Channel availability check',
            value: us
                ? '${fmtRule(r.cacS)} on every DFS channel'
                : '${fmtRule(r.cacS)}; ${fmtRule(r.weatherCacS)} in '
                      '5600-5650 MHz (120, 124, 128)',
          ),
          DfsRow(
            label: 'Channel closing time',
            value: us
                ? '${fmtRule(r.closingS)} of normal traffic, plus '
                      '${fmtRule(r.controlSignalsS!)} of control signals'
                : '${fmtRule(r.closingS)} of transmissions in aggregate',
          ),
          DfsRow(label: 'Channel move time', value: fmtRule(r.moveS)),
          DfsRow(
            label: 'Non-occupancy period',
            value: fmtRule(r.nonOccupancyS),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            us
                ? 'Source: 47 CFR 15.407(h)(2), read in the primary text. The '
                      '60 ms control-signal figure comes from one secondhand '
                      'source (a test lab\'s transcription of FCC KDB 905462 '
                      'D02), not the FCC document itself. The 10-minute CAC '
                      'is ETSI only.'
                : 'Source: ETSI EN 301 893 V2.1.1 Table D.1, read in the '
                      'primary text.',
            style: note,
          ),
          const SizedBox(height: AppSpacing.sm),
          const DfsSectionLabel('Radar detection threshold'),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'AP EIRP',
            semanticLabel: 'AP EIRP',
            field: AppSelect<double>(
              value: cfg.eirpDbm,
              semanticLabel: 'AP EIRP',
              items: <AppSelectItem<double>>[
                for (final double e in kDfsEirpChoices)
                  (e, '${e.toStringAsFixed(0)} dBm'),
              ],
              onChanged: (double e) => c.eirpDbm = e,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          DfsRow(
            label: 'EIRP density at ${cfg.widthMHz} MHz',
            value: '${psd.toStringAsFixed(1)} dBm/MHz',
          ),
          DfsRow(
            label: 'Threshold',
            value: '${thr.toStringAsFixed(1)} dBm',
            emphasize: true,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            us
                ? 'FCC: -64 dBm for an EIRP of 200 mW (23 dBm) or more; '
                      '-62 dBm below 200 mW with less than 10 dBm/MHz. For '
                      'context only: the simulation does not model radar '
                      'signal levels.'
                : 'ETSI: -62 + 10 - PSD + G dBm, never below -64 dBm, with G '
                      'the receive antenna gain (0 dBi here). For context '
                      'only: the simulation does not model radar signal '
                      'levels.',
            style: note,
          ),
        ],
      ),
    );
  }
}
