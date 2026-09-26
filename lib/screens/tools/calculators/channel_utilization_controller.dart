// State for the Wi-Fi Classroom Channel Utilization Meter
// (channel-utilization).
//
// One ChangeNotifier holds the traffic settings, the measurement settings
// (window and carrier-sense definition), the running channel, the clock and
// the predict-then-reveal question, so the stage (ChannelUtilizationStage)
// and the controls (ChannelUtilizationControls) are separate views over one
// object. The phone screen stacks them; the presenter layout puts the same
// views side by side over this same object (spec 00).
//
// THE CLOCK. The Ticker is constructed here directly, not from a widget's
// TickerProvider: the route under the presenter is muted, and a run started
// on the phone screen must keep going while the instructor presents it.
// Every frame bumps [frame], which repaints the time strip; listeners are
// notified (and the cards rebuild) only when a beacon interval completes or
// an input changes, so a running channel does not rebuild every card sixty
// times a second.
//
// Traffic changes start a new run. Window and carrier-sense changes do not:
// they re-read the same recorded history, so the student sees the meter
// move from 73% to 76% on the same traffic.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../services/wifi_lab/airtime_anatomy.dart';
import '../../../services/wifi_lab/channel_utilization_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kChannelUtilizationToolId = 'channel-utilization';

/// Channel time per real second.
enum CuSpeed {
  frames('1 ms per second', 1000),
  slow('20 ms per second', 20000),
  real('Real time', 1000000),
  fast('5 s per second', 5000000);

  const CuSpeed(this.label, this.usPerSecond);

  final String label;
  final int usPerSecond;
}

/// Where the predict-then-reveal question stands.
enum CuQuestion {
  /// Not asked: every number is on screen.
  idle,

  /// Asked: the meter's numbers are hidden until Reveal.
  asking,

  /// Revealed.
  revealed,
}

/// The answers a class can pick.
enum CuGuess {
  about25('About 25%', 0, 0.375),
  about50('About 50%', 0.375, 0.625),
  about75('About 75%', 0.625, 0.875),
  full('100%', 0.875, 1.01);

  const CuGuess(this.label, this.low, this.high);

  final String label;
  final double low;
  final double high;

  bool contains(double share) => share >= low && share < high;
}

/// The question, word for word (spec 37).
const String kCuQuestionText =
    'One laptop sends as fast as it can. What will the meter read?';

/// Simulated channel time the Ticker may add in one frame, us, so a stalled
/// frame cannot turn into a long synchronous catch-up.
const int _kMaxUsPerFrame = 500000;

class ChannelUtilizationController extends ChangeNotifier {
  ChannelUtilizationController({
    CuConfig initial = const CuConfig(),
    this.seed = 1,
  }) : _config = initial,
       _sim = CuSim(initial, seed: seed) {
    _ticker = Ticker(_onTick, debugLabel: 'channel-utilization');
  }

  /// Seed for every random draw. Same seed, same run.
  final int seed;

  CuConfig _config;
  CuSim _sim;
  int _window = kCuDefaultWindow;
  bool _countReserved = false;

  late final Ticker _ticker;
  bool _playing = false;
  bool _reducedMotion = false;
  Duration _lastElapsed = Duration.zero;
  double _carryUs = 0;
  CuSpeed _speed = CuSpeed.real;

  CuQuestion _question = CuQuestion.idle;
  CuGuess? _guess;

  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  bool _disposed = false;

  // Many-sender curve, computed on first read for a rate and size.
  (int, int)? _curveKey;
  List<CuCurvePoint> _curve = const <CuCurvePoint>[];

  // ── Read side ─────────────────────────────────────────────────────────────

  CuConfig get config => _config;
  CuSim get sim => _sim;
  int get window => _window;
  bool get countReserved => _countReserved;
  bool get playing => _playing;
  bool get reducedMotion => _reducedMotion;
  CuSpeed get speed => _speed;
  CuQuestion get question => _question;
  CuGuess? get guess => _guess;

  /// True while the meter's numbers are hidden.
  bool get masked => _question == CuQuestion.asking;

  /// Bumps every animation frame: the time strip repaints on it.
  ValueListenable<int> get frame => _frame;

  CuTiming get timing => _sim.timing;

  /// The worked single-sender case for the current rate and size.
  CuCycle get cycle => CuCycle(_sim.timing);

  /// The meter over the window, or null before one interval completes.
  CuReading? get reading =>
      _sim.reading(window: _window, countReserved: _countReserved);

  /// The same history read the other way (the toggle's other side).
  CuReading? get otherReading =>
      _sim.reading(window: _window, countReserved: !_countReserved);

  /// The window in seconds: N x 100 TU x 1024 us.
  double get windowSeconds => _window * kCuIntervalTenths / 1e7;

  /// How much channel time the strip shows, tenths: ten single-sender
  /// cycles, so frames are wide enough to read at every rate.
  int get stripTenths => math.max(20000, cycle.cycleTenths * 10);

