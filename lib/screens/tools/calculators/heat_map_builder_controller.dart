// State for the Wi-Fi Classroom Heat Map Builder (heat-map-builder).
//
// One ChangeNotifier holds every input, the samples, the computed map and the
// lesson step, so the two halves of the screen stay independent widgets:
// HeatMapBuilderStage (the floor, the map and the spacing plot) and
// HeatMapBuilderControls (inputs, readouts and the worked example) each
// listen to this one object. The phone layout stacks them; the presenter
// layout places them side by side (spec 00).
//
// All math lives in lib/services/wifi_lab/heat_map_builder_engine.dart. The
// map is recomputed whole on every change (4,000 cells; under 30 ms with
// 1,000 samples), so there is no clock and nothing animates.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../services/wifi_lab/heat_map_builder_engine.dart';
import '../../../widgets/presenter/presenter_actions.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kHeatMapBuilderToolId = 'heat-map-builder';

/// Most samples the floor takes (a 1 m grid is 1,000).
const int kHmMaxSamples = 1200;

/// What the map shows.
enum HmView {
  estimate('Heat map'),
  truth('Truth'),
  error('Error map');

  const HmView(this.label);

  final String label;
}

/// What a tap on the floor does.
enum HmTapAction {
  add('Add a sample'),
  inspect('Inspect a cell');

  const HmTapAction(this.label);

  final String label;
}

/// Where the samples came from.
enum HmLayout {
  none('No samples'),
  custom('Your points'),
  grid('Grid'),
  walk('Corridor walk'),
  threeDots('Three dots');

  const HmLayout(this.label);

  final String label;
}

/// The predict-then-reveal lesson (spec: "Three dots can paint the whole
/// floor green. Should they?").
enum HmLessonStep {
  off,

  /// Three dots, 5 m guess range, extrapolation off: mostly white.
  predict,

  /// Guess range widened to 20 m with flat IDW: the whole floor is painted.
  widened,

  /// The hidden wall is revealed on the error map.
  wallRevealed,
}

class HeatMapBuilderController extends ChangeNotifier {
  HeatMapBuilderController({
    HmFloor? floor,
    this.interpolator = documentedHmInterpolator,
  }) : _floor = floor ?? HmFloor() {
    _truth = hmTruthGrid(_floor);
    _recompute();
  }

  /// How samples become cell values. The stage and controls never see the
  /// method, only its results, so a new method is swapped in here.
  final HmInterpolatorFactory interpolator;

  HmFloor _floor;
  late Float64List _truth;
  List<HmPoint> _points = const <HmPoint>[];
  HmLayout _layout = HmLayout.none;
  double _spacingM = 3;
  HmSettings _settings = const HmSettings();
  HmNoise _noise = const HmNoise();
  HmView _view = HmView.estimate;
  HmTapAction _tapAction = HmTapAction.add;
  HmPoint? _inspect;
  bool _wallRevealed = false;
  List<HmSpacingSeries>? _experiment;
  HmNoise? _experimentNoise;
  HmLessonStep _lesson = HmLessonStep.off;

  late List<HmSample> _samples;
  late HmMap _map;

  // ── Read side ─────────────────────────────────────────────────────────────

  HmFloor get floor => _floor;
  List<HmPoint> get points => _points;
  List<HmSample> get samples => _samples;
  HmMap get map => _map;
  HmLayout get layout => _layout;
  double get spacingM => _spacingM;
  HmSettings get settings => _settings;
  HmNoise get noise => _noise;
  HmView get view => _view;
  HmTapAction get tapAction => _tapAction;
  bool get wallRevealed => _wallRevealed;
  HmLessonStep get lesson => _lesson;
  int get apCount => _floor.aps.length;
  bool get hasSamples => _points.isNotEmpty;
  bool get atSampleLimit => _points.length >= kHmMaxSamples;

  /// The spacing experiment's result, or null until it has been run (or
  /// since an input it depends on changed).
  List<HmSpacingSeries>? get experiment => _experiment;

  /// The noise the experiment was run with.
  HmNoise? get experimentNoise => _experimentNoise;

  /// The inspected cell's center, or null.
  HmPoint? get inspectedCell {
    final HmPoint? p = _inspect;
    if (p == null) return null;
    final (int c, int r) = _map.cellOf(p);
    return _map.center(c, r);
  }

  /// How the inspected cell got its value, or null.
  HmCellEstimate? get inspection {
    final HmPoint? q = inspectedCell;
    if (q == null) return null;
    return interpolator(_floor, _samples, _settings).estimateAt(q);
  }

