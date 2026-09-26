// State for the Wi-Fi Classroom Survey Walk (survey-walk).
//
// One ChangeNotifier holds every input, the computed walk and the playback
// position, so the two halves of the screen stay independent widgets:
// SurveyWalkStage (floor, channel strip, signal) and SurveyWalkControls
// (inputs and readouts) each listen to this one object, and the presenter
// layout places them side by side over the same controller (spec 00).
//
// All survey math lives in lib/services/wifi_lab/survey_walk_engine.dart.
// The walk is computed whole whenever an input changes, and playback only
// moves a cursor through it, so what the student sees is always the same
// deterministic walk.
//
// THE CLOCK is a Ticker built here, not from a widget's TickerProvider: a
// route under the presenter route is muted, and the walk must keep going
// when the presenter layout opens over the phone screen.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../services/wifi_lab/survey_walk_engine.dart';
import '../../../widgets/presenter/presenter_actions.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kSurveyWalkToolId = 'survey-walk';

/// Walk time per real second.
enum SurveyPlaySpeed {
  x1('1x (walking pace)', 1),
  x2('2x', 2),
  x5('5x', 5),
  x10('10x', 10);

  const SurveyPlaySpeed(this.label, this.factor);

  final String label;
  final double factor;
}

/// Seconds moved by one press of Step.
const double kSurveyStepSeconds = 1.0;

/// Pace change per Up or Down key, m/s.
const double kPaceNudge = 0.1;

/// The student's answer to the opening question.
enum SurveyPrediction { matters, doesNotMatter }

/// The channel shown by default: 36, where AP 2 lives.
const SurveyChannel kDefaultShownChannel = SurveyChannel(RoamBand.b5, 36);

class SurveyWalkController extends ChangeNotifier {
  SurveyWalkController({SurveyWalkConfig? initial})
    : _config = initial ?? SurveyWalkConfig() {
    _result = simulateSurveyWalk(_config);
    _shown = _defaultShown();
    _ticker = Ticker(_onTick, debugLabel: 'survey-walk');
  }

  SurveyWalkConfig _config;
  late SurveyWalkResult _result;
  late final Ticker _ticker;

  double _timeS = 0;
  bool _playing = false;
  Duration _lastElapsed = Duration.zero;
  SurveyPlaySpeed _speed = SurveyPlaySpeed.x2;

  /// The channel whose dots are shown, or null for all channels.
  SurveyChannel? _shown;
  bool _showSignal = false;
  SurveyPrediction? _prediction;
  bool _revealed = false;

  /// Waypoints of a path being drawn, or null when not drawing.
  List<FloorPoint>? _drawing;

  // ── Read side ─────────────────────────────────────────────────────────────

  SurveyWalkConfig get config => _config;
  SurveyWalkResult get result => _result;
  bool get playing => _playing;
  SurveyPlaySpeed get speed => _speed;
  double get timeS => _timeS;
  bool get atEnd => _timeS >= _result.durationS - 1e-9;
  bool get atStart => _timeS <= 0;

  SurveyChannel? get shownChannel => _shown;

  /// Index of the shown channel in the result, or null (all).
  int? get shownIndex {
    final SurveyChannel? s = _shown;
    if (s == null) return null;
    final int i = _result.indexOf(s);
    return i < 0 ? null : i;
  }

  bool get showSignal => _showSignal;
  SurveyPrediction? get prediction => _prediction;
  bool get revealed => _revealed;

  SurveyPathPreset get pathPreset => SurveyPathPreset.matching(_config.path);

  bool get drawing => _drawing != null;
  List<FloorPoint> get drawnPoints => _drawing ?? const <FloorPoint>[];

  ({bool available, String? reason}) get hybrid =>
      hybridAvailability(_config.scanner);

  /// Walker position now, meters along the path.
  double get walkerS => _result.plan.sAt(_timeS);

  // ── Transport ─────────────────────────────────────────────────────────────

  void togglePlay() {
    if (drawing) return;
    if (_playing) {
      _pause();
    } else {
      if (atEnd) _timeS = 0;
      _playing = true;
      _lastElapsed = Duration.zero;
      _ticker.start();
    }
    notifyListeners();
  }

  void _pause() {
    _playing = false;
    if (_ticker.isActive) _ticker.stop();
  }

  /// Pause without toggling (app backgrounded).
  void pause() {
    if (!_playing) return;
    _pause();
    notifyListeners();
  }

  void step() {
    if (drawing) return;
    _pause();
    _timeS = math.min(_result.durationS, _timeS + kSurveyStepSeconds);
    _checkReveal();
    notifyListeners();
  }

  void restart() {
    _pause();
    _timeS = 0;
    notifyListeners();
  }

  void seek(double seconds) {
    _pause();
    _timeS = seconds.clamp(0.0, _result.durationS);
    _checkReveal();
    notifyListeners();
  }

  set speed(SurveyPlaySpeed s) {
    if (s == _speed) return;
    _speed = s;
    notifyListeners();
  }