  /// The tool's own many-sender run for the current rate and frame size.
  List<CuCurvePoint> get curve {
    final (int, int) key = (_config.rateMbps, _config.payloadBytes);
    if (_curveKey != key) {
      _curveKey = key;
      _curve = saturationCurve(
        rateMbps: _config.rateMbps,
        payloadBytes: _config.payloadBytes,
        seed: seed,
      );
    }
    return _curve;
  }

  // ── Traffic (each starts a new run) ──────────────────────────────────────

  void _setConfig(CuConfig next) {
    if (next == _config) return;
    _config = next;
    _restart();
  }

  set senders(int v) => _setConfig(
    _config.copyWith(senders: v.clamp(kCuMinSenders, kCuMaxSenders)),
  );

  set loadPercent(int v) => _setConfig(
    _config.copyWith(
      loadPercent: v.clamp(kCuMinLoadPercent, kCuMaxLoadPercent),
    ),
  );

  set rateMbps(int v) => _setConfig(_config.copyWith(rateMbps: v));
  set payloadBytes(int v) => _setConfig(_config.copyWith(payloadBytes: v));

  set idleStations(int v) => _setConfig(
    _config.copyWith(idleStations: v.clamp(0, kCuMaxIdleStations)),
  );

  set neighbor(bool on) => _setConfig(_config.copyWith(neighbor: on));

  set neighborPercent(int v) => _setConfig(
    _config.copyWith(
      neighborPercent: v.clamp(kCuMinNeighborPercent, kCuMaxNeighborPercent),
    ),
  );

  set nonWifi(bool on) => _setConfig(_config.copyWith(nonWifi: on));

  /// Up and Down arrows: one sender more or fewer.
  void nudgeSenders(int delta) => senders = _config.senders + delta;

  // ── Measurement (re-reads the same history) ──────────────────────────────

  set window(int v) {
    final int next = v.clamp(kCuMinWindow, kCuMaxWindow);
    if (next == _window) return;
    _window = next;
    _notify();
  }

  set countReserved(bool on) {
    if (on == _countReserved) return;
    _countReserved = on;
    _notify();
  }

  set speed(CuSpeed s) {
    if (s == _speed) return;
    _speed = s;
    _notify();
  }

  // ── Transport ─────────────────────────────────────────────────────────────

  /// The screen reports the platform's reduced-motion setting. With it on,
  /// the channel never runs by itself; Step and Skip still work. Does not
  /// notify (it is set during a build).
  set reducedMotion(bool on) {
    if (on == _reducedMotion) return;
    _reducedMotion = on;
    if (on) _stop();
  }

  /// Space: run or pause the channel. Pressed by the user, so it plays even
  /// with reduced motion on.
  void togglePlay() {
    if (_playing) {
      _stop();
    } else {
      _playing = true;
      _lastElapsed = Duration.zero;
      _carryUs = 0;
      if (_ticker.isActive) _ticker.stop();
      _ticker.start();
    }
    _notify();
  }

  /// Right arrow: pause and run one beacon interval (102.4 ms).
  void stepInterval() {
    _stop();
    _sim.runIntervals(1);
    _bumpFrame();
    _notify();
  }

  /// Pause and run a whole window, so the meter reads a full average.
  void skipWindow() {
    _stop();
    _sim.runIntervals(_window);
    _bumpFrame();
    _notify();
  }

  /// A one-second non-Wi-Fi burst, starting now.
  void addBurst() {
    _sim.injectBurst();
    _bumpFrame();
    _notify();
  }

  /// R: a fresh run with the same settings, keeping play state.
  void reset() => _restart();

  void _restart() {
    _sim = CuSim(_config, seed: seed);
    _carryUs = 0;
    _bumpFrame();
    _notify();
  }

  void _stop() {
    _playing = false;
    if (_ticker.isActive) _ticker.stop();
  }

  void _onTick(Duration elapsed) {
    final Duration dt = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    _carryUs += dt.inMicroseconds / 1e6 * _speed.usPerSecond;
    final double us = math.min(_carryUs, _kMaxUsPerFrame.toDouble());
    _carryUs = 0;
    if (us <= 0) return;
    final int before = _sim.completedIntervals;
    _sim.runForUs(us);
    _bumpFrame();
    if (_sim.completedIntervals != before) _notify();
  }

  void _bumpFrame() => _frame.value++;

  // ── Predict, then reveal ──────────────────────────────────────────────────

  /// Loads the question's scenario (one saturated sender, 54 Mb/s, 1500
  /// bytes, nothing else on the channel) and hides the meter.
  void ask() {
    _config = const CuConfig();
    _window = kCuDefaultWindow;
    _countReserved = false;
    _question = CuQuestion.asking;
    _guess = null;
    _restart();
  }

  set guess(CuGuess? g) {
    if (g == _guess) return;
    _guess = g;
    _notify();
  }

  /// Shows the answer, filling the window first so the meter reads a full
  /// average.
  void reveal() {
    if (_question != CuQuestion.asking) return;
    final int missing = _window - _sim.intervals.length;
    if (missing > 0) _sim.runIntervals(missing);
    _question = CuQuestion.revealed;
    _bumpFrame();
    _notify();
  }

