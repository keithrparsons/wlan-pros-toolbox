// RoamingWalkControls: the inputs-and-readouts half of the Roaming Walk.
//
// Takes the shared RoamingWalkController and a set of parts to show, so the
// phone layout can put playback and readouts right under the stage and the
// setup cards after them, while a presenter layout shows every part in one
// column beside the stage. No part draws a plot; RoamingWalkStage owns those.
//
// Control types follow GL-003 §8.14: client preset, path, AP count, AP to
// move and playback speed are Selects (4 or more options); band is a
// three-option AppToggle. Status hues are verdicts only (§8.13 rule 6):
// warning amber on a ping-pong count above zero and on time spent below
// -70 dBm, each with its word and an icon.
//
// PRESENTER (spec 00): inside a PresenterLayout the panel keeps playback, the
// client's trigger and delta, and the three roam-cost switches in view; the
// live readouts are on the stage, and the roam log, the illustrative timings
// and the floor setup fold into PresenterDisclosures.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/roaming_walk_engine.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter.dart';
import '../labeled_field.dart';
import 'roaming_walk_controller.dart';
import 'roaming_walk_palette.dart';
import 'roaming_walk_parts.dart';

/// The groups RoamingWalkControls can show.
enum RoamControlPart {
  /// Play, pause, step, restart, scrub and speed.
  transport,

  /// Roams, ping-pongs, time below -70 dBm, gap time and the roam log.
  readouts,

  /// Client preset, trigger and delta.
  client,

  /// 802.11k, PMK caching, FT and the illustrative timings.
  roamCost,

  /// Band, power, path loss, shadowing, APs and path.
  floor,
}

/// Roam-log rows shown before "Show all".
const int kRoamLogShort = 5;

class RoamingWalkControls extends StatelessWidget {
  const RoamingWalkControls({
    super.key,
    required this.controller,
    this.parts = const <RoamControlPart>{
      RoamControlPart.transport,
      RoamControlPart.readouts,
      RoamControlPart.client,
      RoamControlPart.roamCost,
      RoamControlPart.floor,
    },
  });

