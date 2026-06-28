// ToneEngine — the swappable real-time tone-synthesis seam for the "Hear the
// Frequency" tool (hear-frequency). The flutter_soloud dependency is isolated
// to the [SoLoudToneEngine] implementation in THIS file (and nowhere else in
// the app), exactly as the build-spec requires, so a per-platform fallback is
// just a second implementation of the [ToneEngine] interface.
//
// WHY soloud (not the existing just_audio DTMF path): this tool needs LIVE
// frequency retune of a SOUNDING voice (the octave x2 / div2 demo must be heard
// smoothly through the envelope, with no stop/restart click) plus native
// oscillators (sine/square/triangle) and built-in volume faders for the
// anti-click attack/release ramp. just_audio plays pre-rendered WAV bytes and
// cannot retune without a source swap (an audible gap). See pubspec.yaml.
//
// GL-008: on-device DSP only. No subprocess, no network, no entitlement, no
// bundled executable content. Audio synthesis is in-process and sandbox-clean.
//
// WEB AUTOPLAY: browsers block audio until a user gesture. [init] is therefore
// called LAZILY on the first Play tap (a real gesture), never in initState, so
// the AudioContext resumes inside the gesture. The screen owns that timing.
//
// LIFECYCLE: the screen creates one engine, calls [playTone] / [setFrequency] /
// [setWaveform] / [setVolume] / [stop] while live, and [dispose]s on screen
// exit so a tone never runs unattended (build-spec 2.6 auto-stop safety).

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart' as soloud;

/// The oscillator timbres the tool exposes. Maps to a subset of soloud's
/// [soloud.WaveForm]; sine is the default and is the only safe choice above
/// ~5 kHz (square/triangle harmonics alias near Nyquist - build-spec 1.3.3).
enum ToneWave { sine, square, triangle, saw }

/// The engine's current readiness, surfaced to the screen so it can show an
/// honest "no audio output" state instead of pretending a tone played
/// (GL-005 / GL-008 honesty corollary).
enum ToneEngineStatus {
  /// Not yet initialized (before the first Play gesture).
  idle,

  /// Initialized and ready to sound.
  ready,

  /// Initialization failed (e.g. no output device on Windows / muted session).
  /// The screen shows a non-fatal "No audio output detected" banner.
  unavailable,
}

/// The swappable tone-synthesis contract. One sustained voice at a time: the
/// tool plays a single tone the user retunes live, not a polyphonic mix.
abstract class ToneEngine {
  /// Initialize the underlying engine. MUST be called from inside a user
  /// gesture (the Play tap) so web AudioContext resumes. Idempotent. Returns
  /// the resulting status; on failure returns [ToneEngineStatus.unavailable]
  /// and never throws to the caller.
  Future<ToneEngineStatus> init();

  /// Current readiness.
  ToneEngineStatus get status;

  /// Whether a sustained tone is currently sounding.
  bool get isPlaying;

  /// Start (or restart) a sustained tone at [hz] with [wave], ramping volume up
  /// over a short attack so it does not click on. [hz] is assumed already
  /// clamped to the audible range by the caller.
  Future<void> playTone({required double hz, required ToneWave wave});

  /// Retune the SOUNDING voice to [hz] with no stop/restart (smooth octave
  /// jump). No-op if nothing is playing.
  Future<void> setFrequency(double hz);

  /// Change the SOUNDING voice's waveform with no restart. No-op if idle.
  Future<void> setWaveform(ToneWave wave);

  /// Set the master output volume, 0..1.
  Future<void> setVolume(double zeroToOne);

  /// Stop the sounding tone with a short release ramp (no click off).
  Future<void> stop();

  /// Release all engine resources. Call from the screen's dispose().
  Future<void> dispose();
}

/// flutter_soloud implementation. The ONLY place in the app that imports
/// flutter_soloud.
class SoLoudToneEngine implements ToneEngine {
  SoLoudToneEngine({double initialVolume = 0.5})
      : _volume = initialVolume.clamp(0.0, 1.0);

  final soloud.SoLoud _soloud = soloud.SoLoud.instance;

  ToneEngineStatus _status = ToneEngineStatus.idle;
  soloud.AudioSource? _source;
  soloud.SoundHandle? _handle;
  ToneWave _wave = ToneWave.sine;
  double _volume;

  /// Attack/release fade lengths for the anti-click envelope (build-spec 1.3.2:
  /// ~10-20 ms attack, ~15-30 ms release).
  static const Duration _attack = Duration(milliseconds: 15);
  static const Duration _release = Duration(milliseconds: 25);

