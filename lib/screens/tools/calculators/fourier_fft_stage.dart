// FourierStage: the plots for the Wi-Fi Lab "Fourier and FFT" tool
// (fourier-fft). It reads FourierLabModel and draws; it holds no inputs, so a
// presenter layout can put it beside FourierControls unchanged.
//
//   Waves: time trace (10 ms) above, ideal line spectrum (dB, -60 dB floor).
//   FFT:   the N captured samples with the window outline above, the N-bin
//          spectrum in dB full scale (-120 dB floor) with true-tone ticks.
//
// Lime marks the measured quantity (the sum, the spectrum). Individual sines,
// the window and the ticks are neutral (§8.15: no categorical palette).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/fourier_dsp.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import 'fourier_fft_model.dart';
import 'fourier_fft_painters.dart';
import 'fourier_fft_parts.dart';

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
        switch (model.mode) {
          case FourierMode.waves:
            return _WavesStage(model: model, plotHeight: plotHeight);
          case FourierMode.fft:
            return _FftStage(model: model, plotHeight: plotHeight);
        }
      },
    );
  }
}

FourierPlotStyle _plotStyle(BuildContext context) {
  final AppColorScheme colors = context.colors;
  return FourierPlotStyle(
    signal: colors.textAccent,
    component: colors.textTertiary.withValues(alpha: 0.7),
    window: colors.textSecondary,
    grid: colors.border,
    axis: colors.borderStrong,
    marker: colors.textSecondary,
    labelStyle: Theme.of(
      context,
    ).textTheme.labelSmall!.copyWith(color: colors.textTertiary),
  );
}

class _Plot extends StatelessWidget {
  const _Plot({
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
    final FourierPlotStyle style = _plotStyle(context);
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
          _Plot(
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
          _Plot(
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
    final FourierPlotStyle style = _plotStyle(context);
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
          _Plot(
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
          _Plot(
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
