// Fourier and FFT: Wi-Fi Lab tool (fourier-fft), parts 1 and 2.
//
// Mode 1, Waves: up to five sines, each with amplitude, frequency and phase.
// The time trace and the ideal line spectrum are the same signal seen two
// ways, both live. Optional sound plays the sum.
//
// Mode 2, FFT: the same signal sampled at Fs with N points, windowed and
// transformed, the way a spectrum analyzer does it. Readouts for bin spacing
// Fs/N, capture time N/Fs, and ENBW computed from the window. Lesson presets
// set up leakage, scalloping and the N trade-off; a closing card shows that a
// Wi-Fi receiver is an FFT analyzer with 312.5 kHz bins.
//
// Mode 3, Swept vs FFT race: one synthetic 2.4 GHz scene watched by a swept
// analyzer (sweep time k x Span / RBW^2) and a gapless FFT analyzer, drawn as
// two waterfalls in the GL-003 §8.22 analyzer rainbow with a dBm legend, and
// a count of Bluetooth hops and microwave pulses each caught.
//
// Mode 4, OFDM is an inverse FFT: toggle subcarriers, see the IFFT's symbol,
// the cyclic prefix, each subcarrier's sinc (orthogonality), and the
// receiver's FFT recovering the points; switch legacy / HE numerology.
//
// CLEAN-ROOM BUILD (2026-09-25) per myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/11-fourier-part1.md, 11-fourier-part2.md and the research
// brief §4 and §5. All math lives in lib/services/wifi_lab/ (fourier_dsp,
// fourier_race, fourier_ofdm). No third-party Fourier tool's code or visuals
// were consulted.
//
// STRUCTURE (Keith, 2026-09-25): stage and controls are separate widgets.
//   fourier_fft_model.dart     FourierLabModel (state), FourierSound (audio)
//   fourier_fft_stage.dart     FourierStage: the plots only
//   fourier_fft_controls.dart  FourierModeSelector, FourierControls
//   fourier_fft_painters.dart  the CustomPainters
//   fourier_fft_parts.dart     shared cards, rows, formatters
// This screen only owns the model's lifetime and stacks the three for phone
// and desktop. The Present button (desktop and tablet windows) opens the
// same stage and controls over the SAME model in the presenter layout
// (lib/widgets/presenter/, spec 00), each mode with its own keys:
//   1 to 4   the four modes (every mode)
//   Waves    Space sound on or off; Up and Down the picked sine's frequency;
//            R back to one sine
//   FFT      Up and Down double or halve N; W the next window; R the
//            analyzer back to Hann, 25.6 kHz, N = 256
//   Race     Space run, pause, resume; Right one step; R an empty run;
//            Up and Down the RBW
//   OFDM     Right the next subcarrier highlighted; Up and Down the
//            modulation; R back to how the mode opens
//
// GROWTH: a mode is a FourierMode value plus a case in the stage and the
// controls. At 4+ modes the selector is a dropdown (GL-003 §8.14); part 2
// took it there. Mode 3 and 4 keep their state in FourierLabModel.race and
// .ofdm and their widgets in fourier_fft_race_* and fourier_fft_ofdm_*.
//
// PLAYBACK (mode 3): the race opens finished. Run the race replays it over
// four seconds, driven by the race state's own Ticker (it moved there from
// this screen for the presenter layout, whose route mutes this one); with
// reduced motion on it jumps straight to the end.
//
// AUDIO: through the hear-frequency ToneEngine seam, unmodified; one engine
// per sine because the seam is one voice per engine. Starts on the Play tap
// (web autoplay needs a gesture); stops when the app backgrounds, when the
// mode leaves Waves, and on exit. Phase is not reproduced; the screen says so.
//
// THEME: chrome from context.colors (dark §8 / light §8.20). Lime marks the
// measured quantity. No categorical palette (§8.15). Status hue only on the
// audio-unavailable verdict, paired with words. ASCII copy, no em dashes.
//
// MOTION (§8.8): only the race playback animates, and only when asked;
// reduced motion skips it. Everything else redraws on input only.
//
// States (SOP-007 §5):
//   - loading     -> none: every number is computed synchronously on-device
//   - empty       -> every amplitude at zero: plots keep their axes, a note
//                    says to raise an amplitude, Play is disabled
//   - error       -> audio engine unavailable: warning banner in words, the
//                    math and plots keep working
//   - success     -> live plots and readouts
//   - disabled    -> Add at five sines, Remove on the last sine, Halve at
//                    N = 64, Double at N = 4096, Play with nothing to play
//   - interactive -> themed Material controls with the global focus ring;
//                    plots carry worded Semantics labels

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../router/app_router.dart';
import '../../../services/audio/tone_engine.dart';
import '../../../services/wifi_lab/fourier_dsp.dart';
import '../../../services/wifi_lab/fourier_ofdm.dart';
import '../../../services/wifi_lab/fourier_race.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'fourier_fft_controls.dart';
import 'fourier_fft_model.dart';
import 'fourier_fft_parts.dart';
import 'fourier_fft_race_state.dart';
import 'fourier_fft_stage.dart';
import 'wifi_lab_presenter_follow.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kFourierFftToolId = 'fourier-fft';

