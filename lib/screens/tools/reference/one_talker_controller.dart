// State for the One Talker per Channel lesson (one-talker).
//
// One ChangeNotifier shared by the stage and the controls, so the lesson's
// "Try it" card and the presenter layout drive the same scene (state is
// shared, not copied). All arithmetic is in
// lib/services/wifi_lab/one_talker_model.dart.
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../services/wifi_lab/one_talker_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';

export '../../../services/wifi_lab/one_talker_model.dart';

class OneTalkerController extends ChangeNotifier {
  OneTalkerConfig _config = OneTalkerConfig();
  int _turn = 0;

  OneTalkerConfig get config => _config;

  /// How many times the turn has been passed since the last reset.
  int get turn => _turn;

  OneTalkerScene get scene => oneTalker(_config);

  bool get isDefault {
    final OneTalkerConfig d = OneTalkerConfig();
    return _turn == 0 &&
        _config.clientsA == d.clientsA &&
        _config.secondAp == d.secondAp &&
        _config.clientsB == d.clientsB &&
        _config.slowTalker == d.slowTalker;
  }

  void _set(OneTalkerConfig c) {
    _config = c;
    notifyListeners();
  }

  // ── Access point 1 ──────────────────────────────────────────────────────

  bool get canAddA => _config.clientsA < kMaxClientsA;
  bool get canRemoveA => _config.clientsA > kMinClients;

  /// Up and Down in presenter mode, clamped at each end.
  void shiftClientsA(int by) {
    final int n = (_config.clientsA + by).clamp(kMinClients, kMaxClientsA);
    if (n != _config.clientsA) _set(_config.copyWith(clientsA: n));
  }

  // ── Access point 2 ──────────────────────────────────────────────────────

  bool get canAddB => _config.hasSecondAp && _config.clientsB < kMaxClientsB;
  bool get canRemoveB => _config.hasSecondAp && _config.clientsB > kMinClients;

  void shiftClientsB(int by) {
    final int n = (_config.clientsB + by).clamp(kMinClients, kMaxClientsB);
    if (n != _config.clientsB) _set(_config.copyWith(clientsB: n));
  }

  void setSecondAp(SecondAp s) {
    if (s != _config.secondAp) _set(_config.copyWith(secondAp: s));
  }

  /// Space: same channel and other channel swap. With no second access
  /// point, Space adds one on the same channel.
  void toggleChannel() => setSecondAp(
    _config.secondAp == SecondAp.sameChannel
        ? SecondAp.otherChannel
        : SecondAp.sameChannel,
  );

  /// A: add the second access point (same channel) or take it away.
  void toggleSecondAp() =>
      setSecondAp(_config.hasSecondAp ? SecondAp.none : SecondAp.sameChannel);

  // ── The slow talker and the turn ────────────────────────────────────────

  void setSlowTalker(bool on) {
    if (on != _config.slowTalker) _set(_config.copyWith(slowTalker: on));
  }

  void toggleSlowTalker() => setSlowTalker(!_config.slowTalker);

  /// Pass the turn: the next device on each channel transmits.
  void nextTurn() {
    _turn++;
    notifyListeners();
  }

  void reset() {
    _config = OneTalkerConfig();
    _turn = 0;
    notifyListeners();
  }

  // ── Presenter keyboard ──────────────────────────────────────────────────

  /// Up and Down add or remove a device on access point 1, Space swaps the
  /// second access point's channel, Right passes the turn, A adds or removes
  /// the second access point, S makes device A slow, R resets.
  PresenterActions get presenterActions => PresenterActions(
    playPause: toggleChannel,
    playPauseLabel: 'Second access point: same channel or other channel',
    step: nextTurn,
    stepLabel: 'Pass the turn',
    reset: reset,
    sliderDown: () => shiftClientsA(-1),
    sliderUp: () => shiftClientsA(1),
    sliderLabel: 'Devices on access point 1',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyA,
        keyLabel: 'A',
        description: 'Add or remove the second access point',
        onPressed: toggleSecondAp,
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyS,
        keyLabel: 'S',
        description: 'Make device A slow, or fast again',
        onPressed: toggleSlowTalker,
      ),
    ],
  );
}
