// Fourier and FFT: Wi-Fi Lab tool (fourier-fft), part 1.
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
// CLEAN-ROOM BUILD (2026-09-25) per myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/11-fourier-part1.md and the research brief §4 and §5. All
// math lives in FourierDsp (lib/services/wifi_lab/fourier_dsp.dart). No
// third-party Fourier tool's code or visuals were consulted.
//
// STRUCTURE (Keith, 2026-09-25): stage and controls are separate widgets.
//   fourier_fft_model.dart     FourierLabModel (state), FourierSound (audio)
//   fourier_fft_stage.dart     FourierStage: the plots only
//   fourier_fft_controls.dart  FourierModeSelector, FourierControls
//   fourier_fft_painters.dart  the CustomPainters
//   fourier_fft_parts.dart     shared cards, rows, formatters
// This screen only owns the model's lifetime and stacks the three for phone
// and desktop. A presenter layout can place FourierStage beside the
// controls with no change to either.
//
// GROWTH: later parts (swept vs FFT race, OFDM as an inverse FFT) add a
// FourierMode value and a case in the stage and the controls. At 4+ modes the
// selector turns itself from a toggle into a dropdown (GL-003 §8.14).
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
// MOTION (§8.8): nothing animates. Plots redraw only when an input changes,
// so reduced motion needs no special path.
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

import 'package:flutter/material.dart';

import '../../../services/audio/tone_engine.dart';
import '../../../services/wifi_lab/fourier_dsp.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'fourier_fft_controls.dart';
import 'fourier_fft_model.dart';
import 'fourier_fft_parts.dart';
import 'fourier_fft_stage.dart';

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
  String _buildCopyText() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fourier and FFT'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
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
