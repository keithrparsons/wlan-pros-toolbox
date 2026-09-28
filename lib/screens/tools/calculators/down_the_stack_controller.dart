// State for the Wi-Fi Classroom tool Down the Stack, Across the Air, Up the
// Other Side (down-the-stack).
//
// One ChangeNotifier holds the inputs, the journey, where the frame is on it,
// the To DS / From DS case the explorer shows, the view, the
// predict-then-reveal question and the play state, so the stage
// (DownTheStackStage) and the controls (DownTheStackControls) are separate
// views over one object (spec 00).
//
// THE CLOCK. The Ticker is constructed here directly, not from a widget's
// TickerProvider, so the journey keeps going while the presenter shows it.
// While playing, the frame moves one step every [kDtsStepDuration], and a
// wave phase (a ValueNotifier, so the drawing repaints without rebuilding the
// cards) runs on the air hop. With reduced motion on, the wave holds still.
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../services/wifi_lab/frame_journey_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kDownTheStackToolId = 'down-the-stack';

/// Time per step while playing.
const Duration kDtsStepDuration = Duration(milliseconds: 2200);

/// One wave cycle on the drawing (slowed far below any radio frequency so it
/// can be seen).
const Duration kDtsWaveDuration = Duration(milliseconds: 1400);

/// What the stage shows.
enum DtsView {
  journey('The journey'),
  addresses('Address fields');

  const DtsView(this.label);
  final String label;
}

/// Where the predict-then-reveal question stands.
enum DtsQuestion { idle, asking, revealed }

/// The class's answer to "Whose MAC is in Address 3?".
enum DtsGuess {
  server('The server\'s'),
  router('The router\'s'),
  ap('The AP\'s');

  const DtsGuess(this.label);
  final String label;
}

/// The question, word for word.
const String kDtsQuestionText =
    'The laptop sends to a server on another subnet. On the air, whose MAC '
    'address is in Address 3, the destination address?';

class DownTheStackController extends ChangeNotifier {
  DownTheStackController({FjConfig initial = const FjConfig()})
    : _config = initial,
      _journey = buildJourney(initial),
      _dsCase = initial.direction == FjDirection.toServer
          ? DsCase.toDs
          : DsCase.fromDs {
    _ticker = Ticker(_onTick, debugLabel: 'down-the-stack');
  }

  FjConfig _config;
  List<FjStep> _journey;
  int _index = 0;
  DsCase _dsCase;
  DtsView _view = DtsView.journey;
  DtsQuestion _question = DtsQuestion.idle;
  DtsGuess? _guess;

  late final Ticker _ticker;
  int _playFromIndex = 0;
  bool _playing = false;
  bool _reducedMotion = false;
  bool _disposed = false;

  final ValueNotifier<double> _wave = ValueNotifier<double>(0);

  // ── Read side ─────────────────────────────────────────────────────────────

  FjConfig get config => _config;
  List<FjStep> get journey => _journey;
  int get index => _index;
  FjStep get step => _journey[_index];
  int get stepCount => _journey.length;
  bool get atStart => _index == 0;
  bool get atEnd => _index >= stepCount - 1;
  bool get playing => _playing;
  bool get reducedMotion => _reducedMotion;
  DsCase get dsCase => _dsCase;
  DsExample get dsExampleNow => dsExample(_dsCase);
  DtsView get view => _view;
  DtsQuestion get question => _question;
  DtsGuess? get guess => _guess;
  List<FjNode> get nodes => journeyNodes(_config);

  /// 0 to 1: the wave's phase on the air hop. Holds still when paused.
  ValueListenable<double> get wave => _wave;

  /// The step index of the laptop's data link step going to the server (the
  /// step where Address 3 is set), for the question.
  int get _addressStep => _journey.indexWhere(
    (FjStep s) =>
        s.node == FjNode.laptop &&
        s.layer == FjLayer.dataLink &&
        s.link is FjWifiLink,
  );

  // ── Inputs ────────────────────────────────────────────────────────────────

  void _set(FjConfig next) {
    if (next == _config) return;
    final bool newPath =
        next.direction != _config.direction || next.server != _config.server;
    _config = next;
    _journey = buildJourney(next);
    if (newPath) {
      _stop();
      _index = 0;
      _dsCase = next.direction == FjDirection.toServer
          ? DsCase.toDs
          : DsCase.fromDs;
    } else {
      _index = _index.clamp(0, stepCount - 1);
    }
    _notify();
  }

  set direction(FjDirection v) => _set(_config.copyWith(direction: v));
  set server(FjServerLocation v) => _set(_config.copyWith(server: v));
  set transport(FjTransport v) => _set(_config.copyWith(transport: v));
  set payload(int v) => _set(_config.copyWith(payload: v));
  set qos(bool v) => _set(_config.copyWith(qos: v));

