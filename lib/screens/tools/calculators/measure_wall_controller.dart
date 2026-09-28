// State for the Wi-Fi Classroom tool "How to Measure Wall Attenuation"
// (measure-wall).
//
// One ChangeNotifier over an immutable MwConfig (the pure model in
// lib/services/wifi_lab/measure_wall_model.dart), shared by the stage and the
// controls so they lay out independently: stacked on a phone, side by side on
// a wide window, and in the full-screen presenter layout, which uses this
// same object (state is shared, not copied).
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/measure_wall_model.dart';
import '../../../services/wifi_lab/wall_slab_physics.dart';
import '../../../units/unit_system.dart';
import '../../../widgets/presenter/presenter_actions.dart';
import 'measure_wall_format.dart';

export '../../../services/wifi_lab/measure_wall_model.dart';

/// A ready-made geometry the student can jump to.
enum MwPreset {
  /// Keith's method: source 4 m away, readings hugging the wall.
  tight(4, 0.1, 'Tight'),

  /// Readings 1 m either side of the wall, source 4 m away.
  loose(4, 1, 'Loose'),

  /// The source 1 m from the wall, readings hugging it.
  sourceClose(1, 0.1, 'Source too close'),

  /// The predict-then-reveal scene: source 2 m away, readings 1 m either side.
  predict(MwPredict.sourceToWallM, MwPredict.gapM, 'The prediction');

  const MwPreset(this.sourceToWallM, this.gapM, this.title);
  final double sourceToWallM;
  final double gapM;
  final String title;
}

class MeasureWallController extends ChangeNotifier {
  MeasureWallController([MwConfig? initial])
    : _initial = initial ?? MwConfig(),
      _config = initial ?? MwConfig();

  final MwConfig _initial;
  MwConfig _config;
  bool _revealed = false;
  int _revision = 0;
  UnitSystem _units = UnitSystem.metric;

  /// Metres per press of Left or Right in presenter mode.
  static const double keyMoveM = 0.1;

  /// Metres per press of Up or Down (source distance) in presenter mode.
  static const double keySourceM = 0.5;

  MwConfig get config => _config;
  bool get revealed => _revealed;

  /// Bumped on every change that alters what the stage draws.
  int get revision => _revision;

  /// Length units on screen. The model stays in metres.
  UnitSystem get units => _units;

  void setUnits(UnitSystem u) {
    if (u == _units) return;
    _units = u;
    _revision++;
    notifyListeners();
  }

  void _set(MwConfig next) {
    _config = next;
    _revision++;
    notifyListeners();
  }

  void setBand(WifiBand b) => _set(_config.copyWith(band: b));
  void setMaterial(WallMaterial m) => _set(_config.copyWith(material: m));
  void setThicknessM(double t) => _set(_config.copyWith(thicknessM: t));
  void setSourceToWall(double d) => _set(_config.copyWith(sourceToWallM: d));
  void setNearGap(double a) =>
      _set(_config.copyWith(nearGapM: a, side: MwSide.near));
  void setFarGap(double a) =>
      _set(_config.copyWith(farGapM: a, side: MwSide.far));
  void setSide(MwSide s) => _set(_config.copyWith(side: s));
  void toggleSide() =>
      setSide(_config.side == MwSide.near ? MwSide.far : MwSide.near);
  void setSamples(int n) => _set(_config.copyWith(samplesPerSide: n));
  void setSpread(double s) => _set(_config.copyWith(spreadDb: s));
  void laptopAt(double distanceFromSourceM) =>
      _set(_config.withLaptopAt(distanceFromSourceM));
  void moveLaptopBy(double deltaM) => _set(_config.moveLaptopBy(deltaM));

  /// "Take readings": a fresh series on the side the laptop is on.
  void retake() => _set(_config.retake());

