// State for the Wi-Fi Classroom Predict, Then Measure tool (predict-then-measure).
//
// One ChangeNotifier holds the scenario, the design's wall losses, the hidden
// truth, the AP on a stick, the student's walk and the computed maps, so the
// two halves of the screen stay independent widgets: PredictMeasureStage
// (floor, maps, walk) and PredictMeasureControls (inputs and readouts) each
// listen to this one object. The phone layout stacks them; the presenter
// layout places them side by side (spec 00).
//
// All math lives in lib/services/wifi_lab/predict_measure_engine.dart. While
// the student is drawing a walk only the samples are recomputed; the maps
// follow when the stroke ends, so drawing stays smooth.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../services/wifi_lab/heat_map_builder_engine.dart';
import '../../../services/wifi_lab/predict_measure_engine.dart';
import '../../../widgets/presenter/presenter_actions.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kPredictMeasureToolId = 'predict-then-measure';

/// What the map shows.
enum PmMapView {
  predicted('Predicted'),
  measured('Measured'),
  difference('Difference'),
  truth('Truth');

  const PmMapView(this.label);

  final String label;
}

/// What a tap or drag on the floor does.
enum PmTapAction {
  walk('Draw the walk'),
  ap('Move the AP');

  const PmTapAction(this.label);

  final String label;
}

class PredictMeasureController extends ChangeNotifier {
  PredictMeasureController({PmPreset preset = PmPreset.office})
    : _preset = preset {
    _load(pmScenario(preset).defaultSeed);
  }

  PmPreset _preset;
  late int _seed;
  late List<double> _trueLosses;
  late PmModel _model;
  List<List<HmPoint>> _legs = const <List<HmPoint>>[];
  bool _drawing = false;
  double _sigmaDb = 0;
  int _noiseSeed = 1;
  PmMapView _view = PmMapView.predicted;
  bool _revealed = false;
  PmTapAction _tapAction = PmTapAction.walk;
  int _selectedWall = 0;
  Set<int> _updated = const <int>{};
  bool _walkFull = false;

  late Float64List _predGrid;
  late Float64List _truthGrid;
  PmSurvey _survey = PmSurvey.empty;
  late PmMaps _maps;

  // ── Read side ─────────────────────────────────────────────────────────────

  PmPreset get preset => _preset;
  PmScenario get scenario => pmScenario(_preset);
  int get seed => _seed;
  PmModel get model => _model;
  List<PmWall> get walls => _model.walls;
  HmPoint get ap => _model.ap;
  List<List<HmPoint>> get legs => _legs;
  bool get hasWalk => _legs.isNotEmpty;
  bool get drawing => _drawing;
  bool get walkFull => _walkFull;
  double get sigmaDb => _sigmaDb;
  PmMapView get view => _view;
  bool get revealed => _revealed;
  PmTapAction get tapAction => _tapAction;
  int get selectedWall => _selectedWall;
  PmWall get selected => _model.walls[_selectedWall];
  PmSurvey get survey => _survey;
  PmMaps get maps => _maps;

  /// Walls whose design loss came from the walk ("Update model").
  Set<int> get updatedWalls => _updated;

  int get testedCount => _survey.tests.length;
  int get untestedCount => _model.walls.length - _survey.tests.length;

  /// The map views on offer: Truth only after the reveal.
  List<PmMapView> get availableViews => <PmMapView>[
    PmMapView.predicted,
    PmMapView.measured,
    PmMapView.difference,
    if (_revealed) PmMapView.truth,
  ];

  /// Tested walls whose estimate differs from the design, to update.
  bool get canUpdateModel {
    for (final PmWallTest t in _survey.tests.values) {
      if ((t.estimateDb - _model.walls[t.wallIndex].predictedLossDb).abs() >
          0.05) {
        return true;
      }
    }
    return false;
  }

  /// "W3": a wall's short name (1-based).
  static String wallName(int i) => 'W${i + 1}';

  // ── Recompute ─────────────────────────────────────────────────────────────

  void _load(int seed) {
    final PmScenario s = scenario;
    _seed = seed;
    _trueLosses = pmHiddenTruth(s, seed);
    _model = PmModel(
      widthM: s.widthM,
      depthM: s.depthM,
      ap: s.ap,
      walls: pmWalls(s, _trueLosses),
      pathLossExponent: s.pathLossExponent,
    );
    _legs = const <List<HmPoint>>[];
    _drawing = false;
    _sigmaDb = 0;
    _noiseSeed = 1;
    _view = PmMapView.predicted;
    _revealed = false;
    _tapAction = PmTapAction.walk;
    _selectedWall = 0;
    _updated = const <int>{};
    _walkFull = false;
    _gridsChanged(predicted: true, truth: true);
  }

