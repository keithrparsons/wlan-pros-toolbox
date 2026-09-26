// FourierStage: the plots for the Wi-Fi Classroom "Fourier and FFT" tool
// (fourier-fft). It reads FourierLabModel and draws; it holds no inputs, so a
// presenter layout can put it beside FourierControls unchanged.
//
//   Waves: time trace (10 ms) above, ideal line spectrum (dB, -60 dB floor).
//   FFT:   the N captured samples with the window outline above, the N-bin
//          spectrum in dB full scale (-120 dB floor) with true-tone ticks.
//   Race:  FourierRaceStage (fourier_fft_race_stage.dart).
//   OFDM:  FourierOfdmStage (fourier_fft_ofdm_stage.dart).
//
// PRESENTER (PresenterMode.isActive): every mode fills the stage's bounded
// box with no scroll. The plots share the height (Expanded, not a fixed
// plotHeight), the numbers the lesson is about sit above them as large
// LabStats, the long captions stay on the phone, and the painters get the
// presenter scale through FourierPlotStyle.
//
// Lime marks the measured quantity (the sum, the spectrum). Individual sines,
// the window and the ticks are neutral (§8.15: no categorical palette).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/fourier_dsp.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'fourier_fft_model.dart';
import 'fourier_fft_ofdm_stage.dart';
import 'fourier_fft_painters.dart';
import 'fourier_fft_parts.dart';
import 'fourier_fft_race_stage.dart';

class FourierStage extends StatelessWidget {
  const FourierStage({super.key, required this.model, this.plotHeight = 176});

  final FourierLabModel model;

  /// Height of each plot. A presenter layout can pass a taller value.
  final double plotHeight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (BuildContext context, _) {
        // Presenter: each mode fills its bounded box with no scroll, its
        // lesson numbers on top as LabStats. Race and OFDM branch in their
        // own stage widgets.
        final bool presenting = PresenterMode.isActive(context);
        switch (model.mode) {
          case FourierMode.waves:
            return presenting
                ? _PresenterWaves(model: model)
                : _WavesStage(model: model, plotHeight: plotHeight);
          case FourierMode.fft:
            return presenting
                ? _PresenterFft(model: model)
                : _FftStage(model: model, plotHeight: plotHeight);
          case FourierMode.race:
            return FourierRaceStage(model: model, plotHeight: plotHeight);
          case FourierMode.ofdm:
            return FourierOfdmStage(model: model, plotHeight: plotHeight);
        }
      },
    );
  }
}

/// Plot colors from the theme. Shared with the part 2 stages.
FourierPlotStyle fourierPlotStyle(BuildContext context) {
  final AppColorScheme colors = context.colors;
  final PresenterScale scale = PresenterMode.scaleOf(context);
  final TextStyle label = Theme.of(context).textTheme.labelSmall!;
  return FourierPlotStyle(
    scale: scale,
    signal: colors.textAccent,
    component: colors.textTertiary.withValues(alpha: 0.7),
    window: colors.textSecondary,
    grid: colors.border,
    axis: colors.borderStrong,
    marker: colors.textSecondary,
    // The painters lay out their own labels, which MediaQuery's text scale
    // does not reach, so the presenter factor goes on the size here.
    labelStyle: label.copyWith(
      color: colors.textTertiary,
      fontSize: scale.paintFont(label.fontSize ?? AppTextSize.caption),
    ),
  );
}

/// A plot on its surface with one worded Semantics label. Shared with the
/// part 2 stages.
class FourierPlot extends StatelessWidget {
  const FourierPlot({
    super.key,
    required this.semantic,
    required this.painter,
    required this.height,
  });

  final String semantic;
  final CustomPainter painter;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semantic,
      image: true,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(
          height: height,
          color: context.colors.surface2,
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: CustomPaint(size: Size.infinite, painter: painter),
        ),
      ),
    );
  }
}

class _WavesStage extends StatelessWidget {
  const _WavesStage({required this.model, required this.plotHeight});
  final FourierLabModel model;
  final double plotHeight;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final FourierPlotStyle style = fourierPlotStyle(context);
    final List<SineComponent> parts = model.parts;
    final bool showEach = model.showComponents && parts.length > 1;
    final bool silent = model.allSilent;

