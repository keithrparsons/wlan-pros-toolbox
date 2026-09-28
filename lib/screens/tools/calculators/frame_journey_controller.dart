// State for the Wi-Fi Classroom tool A Frame's Journey (frame-journey).
//
// One ChangeNotifier holds the inputs, the hop (the steps from the
// transmitting NIC to the receiving one and back with the ACK), where the
// frame is on it, the predict-then-reveal question and the play state, so the
// stage (FrameJourneyStage) and the controls (FrameJourneyControls) are
// separate views over one object (spec 00).
//
// THE CLOCK. The Ticker is constructed here directly so the hop keeps going
// while the presenter shows it. While playing, the frame moves one step every
// [kFhStepDuration], and the wave phase (a ValueNotifier) runs so the drawing
// repaints without rebuilding the cards. With reduced motion on, the wave
// holds still.
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../services/wifi_lab/frame_journey_model.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';
import '../../../widgets/presenter/presenter_actions.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kFrameJourneyToolId = 'frame-journey';

/// Time per step while playing.
const Duration kFhStepDuration = Duration(milliseconds: 2400);

/// One wave cycle on the drawing (slowed so it can be seen).
const Duration kFhWaveDuration = Duration(milliseconds: 1400);

/// The bit the corruption control starts on: inside Address 3 of the default
/// frame (byte 16), so the first flip lands somewhere a student recognizes.
const int kFhDefaultFlipBit = 16 * 8 + 5;

/// Where the predict-then-reveal question stands.
enum FhQuestion { idle, asking, revealed }

/// The class's answer to "What does the receiver send back?".
enum FhGuess {
  ack('An ACK'),
  resend('A request to send it again'),
  nothing('Nothing');

  const FhGuess(this.label);
  final String label;
}

/// The question, word for word.
const String kFhQuestionText =
    'One bit of the frame arrives wrong. What does the receiver send back?';

class FrameJourneyController extends ChangeNotifier {
  FrameJourneyController({
    FhConfig initial = const FhConfig(flipBit: kFhDefaultFlipBit),
  }) : _config = initial,
       _hop = buildHop(initial) {
    _ticker = Ticker(_onTick, debugLabel: 'frame-journey');
  }

  UnitSystem _units = UnitSystem.metric;

  /// Length units on screen. The model stays in metres.
  UnitSystem get units => _units;

  void setUnits(UnitSystem u) {
    if (u == _units) return;
    _units = u;
    notifyListeners();
  }

  FhConfig _config;
  List<FhStep> _hop;
  int _index = 0;
  FhQuestion _question = FhQuestion.idle;
  FhGuess? _guess;

  late final Ticker _ticker;
  int _playFromIndex = 0;
  bool _playing = false;
  bool _reducedMotion = false;
  bool _disposed = false;

  final ValueNotifier<double> _wave = ValueNotifier<double>(0);

  // ── Read side ─────────────────────────────────────────────────────────────

  FhConfig get config => _config;
  List<FhStep> get hop => _hop;
  int get index => _index;
  FhStep get step => _hop[_index];
  int get stepCount => _hop.length;
  bool get atStart => _index == 0;
  bool get atEnd => _index >= stepCount - 1;
  bool get playing => _playing;
  bool get reducedMotion => _reducedMotion;
  FhQuestion get question => _question;
  FhGuess? get guess => _guess;

  /// Bits in the frame (the corruption slider's range).
  int get bitCount => step.frame.bitCount;

  /// The gap before the ACK on this band.
  SifsTiming get sifs => sifsFor(_config.band);

  /// 0 to 1: the wave's phase. Holds still when paused.
  ValueListenable<double> get wave => _wave;

  // ── Inputs ────────────────────────────────────────────────────────────────

  void _set(FhConfig next, {bool restart = false}) {
    if (next == _config) return;
    _config = next;
    _hop = buildHop(next);
    if (restart) {
      _stop();
      _index = 0;
    } else {
      _index = _index.clamp(0, stepCount - 1);
    }
    _notify();
  }

  set band(FjBand v) => _set(_config.copyWith(band: v));
  set distanceM(double v) => _set(
    _config.copyWith(
      distanceM: v.clamp(kFjMinDistanceM, kFjMaxDistanceM).roundToDouble(),
    ),
  );
  set capturing(bool v) => _set(_config.copyWith(capturing: v), restart: true);
  set transport(FjTransport v) =>
      _set(_config.copyWith(transport: v), restart: true);
  set payload(int v) => _set(_config.copyWith(payload: v), restart: true);

  /// Corrupting (or not) changes the number of steps, so it starts over.
  set corrupt(bool v) => _set(_config.copyWith(corrupt: v), restart: true);

  set flipBit(int v) => _set(
    _config.copyWith(
      flipBit: v.clamp(0, airFrameFor(_config.stack).bitCount - 1),
    ),
  );