  void _gridsChanged({bool predicted = false, bool truth = false}) {
    if (predicted) {
      _predGrid = hmTruthGrid(_model.predictedFloor, kPmCellM);
    }
    if (truth) _truthGrid = hmTruthGrid(_model.trueFloor, kPmCellM);
    _surveyChanged();
  }

  void _surveyChanged() {
    _survey = runPmSurvey(
      _model,
      _legs,
      noise: HmNoise(sigmaDb: _sigmaDb, seed: _noiseSeed),
    );
    if (!_drawing) {
      _maps = buildPmMaps(
        _model,
        _survey,
        predicted: _predGrid,
        truth: _truthGrid,
      );
    }
  }

  void _changed({bool predicted = false, bool truth = false}) {
    _gridsChanged(predicted: predicted, truth: truth);
    notifyListeners();
  }

  // ── Scenario ──────────────────────────────────────────────────────────────

  set preset(PmPreset p) {
    if (p == _preset) return;
    _preset = p;
    _load(pmScenario(p).defaultSeed);
    notifyListeners();
  }

  /// Everything but the building back to how the scenario opens (presenter
  /// R): the design's losses, the AP, the walk, the noise, the view and the
  /// reveal. The hidden truth, including any the instructor set, stays.
  void reset() {
    final List<double> keep = _trueLosses;
    final int seed = _seed;
    _load(seed);
    _trueLosses = keep;
    _model = _model.copyWith(
      walls: <PmWall>[
        for (int i = 0; i < _model.walls.length; i++)
          _model.walls[i].copyWith(trueLossDb: keep[i]),
      ],
    );
    _changed(predicted: true, truth: true);
  }

  /// A new seeded hidden truth for the same floor; hides the reveal.
  void newHiddenTruth() {
    _seed++;
    _trueLosses = pmHiddenTruth(scenario, _seed);
    _setTruth();
    _revealed = false;
    if (_view == PmMapView.truth) _view = PmMapView.predicted;
    _changed(truth: true);
  }

  void _setTruth() {
    _model = _model.copyWith(
      walls: <PmWall>[
        for (int i = 0; i < _model.walls.length; i++)
          _model.walls[i].copyWith(trueLossDb: _trueLosses[i]),
      ],
    );
  }

  /// The instructor sets the selected wall's true loss.
  set trueLossDb(double v) {
    final double l = ((v * 2).round() / 2).clamp(kPmMinLossDb, kPmMaxLossDb);
    if (l == _trueLosses[_selectedWall]) return;
    _trueLosses = List<double>.of(_trueLosses)..[_selectedWall] = l;
    _setTruth();
    _changed(truth: true);
  }

  // ── The design ────────────────────────────────────────────────────────────

  set selectedWall(int i) {
    final int w = i.clamp(0, _model.walls.length - 1);
    if (w == _selectedWall) return;
    _selectedWall = w;
    notifyListeners();
  }

  void _setPredicted(int i, double v) {
    final double l = ((v * 2).round() / 2).clamp(kPmMinLossDb, kPmMaxLossDb);
    if (l == _model.walls[i].predictedLossDb) return;
    _model = _model.copyWith(
      walls: <PmWall>[
        for (int j = 0; j < _model.walls.length; j++)
          j == i
              ? _model.walls[j].copyWith(predictedLossDb: l)
              : _model.walls[j],
      ],
    );
    _updated = Set<int>.unmodifiable(<int>{..._updated}..remove(i));
    _changed(predicted: true);
  }

  /// The selected wall's design loss.
  set predictedLossDb(double v) => _setPredicted(_selectedWall, v);

  /// The selected wall back to its material's illustrative default.
  void useMaterialDefault() =>
      _setPredicted(_selectedWall, selected.material.defaultLossDb);

  /// "Update model": tested walls take their measured estimates.
  void updateModel() {
    if (_survey.tests.isEmpty) return;
    _model = _model.copyWith(walls: pmUpdateModel(_model.walls, _survey));
    _updated = Set<int>.unmodifiable(<int>{
      ..._updated,
      ..._survey.tests.keys,
    });
    _changed(predicted: true);
  }

  // ── The AP ────────────────────────────────────────────────────────────────

  /// Moves the AP (snapped to 0.5 m). The walk is taken again from the new
  /// spot, as it would be on site.
  void moveAp(HmPoint p) {
    final HmPoint q = (
      x: ((p.x * 2).round() / 2).clamp(0.5, _model.widthM - 0.5),
      y: ((p.y * 2).round() / 2).clamp(0.5, _model.depthM - 0.5),
    );
    if (q == _model.ap) return;
    _model = _model.copyWith(ap: q);
    _changed(predicted: true, truth: true);
  }

