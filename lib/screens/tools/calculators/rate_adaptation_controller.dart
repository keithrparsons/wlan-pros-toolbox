// State for the Wi-Fi Lab Rate Adaptation tool (rate-adaptation).
//
// One ChangeNotifier holds the settings, the run and the clock, so the stage
// (RateAdaptationStage) and the controls (RateAdaptationControls,
// RateAdaptationReadouts) are independent widgets that each listen to this
// one object. The phone layout stacks them; the desktop layout puts the
// controls in a side panel; a presenter layout can do either without
// touching them (spec 00).
//
// THE CLOCK. The Ticker is constructed here directly, not from a widget's
// TickerProvider: the route under the presenter route is muted, and a
// playing link must keep running while the presenter shows it (spec 00).
//
// The model and every rule live in lib/services/wifi_lab/
// rate_adaptation_model.dart. Settings apply to the running link at once
// (the student moves a slider and watches the rate control react); Restart
// begins a fresh link with no statistics.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../services/wifi_lab/rate_adaptation_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kRateAdaptationToolId = 'rate-adaptation';

/// Simulated air time per real second.
enum RaSpeed {
  x002('1/50 (watch single frames)', 0.02),
  x01('1/10', 0.1),
  x025('1/4', 0.25),
  x1('Real time', 1);

  const RaSpeed(this.label, this.factor);

  final String label;
  final double factor;
}

/// Number formatting shared by stage and controls.
abstract final class RaFormat {
  static String n(double v, [int decimals = 1]) {
    final String s = v.toStringAsFixed(decimals);
    return RegExp(r'^-0\.?0*$').hasMatch(s) ? s.substring(1) : s;
  }

  static String mbps(double v) => '${n(v)} Mbps';

  static String pct(double v01) => '${(v01 * 100).round()}%';

  static String clock(double us) => '${n(us / 1e6, 2)} s';

  static String mcs(int m) => 'MCS $m';

  /// "MCS 9 (114.7 Mbps)".
  static String rate(int m) => 'MCS $m (${mbps(RaLink.phyRateMbps(m))})';
}

class RateAdaptationController extends ChangeNotifier {
  RateAdaptationController({
    this.seed = 1,
    RaSettings initial = const RaSettings(),
  }) : _engine = RateAdaptationEngine(settings: initial, seed: seed) {
    _ticker = Ticker(_onTick, debugLabel: 'rate-adaptation');
  }

  final int seed;
  RateAdaptationEngine _engine;
  late final Ticker _ticker;
  bool _playing = false;
  Duration _lastElapsed = Duration.zero;
  RaSpeed _speed = RaSpeed.x025;

  // ── Read side ─────────────────────────────────────────────────────────────

  RateAdaptationEngine get engine => _engine;
  RaSettings get settings => _engine.settings;
  bool get playing => _playing;
  RaSpeed get speed => _speed;
  bool get atStart => _engine.nowUs == 0;

  // ── Clock ─────────────────────────────────────────────────────────────────

  void togglePlay() {
    if (_playing) {
      _pause();
    } else {
      _playing = true;
      _lastElapsed = Duration.zero;
      _ticker.start();
    }
    notifyListeners();
  }

  void _pause() {
    _playing = false;
    if (_ticker.isActive) _ticker.stop();
  }

  /// Pause without toggling (app backgrounded).
  void pause() {
    if (!_playing) return;
    _pause();
    notifyListeners();
  }

  /// One frame, with all its retries.
  void stepFrame() {
    _pause();
    _engine.stepFrame();
    notifyListeners();
  }

  /// Advance by [us] of air time (tests and renders).
  void advanceBy(double us) {
    _engine.advanceBy(us);
    notifyListeners();
  }

  /// A fresh link: no statistics, clock at 0, same settings.
  void restart() {
    _pause();
    _engine = RateAdaptationEngine(settings: _engine.settings, seed: seed);
    notifyListeners();
  }

  set speed(RaSpeed s) {
    if (s == _speed) return;
    _speed = s;
    notifyListeners();
  }

  void _onTick(Duration elapsed) {
    final double dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    // A stalled frame cannot jump more than a tenth of a real second.
    _engine.advanceBy(math.min(dt, 0.1) * _speed.factor * 1e6);
    notifyListeners();
  }

  // ── Settings (apply to the running link) ──────────────────────────────────

