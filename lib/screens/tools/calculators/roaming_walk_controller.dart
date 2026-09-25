// State for the Wi-Fi Lab Roaming Walk (roaming-walk).
//
// One ChangeNotifier holds every input, the computed walk and the playback
// position, so the two halves of the screen stay independent widgets:
// RoamingWalkStage (floor plan and RSSI plot) and RoamingWalkControls (inputs
// and readouts) each listen to this one object. The phone layout stacks them;
// a presenter layout can place them side by side without either knowing
// about the other (spec 00).
//
// All roaming math lives in lib/services/wifi_lab/roaming_walk_engine.dart.
// The walk is computed whole whenever an input changes (a few hundred
// samples), and playback only moves a cursor through it, so what the student
// sees is always the same deterministic walk.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../services/wifi_lab/roaming_walk_engine.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kRoamingWalkToolId = 'roaming-walk';

/// Walk time per real second.
enum RoamPlaySpeed {
  x1('1x (walking pace)', 1),
  x2('2x', 2),
  x5('5x', 5),
  x10('10x', 10);

  const RoamPlaySpeed(this.label, this.factor);

  final String label;
  final double factor;
}

/// Seconds moved by one press of Step.
const double kRoamStepSeconds = 1.0;

class RoamingWalkController extends ChangeNotifier {
  RoamingWalkController({
    required TickerProvider vsync,
    RoamWalkConfig? initial,
  }) : _config = initial ?? RoamWalkConfig() {
    _result = simulateRoamWalk(_config);
    _ticker = vsync.createTicker(_onTick);
  }

  RoamWalkConfig _config;
  late RoamWalkResult _result;
  late final Ticker _ticker;

  /// Walk time shown, seconds.
  double _timeS = 0;
  bool _playing = false;
  Duration _lastElapsed = Duration.zero;
  RoamPlaySpeed _speed = RoamPlaySpeed.x2;
  int _editingAp = 0;

  /// Waypoints of a path being drawn, or null when not drawing.
  List<FloorPoint>? _drawing;

  // ── Read side ─────────────────────────────────────────────────────────────

  RoamWalkConfig get config => _config;
  RoamWalkResult get result => _result;
  bool get playing => _playing;
  RoamPlaySpeed get speed => _speed;
  double get timeS => _timeS;

  /// The sample on screen.
  int get sample => math.min(
    _result.sampleCount - 1,
    (_timeS / kRoamSampleSeconds + 1e-9).floor(),
  );

  bool get atEnd => sample >= _result.sampleCount - 1;
  bool get atStart => _timeS <= 0;

  RoamTotals get totals => _result.totalsAt(sample);

  /// The preset the trigger and delta still match, or null (custom).
  ClientPreset? get preset =>
      ClientPreset.matching(_config.triggerDbm, _config.deltaDb);

  WalkPathPreset get pathPreset => WalkPathPreset.matching(_config.path);

  int get apCount => _config.aps.length;

  /// Which AP the position sliders move.
  int get editingAp => math.min(_editingAp, apCount - 1);

  bool get drawing => _drawing != null;
  List<FloorPoint> get drawnPoints => _drawing ?? const <FloorPoint>[];

  // ── Transport ─────────────────────────────────────────────────────────────

  void togglePlay() {
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
    _pause();
    _timeS = math.min(_result.durationS, _timeS + kRoamStepSeconds);
    notifyListeners();
  }

  void restart() {
    _pause();
    _timeS = 0;
    notifyListeners();
  }

  /// Moves the cursor to [seconds] (the scrub slider).
  void seek(double seconds) {
    _pause();
    _timeS = seconds.clamp(0.0, _result.durationS);
    notifyListeners();
  }

  set speed(RoamPlaySpeed s) {
    if (s == _speed) return;
    _speed = s;
    notifyListeners();
  }

  void _onTick(Duration elapsed) {
    final double dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    // A stalled frame cannot jump more than half a second of walk.
    _timeS += math.min(dt, 0.5) * _speed.factor;
    if (_timeS >= _result.durationS) {
      _timeS = _result.durationS;
      _pause();
    }
    notifyListeners();
  }

  // ── Inputs ────────────────────────────────────────────────────────────────

  void _apply(RoamWalkConfig next, {bool resetTime = false}) {
    if (next == _config) return;
    _config = next;
    _result = simulateRoamWalk(next);
    if (resetTime) {
      _pause();
      _timeS = 0;
    } else {
      _timeS = math.min(_timeS, _result.durationS);
    }
    notifyListeners();
  }

  void applyPreset(ClientPreset p) =>
      _apply(_config.copyWith(triggerDbm: p.triggerDbm, deltaDb: p.deltaDb));

  set triggerDbm(double v) =>
      _apply(_config.copyWith(triggerDbm: v.roundToDouble().clamp(-90, -55)));

  set deltaDb(double v) =>
      _apply(_config.copyWith(deltaDb: v.roundToDouble().clamp(0, 20)));

  set use11k(bool v) => _apply(_config.copyWith(use11k: v));
  set usePmkCaching(bool v) => _apply(_config.copyWith(usePmkCaching: v));
  set useFt(bool v) => _apply(_config.copyWith(useFt: v));

  set band(RoamBand b) => _apply(_config.copyWith(band: b));

  set eirpDbm(double v) =>
      _apply(_config.copyWith(eirpDbm: v.roundToDouble().clamp(5, 30)));

