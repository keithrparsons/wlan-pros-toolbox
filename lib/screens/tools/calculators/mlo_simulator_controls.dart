// MloSimulatorControls: the inputs-and-readouts half of Multi-Link
// Operation.
//
// Takes the shared MloSimulatorState and a set of parts to show, so the
// phone layout can put the readouts right under the stage and the setup
// after them, while a presenter layout shows every part in one column
// beside the stage. No part draws the lanes or the histograms;
// MloSimulatorStage owns those.
//
// Control types follow GL-003 §8.14: two-option choices are AppToggles,
// longer lists are Selects, on/off is a Switch row. Status hues are verdicts
// only (§8.13 rule 6), each with its word and an icon: amber for "worse than
// the best single link", red for "overloaded". Link hues (§8.15.2) sit beside
// their band names.
//
// PRESENTER (spec 00): inside a PresenterLayout the verdict is on the stage;
// the panel keeps the lesson, each link's on/off and busy share, the arrival
// rate and the modes in view, and folds the busy-period lengths, the frame
// airtime, the EMLSR delays, the latency table and the notes into
// PresenterDisclosures.
//
// ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/mlo_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter.dart';
import '../labeled_field.dart';
import 'mlo_simulator_parts.dart';
import 'mlo_simulator_state.dart';

/// The groups MloSimulatorControls can show.
enum MloControlPart {
  /// Mean and 99th percentile per mode, links used, the verdict line.
  readouts,

  /// Lesson preset and new random traffic.
  lesson,

  /// Links: which bands, how busy.
  links,

  /// Arrival rate and frame airtime.
  traffic,

  /// Which modes to compare; EMLSR delays and the driver switch.
  modes,

  /// What the modes mean, the one latency study, and the driver note.
  notes,
}

class MloSimulatorControls extends StatelessWidget {
  const MloSimulatorControls({
    super.key,
    required this.state,
    this.parts = const <MloControlPart>{
      MloControlPart.readouts,
      MloControlPart.lesson,
      MloControlPart.links,
      MloControlPart.traffic,
      MloControlPart.modes,
      MloControlPart.notes,
    },
  });

