// Controls for the Wi-Fi Lab "Fourier and FFT" tool (fourier-fft): the mode
// selector, the inputs and the readouts. They write FourierLabModel and never
// draw a plot, so a presenter layout can put them beside FourierStage
// unchanged.
//
//   FourierModeSelector: AppToggle while there are 2-3 modes; at 4+ it becomes
//                        an AppSelect on its own (GL-003 §8.14).
//   FourierControls:     Waves -> sound, preset, sine rows, explainer.
//                        FFT   -> lesson, analyzer settings, readouts, and the
//                                 Wi-Fi closing card.

import 'package:flutter/material.dart';

import '../../../services/audio/tone_engine.dart';
import '../../../services/wifi_lab/fourier_dsp.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../labeled_field.dart';
import 'fourier_fft_model.dart';
import 'fourier_fft_parts.dart';

class FourierModeSelector extends StatelessWidget {
  const FourierModeSelector({super.key, required this.model});
  final FourierLabModel model;

  static String blurb(FourierMode m) => switch (m) {
    FourierMode.waves =>
      'Build a signal from sines and see it two ways: amplitude over time, '
          'and which frequencies it contains.',
    FourierMode.fft =>
      'Sample the same signal and compute its spectrum the way an analyzer '
          'does: N samples at Fs, a window, and an FFT.',
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (BuildContext context, _) {
        // §8.14: a segmented toggle holds 2-3 options; 4+ is a Select.
        final Widget selector = FourierMode.values.length <= 3
            ? AppToggle<FourierMode>(
                label: 'Mode',
                value: model.mode,
                expand: true,
                items: <AppToggleItem<FourierMode>>[
                  for (final FourierMode m in FourierMode.values) (m, m.label),
                ],
                onChanged: model.setMode,
              )
            : LabeledField(
                label: 'Mode',
                semanticLabel: 'Mode',
                field: AppSelect<FourierMode>(
                  value: model.mode,
                  semanticLabel: 'Mode',
                  items: <AppSelectItem<FourierMode>>[
                    for (final FourierMode m in FourierMode.values)
                      (m, m.label),
                  ],
                  onChanged: model.setMode,
                ),
              );
        return LabCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              selector,
              const SizedBox(height: AppSpacing.xs),
              LabCaption(blurb(model.mode)),
            ],
          ),
        );
      },
    );
  }
}

class FourierControls extends StatelessWidget {
  const FourierControls({super.key, required this.model, required this.sound});

  final FourierLabModel model;
  final FourierSound sound;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[model, sound]),
      builder: (BuildContext context, _) {
        const Widget gap = SizedBox(height: AppSpacing.sm);
        final List<Widget> cards = switch (model.mode) {
          FourierMode.waves => <Widget>[
            _SoundCard(model: model, sound: sound),
            gap,
            _SinesCard(model: model),
            gap,
            const _WavesExplainer(),
          ],
          FourierMode.fft => <Widget>[
            _LessonCard(model: model),
            gap,
            _AnalyzerCard(model: model),
            gap,
            _ReadoutsCard(model: model),
            gap,
            const _WifiBridgeCard(),
          ],
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: cards,
        );
      },
    );
  }
}

// ── Waves ───────────────────────────────────────────────────────────────────

class _SoundCard extends StatelessWidget {
  const _SoundCard({required this.model, required this.sound});
  final FourierLabModel model;
  final FourierSound sound;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool unavailable = sound.status == ToneEngineStatus.unavailable;
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LabSectionLabel('Sound'),
          const SizedBox(height: AppSpacing.xs),
          if (unavailable) ...<Widget>[
            const _AudioUnavailableBanner(),
            const SizedBox(height: AppSpacing.xs),
          ],
          if (sound.isOn)
            OutlinedButton.icon(
              onPressed: sound.stop,
              icon: const Icon(Icons.stop_rounded),
              label: const Text('Stop sound'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.textPrimary,
                side: BorderSide(color: colors.borderStrong, width: 1.5),
                minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
              ),
            )
          else
            FilledButton.icon(
              onPressed: sound.canStart ? sound.start : null,
              icon: const Icon(Icons.volume_up_rounded),
              label: Text(sound.isStarting ? 'Starting...' : 'Play sound'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          LabCaption(
            model.allSilent
                ? 'Every amplitude is zero, so there is nothing to play.'
                : 'Plays each sine as its own tone at the frequency shown, as '
                      'loud as its amplitude. The phase sliders do not change '
                      'the sound. Mind your volume.',
          ),
        ],
      ),
    );
  }
}

