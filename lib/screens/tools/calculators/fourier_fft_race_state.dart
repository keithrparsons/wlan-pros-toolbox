// Mode 3 state for the Wi-Fi Lab "Fourier and FFT" tool (fourier-fft): the
// swept vs FFT race. Owned by FourierLabModel (the one shared state object);
// every setter calls back into it, so the stage and the controls both rebuild
// from the same notification.
//
// The run is computed once per settings change (RaceRun.compute) and cached.
// Playback only moves [progress]. The run opens finished (progress 1), so the
// full result shows without pressing anything.
//
// PLAYBACK CLOCK (moved here from the screen, 2026-09-26, for the presenter
// layout): a Ticker built directly, not from a widget's TickerProvider,
// because the phone route under the presenter route is muted and a playback
// started there must keep going. With [reduceMotion] (the screen sets it
// from MediaQuery) a playback jumps straight to the end, as before. The
// presenter keys add pause, resume, a step of one [stepFraction] of the run,
// and a rewind to an empty run.

import 'package:flutter/scheduler.dart';

import '../../../services/wifi_lab/fourier_race.dart';

/// Spans offered, centered on 2450 MHz.
const List<double> kRaceSpansMhz = <double>[20, 50, 100];

/// RBW settings offered, widest first.
const List<double> kRaceRbwHz = <double>[3e6, 1e6, 300e3, 100e3, 30e3, 10e3];

/// Run lengths offered.
const List<double> kRaceRunSeconds = <double>[0.05, 0.2, 1.0];

/// Microwave-oven sweep widths offered (0 = near CW).
const List<double> kMicrowaveSweepsMhz = <double>[0, 10, 20, 40];

/// Analog video camera bandwidths offered.
const List<double> kVideoBandwidthsMhz = <double>[4, 8, 18];

/// Wall-clock length of one playback, whatever the run length.
const Duration kRacePlayback = Duration(seconds: 4);

/// One Step (Right arrow) of a race playback, as a share of the run.
const double kRaceStepFraction = 1 / 40;

class FourierRaceState {
  FourierRaceState(this._onChanged);

  final VoidCallback _onChanged;

  /// Set by the screen from MediaQuery: playbacks jump to the end.
  bool reduceMotion = false;

  Ticker? _ticker;
  double _tickFrom = 0;
  bool _paused = false;
  bool _disposed = false;

  double _spanMhz = 100;
  double _rbwHz = 100e3;
  RaceSceneConfig _config = const RaceSceneConfig();
  double _progress = 1;
  bool _animating = false;
  int _runToken = 0;

  RaceRun? _run;
  Object? _runKey;

  double get spanMhz => _spanMhz;
  double get rbwHz => _rbwHz;
  RaceSceneConfig get config => _config;

  /// 0 .. 1 of the run revealed so far.
  double get progress => _progress;

  /// True while a playback is under way, running or paused.
  bool get animating => _animating;

  /// True while a playback is under way and paused.
  bool get paused => _animating && _paused;

  /// True while a playback is under way and running.
  bool get playing => _animating && !_paused;

  /// Bumped each time a playback is asked for.
  int get runToken => _runToken;

  /// Seconds of the run revealed so far.
  double get elapsedSeconds => _progress * _config.runSeconds;

  double get sweepSeconds =>
      SweptAnalyzer.sweepTimeSeconds(spanHz: _spanMhz * 1e6, rbwHz: _rbwHz);

  RaceRun get run {
    final Object key = (
      _spanMhz,
      _rbwHz,
      _config.seed,
      _config.runSeconds,
      _config.mainsHz,
      _config.microwaveSweepMhz,
      _config.videoBandwidthMhz,
    );
    if (_run == null || _runKey != key) {
      _run = RaceRun.compute(config: _config, spanMhz: _spanMhz, rbwHz: _rbwHz);
      _runKey = key;
    }
    return _run!;
  }

  /// Any setting change stops a playback and shows the full new result.
  void _settle() {
    _stopClock();
    _animating = false;
    _paused = false;
    _progress = 1;
    _onChanged();
  }

  void _stopClock() {
    final Ticker? t = _ticker;
    if (t != null && t.isActive) t.stop();
  }