  static soloud.WaveForm _mapWave(ToneWave w) {
    switch (w) {
      case ToneWave.sine:
        return soloud.WaveForm.sin;
      case ToneWave.square:
        return soloud.WaveForm.square;
      case ToneWave.triangle:
        return soloud.WaveForm.triangle;
      case ToneWave.saw:
        return soloud.WaveForm.saw;
    }
  }

  @override
  ToneEngineStatus get status => _status;

  @override
  bool get isPlaying => _handle != null;

  @override
  Future<ToneEngineStatus> init() async {
    if (_status == ToneEngineStatus.ready) return _status;
    try {
      if (!_soloud.isInitialized) {
        await _soloud.init();
      }
      _status =
          _soloud.isInitialized ? ToneEngineStatus.ready : ToneEngineStatus.unavailable;
    } catch (e) {
      // No output device, blocked AudioContext, etc. - honest unavailable, no
      // crash, no faked playback (GL-008 honesty corollary).
      debugPrint('SoLoudToneEngine.init failed: $e');
      _status = ToneEngineStatus.unavailable;
    }
    return _status;
  }

  @override
  Future<void> playTone({required double hz, required ToneWave wave}) async {
    if (_status != ToneEngineStatus.ready) {
      final ToneEngineStatus s = await init();
      if (s != ToneEngineStatus.ready) return;
    }
    _wave = wave;
    try {
      // Reuse one waveform source; create it on first play.
      _source ??= await _soloud.loadWaveform(_mapWave(wave), false, 1.0, 0.0);
      final soloud.AudioSource src = _source!;
      _soloud.setWaveform(src, _mapWave(wave));
      _soloud.setWaveformFreq(src, hz);

      // Stop any prior voice cleanly, then start silent and fade up (no click).
      await _stopHandle();
      final soloud.SoundHandle h =
          _soloud.play(src, volume: 0.0, looping: true);
      _handle = h;
      _soloud.fadeVolume(h, _volume, _attack);
    } catch (e) {
      debugPrint('SoLoudToneEngine.playTone failed: $e');
      _status = ToneEngineStatus.unavailable;
    }
  }

  @override
  Future<void> setFrequency(double hz) async {
    final soloud.AudioSource? src = _source;
    if (src == null || _handle == null) return;
    try {
      _soloud.setWaveformFreq(src, hz);
    } catch (e) {
      debugPrint('SoLoudToneEngine.setFrequency failed: $e');
    }
  }

  @override
  Future<void> setWaveform(ToneWave wave) async {
    _wave = wave;
    final soloud.AudioSource? src = _source;
    if (src == null) return;
    try {
      _soloud.setWaveform(src, _mapWave(wave));
    } catch (e) {
      debugPrint('SoLoudToneEngine.setWaveform failed: $e');
    }
  }

  @override
  Future<void> setVolume(double zeroToOne) async {
    _volume = zeroToOne.clamp(0.0, 1.0);
    final soloud.SoundHandle? h = _handle;
    if (h == null) return;
    try {
      _soloud.setVolume(h, _volume);
    } catch (e) {
      debugPrint('SoLoudToneEngine.setVolume failed: $e');
    }
  }

  @override
  Future<void> stop() async {
    await _stopHandle(fadeOut: true);
  }

  Future<void> _stopHandle({bool fadeOut = false}) async {
    final soloud.SoundHandle? h = _handle;
    _handle = null;
    if (h == null) return;
    try {
      if (fadeOut) {
        _soloud.fadeVolume(h, 0.0, _release);
        await Future<void>.delayed(
          _release + const Duration(milliseconds: 10),
        );
      }
      await _soloud.stop(h);
    } catch (e) {
      debugPrint('SoLoudToneEngine.stop failed: $e');
    }
  }

  @override
  Future<void> dispose() async {
    await _stopHandle();
    final soloud.AudioSource? src = _source;
    _source = null;
    try {
      if (src != null) await _soloud.disposeSource(src);
    } catch (e) {
      debugPrint('SoLoudToneEngine.dispose failed: $e');
    }
    // Leave the shared SoLoud engine initialized for the process lifetime;
    // deinit-on-every-screen-exit thrashes the audio device. The voice is
    // stopped and the source disposed, so nothing sounds after exit.
  }

  /// The current waveform (exposed for tests / debug).
  @visibleForTesting
  ToneWave get debugWave => _wave;
}
