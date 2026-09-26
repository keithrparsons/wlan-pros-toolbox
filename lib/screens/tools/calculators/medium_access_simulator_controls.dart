// Controls for the Medium Access Simulator, over one
// MediumAccessSimulatorController:
//   - MediumAccessTransport  Play, Step, Reset, speed, zoom
//   - MediumAccessResults    the results card (phone; the presenter shows a
//                            results strip on the stage instead)
//   - MediumAccessStations   the stations and their class and load
//   - MediumAccessRules      channel access, hidden node, RTS/CTS, frame
//   - MediumAccessAbout      what the model covers
// The phone screen stacks them around the stage in the original order.
//
// PRESENTER. The panel holds Transport, Stations and Rules. What an
// instructor changes mid-lesson stays in view: play, step, speed, adding and
// removing stations, DCF or EDCA, hidden node, RTS/CTS, frame size and rate.
// What they set once sits behind a disclosure: each station's class and load,
// the per-station table, the frame timing and the EDCA parameters.
//
// States (SOP-007 §5) are the screen's, unchanged: fresh (clock at 0,
// paused), running, paused, disabled (Add at 10, Remove at 1, class selects
// in Legacy DCF, hidden node with one station), reduced motion (starts
// paused; Step works), interactive (themed controls, global focus ring).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/medium_access_engine.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'medium_access_simulator_controller.dart';
import 'medium_access_simulator_parts.dart';
import 'medium_access_timeline.dart';

typedef _C = MediumAccessSimulatorController;

/// Rebuilds [builder] whenever the controller changes.
class _Listen extends StatelessWidget {
  const _Listen({required this.controller, required this.builder});

  final MediumAccessSimulatorController controller;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (BuildContext context, _) => builder(context),
  );
}

// ── Transport ─────────────────────────────────────────────────────────────

class MediumAccessTransport extends StatelessWidget {
  const MediumAccessTransport({super.key, required this.controller});

  final MediumAccessSimulatorController controller;

  @override
  Widget build(BuildContext context) =>
      _Listen(controller: controller, builder: _build);

