// State for the Wi-Fi Classroom tool "PoE: Why the New AP Runs at Half
// Strength" (poe-half-strength).
//
// One ChangeNotifier over an immutable PhConfig (the pure model in
// lib/services/wifi_lab/poe_half_strength_model.dart) and the
// predict-then-reveal flag, shared by the stage and the controls so they lay
// out independently: stacked on a phone, side by side on a wide window, and
// in the full-screen presenter layout, which uses this same object.
//
// Nothing animates: a port change is a state change, drawn at once.
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../services/wifi_lab/poe_half_strength_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';

export '../../../services/wifi_lab/poe_half_strength_model.dart';

class PoeHalfStrengthController extends ChangeNotifier {
  PoeHalfStrengthController({PhConfig initial = const PhConfig()})
    : _config = initial;

  PhConfig _config;
  bool _revealed = false;

  PhConfig get config => _config;
  bool get revealed => _revealed;

  void setPort(PhPort p) {
    if (p == _config.port) return;
    _config = _config.withPort(p);
    notifyListeners();
  }

  /// Up and Down in presenter mode: af, at, bt, with no wrap.
  void stepPort(int by) {
    const List<PhPort> all = PhPort.values;
    final int i = (all.indexOf(_config.port) + by).clamp(0, all.length - 1);
    setPort(all[i]);
  }

  void setAtMode(PhAtMode m) {
    if (m == _config.atMode) return;
    _config = _config.withAtMode(m);
    notifyListeners();
  }

  void toggleAtMode() => setAtMode(
    _config.atMode == PhAtMode.allAt2x2 ? PhAtMode.twoAt4x4 : PhAtMode.allAt2x2,
  );

  void setRevealed(bool v) {
    if (v == _revealed) return;
    _revealed = v;
    notifyListeners();
  }

  void toggleReveal() => setRevealed(!_revealed);

  void reset() {
    _config = const PhConfig();
    _revealed = false;
    notifyListeners();
  }

  /// Presenter keyboard. Nothing plays, so Space and Right are relabeled:
  /// Right steps to the next port type, Space switches what the AP gives up
  /// on 802.3at.
  PresenterActions get presenterActions => PresenterActions(
    playPause: toggleAtMode,
    playPauseLabel: 'Switch what the AP gives up on 802.3at',
    step: () => stepPort(1),
    stepLabel: 'Next switch port type',
    reset: reset,
    sliderDown: () => stepPort(-1),
    sliderUp: () => stepPort(1),
    sliderLabel: 'Switch port type',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.digit1,
        keyLabel: '1',
        description: '802.3af port',
        onPressed: () => setPort(PhPort.af),
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.digit2,
        keyLabel: '2',
        description: '802.3at port',
        onPressed: () => setPort(PhPort.at),
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.digit3,
        keyLabel: '3',
        description: '802.3bt port',
        onPressed: () => setPort(PhPort.bt),
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyP,
        keyLabel: 'P',
        description: 'Show or hide the prediction answer',
        onPressed: toggleReveal,
      ),
    ],
  );

  // ── Copy payload (GL-003 §8.16) ──────────────────────────────────────────

  String copyText() {
    final PhConfig c = _config;
    return <String>[
      'PoE: Why the New AP Runs at Half Strength',
      'Switch port: ${c.port.label}, ${PhFormat.watts(c.port.pseWatts)} from '
          'the switch, up to ${PhFormat.watts(c.port.pdWatts)} at the AP',
      '${PhLabels.genericAp}; power light on',
      for (final PhRadio r in PhRadio.values) '${r.label}: ${c.radioState(r)}',
      'Streams live: ${c.streamsLive} of ${PhAp.maxStreams} '
          '(${PhFormat.percent(c.streamShare)}); radios live: '
          '${c.radiosLive} of ${PhRadio.values.length}',
      if (c.port == PhPort.at) 'On 802.3at this AP runs ${c.atMode.phrase}',
      if (c.illustrative) PhLabels.afIllustrative,
      'Sources: Juniper Mist Wi-Fi 7 AP guide; Cisco Meraki Wi-Fi 7 '
          '(802.11be) Technical Guide; IEEE 802.3. ${PhLabels.vendorsDiffer}',
    ].join('\n');
  }
}