  /// The truth at the inspected cell, dBm, or null.
  double? get inspectedTruthDbm {
    final HmPoint? q = inspectedCell;
    return q == null ? null : _floor.truthDbm(q);
  }

  // ── Recompute ─────────────────────────────────────────────────────────────

  void _recompute() {
    _samples = takeHmSamples(_floor, _points, _noise);
    _map = buildHmMap(
      _floor,
      _samples,
      _settings,
      truth: _truth,
      interpolator: interpolator,
    );
  }

  void _changed({bool staleExperiment = false}) {
    _recompute();
    if (staleExperiment) {
      _experiment = null;
      _experimentNoise = null;
    }
    notifyListeners();
  }

  // ── Samples ───────────────────────────────────────────────────────────────

  static HmPoint _snap(HmFloor f, HmPoint p) => (
    x: ((p.x * 2).round() / 2).clamp(0.0, f.widthM),
    y: ((p.y * 2).round() / 2).clamp(0.0, f.depthM),
  );

  /// Adds a sample at [p] (snapped to 0.5 m). Returns false at the limit.
  bool addSample(HmPoint p) {
    if (atSampleLimit) return false;
    _points = List<HmPoint>.unmodifiable(<HmPoint>[
      ..._points,
      _snap(_floor, p),
    ]);
    _layout = HmLayout.custom;
    _changed();
    return true;
  }

  void undoSample() {
    if (_points.isEmpty) return;
    _points = List<HmPoint>.unmodifiable(
      _points.sublist(0, _points.length - 1),
    );
    _layout = _points.isEmpty ? HmLayout.none : HmLayout.custom;
    _changed();
  }

  void clearSamples() {
    if (_points.isEmpty && _lesson == HmLessonStep.off) return;
    _points = const <HmPoint>[];
    _layout = HmLayout.none;
    _inspect = null;
    _lesson = HmLessonStep.off;
    _changed();
  }

  void useGrid() {
    _points = List<HmPoint>.unmodifiable(hmGridPoints(_floor, _spacingM));
    _layout = HmLayout.grid;
    _changed();
  }

  void useWalk() {
    _points = List<HmPoint>.unmodifiable(hmWalkPoints(_floor, _spacingM));
    _layout = HmLayout.walk;
    _changed();
  }

  /// Grid and walk spacing; re-lays a grid or walk already on the floor.
  set spacingM(double v) {
    final double s = v.roundToDouble().clamp(kHmMinSpacingM, kHmMaxSpacingM);
    if (s == _spacingM) return;
    _spacingM = s;
    switch (_layout) {
      case HmLayout.grid:
        useGrid();
      case HmLayout.walk:
        useWalk();
      case HmLayout.none:
      case HmLayout.custom:
      case HmLayout.threeDots:
        notifyListeners();
    }
  }

  set tapAction(HmTapAction a) {
    if (a == _tapAction) return;
    _tapAction = a;
    notifyListeners();
  }

  /// A tap on the floor at [p]: adds a sample or inspects the cell.
  void tapFloor(HmPoint p) {
    if (!_floor.contains(p)) return;
    if (_tapAction == HmTapAction.add) {
      addSample(p);
    } else {
      inspect(p);
    }
  }

  void inspect(HmPoint? p) {
    _inspect = p == null
        ? null
        : (
            x: p.x.clamp(0.0, _floor.widthM - 1e-6),
            y: p.y.clamp(0.0, _floor.depthM - 1e-6),
          );
    notifyListeners();
  }

  /// Moves the inspected cell by whole cells (keyboard equivalent of a tap).
  void moveInspection(int dCol, int dRow) {
    final HmPoint p =
        inspectedCell ?? (x: _floor.widthM / 2, y: _floor.depthM / 2);
    inspect((
      x: p.x + dCol * _map.cellM,
      y: p.y + dRow * _map.cellM,
    ));
  }

  // ── Method ────────────────────────────────────────────────────────────────

  void _apply(HmSettings s) {
    if (s == _settings) return;
    _settings = s;
    _changed(staleExperiment: true);
  }

  set method(HmMethod m) => _apply(_settings.copyWith(method: m));

  set power(double v) => _apply(
    _settings.copyWith(
      power: ((v * 2).round() / 2).clamp(kHmMinPower, kHmMaxPower),
    ),
  );

  /// The next of p = 1, 2, 4, 6, wrapping (presenter key P).
  void nextPower() {
    const List<double> steps = <double>[1, 2, 4, 6];
    final double p = _settings.power;
    method = HmMethod.idw;
    power = steps.firstWhere((double s) => s > p, orElse: () => steps.first);
  }

