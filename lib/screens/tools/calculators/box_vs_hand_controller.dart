// State for the Wi-Fi Classroom tool The Number on the Box vs the Number in
// Your Hand (box-vs-hand).
//
// One ChangeNotifier shared by the stage and the controls, so the two lay out
// independently: stacked on a phone, side by side on a wide window, and in the
// presenter layout, which uses this same object (state is shared, not
// copied). All math is in lib/services/wifi_lab/box_vs_hand_model.dart.
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/box_vs_hand_model.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';
import '../../../widgets/presenter/presenter_actions.dart';

export '../../../services/wifi_lab/box_vs_hand_model.dart';

/// How long a bar takes to shrink to its new length. A teaching animation,
/// slow enough to watch; zero under reduced motion (the stage checks).
const Duration kBvhShrinkDuration = Duration(milliseconds: 900);

class BoxVsHandController extends ChangeNotifier {
  BvhClient _client = BvhClient.phone2x2;
  BvhStep _step = BvhStep.box;
  double _distanceM = BoxVsHand.defaultDistanceM;
  int _widthMHz = BoxVsHand.defaultWidthMHz;
  UnitSystem _units = UnitSystem.metric;

  BvhClient get client => _client;
  BvhStep get step => _step;
  double get distanceM => _distanceM;
  int get widthMHz => _widthMHz;

  /// Length units on screen. The model stays in metres.
  UnitSystem get units => _units;

  LengthFormat get length => LengthFormat(_units);

  void setUnits(UnitSystem u) {
    if (u == _units) return;
    _units = u;
    notifyListeners();
  }

  void setClient(BvhClient c) {
    if (c == _client) return;
    _client = c;
    notifyListeners();
  }

  /// Up and Down in presenter mode walk the client list (Up toward more
  /// streams), clamped at each end.
  void shiftClient(int by) {
    final int i = (_client.index + by).clamp(0, BvhClient.values.length - 1);
    setClient(BvhClient.values[i]);
  }

  void setStep(BvhStep s) {
    if (s == _step) return;
    _step = s;
    notifyListeners();
  }

  bool get canAdvance => _step.index < BvhStep.values.length - 1;
  bool get canGoBack => _step.index > 0;

  void nextStep() {
    if (canAdvance) setStep(BvhStep.values[_step.index + 1]);
  }

  void previousStep() {
    if (canGoBack) setStep(BvhStep.values[_step.index - 1]);
  }

  /// Space: from the box straight to the hand, and back.
  void jump() =>
      setStep(_step == BvhStep.atDistance ? BvhStep.box : BvhStep.atDistance);

  void setDistance(double m) {
    final double d = m.clamp(BoxVsHand.minDistanceM, BoxVsHand.maxDistanceM);
    if (d == _distanceM) return;
    _distanceM = d;
    notifyListeners();
  }

  void setWidth(int w) {
    if (!BoxVsHand.widthsMHz.contains(w) || w == _widthMHz) return;
    _widthMHz = w;
    notifyListeners();
  }

  void reset() {
    _client = BvhClient.phone2x2;
    _step = BvhStep.box;
    _distanceM = BoxVsHand.defaultDistanceM;
    _widthMHz = BoxVsHand.defaultWidthMHz;
    notifyListeners();
  }

  // ── Derived ─────────────────────────────────────────────────────────────

  double get boxMbps => BoxVsHand.boxMbps;
  double get bestCaseMbps => BoxVsHand.bestCaseMbps(_client);

  BvhReading get reading => BoxVsHand.reading(
    client: _client,
    distanceM: _distanceM,
    widthMHz: _widthMHz,
  );

  /// The distance step's heading: "At 5.0 m on a 320 MHz channel".
  String get distanceHeading =>
      'At ${length.dist(_distanceM)} on a $_widthMHz MHz channel';

  // ── Presenter keyboard ──────────────────────────────────────────────────

  /// Right shows the next step, Left the one before, Space jumps between the
  /// box and the hand, Up and Down change the client, R resets. Nothing
  /// plays, so Space and Right are relabeled in the shortcut list.
  PresenterActions get presenterActions => PresenterActions(
    playPause: jump,
    playPauseLabel: 'Jump between the box and the hand',
    step: nextStep,
    stepLabel: 'Show the next step',
    reset: reset,
    sliderDown: () => shiftClient(-1),
    sliderUp: () => shiftClient(1),
    sliderLabel: 'Client',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.arrowLeft,
        keyLabel: 'Left arrow',
        description: 'Show the step before',
        onPressed: previousStep,
      ),
    ],
  );

  // ── Copy payload (GL-003 §8.16) ────────────────────────────────────────

  String copyText() {
    final BvhReading r = reading;
    final StringBuffer b = StringBuffer()
      ..writeln('The Number on the Box vs the Number in Your Hand')
      ..writeln(
        'On the box: a ${BoxVsHand.className}-class router, '
        '${BvhFormat.mbps(boxMbps)} = '
        '${BoxVsHand.radios.map((BvhRadio x) => '${BvhFormat.mbps(x.datasheetMbps)} (${x.band.label})').join(' + ')}',
      )
      ..writeln(
        'Best case, ${_client.label.toLowerCase()}: '
        '${BvhFormat.mbps(bestCaseMbps)} (one link, 6 GHz, '
        '${BoxVsHand.bestRadio.widthMHz} MHz, ${_client.streams} streams, '
        'MCS ${BoxVsHand.topMcs}), ${BvhFormat.pct(bestCaseMbps, boxMbps)} '
        'of the box',
      )
      ..writeln(
        '$distanceHeading (6 GHz, 20 dBm EIRP, path-loss exponent 3): '
        '${BvhFormat.dbm(r.receivedDbm)}, '
        '${r.mcs == null ? 'below MCS 0, no link' : 'MCS ${r.mcs}, PHY ${BvhFormat.mbps(r.phyMbps)}, estimate ${BvhFormat.mbps(r.estimateMbps)} (x ${BoxVsHand.efficiency.toStringAsFixed(2)}, a favorable estimate)'}',
      );
    return b.toString().trimRight();
  }
}
