// State for the Wi-Fi Classroom "Where Am I?" tool (location-rssi-ftm).
//
// One ChangeNotifier holds every input, the run and the lesson step, so the
// two halves of the screen stay independent widgets: LocationStage (the
// floor, the circles and the scatter) and LocationControls (inputs, readouts
// and the worked example) each listen to this one object. The phone layout
// stacks them; the presenter layout places them side by side (spec 00).
//
// All math lives in lib/services/wifi_lab/location_engine.dart. A run is 50
// trials of 3 to 6 APs (well under a millisecond), recomputed whole on every
// change, so there is no clock and nothing animates.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../services/wifi_lab/location_engine.dart';
import '../../../widgets/presenter/presenter_actions.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kLocationToolId = 'location-rssi-ftm';

/// What the floor shows.
enum LocView {
  signal('Signal strength'),
  ftm('Timing'),
  both('Both');

  const LocView(this.label);

  final String label;

  /// The methods this view draws, in order.
  List<LocMethod> get methods => switch (this) {
    LocView.signal => const <LocMethod>[LocMethod.signal],
    LocView.ftm => const <LocMethod>[LocMethod.ftm],
    LocView.both => const <LocMethod>[LocMethod.signal, LocMethod.ftm],
  };
}

/// Predict, then reveal (spec: "Your phone sees an AP at -70 dBm. How far
/// away is it?").
enum LocLessonStep { off, predict, revealed }

class LocationController extends ChangeNotifier {
  UnitSystem _units = UnitSystem.metric;

  /// Length units on screen. The floor stays in metres.
  UnitSystem get units => _units;

  void setUnits(UnitSystem u) {
    if (u == _units) return;
    _units = u;
    notifyListeners();
  }

  LocationController() {
    _recompute();
  }

  LocSettings _settings = const LocSettings();
  LocView _view = LocView.both;
  LocLessonStep _lesson = LocLessonStep.off;
  late LocRun _run;

  // ── Read side ─────────────────────────────────────────────────────────────

  LocSettings get settings => _settings;
  LocRun get run => _run;
  LocView get view => _view;
  LocLessonStep get lesson => _lesson;
  int get apCount => _settings.aps.length;
  LocPoint get device => _settings.device;

  /// The one-sigma distance factor at the current sigma and n.
  double get errorFactor =>
      locErrorFactor(_settings.sigmaDb, _settings.exponent);

  /// The lesson's model distance for -70 dBm at the current n.
  double get lessonDistanceM =>
      locDistanceFromRssi(kLocLessonRssiDbm, n: _settings.exponent);

  // ── Recompute ─────────────────────────────────────────────────────────────

  void _recompute() => _run = runLocation(_settings);

  void _apply(LocSettings s) {
    _settings = s;
    _recompute();
    notifyListeners();
  }

  // ── Inputs ────────────────────────────────────────────────────────────────

  set view(LocView v) {
    if (v == _view) return;
    _view = v;
    notifyListeners();
  }

  /// Signal strength, timing, both, wrapping (presenter Tab and M).
  void nextView() => view = LocView.values[(_view.index + 1) % 3];

  /// Moves the device to [p], held on the floor and snapped to 0.1 m.
  set device(LocPoint p) {
    final LocPoint q = (
      x: ((p.x * 10).round() / 10).clamp(0.0, kLocFloorWidthM),
      y: ((p.y * 10).round() / 10).clamp(0.0, kLocFloorDepthM),
    );
    if (q == _settings.device) return;
    _apply(_settings.copyWith(device: q));
  }

  set exponent(double v) {
    final double n = ((v * 10).round() / 10).clamp(
      kLocMinExponent,
      kLocMaxExponent,
    );
    if (n == _settings.exponent) return;
    _apply(_settings.copyWith(exponent: n));
  }

  set sigmaDb(double v) {
    final double s = ((v * 2).round() / 2).clamp(0.0, kLocMaxSigmaDb);
    if (s == _settings.sigmaDb) return;
    _apply(_settings.copyWith(sigmaDb: s));
  }