  set domain(HmDomain d) => _apply(_settings.copyWith(domain: d));

  set guessRangeM(double v) => _apply(
    _settings.copyWith(
      guessRangeM: v.roundToDouble().clamp(
        kHmMinGuessRangeM,
        kHmMaxGuessRangeM,
      ),
    ),
  );

  void nudgeGuessRange(int dir) =>
      guessRangeM = _settings.guessRangeM + dir.sign;

  set extrapolation(HmExtrapolation x) =>
      _apply(_settings.copyWith(extrapolation: x));

  // ── Noise ─────────────────────────────────────────────────────────────────

  set sigmaDb(double v) {
    final HmNoise n = _noise.copyWith(
      sigmaDb: ((v * 2).round() / 2).clamp(0.0, kHmMaxSigmaDb),
    );
    if (n == _noise) return;
    _noise = n;
    _changed(staleExperiment: true);
  }

  set averaging(int v) {
    final HmNoise n = _noise.copyWith(averaging: v.clamp(1, kHmMaxAveraging));
    if (n == _noise) return;
    _noise = n;
    _changed(staleExperiment: true);
  }

  /// Takes every sample again with fresh noise (presenter Space).
  void rerun() {
    _noise = _noise.copyWith(seed: _noise.seed + 1);
    _changed(staleExperiment: true);
  }

  // ── Floor ─────────────────────────────────────────────────────────────────

  void _setFloor(HmFloor f) {
    _floor = f;
    _truth = hmTruthGrid(f);
    if (_layout == HmLayout.threeDots) {
      _points = List<HmPoint>.unmodifiable(hmThreeDotPoints(f));
    }
    _changed(staleExperiment: true);
  }

  set apCount(int n) {
    final int c = n.clamp(kHmMinAps, kHmMaxAps);
    if (c == apCount) return;
    _setFloor(_floor.copyWith(aps: defaultHmAps(c)));
  }

  set pathLossExponent(double v) {
    final double n = ((v * 10).round() / 10).clamp(2.0, 4.0);
    if (n == _floor.pathLossExponent) return;
    _setFloor(_floor.copyWith(pathLossExponent: n));
  }

  // ── View ──────────────────────────────────────────────────────────────────

  set view(HmView v) {
    if (v == _view) return;
    _view = v;
    notifyListeners();
  }

  void nextView() => view = HmView.values[(_view.index + 1) % 3];

  set wallRevealed(bool v) {
    if (v == _wallRevealed) return;
    _wallRevealed = v;
    notifyListeners();
  }

  // ── Experiment ────────────────────────────────────────────────────────────

  void runExperiment() {
    _experiment = runHmSpacingExperiment(
      _floor,
      _settings,
      _noise,
      interpolator: interpolator,
    );
    _experimentNoise = _noise;
    notifyListeners();
  }

  void closeExperiment() {
    if (_experiment == null) return;
    _experiment = null;
    _experimentNoise = null;
    notifyListeners();
  }

  // ── Lesson: predict, then reveal ─────────────────────────────────────────

  void startLesson() {
    _points = List<HmPoint>.unmodifiable(hmThreeDotPoints(_floor));
    _layout = HmLayout.threeDots;
    _settings = _settings.copyWith(
      method: HmMethod.idw,
      guessRangeM: kHmDefaultGuessRangeM,
      extrapolation: HmExtrapolation.off,
    );
    _view = HmView.estimate;
    _wallRevealed = false;
    _inspect = null;
    _lesson = HmLessonStep.predict;
    _changed(staleExperiment: true);
  }

  /// The next reveal: widen the guess range, then show the hidden wall.
  void nextReveal() {
    switch (_lesson) {
      case HmLessonStep.off:
        startLesson();
      case HmLessonStep.predict:
        _settings = _settings.copyWith(
          guessRangeM: kHmMaxGuessRangeM,
          extrapolation: HmExtrapolation.flatIdw,
        );
        _lesson = HmLessonStep.widened;
        _changed(staleExperiment: true);
      case HmLessonStep.widened:
        _wallRevealed = true;
        _view = HmView.error;
        _lesson = HmLessonStep.wallRevealed;
        notifyListeners();
      case HmLessonStep.wallRevealed:
        endLesson();
    }
  }

  void endLesson() {
    if (_lesson == HmLessonStep.off) return;
    _lesson = HmLessonStep.off;
    notifyListeners();
  }

  // ── Reset ─────────────────────────────────────────────────────────────────