class FourierFftScreen extends StatefulWidget {
  const FourierFftScreen({
    super.key,
    this.toneEngineFactory,
    this.initialMode = FourierMode.waves,
  });

  /// Test seam: builds one tone voice. Defaults to the hear-frequency
  /// SoLoudToneEngine. Widget tests pass a fake so no audio device is needed.
  final ToneEngine Function()? toneEngineFactory;

  final FourierMode initialMode;

  @override
  State<FourierFftScreen> createState() => _FourierFftScreenState();
}

class _FourierFftScreenState extends State<FourierFftScreen>
    with WidgetsBindingObserver {
  late final FourierLabModel _model = FourierLabModel(
    initialMode: widget.initialMode,
  );
  late final FourierSound _sound = FourierSound(
    _model,
    engineFactory: widget.toneEngineFactory,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The race's own clock (in FourierRaceState) jumps to the end with
    // reduced motion on.
    _model.race.reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sound.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A tone never runs unattended.
    if (state != AppLifecycleState.resumed && _sound.isOn) _sound.stop();
  }

  // Copy payload (GL-003 §8.16).
  String _buildCopyText() => switch (_model.mode) {
    FourierMode.waves || FourierMode.fft => _signalCopy(),
    FourierMode.race => _raceCopy(),
    FourierMode.ofdm => _ofdmCopy(),
  };

  String _signalCopy() {
    final StringBuffer b = StringBuffer()..writeln('Fourier and FFT');
    final List<SineComponent> parts = _model.parts;
    for (int i = 0; i < parts.length; i++) {
      final SineComponent p = parts[i];
      b.writeln(
        'Sine ${i + 1}: ${fmtHz(p.frequencyHz)}, amplitude '
        '${fmtAmpWithDb(p)}, phase ${fmtDeg(p.phaseDeg)}',
      );
    }
    if (_model.mode == FourierMode.fft) {
      final SpectrumAnalysis a = _model.analysis;
      b
        ..writeln(
          'Sample rate: ${fmtHz(_model.sampleRateHz)}, N = ${_model.n}, '
          'window: ${_model.window.label}',
        )
        ..writeln('Bin spacing (Fs/N): ${fmtHz(a.binSpacingHz)}')
        ..writeln('Capture time (N/Fs): ${fmtTime(a.captureSeconds)}')
        ..writeln('ENBW: ${a.enbwBins.toStringAsFixed(2)} bins')
        ..writeln('RBW: ${fmtHz(a.rbwHz)}');
    }
    return b.toString().trimRight();
  }

  String _raceCopy() {
    final FourierRaceState r = _model.race;
    final RaceRun run = r.run;
    final RaceTally bt = run.tally(RaceSource.bluetooth);
    final RaceTally mw = run.tally(RaceSource.microwave);
    return <String>[
      'Fourier and FFT: swept vs FFT race (synthetic scene)',
      'Span: ${fmtMhz(r.spanMhz)}, RBW: ${fmtHz(r.rbwHz)}, run: '
          '${fmtTime(run.runSeconds)}',
      'Sweep time (k x Span / RBW^2, k = ${SweptAnalyzer.kSweepK}): '
          '${fmtTime(run.swept.sweepSeconds)}',
      'Bluetooth hops caught: swept ${bt.sweptCaught} of ${bt.total}, '
          'FFT ${bt.fftCaught} of ${bt.total}',
      'Microwave pulses caught: swept ${mw.sweptCaught} of ${mw.total}, '
          'FFT ${mw.fftCaught} of ${mw.total}',
    ].join('\n');
  }

  String _ofdmCopy() {
    final OfdmSymbol s = _model.ofdm.symbol;
    return <String>[
      'Fourier and FFT: OFDM is an inverse FFT',
      '${s.numerology.label}: spacing ${fmtHz(s.spacingHz)}, useful symbol '
          '${fmtTime(s.usefulSeconds)}, GI ${fmtTime(s.guardSeconds)}, total '
          '${fmtTime(s.totalSeconds)}',
      'N = ${s.n}, sample rate ${fmtHz(s.sampleRateHz)}, cyclic prefix '
          '${s.cpSamples} samples, ${s.points.length} subcarriers on, '
          '${_model.ofdm.modulation.label}',
      'Largest error, sent vs recovered by the FFT: '
          '${_model.ofdm.maxRecoveryError.toStringAsExponential(1)}',
    ].join('\n');
  }

  // ── Presenter ─────────────────────────────────────────────────────────

  /// Keys 1 to 4 switch modes in every mode.
  List<PresenterExtraKey> get _modeKeys => <PresenterExtraKey>[
    for (int i = 0; i < FourierMode.values.length; i++)
      PresenterExtraKey(
        key: <LogicalKeyboardKey>[
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.digit2,
          LogicalKeyboardKey.digit3,
          LogicalKeyboardKey.digit4,
        ][i],
        keyLabel: '${i + 1}',
        description: '${FourierMode.values[i].label} mode',
        onPressed: () => _model.setMode(FourierMode.values[i]),
      ),
  ];

  /// What the keys do in the current mode (they change with it).
  PresenterActions get _presenterActions {
    final FourierLabModel m = _model;
    switch (m.mode) {
      case FourierMode.waves:
        return PresenterActions(
          playPause: () =>
              unawaited(_sound.isOn ? _sound.stop() : _sound.start()),
          reset: () => m.applyPreset(WavePreset.oneSine),
          sliderDown: () => m.nudgeEditFrequency(-1),
          sliderUp: () => m.nudgeEditFrequency(1),
          sliderLabel: 'Picked sine frequency',
          extra: _modeKeys,
        );
      case FourierMode.fft:
        return PresenterActions(
          reset: m.resetAnalyzer,
          sliderDown: m.halveN,
          sliderUp: m.doubleN,
          sliderLabel: 'FFT size N',
          extra: <PresenterExtraKey>[
            PresenterExtraKey(
              key: LogicalKeyboardKey.keyW,
              keyLabel: 'W',
              description: 'Next window',
              onPressed: m.nextWindow,
            ),
            ..._modeKeys,
          ],
        );
      case FourierMode.race:
        return PresenterActions(
          playPause: m.race.playPause,
          step: m.race.step,
          reset: m.race.rewind,
          sliderDown: () => m.race.nudgeRbw(-1),
          sliderUp: () => m.race.nudgeRbw(1),
          sliderLabel: 'RBW',
          extra: _modeKeys,
        );
      case FourierMode.ofdm:
        return PresenterActions(
          step: m.ofdm.highlightNext,
          reset: m.ofdm.reset,
          sliderDown: () => m.ofdm.nudgeModulation(-1),
          sliderUp: () => m.ofdm.nudgeModulation(1),
          sliderLabel: 'Modulation',
          extra: _modeKeys,
        );
    }
  }

  /// The presenter layout over this screen's model (shared, not copied),
  /// rebuilt when the mode changes so the keys follow it.
  Widget _presenter(BuildContext context) => PresenterFollow(
    listenable: _model,
    select: () => _model.mode,
    builder: (BuildContext context) => PresenterLayout(
      title: 'Fourier and FFT',
      stage: FourierStage(model: _model),
      controls: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FourierModeSelector(model: _model),
          const SizedBox(height: AppSpacing.sm),
          FourierControls(model: _model, sound: _sound),
        ],
      ),
      actions: _presenterActions,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fourier and FFT'),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(toolRoute: AppRouter.fourierFft, builder: _presenter),
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool isDesktop = constraints.maxWidth >= 720;
            final double edge = isDesktop
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.calculatorMaxWidth,
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    edge,
                    AppSpacing.sm,
                    edge,
                    edge + AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      FourierModeSelector(model: _model),
                      const SizedBox(height: AppSpacing.sm),
                      FourierStage(
                        model: _model,
                        plotHeight: isDesktop ? 200 : 176,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      FourierControls(model: _model, sound: _sound),
                      ToolHelpFooter(toolId: kFourierFftToolId),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