  set apX(double x) => moveAp((x: x, y: _model.ap.y));
  set apY(double y) => moveAp((x: _model.ap.x, y: y));

  set tapAction(PmTapAction a) {
    if (a == _tapAction) return;
    _tapAction = a;
    notifyListeners();
  }

  // ── The walk ──────────────────────────────────────────────────────────────

  int get sampleCount => _survey.samples.length;

  HmPoint _clampFloor(HmPoint p) => (
    x: p.x.clamp(0.0, _model.widthM),
    y: p.y.clamp(0.0, _model.depthM),
  );

  /// Appends [p] to the last leg when the walk still has room.
  bool _append(HmPoint p, {bool newLeg = false}) {
    if (_survey.samples.length >= kPmMaxSamples) {
      _walkFull = true;
      return false;
    }
    final HmPoint q = _clampFloor(p);
    if (newLeg || _legs.isEmpty) {
      _legs = List<List<HmPoint>>.unmodifiable(<List<HmPoint>>[
        ..._legs,
        List<HmPoint>.unmodifiable(<HmPoint>[q]),
      ]);
    } else {
      final List<HmPoint> last = _legs.last;
      _legs = List<List<HmPoint>>.unmodifiable(<List<HmPoint>>[
        ..._legs.sublist(0, _legs.length - 1),
        List<HmPoint>.unmodifiable(<HmPoint>[...last, q]),
      ]);
    }
    return true;
  }

  /// A tap in walk mode: the walk continues to [p].
  void addWalkPoint(HmPoint p) {
    if (!_model.contains(p)) return;
    _append(p);
    _changed();
  }

  /// A drag starts a new leg at [p].
  void startLeg(HmPoint p) {
    if (!_model.contains(p)) return;
    _drawing = true;
    _append(p, newLeg: true);
    _surveyChanged();
    notifyListeners();
  }

  /// A drag moves on to [p]. Points closer than 0.25 m are skipped.
  void extendLeg(HmPoint p) {
    if (!_drawing || _legs.isEmpty) return;
    final HmPoint last = _legs.last.last;
    final HmPoint q = _clampFloor(p);
    final double dx = q.x - last.x;
    final double dy = q.y - last.y;
    if (dx * dx + dy * dy < 0.0625) return;
    if (!_append(q)) return;
    _surveyChanged();
    notifyListeners();
  }

  void endLeg() {
    if (!_drawing) return;
    _drawing = false;
    _changed();
  }

  /// A tap on the floor, per [tapAction].
  void tapFloor(HmPoint p) {
    if (_tapAction == PmTapAction.ap) {
      moveAp(p);
    } else {
      addWalkPoint(p);
    }
  }

  void undoLeg() {
    if (_legs.isEmpty) return;
    _legs = List<List<HmPoint>>.unmodifiable(
      _legs.sublist(0, _legs.length - 1),
    );
    _walkFull = false;
    _changed();
  }

  void clearWalk() {
    if (_legs.isEmpty) return;
    _legs = const <List<HmPoint>>[];
    _walkFull = false;
    _changed();
  }

  /// The scenario's corridor walk, which crosses no wall.
  void useOneSideWalk() {
    _legs = List<List<HmPoint>>.unmodifiable(<List<HmPoint>>[
      List<HmPoint>.unmodifiable(scenario.oneSideWalk),
    ]);
    _walkFull = false;
    _changed();
  }

  /// A short leg across every wall: captures on both sides of each.
  void useBothSidesWalk() {
    _legs = List<List<HmPoint>>.unmodifiable(pmBothSidesWalk(_model));
    _walkFull = false;
    _changed();
  }

  set sigmaDb(double v) {
    final double s = ((v * 2).round() / 2).clamp(0.0, kPmMaxSigmaDb);
    if (s == _sigmaDb) return;
    _sigmaDb = s;
    _changed();
  }

  void nudgeNoise(int dir) => sigmaDb = _sigmaDb + 0.5 * dir.sign;

  /// Walks the same path again with fresh noise.
  void retakeWalk() {
    _noiseSeed++;
    _changed();
  }

  // ── View and reveal ───────────────────────────────────────────────────────

  set view(PmMapView v) {
    if (v == _view || !availableViews.contains(v)) return;
    _view = v;
    notifyListeners();
  }

  /// The next map on offer, wrapping (presenter M).
  void nextView() {
    final List<PmMapView> v = availableViews;
    _view = v[(v.indexOf(_view) + 1) % v.length];
    notifyListeners();
  }

  set revealed(bool r) {
    if (r == _revealed) return;
    _revealed = r;
    if (r) {
      _view = PmMapView.truth;
    } else if (_view == PmMapView.truth) {
      _view = PmMapView.predicted;
    }
    notifyListeners();
  }

