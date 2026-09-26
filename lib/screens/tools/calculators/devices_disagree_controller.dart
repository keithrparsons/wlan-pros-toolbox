// State for the Wi-Fi Classroom tool Why Two Devices Disagree
// (devices-disagree).
//
// One ChangeNotifier holds every input and caches the one computed run, so
// the stage (DevicesDisagreeStage) and the controls (DevicesDisagreeControls)
// are independent widgets over the same object. The phone layout stacks
// them; the presenter layout puts them side by side (spec 00).
//
// All physics lives in lib/services/wifi_lab/devices_disagree_model.dart.
// This file only holds the settings, which device is being edited, the two
// teaching toggles (Apply offsets, the predict-then-reveal card), and the
// number formatting shared by stage, controls and copy.
//
// Nothing animates. A run is a few seconds of readings computed at once;
// Re-sample (Space) takes the next few seconds with a new fading draw.
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/foundation.dart';

import '../../../services/wifi_lab/devices_disagree_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kDevicesDisagreeToolId = 'devices-disagree';

/// Screen title, one home.
const String kDevicesDisagreeTitle = 'Why Two Devices Disagree';

/// The predict-then-reveal prompt (spec 31, "Screen").
const String kDdPredictPrompt =
    'Laptop says -62, phone says -68, same spot. Which one is right?';

/// Number formatting shared by stage, controls and copy.
abstract final class DdFormat {
  static String _n(double v, int decimals) {
    final String s = v.toStringAsFixed(decimals);
    return RegExp(r'^-0\.?0*$').hasMatch(s) ? s.substring(1) : s;
  }

  /// A power reading, "-62 dBm" (whole dB, as a device reports it).
  static String dbm(double v) => '${_n(v, 0)} dBm';

  /// True power, one decimal: "-60.4 dBm".
  static String dbmPrecise(double v) => '${_n(v, 1)} dBm';

  /// A spread or a loss, "6 dB".
  static String db(double v, [int decimals = 0]) => '${_n(v, decimals)} dB';

  /// A signed offset, "+1 dB", "-4 dB", "0 dB".
  static String signedDb(double v) {
    final String s = _n(v, 0);
    return v > 0 ? '+$s dB' : '$s dB';
  }

  static String meters(double m) =>
      '${_n(m, m == m.roundToDouble() ? 0 : 1)} m';

  static String cm(double m) => '${_n(m * 100, 0)} cm';

  static String cmPrecise(double m) => '${_n(m * 100, 1)} cm';
}

class DevicesDisagreeController extends ChangeNotifier {
  DevicesDisagreeController({DdConfig? initial})
    : _config = initial ?? DdConfig();

  DdConfig _config;
  int _selected = 0;
  bool _applyOffsets = false;
  bool _revealed = false;
  DdResult? _result;

  // ── Read side ─────────────────────────────────────────────────────────────

  DdConfig get config => _config;

  /// The computed run for the current settings (cached).
  DdResult get result => _result ??= DdResult.compute(_config);

  /// The device being edited (0 = A).
  int get selected => _selected;
  DeviceSettings get selectedDevice => _config.devices[_selected];

  bool get applyOffsets => _applyOffsets;
  bool get revealed => _revealed;

  /// Which sample set this is (1 for a fresh start; Re-sample adds one).
  int get sampleSet => _config.seed;

  // ── Settings ──────────────────────────────────────────────────────────────

  void _setConfig(DdConfig next) {
    if (next == _config) return;
    _config = next;
    _result = null;
    notifyListeners();
  }

  set band(DdBand v) => _setConfig(_config.copyWith(band: v));
  set distanceM(double v) => _setConfig(_config.copyWith(distanceM: v));
  set fadingOn(bool v) => _setConfig(_config.copyWith(fadingOn: v));
  set spacingM(double v) => _setConfig(_config.copyWith(spacingM: v));
  set bodyLossDb(double v) => _setConfig(_config.copyWith(bodyLossDb: v));

  set deviceCount(int v) {
    final DdConfig next = _config.copyWith(deviceCount: v);
    if (_selected >= next.deviceCount) _selected = next.deviceCount - 1;
    _setConfig(next);
  }

  void selectDevice(int index) {
    final int i = index.clamp(0, _config.deviceCount - 1);
    if (i == _selected) return;
    _selected = i;
    notifyListeners();
  }