  final MloSimulatorState state;
  final Set<MloControlPart> parts;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, _) {
        final MloSimulatorState s = state;
        if (PresenterMode.isActive(context)) return _PresenterPanel(s);
        final List<Widget> cards = <Widget>[
          if (parts.contains(MloControlPart.readouts)) _ReadoutsCard(s),
          if (parts.contains(MloControlPart.lesson)) _LessonCard(s),
          if (parts.contains(MloControlPart.links)) _LinksCard(s),
          if (parts.contains(MloControlPart.traffic)) _TrafficCard(s),
          if (parts.contains(MloControlPart.modes)) _ModesCard(s),
          if (parts.contains(MloControlPart.notes)) const _NotesCard(),
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
  const _PresenterPanel(this.s);

  final MloSimulatorState s;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final MloConfig c = s.config;
    final bool multi = c.links.length > 1;
    final int on = c.links.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        MloCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: LabeledField(
                      label: 'Lesson',
                      field: AppSelect<MloPreset?>(
                        value: s.preset,
                        semanticLabel: 'Lesson',
                        items: <AppSelectItem<MloPreset?>>[
                          if (s.preset == null) (null, 'Your own settings'),
                          for (final MloPreset p in MloPreset.values)
                            (p, p.label),
                        ],
                        onChanged: (MloPreset? p) => s.preset = p,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: s.newTraffic,
                    tooltip: 'New random traffic, same settings (N)',
                    icon: const Icon(Icons.casino_outlined),
                    color: colors.textAccent,
                  ),
                ],
              ),
              for (final MloBand b in MloBand.values)
                _PresenterBand(
                  s: s,
                  band: b,
                  isLastOn: on == 1 && s.bandEnabled(b),
                ),
              MloSlider(
                label: 'Our frames per second',
                valueText: _thousands(c.arrivalsPerSecond.round()),
                value: c.arrivalsPerSecond,
                min: kMloRateMin,
                max: kMloRateMax,
                divisions: 29,
                onChanged: (double v) =>
                    s.arrivalsPerSecond = (v / 100).round() * 100.0,
                semanticValue: (double v) => '${v.round()} frames per second',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        MloCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final MloMode m in kMloComparableModes)
                MloSwitchRow(
                  title: m.label,
                  subtitle: '',
                  value: s.isShown(m),
                  onChanged: (bool v) => s.setModeShown(m, v),
                ),
              MloSwitchRow(
                title: 'EMLSR disabled by driver',
                subtitle: multi ? '' : 'Needs two or more links',
                value: c.emlsrDisabledByDriver,
                onChanged: multi
                    ? (bool v) => s.emlsrDisabledByDriver = v
                    : null,
              ),
            ],
          ),
        ),
        PresenterDisclosure(
          title: 'Busy periods and frame airtime',
          children: <Widget>[
            for (final MloBand b in MloBand.values)
              if (s.bandEnabled(b)) ...<Widget>[
                LabeledField(
                  label: '${b.label} mean busy period',
                  field: AppSelect<double>(
                    value:
                        kMloBusyLengthsUs.contains(s.bandSettings(b).meanBusyUs)
                        ? s.bandSettings(b).meanBusyUs
                        : kMloBusyLengthsUs[2],
                    semanticLabel: '${b.label} mean busy period',
                    items: <AppSelectItem<double>>[
                      for (final double us in kMloBusyLengthsUs)
                        (us, mloFmtUs(us)),
                    ],
                    onChanged: (double us) => s.setMeanBusyUs(b, us),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
            _TrafficCard(s),
          ],
        ),
        PresenterDisclosure(
          title: 'EMLSR switch delays',
          children: <Widget>[
            LabeledField(
              label: 'Padding delay',
              field: AppSelect<int>(
                value: c.paddingDelayUs,
                semanticLabel: 'EMLSR padding delay',
                items: <AppSelectItem<int>>[
                  for (final int d in kEmlsrPaddingDelaysUs) (d, '$d µs'),
                ],
                onChanged: (int d) => s.paddingDelayUs = d,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            LabeledField(
              label: 'Transition delay',
              field: AppSelect<int>(
                value: c.transitionDelayUs,
                semanticLabel: 'EMLSR transition delay',
                items: <AppSelectItem<int>>[
                  for (final int d in kEmlsrTransitionDelaysUs) (d, '$d µs'),
                ],
                onChanged: (int d) => s.transitionDelayUs = d,
              ),
            ),
          ],
        ),
        PresenterDisclosure(
          title: 'Latency per mode, as a table',
          children: <Widget>[_ReadoutsCard(s)],
        ),
        const PresenterDisclosure(
          title: 'The four modes, and the one study',
          children: <Widget>[_NotesCard()],
        ),
      ],
    );
  }
}

/// Presenter: one link's switch and busy share, one line each.
class _PresenterBand extends StatelessWidget {
  const _PresenterBand({
    required this.s,
    required this.band,
    required this.isLastOn,
  });

  final MloSimulatorState s;
  final MloBand band;
  final bool isLastOn;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool on = s.bandEnabled(band);
    final MloLinkConfig l = s.bandSettings(band);
    return Row(
      children: <Widget>[
        SizedBox(
          width: 190,
          child: MloSwitchRow(
            leading: ExcludeSemantics(
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: mloLinkStyle(band, colors).hue,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            title: band.label,
            subtitle: '',
            value: on,
            onChanged: isLastOn ? null : (bool v) => s.setBandEnabled(band, v),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: on
              ? MloSlider(
                  inline: true,
                  label: '${band.label} busy',
                  valueText: '${mloPct(l.busyFraction)} busy',
                  value: l.busyFraction,
                  min: 0,
                  max: kMloMaxBusyFraction,
                  divisions: 19,
                  onChanged: (double v) =>
                      s.setBusyFraction(band, (v * 20).round() / 20),
                  semanticValue: (double v) => '${mloPct(v)} busy',
                )
              : Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: Text(
                    isLastOn ? 'The last link stays on' : 'Off',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                  ),
                ),
        ),
      ],
    );
  }
}

// ── Readouts ────────────────────────────────────────────────────────────────

/// The verdict line: which shown modes are worse than the best single link.
String mloVerdict(MloSimulatorState s) {
  final MloRun run = s.run;
  if (run.linkCount == 1) {
    return 'One link: every mode is the single link, so there is nothing to '
        'gain and nothing to lose.';
  }
  final MloModeResult best = run.bestSingle;
  final String bestName = run.config.links[best.singleLink!].band.label;
  final List<MloMode> shown = s.shownModes;
  if (shown.isEmpty) {
    return 'Switch on a mode below to compare it with the best single link '
        '($bestName).';
  }
  final List<MloMode> worse = <MloMode>[
    for (final MloMode m in shown)
      if (run.worseThanBestSingle(m)) m,
  ];
  if (worse.isEmpty) {
    final List<MloMode> tail = <MloMode>[
      for (final MloMode m in shown)
        if (run.tailWorseThanBestSingle(m)) m,
    ];
    final String better = shown
        .map(
          (MloMode m) =>
              '${m.label} ${_times(1 / run.ratioToBestSingle(m))} lower',
        )
        .join(', ');
    return 'Here MLO beats the best single link ($bestName) on mean latency: '
        '$better.'
        '${tail.isEmpty ? '' : ' But the 99th percentile is worse for ${_names(tail)}.'}';
  }
  return 'MLO is worse than the best single link ($bestName) here: '
      '${worse.map((MloMode m) => '${m.label} ${_times(run.ratioToBestSingle(m))} higher').join(', ')} '
      'on mean latency.';
}

String _thousands(int n) {
  final String t = '$n';
  return t.length <= 3
      ? t
      : '${t.substring(0, t.length - 3)},${t.substring(t.length - 3)}';
}

String _times(double r) => '${r.toStringAsFixed(r < 10 ? 1 : 0)}x';

String _names(List<MloMode> ms) => ms.map((MloMode m) => m.label).join(' and ');

class _ReadoutsCard extends StatelessWidget {
  const _ReadoutsCard(this.s);

  final MloSimulatorState s;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final MloRun run = s.run;
    final bool anyWorse = s.shownModes.any(run.worseThanBestSingle);
    final List<MloModeResult> rows = <MloModeResult>[
      ...run.singles,
      for (final MloMode m in s.shownModes) run.result(m),
    ];
    return MloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MloSectionLabel('Latency per mode'),
          const SizedBox(height: AppSpacing.xs),
          for (final MloModeResult r in rows) _ModeRow(run: run, r: r),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            liveRegion: true,
            child: MloNote(
              icon: anyWorse
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_outline,
              color: anyWorse ? colors.statusWarning : null,
              message: mloVerdict(s),
            ),
          ),
          if (rows.any((MloModeResult r) => r.overloaded)) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            MloNote(
              icon: Icons.error_outline,
              color: colors.statusDanger,
              message:
                  'Overloaded: frames arrive faster than that mode can send '
                  'them, so its queue keeps growing and its latency depends '
                  'on how long the run is. Lower the arrival rate or the '
                  'busy fraction.',
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({required this.run, required this.r});

  final MloRun run;
  final MloModeResult r;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final List<MloLinkConfig> links = run.config.links;
    final bool single = r.mode == MloMode.single;
    final bool best = single && identical(r, run.bestSingle);
    final String name = single
        ? 'Single, ${links[r.singleLink!].band.label}${best ? ' (best)' : ''}'
        : r.fellBackToSingle && run.linkCount > 1
        ? '${r.mode.label} (off: ${links[r.singleLink!].band.label} only)'
        : r.mode.label;
    final bool worse = run.worseThanBestSingle(r.mode) && !single;
    final List<int> counts = r.linkCounts;
    final int total = r.txs.length;
    final String used = <String>[
      for (int k = 0; k < links.length; k++)
        if (counts[k] > 0)
          '${links[k].band.label} ${mloPct(counts[k] / total)}',
    ].join(', ');
    final Color valueColor = r.overloaded
        ? colors.statusDanger
        : worse
        ? colors.statusWarning
        : best
        ? colors.textAccent
        : colors.textPrimary;
    final String stats = r.overloaded
        ? 'Overloaded'
        : 'mean ${mloFmtUs(r.meanUs)}\np99 ${mloFmtUs(r.p99Us)}';
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    style: text.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: single ? FontWeight.w400 : FontWeight.w600,
                    ),
                  ),
                  if (!single && !r.fellBackToSingle)
                    Text(
                      'Links used: $used',
                      style: text.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              flex: 4,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (worse || r.overloaded) ...<Widget>[
                    ExcludeSemantics(
                      child: Icon(
                        r.overloaded
                            ? Icons.error_outline
                            : Icons.warning_amber_rounded,
                        size: 16,
                        color: valueColor,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                  ],
                  Expanded(
                    child: Text(
                      worse ? '$stats\nworse' : stats,
                      style: mono.inlineCode.copyWith(color: valueColor),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Lesson ──────────────────────────────────────────────────────────────────

class _LessonCard extends StatelessWidget {
  const _LessonCard(this.s);

  final MloSimulatorState s;

  @override
  Widget build(BuildContext context) {
    return MloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LabeledField(
            label: 'Lesson',
            field: AppSelect<MloPreset?>(
              value: s.preset,
              semanticLabel: 'Lesson',
              maxLines: 2,
              items: <AppSelectItem<MloPreset?>>[
                if (s.preset == null) (null, 'Your own settings'),
                for (final MloPreset p in MloPreset.values) (p, p.label),
              ],
              onChanged: (MloPreset? p) => s.preset = p,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          MloOutlineButton(
            icon: Icons.casino_outlined,
            label: 'New random traffic',
            semanticLabel:
                'New random traffic: new frame arrivals and new busy periods, '
                'same settings',
            onPressed: s.newTraffic,
          ),
          const SizedBox(height: AppSpacing.xxs),
          MloNote(
            icon: Icons.info_outline,
            message:
                'Traffic ${s.config.seed}. Every mode sees the same frames and '
                'the same busy periods, so the comparison is fair.',
          ),
        ],
      ),
    );
  }
}

// ── Links ───────────────────────────────────────────────────────────────────

class _LinksCard extends StatelessWidget {
  const _LinksCard(this.s);

  final MloSimulatorState s;

  @override
  Widget build(BuildContext context) {
    final int on = s.config.links.length;
    return MloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MloSectionLabel('Links'),
          const SizedBox(height: AppSpacing.xxs),
          MloNote(
            icon: Icons.info_outline,
            message:
                'Busy is how much of the time other networks hold the '
                'channel. Longer busy periods mean longer waits when a frame '
                'lands in one.',
          ),
          for (final MloBand b in MloBand.values) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _BandBlock(s: s, band: b, isLastOn: on == 1 && s.bandEnabled(b)),
          ],
        ],
      ),
    );
  }
}

