// State for the Wi-Fi Classroom Band Steering tool (band-steering).
//
// One ChangeNotifier holds the inputs, the simulated walk, where the client
// is on it, the predict-then-reveal question and the play state, so the
// stage (BandSteeringStage) and the controls (BandSteeringControls) are
// separate views over one object. The phone screen stacks them; the
// presenter layout puts the same views side by side over this same object
// (spec 00).
//
// THE CLOCK. The Ticker is constructed here directly, not from a widget's
// TickerProvider: the route under the presenter is muted, and the walk must
// keep going while the presenter shows it. While playing, the client moves
// one meter every [kBsStepDuration] and the beacon pulse (a ValueNotifier, so
// it repaints the floor without rebuilding the cards) runs. Paused, the
// beacons are drawn as a still ring: they never stop, the drawing just holds.
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../services/wifi_lab/band_steering_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kBandSteeringToolId = 'band-steering';

/// Time per meter walked while playing.
const Duration kBsStepDuration = Duration(milliseconds: 450);

/// One beacon pulse on the drawing (slowed far below the real 102.4 ms so it
/// can be seen).
const Duration kBsPulseDuration = Duration(milliseconds: 1200);

/// Up and Down move the client this many meters along the walk.
const int kBsNudgeSteps = 5;

/// Where the predict-then-reveal question stands.
enum BsQuestion { idle, asking, revealed }

/// The class's answer to "Does it move to 5 GHz?".
enum BsGuess {
  yes('Yes, it moves to 5 GHz'),
  no('No, it stays on 2.4 GHz');

  const BsGuess(this.label);

  final String label;
}

/// The question, word for word (spec 38).
const String kBsQuestionText =
    'The client walks from the edge of coverage right up to the AP. Does it '
    'move to 5 GHz?';

class BandSteeringController extends ChangeNotifier {
  BandSteeringController({BsConfig initial = const BsConfig()})
    : _config = initial,
      _walk = simulateWalk(initial) {
    _ticker = Ticker(_onTick, debugLabel: 'band-steering-walk');
  }

  BsConfig _config;
  BsWalk _walk;
  int _index = 0;
  BsQuestion _question = BsQuestion.idle;
  BsGuess? _guess;

  late final Ticker _ticker;
  int _playFromIndex = 0;
  bool _playing = false;
  bool _reducedMotion = false;
  bool _disposed = false;

  final ValueNotifier<double> _pulse = ValueNotifier<double>(0);

  // ── Read side ─────────────────────────────────────────────────────────────

  BsConfig get config => _config;
  BsWalk get walk => _walk;
  int get index => _index;
  BsStep get step => _walk.steps[_index];
  int get stepCount => _walk.steps.length;
  bool get atEnd => _index >= stepCount - 1;
  bool get playing => _playing;
  bool get reducedMotion => _reducedMotion;
  BsQuestion get question => _question;
  BsGuess? get guess => _guess;

  /// 0 to 1: how far the current beacon pulse has spread. Holds still when
  /// paused.
  ValueListenable<double> get pulse => _pulse;

  /// The final band under Client A's and Client B's published rules for the
  /// question's walk (edge to AP, steering off). Both are 2.4 GHz.
  ({BsBand? a, BsBand? b}) get questionAnswer {
    BsBand? end(ClientProfile p) =>
        simulateWalk(_questionConfig.copyWith(profile: p)).last.band;
    return (a: end(ClientProfile.a), b: end(ClientProfile.b));
  }

  BsConfig get _questionConfig => _config.copyWith(
    mode: SteeringMode.off,
    path: WalkPath.edgeToAp,
    randomScanAddress: false,
  );

  // ── Inputs ────────────────────────────────────────────────────────────────

  void _set(BsConfig next, {bool restart = false}) {
    if (next == _config) return;
    _config = next;
    _walk = simulateWalk(next);
    _index = restart ? 0 : _index.clamp(0, stepCount - 1);
    _notify();
  }

  set profile(ClientProfile v) => _set(_config.copyWith(profile: v));
  set mode(SteeringMode v) => _set(_config.copyWith(mode: v));
  set randomScanAddress(bool v) => _set(_config.copyWith(randomScanAddress: v));
  set extra5LossDb(double v) => _set(
    _config.copyWith(
      extra5LossDb: v.clamp(kBsMinExtraLossDb, kBsMaxExtraLossDb),
    ),
  );
  set refusalTolerance(int v) => _set(
    _config.copyWith(
      refusalTolerance: v.clamp(kBsMinTolerance, kBsMaxTolerance),
    ),
  );
  set driverSupportsBtm(bool v) => _set(_config.copyWith(driverSupportsBtm: v));