  void _startClock() {
    if (_disposed) return;
    _stopClock();
    _tickFrom = _progress;
    (_ticker ??= Ticker(_onTick, debugLabel: 'fourier-race')).start();
  }

  void _onTick(Duration elapsed) {
    setProgress(
      _tickFrom + elapsed.inMicroseconds / kRacePlayback.inMicroseconds,
    );
  }

  void setSpan(double mhz) {
    if (mhz == _spanMhz || !kRaceSpansMhz.contains(mhz)) return;
    _spanMhz = mhz;
    _settle();
  }

  void setRbw(double hz) {
    if (hz == _rbwHz || !kRaceRbwHz.contains(hz)) return;
    _rbwHz = hz;
    _settle();
  }

  /// The next wider (+1) or narrower (-1) RBW, held at the ends.
  void nudgeRbw(int wider) {
    final int i = (kRaceRbwHz.indexOf(_rbwHz) - wider).clamp(
      0,
      kRaceRbwHz.length - 1,
    );
    setRbw(kRaceRbwHz[i]);
  }

  void setRunSeconds(double s) {
    if (s == _config.runSeconds || !kRaceRunSeconds.contains(s)) return;
    _config = _config.copyWith(runSeconds: s);
    _settle();
  }

  void setMains(double hz) {
    if (hz == _config.mainsHz || (hz != 50 && hz != 60)) return;
    _config = _config.copyWith(mainsHz: hz);
    _settle();
  }

  void setMicrowaveSweep(double mhz) {
    if (mhz == _config.microwaveSweepMhz ||
        !kMicrowaveSweepsMhz.contains(mhz)) {
      return;
    }
    _config = _config.copyWith(microwaveSweepMhz: mhz);
    _settle();
  }

  void setVideoBandwidth(double mhz) {
    if (mhz == _config.videoBandwidthMhz ||
        !kVideoBandwidthsMhz.contains(mhz)) {
      return;
    }
    _config = _config.copyWith(videoBandwidthMhz: mhz);
    _settle();
  }

  /// A new random scene (new hops, new Wi-Fi gaps, new oven phase).
  void newScene() {
    _config = _config.copyWith(seed: _config.seed + 1);
    _settle();
  }

  /// Plays the run from the start (or, with reduced motion, shows the end).
  void startRun() {
    _progress = 0;
    _animating = true;
    _paused = false;
    _runToken++;
    if (reduceMotion) {
      setProgress(1);
      return;
    }
    _startClock();
    _onChanged();
  }

  /// Holds a running playback where it is.
  void pause() {
    if (!playing) return;
    _paused = true;
    _stopClock();
    _onChanged();
  }

  /// Carries on from a pause.
  void resume() {
    if (!paused) return;
    _paused = false;
    if (reduceMotion) {
      setProgress(1);
      return;
    }
    _startClock();
    _onChanged();
  }

  /// Space in presenter mode: pause while running, resume while paused,
  /// otherwise play from the start.
  void playPause() {
    if (playing) {
      pause();
    } else if (paused) {
      resume();
    } else {
      startRun();
    }
  }

  /// One [kRaceStepFraction] of the run, then paused. From a finished run
  /// it starts again from empty.
  void step() {
    if (!_animating) {
      _progress = 0;
      _animating = true;
      _runToken++;
    }
    _paused = true;
    _stopClock();
    setProgress(_progress + kRaceStepFraction);
    if (_animating) _onChanged();
  }

  /// Back to an empty run, paused, ready to play or step.
  void rewind() {
    _stopClock();
    _progress = 0;
    _animating = true;
    _paused = true;
    _runToken++;
    _onChanged();
  }

  /// Moves the playback (the clock calls this; 1 finishes at once).
  void setProgress(double p) {
    final double v = p.clamp(0.0, 1.0);
    if (v == _progress && (v < 1 || !_animating)) return;
    _progress = v;
    if (v >= 1) {
      _animating = false;
      _paused = false;
      _stopClock();
    }
    _onChanged();
  }

  void dispose() {
    _disposed = true;
    _ticker?.dispose();
  }
}
