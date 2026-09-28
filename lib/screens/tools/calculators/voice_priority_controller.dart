// State for the Wi-Fi Classroom tool Voice Priority, End to End
// (voice-priority).
//
// One ChangeNotifier over an immutable VpConfig (the pure model in
// lib/services/wifi_lab/voice_priority_model.dart), shared by the stage and
// the controls so the two lay out independently: stacked on a phone and in
// the full-screen presenter layout, which uses this same object (state is
// shared, not copied).
//
// The packet moves hop by hop: Step moves it one hop, Play moves it one hop
// per [kVpHopDuration] and stops at the phone. Each move is a jump, not a
// tween, so reduced motion changes nothing (GL-003 §8.8).
//
// ASCII only, no em dashes (GL-004).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../services/wifi_lab/voice_priority_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';

export '../../../services/wifi_lab/voice_priority_model.dart';

/// Time per hop while playing.
const Duration kVpHopDuration = Duration(milliseconds: 900);

/// The predict-then-reveal question.
const String kVpQuestionText =
    'The phone has WMM (Wi-Fi Multimedia) on and the call app marks its '
    'voice packets EF. Your internet provider resets the marking to 0. '
    'While a download runs, which queue does the call wait in on your '
    'Wi-Fi?';

enum VpQuestion { idle, asking, revealed }

enum VpGuess {
  voice('Voice'),
  video('Video'),
  bestEffort('Best effort');

  const VpGuess(this.label);

  final String label;
}

class VoicePriorityController extends ChangeNotifier {
  VoicePriorityController([VpConfig initial = const VpConfig()])
    : _config = initial,
      _trip = VpTrip(initial);

  VpConfig _config;
  VpTrip _trip;
  int _hop = 0;
  Timer? _timer;
  VpQuestion _question = VpQuestion.idle;
  VpGuess? _guess;

  VpConfig get config => _config;
  VpTrip get trip => _trip;

  /// Index into [VpTrip.hops] of the hop the packet is at.
  int get hop => _hop;
  int get hopCount => VpHopId.values.length;
  bool get atEnd => _hop >= hopCount - 1;
  bool get playing => _timer != null;

  VpQuestion get question => _question;
  VpGuess? get guess => _guess;

  /// While the class is predicting, the stage hides where the call lands.
  bool get hidingAnswer => _question == VpQuestion.asking;

  set guess(VpGuess? g) {
    _guess = g;
    notifyListeners();
  }

  void _set(VpConfig next) {
    if (next == _config) return;
    _config = next;
    _trip = VpTrip(next);
    notifyListeners();
  }

  set loss(MarkLoss v) => _set(_config.copyWith(loss: v));
  set mapping(ApMapping v) => _set(_config.copyWith(mapping: v));
  set downloadRunning(bool v) => _set(_config.copyWith(downloadRunning: v));
  set framesAhead(int v) => _set(_config.copyWith(framesAhead: v));

  /// The main control one step down or up the list of loss points.
  void shiftLoss(int delta) {
    const List<MarkLoss> all = MarkLoss.values;
    final int i = (_config.loss.index + delta).clamp(0, all.length - 1);
    loss = all[i];
  }

  void toggleDownload() => downloadRunning = !_config.downloadRunning;

  void toggleMapping() => mapping = _config.mapping == ApMapping.rfc8325
      ? ApMapping.topThreeBits
      : ApMapping.rfc8325;

  // ── The packet's trip ────────────────────────────────────────────────────

  set hop(int v) {
    final int next = v.clamp(0, hopCount - 1);
    if (next == _hop) return;
    _hop = next;
    notifyListeners();
  }

  void stepOnce() {
    if (atEnd) {
      _stop();
      notifyListeners();
      return;
    }
    hop = _hop + 1;
  }