  set pathLossExponent(double v) => _apply(
    _config.copyWith(pathLossExponent: ((v * 10).round() / 10).clamp(2.0, 4.0)),
  );

  set shadowSigmaDb(double v) => _apply(
    _config.copyWith(shadowSigmaDb: ((v * 2).round() / 2).clamp(0.0, 6.0)),
  );

  /// A new random shadowing pattern (next seed).
  void newShadowing() => _apply(_config.copyWith(seed: _config.seed + 1));

  set timing(RoamTiming t) => _apply(_config.copyWith(timing: t));

  /// Changing the count spaces the APs evenly again.
  set apCount(int n) {
    final int c = n.clamp(kMinAps, kMaxAps);
    if (c == apCount) return;
    _apply(_config.copyWith(aps: defaultApLayout(c)));
  }

  set editingAp(int i) {
    final int c = i.clamp(0, apCount - 1);
    if (c == _editingAp) return;
    _editingAp = c;
    notifyListeners();
  }

  /// Moves AP [i] to [p], kept on the floor, positions rounded to 0.5 m.
  void moveAp(int i, FloorPoint p) {
    final List<FloorPoint> aps = List<FloorPoint>.of(_config.aps);
    aps[i] = _snapToFloor(p);
    _editingAp = i;
    _apply(_config.copyWith(aps: aps));
  }

  void setApX(double x) =>
      moveAp(editingAp, (x: x, y: _config.aps[editingAp].y));

  void setApY(double y) =>
      moveAp(editingAp, (x: _config.aps[editingAp].x, y: y));

  /// Index of the AP within [radiusM] of [p], nearest first, or null.
  int? apNear(FloorPoint p, double radiusM) {
    int? best;
    double bestD = radiusM;
    for (int i = 0; i < apCount; i++) {
      final FloorPoint a = _config.aps[i];
      final double d = math.sqrt(
        (a.x - p.x) * (a.x - p.x) + (a.y - p.y) * (a.y - p.y),
      );
      if (d <= bestD) {
        best = i;
        bestD = d;
      }
    }
    return best;
  }

  set pathPreset(WalkPathPreset p) {
    final List<FloorPoint>? pts = p.points;
    if (pts == null) {
      startDrawing();
      return;
    }
    _drawing = null;
    _apply(_config.copyWith(path: pts), resetTime: true);
    notifyListeners();
  }

  // ── Drawing a path ────────────────────────────────────────────────────────

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
    return d != null && d.length >= 2 && pathLengthM(d) >= 1;
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
    final RoamWalkConfig c = _config;
    final RoamTotals t = _result.totals;
    final ClientPreset? p = preset;
    final StringBuffer b = StringBuffer()
      ..writeln('Roaming Walk (WLAN Pros Toolbox, teaching model)')
      ..writeln(
        'Client: ${p?.label ?? 'Custom'}, trigger ${fmtDbm(c.triggerDbm)}, '
        'delta ${c.deltaDb.toStringAsFixed(0)} dB',
      )
      ..writeln(
        '${c.aps.length} APs, ${c.band.label}, EIRP '
        '${c.eirpDbm.toStringAsFixed(0)} dBm, n = '
        '${c.pathLossExponent.toStringAsFixed(1)}, shadowing '
        '${c.shadowSigmaDb.toStringAsFixed(1)} dB',
      )
      ..writeln(
        'Path: ${pathPreset.label}, '
        '${pathLengthM(c.path).toStringAsFixed(0)} m, '
        '${_result.durationS.toStringAsFixed(1)} s',
      )
      ..writeln(
        '802.11k ${c.use11k ? 'on' : 'off'}, PMK caching '
        '${c.usePmkCaching ? 'on' : 'off'}, FT ${c.useFt ? 'on' : 'off'}',
      )
      ..writeln('Whole walk:')
      ..writeln('  Roams: ${t.roams}')
      ..writeln(
        '  Ping-pongs: ${t.pingPongs}'
        '${t.pingPongs > 0 ? ' (ping-pong)' : ''}',
      )
      ..writeln(
        '  Time below -70 dBm: ${t.secondsBelowWeak.toStringAsFixed(1)} s'
        '${t.secondsBelowWeak > 0 ? ' (weak signal)' : ''}',
      )
      ..writeln('  Total roam gap: ${fmtMs(t.gapMs)}');
    for (final RoamEvent e in _result.events) {
      b.writeln(
        '  ${e.timeS.toStringAsFixed(1)} s: AP ${e.fromAp + 1} '
        '(${fmtDbm(e.fromRssiDbm)}) to AP ${e.toAp + 1} '
        '(${fmtDbm(e.toRssiDbm)}), gap ${fmtMs(e.gapMs)} = scan '
        '${fmtMs(e.cost.scanMs)} + ${e.cost.method.label} '
        '${fmtMs(e.cost.authMs)}${e.pingPong ? ', ping-pong' : ''}',
      );
    }
    return b.toString().trimRight();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

/// "-70.4 dBm" (ASCII hyphen, so copied text stays plain).
String fmtDbm(double v) => '${v.toStringAsFixed(1)} dBm';

/// "342 ms", or "1.20 s" past a second.
String fmtMs(double ms) =>
    ms >= 1000 ? '${(ms / 1000).toStringAsFixed(2)} s' : '${ms.round()} ms';
