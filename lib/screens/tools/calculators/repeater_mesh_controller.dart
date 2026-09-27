// State for the Wi-Fi Classroom Repeaters and Mesh Backhaul tool
// (repeater-mesh).
//
// One ChangeNotifier holds the inputs, the computed result, the
// predict-then-reveal question and the animation clock, so the stage
// (RepeaterMeshStage) and the controls (RepeaterMeshControls) are separate
// views over one object. The phone screen stacks them; the presenter layout
// puts the same views side by side over this same object (spec 00).
//
// THE CLOCK. The Ticker is constructed here directly, not from a widget's
// TickerProvider: the route under the presenter is muted, and the animation
// must keep running while the presenter shows it. The phase is its own
// ValueNotifier, so a running animation repaints the corridor and the
// airtime lanes without rebuilding the cards; this object notifies only when
// an input, the play state or the question changes. The animation loops
// until paused and starts paused, so it never runs unasked (reduced motion,
// and a test's pumpAndSettle).
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../services/wifi_lab/repeater_mesh_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';
import '../../../units/unit_system.dart';

export '../../../services/wifi_lab/repeater_mesh_model.dart'
    show kRepeaterMeshToolId;

/// One pass of the animation: every hop carries its share of one unit of
/// data. Slow enough for a class to follow.
const Duration kRmCycle = Duration(seconds: 4);

/// Where the predict-then-reveal question stands.
enum RmQuestion {
  /// Not asked: every number is on screen.
  idle,

  /// Asked: the throughputs are hidden until Reveal.
  asking,

  /// Revealed: the answer and the guess are shown.
  revealed,
}

/// The reasons a class can pick from. One is right.
enum RmGuess {
  tooClose('The laptop is too close to the repeater', right: false),
  sharedAir(
    'Every frame crosses the air twice on one channel, and the repeater\'s '
    'link back to the AP is weak',
    right: true,
  ),
  barsWrong(
    'The bars are wrong: the laptop\'s signal is really weak',
    right: false,
  );

  const RmGuess(this.label, {required this.right});

  final String label;
  final bool right;
}

/// The question's scenario: the repeater was put where the laptop is, 30 m
/// down the corridor, and the laptop sits 2 m from it. 5 GHz, one channel.
final RmConfig kRmQuestionConfig = RmConfig(
  relaysM: const <double>[30],
  clientM: 32,
);

class RepeaterMeshController extends ChangeNotifier {
  UnitSystem _units = UnitSystem.metric;

  /// Length units on screen. The corridor stays in metres.
  UnitSystem get units => _units;

  void setUnits(UnitSystem u) {
    if (u == _units) return;
    _units = u;
    notifyListeners();
  }

  RepeaterMeshController({RmConfig? initial})
    : _config = initial ?? RmConfig(),
      _result = computeRepeaterMesh(initial ?? RmConfig()) {
    _ticker = Ticker(_onTick, debugLabel: 'repeater-mesh-cycle');
  }

  RmConfig _config;
  RmResult _result;
  RmQuestion _question = RmQuestion.idle;
  RmGuess? _guess;

  late final Ticker _ticker;

