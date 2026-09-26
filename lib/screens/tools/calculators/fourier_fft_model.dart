// State for the Wi-Fi Classroom "Fourier and FFT" tool (fourier-fft).
//
// The screen is split into a stage (the plots, FourierStage) and controls
// (inputs and readouts, FourierModeSelector + FourierControls), so a later
// presenter layout can place them side by side without rewriting either.
// Both read and write this one model:
//   - FourierLabModel: the mode, the signal (up to five sines), the analyzer
//     settings, and the cached FFT of the current capture.
//   - FourierSound: the optional audio, one hear-frequency ToneEngine voice
//     per sine. It follows the model and stops itself when the model leaves
//     the Waves mode.
//   - Part 2: FourierLabModel.race (mode 3, fourier_fft_race_state.dart) and
//     FourierLabModel.ofdm (mode 4, fourier_fft_ofdm_state.dart). Both are
//     owned here and notify through this model, so it stays the one shared
//     state object the stage and the controls read.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../services/audio/tone_engine.dart';
import '../../../services/wifi_lab/fourier_dsp.dart';
import 'fourier_fft_ofdm_state.dart';
import 'fourier_fft_race_state.dart';

/// The tool's modes, in selector order. At four modes the selector is a
/// dropdown (GL-003 §8.14).
enum FourierMode {
  waves('Waves'),
  fft('FFT'),
  race('Swept vs FFT race'),
  ofdm('OFDM is an inverse FFT');

  const FourierMode(this.label);
  final String label;
}

/// Mode 1 starting points.
enum WavePreset {
  oneSine('One sine'),
  square('Square wave (odd harmonics)'),
  twoClose('Two close tones'),
  weakNeighbor('Tone plus weak neighbor'),
  custom('Your own mix');

  const WavePreset(this.label);
  final String label;
}

/// Mode 2 lessons. Each sets the signal and the analyzer, then its hint says
/// what to change.
enum FftLesson {
  free('Free play'),
  weakNeighbor('Weak neighbor 40 dB down'),
  betweenBins('Tone between bins'),
  halveN('Halve N');

  const FftLesson(this.label);
  final String label;
}

/// Most sines the tool sums (spec: up to five).
const int kMaxSines = 5;

/// Slider range. Real audio frequencies, so the plot is exactly what plays.
const double kMinToneHz = 100;
const double kMaxToneHz = 5000;

/// Mode 1 shows 10 ms: a 100 Hz sine is one cycle, 5 kHz is fifty.
const double kWavesWindowSeconds = 0.010;

/// Both spectra stop at 6 kHz, above every tone the sliders can make.
const double kSpectrumMaxHz = 6000;

const double kWavesFloorDb = -60;
const double kFftFloorDb = -120;

/// Sample rates offered in mode 2. The lowest Nyquist (6.4 kHz) is above the
/// highest tone (5 kHz), so nothing aliases in this part.
const List<double> kSampleRates = <double>[12800, 25600, 51200, 102400];

class FourierLabModel extends ChangeNotifier {
  FourierLabModel({FourierMode initialMode = FourierMode.waves})
    : _mode = initialMode;

  FourierMode _mode;
  List<SineComponent> _parts = presetParts(WavePreset.oneSine);
  WavePreset _preset = WavePreset.oneSine;
  bool _showComponents = true;
  int _revision = 0;

  double _fs = 25600;
  int _n = 256;
  SpectrumWindow _window = SpectrumWindow.hann;
  FftLesson _lesson = FftLesson.free;

  SpectrumAnalysis? _analysis;
  int _analysisRevision = -1;

  /// Mode 3: swept vs FFT race.
  late final FourierRaceState race = FourierRaceState(_changed);

  /// Mode 4: OFDM is an inverse FFT.
  late final FourierOfdmState ofdm = FourierOfdmState(_changed);

  FourierMode get mode => _mode;
  List<SineComponent> get parts => _parts;
  WavePreset get preset => _preset;
  bool get showComponents => _showComponents;

  /// Bumped on every change; painters repaint on it.
  int get revision => _revision;
  double get sampleRateHz => _fs;
  int get n => _n;
  SpectrumWindow get window => _window;
  FftLesson get lesson => _lesson;

  bool get allSilent => _parts.every((SineComponent p) => p.amplitude <= 0);
  bool get canAddSine => _parts.length < kMaxSines;
  bool get canRemoveSine => _parts.length > 1;
  bool get canHalveN => _n > FourierDsp.fftSizes.first;
  bool get canDoubleN => _n < FourierDsp.fftSizes.last;

  /// Top of the time-trace y axis: the peak bound rounded up to 0.5, at
  /// least 1.
  double get yMax {
    final double b = FourierDsp.peakBound(_parts);
    return math.max(1, (b * 2).ceil() / 2);
  }

  /// The strongest sine (by amplitude), or null when all are silent.
  SineComponent? get strongest {
    SineComponent? best;
    for (final SineComponent p in _parts) {
      if (p.amplitude > 0 && (best == null || p.amplitude > best.amplitude)) {
        best = p;
      }
    }
    return best;
  }