  void _apply(RaSettings next) {
    if (next == _engine.settings) return;
    _engine.settings = next;
    notifyListeners();
  }

  set path(RaPath p) => _apply(settings.copyWith(path: p));
  set snrOffsetDb(double v) => _apply(settings.copyWith(snrOffsetDb: v));
  set samplingShare(double v) => _apply(settings.copyWith(samplingShare: v));
  set ewmaHistory(double v) => _apply(settings.copyWith(ewmaHistory: v));
  set retryChain(bool v) => _apply(settings.copyWith(retryChain: v));
  set retryLimit(RaRetryLimit v) => _apply(settings.copyWith(retryLimit: v));
  set ackTimeoutUs(double v) => _apply(settings.copyWith(ackTimeoutUs: v));

  /// The SNR offset slider's range, dB.
  static const double snrOffsetMinDb = -20;
  static const double snrOffsetMaxDb = 20;

  /// Up and Down arrows: the SNR offset one dB.
  void nudgeSnrOffset(double deltaDb) {
    snrOffsetDb = (settings.snrOffsetDb + deltaDb)
        .clamp(snrOffsetMinDb, snrOffsetMaxDb)
        .roundToDouble();
  }

  // ── Presenter keys ────────────────────────────────────────────────────────

  PresenterActions get presenterActions => PresenterActions(
    playPause: togglePlay,
    step: stepFrame,
    reset: restart,
    sliderDown: () => nudgeSnrOffset(-1),
    sliderUp: () => nudgeSnrOffset(1),
    sliderLabel: 'SNR offset',
  );

  // ── Copy ──────────────────────────────────────────────────────────────────

  String? copyText() {
    final RateAdaptationEngine e = _engine;
    if (e.nowUs == 0) return null;
    final RaSettings s = e.settings;
    final RaWindowStats w = e.window;
    final RaRanking r = e.ranking;
    final int? sup = RateAdaptationMath.supportedMcs(e.snrNowDb);
    final StringBuffer b = StringBuffer()
      ..writeln('Rate Adaptation (WLAN Pros Toolbox, teaching model)')
      ..writeln(
        'Link: 5 GHz, 802.11ax, 20 MHz, 1 stream, 1500-byte frames, best '
        'effort',
      )
      ..writeln(
        'Path ${s.path.label}, SNR offset ${RaFormat.n(s.snrOffsetDb, 0)} dB, '
        'sampling ${RaFormat.pct(s.samplingShare)}, EWMA '
        '${RaFormat.pct(s.ewmaHistory)} history, retry chain '
        '${s.retryChain ? 'on' : 'off'}, retry limit ${s.retryLimit.label}, '
        'ACK timeout ${RaFormat.n(s.ackTimeoutUs, 0)} µs',
      )
      ..writeln(
        'At ${RaFormat.clock(e.nowUs)}: SNR ${RaFormat.n(e.snrNowDb)} dB '
        '(supports ${sup == null ? 'no MCS' : RaFormat.mcs(sup)})',
      )
      ..writeln(
        'Retry chain: ${RaFormat.mcs(r.bestThroughput)}, '
        '${RaFormat.mcs(r.secondThroughput)}, '
        '${RaFormat.mcs(r.bestProbability)}, ${RaFormat.mcs(RaLink.lowestMcs)}',
      )
      ..writeln(
        'Best rate ${RaFormat.rate(r.bestThroughput)}, estimate '
        '${RaFormat.mbps(e.stats[r.bestThroughput].throughputEstimateMbps)}',
      )
      ..writeln(
        'Last second: delivered ${RaFormat.mbps(w.deliveredMbps)}, '
        '${RaFormat.n(w.retriesPerFrame, 2)} retries per frame, '
        '${RaFormat.pct(w.retryAirtimeShare)} of airtime on retries, '
        '${w.dropped} dropped',
      )
      ..writeln('MCS\tSmoothed success\tEstimate Mbps\tAttempts');
    for (final RaRateStats st in e.stats) {
      b.writeln(
        '${st.mcs}\t'
        '${st.ewma == null ? 'untried' : RaFormat.pct(st.ewma!)}\t'
        '${RaFormat.n(st.throughputEstimateMbps)}\t${st.totalAttempts}',
      );
    }
    return b.toString().trimRight();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
