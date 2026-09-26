// FourierRaceStage: mode 3 of the Wi-Fi Lab "Fourier and FFT" tool
// (fourier-fft), swept vs FFT race. Plots only; it reads FourierLabModel.race
// and holds no inputs, so a presenter layout can place it beside the controls
// unchanged.
//
// Two waterfalls over the same synthetic scene and the same axes: the FFT
// analyzer (every bin, every frame) and the swept analyzer (only where it is
// tuned). The swept analyzer's path is the lime diagonal on both. Colors are
// the GL-003 §8.22 analyzer rainbow with its mandatory dBm legend; the data
// area stays dark in both themes, the chrome around it follows the theme.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/fourier_race.dart';
import '../../../theme/app_analyzer_rainbow.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'fourier_fft_model.dart';
import 'fourier_fft_painters.dart';
import 'fourier_fft_part2_painters.dart';
import 'fourier_fft_parts.dart';
import 'fourier_fft_race_state.dart';
import 'fourier_fft_stage.dart';

/// "caught 12 of 320" for a tally, per analyzer.
String _caught(int caught, int total) => '$caught of $total';

class FourierRaceStage extends StatelessWidget {
  const FourierRaceStage({
    super.key,
    required this.model,
    this.plotHeight = 176,
  });

  final FourierLabModel model;
  final double plotHeight;

  @override
  Widget build(BuildContext context) {
    final FourierRaceState race = model.race;
    final RaceRun run = race.run;
    final FourierPlotStyle style = fourierPlotStyle(context);
    final double elapsed = race.elapsedSeconds;
    final RaceTally bt = run.tally(
      RaceSource.bluetooth,
      untilSeconds: race.animating ? elapsed : null,
    );
    final RaceTally mw = run.tally(
      RaceSource.microwave,
      untilSeconds: race.animating ? elapsed : null,
    );
    final String span = '${fmtMhz(race.spanMhz)} span';
    final String runLen = fmtTime(run.runSeconds);
    final bool pathDrawn = run.sweepsInRun <= kMaxSweepLinesDrawn;
    final double height = plotHeight + 64;
    final bool presenting = PresenterMode.isActive(context);

    Widget waterfall(
      Float32List grid,
      String semantic,
      bool showPath, {
      double height = double.infinity,
    }) => FourierPlot(
      semantic: semantic,
      height: height,
      painter: WaterfallPainter(
        run: run,
        grid: grid,
        progress: race.progress,
        style: style,
        revision: model.revision,
        showSweepPath: showPath,
      ),
    );

    Widget panel({
      required String title,
      required String subtitle,
      required Float32List grid,
      required String semantic,
      required bool showPath,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LabSectionLabel(title),
          const SizedBox(height: AppSpacing.xxs),
          LabCaption(subtitle),
          const SizedBox(height: AppSpacing.xs),
          // Presenter: the waterfall takes the height the stage gives it.
          if (presenting)
            Expanded(child: waterfall(grid, semantic, showPath))
          else
            waterfall(grid, semantic, showPath, height: height),
        ],
      );
    }

    final Widget fftPanel = panel(
      title: 'FFT analyzer (real time)',
      subtitle: 'Transforms the whole span every frame, with no gaps.',
      grid: run.fftGrid,
      // The path goes on the FFT panel only: on the swept panel the measured
      // cells ARE the path, and a line would cover them.
      showPath: true,
      semantic:
          'FFT analyzer waterfall, $span, $runLen run, time running up. It '
          'caught ${_caught(bt.fftCaught, bt.total)} Bluetooth hops and '
          '${_caught(mw.fftCaught, mw.total)} microwave pulses.',
    );
    final Widget sweptPanel = panel(
      title: 'Swept analyzer',
      subtitle: 'Sees only the slice it is tuned to at each instant.',
      grid: run.sweptGrid,
      showPath: false,
      semantic:
          'Swept analyzer waterfall, $span, $runLen run, time running up. '
          'It sweeps once every ${fmtTime(run.swept.sweepSeconds)}, so it '
          'saw only the cells along its diagonal path. It caught '
          '${_caught(bt.sweptCaught, bt.total)} Bluetooth hops and '
          '${_caught(mw.sweptCaught, mw.total)} microwave pulses.',
    );