  Widget _build(BuildContext context) {
    final MaUi ui = MaUi.of(context);
    final AppColorScheme colors = ui.colors;
    final _C c = controller;
    final bool presenting = PresenterMode.isActive(context);
    final bool reducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final Widget play = Semantics(
      button: true,
      label: c.playing ? 'Pause simulation' : 'Play simulation',
      excludeSemantics: true,
      child: FilledButton.icon(
        onPressed: c.togglePlay,
        icon: Icon(c.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        label: Text(c.playing ? 'Pause' : 'Play'),
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
          textStyle: ui.text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
    final Widget step = ui.outlineButton(
      icon: Icons.skip_next_rounded,
      label: 'Step 1 slot',
      semanticLabel: 'Step one 9 microsecond slot',
      onPressed: c.step,
    );
    final Widget reset = ui.outlineButton(
      icon: Icons.restart_alt_rounded,
      label: 'Reset',
      semanticLabel: 'Reset the simulation to time zero',
      onPressed: c.reset,
    );

    return ui.card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!presenting) ...<Widget>[
            Text(
              'Only one station talks at a time. Each waits for a quiet '
              'medium, counts down a random number of 9 µs slots, and '
              'transmits at zero. Two zeros in the same slot is a collision.',
              style: ui.text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(width: double.infinity, child: play),
            const SizedBox(height: AppSpacing.xs),
          ] else ...<Widget>[play, const SizedBox(height: AppSpacing.xs)],
          Row(
            children: <Widget>[
              Expanded(child: step),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: reset),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ui.labeledSelect<SimSpeed>(
            label: 'Speed (air time per real second)',
            value: c.speed,
            items: <AppSelectItem<SimSpeed>>[
              for (final SimSpeed s in SimSpeed.values) (s, s.label),
            ],
            onChanged: c.setSpeed,
          ),
          // Presenter: the zoom sits on the stage, over the timeline it
          // changes.
          if (!presenting) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            AppToggle<TimelineZoom>(
              label: 'Zoom',
              value: c.zoom,
              expand: true,
              items: <AppToggleItem<TimelineZoom>>[
                for (final TimelineZoom z in TimelineZoom.values) (z, z.label),
              ],
              onChanged: c.setZoom,
            ),
          ],
          if (reducedMotion) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Reduced motion is on. The simulation waits for you: use Step '
              'to move one slot at a time, or Play at the slowest speed.',
              style: ui.text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Results (phone) ───────────────────────────────────────────────────────

class MediumAccessResults extends StatelessWidget {
  const MediumAccessResults({super.key, required this.controller});

  final MediumAccessSimulatorController controller;

  @override
  Widget build(BuildContext context) =>
      _Listen(controller: controller, builder: _build);

  Widget _build(BuildContext context) {
    final MaUi ui = MaUi.of(context);
    final AppColorScheme colors = ui.colors;
    final MediumAccessStats s = controller.engine.stats;
    final bool fresh = s.elapsedUs == 0;
    String v(String value) => fresh ? '--' : value;

    return ui.card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ui.sectionTitle('Results'),
          const SizedBox(height: AppSpacing.xs),
          if (fresh)
            Text(
              'Press Play or Step to start the clock.',
              style: ui.text.bodySmall?.copyWith(color: colors.textTertiary),
            )
          else
            Text(
              'Over ${_C.fmtMs(s.elapsedUs)} of simulated air time.',
              style: ui.text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text('Delivered throughput', style: ui.labelStyle),
          Text(
            v('${s.throughputMbps.toStringAsFixed(1)} Mbps'),
            style: ui.mono.outputLarge.copyWith(color: colors.textAccent),
          ),
          const SizedBox(height: AppSpacing.xs),
          ui.statRow(
            'Airtime busy',
            v('${s.utilizationPercent.toStringAsFixed(1)} %'),
          ),
          ui.statRow(
            'Collision rate',
            v(
              '${s.collisionPercent.toStringAsFixed(1)} % '
              '(${s.failedAttempts} of ${s.attempts})',
            ),
          ),
          ui.statRow('Delivered / dropped', v('${s.delivered} / ${s.dropped}')),
          const SizedBox(height: AppSpacing.sm),
          Text('Average access delay', style: ui.labelStyle),
          const SizedBox(height: AppSpacing.xxs),
          ..._delayRows(ui, controller, s),
          const SizedBox(height: AppSpacing.sm),
          Text('Per station', style: ui.labelStyle),
          const SizedBox(height: AppSpacing.xxs),
          _StationTable(controller: controller),
        ],
      ),
    );
  }
}

List<Widget> _delayRows(MaUi ui, _C c, MediumAccessStats s) {
  String fmt(AccessDelayStat? d) {
    final double? us = d?.meanUs;
    if (us == null) return 'no deliveries yet';
    return '${(us / 1000).toStringAsFixed(2)} ms';
  }

  if (c.dcf) {
    int frames = 0, total = 0;
    for (final AccessDelayStat d in s.accessDelay.values) {
      frames += d.frames;
      total += d.totalUs;
    }
    return <Widget>[
      ui.statRow(
        'All stations (DCF)',
        fmt(AccessDelayStat(frames: frames, totalUs: total)),
      ),
    ];
  }
  final List<AccessCategory> inUse = <AccessCategory>[
    for (final AccessCategory ac in AccessCategory.values)
      if (c.stations.any((StationConfig sc) => sc.accessCategory == ac)) ac,
  ];
  return <Widget>[
    for (final AccessCategory ac in inUse)
      ui.statRow(ac.label, fmt(s.accessDelay[ac])),
  ];
}

class _StationTable extends StatelessWidget {
  const _StationTable({required this.controller});

  final MediumAccessSimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final MaUi ui = MaUi.of(context);
    final AppColorScheme colors = ui.colors;
    final TextStyle head = ui.labelStyle;
    final TextStyle cell = ui.mono.inlineCode.copyWith(
      fontSize: AppTextSize.caption,
      color: colors.textPrimary,
    );
    Widget pad(Widget w) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: w,
    );
    return Table(
      columnWidths: const <int, TableColumnWidth>{
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(1.3),
        4: FlexColumnWidth(1.1),
      },
      children: <TableRow>[
        TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          children: <Widget>[
            for (final String h in <String>[
              'Station',
              'CW',
              'Backoff',
              'Delivered',
              'Dropped',
            ])
              pad(Text(h, style: head)),
          ],
        ),
        for (final StationSnapshot st in controller.engine.stations)
          TableRow(
            children: <Widget>[
              pad(Text('${st.letter} ${controller.acShort(st)}', style: cell)),
              pad(Text('${st.cw}', style: cell)),
              pad(
                Text(st.backoff == null ? '-' : '${st.backoff}', style: cell),
              ),
              pad(Text('${st.delivered}', style: cell)),
              pad(Text('${st.dropped}', style: cell)),
            ],
          ),
      ],
    );
  }
}