  /// Presenter Space.
  void toggleReveal() => revealed = !_revealed;

  // ── Presenter ─────────────────────────────────────────────────────────────

  /// Presenter keys (spec 00 and 32): Space reveals or hides the truth, R
  /// resets, Up and Down move the noise 0.5 dB, M cycles the maps, U updates
  /// the model, C clears the walk, B walks both sides of every wall, O walks
  /// one side only. The spec asked for Tab to cycle the maps; Tab stays the
  /// keyboard's way between controls (WCAG 2.1.1), so maps are on M.
  PresenterActions get presenterActions => PresenterActions(
    playPause: toggleReveal,
    playPauseLabel: 'Reveal or hide the truth',
    reset: reset,
    sliderDown: () => nudgeNoise(-1),
    sliderUp: () => nudgeNoise(1),
    sliderLabel: 'Noise',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyM,
        keyLabel: 'M',
        description: 'Next map: predicted, measured, difference, truth',
        onPressed: nextView,
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyU,
        keyLabel: 'U',
        description: 'Update the model from the walk',
        onPressed: updateModel,
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyC,
        keyLabel: 'C',
        description: 'Clear the walk',
        onPressed: clearWalk,
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyB,
        keyLabel: 'B',
        description: 'Walk both sides of every wall',
        onPressed: useBothSidesWalk,
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyO,
        keyLabel: 'O',
        description: 'Walk one side only (the corridor)',
        onPressed: useOneSideWalk,
      ),
    ],
  );

  // ── Copy ──────────────────────────────────────────────────────────────────

  String copyText() {
    final PmMaps m = _maps;
    final StringBuffer b = StringBuffer()
      ..writeln('Predict, Then Measure (WLAN Pros Toolbox, teaching model)')
      ..writeln(
        '${_preset.label} floor (illustrative), '
        '${_model.widthM.toStringAsFixed(0)} m x '
        '${_model.depthM.toStringAsFixed(0)} m, AP on a stick at '
        '${fmtM(_model.ap.x)}, ${fmtM(_model.ap.y)} m, '
        '${_model.eirpDbm.toStringAsFixed(0)} dBm effective isotropic '
        'radiated power (EIRP), n = '
        '${_model.pathLossExponent.toStringAsFixed(1)} (illustrative)',
      )
      ..writeln(
        'Walk: $sampleCount samples every '
        '${kPmSampleSpacingM.toStringAsFixed(0)} m, noise '
        '${_sigmaDb.toStringAsFixed(1)} dB (illustrative)',
      )
      ..writeln('Walls (losses illustrative):');
    for (int i = 0; i < _model.walls.length; i++) {
      final PmWall w = _model.walls[i];
      final PmWallTest? t = _survey.tests[i];
      b.writeln(
        '  ${wallName(i)} ${w.material.label}: design '
        '${fmtDb(w.predictedLossDb)}'
        '${_updated.contains(i) ? ' (updated from the walk)' : ''}, '
        '${t == null ? 'untested' : 'tested ${fmtDb(t.estimateDb)}'}'
        '${_revealed ? ', true ${fmtDb(w.trueLossDb)}' : ''}',
      );
    }
    b
      ..writeln('Walls tested: $testedCount, untested: $untestedCount')
      ..writeln(
        'Largest measured-vs-predicted difference: '
        '${m.largestDiffDb == null ? 'no data' : fmtSignedDb(m.largestDiffDb!)}',
      )
      ..writeln(
        'Floor where they differ by more than '
        '${kPmDiffThresholdDb.toStringAsFixed(0)} dB: '
        '${fmtPct(m.diffOverShare)} (measured: ${fmtPct(m.measuredShare)})',
      )
      ..writeln(
        'Below the ${kPmDesignTargetDbm.toStringAsFixed(0)} dBm design target '
        '(illustrative): predicted ${fmtPct(m.predictedBelowTarget)}'
        '${_revealed ? ', truth ${fmtPct(m.truthBelowTarget)}' : ''}',
      )
      ..writeln(
        'Wall losses are illustrative, adjustable values, not measured '
        'material data.',
      );
    return b.toString().trimRight();
  }
}

/// "12.5 m" without the unit: one decimal only when needed.
String fmtM(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// "10.0 dB".
String fmtDb(double v) => '${v.toStringAsFixed(1)} dB';

/// "+17.3 dB" / "-2.0 dB" (ASCII hyphen, so copied text stays plain).
String fmtSignedDb(double v) =>
    '${v >= 0 ? '+' : '-'}${v.abs().toStringAsFixed(1)} dB';

/// "-60.5 dBm".
String fmtDbm(double v) => '${v.toStringAsFixed(1)} dBm';

/// "12%".
String fmtPct(double share) => '${(share * 100).toStringAsFixed(0)}%';