  final RoamingWalkController controller;
  final Set<RoamControlPart> parts;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final RoamingWalkController c = controller;
        if (PresenterMode.isActive(context)) return _PresenterPanel(c);
        final List<Widget> cards = <Widget>[
          if (parts.contains(RoamControlPart.transport)) _TransportCard(c),
          if (parts.contains(RoamControlPart.readouts)) _ReadoutsCard(c),
          if (parts.contains(RoamControlPart.client)) _ClientCard(c),
          if (parts.contains(RoamControlPart.roamCost)) _RoamCostCard(c),
          if (parts.contains(RoamControlPart.floor)) _FloorSetupCard(c),
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

  final RoamingWalkController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool reducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final RoamWalkConfig cfg = c.config;
    final ClientPreset? p = c.preset;
    final double dur = c.result.durationS;
    final RoamCost first = cfg.costFor(cfg.authMethodFor(joinedBefore: false));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        RwCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      onPressed: c.drawing ? null : c.togglePlay,
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
                        disabledBackgroundColor: colors.disabledFill,
                        disabledForegroundColor: colors.textDisabled,
                        minimumSize: const Size.fromHeight(
                          AppSpacing.minTouchTarget,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    flex: 2,
                    child: RwOutlineButton(
                      icon: Icons.skip_next_rounded,
                      label: 'Step',
                      semanticLabel: 'Step the walk forward one second',
                      onPressed: c.atEnd || c.drawing ? null : c.step,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton(
                    onPressed: c.atStart ? null : c.restart,
                    tooltip: 'Back to the start of the walk (R)',
                    icon: const Icon(Icons.restart_alt_rounded),
                    color: colors.textAccent,
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: RwSlider(
                      label: 'Walk time',
                      valueText:
                          '${c.timeS.toStringAsFixed(1)} of '
                          '${dur.toStringAsFixed(1)} s',
                      value: c.timeS,
                      min: 0,
                      max: dur,
                      divisions: (dur / kRoamSampleSeconds).round().clamp(
                        1,
                        100000,
                      ),
                      onChanged: c.seek,
                      semanticValue: (double v) =>
                          '${v.toStringAsFixed(1)} of '
                          '${dur.toStringAsFixed(1)} seconds',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  SizedBox(
                    width: 120,
                    child: AppSelect<RoamPlaySpeed>(
                      value: c.speed,
                      semanticLabel: 'Playback speed',
                      items: <AppSelectItem<RoamPlaySpeed>>[
                        for (final RoamPlaySpeed s in RoamPlaySpeed.values)
                          (s, s == RoamPlaySpeed.x1 ? '1x' : s.label),
                      ],
                      onChanged: (RoamPlaySpeed s) => c.speed = s,
                    ),
                  ),
                ],
              ),
              if (reducedMotion)
                Text(
                  'Reduced motion is on: nothing moves until you press Play.',
                  style: text.bodySmall?.copyWith(color: colors.textTertiary),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        RwCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LabeledField(
                label: 'Client',
                semanticLabel: 'Client preset',
                field: AppSelect<int>(
                  value: p?.index ?? ClientPreset.values.length,
                  semanticLabel: 'Client preset',
                  items: <AppSelectItem<int>>[
                    for (final ClientPreset x in ClientPreset.values)
                      (x.index, x.label),
                    if (p == null) (ClientPreset.values.length, 'Custom'),
                  ],
                  onChanged: (int i) {
                    if (i < ClientPreset.values.length) {
                      c.applyPreset(ClientPreset.values[i]);
                    }
                  },
                ),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: RwSlider(
                      label: 'Trigger',
                      valueText: '${cfg.triggerDbm.toStringAsFixed(0)} dBm',
                      value: cfg.triggerDbm,
                      min: -90,
                      max: -55,
                      divisions: 35,
                      onChanged: (double v) => c.triggerDbm = v,
                      semanticValue: (double v) =>
                          '${v.toStringAsFixed(0)} dBm',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: RwSlider(
                      label: 'Delta',
                      valueText: '${cfg.deltaDb.toStringAsFixed(0)} dB',
                      value: cfg.deltaDb,
                      min: 0,
                      max: 20,
                      divisions: 20,
                      onChanged: (double v) => c.deltaDb = v,
                      semanticValue: (double v) => '${v.toStringAsFixed(0)} dB',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        RwCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              RwSwitchRow(
                title: '802.11k neighbor list',
                subtitle: '',
                value: cfg.use11k,
                onChanged: (bool v) => c.use11k = v,
              ),
              RwSwitchRow(
                title: 'PMK caching',
                subtitle: '',
                value: cfg.usePmkCaching,
                onChanged: (bool v) => c.usePmkCaching = v,
              ),
              RwSwitchRow(
                title: '802.11r fast transition (FT)',
                subtitle: '',
                value: cfg.useFt,
                onChanged: (bool v) => c.useFt = v,
              ),
              // Short values so each fits one line; the timings fold has
              // the long form.
              RwRow(
                label: 'Scan',
                value: '${fmtMs(first.scanMs)}, ${first.scanChannels} ch',
              ),
              RwRow(
                label: 'Authenticate',
                value: '${fmtMs(first.authMs)}, ${first.method.label}',
              ),
            ],
          ),
        ),
        PresenterDisclosure(
          title: 'Roam log and totals',
          children: <Widget>[_ReadoutsCard(c)],
        ),
        PresenterDisclosure(
          title: 'Roam timings (illustrative)',
          children: <Widget>[_RoamCostCard(c)],
        ),
        PresenterDisclosure(
          title: 'The floor and the walk',
          children: <Widget>[_FloorSetupCard(c)],
        ),
      ],
    );
  }
}

// ── Transport ───────────────────────────────────────────────────────────────

class _TransportCard extends StatelessWidget {
  const _TransportCard(this.c);