  void _onTick(Duration elapsed) {
    final double dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    _timeS += math.min(dt, 0.5) * _speed.factor;
    if (_timeS >= _result.durationS) {
      _timeS = _result.durationS;
      _pause();
    }
    _checkReveal();
    notifyListeners();
  }

  /// The reveal comes after the first complete walk.
  void _checkReveal() {
    if (!_revealed && atEnd) _revealed = true;
  }

  // ── Predict, then reveal ──────────────────────────────────────────────────

  set prediction(SurveyPrediction? p) {
    if (p == _prediction) return;
    _prediction = p;
    notifyListeners();
  }

  void reveal() {
    if (_revealed) return;
    _revealed = true;
    notifyListeners();
  }

  void askAgain() {
    _prediction = null;
    _revealed = false;
    notifyListeners();
  }

  // ── Inputs ────────────────────────────────────────────────────────────────

  void _apply(SurveyWalkConfig next, {bool resetTime = false}) {
    if (next == _config) return;
    _config = next;
    _result = simulateSurveyWalk(next);
    if (shownIndex == null && _shown != null) _shown = _defaultShown();
    if (resetTime) {
      _pause();
      _timeS = 0;
    } else {
      _timeS = math.min(_timeS, _result.durationS);
    }
    notifyListeners();
  }

  SurveyChannel? _defaultShown() {
    if (_result.indexOf(kDefaultShownChannel) >= 0) {
      return kDefaultShownChannel;
    }
    return _result.channels.isEmpty ? null : _result.channels.first;
  }

  set shownChannel(SurveyChannel? c) {
    if (c == _shown) return;
    _shown = c;
    notifyListeners();
  }

  set showSignal(bool v) {
    if (v == _showSignal) return;
    _showSignal = v;
    notifyListeners();
  }

  /// Refuses hybrid when it is not available (the controls say why).
  set surveyType(SurveyType t) {
    if (t == SurveyType.hybrid && !hybrid.available) return;
    _apply(_config.copyWith(surveyType: t));
  }

  set capture(CaptureMethod m) =>
      _apply(_config.copyWith(capture: m), resetTime: true);

  set timestamp(TimestampMode m) => _apply(_config.copyWith(timestamp: m));

  void _scanner(ScannerConfig s) {
    // Hybrid that is no longer possible falls back to passive.
    SurveyType t = _config.surveyType;
    if (t == SurveyType.hybrid && !hybridAvailability(s).available) {
      t = SurveyType.passive;
    }
    _apply(_config.copyWith(scanner: s, surveyType: t));
  }

  /// A device preset (1 to 4 NICs) keeps the channel set and dwell.
  ScannerConfig get _explicit => _config.scanner;

  set channelSet(ChannelSetPreset p) =>
      _scanner(_explicit.copyWith(channelSet: p));

  set customCount(int n) => _scanner(
    _explicit.copyWith(
      channelSet: ChannelSetPreset.custom,
      customCount: n.clamp(1, kAllUsChannels.length),
    ),
  );

  set dwellMs(double v) => _scanner(
    _explicit.copyWith(dwellMs: v.roundToDouble().clamp(kDwellMin, kDwellMax)),
  );

  set switchMs(double v) => _scanner(
    _explicit.copyWith(switchMs: v.roundToDouble().clamp(0, kSwitchMax)),
  );

  set radios(int n) =>
      _scanner(_explicit.copyWith(radios: n.clamp(kMinRadios, kMaxRadios)));

  set algorithm(HoppingAlgorithm a) =>
      _scanner(_explicit.copyWith(algorithm: a));

  set priorityEvery(int k) => _scanner(
    _explicit.copyWith(
      priorityEvery: k.clamp(kPriorityEveryMin, kPriorityEveryMax),
    ),
  );

  void togglePriority(SurveyChannel c) {
    final List<SurveyChannel> p = List<SurveyChannel>.of(
      _config.scanner.priority,
    );
    if (!p.remove(c)) p.add(c);
    _scanner(_explicit.copyWith(priority: p));
  }

  set paceMps(double v) => _apply(
    _config.copyWith(
      paceMps: ((v * 10).round() / 10).clamp(kSurveyPaceMin, kSurveyPaceMax),
    ),
  );

  /// Pace one notch up ([dir] > 0) or down.
  void nudgePace(int dir) => paceMps = _config.paceMps + dir.sign * kPaceNudge;

  set guessRangeM(double v) => _apply(
    _config.copyWith(
      guessRangeM: v.roundToDouble().clamp(kGuessRangeMin, kGuessRangeMax),
    ),
  );

  set doorPause(bool v) => _apply(_config.copyWith(doorPause: v));

  set doorPauseS(double v) => _apply(
    _config.copyWith(
      doorPauseS: v.roundToDouble().clamp(kDoorPauseMin, kDoorPauseMax),
    ),
  );

  set stopSpacingM(double v) => _apply(
    _config.copyWith(
      stopSpacingM: v.roundToDouble().clamp(kStopSpacingMin, kStopSpacingMax),
    ),
    resetTime: true,
  );

  /// A new fading pattern (next seed).
  void newFading() => _apply(_config.copyWith(seed: _config.seed + 1));