  /// Replaces the edited device's settings.
  void editDevice(DeviceSettings Function(DeviceSettings d) change) =>
      _setConfig(_config.withDevice(_selected, change(selectedDevice)));

  set applyOffsets(bool v) {
    if (v == _applyOffsets) return;
    _applyOffsets = v;
    notifyListeners();
  }

  void reveal() {
    if (_revealed) return;
    _revealed = true;
    notifyListeners();
  }

  /// The next few seconds: same room and devices, a new fading draw.
  void resample() => _setConfig(_config.copyWith(seed: _config.seed + 1));

  /// Every setting back to its default, first sample set, answer hidden.
  void reset() {
    _config = DdConfig();
    _selected = 0;
    _applyOffsets = false;
    _revealed = false;
    _result = null;
    notifyListeners();
  }

  /// Up and Down: the AP distance one meter.
  void nudgeDistance(double deltaM) =>
      distanceM = (_config.distanceM + deltaM).roundToDouble();

  // ── Presenter keys ────────────────────────────────────────────────────────

  PresenterActions get presenterActions => PresenterActions(
    playPause: resample,
    playPauseLabel: 'Re-sample',
    reset: reset,
    sliderDown: () => nudgeDistance(-1),
    sliderUp: () => nudgeDistance(1),
    sliderLabel: 'AP distance',
  );

  // ── Derived text ──────────────────────────────────────────────────────────

  /// "Device A (laptop)".
  String deviceName(int index) =>
      'Device ${deviceLetter(index)} '
      '(${_config.devices[index].kind.label.toLowerCase()})';

  /// The value a device shows now, with or without its offset applied.
  double shownNow(int index) {
    final DeviceTrace t = result.traces[index];
    return _applyOffsets ? t.latestCorrected : t.latest;
  }

  /// The answer to the predict-then-reveal prompt, with this run's numbers.
  String get revealText {
    final DdResult r = result;
    return 'Neither one, on its own. Each number is the true power plus that '
        "device's own fixed offset, minus how it is held and any body in "
        'the way, plus the fading at the exact spot its antenna sits. Here '
        'the true power is ${DdFormat.dbmPrecise(r.trueDbm)}, and right now '
        'the devices spread ${DdFormat.db(r.spreadNow())}. Turn on Apply '
        'offsets: the fixed part goes away, and the grip, body and fading '
        'stay.';
  }

  // ── Copy payload (GL-003 §8.16) ────────────────────────────────────────────

  String copyText() {
    final DdResult r = result;
    final DdConfig c = _config;
    final StringBuffer b = StringBuffer()
      ..writeln('$kDevicesDisagreeTitle (WLAN Pros Toolbox, teaching model)')
      ..writeln(
        'Band ${c.band.label}, AP ${DdFormat.meters(c.distanceM)} away, '
        'true power ${DdFormat.dbmPrecise(r.trueDbm)}',
      )
      ..writeln(
        'Fading ${c.fadingOn ? 'on' : 'off'}, devices '
        '${DdFormat.cm(c.spacingM)} apart, sample set ${c.seed}',
      );
    for (int i = 0; i < r.traces.length; i++) {
      final DeviceTrace t = r.traces[i];
      final DeviceSettings d = t.settings;
      b.writeln(
        '${deviceName(i)}: reports ${DdFormat.dbm(t.latest)}, with offset '
        'applied ${DdFormat.dbm(t.latestCorrected)} (offset '
        '${DdFormat.signedDb(d.offsetDb)}, grip ${DdFormat.db(d.gripLossDb)}, '
        'body ${DdFormat.db(t.bodyLossDb)}, ${d.stepDb} dB step, average of '
        '${d.averaging})',
      );
    }
    b
      ..writeln(
        'Spread now ${DdFormat.db(r.spreadNow())}, after offsets '
        '${DdFormat.db(r.spreadNow(corrected: true))}',
      )
      ..writeln(
        'Average spread over $kStripSeconds s '
        '${DdFormat.db(r.meanSpread(), 1)}, after offsets '
        '${DdFormat.db(r.meanSpread(corrected: true), 1)}',
      )
      ..writeln(
        'Offsets, grip and body losses, AP power and path loss are '
        'illustrative.',
      );
    return b.toString().trimRight();
  }
}