  /// Jumps to a preset geometry, laptop on the near side. The wall, band and
  /// readings stay as set.
  void applyPreset(MwPreset p) => _set(
    _config.copyWith(
      sourceToWallM: p.sourceToWallM,
      nearGapM: p.gapM,
      farGapM: p.gapM,
      side: MwSide.near,
    ),
  );

  /// The preset the geometry matches now, if any.
  MwPreset? get activePreset {
    for (final MwPreset p in MwPreset.values) {
      if ((_config.sourceToWallM - p.sourceToWallM).abs() < 1e-9 &&
          (_config.nearGapM - p.gapM).abs() < 1e-9 &&
          (_config.farGapM - p.gapM).abs() < 1e-9) {
        return p;
      }
    }
    return null;
  }

  void setRevealed(bool v) {
    _revealed = v;
    _revision++;
    notifyListeners();
  }

  void toggleReveal() => setRevealed(!_revealed);

  /// Back to the opening scene; the answer hides.
  void reset() {
    _revealed = false;
    _set(_initial);
  }

  /// Presenter keyboard: Space takes new readings, Right and Left walk the
  /// laptop away from and toward the source (crossing the wall at a face),
  /// Up and Down move the source, S switches sides, P reveals the answer,
  /// R resets. Nothing animates, so Space and Right are relabeled.
  PresenterActions get presenterActions => PresenterActions(
    playPause: retake,
    playPauseLabel: 'Take new readings on this side',
    step: () => moveLaptopBy(keyMoveM),
    stepLabel: 'Move the laptop away from the source',
    reset: reset,
    sliderDown: () => setSourceToWall(_config.sourceToWallM - keySourceM),
    sliderUp: () => setSourceToWall(_config.sourceToWallM + keySourceM),
    sliderLabel: 'Source distance from the wall',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.arrowLeft,
        keyLabel: 'Left arrow',
        description: 'Move the laptop toward the source',
        onPressed: () => moveLaptopBy(-keyMoveM),
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyS,
        keyLabel: 'S',
        description: 'Switch the laptop to the other side of the wall',
        onPressed: toggleSide,
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
    final MwConfig c = _config;
    final MwFormat f = MwFormat(_units);
    final double? m = c.measuredDb;
    return <String>[
      'How to Measure Wall Attenuation',
      'Laptop locked to channel ${c.channel} (${c.freqMHz} MHz, '
          '${c.band.label}); source radiates '
          '${MwFormat.n(MwConfig.txPowerDbm, 0)} dBm',
      'Wall: ${c.material.label}, ${f.thickness(c.thicknessM)} '
          '(ITU-R P.2040-4 model): true loss ${MwFormat.wallDb(c.trueWallDb)}',
      'Source ${f.dist(c.sourceToWallM)} from the wall; near readings '
          '${f.gap(c.nearGapM)} in front, far readings ${f.gap(c.farGapM)} '
          'behind',
      'Near: ${c.samplesPerSide} readings, average '
          '${MwFormat.dbm(c.nearSeries.averageDbm)}',
      c.farBelowFloor
          ? 'Far: below the ${MwFormat.dbm(MwConfig.noiseFloorDbm)} noise '
                'floor, no reading'
          : 'Far: ${c.samplesPerSide} readings, average '
                '${MwFormat.dbm(c.farSeries.averageDbm)}',
      m == null
          ? 'Measured wall attenuation: cannot be measured here'
          : 'Measured wall attenuation: ${MwFormat.db(m)}',
      'Free-space error from the geometry: '
          '${MwFormat.signedDb(c.geometryErrorDb)} '
          '(20 log10(${f.dist(c.farDistM, decimals: 2)} / '
          '${f.dist(c.nearDistM, decimals: 2)}))',
      'Fading left in the averages: '
          '${c.farBelowFloor ? 'none, no far reading' : MwFormat.signedDb(c.fadingResidualDb)} '
          '(illustrative spread, ${MwFormat.n(c.spreadDb)} dB standard '
          'deviation)',
    ].join('\n');
  }
}