  final RoamingWalkController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool reducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final double dur = c.result.durationS;
    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: double.infinity,
            child: Semantics(
              button: true,
              label: c.playing
                  ? 'Pause the walk'
                  : c.atEnd
                  ? 'Play the walk again from the start'
                  : 'Play the walk',
              excludeSemantics: true,
              child: FilledButton.icon(
                onPressed: c.drawing ? null : c.togglePlay,
                icon: Icon(
                  c.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
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
                  disabledBackgroundColor: colors.disabledFill,
                  disabledForegroundColor: colors.textDisabled,
                  minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
                  textStyle: text.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Expanded(
                child: RwOutlineButton(
                  icon: Icons.skip_next_rounded,
                  label: 'Step 1 s',
                  semanticLabel: 'Step the walk forward one second',
                  onPressed: c.atEnd || c.drawing ? null : c.step,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: RwOutlineButton(
                  icon: Icons.restart_alt_rounded,
                  label: 'Restart',
                  semanticLabel: 'Back to the start of the walk',
                  onPressed: c.atStart ? null : c.restart,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          RwSlider(
            label: 'Walk time',
            valueText:
                '${c.timeS.toStringAsFixed(1)} of ${dur.toStringAsFixed(1)} s',
            value: c.timeS,
            min: 0,
            max: dur,
            divisions: (dur / kRoamSampleSeconds).round().clamp(1, 100000),
            onChanged: c.seek,
            semanticValue: (double v) =>
                '${v.toStringAsFixed(1)} of ${dur.toStringAsFixed(1)} seconds',
          ),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Speed',
            semanticLabel: 'Playback speed',
            field: AppSelect<RoamPlaySpeed>(
              value: c.speed,
              semanticLabel: 'Playback speed',
              items: <AppSelectItem<RoamPlaySpeed>>[
                for (final RoamPlaySpeed s in RoamPlaySpeed.values)
                  (s, s.label),
              ],
              onChanged: (RoamPlaySpeed s) => c.speed = s,
            ),
          ),
          if (reducedMotion) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Reduced motion is on. The walk waits for you: use Step or '
              'drag the walk-time slider, or press Play.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Readouts ────────────────────────────────────────────────────────────────

class _ReadoutsCard extends StatefulWidget {
  const _ReadoutsCard(this.c);

  final RoamingWalkController c;

  @override
  State<_ReadoutsCard> createState() => _ReadoutsCardState();
}

class _ReadoutsCardState extends State<_ReadoutsCard> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final RoamingWalkController c = widget.c;
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final RoamTotals t = c.totals;
    final List<RoamEvent> shown = c.result.events
        .where((RoamEvent e) => e.sample <= c.sample)
        .toList();
    final List<RoamEvent> rows = _all || shown.length <= kRoamLogShort
        ? shown
        : shown.sublist(shown.length - kRoamLogShort);
    final bool pp = t.pingPongs > 0;
    final bool weak = t.secondsBelowWeak > 0;
    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          RwSectionLabel(
            c.atEnd
                ? 'The whole walk'
                : 'So far (${c.timeS.toStringAsFixed(1)} s)',
          ),
          const SizedBox(height: AppSpacing.xxs),
          RwRow(label: 'Roams', value: '${t.roams}', emphasize: true),
          RwRow(
            label: 'Ping-pongs',
            value: pp ? '${t.pingPongs}, ping-pong: back within 5 s' : '0',
            valueColor: pp ? colors.statusWarning : null,
            icon: pp ? Icons.warning_amber_rounded : null,
          ),
          RwRow(
            label: 'Time below -70 dBm',
            value: weak
                ? '${t.secondsBelowWeak.toStringAsFixed(1)} s, weak signal'
                : '0.0 s',
            valueColor: weak ? colors.statusWarning : null,
            icon: weak ? Icons.warning_amber_rounded : null,
          ),
          RwRow(label: 'Total roam gap', value: fmtMs(t.gapMs)),
          const SizedBox(height: AppSpacing.xs),
          const RwSectionLabel('Roam log'),
          const SizedBox(height: AppSpacing.xxs),
          if (shown.isEmpty)
            Text(
              c.atStart
                  ? 'No roams yet. Press Play or Step.'
                  : 'No roams yet: the client is holding its AP.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            )
          else ...<Widget>[
            for (final RoamEvent e in rows) _LogRow(e),
            if (shown.length > kRoamLogShort)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _all = !_all),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textAccent,
                    minimumSize: const Size(0, AppSpacing.minTouchTarget),
                  ),
                  child: Text(
                    _all
                        ? 'Show the last $kRoamLogShort'
                        : 'Show all ${shown.length}',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow(this.e);

  final RoamEvent e;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool light = colors.isLight;
    final TextStyle base =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    TextStyle apStyle(int i) => base.copyWith(
      color: roamApColor(i, isLight: light),
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Text.rich(
        TextSpan(
          style: base,
          children: <InlineSpan>[
            TextSpan(
              text: '${e.timeS.toStringAsFixed(1)} s  ',
              style: base.copyWith(color: colors.textPrimary),
            ),
            TextSpan(text: 'AP ${e.fromAp + 1}', style: apStyle(e.fromAp)),
            TextSpan(text: ' (${fmtDbm(e.fromRssiDbm)}) to '),
            TextSpan(text: 'AP ${e.toAp + 1}', style: apStyle(e.toAp)),
            TextSpan(
              text:
                  ' (${fmtDbm(e.toRssiDbm)}). Gap ${fmtMs(e.gapMs)}: scan '
                  '${fmtMs(e.cost.scanMs)} + ${e.cost.method.label} '
                  '${fmtMs(e.cost.authMs)}.',
            ),
            if (e.pingPong)
              TextSpan(
                text: ' Ping-pong.',
                style: base.copyWith(
                  color: colors.statusWarning,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Client ──────────────────────────────────────────────────────────────────

class _ClientCard extends StatelessWidget {
  const _ClientCard(this.c);

  final RoamingWalkController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final RoamWalkConfig cfg = c.config;
    final ClientPreset? p = c.preset;
    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const RwSectionLabel('The client decides when to roam'),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Client',
            semanticLabel: 'Client preset',
            // Index into ClientPreset.values; one past the end is Custom,
            // offered only while the values match no preset.
            field: AppSelect<int>(
              value: p?.index ?? ClientPreset.values.length,
              semanticLabel: 'Client preset',
              items: <AppSelectItem<int>>[
                for (final ClientPreset x in ClientPreset.values)
                  (x.index, x.label),
                if (p == null) (ClientPreset.values.length, 'Custom'),
              ],
              onChanged: (int i) {
                if (i < ClientPreset.values.length) {
                  c.applyPreset(ClientPreset.values[i]);
                }
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            p == null
                ? 'Custom values.'
                : p.published
                // The published presets credit their source (Keith,
                // 2026-09-27: citations stay); the devices stay generic.
                ? 'Source: Apple, Wi-Fi roaming support in Apple devices.'
                : 'Illustrative: other client platforms publish no roam '
                      'thresholds.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          RwSlider(
            label: 'Trigger',
            valueText: '${cfg.triggerDbm.toStringAsFixed(0)} dBm',
            value: cfg.triggerDbm,
            min: -90,
            max: -55,
            divisions: 35,
            onChanged: (double v) => c.triggerDbm = v,
            semanticValue: (double v) => '${v.toStringAsFixed(0)} dBm',
          ),
          RwSlider(
            label: 'Delta (how much stronger a new AP must be)',
            valueText: '${cfg.deltaDb.toStringAsFixed(0)} dB',
            value: cfg.deltaDb,
            min: 0,
            max: 20,
            divisions: 20,
            onChanged: (double v) => c.deltaDb = v,
            semanticValue: (double v) => '${v.toStringAsFixed(0)} dB',
          ),
          RwNote(
            icon: Icons.info_outline,
            message:
                'Above its trigger the client stays put, however strong '
                'another AP is. Below it, it scans and moves only to an AP '
                'at least delta stronger. A low trigger makes a sticky '
                'client; a small delta makes it ping-pong between two '
                'similar APs.',
          ),
        ],
      ),
    );
  }
}

// ── Roam cost ───────────────────────────────────────────────────────────────

class _RoamCostCard extends StatelessWidget {
  const _RoamCostCard(this.c);

  final RoamingWalkController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final RoamWalkConfig cfg = c.config;
    final RoamTiming tm = cfg.timing;
    final RoamCost first = cfg.costFor(cfg.authMethodFor(joinedBefore: false));
    final RoamCost back = cfg.costFor(cfg.authMethodFor(joinedBefore: true));
    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const RwSectionLabel('What a roam costs'),
          const SizedBox(height: AppSpacing.xxs),
          RwSwitchRow(
            title: '802.11k neighbor list',
            subtitle:
                'Scan only the neighbor channels, up to 6, instead of all '
                '${tm.channelCount}',
            value: cfg.use11k,
            onChanged: (bool v) => c.use11k = v,
          ),
          RwSwitchRow(
            title: 'PMK caching',
            subtitle: 'Skip EAP when going back to an AP already joined',
            value: cfg.usePmkCaching,
            onChanged: (bool v) => c.usePmkCaching = v,
          ),
          RwSwitchRow(
            title: '802.11r fast transition (FT)',
            subtitle: 'Four frames over the air, no EAP, to any AP',
            value: cfg.useFt,
            onChanged: (bool v) => c.useFt = v,
          ),
          const SizedBox(height: AppSpacing.xs),
          RwRow(
            label: 'Scan',
            value:
                '${first.scanChannels} ch x ${tm.dwellMs.toStringAsFixed(0)} '
                'ms = ${fmtMs(first.scanMs)}',
          ),
          RwRow(
            label: 'Authenticate',
            value:
                '${first.method.label}, ${first.frames} frames, '
                '${fmtMs(first.authMs)}',
          ),
          if (back.method != first.method)
            RwRow(
              label: 'Back to a joined AP',
              value:
                  '${back.method.label}, ${back.frames} frames, '
                  '${fmtMs(back.authMs)}',
            ),
          RwRow(
            label: 'Gap per roam',
            value: back.method != first.method
                ? '${fmtMs(first.totalMs)} (${fmtMs(back.totalMs)} going back)'
                : fmtMs(first.totalMs),
            emphasize: true,
          ),
          const SizedBox(height: AppSpacing.xs),
          const RwSectionLabel('Illustrative timings'),
          const SizedBox(height: AppSpacing.xxs),
          RwSlider(
            label: 'Dwell per channel',
            valueText: '${tm.dwellMs.toStringAsFixed(0)} ms',
            value: tm.dwellMs,
            min: 5,
            max: 100,
            divisions: 19,
            onChanged: (double v) =>
                c.timing = tm.copyWith(dwellMs: v.roundToDouble()),
            semanticValue: (double v) => '${v.toStringAsFixed(0)} milliseconds',
          ),
          RwSlider(
            label: 'Channels in a full scan',
            valueText: '${tm.channelCount}',
            value: tm.channelCount.toDouble(),
            min: 1,
            max: 40,
            divisions: 39,
            onChanged: (double v) =>
                c.timing = tm.copyWith(channelCount: v.round()),
            semanticValue: (double v) => '${v.round()} channels',
          ),
          RwSlider(
            label: 'Time per auth frame',
            valueText: '${tm.frameMs.toStringAsFixed(0)} ms',
            value: tm.frameMs,
            min: 1,
            max: 10,
            divisions: 9,
            onChanged: (double v) =>
                c.timing = tm.copyWith(frameMs: v.roundToDouble()),
            semanticValue: (double v) => '${v.toStringAsFixed(0)} milliseconds',
          ),
          RwSlider(
            label: 'Authentication server time (802.1X)',
            valueText: '${tm.serverMs.toStringAsFixed(0)} ms',
            value: tm.serverMs,
            min: 0,
            max: 200,
            divisions: 20,
            onChanged: (double v) =>
                c.timing = tm.copyWith(serverMs: v.roundToDouble()),
            semanticValue: (double v) => '${v.toStringAsFixed(0)} milliseconds',
          ),
          const SizedBox(height: AppSpacing.xs),
          RwNote(
            icon: Icons.menu_book_outlined,
            message:
                'Measured, for context: Mishra, Shin and Arbaugh (2003) '
                'timed handoffs at 58.74 to 396.76 ms, with scanning over '
                '90% of it (802.11b, open authentication). One FT lab '
                'capture read 14 ms. Neither is the model above.',
          ),
          const SizedBox(height: AppSpacing.xs),
          RwNote(
            icon: Icons.lightbulb_outline,
            message:
                'Scanning is most of a slow roam, so 802.11k helps more than '
                'FT when the scan is long. 802.11v is the AP side: it can '
                'suggest a better AP, and the client decides whether to go. '
                'This model does not simulate 802.11v.',
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Full 802.1X: Open authentication (2), reassociation (2), EAP '
            'identity (2), EAP method exchange '
            '(${tm.eapMethodFrames}), EAP-Success (1), 4-way handshake (4).',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ── Floor setup ─────────────────────────────────────────────────────────────

class _FloorSetupCard extends StatelessWidget {
  const _FloorSetupCard(this.c);

  final RoamingWalkController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final RoamWalkConfig cfg = c.config;
    final int ap = c.editingAp;
    final FloorPoint pos = cfg.aps[ap];
    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const RwSectionLabel('The floor and the walk'),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Path',
            semanticLabel: 'Walking path',
            field: AppSelect<WalkPathPreset>(
              value: c.drawing ? WalkPathPreset.custom : c.pathPreset,
              semanticLabel: 'Walking path',
              items: <AppSelectItem<WalkPathPreset>>[
                for (final WalkPathPreset p in WalkPathPreset.values)
                  (p, p == WalkPathPreset.custom ? 'Draw your own' : p.label),
              ],
              onChanged: (WalkPathPreset p) => c.pathPreset = p,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${pathLengthM(cfg.path).toStringAsFixed(0)} m at '
            '${kRoamWalkSpeedMps.toStringAsFixed(1)} m/s, sampled every '
            '100 ms.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'APs',
            semanticLabel: 'Number of access points',
            field: AppSelect<int>(
              value: c.apCount,
              semanticLabel: 'Number of access points',
              items: <AppSelectItem<int>>[
                for (int n = kMinAps; n <= kMaxAps; n++) (n, '$n APs'),
              ],
              onChanged: (int n) => c.apCount = n,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Changing the count spaces them evenly again.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Move',
            semanticLabel: 'Access point to move',
            field: AppSelect<int>(
              value: ap,
              semanticLabel: 'Access point to move',
              items: <AppSelectItem<int>>[
                for (int i = 0; i < c.apCount; i++) (i, 'AP ${i + 1}'),
              ],
              onChanged: (int i) => c.editingAp = i,
            ),
          ),
          RwSlider(
            label: 'AP ${ap + 1} across',
            valueText: '${pos.x.toStringAsFixed(1)} m',
            value: pos.x,
            min: 0,
            max: kFloorWidthM,
            divisions: (kFloorWidthM * 2).round(),
            onChanged: c.setApX,
            semanticValue: (double v) => '${v.toStringAsFixed(1)} meters',
          ),
          RwSlider(
            label: 'AP ${ap + 1} down',
            valueText: '${pos.y.toStringAsFixed(1)} m',
            value: pos.y,
            min: 0,
            max: kFloorDepthM,
            divisions: (kFloorDepthM * 2).round(),
            onChanged: c.setApY,
            semanticValue: (double v) => '${v.toStringAsFixed(1)} meters',
          ),
          const SizedBox(height: AppSpacing.xs),
          AppToggle<RoamBand>(
            label: 'Band',
            value: cfg.band,
            expand: true,
            items: <AppToggleItem<RoamBand>>[
              for (final RoamBand b in RoamBand.values) (b, b.label),
            ],
            onChanged: (RoamBand b) => c.band = b,
          ),
          const SizedBox(height: AppSpacing.sm),
          RwSlider(
            label: 'AP power (EIRP, illustrative)',
            valueText: '${cfg.eirpDbm.toStringAsFixed(0)} dBm',
            value: cfg.eirpDbm,
            min: 5,
            max: 30,
            divisions: 25,
            onChanged: (double v) => c.eirpDbm = v,
            semanticValue: (double v) => '${v.toStringAsFixed(0)} dBm',
          ),
          RwSlider(
            label: 'Path-loss exponent n',
            valueText: cfg.pathLossExponent.toStringAsFixed(1),
            value: cfg.pathLossExponent,
            min: 2,
            max: 4,
            divisions: 20,
            onChanged: (double v) => c.pathLossExponent = v,
            semanticValue: (double v) => v.toStringAsFixed(1),
          ),
          RwSlider(
            label: 'Shadowing (sigma)',
            valueText: cfg.shadowSigmaDb == 0
                ? 'off'
                : '${cfg.shadowSigmaDb.toStringAsFixed(1)} dB',
            value: cfg.shadowSigmaDb,
            min: 0,
            max: 6,
            divisions: 12,
            onChanged: (double v) => c.shadowSigmaDb = v,
            semanticValue: (double v) =>
                v == 0 ? 'off' : '${v.toStringAsFixed(1)} dB',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 220,
              child: RwOutlineButton(
                icon: Icons.casino_outlined,
                label: 'New shadowing',
                semanticLabel: 'Draw a new random shadowing pattern',
                onPressed: cfg.shadowSigmaDb == 0 ? null : c.newShadowing,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          RwRow(
            label: '-67 dBm reaches',
            value:
                '${cfg.contourRadiusM(kDesignOverlapDbm).toStringAsFixed(1)} m',
          ),
          RwRow(
            label: '-70 dBm reaches',
            value: '${cfg.contourRadiusM(kWeakSignalDbm).toStringAsFixed(1)} m',
          ),
          const SizedBox(height: AppSpacing.xs),
          RwNote(
            icon: Icons.info_outline,
            message:
                'RSSI = EIRP - FSPL(1 m) - 10 n log10(d) + shadowing. '
                'Designing to -67 dBm overlap still leaves a phone on its '
                'AP down to -70 dBm, so it holds on longer than the design '
                'drawing suggests.',
          ),
        ],
      ),
    );
  }
}