  /// Up and Down: one meter (or foot, shown) closer or farther.
  void nudgeDistance(int direction) {
    distanceM = _config.distanceM + direction;
  }

  /// The hop position (the step slider).
  set index(int v) {
    final int next = v.clamp(0, stepCount - 1);
    if (next == _index) return;
    _index = next;
    _notify();
  }

  // ── Predict, then reveal ──────────────────────────────────────────────────

  /// Loads the question: one bit corrupted, the hop at its start.
  void ask() {
    _stop();
    _config = _config.copyWith(corrupt: true);
    _hop = buildHop(_config);
    _index = 0;
    _question = FhQuestion.asking;
    _guess = null;
    _notify();
  }

  set guess(FhGuess? g) {
    if (g == _guess) return;
    _guess = g;
    _notify();
  }

  /// Shows the answer and jumps to the no-ACK step.
  void reveal() {
    if (_question != FhQuestion.asking) return;
    _question = FhQuestion.revealed;
    final int i = _hop.indexWhere((FhStep s) => s.stage == FjHopStage.noAck);
    if (i >= 0) _index = i;
    _notify();
  }

  void dismissQuestion() {
    if (_question == FhQuestion.idle) return;
    _question = FhQuestion.idle;
    _guess = null;
    _notify();
  }

  // ── Play ──────────────────────────────────────────────────────────────────

  /// The screen reports the platform's reduced-motion setting. Does not
  /// notify (it is set during a build).
  set reducedMotion(bool on) {
    if (on == _reducedMotion) return;
    _reducedMotion = on;
    if (on) _wave.value = 0;
  }

  void togglePlay() {
    if (_playing) {
      _stop();
      _notify();
      return;
    }
    if (atEnd) _index = 0;
    _start();
  }

  void stepOnce() {
    _stop();
    if (!atEnd) _index++;
    _notify();
  }

  void stepBack() {
    _stop();
    if (!atStart) _index--;
    _notify();
  }

  void reset() {
    _stop();
    _index = 0;
    _wave.value = 0;
    _notify();
  }

  void _start() {
    _playing = true;
    _playFromIndex = _index;
    if (_ticker.isActive) _ticker.stop();
    _ticker.start();
    _notify();
  }

  void _stop() {
    _playing = false;
    if (_ticker.isActive) _ticker.stop();
  }

  void _onTick(Duration elapsed) {
    if (!_reducedMotion) {
      _wave.value =
          (elapsed.inMicroseconds % kFhWaveDuration.inMicroseconds) /
          kFhWaveDuration.inMicroseconds;
    }
    final int target =
        (_playFromIndex +
                elapsed.inMicroseconds ~/ kFhStepDuration.inMicroseconds)
            .clamp(0, stepCount - 1);
    if (target == _index) return;
    _index = target;
    if (atEnd) _stop();
    _notify();
  }

  // ── Presenter keys ────────────────────────────────────────────────────────

  PresenterActions get presenterActions => PresenterActions(
    playPause: togglePlay,
    step: stepOnce,
    reset: reset,
    sliderDown: () => nudgeDistance(-1),
    sliderUp: () => nudgeDistance(1),
    sliderLabel: 'Distance',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyC,
        keyLabel: 'C',
        description: 'Corrupt one bit, or send it clean',
        onPressed: () => corrupt = !_config.corrupt,
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyB,
        keyLabel: 'B',
        description: 'Next band',
        onPressed: () => band =
            FjBand.values[(_config.band.index + 1) % FjBand.values.length],
      ),
    ],
  );

  // ── Copy ──────────────────────────────────────────────────────────────────

  String copyText() {
    final FhConfig c = _config;
    final FhStep s = step;
    final SifsTiming t = sifs;
    final StringBuffer b = StringBuffer()
      ..writeln('A Frame\'s Journey (WLAN Pros Toolbox)')
      ..writeln(
        '${c.band.label}, channel ${c.band.channel}; '
        '${LengthFormat(_units).dist(c.distanceM, decimals: 0)} apart; '
        '${c.transport.label}, ${c.payload} bytes of data; frame '
        '${s.frame.length} bytes',
      )
      ..writeln(
        c.corrupt
            ? 'One bit corrupted on the first attempt: bit ${c.flipBit}'
            : 'Sent clean',
      )
      ..writeln(
        'Step ${s.index + 1} of $stepCount (attempt ${s.attempt}): ${s.title}',
      )
      ..writeln(s.detail)
      ..writeln('FCS sent: ${hex32(s.frame.fcsSent)}');
    if (s.check != null) {
      b.writeln(
        'FCS computed: ${hex32(s.check!.computed)} '
        '(${s.check!.pass ? 'pass' : 'fail'})',
      );
    }
    b.writeln(
      'SIFS ${t.sifsUs} us${t.signalExtensionUs > 0 ? ' + ${t.signalExtensionUs} us signal extension' : ''}',
    );
    return b.toString().trimRight();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    _wave.dispose();
    super.dispose();
  }
}