    final String timeSemantic = silent
        ? 'Time trace over 10 milliseconds. Every amplitude is zero, so the '
              'trace is flat.'
        : 'Time trace over 10 milliseconds of the sum of ${parts.length} '
              'sine${parts.length == 1 ? '' : 's'}, peaking at most '
              '${fmtAmp(FourierDsp.peakBound(parts))}.';
    final String specSemantic = silent
        ? 'Spectrum. No lines above the floor.'
        : 'Spectrum lines: '
              '${<String>[for (final SineComponent p in parts)
                if (p.amplitude > 0) '${fmtHz(p.frequencyHz)} at ${fmtDb(p.levelDb)} dB'].join('; ')}.';

    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LabSectionLabel('Time: amplitude over 10 ms'),
          const SizedBox(height: AppSpacing.xs),
          FourierPlot(
            semantic: timeSemantic,
            height: plotHeight,
            painter: TimeTracePainter(
              durationSeconds: kWavesWindowSeconds,
              yMax: model.yMax,
              style: style,
              revision: model.revision,
              signalAt: (double t) => FourierDsp.sumAt(parts, t),
              componentsAt: showEach
                  ? <double Function(double)>[
                      for (final SineComponent p in parts) p.valueAt,
                    ]
                  : const <double Function(double)>[],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          LabLegend(
            items: <(Widget, String)>[
              (labLineSample(colors.textAccent, 2), 'Sum'),
              if (showEach)
                (labLineSample(colors.textTertiary, 1), 'Each sine'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const LabSectionLabel(
            'Frequency: level in dB (floor ${kWavesFloorDb ~/ 1} dB)',
          ),
          const SizedBox(height: AppSpacing.xs),
          FourierPlot(
            semantic: specSemantic,
            height: plotHeight,
            painter: SpectrumPainter(
              maxHz: kSpectrumMaxHz,
              floorDb: kWavesFloorDb,
              style: style,
              revision: model.revision,
              lines: <SpectrumLine>[
                for (final SineComponent p in parts)
                  (frequencyHz: p.frequencyHz, levelDb: p.levelDb),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (silent)
            const LabNote(
              icon: Icons.info_outline,
              message:
                  'Every amplitude is zero, so there is nothing to show. '
                  'Raise an amplitude slider.',
            )
          else
            const LabCaption(
              'One line per sine: its position is the frequency, its height '
              'is the amplitude in dB (1.00 = 0 dB, 0.10 = -20 dB). Phase '
              'changes the shape of the time trace and not these lines.',
            ),
        ],
      ),
    );
  }
}

class _FftStage extends StatelessWidget {
  const _FftStage({required this.model, required this.plotHeight});
  final FourierLabModel model;
  final double plotHeight;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final FourierPlotStyle style = fourierPlotStyle(context);
    final SpectrumAnalysis a = model.analysis;
    final int n = model.n;
    final double fs = model.sampleRateHz;
    final double shownHz = math.min(kSpectrumMaxHz, fs / 2);
    final int peak = a.peakBin;
    final SpectrumWindow window = model.window;

    final String timeSemantic =
        'Capture of $n samples at ${fmtHz(fs)}, lasting '
        '${fmtTime(a.captureSeconds)}, with the ${window.label} window drawn '
        'as a dashed outline.';
    final String specSemantic = model.allSilent
        ? 'Spectrum of $n bins. Nothing above the floor.'
        : 'Spectrum of $n bins, ${fmtHz(a.binSpacingHz)} apart, with the '
              '${window.label} window. Strongest bin '
              '${fmtHz(a.binFrequencyHz(peak))} at '
              '${fmtDb(a.levelsDb[peak])} dB full scale.';

    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LabSectionLabel('Time: $n samples over ${fmtTime(a.captureSeconds)}'),
          const SizedBox(height: AppSpacing.xs),
          FourierPlot(
            semantic: timeSemantic,
            height: plotHeight,
            painter: TimeTracePainter(
              durationSeconds: a.captureSeconds,
              yMax: model.yMax,
              style: style,
              revision: model.revision,
              samples: a.samples,
              windowValues: a.windowValues,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          LabLegend(
            items: <(Widget, String)>[
              (labDot(colors.textAccent, 3), 'Samples'),
              (
                labLineSample(colors.textSecondary, 1.5, dashed: true),
                'Window (${window.label})',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              // Matches the painter's three drawings.
              final double spacing = (c.maxWidth - 48) / n;
              final String how = spacing >= 4
                  ? 'Each dot is one sample.'
                  : spacing >= 1
                  ? 'At this width the $n samples are drawn as a line '
                        'through them.'
                  : 'At this width there are more samples than pixel '
                        'columns, so each column shows the range of its '
                        'samples.';
              return LabCaption(
                '$how The FFT sees the samples multiplied by the window.',
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          const LabSectionLabel(
            'Spectrum: dB full scale (floor ${kFftFloorDb ~/ 1} dB)',
          ),
          const SizedBox(height: AppSpacing.xs),
          FourierPlot(
            semantic: specSemantic,
            height: plotHeight + 24,
            painter: SpectrumPainter(
              maxHz: shownHz,
              floorDb: kFftFloorDb,
              style: style,
              revision: model.revision,
              bins: a.levelsDb,
              binSpacingHz: a.binSpacingHz,
              markersHz: <double>[
                for (final SineComponent p in model.parts)
                  if (p.amplitude > 0) p.frequencyHz,
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          LabLegend(
            items: <(Widget, String)>[
              (labLineSample(colors.textAccent, 2), 'FFT bins'),
              (
                Container(width: 2, height: 8, color: colors.textSecondary),
                'True tone frequency',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          LabCaption(
            'Showing 0 to ${fmtHz(shownHz)}. The FFT computes $n bins; for a '
            'real signal the upper half mirrors the lower half, so bins 0 to '
            '${n ~/ 2} (0 to ${fmtHz(fs / 2)}) carry everything.',
          ),
          if (model.allSilent) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            const LabNote(
              icon: Icons.info_outline,
              message:
                  'Every amplitude is zero, so every bin sits on the floor. '
                  'Raise an amplitude in Waves or pick a lesson.',
            ),
          ],
        ],
      ),
    );
  }
}

// ── Presenter arrangements ──────────────────────────────────────────────────

/// A section label with its legend beside it, so the legend costs no line.
class _PlotHeader extends StatelessWidget {
  const _PlotHeader({required this.label, required this.legend});
  final String label;
  final List<(Widget, String)> legend;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: <Widget>[
      LabSectionLabel(label),
      const SizedBox(width: AppSpacing.md),
      Expanded(child: LabLegend(items: legend)),
    ],
  );
}

class _PresenterWaves extends StatelessWidget {
  const _PresenterWaves({required this.model});
  final FourierLabModel model;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final FourierPlotStyle style = fourierPlotStyle(context);
    final List<SineComponent> parts = model.parts;
    final bool showEach = model.showComponents && parts.length > 1;
    final bool silent = model.allSilent;
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PlotHeader(
            label: 'Time: amplitude over 10 ms',
            legend: <(Widget, String)>[
              (labLineSample(colors.textAccent, 2), 'Sum'),
              if (showEach)
                (labLineSample(colors.textTertiary, 1), 'Each sine'),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: FourierPlot(
              semantic: silent
                  ? 'Time trace over 10 milliseconds. Every amplitude is '
                        'zero, so the trace is flat.'
                  : 'Time trace over 10 milliseconds of the sum of '
                        '${parts.length} sine${parts.length == 1 ? '' : 's'}.',
              height: double.infinity,
              painter: TimeTracePainter(
                durationSeconds: kWavesWindowSeconds,
                yMax: model.yMax,
                style: style,
                revision: model.revision,
                signalAt: (double t) => FourierDsp.sumAt(parts, t),
                componentsAt: showEach
                    ? <double Function(double)>[
                        for (final SineComponent p in parts) p.valueAt,
                      ]
                    : const <double Function(double)>[],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabSectionLabel(
            'Frequency: level in dB (floor ${kWavesFloorDb ~/ 1} dB)',
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: FourierPlot(
              semantic: silent
                  ? 'Spectrum. No lines above the floor.'
                  : 'Spectrum lines: '
                        '${<String>[for (final SineComponent p in parts)
                          if (p.amplitude > 0) '${fmtHz(p.frequencyHz)} at ${fmtDb(p.levelDb)} dB'].join('; ')}.',
              height: double.infinity,
              painter: SpectrumPainter(
                maxHz: kSpectrumMaxHz,
                floorDb: kWavesFloorDb,
                style: style,
                revision: model.revision,
                lines: <SpectrumLine>[
                  for (final SineComponent p in parts)
                    (frequencyHz: p.frequencyHz, levelDb: p.levelDb),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (silent)
            const LabNote(
              icon: Icons.info_outline,
              message:
                  'Every amplitude is zero, so there is nothing to show. '
                  'Raise an amplitude.',
            )
          else
            // The lines themselves, the numbers the spectrum draws.
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  'Lines',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
                for (final SineComponent p in parts)
                  if (p.amplitude > 0)
                    Text(
                      '${fmtHz(p.frequencyHz)}  ${fmtDb(p.levelDb)} dB',
                      style: labMono(
                        context,
                      ).inlineCode.copyWith(color: colors.textPrimary),
                    ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PresenterFft extends StatelessWidget {
  const _PresenterFft({required this.model});
  final FourierLabModel model;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final FourierPlotStyle style = fourierPlotStyle(context);
    final SpectrumAnalysis a = model.analysis;
    final int n = model.n;
    final double fs = model.sampleRateHz;
    final double shownHz = math.min(kSpectrumMaxHz, fs / 2);
    final int peak = a.peakBin;
    final SpectrumWindow window = model.window;
    final SineComponent? strongest = model.strongest;
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LabStatRow(
            children: <Widget>[
              LabStat(
                label: 'Bin spacing, Fs/N',
                value: fmtHz(a.binSpacingHz),
                accent: true,
              ),
              LabStat(
                label: 'Capture time, N/Fs',
                value: fmtTime(a.captureSeconds),
              ),
              LabStat(
                label: strongest == null
                    ? 'Strongest bin'
                    : 'Strongest bin (true ${fmtDb(strongest.levelDb)} dB '
                          'at ${fmtHz(strongest.frequencyHz)})',
                value: strongest == null
                    ? 'none'
                    : '${fmtDb(a.levelsDb[peak])} dB at '
                          '${fmtHz(a.binFrequencyHz(peak))}',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _PlotHeader(
            label: 'Time: $n samples over ${fmtTime(a.captureSeconds)}',
            legend: <(Widget, String)>[
              (labDot(colors.textAccent, 3), 'Samples'),
              (
                labLineSample(colors.textSecondary, 1.5, dashed: true),
                'Window (${window.label})',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            flex: 2,
            child: FourierPlot(
              semantic:
                  'Capture of $n samples at ${fmtHz(fs)}, lasting '
                  '${fmtTime(a.captureSeconds)}, with the ${window.label} '
                  'window drawn as a dashed outline.',
              height: double.infinity,
              painter: TimeTracePainter(
                durationSeconds: a.captureSeconds,
                yMax: model.yMax,
                style: style,
                revision: model.revision,
                samples: a.samples,
                windowValues: a.windowValues,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _PlotHeader(
            label: 'Spectrum: dB full scale, 0 to ${fmtHz(shownHz)}',
            legend: <(Widget, String)>[
              (labLineSample(colors.textAccent, 2), 'FFT bins'),
              (
                Container(width: 2, height: 8, color: colors.textSecondary),
                'True tone',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            flex: 3,
            child: FourierPlot(
              semantic: model.allSilent
                  ? 'Spectrum of $n bins. Nothing above the floor.'
                  : 'Spectrum of $n bins, ${fmtHz(a.binSpacingHz)} apart, '
                        'with the ${window.label} window. Strongest bin '
                        '${fmtHz(a.binFrequencyHz(peak))} at '
                        '${fmtDb(a.levelsDb[peak])} dB full scale.',
              height: double.infinity,
              painter: SpectrumPainter(
                maxHz: shownHz,
                floorDb: kFftFloorDb,
                style: style,
                revision: model.revision,
                bins: a.levelsDb,
                binSpacingHz: a.binSpacingHz,
                markersHz: <double>[
                  for (final SineComponent p in model.parts)
                    if (p.amplitude > 0) p.frequencyHz,
                ],
              ),
            ),
          ),
          if (model.allSilent) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            const LabNote(
              icon: Icons.info_outline,
              message:
                  'Every amplitude is zero, so every bin sits on the floor.',
            ),
          ],
        ],
      ),
    );
  }
}
