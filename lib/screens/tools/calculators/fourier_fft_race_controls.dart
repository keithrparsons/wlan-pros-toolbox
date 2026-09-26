// FourierRaceControls: mode 3 of the Wi-Fi Lab "Fourier and FFT" tool
// (fourier-fft), swept vs FFT race. Inputs and readouts only; it writes
// FourierLabModel.race and never draws a plot.
//
// The fingerprint sentences below are copied word for word from the Spectrum
// Analysis module's signature cards (lib/screens/tools/educational/
// spectrum_analysis_screen.dart, _kSignatures), so the two surfaces agree.
// That module is not modified; a test holds these strings to its source.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/fourier_race.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../labeled_field.dart';
import 'fourier_fft_model.dart';
import 'fourier_fft_parts.dart';
import 'fourier_fft_race_state.dart';

/// Signature-card fingerprints, verbatim, for the scene's sources that have
/// a card. Wi-Fi has no signature card; its line is this tool's own.
const Map<RaceSource, String> kRaceFingerprints = <RaceSource, String>{
  RaceSource.microwave:
      'A broad, wandering blob that climbs into the upper 2.4 GHz channels '
      '(worst around channel 9 to 11), pulsing on and off with the mains '
      'cycle. It is never centered on channel 6.',
  RaceSource.bluetooth:
      'A dense, fine speckle of thin 1 MHz hops scattered across the whole '
      'band every frame: 79 channels, hopping about 1,600 times per second, '
      'with no fixed home.',
  RaceSource.ble:
      'Three strong, persistent pickets on the advertising channels 37, 38, '
      'and 39 (2402, 2426, and 2480 MHz), parked in the gaps around Wi-Fi 1, '
      '6, and 11, with faint data-hop speckle behind them.',
  RaceSource.video:
      'Three adjacent continuous carriers on a fixed frequency, the video '
      'carrier flanked by its audio and color subcarriers. It is steady, '
      'never hops, and never stops.',
};

/// What this scene draws for each source (the synthetic parameters).
String raceSceneLine(RaceSource s, RaceSceneConfig c) => switch (s) {
  RaceSource.microwave =>
    'Here: on for ${fmtTime(RaceScene.microwaveOnSeconds(c.mainsHz))} of '
        'every ${fmtTime(1 / c.mainsHz)} (${c.mainsHz.round()} Hz mains), '
        '${c.microwaveSweepMhz == 0 ? 'holding near ${RaceScene.microwaveCenterMhz.round()} MHz' : 'climbing ${fmtMhz(c.microwaveSweepMhz)} around ${RaceScene.microwaveCenterMhz.round()} MHz'} '
        'each time.',
  RaceSource.bluetooth =>
    'Here: one hop per 625 µs slot, each to a channel picked at random. The '
        'real sequence is pseudo-random. Each hop is drawn as its full slot; '
        'real packets fill part of it.',
  RaceSource.ble =>
    'Here: one advertising event about every 100 ms (a typical interval; '
        'devices vary), a short packet on each of the three channels. Data '
        'hops are left out.',
  RaceSource.video =>
    'Here: continuous at ${RaceScene.videoCenterMhz.round()} MHz, '
        '${fmtMhz(c.videoBandwidthMhz)} wide. The width is a setting because '
        'it varies by model.',
  RaceSource.wifi =>
    'OFDM bursts on channel 6, about 16.6 MHz wide: 1500-byte frames at '
        '54 Mbps (244 µs each) with DIFS and a random backoff between them.',
};

class FourierRaceControls extends StatelessWidget {
  const FourierRaceControls({super.key, required this.model});
  final FourierLabModel model;

  @override
  Widget build(BuildContext context) {
    const Widget gap = SizedBox(height: AppSpacing.sm);
    if (PresenterMode.isActive(context)) {
      // Presenter: the catches and the sweep time are on the stage; the
      // run button and the analyzer settings stay; the scene, the
      // fingerprints and the formula's caveats fold.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _RaceCard(model: model, compact: true),
          gap,
          _AnalyzersCard(model: model, compact: true),
          gap,
          LabCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                PresenterDisclosure(
                  title: 'Scene: mains, oven sweep, camera',
                  children: <Widget>[_SceneCard(model: model)],
                ),
                PresenterDisclosure(
                  title: 'What each one looks like',
                  children: <Widget>[_FingerprintsCard(model: model)],
                ),
                const PresenterDisclosure(
                  title: 'About the sweep-time formula',
                  children: <Widget>[_SweepFormulaNotes()],
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _RaceCard(model: model),
        gap,
        _AnalyzersCard(model: model),
        gap,
        _SceneCard(model: model),
        gap,
        _FingerprintsCard(model: model),
      ],
    );
  }
}

class _RaceCard extends StatelessWidget {
  const _RaceCard({required this.model, this.compact = false});
  final FourierLabModel model;