  /// The FFT of the current capture, recomputed only when an input changed.
  SpectrumAnalysis get analysis {
    if (_analysis == null || _analysisRevision != _revision) {
      _analysis = FourierDsp.analyze(
        parts: _parts,
        sampleRateHz: _fs,
        n: _n,
        window: _window,
      );
      _analysisRevision = _revision;
    }
    return _analysis!;
  }

  void _changed() {
    _revision++;
    notifyListeners();
  }

  // ── Mode ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    race.dispose();
    super.dispose();
  }

  void setMode(FourierMode m) {
    if (m == _mode) return;
    _mode = m;
    // Leaving the race mid-playback shows the finished run on return.
    if (race.animating) race.setProgress(1);
    _changed();
  }

  // ── Signal ──────────────────────────────────────────────────────────────

  static List<SineComponent> presetParts(WavePreset p) {
    switch (p) {
      case WavePreset.oneSine:
      case WavePreset.custom:
        return const <SineComponent>[
          SineComponent(amplitude: 1, frequencyHz: 1000),
        ];
      case WavePreset.square:
        // Odd harmonics 1, 1/3, 1/5 ... of 200 Hz. Phase -90 turns each
        // cosine into a sine, which is the form that sums to a square.
        return <SineComponent>[
          for (int h = 1; h <= 9; h += 2)
            SineComponent(
              amplitude: 1 / h,
              frequencyHz: 200.0 * h,
              phaseDeg: -90,
            ),
        ];
      case WavePreset.twoClose:
        return const <SineComponent>[
          SineComponent(amplitude: 1, frequencyHz: 1000),
          SineComponent(amplitude: 1, frequencyHz: 1100),
        ];
      case WavePreset.weakNeighbor:
        return const <SineComponent>[
          SineComponent(amplitude: 1, frequencyHz: 2050),
          SineComponent(amplitude: 0.01, frequencyHz: 2700),
        ];
    }
  }

  void _setParts(List<SineComponent> parts, WavePreset preset) {
    _parts = List<SineComponent>.unmodifiable(parts);
    _preset = preset;
  }

  void applyPreset(WavePreset p) {
    if (p == WavePreset.custom) return;
    _setParts(presetParts(p), p);
    _lesson = FftLesson.free;
    _changed();
  }

  void updateSine(int i, SineComponent next) {
    if (i < 0 || i >= _parts.length || _parts[i] == next) return;
    final List<SineComponent> p = List<SineComponent>.of(_parts);
    p[i] = next;
    _setParts(p, WavePreset.custom);
    _lesson = FftLesson.free;
    _changed();
  }

  void addSine() {
    if (!canAddSine) return;
    final double last = _parts.last.frequencyHz;
    final double f = last + 500 <= kMaxToneHz ? last + 500 : 500;
    _setParts(<SineComponent>[
      ..._parts,
      SineComponent(amplitude: 0.5, frequencyHz: f),
    ], WavePreset.custom);
    _lesson = FftLesson.free;
    _changed();
  }

  void removeSine(int i) {
    if (!canRemoveSine || i < 0 || i >= _parts.length) return;
    _setParts(List<SineComponent>.of(_parts)..removeAt(i), WavePreset.custom);
    _lesson = FftLesson.free;
    _changed();
  }

  void setShowComponents(bool v) {
    if (v == _showComponents) return;
    _showComponents = v;
    _changed();
  }

  // ── Analyzer ────────────────────────────────────────────────────────────

  void applyLesson(FftLesson l) {
    _lesson = l;
    switch (l) {
      case FftLesson.free:
        break;
      case FftLesson.weakNeighbor:
        _setParts(
          presetParts(WavePreset.weakNeighbor),
          WavePreset.weakNeighbor,
        );
        _fs = 25600;
        _n = 256;
        _window = SpectrumWindow.rectangular;
      case FftLesson.betweenBins:
        _setParts(const <SineComponent>[
          SineComponent(amplitude: 1, frequencyHz: 2050),
        ], WavePreset.custom);
        _fs = 25600;
        _n = 256;
        _window = SpectrumWindow.rectangular;
      case FftLesson.halveN:
        _setParts(const <SineComponent>[
          SineComponent(amplitude: 1, frequencyHz: 2000),
          SineComponent(amplitude: 1, frequencyHz: 2300),
        ], WavePreset.custom);
        _fs = 25600;
        _n = 256;
        _window = SpectrumWindow.hann;
    }
    _changed();
  }

  void setWindow(SpectrumWindow w) {
    if (w == _window) return;
    _window = w;
    _changed();
  }

  void setSampleRate(double fs) {
    if (fs == _fs || !kSampleRates.contains(fs)) return;
    _fs = fs;
    _changed();
  }

  void setN(int n) {
    if (n == _n || !FourierDsp.fftSizes.contains(n)) return;
    _n = n;
    _changed();
  }

  /// Back to the analyzer the FFT mode opens with (Hann, 25.6 kHz, N 256,
  /// free play). The signal is left alone.
  void resetAnalyzer() {
    _lesson = FftLesson.free;
    _fs = 25600;
    _n = 256;
    _window = SpectrumWindow.hann;
    _changed();
  }

  /// The next window in the list, wrapping (the presenter's W key).
  void nextWindow() {
    const List<SpectrumWindow> all = SpectrumWindow.values;
    setWindow(all[(all.indexOf(_window) + 1) % all.length]);
  }

  // ── The sine the presenter panel edits ──────────────────────────────────

  int _editSine = 0;

  /// Which sine the presenter panel's sliders (and Up and Down) edit.
  int get editSine => _editSine.clamp(0, _parts.length - 1);

  void setEditSine(int i) {
    if (i < 0 || i >= _parts.length || i == editSine) return;
    _editSine = i;
    _changed();
  }

  /// The edited sine's frequency one step (50 Hz) up or down.
  void nudgeEditFrequency(int dir) {
    final SineComponent p = _parts[editSine];
    updateSine(
      editSine,
      p.copyWith(
        frequencyHz: (p.frequencyHz + 50 * dir).clamp(kMinToneHz, kMaxToneHz),
      ),
    );
  }

  void halveN() {
    if (canHalveN) setN(_n ~/ 2);
  }

  void doubleN() {
    if (canDoubleN) setN(_n * 2);
  }
}