  void dismissQuestion() {
    if (_question == CuQuestion.idle) return;
    _question = CuQuestion.idle;
    _guess = null;
    _notify();
  }

  // ── Presenter keys ────────────────────────────────────────────────────────

  PresenterActions get presenterActions => PresenterActions(
    playPause: togglePlay,
    step: stepInterval,
    reset: reset,
    sliderDown: () => nudgeSenders(-1),
    sliderUp: () => nudgeSenders(1),
    sliderLabel: 'Senders',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyB,
        keyLabel: 'B',
        description: 'Add a 1-second non-Wi-Fi burst',
        onPressed: addBurst,
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyW,
        keyLabel: 'W',
        description: 'Skip ahead one full window',
        onPressed: skipWindow,
      ),
    ],
  );

  // ── Copy ──────────────────────────────────────────────────────────────────

  String copyText() {
    final CuConfig c = _config;
    final CuReading? r = reading;
    final CuCycle cy = cycle;
    String pct(double s) => '${(s * 100).toStringAsFixed(1)}%';
    final StringBuffer b = StringBuffer()
      ..writeln('Channel Utilization Meter (WLAN Pros Toolbox)')
      ..writeln(
        '${c.senders} sender${c.senders == 1 ? '' : 's'}, '
        '${c.saturated ? 'saturated' : '${c.loadPercent}% offered load each'}, '
        '${c.payloadBytes}-byte frames at ${c.rateMbps} Mb/s, 2.4 GHz',
      )
      ..writeln(
        'Neighbor network: ${c.neighbor ? '${c.neighborPercent}% offered (illustrative)' : 'off'}; '
        'non-Wi-Fi bursts: ${c.nonWifi ? 'on (illustrative)' : 'off'}',
      )
      ..writeln(
        'Window: $_window beacon intervals (${windowSeconds.toStringAsFixed(2)} s); '
        'busy counts ${_countReserved ? 'physical or virtual carrier sense' : 'physical carrier sense only'}',
      );
    if (r == null) {
      b.writeln('Meter: collecting the first beacon interval');
    } else {
      b
        ..writeln(
          'Channel Utilization: ${r.byte} of 255 (${pct(r.share)})'
          '${r.filling ? ', window filling: ${r.intervalsUsed} of $_window intervals' : ''}',
        )
        ..writeln('Station Count: ${c.stationCount}')
        ..writeln(
          'Payload ${pct(r.totals.share(CuSpan.payload))}, collisions '
          '${pct(r.totals.share(CuSpan.collision))}, required idle '
          '${pct(_requiredIdle(r))}, truly spare '
          '${pct(r.totals.share(CuSpan.spare))}',
        );
    }
    b.writeln(
      'One sender alone: cycle ${cy.cycleUs.toStringAsFixed(1)} µs, '
      '${pct(cy.physicalShare)} busy (physical), '
      '${pct(cy.virtualShare)} (counting reserved time), '
      'payload ${pct(cy.payloadShare)}',
    );
    return b.toString().trimRight();
  }

  /// Required idle in the split bar: with reserved time not counted, the
  /// SIFS inside each exchange is idle the protocol requires.
  double _requiredIdle(CuReading r) =>
      r.totals.share(CuSpan.requiredIdle) +
      (_countReserved
          ? 0
          : r.totals.share(CuSpan.reservedGap) +
                r.totals.share(CuSpan.neighborGap));

  /// The legacy rates on offer.
  static List<int> get rates => AirtimeConstants.legacyRatesMbps;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }
}

/// The seven segments of the split bar, in order.
enum CuSplit {
  payload('Payload'),
  overhead('Overhead'),
  collision('Collisions'),
  neighbor('Other network'),
  nonWifi('Non-Wi-Fi'),
  requiredIdle('Required idle'),
  spare('Truly spare');

  const CuSplit(this.label);

  final String label;

  /// Counts toward the meter's busy time.
  bool get busy => index <= CuSplit.nonWifi.index;
}

/// The split bar's shares over [r]. With reserved time counted, the SIFS in
/// each exchange is busy (overhead, or the other network's); without, it is
/// required idle.
Map<CuSplit, double> cuSplitShares(CuReading r, {required bool countReserved}) {
  final CuTotals t = r.totals;
  double s(CuSpan x) => t.share(x);
  return <CuSplit, double>{
    CuSplit.payload: s(CuSpan.payload),
    CuSplit.overhead:
        s(CuSpan.overhead) + (countReserved ? s(CuSpan.reservedGap) : 0),
    CuSplit.collision: s(CuSpan.collision),
    CuSplit.neighbor:
        s(CuSpan.neighbor) + (countReserved ? s(CuSpan.neighborGap) : 0),
    CuSplit.nonWifi: s(CuSpan.nonWifi),
    CuSplit.requiredIdle:
        s(CuSpan.requiredIdle) +
        (countReserved ? 0 : s(CuSpan.reservedGap) + s(CuSpan.neighborGap)),
    CuSplit.spare: s(CuSpan.spare),
  };
}

/// Formats a share as a percentage: 0.7319 -> "73.2%".
String cuPct(double share) => '${(share * 100).toStringAsFixed(1)}%';