  /// Presenter Up and Down: sigma 1 dB at a time.
  void nudgeSigma(int dir) => sigmaDb = _settings.sigmaDb + dir.sign;

  set ftmErrorM(double v) {
    final double e = ((v * 10).round() / 10).clamp(
      kLocMinFtmErrorM,
      kLocMaxFtmErrorM,
    );
    if (e == _settings.ftmErrorM) return;
    _apply(_settings.copyWith(ftmErrorM: e));
  }

  set blockedBiasM(double v) {
    final double b = ((v * 2).round() / 2).clamp(0.0, kLocMaxBlockedBiasM);
    if (b == _settings.blockedBiasM) return;
    _apply(_settings.copyWith(blockedBiasM: b));
  }

  bool isBlocked(int ap) => _settings.isBlocked(ap);

  int get blockedCount =>
      <int>[for (int i = 0; i < apCount; i++) i].where(isBlocked).length;

  void toggleBlocked(int ap) {
    if (ap < 0 || ap >= apCount) return;
    final List<bool> b = List<bool>.generate(apCount, isBlocked);
    b[ap] = !b[ap];
    _apply(_settings.copyWith(blocked: List<bool>.unmodifiable(b)));
  }

  set apCount(int n) {
    final int c = n.clamp(kLocMinAps, kLocMaxAps);
    if (c == apCount) return;
    _apply(
      _settings.copyWith(
        aps: defaultLocAps(c),
        blocked: List<bool>.unmodifiable(List<bool>.generate(c, isBlocked)),
      ),
    );
  }

  /// Every measurement again with fresh draws (presenter Space).
  void resample() => _apply(_settings.copyWith(seed: _settings.seed + 1));

  // ── Lesson ────────────────────────────────────────────────────────────────

  void nextReveal() {
    _lesson = switch (_lesson) {
      LocLessonStep.off => LocLessonStep.predict,
      LocLessonStep.predict => LocLessonStep.revealed,
      LocLessonStep.revealed => LocLessonStep.off,
    };
    notifyListeners();
  }

  void endLesson() {
    if (_lesson == LocLessonStep.off) return;
    _lesson = LocLessonStep.off;
    notifyListeners();
  }

  // ── Reset ─────────────────────────────────────────────────────────────────

  /// Everything back to how the tool opens (presenter R).
  void reset() {
    _settings = const LocSettings();
    _view = LocView.both;
    _lesson = LocLessonStep.off;
    _recompute();
    notifyListeners();
  }

  /// Tab switches the method while no control has keyboard focus (the
  /// presenter's own key node, which holds every control below it, is
  /// focused). Once a control has focus, Tab and Shift+Tab move focus as
  /// usual, so the controls stay reachable by keyboard.
  void _tab() {
    final FocusNode? f = FocusManager.instance.primaryFocus;
    final bool shift = HardwareKeyboard.instance.isShiftPressed;
    if (f == null || f.children.isNotEmpty) {
      if (shift) {
        f?.previousFocus();
      } else {
        nextView();
      }
      return;
    }
    if (shift) {
      f.previousFocus();
    } else {
      f.nextFocus();
    }
  }