class _AudioUnavailableBanner extends StatelessWidget {
  const _AudioUnavailableBanner();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.statusWarningFill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.statusWarning, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.volume_off_outlined,
            size: 18,
            color: colors.statusWarning,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'No audio output detected. Check that an output device is '
              'connected and not muted, then press Play sound again. The '
              'plots and numbers still work.',
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

class _SinesCard extends StatelessWidget {
  const _SinesCard({required this.model});
  final FourierLabModel model;

  static String presetBlurb(WavePreset p) => switch (p) {
    WavePreset.oneSine =>
      'One 1 kHz sine: ten cycles in 10 ms, one line at 1 kHz.',
    WavePreset.square =>
      'Odd harmonics of 200 Hz at 1, 1/3, 1/5, 1/7 and 1/9. Five sines '
          'already look square. Set every phase to 0 and the same lines make '
          'a different shape.',
    WavePreset.twoClose =>
      '1.0 and 1.1 kHz at equal level. In time they beat: the sum swells and '
          'fades 100 times a second. In frequency they are two lines.',
    WavePreset.weakNeighbor =>
      'A strong tone at 2.05 kHz and one 40 dB weaker at 2.7 kHz. The weak '
          'one is invisible in the time trace and plain in the spectrum. '
          'Switch to FFT to see what an analyzer makes of it.',
    WavePreset.custom => 'Your own mix. Pick a preset to start over.',
  };

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final List<SineComponent> parts = model.parts;
    final bool full = !model.canAddSine;
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LabeledField(
            label: 'Start from',
            semanticLabel: 'Start from preset',
            field: AppSelect<WavePreset>(
              value: model.preset,
              semanticLabel: 'Start from preset',
              items: <AppSelectItem<WavePreset>>[
                for (final WavePreset p in WavePreset.values)
                  if (p != WavePreset.custom ||
                      model.preset == WavePreset.custom)
                    (p, p.label),
              ],
              onChanged: model.applyPreset,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          LabCaption(presetBlurb(model.preset)),
          if (parts.length > 1) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            MergeSemantics(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Show each sine behind the sum',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Switch(
                    value: model.showComponents,
                    onChanged: model.setShowComponents,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          LabSectionLabel('Sines (${parts.length} of $kMaxSines)'),
          for (int i = 0; i < parts.length; i++) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _SineRow(model: model, index: i),
          ],
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: full ? null : model.addSine,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add a sine'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.textPrimary,
              side: BorderSide(
                color: full ? colors.disabledFill : colors.borderStrong,
                width: 1.5,
              ),
              minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
            ),
          ),
          if (full) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            const LabNote(
              icon: Icons.info_outline,
              message:
                  'Five sines is the most this tool sums. Remove one to add '
                  'another.',
            ),
          ],
        ],
      ),
    );
  }
}

class _SineRow extends StatelessWidget {
  const _SineRow({required this.model, required this.index});
  final FourierLabModel model;
  final int index;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final SineComponent p = model.parts[index];
    final String name = 'Sine ${index + 1}';
    return Container(
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xxs,
        AppSpacing.xxs,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: colors.textPrimary),
                ),
              ),
              IconButton(
                onPressed: model.canRemoveSine
                    ? () => model.removeSine(index)
                    : null,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Remove $name',
                color: colors.textSecondary,
              ),
            ],
          ),
          _SliderRow(
            label: 'Frequency',
            value: fmtHz(p.frequencyHz),
            slider: Slider(
              value: p.frequencyHz.clamp(kMinToneHz, kMaxToneHz),
              min: kMinToneHz,
              max: kMaxToneHz,
              divisions: ((kMaxToneHz - kMinToneHz) / 10).round(),
              onChanged: (double v) => model.updateSine(
                index,
                p.copyWith(frequencyHz: v.roundToDouble()),
              ),
              activeColor: colors.primary,
              // The rows sit on surface2, where disabledFill vanishes; the
              // idle track takes the §8.14 interactive-boundary token.
              inactiveColor: colors.borderStrong,
              semanticFormatterCallback: (double v) =>
                  '$name frequency ${fmtHz(v.roundToDouble())}',
            ),
          ),
          _SliderRow(
            label: 'Amplitude',
            value: fmtAmpWithDb(p),
            slider: Slider(
              value: p.amplitude.clamp(0, 1),
              min: 0,
              max: 1,
              divisions: 100,
              onChanged: (double v) => model.updateSine(
                index,
                p.copyWith(amplitude: (v * 100).roundToDouble() / 100),
              ),
              activeColor: colors.primary,
              // The rows sit on surface2, where disabledFill vanishes; the
              // idle track takes the §8.14 interactive-boundary token.
              inactiveColor: colors.borderStrong,
              semanticFormatterCallback: (double v) =>
                  '$name amplitude ${fmtAmp(v)}',
            ),
          ),
          _SliderRow(
            label: 'Phase',
            value: fmtDeg(p.phaseDeg),
            slider: Slider(
              value: p.phaseDeg.clamp(-180, 180),
              min: -180,
              max: 180,
              divisions: 72,
              onChanged: (double v) => model.updateSine(
                index,
                p.copyWith(phaseDeg: v.roundToDouble()),
              ),
              activeColor: colors.primary,
              // The rows sit on surface2, where disabledFill vanishes; the
              // idle track takes the §8.14 interactive-boundary token.
              inactiveColor: colors.borderStrong,
              semanticFormatterCallback: (double v) =>
                  '$name phase ${v.toStringAsFixed(0)} degrees',
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.slider,
  });

  final String label;
  final String value;
  final Widget slider;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.xs),
          child: Row(
            children: <Widget>[
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
              const Spacer(),
              Text(
                value,
                style: labMono(
                  context,
                ).inlineCode.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ),
        slider,
      ],
    );
  }
}