  /// Presenter: Run, Pause or Resume and Rewind only (the stage shows the
  /// catches).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final FourierRaceState race = model.race;
    final RaceRun run = race.run;
    final double? until = race.animating ? race.elapsedSeconds : null;
    final RaceTally bt = run.tally(RaceSource.bluetooth, untilSeconds: until);
    final RaceTally mw = run.tally(RaceSource.microwave, untilSeconds: until);

    if (compact) {
      return LabCard(
        child: Row(
          children: <Widget>[
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                onPressed: race.playPause,
                icon: Icon(
                  race.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(
                  race.playing
                      ? 'Pause'
                      : race.paused
                      ? 'Resume'
                      : 'Run the race',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              flex: 2,
              child: LabOutlinedAction(
                label: 'Step',
                icon: Icons.skip_next_rounded,
                semantic: 'Step the race one fortieth of the run',
                enabled: true,
                onTap: race.step,
              ),
            ),
          ],
        ),
      );
    }

    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LabSectionLabel('The race'),
          const SizedBox(height: AppSpacing.xs),
          FilledButton.icon(
            onPressed: race.playing
                ? null
                : race.paused
                ? race.resume
                : race.startRun,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(
              race.playing
                  ? 'Running...'
                  : race.paused
                  ? 'Resume'
                  : 'Run the race',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          LabCaption(
            'Plays the ${fmtTime(run.runSeconds)} run slowed down, so you can '
            'watch the counts climb. The result below is the whole run.',
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            liveRegion: true,
            child: _TallyTable(bt: bt, mw: mw),
          ),
          const SizedBox(height: AppSpacing.xs),
          const LabCaption(
            'A catch is any instant the signal was within half an RBW of where '
            'the analyzer was looking. The swept analyzer looks at one slice '
            'at a time, so a hop that comes and goes while the sweep is '
            'elsewhere is never seen.',
          ),
        ],
      ),
    );
  }
}

/// Caught and missed per analyzer, as a small table (rows wrap badly at
/// phone width as label/value pairs).
class _TallyTable extends StatelessWidget {
  const _TallyTable({required this.bt, required this.mw});
  final RaceTally bt;
  final RaceTally mw;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle head = Theme.of(
      context,
    ).textTheme.labelMedium!.copyWith(color: colors.textSecondary);
    final TextStyle name = Theme.of(
      context,
    ).textTheme.bodyMedium!.copyWith(color: colors.textSecondary);
    final TextStyle mono = labMono(context).inlineCode;
    TableRow row(String who, int caught, int total, {bool lime = false}) {
      final TextStyle v = mono.copyWith(
        color: lime ? colors.textAccent : colors.textPrimary,
        fontWeight: lime ? FontWeight.w500 : FontWeight.w400,
      );
      return TableRow(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Text(who, style: name),
          ),
          Text(total == 0 ? 'none' : '$caught of $total', style: v),
          Text(total == 0 ? '-' : '${total - caught}', style: v),
        ],
      );
    }

    Widget table(String title, RaceTally t) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LabSectionLabel(title),
        const SizedBox(height: AppSpacing.xxs),
        Table(
          columnWidths: const <int, TableColumnWidth>{
            0: FlexColumnWidth(1.1),
            1: FlexColumnWidth(1.4),
            2: FlexColumnWidth(1),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: <TableRow>[
            TableRow(
              children: <Widget>[
                const SizedBox.shrink(),
                Text('Caught', style: head),
                Text('Missed', style: head),
              ],
            ),
            row('Swept', t.sweptCaught, t.total, lime: true),
            row('FFT', t.fftCaught, t.total),
          ],
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        table('Bluetooth hops', bt),
        const SizedBox(height: AppSpacing.sm),
        table('Microwave pulses', mw),
      ],
    );
  }
}

class _AnalyzersCard extends StatelessWidget {
  const _AnalyzersCard({required this.model, this.compact = false});
  final FourierLabModel model;

  /// Presenter: settings and the two secondary readouts; the sweep time is
  /// on the stage and the formula's caveats fold.
  final bool compact;

  static String _rbwLabel(double hz) => fmtHz(hz);