  /// Presenter keys (spec 00 and 26): Space plays or pauses, Right steps
  /// 1 s, R restarts the walk, Up and Down change the pace 0.1 m/s.
  PresenterActions get presenterActions => PresenterActions(
    playPause: togglePlay,
    step: () {
      if (!atEnd) step();
    },
    reset: restart,
    sliderDown: () => nudgePace(-1),
    sliderUp: () => nudgePace(1),
    sliderLabel: 'Walking pace',
  );

  // ── Path ──────────────────────────────────────────────────────────────────

  set pathPreset(SurveyPathPreset p) {
    final List<FloorPoint>? pts = p.points;
    if (pts == null) {
      startDrawing();
      return;
    }
    _drawing = null;
    _apply(_config.copyWith(path: pts), resetTime: true);
    notifyListeners();
  }

  void startDrawing() {
    _pause();
    _drawing = <FloorPoint>[];
    notifyListeners();
  }

  void addWaypoint(FloorPoint p) {
    final List<FloorPoint>? d = _drawing;
    if (d == null) return;
    d.add(_snapToFloor(p));
    notifyListeners();
  }

  void undoWaypoint() {
    final List<FloorPoint>? d = _drawing;
    if (d == null || d.isEmpty) return;
    d.removeLast();
    notifyListeners();
  }

  bool get canFinishDrawing {
    final List<FloorPoint>? d = _drawing;
    if (d == null || d.length < 2) return false;
    // The first segment holds the door, so it must have length.
    final double dx = d[1].x - d[0].x;
    final double dy = d[1].y - d[0].y;
    return pathLengthM(d) >= 2 && dx * dx + dy * dy >= 1;
  }

  void finishDrawing() {
    if (!canFinishDrawing) return;
    final List<FloorPoint> pts = List<FloorPoint>.unmodifiable(_drawing!);
    _drawing = null;
    _apply(_config.copyWith(path: pts), resetTime: true);
    notifyListeners();
  }

  void cancelDrawing() {
    if (_drawing == null) return;
    _drawing = null;
    notifyListeners();
  }

  static FloorPoint _snapToFloor(FloorPoint p) => (
    x: ((p.x * 2).round() / 2).clamp(0.0, kFloorWidthM),
    y: ((p.y * 2).round() / 2).clamp(0.0, kFloorDepthM),
  );

  // ── Copy ──────────────────────────────────────────────────────────────────

  String copyText() {
    final SurveyWalkConfig c = _config;
    final SurveyWalkResult r = _result;
    final ScannerConfig s = c.scanner;
    final StringBuffer b = StringBuffer()
      ..writeln('Survey Walk (WLAN Pros Toolbox, teaching model)')
      ..writeln(
        '${c.effectiveType.label} survey, ${c.capture.label.toLowerCase()} '
        'capture, ${c.timestamp.label.toLowerCase()} timestamps',
      )
      ..writeln(
        'Device: ${nicPresetLabel(s.radios)}, '
        '${r.schedule?.channels.length ?? 0} channels scanned, '
        '${fmtMs(s.dwellMs)} dwell, ${s.algorithm.label.toLowerCase()}',
      );
    b
      ..writeln(
        'Path: ${pathPreset.label}, ${r.plan.lengthM.toStringAsFixed(0)} m '
        'at ${c.paceMps.toStringAsFixed(1)} m/s, '
        '${r.durationS.toStringAsFixed(1)} s'
        '${c.doorPause ? ', ${c.doorPauseS.toStringAsFixed(0)} s pause at the door' : ''}',
      )
      ..writeln(
        'Guess range ${c.guessRangeM.toStringAsFixed(0)} m. Rule 4: longest '
        'allowed revisit ${fmtS(r.maxAllowedRevisit)}, longest revisit '
        '${fmtS(r.ruleRevisitS)}: ${r.rule4Pass ? 'pass' : 'fail'}',
      );
    final Map<RoamBand, double>? bands = r.schedule?.bandRevisitS;
    if (bands != null) {
      for (final MapEntry<RoamBand, double> e in bands.entries) {
        b.writeln(
          '  ${e.key.label}: revisit ${fmtS(e.value)}, spacing '
          '${fmtM(sampleSpacingM(c.paceMps, e.value))}',
        );
      }
    }
    final double? gap = r.largestGapM;
    b
      ..writeln('Largest gap: ${gap == null ? 'n/a' : fmtM(gap)}')
      ..writeln('Largest position error: ${fmtM(r.maxErrorM)}');
    return b.toString().trimRight();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

/// "7.0 s", "1.21 s" (two decimals only when the second one is not zero),
/// or "750 ms" under a second.
String fmtS(double s) {
  if (s.isInfinite) return 'never';
  if (s < 1) return '${(s * 1000).round()} ms';
  final bool one = (s * 10).roundToDouble() == (s * 100).roundToDouble() / 10;
  return '${s.toStringAsFixed(one || s >= 10 ? 1 : 2)} s';
}

/// "250 ms".
String fmtMs(double ms) => '${ms.round()} ms';

/// "9.8 m".
String fmtM(double m) => '${m.toStringAsFixed(1)} m';