  /// Presenter keys (spec 00 and 33): Space re-samples, Tab switches the
  /// method, R resets, Up and Down move the shadowing sigma 1 dB, M also
  /// switches the method, B blocks or clears AP 1's direct path, P steps the
  /// predict-then-reveal question.
  PresenterActions get presenterActions => PresenterActions(
    playPause: resample,
    reset: reset,
    sliderDown: () => nudgeSigma(-1),
    sliderUp: () => nudgeSigma(1),
    sliderLabel: 'Shadowing sigma',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.tab,
        keyLabel: 'Tab',
        description:
            'Signal strength, timing, both (Shift+Tab moves into the '
            'controls)',
        onPressed: _tab,
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyM,
        keyLabel: 'M',
        description: 'Signal strength, timing, both',
        onPressed: nextView,
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyB,
        keyLabel: 'B',
        description: "Block or clear AP 1's direct path",
        onPressed: () => toggleBlocked(0),
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyP,
        keyLabel: 'P',
        description: 'Predict, then reveal: the -70 dBm question',
        onPressed: nextReveal,
      ),
    ],
  );

  // ── Copy ──────────────────────────────────────────────────────────────────

  String copyText() {
    final LocSettings s = _settings;
    final (double lo, double hi) = locOneSigmaRange(
      locWorkedDistanceM(_units),
      s.sigmaDb,
      s.exponent,
    );
    final StringBuffer b = StringBuffer()
      ..writeln(
        'Where Am I? Signal strength vs round-trip timing (WLAN Pros '
        'Toolbox, teaching model)',
      )
      ..writeln(
        'Floor ${LengthFormat(_units).dist(kLocFloorWidthM, decimals: 0)} x '
        '${LengthFormat(_units).dist(kLocFloorDepthM, decimals: 0)}, '
        '$apCount APs, device at '
        '${fmtM(s.device.x, _units)}, ${fmtM(s.device.y, _units)}',
      )
      ..writeln(
        'Signal strength: path-loss exponent n = '
        '${s.exponent.toStringAsFixed(1)}, shadowing sigma '
        '${s.sigmaDb.toStringAsFixed(1)} dB (illustrative), each AP radiating '
        '${kLocApPowerDbm.toStringAsFixed(0)} dBm (illustrative)',
      )
      ..writeln(
        'One-sigma distance factor 10^(sigma / 10n) = x'
        '${errorFactor.toStringAsFixed(3)}: a device '
        '${LengthFormat(_units).dist(locWorkedDistanceM(_units), decimals: 0)} '
        'away reads ${fmtM(lo, _units)} to ${fmtM(hi, _units)}',
      )
      ..writeln(
        'FTM (fine timing measurement) error '
        '${fmtM(s.ftmErrorM, _units)}, one standard deviation '
        '(vendor-documented ${locVendorRange(_units)}); ${blockedCount == 0 ? 'no direct path blocked' : '$blockedCount blocked, each reading ${fmtM(s.blockedBiasM, _units)} long (illustrative)'}',
      );
    for (int i = 0; i < apCount; i++) {
      final LocApReading a = _run.drawn[i];
      b.writeln(
        '  AP ${i + 1}: true ${fmtM(a.trueDistanceM, _units)}; signal '
        '${fmtDbm(a.rssiDbm)} reads ${fmtM(a.signalDistanceM, _units)} '
        '(${fmtSignedM(a.errorFor(LocMethod.signal), _units)}); timing reads '
        '${fmtM(a.ftmDistanceM, _units)} (${fmtSignedM(a.errorFor(LocMethod.ftm), _units)})'
        '${isBlocked(i) ? ', direct path blocked' : ''}',
      );
    }
    for (final LocMethod m in LocMethod.values) {
      final LocMethodResult r = _run.result(m);
      b.writeln(
        '${m == LocMethod.signal ? 'Signal strength' : 'FTM timing'}: '
        'position error ${r.positionErrorM == null ? 'no fix' : fmtM(r.positionErrorM!, _units)}, '
        'spread radius over $kLocTrials repeats ${fmtM(r.spreadRadiusM, _units)}',
      );
    }
    return b.toString().trimRight();
  }
}

/// "12.3 m" / "40.4 ft".
String fmtM(double v, [UnitSystem u = UnitSystem.metric]) =>
    LengthFormat(u).dist(v, decimals: 1, keepZeros: true);

/// "+1.2 m" / "-0.4 m" (ASCII hyphen); feet in imperial.
String fmtSignedM(double v, [UnitSystem u = UnitSystem.metric]) =>
    '${v >= 0 ? '+' : '-'}${fmtM(v.abs(), u)}';

/// The vendor's documented FTM accuracy, "1 to 2 m", in [u].
String locVendorRange(UnitSystem u) =>
    u.isMetric ? '1 to 2 m' : '3.3 to 6.6 ft';

/// The worked example's distance, metres: 10 m, or 30 ft.
double locWorkedDistanceM(UnitSystem u) =>
    u.isMetric ? 10 : LengthUnits.feetToMetres(30);

/// "-61.2 dBm".
String fmtDbm(double v) => '${v.toStringAsFixed(1)} dBm';