class _WavesExplainer extends StatelessWidget {
  const _WavesExplainer();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LabSectionLabel('What you are seeing'),
          const SizedBox(height: AppSpacing.xs),
          for (final String s in <String>[
            'A sine has three knobs. Amplitude sets how tall it is, frequency '
                'sets how many cycles fit in a second, and phase sets where '
                'in its cycle it starts.',
            'Any signal is a sum of sines. The time trace shows the sum; the '
                'spectrum shows which sines are in it and how strong each '
                'one is.',
            'A real analyzer never sees these ideal lines. It sees a short '
                'run of samples and computes the spectrum from them. The FFT '
                'mode shows what that costs.',
          ]) ...<Widget>[
            Text(
              s,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

// ── FFT ─────────────────────────────────────────────────────────────────────

class _LessonCard extends StatelessWidget {
  const _LessonCard({required this.model});
  final FourierLabModel model;

  static String hint(FftLesson l) => switch (l) {
    FftLesson.free =>
      'The signal is the one built in Waves. Change the window, the sample '
          'rate or N and watch the spectrum and the readouts, or pick a '
          'lesson.',
    FftLesson.weakNeighbor =>
      'The tone at 2.7 kHz is 40 dB weaker than the one at 2.05 kHz. The '
          'strong tone falls between bins, and with Rectangular its leakage '
          'buries the weak one. Switch the window to Blackman-Harris and the '
          'weak tone appears at -40 dB.',
    FftLesson.betweenBins =>
      'The bins are 100 Hz apart and the tone is at 2.05 kHz, half way '
          'between two of them. With Rectangular the peak reads almost 4 dB '
          'low. Switch to Flat top: the peak reads the true 0 dB, and it gets '
          'wider.',
    FftLesson.halveN =>
      'Two tones 300 Hz apart show as two peaks with 100 Hz bins. Press '
          'Halve N: the bins widen to 200 Hz, the capture drops from 10 ms '
          'to 5 ms, and the two peaks merge into one.',
  };

  @override
  Widget build(BuildContext context) {
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LabeledField(
            label: 'Lesson',
            semanticLabel: 'Lesson',
            field: AppSelect<FftLesson>(
              value: model.lesson,
              semanticLabel: 'Lesson',
              items: <AppSelectItem<FftLesson>>[
                for (final FftLesson l in FftLesson.values) (l, l.label),
              ],
              onChanged: model.applyLesson,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          LabNote(icon: Icons.lightbulb_outline, message: hint(model.lesson)),
        ],
      ),
    );
  }
}

class _AnalyzerCard extends StatelessWidget {
  const _AnalyzerCard({required this.model});
  final FourierLabModel model;

  @override
  Widget build(BuildContext context) {
    final int n = model.n;
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LabSectionLabel('Analyzer settings'),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Window',
            semanticLabel: 'Window',
            field: AppSelect<SpectrumWindow>(
              value: model.window,
              semanticLabel: 'Window',
              items: <AppSelectItem<SpectrumWindow>>[
                for (final SpectrumWindow w in SpectrumWindow.values)
                  (
                    w,
                    '${w.label} (${w.publishedSidelobeDb.toStringAsFixed(0)} '
                        'dB)',
                  ),
              ],
              onChanged: model.setWindow,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          const LabCaption(
            'The number after each window is its published highest sidelobe: '
            'how far below the peak its leakage stays.',
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: LabeledField(
                  label: 'Sample rate (Fs)',
                  semanticLabel: 'Sample rate',
                  field: AppSelect<double>(
                    value: model.sampleRateHz,
                    semanticLabel: 'Sample rate',
                    items: <AppSelectItem<double>>[
                      for (final double f in kSampleRates) (f, fmtHz(f)),
                    ],
                    onChanged: model.setSampleRate,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: LabeledField(
                  label: 'FFT size (N)',
                  semanticLabel: 'FFT size N',
                  field: AppSelect<int>(
                    value: n,
                    semanticLabel: 'FFT size N',
                    items: <AppSelectItem<int>>[
                      for (final int s in FourierDsp.fftSizes) (s, '$s'),
                    ],
                    onChanged: model.setN,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: LabOutlinedAction(
                  label: 'Halve N',
                  icon: Icons.remove_rounded,
                  semantic: model.canHalveN
                      ? 'Halve N to ${n ~/ 2}'
                      : 'Halve N, unavailable: 64 is the smallest',
                  enabled: model.canHalveN,
                  onTap: model.halveN,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: LabOutlinedAction(
                  label: 'Double N',
                  icon: Icons.add_rounded,
                  semantic: model.canDoubleN
                      ? 'Double N to ${n * 2}'
                      : 'Double N, unavailable: 4096 is the largest',
                  enabled: model.canDoubleN,
                  onTap: model.doubleN,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadoutsCard extends StatelessWidget {
  const _ReadoutsCard({required this.model});
  final FourierLabModel model;

  @override
  Widget build(BuildContext context) {
    final SpectrumAnalysis a = model.analysis;
    final SpectrumWindow w = model.window;
    final int n = model.n;
    final double measuredSide = FourierDsp.measuredSidelobeAt(w, n);
    final double scallop = FourierDsp.scallopingLossDb(a.windowValues);
    final int peak = a.peakBin;
    final SineComponent? strongest = model.strongest;
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LabSectionLabel('Readouts'),
          const SizedBox(height: AppSpacing.xs),
          LabReadoutRow(
            label: 'Bin spacing',
            value: '${fmtHz(a.binSpacingHz)} (Fs/N)',
            emphasize: true,
          ),
          LabReadoutRow(
            label: 'Capture time',
            value: '${fmtTime(a.captureSeconds)} (N/Fs)',
            emphasize: true,
          ),
          LabReadoutRow(
            label: 'ENBW',
            value: '${a.enbwBins.toStringAsFixed(2)} bins',
          ),
          LabReadoutRow(label: 'RBW', value: fmtHz(a.rbwHz)),
          LabReadoutRow(
            label: 'Highest sidelobe',
            value:
                '${w.publishedSidelobeDb.toStringAsFixed(0)} dB published; '
                '${fmtDb(measuredSide)} dB measured at N = $n',
          ),
          LabReadoutRow(
            label: 'Scalloping loss',
            value:
                '${scallop.toStringAsFixed(2)} dB for a tone half way '
                'between bins',
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            liveRegion: true,
            child: LabReadoutRow(
              label: 'Strongest bin',
              value: strongest == null
                  ? 'nothing above the floor'
                  : '${fmtDb(a.levelsDb[peak])} dB at '
                        '${fmtHz(a.binFrequencyHz(peak))}; true '
                        '${fmtDb(strongest.levelDb)} dB at '
                        '${fmtHz(strongest.frequencyHz)}',
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const LabCaption(
            'ENBW is computed from the window itself: '
            'N x sum(w²) / (sum w)², and RBW = ENBW x Fs/N. More samples give finer bins '
            'and a longer capture; bin spacing times capture time is always '
            '1.',
          ),
        ],
      ),
    );
  }
}

class _WifiBridgeCard extends StatelessWidget {
  const _WifiBridgeCard();

  static const double _wifiFs = 20e6;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LabSectionLabel('The Wi-Fi receiver is an FFT analyzer'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'A 20 MHz Wi-Fi receiver samples at 20 MS/s and runs an FFT on '
            'each symbol. Its bins are the subcarriers, so the same two '
            'formulas give the Wi-Fi numbers.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          const LabSectionLabel(
            'Legacy OFDM (802.11a/g/n/ac): 20 MS/s, N = 64',
          ),
          LabReadoutRow(
            label: 'Bin spacing',
            value: fmtHz(FourierDsp.binSpacingHz(_wifiFs, 64)),
            emphasize: true,
          ),
          LabReadoutRow(
            label: 'Frame time',
            value: fmtTime(FourierDsp.captureSeconds(_wifiFs, 64)),
          ),
          const SizedBox(height: AppSpacing.xs),
          const LabSectionLabel('HE (802.11ax/be): 20 MS/s, N = 256'),
          LabReadoutRow(
            label: 'Bin spacing',
            value: fmtHz(FourierDsp.binSpacingHz(_wifiFs, 256)),
            emphasize: true,
          ),
          LabReadoutRow(
            label: 'Frame time',
            value: fmtTime(FourierDsp.captureSeconds(_wifiFs, 256)),
          ),
          const SizedBox(height: AppSpacing.xs),
          const LabCaption(
            'Four times the samples per symbol gives bins a quarter as wide '
            'and a symbol four times as long: the same trade as N above. The '
            'guard interval is added on top of these times.',
          ),
        ],
      ),
    );
  }
}