  /// A new path starts the walk over.
  set path(WalkPath v) {
    if (v == _config.path) return;
    _stop();
    _set(_config.copyWith(path: v), restart: true);
  }

  /// The client's place on the walk (the position slider).
  set index(int v) {
    final int next = v.clamp(0, stepCount - 1);
    if (next == _index) return;
    _index = next;
    _notify();
  }

  /// Up and Down: move [kBsNudgeSteps] meters along the walk.
  void nudgePosition(int direction) {
    _stop();
    index = _index + direction * kBsNudgeSteps;
    _notify();
  }

  // ── Predict, then reveal ──────────────────────────────────────────────────

  /// Loads the question's walk (edge to AP, steering off) with the client at
  /// the edge. Client C becomes Client A: the question is about A and B.
  void ask() {
    _stop();
    _config = _questionConfig.copyWith(
      profile: _config.profile == ClientProfile.c
          ? ClientProfile.a
          : _config.profile,
    );
    _walk = simulateWalk(_config);
    _index = 0;
    _question = BsQuestion.asking;
    _guess = null;
    _notify();
  }

  set guess(BsGuess? g) {
    if (g == _guess) return;
    _guess = g;
    _notify();
  }

  /// Shows the answer and walks the client in (or jumps to the AP with
  /// reduced motion on).
  void reveal() {
    if (_question != BsQuestion.asking) return;
    _question = BsQuestion.revealed;
    if (_reducedMotion) {
      _index = stepCount - 1;
      _notify();
      return;
    }
    _index = 0;
    _start();
  }

  void dismissQuestion() {
    if (_question == BsQuestion.idle) return;
    _question = BsQuestion.idle;
    _guess = null;
    _notify();
  }

  // ── Play ──────────────────────────────────────────────────────────────────

  /// The screen reports the platform's reduced-motion setting. Does not
  /// notify (it is set during a build).
  set reducedMotion(bool on) {
    if (on == _reducedMotion) return;
    _reducedMotion = on;
    if (on) {
      _stop();
      _pulse.value = 0;
    }
  }

  /// Space: walk, or pause. At the end of the walk, starts it over.
  void togglePlay() {
    if (_playing) {
      _stop();
      _notify();
      return;
    }
    if (atEnd) _index = 0;
    _start();
  }

  /// Right arrow: pause and walk one meter.
  void stepOnce() {
    _stop();
    if (!atEnd) _index++;
    _notify();
  }

  /// R: back to the start of the walk, paused.
  void reset() {
    _stop();
    _index = 0;
    _pulse.value = 0;
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
      _pulse.value =
          (elapsed.inMicroseconds % kBsPulseDuration.inMicroseconds) /
          kBsPulseDuration.inMicroseconds;
    }
    // By elapsed time, not by tick count, so a dropped frame never slows the
    // walk: one meter per kBsStepDuration since Play.
    final int target =
        (_playFromIndex +
                elapsed.inMicroseconds ~/ kBsStepDuration.inMicroseconds)
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
    sliderDown: () => nudgePosition(-1),
    sliderUp: () => nudgePosition(1),
    sliderLabel: 'Walking position',
  );

  // ── Copy ──────────────────────────────────────────────────────────────────

  String copyText() {
    final BsConfig c = _config;
    final BsStep s = step;
    final StringBuffer b = StringBuffer()
      ..writeln('Band Steering (WLAN Pros Toolbox)')
      ..writeln(
        '${c.profile.label}, AP steering: ${c.mode.label}, walk: '
        '${c.path.label}',
      )
      ..writeln(
        'Extra 5 GHz wall loss ${c.extra5LossDb.toStringAsFixed(0)} dB '
        '(illustrative); random address while scanning: '
        '${c.randomScanAddress ? 'on' : 'off'}',
      )
      ..writeln(
        'At ${s.distanceM.toStringAsFixed(0)} m from the AP: 2.4 GHz '
        '${bsDbm(s.rssi24)}, 5 GHz ${bsDbm(s.rssi5)}',
      )
      ..writeln('On: ${s.band?.label ?? 'not connected'}')
      ..writeln('Why: ${s.why}');
    if (c.mode == SteeringMode.authRefusal) {
      b.writeln(
        'Authentication refusals so far: ${s.refusalsTotal} (tolerance '
        '${c.refusalTolerance}, illustrative)',
      );
    }
    if (c.mode == SteeringMode.transitionRequest) {
      b.writeln('Transition request answer: ${s.btm?.label ?? 'none yet'}');
    }
    return b.toString().trimRight();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    _pulse.dispose();
    super.dispose();
  }
}