// ── Stations ──────────────────────────────────────────────────────────────

class MediumAccessStations extends StatelessWidget {
  const MediumAccessStations({super.key, required this.controller});

  final MediumAccessSimulatorController controller;

  @override
  Widget build(BuildContext context) =>
      _Listen(controller: controller, builder: _build);

  Widget _build(BuildContext context) {
    final MaUi ui = MaUi.of(context);
    final AppColorScheme colors = ui.colors;
    final _C c = controller;
    final int n = c.stations.length;
    final bool dcf = c.dcf;
    final bool presenting = PresenterMode.isActive(context);

    final Widget add = ui.outlineButton(
      icon: Icons.add_rounded,
      label: 'Add station',
      semanticLabel: c.canAddStation
          ? 'Add station ${stationLetter(n)}'
          : 'Add station, unavailable: 10 is the maximum',
      onPressed: c.canAddStation ? c.addStation : null,
    );
    final String title = 'Stations ($n of ${MediumAccessConfig.maxStations})';
    final String note = dcf
        ? 'Legacy DCF: every station uses DIFS and a contention window of 15 '
              'to 1023. Switch to EDCA below to give stations a traffic class.'
        : 'Each station sends one class of traffic to the AP.';

    if (presenting) {
      return ui.card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ui.sectionTitle(title),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: <Widget>[
                Expanded(
                  child: ui.outlineButton(
                    icon: Icons.remove_rounded,
                    label: 'Remove',
                    semanticLabel: c.canRemoveStation
                        ? 'Remove station ${stationLetter(n - 1)}'
                        : 'Remove station, unavailable: at least one is '
                              'required',
                    onPressed: c.canRemoveStation
                        ? () => c.removeStation(n - 1)
                        : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: add),
              ],
            ),
            PresenterDisclosure(
              title: dcf
                  ? 'Offered load per station'
                  : 'Traffic class and load per station',
              children: <Widget>[
                Text(
                  note,
                  style: ui.text.bodySmall?.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
                for (int i = 0; i < n; i++) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  _StationRow(controller: c, index: i),
                ],
              ],
            ),
            PresenterDisclosure(
              title: 'Per-station table',
              children: <Widget>[_StationTable(controller: c)],
            ),
          ],
        ),
      );
    }

    return ui.card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ui.sectionTitle(title),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            note,
            style: ui.text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          for (int i = 0; i < n; i++) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _StationRow(controller: c, index: i),
          ],
          const SizedBox(height: AppSpacing.sm),
          add,
        ],
      ),
    );
  }
}

class _StationRow extends StatelessWidget {
  const _StationRow({required this.controller, required this.index});

  final MediumAccessSimulatorController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final MaUi ui = MaUi.of(context);
    final AppColorScheme colors = ui.colors;
    final _C c = controller;
    final int i = index;
    final bool dcf = c.dcf;
    final StationConfig sc = c.stations[i];
    final String letter = stationLetter(i);
    final bool canRemove = c.canRemoveStation;
    final String? group = c.config.hiddenNode
        ? (i.isEven ? 'group 1' : 'group 2')
        : null;