  /// 0 to 1 through one pass of the animation.
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);
  double _playFrom = 0;
  bool _playing = false;
  bool _reducedMotion = false;
  bool _disposed = false;

  // ── Read side ─────────────────────────────────────────────────────────────

  RmConfig get config => _config;
  RmResult get result => _result;
  RmQuestion get question => _question;
  RmGuess? get guess => _guess;

  /// True while the throughputs are hidden.
  bool get masked => _question == RmQuestion.asking;

  ValueListenable<double> get phase => _phase;
  bool get playing => _playing;
  bool get reducedMotion => _reducedMotion;

  // ── Inputs ────────────────────────────────────────────────────────────────

  void _set(RmConfig next) {
    if (next == _config) return;
    _config = next;
    _result = computeRepeaterMesh(next);
    _notify();
  }

  set relayCount(int n) => _set(_config.withRelayCount(n));
  set band(RmBand b) => _set(_config.copyWith(band: b));
  set backhaul(RmBackhaul b) => _set(_config.copyWith(backhaul: b));
  set efficiency(double v) => _set(
    _config.copyWith(
      efficiency: _round2(v.clamp(kRmMinEfficiency, kRmMaxEfficiency)),
    ),
  );
  set forwardingDelayMs(double v) => _set(
    _config.copyWith(
      forwardingDelayMs: _round1(v.clamp(kRmMinDelayMs, kRmMaxDelayMs)),
    ),
  );

  /// Moves node [index] (1 = first relay, relayCount + 1 = the client).
  void moveNode(int index, double m) => _set(_config.withNodeAt(index, m));

  /// Up and Down arrows: one relay more or fewer.
  void nudgeRelays(int delta) => relayCount = _config.relayCount + delta;

  /// R: the opening scene, the animation stopped at its start, the question
  /// closed.
  void resetAll() {
    _stop();
    _phase.value = 0;
    _question = RmQuestion.idle;
    _guess = null;
    _config = RmConfig();
    _result = computeRepeaterMesh(_config);
    _notify();
  }

  // ── Predict, then reveal ──────────────────────────────────────────────────

  /// Loads the question's scenario and hides the throughputs.
  void ask() {
    _config = kRmQuestionConfig;
    _result = computeRepeaterMesh(_config);
    _question = RmQuestion.asking;
    _guess = null;
    _notify();
  }

  set guess(RmGuess? g) {
    if (g == _guess) return;
    _guess = g;
    _notify();
  }

  void reveal() {
    if (_question != RmQuestion.asking) return;
    _question = RmQuestion.revealed;
    _notify();
  }

  /// Closes the question card.
  void dismissQuestion() {
    if (_question == RmQuestion.idle) return;
    _question = RmQuestion.idle;
    _guess = null;
    _notify();
  }

  // ── Animation ─────────────────────────────────────────────────────────────

  /// The screen reports the platform's reduced-motion setting. With it on,
  /// nothing moves unless the user presses Play. Does not notify (it is set
  /// during a build).
  set reducedMotion(bool on) {
    if (on == _reducedMotion) return;
    _reducedMotion = on;
    if (on) _stop();
  }

  /// Space: play or pause. Pressed by the user, so it plays even with
  /// reduced motion on.
  void togglePlay() {
    if (_playing) {
      _stop();
      _notify();
      return;
    }
    _playFrom = _phase.value;
    _playing = true;
    if (_ticker.isActive) _ticker.stop();
    _ticker.start();
    _notify();
  }

  void _stop() {
    _playing = false;
    if (_ticker.isActive) _ticker.stop();
  }

  void _onTick(Duration elapsed) {
    final double t =
        _playFrom + elapsed.inMicroseconds / kRmCycle.inMicroseconds;
    _phase.value = t - t.floorToDouble();
  }

  // ── Presenter keys ────────────────────────────────────────────────────────

  PresenterActions get presenterActions => PresenterActions(
    playPause: togglePlay,
    reset: resetAll,
    sliderDown: () => nudgeRelays(-1),
    sliderUp: () => nudgeRelays(1),
    sliderLabel: 'Relays',
  );

  // ── Copy ──────────────────────────────────────────────────────────────────

  String copyText() {
    final RmConfig c = _config;
    final RmResult r = _result;
    final StringBuffer b = StringBuffer()
      ..writeln('Repeaters and Mesh Backhaul (WLAN Pros Toolbox)')
      ..writeln(
        '${c.band.label}, ${c.band.widthMHz} MHz, ${c.backhaul.label}, '
        'efficiency ${c.efficiency.toStringAsFixed(2)} (illustrative), '
        'forwarding delay ${rmMs(c.forwardingDelayMs)} per hop (illustrative)',
      );
    for (final RmHop h in r.hops) {
      final String from = rmNodeName(h.from, c.relayCount);
      final String to = rmNodeName(h.to, c.relayCount);
      b.writeln(
        h.wired
            ? 'Hop ${h.from + 1}, $from to $to: cable'
            : 'Hop ${h.from + 1}, $from to $to, '
                  '${rmMeters(h.link.distanceM, _units)}: '
                  '${h.link.rxDbm.toStringAsFixed(1)} dBm, '
                  '${h.link.hasLink ? 'MCS ${h.link.mcs}, ${rmMbps(h.throughputMbps)}' : 'no link'}',
      );
    }
    b
      ..writeln(
        'End to end: ${rmMbps(r.endToEndMbps)}, delay ${rmMs(r.delayMs)}',
      )
      ..writeln(
        'Straight to the AP from ${rmMeters(c.clientM, _units)}: '
        '${r.direct.hasLink ? rmMbps(r.direct.throughputMbps) : 'no link'}, '
        'delay ${rmMs(r.directDelayMs)}',
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
    _phase.dispose();
    super.dispose();
  }
}

double _round1(double v) => (v * 10).roundToDouble() / 10;
double _round2(double v) => (v * 100).roundToDouble() / 100;
