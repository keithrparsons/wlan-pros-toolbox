// State for the Wi-Fi Classroom tool Why a Busy Line Lags
// (latency-under-load).
//
// One ChangeNotifier holds the setting (the line and the smart queue
// management switch) and the run clock, so the stage (LatencyUnderLoadStage)
// and the controls (LatencyUnderLoadControls) are separate views over one
// object. The phone screen stacks them; the presenter layout puts the same
// views side by side over this same object (spec 00).
//
// THE CLOCK. The Ticker is constructed here directly, not from a widget's
// TickerProvider: the route under the presenter is muted, and the run must
// keep going while the presenter shows it. The run time is its own
// ValueNotifier, so a running trace repaints without rebuilding the cards;
// this object notifies only when a setting or the play state changes.
//
// The run opens at its END, with the whole trace drawn and nothing moving,
// so a still screen already tells the story (reduced motion, and a test's
// pumpAndSettle). Play starts the run from 0 in real time and stops at the
// end; it does not loop.
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../services/wifi_lab/latency_under_load_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';

export '../../../services/wifi_lab/latency_under_load_model.dart'
    show kLatencyUnderLoadToolId;

/// How far Right arrow moves the run, seconds.
const double kLulStepS = 1;

class LatencyUnderLoadController extends ChangeNotifier {
  LatencyUnderLoadController({LulConfig initial = const LulConfig()})
    : _config = initial {
    _ticker = Ticker(_onTick, debugLabel: 'latency-under-load-run');
  }

  LulConfig _config;
  late final Ticker _ticker;

  /// Seconds into the run, 0 to [kLulRunS].
  final ValueNotifier<double> _tS = ValueNotifier<double>(kLulRunS);
  double _playFrom = 0;
  bool _playing = false;
  bool _reducedMotion = false;
  bool _disposed = false;

  // ── Read side ─────────────────────────────────────────────────────────────

  LulConfig get config => _config;
  LulSummary get summary => LulSummary(_config);
  ValueListenable<double> get timeS => _tS;
  bool get playing => _playing;
  bool get reducedMotion => _reducedMotion;

  /// The call's delay at the playhead, ms.
  double get nowMs =>
      lulLatencyMs(_config.line, sqm: _config.sqm, tS: _tS.value);

  // ── Inputs ────────────────────────────────────────────────────────────────

  set sqm(bool on) {
    if (on == _config.sqm) return;
    _config = _config.copyWith(sqm: on);
    _notify();
  }

  set line(LulLine l) {
    if (l == _config.line) return;
    _config = _config.copyWith(line: l);
    _notify();
  }

  void toggleSqm() => sqm = !_config.sqm;

  /// R: the opening scene. Cable, SQM off, the whole run drawn, stopped.
  void resetAll() {
    _stop();
    _tS.value = kLulRunS;
    _config = const LulConfig();
    _notify();
  }

  // ── The run ───────────────────────────────────────────────────────────────

  /// The screen reports the platform's reduced-motion setting. With it on,
  /// nothing moves unless the user presses Play. Does not notify (it is set
  /// during a build).
  set reducedMotion(bool on) {
    if (on == _reducedMotion) return;
    _reducedMotion = on;
    if (on) _stop();
  }

  /// Space: play or pause. At the end of the run, Play starts it again from
  /// 0. Pressed by the user, so it plays even with reduced motion on.
  void togglePlay() {
    if (_playing) {
      _stop();
      _notify();
      return;
    }
    if (_tS.value >= kLulRunS) _tS.value = 0;
    _playFrom = _tS.value;
    _playing = true;
    if (_ticker.isActive) _ticker.stop();
    _ticker.start();
    _notify();
  }

  /// Right arrow: one second on, paused. At the end it starts over at 0.
  void step() {
    final bool wasPlaying = _playing;
    _stop();
    final double t = _tS.value >= kLulRunS ? 0 : _tS.value + kLulStepS;
    _tS.value = t.clamp(0, kLulRunS).toDouble();
    if (wasPlaying) _notify();
  }

  /// Moves the playhead (the scrub slider). Pauses the run.
  void seek(double tS) {
    final bool wasPlaying = _playing;
    _stop();
    _tS.value = tS.clamp(0, kLulRunS).toDouble();
    if (wasPlaying) _notify();
  }

  void _stop() {
    _playing = false;
    if (_ticker.isActive) _ticker.stop();
  }

  void _onTick(Duration elapsed) {
    final double t =
        _playFrom + elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (t >= kLulRunS) {
      _tS.value = kLulRunS;
      _stop();
      _notify();
      return;
    }
    _tS.value = t;
  }

  // ── Presenter keys ────────────────────────────────────────────────────────

  PresenterActions get presenterActions => PresenterActions(
    playPause: togglePlay,
    step: step,
    stepLabel: 'One second on',
    reset: resetAll,
    sliderDown: () => sqm = false,
    sliderUp: () => sqm = true,
    sliderLabel: 'Smart queue management off or on',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyQ,
        keyLabel: 'Q',
        description: 'Switch smart queue management',
        onPressed: toggleSqm,
      ),
    ],
  );

  // ── Copy ──────────────────────────────────────────────────────────────────

  String copyText() {
    final LulSummary s = summary;
    final LulLine l = _config.line;
    return <String>[
      'Why a Busy Line Lags (WLAN Pros Toolbox)',
      '${l.label} line, smart queue management '
          '${_config.sqm ? 'on' : 'off'}',
      'Idle: ${lulMs(s.idleMs)} (FCC measured ${l.inSentence} '
          'ISPs: ${lulMs(l.idleLowMs)} to ${lulMs(l.idleHighMs)})',
      'Under someone else\'s upload, SQM off: ${lulMs(s.busyOffMs)} '
          '(FCC chart reading, approximate; ISPs ran about '
          '${lulMs(l.busyLowMs)} to ${lulMs(l.busyHighMs)})',
      'Under the upload, SQM on: ${lulMs(s.busyOnMs)} (illustrative: idle '
          'plus the 5 ms FQ-CoDel target)',
      'Source: FCC Measuring Broadband America, 13th report (2022 test '
          'period); RFC 8290',
    ].join('\n');
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    _tS.dispose();
    super.dispose();
  }
}