  /// Everything back to how the tool opens (presenter R).
  void reset() {
    _floor = HmFloor();
    _truth = hmTruthGrid(_floor);
    _points = const <HmPoint>[];
    _layout = HmLayout.none;
    _spacingM = 3;
    _settings = const HmSettings();
    _noise = const HmNoise();
    _view = HmView.estimate;
    _tapAction = HmTapAction.add;
    _inspect = null;
    _wallRevealed = false;
    _lesson = HmLessonStep.off;
    _changed(staleExperiment: true);
  }

  /// Presenter keys (spec 00 and 27): Space takes the samples again with new
  /// noise, R resets, Up and Down move the guess range 1 m, P steps the power
  /// through 1, 2, 4 and 6, E switches heat map, truth and error map, W shows
  /// or hides the hidden wall, N is the next reveal of the lesson.
  PresenterActions get presenterActions => PresenterActions(
    playPause: rerun,
    reset: reset,
    sliderDown: () => nudgeGuessRange(-1),
    sliderUp: () => nudgeGuessRange(1),
    sliderLabel: 'Guess range',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyP,
        keyLabel: 'P',
        description: 'Next power (1, 2, 4, 6)',
        onPressed: nextPower,
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyE,
        keyLabel: 'E',
        description: 'Heat map, truth, error map',
        onPressed: nextView,
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyW,
        keyLabel: 'W',
        description: 'Show or hide the hidden wall',
        onPressed: () => wallRevealed = !_wallRevealed,
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyN,
        keyLabel: 'N',
        description: 'Next step of the three-dots lesson',
        onPressed: nextReveal,
      ),
    ],
  );

  // ── Copy ──────────────────────────────────────────────────────────────────

  String copyText() {
    final HmSettings s = _settings;
    final HmMap m = _map;
    final StringBuffer b = StringBuffer()
      ..writeln('Heat Map Builder (WLAN Pros Toolbox, teaching model)')
      ..writeln(
        'Floor ${_floor.widthM.toStringAsFixed(0)} m x '
        '${_floor.depthM.toStringAsFixed(0)} m, $apCount '
        '${apCount == 1 ? 'AP' : 'APs'}, n = '
        '${_floor.pathLossExponent.toStringAsFixed(1)}, each AP radiating '
        '${_floor.eirpDbm.toStringAsFixed(0)} dBm',
      )
      ..writeln(
        'Samples: ${_points.length} (${_layout.label}'
        '${_layout == HmLayout.grid || _layout == HmLayout.walk ? ', every ${_spacingM.toStringAsFixed(0)} m' : ''})',
      )
      ..writeln(
        'Method: ${s.method == HmMethod.idw ? 'IDW (inverse distance weighting), power ${fmtPower(s.power)}' : 'nearest neighbor'}, '
        'averaged in ${s.domain == HmDomain.db ? 'dB' : 'milliwatts'}',
      )
      ..writeln(
        'Guess range ${s.guessRangeM.toStringAsFixed(0)} m, extrapolation '
        '${s.extrapolation.label}',
      )
      ..writeln(
        'Noise ${_noise.sigmaDb.toStringAsFixed(1)} dB (illustrative), '
        '${_noise.averaging} per point',
      )
      ..writeln(
        'RMSE (root mean square error): '
        '${m.rmseDb == null ? 'no data' : '${m.rmseDb!.toStringAsFixed(1)} dB'}',
      )
      ..writeln(
        'Largest error: '
        '${m.maxErrorDb == null ? 'no data' : fmtSignedDb(m.maxErrorDb!)}',
      )
      ..writeln(
        'No data (white): ${(m.noDataShare * 100).toStringAsFixed(0)}% of '
        'the floor',
      );
    final List<HmSpacingSeries>? x = _experiment;
    if (x != null) {
      b.writeln(
        'Spacing experiment, RMSE by grid spacing '
        '(${kHmExperimentSpacings.map((double v) => '${v.toStringAsFixed(0)} m').join(', ')}):',
      );
      for (final HmSpacingSeries ser in x) {
        b.writeln(
          '  ${ser.label}: '
          '${ser.rmseDb.map((double v) => v.toStringAsFixed(1)).join(', ')} dB',
        );
      }
    }
    b.writeln(
      'One documented method, not any survey product\'s published '
      'algorithm.',
    );
    return b.toString().trimRight();
  }
}

/// "-60.5 dBm" (ASCII hyphen, so copied text stays plain).
String fmtDbm(double v) => '${v.toStringAsFixed(1)} dBm';

/// "+17.3 dB" / "-2.0 dB".
String fmtSignedDb(double v) =>
    '${v >= 0 ? '+' : '-'}${v.abs().toStringAsFixed(1)} dB';

/// "2" or "2.5".
String fmtPower(double p) =>
    p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(1);
