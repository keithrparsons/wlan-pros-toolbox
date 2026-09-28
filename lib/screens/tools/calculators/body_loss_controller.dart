// State for the Wi-Fi Classroom Body Loss tool (body-loss).
//
// One ChangeNotifier over an immutable BlConfig (the pure model in
// lib/services/wifi_lab/body_loss_model.dart), shared by the stage and the
// controls so the two lay out independently: stacked on a phone, side by side
// on a wide window, and in the full-screen presenter layout, which uses this
// same object (state is shared, not copied).
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/body_loss_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';
import '../../../units/unit_system.dart';

export '../../../services/wifi_lab/body_loss_model.dart';

class BodyLossController extends ChangeNotifier {
  UnitSystem _units = UnitSystem.metric;

  /// Length units on screen. The model stays in metres.
  UnitSystem get units => _units;

  void setUnits(UnitSystem u) {
    if (u == _units) return;
    _units = u;
    notifyListeners();
  }

  BodyLossController([BlConfig? initial]) : _config = initial ?? BlConfig();

  BlConfig _config;
  bool _revealed = false;
  int _revision = 0;

  /// Degrees per press of Left or Right in presenter mode.
  static const double keyTurnDeg = 15;

  /// People per press of Up or Down in presenter mode.
  static const int keyCrowdStep = 5;

  BlConfig get config => _config;

  /// Whether the predict-then-reveal answer is showing.
  bool get revealed => _revealed;

  /// Bumped on every change that alters what the stage draws.
  int get revision => _revision;

  void _set(BlConfig next) {
    _config = next;
    _revision++;
    notifyListeners();
  }

  void setBand(WifiBand b) => _set(_config.withBand(b));
  void setHolderLoss(double v) => _set(_config.withHolderLoss(v));
  void setPerPersonLoss(double v) => _set(_config.withPerPersonLoss(v));
  void setMultiplier5(double v) => _set(_config.withMultiplier5(v));
  void setMultiplier6(double v) => _set(_config.withMultiplier6(v));
  void setCrowdSize(int n) => _set(_config.withCrowdSize(n));
  void setOccupied(bool v) => _set(_config.withOccupied(v));
  void toggleOccupied() => _set(_config.toggleOccupied());
  void scatter() => _set(_config.scatter());
  void setFacing(double deg) => _set(_config.withFacing(deg));
  void rotate(double deg) => _set(_config.rotatedBy(deg));
  void faceToward(BlPoint p) => _set(_config.facing(p));
  void faceAp() => _set(_config.facingAp());
  void backToAp() => _set(_config.backToAp());
  void moveHolder(BlPoint p) => _set(_config.withHolder(p));
  void setHolderX(double x) => _set(_config.withHolderX(x));
  void movePerson(int i, BlPoint p) => _set(_config.withPerson(i, p));

  void setRevealed(bool v) {
    _revealed = v;
    _revision++;
    notifyListeners();
  }

  void toggleReveal() => setRevealed(!_revealed);

  /// Back to the defaults; the answer hides.
  void reset() {
    _revealed = false;
    _set(_config.reset());
  }

  /// Presenter keyboard (spec 34): Left and Right turn the holder, Space
  /// empties or fills the room, R resets. Up and Down change the crowd size;
  /// P reveals the answer. Nothing animates, so there is no play or step:
  /// Space and Right are relabeled in the shortcut list to say what they do.
  PresenterActions get presenterActions => PresenterActions(
    playPause: toggleOccupied,
    playPauseLabel: 'Empty the room or fill it',
    step: () => rotate(keyTurnDeg),
    stepLabel: 'Turn the holder clockwise',
    reset: reset,
    sliderDown: () => setCrowdSize(_config.crowdSize - keyCrowdStep),
    sliderUp: () => setCrowdSize(_config.crowdSize + keyCrowdStep),
    sliderLabel: 'Crowd size',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.arrowLeft,
        keyLabel: 'Left arrow',
        description: 'Turn the holder counterclockwise',
        onPressed: () => rotate(-keyTurnDeg),
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyP,
        keyLabel: 'P',
        description: 'Show or hide the prediction answer',
        onPressed: toggleReveal,
      ),
    ],
  );

  // ── Copy payload (GL-003 §8.16) ────────────────────────────────────────

  String copyText() {
    final BlConfig c = _config;
    final String Function(double, [int]) n = BlFormat.n;
    return <String>[
      'Body Loss',
      '${c.band.label} ch ${c.channel} (${c.freqMHz.round()} MHz), 20 MHz, '
          'AP radiates ${n(BlConfig.apEirpDbm, 0)} dBm, path-loss exponent '
          '${n(BlConfig.exponent)}, device ${BlFormat.dist(c.distanceM, _units)} from '
          'the AP',
      'Illustrative losses: holder ${n(c.holderLossDb)} dB at 2.4 GHz, '
          '${n(c.perPersonLossDb)} dB per person at 2.4 GHz, band multipliers '
          '1.0 / ${n(c.multiplier5, 2)} / ${n(c.multiplier6, 2)} '
          '(2.4 / 5 / 6 GHz)',
      'Holder facing ${BlFormat.deg(c.facingDeg)}, '
          '${BlFormat.deg(c.offAxisDeg)} off the AP: holder loss '
          '${BlFormat.db(c.holderLossAppliedDb)}',
      '${c.occupied ? 'Occupied' : 'Empty'}, ${c.crowdSize} people in the '
          'room, ${BlFormat.people(c.crossingCount)} on the line: crowd loss '
          '${BlFormat.db(c.crowdLossDb)}',
      'Received ${BlFormat.dbm(c.receivedDbm)}, ${BlFormat.mcs(c.mcs)} '
          '(modulation and coding scheme)',
      'Empty ${BlFormat.dbm(c.emptyDbm)} (${BlFormat.mcs(c.mcsEmpty)}) vs '
          'occupied ${BlFormat.dbm(c.occupiedDbm)} '
          '(${BlFormat.mcs(c.mcsOccupied)}): '
          '${BlFormat.db(c.emptyVsOccupiedDb)}',
    ].join('\n');
  }
}