class _BandBlock extends StatelessWidget {
  const _BandBlock({
    required this.s,
    required this.band,
    required this.isLastOn,
  });

  final MloSimulatorState s;
  final MloBand band;
  final bool isLastOn;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool on = s.bandEnabled(band);
    final MloLinkConfig l = s.bandSettings(band);
    final int? k = s.linkIndex(band);
    final String sub = isLastOn
        ? 'The last link stays on'
        : on
        ? 'Frame airtime ${mloFmtUs(s.run.airtimeUs[k!])}'
        : 'Off';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        MloSwitchRow(
          leading: ExcludeSemantics(
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: mloLinkStyle(band, colors).hue,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          title: '${band.label} link',
          subtitle: sub,
          value: on,
          onChanged: isLastOn ? null : (bool v) => s.setBandEnabled(band, v),
        ),
        if (on) ...<Widget>[
          MloSlider(
            label: '${band.label} busy',
            valueText: mloPct(l.busyFraction),
            value: l.busyFraction,
            min: 0,
            max: kMloMaxBusyFraction,
            divisions: 19,
            onChanged: (double v) =>
                s.setBusyFraction(band, (v * 20).round() / 20),
            semanticValue: (double v) => '${mloPct(v)} busy',
          ),
          LabeledField(
            label: '${band.label} mean busy period',
            field: AppSelect<double>(
              value: kMloBusyLengthsUs.contains(l.meanBusyUs)
                  ? l.meanBusyUs
                  : kMloBusyLengthsUs[2],
              semanticLabel: '${band.label} mean busy period',
              items: <AppSelectItem<double>>[
                for (final double us in kMloBusyLengthsUs) (us, mloFmtUs(us)),
              ],
              onChanged: (double us) => s.setMeanBusyUs(band, us),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Traffic ─────────────────────────────────────────────────────────────────

class _TrafficCard extends StatelessWidget {
  const _TrafficCard(this.s);

  final MloSimulatorState s;

  @override
  Widget build(BuildContext context) {
    final MloConfig c = s.config;
    final bool fixed = c.airtimeSource == MloAirtimeSource.fixed;
    return MloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MloSectionLabel('Our traffic'),
          const SizedBox(height: AppSpacing.xs),
          MloSlider(
            label: 'Frames per second',
            valueText: _thousands(c.arrivalsPerSecond.round()),
            value: c.arrivalsPerSecond,
            min: kMloRateMin,
            max: kMloRateMax,
            divisions: 29,
            onChanged: (double v) =>
                s.arrivalsPerSecond = (v / 100).round() * 100.0,
            semanticValue: (double v) => '${v.round()} frames per second',
          ),
          MloNote(
            icon: Icons.info_outline,
            message:
                '${_thousands(c.frameCount)} frames, arriving at random times at this '
                'average rate.',
          ),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<MloAirtimeSource>(
            label: 'Frame airtime',
            semanticLabel: 'Frame airtime from',
            value: c.airtimeSource,
            expand: true,
            items: <AppToggleItem<MloAirtimeSource>>[
              for (final MloAirtimeSource a in MloAirtimeSource.values)
                (a, a.label),
            ],
            onChanged: (MloAirtimeSource a) => s.airtimeSource = a,
          ),
          const SizedBox(height: AppSpacing.xs),
          if (fixed)
            MloSlider(
              label: 'Airtime per frame, every link',
              valueText: mloFmtUs(c.fixedAirtimeUs),
              value: c.fixedAirtimeUs,
              min: kMloFixedAirtimeMinUs,
              max: kMloFixedAirtimeMaxUs,
              divisions: 19,
              onChanged: (double v) =>
                  s.fixedAirtimeUs = (v / 100).round() * 100.0,
              semanticValue: (double v) => mloFmtUs(v),
            )
          else ...<Widget>[
            LabeledField(
              label: 'HE MCS',
              field: AppSelect<int>(
                value: c.mcs,
                semanticLabel: 'HE MCS',
                items: <AppSelectItem<int>>[
                  for (int m = 0; m <= 11; m++) (m, 'MCS $m'),
                ],
                onChanged: (int m) => s.mcs = m,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            AppToggle<int>(
              label: 'Frames per A-MPDU',
              semanticLabel: 'Frames per A-MPDU',
              value: c.aggregation,
              expand: true,
              items: <AppToggleItem<int>>[
                for (final int a in kMloAggregationChoices) (a, '$a'),
              ],
              onChanged: (int a) => s.aggregation = a,
            ),
            const SizedBox(height: AppSpacing.xs),
            MloNote(
              icon: Icons.info_outline,
              message:
                  'One TXOP from Airtime Anatomy: HE, $kMloStreams streams, '
                  '$kMloFrameBytes-byte frames, 20 MHz on 2.4 GHz, 80 MHz on '
                  '5 GHz, 160 MHz on 6 GHz, with AIFS, average backoff and the '
                  'Block Ack. HE timing stands in for EHT.',
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xxs,
            children: <Widget>[
              for (int k = 0; k < c.links.length; k++)
                MloLinkTag(
                  band: c.links[k].band,
                  suffix: mloFmtUs(s.run.airtimeUs[k]),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Modes ───────────────────────────────────────────────────────────────────

class _ModesCard extends StatelessWidget {
  const _ModesCard(this.s);

  final MloSimulatorState s;

  @override
  Widget build(BuildContext context) {
    final MloConfig c = s.config;
    final bool multi = c.links.length > 1;
    String sub(MloMode m) => switch (m) {
      MloMode.str => 'Send on one link while receiving on another',
      MloMode.nstr => 'Links send together or receive together',
      MloMode.emlsr => 'Listen on all links, exchange on one at a time',
      MloMode.single => '',
    };
    return MloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MloSectionLabel('Modes to compare'),
          const SizedBox(height: AppSpacing.xxs),
          MloNote(
            icon: Icons.info_outline,
            message:
                'The single links are always shown: they are the '
                'baseline every mode is judged against.',
          ),
          for (final MloMode m in kMloComparableModes)
            MloSwitchRow(
              title: m.label,
              subtitle: sub(m),
              value: s.isShown(m),
              onChanged: (bool v) => s.setModeShown(m, v),
            ),
          const SizedBox(height: AppSpacing.sm),
          const MloSectionLabel('EMLSR switch delays'),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Padding delay',
            field: AppSelect<int>(
              value: c.paddingDelayUs,
              semanticLabel: 'EMLSR padding delay',
              items: <AppSelectItem<int>>[
                for (final int d in kEmlsrPaddingDelaysUs) (d, '$d µs'),
              ],
              onChanged: (int d) => s.paddingDelayUs = d,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Transition delay',
            field: AppSelect<int>(
              value: c.transitionDelayUs,
              semanticLabel: 'EMLSR transition delay',
              items: <AppSelectItem<int>>[
                for (final int d in kEmlsrTransitionDelaysUs) (d, '$d µs'),
              ],
              onChanged: (int d) => s.transitionDelayUs = d,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          MloNote(
            icon: Icons.info_outline,
            message:
                'The values a client can advertise, as listed in the Linux '
                'kernel\'s 802.11be header. Each EMLSR exchange here opens '
                'with an initial control frame (sized as an RTS at 24 Mbps, '
                'a lower bound) plus the padding delay and the client\'s '
                'answer; after it, the transition delay.',
          ),
          const SizedBox(height: AppSpacing.xs),
          MloSwitchRow(
            title: 'EMLSR disabled by driver',
            subtitle: multi
                ? 'Falls back to one link, the least busy here'
                : 'Needs two or more links',
            value: c.emlsrDisabledByDriver,
            onChanged: multi ? (bool v) => s.emlsrDisabledByDriver = v : null,
          ),
        ],
      ),
    );
  }
}

// ── Notes ───────────────────────────────────────────────────────────────────

class _NotesCard extends StatelessWidget {
  const _NotesCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle body =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final TextStyle strong = body.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w600,
    );
    Widget def(String term, String meaning) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(text: '$term. ', style: strong),
            TextSpan(text: meaning, style: body),
          ],
        ),
      ),
    );
    return MloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MloSectionLabel('The four modes'),
          def(
            'STR (simultaneous transmit and receive)',
            'The client can send on one link while it receives on another. '
                'It needs enough frequency separation between the links.',
          ),
          def(
            'NSTR (non-simultaneous transmit and receive)',
            'The links can send together or receive together, but not send '
                'on one while receiving on another, so transmissions are '
                'aligned.',
          ),
          def(
            'EMLSR (enhanced multi-link single radio)',
            'The client listens on several links, and exchanges frames on '
                'only one at a time. The AP opens each exchange with an '
                'initial control frame (an MU-RTS or BSRP trigger), and the '
                'client moves all its radio chains to that link.',
          ),
          def(
            'EMLMR (enhanced multi-link multi-radio)',
            'Like EMLSR, but the client can still send or receive on the '
                'other links; what it adds is moving extra radio chains to '
                'one link. Not simulated here.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const MloSectionLabel('The one published latency study'),
          const SizedBox(height: AppSpacing.xxs),
          Semantics(
            container: true,
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text:
                        'A model built on real traffic, not a field '
                        'measurement. ',
                    style: strong,
                  ),
                  TextSpan(
                    text:
                        'Carrascosa, Geraci, Knightly and Bellalta (IEEE ICC '
                        '2022) drove MLO with measured 5 GHz channel '
                        'occupancy, not with Wi-Fi 7 hardware. They found MLO '
                        'can cut latency by an order of magnitude when the '
                        'links are equally busy, and can make it worse when '
                        'they are not. We found no independent latency '
                        'measurement on Wi-Fi 7 hardware (research as of '
                        'September 2026). This tool is a simpler teaching model of the same idea.',
                    style: body,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const MloSectionLabel('Real drivers switch EMLSR off'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Intel\'s Linux driver (iwlwifi) leaves EMLSR for reasons that '
            'include low signal, Bluetooth coexistence, channel load, link '
            'usage and missed beacons, and after some of them it will not '
            'go back for 300 or 600 seconds. A Wi-Fi 7 laptop is often on one '
            'link. Use the "EMLSR disabled by driver" switch to see it.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.sm),
          const MloSectionLabel('What this model leaves out'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Other networks send the same planned traffic in every mode; they '
            'wait while our frame is on the air and go right after it, and '
            'nothing collides. One frame (or one A-MPDU) per exchange, no '
            'retries, no uplink, and one link per band.',
            style: body,
          ),
        ],
      ),
    );
  }
}