  set dsCase(DsCase v) {
    if (v == _dsCase) return;
    _dsCase = v;
    _notify();
  }

  set view(DtsView v) {
    if (v == _view) return;
    _view = v;
    _notify();
  }

  /// D: the next To DS / From DS case, and show the address view.
  void nextDsCase() {
    _dsCase = DsCase.values[(_dsCase.index + 1) % DsCase.values.length];
    _view = DtsView.addresses;
    _notify();
  }

  /// The journey position (the step slider).
  set index(int v) {
    final int next = v.clamp(0, stepCount - 1);
    if (next == _index) return;
    _index = next;
    _notify();
  }

  // ── Predict, then reveal ──────────────────────────────────────────────────

  /// Loads the question's scene: laptop to a server on another subnet, the
  /// journey at its start, the journey view.
  void ask() {
    _stop();
    _config = _config.copyWith(
      direction: FjDirection.toServer,
      server: FjServerLocation.otherSubnet,
    );
    _journey = buildJourney(_config);
    _index = 0;
    _dsCase = DsCase.toDs;
    _view = DtsView.journey;
    _question = DtsQuestion.asking;
    _guess = null;
    _notify();
  }

  set guess(DtsGuess? g) {
    if (g == _guess) return;
    _guess = g;
    _notify();
  }

  /// Shows the answer and jumps to the step where the laptop fills in the
  /// 802.11 header.
  void reveal() {
    if (_question != DtsQuestion.asking) return;
    _question = DtsQuestion.revealed;
    _index = _addressStep;
    _notify();
  }

  void dismissQuestion() {
    if (_question == DtsQuestion.idle) return;
    _question = DtsQuestion.idle;
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

  /// Space: play, or pause. At the end, starts over.
  void togglePlay() {
    if (_playing) {
      _stop();
      _notify();
      return;
    }
    if (atEnd) _index = 0;
    _view = DtsView.journey;
    _start();
  }

  /// Right arrow: pause and move one step on.
  void stepOnce() {
    _stop();
    if (!atEnd) _index++;
    _notify();
  }

  /// Back one step.
  void stepBack() {
    _stop();
    if (!atStart) _index--;
    _notify();
  }

  /// R: back to the start, paused.
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
          (elapsed.inMicroseconds % kDtsWaveDuration.inMicroseconds) /
          kDtsWaveDuration.inMicroseconds;
    }
    final int target =
        (_playFromIndex +
                elapsed.inMicroseconds ~/ kDtsStepDuration.inMicroseconds)
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
    sliderDown: stepBack,
    sliderUp: stepOnce,
    sliderLabel: 'Journey step',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyD,
        keyLabel: 'D',
        description: 'Next To DS / From DS case',
        onPressed: nextDsCase,
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyV,
        keyLabel: 'V',
        description: 'Switch between the journey and the address fields',
        onPressed: () => view = _view == DtsView.journey
            ? DtsView.addresses
            : DtsView.journey,
      ),
    ],
  );

  // ── Copy ──────────────────────────────────────────────────────────────────

  String copyText() {
    final FjStep s = step;
    final FjConfig c = _config;
    final StringBuffer b = StringBuffer()
      ..writeln(
        'Down the Stack, Across the Air, Up the Other Side (WLAN Pros Toolbox)',
      )
      ..writeln(
        '${c.direction.label}; server on ${c.server.label.toLowerCase()}; '
        '${c.transport.label}, ${c.payload} bytes of data; '
        '${c.qos ? 'QoS Data header' : 'textbook Data header'}',
      )
      ..writeln('Step ${s.index + 1} of $stepCount: ${s.title}')
      ..writeln(s.detail)
      ..writeln('Now: ${s.pduName}, ${s.pduBytes} bytes')
      ..writeln(
        'IP: ${s.ip.src} to ${s.ip.dst}, TTL ${s.ip.ttl}; ports '
        '${s.ports.src} to ${s.ports.dst}',
      );
    final FjLink? l = s.link;
    if (l is FjWifiLink) {
      b.writeln(l.dsCase.label);
      for (final AddressField f in l.fields) {
        b.writeln(
          'Address ${f.number} (${f.roleText}): ${f.mac} ${f.device.name}',
        );
      }
    } else if (l is FjEthLink) {
      b.writeln(
        'Ethernet: source ${l.src.mac} (${l.src.name}), destination '
        '${l.dst.mac} (${l.dst.name})',
      );
    }
    b.writeln(
      'Addresses are illustrative (IPs from RFC 5737 documentation ranges).',
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