    final String status =
        '${race.paused ? 'Paused' : 'Playing'}: ${fmtTime(elapsed)} of '
        '$runLen, slowed down '
        '${(kRacePlayback.inMicroseconds / 1e6 / run.runSeconds).round()}x.';
    if (presenting) {
      // Presenter: the sweep time and what each analyzer caught are the
      // lesson, so they lead; the two waterfalls share the height below.
      return LabCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            LabStatRow(
              children: <Widget>[
                LabStat(
                  label: 'Sweep time (k x Span / RBW²)',
                  value: fmtTime(run.swept.sweepSeconds),
                  accent: true,
                ),
                LabStat(
                  label: 'Bluetooth hops caught, swept / FFT',
                  value: bt.total == 0
                      ? 'none yet'
                      : '${bt.sweptCaught} / ${bt.fftCaught} of ${bt.total}',
                ),
                LabStat(
                  label: 'Microwave pulses caught, swept / FFT',
                  value: mw.total == 0
                      ? 'none yet'
                      : '${mw.sweptCaught} / ${mw.fftCaught} of ${mw.total}',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: <Widget>[
                Expanded(
                  child: LabSectionLabel(
                    'Synthetic 2.4 GHz scene: $span, $runLen, same scene '
                    'for both, time running up',
                  ),
                ),
                if (race.animating)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      status,
                      style: labMono(
                        context,
                      ).inlineCode.copyWith(color: context.colors.textPrimary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: fftPanel),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: sweptPanel),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            const AnalyzerDbmLegend(),
            const SizedBox(height: AppSpacing.xxs),
            _PathLegend(pathDrawn: pathDrawn, sweeps: run.sweepsInRun),
          ],
        ),
      );
    }

    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LabSectionLabel(
            'Synthetic 2.4 GHz scene: $span, $runLen, same scene for both',
          ),
          const SizedBox(height: AppSpacing.xs),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              if (c.maxWidth >= 640) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: fftPanel),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: sweptPanel),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  fftPanel,
                  const SizedBox(height: AppSpacing.sm),
                  sweptPanel,
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          const AnalyzerDbmLegend(),
          const SizedBox(height: AppSpacing.xs),
          _PathLegend(pathDrawn: pathDrawn, sweeps: run.sweepsInRun),
          const SizedBox(height: AppSpacing.xs),
          LabCaption(
            'The left axis is time in ms, running up, newest at the top; each '
            'row is '
            '${fmtTime(run.rowSeconds)}. A cell is the strongest signal the '
            'analyzer measured there during that row. Both analyzers blur a '
            'signal by their RBW.',
          ),
          if (race.animating) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Semantics(
              liveRegion: true,
              child: LabNote(
                icon: race.paused
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                message: status,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The swept path's legend, or why it is not drawn.
class _PathLegend extends StatelessWidget {
  const _PathLegend({required this.pathDrawn, required this.sweeps});
  final bool pathDrawn;
  final double sweeps;

  @override
  Widget build(BuildContext context) {
    if (!pathDrawn) {
      return LabCaption(
        'The swept analyzer finishes ${sweeps.round()} sweeps in this run, '
        'too many diagonals to draw one by one. Its waterfall fills in '
        'because it passes every slice many times per row.',
      );
    }
    final AppColorScheme colors = context.colors;
    // A Row with an Expanded label, not LabLegend: the label is long enough
    // to need wrapping at phone width.
    return ExcludeSemantics(
      child: Row(
        children: <Widget>[
          Container(
            width: 20,
            height: 4,
            decoration: BoxDecoration(
              color: AppAnalyzerRainbow.annotation,
              border: Border.all(color: AppAnalyzerRainbow.annotationHalo),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'On the FFT waterfall: where the swept analyzer is tuned, one '
              'diagonal per sweep. The swept waterfall holds only those cells.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The mandatory §8.22 dBm legend: the analyzer rainbow as a stepped scale,
/// weak to strong, with its values, plus the "not looked at" swatch.
class AnalyzerDbmLegend extends StatelessWidget {
  const AnalyzerDbmLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle mono = labMono(context).inlineCode.copyWith(
      color: colors.textSecondary,
      fontSize: Theme.of(context).textTheme.labelSmall?.fontSize,
    );
    Widget swatch(Color c) => Container(
      height: 12,
      decoration: BoxDecoration(
        color: c,
        border: Border.all(color: colors.borderStrong, width: 0.5),
      ),
    );
    return Semantics(
      label:
          'Color scale in dBm: dark blue is the noise floor, -95 dBm, then '
          'light blue, green, yellow, orange and red, to white at -30 dBm or '
          'stronger. Deepest navy means the analyzer did not look there.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (int s = 1; s <= 7; s++)
                Expanded(
                  child: Column(
                    children: <Widget>[
                      swatch(AppAnalyzerRainbow.stops[s]),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        AppAnalyzerRainbow.dbmForStop(
                          s,
                          floorDbm: RaceRun.noiseFloorDbm,
                          topDbm: RaceRun.topDbm,
                        ).round().toString(),
                        style: mono,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            children: <Widget>[
              Text(
                'dBm, weak to strong',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              const Spacer(),
              SizedBox(width: 20, child: swatch(AppAnalyzerRainbow.jet0)),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Not looked at',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