    final Widget acSelect = ui.labeledSelect<AccessCategory>(
      label: 'Access category',
      semanticLabel: 'Station $letter access category',
      value: sc.accessCategory,
      enabled: !dcf,
      items: <AppSelectItem<AccessCategory>>[
        for (final AccessCategory ac in AccessCategory.values)
          (ac, '${ac.label} (${ac.shortLabel})'),
      ],
      onChanged: (AccessCategory ac) => c.setAccessCategory(i, ac),
    );
    final Widget loadSelect = ui.labeledSelect<double?>(
      label: 'Offered load',
      semanticLabel: 'Station $letter offered load',
      value: sc.framesPerSecond,
      items: <AppSelectItem<double?>>[
        for (final double? l in kMediumAccessLoads)
          (l, l == null ? 'Always has a frame' : '${l.round()} frames/s'),
      ],
      onChanged: (double? l) => c.setLoad(i, l),
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  group == null
                      ? 'Station $letter'
                      : 'Station $letter · $group',
                  style: ui.text.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: canRemove ? () => c.removeStation(i) : null,
                tooltip: canRemove
                    ? 'Remove station $letter'
                    : 'At least one station is required',
                icon: const Icon(Icons.remove_circle_outline_rounded),
                color: colors.textSecondary,
                disabledColor: colors.textDisabled,
              ),
            ],
          ),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              if (box.maxWidth < AppSpacing.gridTwoColBreakpoint) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    acSelect,
                    const SizedBox(height: AppSpacing.xs),
                    loadSelect,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(child: acSelect),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: loadSelect),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Medium and rules ──────────────────────────────────────────────────────

class MediumAccessRules extends StatelessWidget {
  const MediumAccessRules({super.key, required this.controller});

  final MediumAccessSimulatorController controller;

  @override
  Widget build(BuildContext context) =>
      _Listen(controller: controller, builder: _build);

  Widget _build(BuildContext context) {
    final MaUi ui = MaUi.of(context);
    final AppColorScheme colors = ui.colors;
    final _C c = controller;
    final bool presenting = PresenterMode.isActive(context);
    final bool oneStation = c.stations.length < 2;
    final int dataUs = OfdmTiming.frameDurationUs(c.frameBytes, c.rateMbps);

    final Widget sizeRate = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final Widget size = ui.labeledSelect<int>(
          label: 'Frame size',
          value: c.frameBytes,
          items: <AppSelectItem<int>>[
            for (final int b in kMediumAccessFrameSizes) (b, '$b bytes'),
          ],
          onChanged: c.setFrameBytes,
        );
        final Widget rate = ui.labeledSelect<int>(
          label: 'PHY rate',
          value: c.rateMbps,
          items: <AppSelectItem<int>>[
            for (final int r in OfdmTiming.phyRatesMbps) (r, '$r Mbps'),
          ],
          onChanged: c.setRate,
        );
        if (box.maxWidth < AppSpacing.gridTwoColBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              size,
              const SizedBox(height: AppSpacing.sm),
              rate,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(child: size),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: rate),
          ],
        );
      },
    );

    final Widget timing = Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ui.statRow('Data frame', '$dataUs µs'),
          ui.statRow(
            'ACK / RTS / CTS (24 Mbps)',
            '${OfdmTiming.ackUs} µs each',
          ),
          ui.statRow('Slot / SIFS', '9 µs / 16 µs'),
          ui.statRow(
            'DIFS / EIFS',
            '${OfdmTiming.difsUs} µs / ${OfdmTiming.eifsUs} µs',
          ),
          const SizedBox(height: AppSpacing.xxs),
          SelectableText(
            '20 + 4 x ceil((16 + 8 x ${c.frameBytes} + 6) / '
            '${OfdmTiming.dataBitsPerSymbol(c.rateMbps)}) = $dataUs µs',
            style: ui.mono.inlineCode.copyWith(
              fontSize: AppTextSize.caption,
              color: colors.textTertiary,
            ),
          ),
        ],
      ),
    );

    return ui.card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ui.sectionTitle('Medium and rules'),
          SizedBox(height: presenting ? AppSpacing.xs : AppSpacing.sm),
          AppToggle<AccessMode>(
            label: 'Channel access',
            value: c.mode,
            expand: true,
            items: const <AppToggleItem<AccessMode>>[
              (AccessMode.dcf, 'Legacy DCF'),
              (AccessMode.edca, 'EDCA'),
            ],
            onChanged: c.setMode,
          ),
          SizedBox(height: presenting ? AppSpacing.xs : AppSpacing.sm),
          ui.switchRow(
            title: 'Hidden node',
            // Presenter: the lane labels name each station's group.
            subtitle: oneStation
                ? 'Needs two or more stations.'
                : presenting
                ? null
                : 'Stations A, C, E ... cannot hear B, D, F ... Everyone '
                      'still reaches the AP.',
            value: c.hidden && !oneStation,
            onChanged: oneStation ? null : c.setHidden,
          ),
          ui.switchRow(
            title: 'RTS/CTS',
            subtitle: presenting
                ? null
                : 'Ask first: RTS, CTS, data, ACK. Anyone who hears the CTS '
                      'sets its NAV and stays quiet.',
            value: c.rts,
            onChanged: c.setRts,
          ),
          if (!presenting) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            sizeRate,
          ],
          if (presenting)
            PresenterDisclosure(
              title:
                  'Frame size ${c.frameBytes} bytes at ${c.rateMbps} Mbps'
                  '${c.dcf ? '' : ', EDCA parameters'}',
              children: <Widget>[
                sizeRate,
                const SizedBox(height: AppSpacing.sm),
                timing,
                if (!c.dcf) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  const _EdcaTable(),
                ],
              ],
            )
          else ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            timing,
            if (!c.dcf) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              const _EdcaTable(),
            ],
          ],
        ],
      ),
    );
  }
}

