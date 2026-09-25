// Mode 3 state for the Wi-Fi Lab "Fourier and FFT" tool (fourier-fft): the
// swept vs FFT race. Owned by FourierLabModel (the one shared state object);
// every setter calls back into it, so the stage and the controls both rebuild
// from the same notification.
//
// The run is computed once per settings change (RaceRun.compute) and cached.
// Playback only moves [progress]; the screen drives it with a ticker so this
// file needs no TickerProvider. The run opens finished (progress 1), so the
// full result shows without pressing anything and reduced motion needs no
// special path: the screen jumps straight to 1.

import 'package:flutter/foundation.dart';

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

class FourierRaceState {
  FourierRaceState(this._onChanged);

  final VoidCallback _onChanged;

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

  /// True while a playback is under way.
  bool get animating => _animating;

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
    _animating = false;
    _progress = 1;
    _onChanged();
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

  /// Asks the screen to play the run from the start.
  void startRun() {
    _progress = 0;
    _animating = true;
    _runToken++;
    _onChanged();
  }

  /// Called by the screen's ticker (or with 1 to finish at once).
  void setProgress(double p) {
    final double v = p.clamp(0.0, 1.0);
    if (v == _progress && (v < 1 || !_animating)) return;
    _progress = v;
    if (v >= 1) _animating = false;
    _onChanged();
  }
}