  void togglePlay() {
    if (playing) {
      _stop();
      notifyListeners();
      return;
    }
    if (atEnd) _hop = 0;
    _timer = Timer.periodic(kVpHopDuration, (_) {
      stepOnce();
      if (atEnd) {
        _stop();
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Back to the defaults: the packet at the caller, no question showing.
  void reset() {
    _stop();
    _hop = 0;
    _question = VpQuestion.idle;
    _guess = null;
    _config = const VpConfig();
    _trip = VpTrip(_config);
    notifyListeners();
  }

  // ── Predict, then reveal ─────────────────────────────────────────────────

  /// Loads the question: the provider resets the marking, a download runs,
  /// the AP uses RFC 8325, and the packet waits at the caller.
  void ask() {
    _stop();
    _config = const VpConfig(loss: MarkLoss.isp);
    _trip = VpTrip(_config);
    _hop = 0;
    _guess = null;
    _question = VpQuestion.asking;
    notifyListeners();
  }

  /// Shows the answer and moves the packet onto the air.
  void reveal() {
    _stop();
    _question = VpQuestion.revealed;
    _hop = VpHopId.air.index;
    notifyListeners();
  }

  void dismissQuestion() {
    _question = VpQuestion.idle;
    _guess = null;
    notifyListeners();
  }

  /// P: ask when idle, reveal while asking, close when revealed.
  void cycleQuestion() => switch (_question) {
    VpQuestion.idle => ask(),
    VpQuestion.asking => reveal(),
    VpQuestion.revealed => dismissQuestion(),
  };

  /// The right answer to the loaded question.
  VpGuess get rightAnswer => switch (_trip.queue) {
    AccessCategory.voice => VpGuess.voice,
    AccessCategory.video => VpGuess.video,
    _ => VpGuess.bestEffort,
  };

  /// Presenter keyboard: Space plays the trip, Right steps one hop, R
  /// resets, Up and Down move where the marking is lost; D starts or stops
  /// the download, M switches the AP mapping, P asks, reveals and closes.
  PresenterActions get presenterActions => PresenterActions(
    playPause: togglePlay,
    playPauseLabel: 'Send the packet, or pause',
    step: stepOnce,
    stepLabel: 'Move the packet one hop',
    reset: reset,
    sliderDown: () => shiftLoss(-1),
    sliderUp: () => shiftLoss(1),
    sliderLabel: 'Where the marking is lost',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyD,
        keyLabel: 'D',
        description: 'Start or stop the download',
        onPressed: toggleDownload,
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyM,
        keyLabel: 'M',
        description: 'Switch the AP mapping',
        onPressed: toggleMapping,
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyP,
        keyLabel: 'P',
        description: 'Ask the question, reveal, close',
        onPressed: cycleQuestion,
      ),
    ],
  );

  // ── Copy payload (GL-003 §8.16) ──────────────────────────────────────────

  String copyText() {
    final VpTrip t = _trip;
    final VpConfig c = _config;
    final StringBuffer b = StringBuffer()
      ..writeln('Voice Priority, End to End')
      ..writeln(
        'Marking lost: ${c.loss.label.toLowerCase()}; AP mapping: '
        '${c.mapping.label}; download '
        '${c.downloadRunning ? 'running' : 'stopped'}',
      );
    for (final VpHop h in t.hops) {
      b.writeln(
        '${h.id.label}: ${dscpLabel(h.dscpOut)}. ${h.note}'
        '${h.lostHere ? ' (marking lost here)' : ''}',
      );
    }
    b
      ..writeln(
        'The call waits in ${t.queue.label} (${acCode(t.queue)}, UP ${t.up}): '
        '${vpMs(t.waitUs)} on the Wi-Fi hop',
      )
      ..writeln(
        'Wi-Fi hop from the Medium Access Simulator engine: 1,500-byte '
        'frames at 54 Mbps, a voice packet every 20 ms and '
        '${c.framesAhead} download frames ahead in Best effort '
        '(illustrative)',
      );
    return b.toString().trimRight();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
