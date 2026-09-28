// State for the Wi-Fi Classroom tool Conference Wi-Fi Runs Out of Addresses
// (dhcp-exhaustion).
//
// One ChangeNotifier over an immutable DxConfig and the DxMorning it
// produces (the pure model in lib/services/wifi_lab/
// dhcp_exhaustion_model.dart), shared by the stage and the controls, and by
// the presenter layout (state is shared, not copied).
//
// The playhead walks the morning: Play moves it [kDxPlayStepMinutes] per
// [kDxTick] and stops at 13:00; Step moves it 10 minutes. Each move is a
// jump, not a tween, so reduced motion changes nothing (GL-003 §8.8).
//
// ASCII only, no em dashes (GL-004).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../services/wifi_lab/dhcp_exhaustion_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';

export '../../../services/wifi_lab/dhcp_exhaustion_model.dart';

/// Playhead speed while playing.
const Duration kDxTick = Duration(milliseconds: 150);
const int kDxPlayStepMinutes = 5;

/// What Step and the Right arrow move.
const int kDxStepMinutes = 10;

/// The predict-then-reveal question.
const String kDxQuestionText =
    'A conference hall, 07:00 to 13:00. The Wi-Fi hands out addresses from '
    'a /24 with a 1-day lease. Mid-morning, people say the Wi-Fi is down: '
    'full bars, nothing loads. What fixes it?';

enum DxQuestion { idle, asking, revealed }

enum DxGuess {
  moreAps('Add more APs'),
  leaseOrPool('A shorter lease or a bigger pool'),
  fasterLine('A faster internet line');

  const DxGuess(this.label);

  final String label;
}

class DhcpExhaustionController extends ChangeNotifier {
  DhcpExhaustionController([DxConfig initial = const DxConfig()])
    : _config = initial,
      _morning = DxMorning(initial);

  DxConfig _config;
  DxMorning _morning;
  int _minute = 0;
  Timer? _timer;
  DxQuestion _question = DxQuestion.idle;
  DxGuess? _guess;

  DxConfig get config => _config;
  DxMorning get morning => _morning;

  /// Playhead, minutes after 07:00 (0 to [kDxMinutes]).
  int get minute => _minute;
  DxMinute get now => _morning.minutes[_minute];
  bool get atEnd => _minute >= kDxMinutes;
  bool get playing => _timer != null;

  DxQuestion get question => _question;
  DxGuess? get guess => _guess;

  /// While the class predicts, the headline keeps the reason to itself.
  bool get hidingAnswer => _question == DxQuestion.asking;

  set guess(DxGuess? g) {
    _guess = g;
    notifyListeners();
  }

  void _set(DxConfig next) {
    if (next == _config) return;
    _config = next;
    _morning = DxMorning(next);
    notifyListeners();
  }

  set leaseMinutes(int v) => _set(_config.copyWith(leaseMinutes: v));
  set prefix(int v) => _set(_config.copyWith(prefix: v));
  set reserved(int v) => _set(_config.copyWith(reserved: v));
  set people(int v) => _set(_config.copyWith(people: v));
  set devicesPerPerson(double v) => _set(_config.copyWith(devicesPerPerson: v));
  set stayMinutes(int v) => _set(_config.copyWith(stayMinutes: v));
  set rotation(bool v) => _set(_config.copyWith(rotation: v));
  set rotatingShare(double v) => _set(_config.copyWith(rotatingShare: v));
  set rotationMinutes(int v) => _set(_config.copyWith(rotationMinutes: v));

  /// Index of the lease in [kDxLeaseChoices].
  int get leaseIndex {
    final int i = kDxLeaseChoices.indexOf(_config.leaseMinutes);
    return i < 0 ? kDxLeaseChoices.length - 1 : i;
  }

  /// The main control one choice shorter (-1) or longer (+1).
  void shiftLease(int delta) {
    final int i = (leaseIndex + delta).clamp(0, kDxLeaseChoices.length - 1);
    leaseMinutes = kDxLeaseChoices[i];
  }

  void toggleRotation() => rotation = !_config.rotation;

  // ── The playhead ─────────────────────────────────────────────────────────