/// Plays the model's sum of sines through the hear-frequency ToneEngine seam,
/// unmodified. The seam is one voice per engine, so this keeps one engine per
/// sine (up to five) and follows the model: frequency and loudness track the
/// sliders, a removed or silenced sine stops, and leaving the Waves mode stops
/// everything. Phase is not reproduced.
class FourierSound extends ChangeNotifier {
  FourierSound(this._model, {ToneEngine Function()? engineFactory})
    : _factory = engineFactory {
    _model.addListener(_onModel);
  }

  final FourierLabModel _model;
  final ToneEngine Function()? _factory;
  final List<ToneEngine> _voices = <ToneEngine>[];

  bool _on = false;
  bool _starting = false;
  bool _disposed = false;
  ToneEngineStatus _status = ToneEngineStatus.idle;
  bool _syncing = false;
  bool _syncAgain = false;

  /// Total loudness across all voices, so a five-sine sum cannot clip.
  static const double masterVolume = 0.5;

  bool get isOn => _on;
  bool get isStarting => _starting;
  ToneEngineStatus get status => _status;
  bool get canStart => !_on && !_starting && !_model.allSilent;

  /// Voices created so far (for tests).
  @visibleForTesting
  List<ToneEngine> get voices => List<ToneEngine>.unmodifiable(_voices);

  ToneEngine _voice(int i) {
    while (_voices.length <= i) {
      _voices.add(_factory?.call() ?? SoLoudToneEngine(initialVolume: 0));
    }
    return _voices[i];
  }

  double _volumeFor(SineComponent p) {
    final double total = FourierDsp.peakBound(_model.parts);
    return masterVolume * p.amplitude / math.max(1, total);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _onModel() {
    if (!_on) return;
    if (_model.mode != FourierMode.waves || _model.allSilent) {
      unawaited(stop());
    } else {
      unawaited(_sync());
    }
  }

  /// Call from a user gesture (web audio needs one).
  Future<void> start() async {
    if (!canStart) return;
    _starting = true;
    _notify();
    final ToneEngineStatus s = await _voice(0).init();
    if (_disposed) return;
    _starting = false;
    _status = s;
    _on = s == ToneEngineStatus.ready;
    _notify();
    await _sync();
    if (_disposed) return;
    // A voice can fail on its first playTone even after init said ready.
    if (_voices.any(
      (ToneEngine v) => v.status == ToneEngineStatus.unavailable,
    )) {
      await stop();
      _status = ToneEngineStatus.unavailable;
      _notify();
    }
  }

  Future<void> stop() async {
    _on = false;
    _notify();
    for (final ToneEngine v in _voices) {
      if (v.isPlaying) await v.stop();
    }
  }

  /// Makes the sounding voices match the model. Serialized: a burst of slider
  /// events coalesces into one extra pass instead of overlapping calls.
  Future<void> _sync() async {
    if (!_on) return;
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _syncAgain = false;
        final List<SineComponent> parts = _model.parts;
        for (int i = 0; i < kMaxSines; i++) {
          final bool want = _on && i < parts.length && parts[i].amplitude > 0;
          if (want) {
            final ToneEngine v = _voice(i);
            final SineComponent p = parts[i];
            await v.setVolume(_volumeFor(p));
            if (v.isPlaying) {
              await v.setFrequency(p.frequencyHz);
            } else {
              await v.playTone(hz: p.frequencyHz, wave: ToneWave.sine);
            }
          } else if (i < _voices.length && _voices[i].isPlaying) {
            await _voices[i].stop();
          }
        }
      } while (_syncAgain && _on && !_disposed);
    } finally {
      _syncing = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _on = false;
    _model.removeListener(_onModel);
    for (final ToneEngine v in _voices) {
      v.dispose();
    }
    super.dispose();
  }
}