  @override
  Widget build(BuildContext context) {
    final FourierRaceState race = model.race;
    final RaceRun run = race.run;
    final double sweeps = run.sweepsInRun;
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LabSectionLabel('Analyzer settings'),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: LabeledField(
                  label: 'Span',
                  semanticLabel: 'Span',
                  field: AppSelect<double>(
                    value: race.spanMhz,
                    semanticLabel: 'Span',
                    items: <AppSelectItem<double>>[
                      for (final double s in kRaceSpansMhz) (s, fmtMhz(s)),
                    ],
                    onChanged: race.setSpan,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: LabeledField(
                  label: 'RBW',
                  semanticLabel: 'Resolution bandwidth',
                  field: AppSelect<double>(
                    value: race.rbwHz,
                    semanticLabel: 'Resolution bandwidth',
                    items: <AppSelectItem<double>>[
                      for (final double r in kRaceRbwHz) (r, _rbwLabel(r)),
                    ],
                    onChanged: race.setRbw,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Run length',
            semanticLabel: 'Run length',
            field: AppSelect<double>(
              value: race.config.runSeconds,
              semanticLabel: 'Run length',
              items: <AppSelectItem<double>>[
                for (final double s in kRaceRunSeconds) (s, fmtTime(s)),
              ],
              onChanged: race.setRunSeconds,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (!compact)
            LabReadoutRow(
              label: 'Sweep time',
              value: fmtTime(run.swept.sweepSeconds),
              emphasize: true,
            ),
          LabReadoutRow(
            label: 'Sweeps in run',
            value: sweeps >= 1
                ? sweeps.toStringAsFixed(sweeps >= 10 ? 0 : 1)
                : '${sweeps.toStringAsFixed(2)} (it looked at '
                      '${(run.spanCoveredFraction * 100).toStringAsFixed(0)}% '
                      'of the span)',
          ),
          LabReadoutRow(
            label: 'FFT frame',
            value: 'about ${fmtTime(run.fft.frameSeconds)} (1/RBW), no gaps',
          ),
          if (!compact) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            const _SweepFormulaNotes(),
          ],
        ],
      ),
    );
  }
}

/// What the sweep-time formula is and is not (the phone shows it under the
/// analyzer settings; the presenter panel folds it).
class _SweepFormulaNotes extends StatelessWidget {
  const _SweepFormulaNotes();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      LabCaption(
        'Sweep time = k x Span / RBW², with k = '
        '${SweptAnalyzer.kSweepK} (Keysight AN 150 gives 2 to 3 for '
        'analog filters). Ten times narrower RBW makes the sweep 100 '
        'times slower. Narrow RBW is worth having: it lowers the noise '
        'floor and separates close signals.',
      ),
      SizedBox(height: AppSpacing.xs),
      LabNote(
        icon: Icons.info_outline,
        message:
            'Real analyzers with digital RBW filters, or FFT-assisted '
            'sweeps, sweep faster than this formula says. The formula is '
            'the classic analog case. The FFT analyzer here is ideal: it '
            'covers the whole span with no gaps; a real one has a '
            'real-time bandwidth limit.',
      ),
    ],
  );
}

class _SceneCard extends StatelessWidget {
  const _SceneCard({required this.model});
  final FourierLabModel model;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final FourierRaceState race = model.race;
    final RaceSceneConfig c = race.config;
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LabSectionLabel('Scene (synthetic)'),
          const SizedBox(height: AppSpacing.xs),
          AppToggle<double>(
            label: 'Mains frequency',
            value: c.mainsHz,
            expand: true,
            items: const <AppToggleItem<double>>[(60, '60 Hz'), (50, '50 Hz')],
            onChanged: race.setMains,
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Microwave sweep width',
            semanticLabel: 'Microwave sweep width',
            field: AppSelect<double>(
              value: c.microwaveSweepMhz,
              semanticLabel: 'Microwave sweep width',
              items: <AppSelectItem<double>>[
                for (final double w in kMicrowaveSweepsMhz)
                  (w, w == 0 ? 'Near CW (no sweep)' : fmtMhz(w)),
              ],
              onChanged: race.setMicrowaveSweep,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          const LabCaption(
            'Sources disagree: some ovens hold one frequency, others sweep '
            'tens of MHz while on.',
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Video camera bandwidth',
            semanticLabel: 'Analog video camera bandwidth',
            field: AppSelect<double>(
              value: c.videoBandwidthMhz,
              semanticLabel: 'Analog video camera bandwidth',
              items: <AppSelectItem<double>>[
                for (final double w in kVideoBandwidthsMhz) (w, fmtMhz(w)),
              ],
              onChanged: race.setVideoBandwidth,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: race.newScene,
            icon: const Icon(Icons.shuffle_rounded),
            label: const Text('New scene'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.textPrimary,
              side: BorderSide(color: colors.borderStrong, width: 1.5),
              minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const LabCaption(
            'Everything here is simulated from published timings, not '
            'captured. New scene draws new hops, gaps and oven timing.',
          ),
        ],
      ),
    );
  }
}

class _FingerprintsCard extends StatelessWidget {
  const _FingerprintsCard({required this.model});
  final FourierLabModel model;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final RaceSceneConfig c = model.race.config;
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LabSectionLabel('What each one looks like'),
          const SizedBox(height: AppSpacing.xxs),
          const LabCaption(
            'Fingerprints from the Spectrum Analysis signature cards, and '
            'what this scene draws.',
          ),
          for (final RaceSource s in RaceSource.values) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              s.label,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xxs),
            if (kRaceFingerprints[s] case final String f) ...<Widget>[
              _FingerprintStrip(text: f),
              const SizedBox(height: AppSpacing.xxs),
            ],
            LabCaption(raceSceneLine(s, c)),
          ],
        ],
      ),
    );
  }
}

/// The §8.22 fingerprint caption strip: surface2 with a 4 px lime left edge.
class _FingerprintStrip extends StatelessWidget {
  const _FingerprintStrip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface2,
        border: Border(left: BorderSide(color: colors.primary, width: 4)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.xxs,
        AppSpacing.xs,
        AppSpacing.xxs,
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
      ),
    );
  }
}