  set minute(int v) {
    final int next = v.clamp(0, kDxMinutes);
    if (next == _minute) return;
    _minute = next;
    notifyListeners();
  }

  void stepOnce() {
    if (atEnd) {
      _stop();
      notifyListeners();
      return;
    }
    minute = _minute + kDxStepMinutes;
  }

  void togglePlay() {
    if (playing) {
      _stop();
      notifyListeners();
      return;
    }
    if (atEnd) _minute = 0;
    _timer = Timer.periodic(kDxTick, (_) {
      _minute = (_minute + kDxPlayStepMinutes).clamp(0, kDxMinutes);
      if (atEnd) _stop();
      notifyListeners();
    });
    notifyListeners();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Back to the defaults: 07:00, no question showing.
  void reset() {
    _stop();
    _minute = 0;
    _question = DxQuestion.idle;
    _guess = null;
    _config = const DxConfig();
    _morning = DxMorning(_config);
    notifyListeners();
  }

  // ── Predict, then reveal ─────────────────────────────────────────────────

  /// Loads the question: the defaults, the playhead at the first minute
  /// anyone goes without an address.
  void ask() {
    _stop();
    _config = const DxConfig();
    _morning = DxMorning(_config);
    _minute = _morning.firstDryMinute ?? 0;
    _guess = null;
    _question = DxQuestion.asking;
    notifyListeners();
  }

  void reveal() {
    _stop();
    _question = DxQuestion.revealed;
    notifyListeners();
  }

  void dismissQuestion() {
    _question = DxQuestion.idle;
    _guess = null;
    notifyListeners();
  }

  /// P: ask when idle, reveal while asking, close when revealed.
  void cycleQuestion() => switch (_question) {
    DxQuestion.idle => ask(),
    DxQuestion.asking => reveal(),
    DxQuestion.revealed => dismissQuestion(),
  };

  /// The same crowd with a 30-minute lease, for the revealed answer.
  DxMorning get shortLeaseMorning =>
      DxMorning(_config.copyWith(leaseMinutes: 30));

  /// Presenter keyboard: Space plays the morning, Right moves 10 minutes,
  /// R resets, Up and Down change the lease; M switches address rotation,
  /// P asks, reveals and closes the question.
  PresenterActions get presenterActions => PresenterActions(
    playPause: togglePlay,
    playPauseLabel: 'Play the morning, or pause',
    step: stepOnce,
    stepLabel: 'Forward 10 minutes',
    reset: reset,
    sliderDown: () => shiftLease(-1),
    sliderUp: () => shiftLease(1),
    sliderLabel: 'Lease time',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyM,
        keyLabel: 'M',
        description: 'Private-address rotation on or off',
        onPressed: toggleRotation,
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
    final DxConfig c = _config;
    final DxMorning m = _morning;
    final DxMinute x = now;
    final int? dry = m.firstDryMinute;
    final StringBuffer b = StringBuffer()
      ..writeln('Conference Wi-Fi Runs Out of Addresses')
      ..writeln(
        'Pool: /${c.prefix}, ${c.usableHosts} usable minus ${c.reserved} '
        'reserved = ${m.poolSize} addresses; lease '
        '${dxLeaseLabel(c.leaseMinutes)}',
      )
      ..writeln(
        'Crowd (illustrative): ${c.people} people, ${c.devicesPerPerson} '
        'devices each, ${c.stayMinutes} min average stay',
      )
      ..writeln(
        c.rotation
            ? 'Private-address rotation on (assumption): '
                  '${(c.rotatingShare * 100).round()}% of devices, a new '
                  'address every ${c.rotationMinutes} min'
            : 'Private-address rotation off',
      )
      ..writeln(
        dry == null
            ? 'The pool held all morning; peak ${m.peakBound} bound'
            : 'Ran dry at ${dxClock(dry)}; up to ${m.peakWaiting} devices '
                  'without an address',
      )
      ..writeln(
        'At ${dxClock(_minute)}: ${x.devicesHere} devices in the hall, '
        '${x.inUse} addresses in use, ${x.heldLeft} held for devices that '
        'left, ${x.heldRotated} held for old private addresses, '
        '${m.poolSize - x.bound} free, ${x.waiting} devices with no address',
      );
    return b.toString().trimRight();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