class _EdcaTable extends StatelessWidget {
  const _EdcaTable();

  @override
  Widget build(BuildContext context) {
    final MaUi ui = MaUi.of(context);
    final AppColorScheme colors = ui.colors;
    final TextStyle head = ui.labelStyle;
    final TextStyle cell = ui.mono.inlineCode.copyWith(
      fontSize: AppTextSize.caption,
      color: colors.textPrimary,
    );
    Widget pad(Widget w) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: w,
    );
    return Table(
      children: <TableRow>[
        TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          children: <Widget>[
            for (final String h in <String>['Class', 'AIFS', 'CWmin', 'CWmax'])
              pad(Text(h, style: head)),
          ],
        ),
        for (final AccessCategory ac in AccessCategory.values)
          TableRow(
            children: <Widget>[
              pad(Text(ac.shortLabel, style: cell)),
              pad(Text('${ac.params.aifsUs} µs', style: cell)),
              pad(Text('${ac.params.cwMin}', style: cell)),
              pad(Text('${ac.params.cwMax}', style: cell)),
            ],
          ),
      ],
    );
  }
}

// ── About ─────────────────────────────────────────────────────────────────

class MediumAccessAbout extends StatelessWidget {
  const MediumAccessAbout({super.key});

  @override
  Widget build(BuildContext context) {
    final MaUi ui = MaUi.of(context);
    final TextStyle body =
        ui.text.bodySmall?.copyWith(color: ui.colors.textSecondary) ??
        TextStyle(color: ui.colors.textSecondary);
    return ui.card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ui.sectionTitle('What this models'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Timing is legacy OFDM (802.11a/g, 5 GHz): 9 µs slots, 16 µs '
            'SIFS, a 20 µs preamble. Newer PHYs have longer preambles and '
            'aggregate frames, and the lesson about contention is the same.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Every station sends to the AP; the AP answers with ACK or CTS. '
            'Control frames go at 24 Mbps. A frame is lost when anything '
            'else is on the air at the AP during it. After 7 failed tries a '
            'frame is dropped. Access delay runs from the moment a frame '
            'reaches the front of its queue to its ACK.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Not modeled: rate adaptation, the AP sending its own data, '
            'frame aggregation, and the NAV reset rule. Runs are seeded, so '
            'Reset replays the same run.',
            style: body,
          ),
        ],
      ),
    );
  }
}
