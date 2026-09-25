// State for the Wi-Fi Lab Multipath Simulator (multipath-simulator).
//
// One ChangeNotifier holds every input and caches the derived results, so the
// two halves of the screen stay independent widgets: MultipathStage (the
// plots) and MultipathControls (the inputs and readouts) each listen to the
// same controller. The phone layout stacks them; a presenter layout can put
// them side by side without either knowing about the other.
//
// All physics lives in lib/services/wifi_lab/multipath_model.dart. This file
// only chooses which model to call, caches the one expensive sweep (many
// paths), and formats numbers for display.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../services/wifi_lab/multipath_model.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kMultipathSimulatorToolId = 'multipath-simulator';

/// The three scenes.
enum MultipathMode {
  oneWall('One wall', 'One wall (two-ray)'),
  standingWave('Standing wave', 'Standing wave (walk to a wall)'),
  manyPaths('Many paths', 'Many paths (Rayleigh fading)');

  const MultipathMode(this.label, this.menuLabel);

  /// Short name, used in the copy payload.
  final String label;

  /// Longer name for the Scene select.
  final String menuLabel;
}

/// Samples per plotted trace.
const int kTwoPathSamples = 801;
const int kManyPathSamples = 2001;

/// One row of the delay readout.
typedef MultipathDelayRow = ({String name, double extraMeters});

class MultipathController extends ChangeNotifier {
  MultipathController({MultipathMode initialMode = MultipathMode.oneWall})
    : _mode = initialMode;

  static const TwoRayScene twoRay = TwoRayScene();
  static const StandingWaveScene standing = StandingWaveScene();

  MultipathMode _mode;
  MultipathBand _band = MultipathBand.b24;
  WallMaterial _material = WallMaterial.metal;
  double _customGamma = 0.5;

  /// Mode 1: receiver offset along the 1 m track, meters.
  double _t = 0.3;

  /// Mode 2: receiver distance from the wall, meters.
  double _d = 0.15;

  /// Mode 3: antenna A position along the 2 m track, meters.
  double _x = 1.0;
  int _count = 12;
  ScatterEnvironment _env = ScatterEnvironment.room;
  int _seed = 1;
  double _offsetLambda = 0.5;
  bool _showAllPaths = false;

  // ── Inputs ──────────────────────────────────────────────────────────────

  MultipathMode get mode => _mode;
  set mode(MultipathMode v) => _set(() => _mode = v);

  MultipathBand get band => _band;
  set band(MultipathBand v) => _set(() => _band = v);

  WallMaterial get material => _material;
  set material(WallMaterial m) => _set(() {
    // Switching to Custom starts from the preset's value, not a jump.
    if (m == WallMaterial.custom && _material != WallMaterial.custom) {
      _customGamma = gammaMagnitude;
    }
    _material = m;
  });

  /// |Gamma| from the preset, or the custom slider.
  double get gammaMagnitude => _material.gammaMagnitude ?? _customGamma;

  /// Moving the slider makes the wall Custom.
  set gammaMagnitude(double g) => _set(() {
    _material = WallMaterial.custom;
    _customGamma = g.clamp(0.0, 1.0);
  });

  Complex get gamma => reflectionCoefficient(gammaMagnitude);

  double get trackOffset => _t;
  set trackOffset(double v) =>
      _set(() => _t = v.clamp(0.0, twoRay.trackLength));

  double get wallDistance => _d;
  set wallDistance(double v) => _set(() => _d = v.clamp(0.0, standing.range));

  double get antennaX => _x;
  set antennaX(double v) => _set(() => _x = v.clamp(0.0, 2.0));

  int get reflectorCount => _count;
  set reflectorCount(int v) => _set(() => _count = v.clamp(2, 30));

  ScatterEnvironment get environment => _env;
  set environment(ScatterEnvironment v) => _set(() => _env = v);

  int get layout => _seed;
  void newLayout() => _set(() {
    _seed++;
    _showAllPaths = false;
  });

  double get offsetLambda => _offsetLambda;
  set offsetLambda(double v) => _set(() => _offsetLambda = v.clamp(0.0, 1.0));
  double get offsetMeters => _offsetLambda * _band.wavelength;

  bool get showAllPaths => _showAllPaths;
  void toggleShowAllPaths() => _set(() => _showAllPaths = !_showAllPaths);

  /// The receiver position on the current plot's x axis, in cm.
  double get positionCm => switch (_mode) {
    MultipathMode.oneWall => _t * 100,
    MultipathMode.standingWave => _d * 100,
    MultipathMode.manyPaths => _x * 100,
  };

  /// Sets the receiver from a plot position in cm (drag on the plot).
  void setPositionCm(double cm) {
    switch (_mode) {
      case MultipathMode.oneWall:
        trackOffset = cm / 100;
      case MultipathMode.standingWave:
        wallDistance = cm / 100;
      case MultipathMode.manyPaths:
        antennaX = cm / 100;
    }
  }

  /// Right end of the plot's x axis, cm.
  double get plotRangeCm => switch (_mode) {
    MultipathMode.oneWall => twoRay.trackLength * 100,
    MultipathMode.standingWave => standing.range * 100,
    MultipathMode.manyPaths => 200,
  };

  void _set(VoidCallback f) {
    f();
    notifyListeners();
  }

  // ── Two-path modes ──────────────────────────────────────────────────────

  bool get isManyPaths => _mode == MultipathMode.manyPaths;

  List<MultipathPath> get twoPaths => _mode == MultipathMode.oneWall
      ? twoRay.paths(_t, gamma)
      : standing.paths(_d, gamma);

  double get _directLength => _mode == MultipathMode.oneWall
      ? twoRay.directLength(_t)
      : standing.directLength(_d);

  List<double> get nulls => standing.nulls(gamma, _band);

  // ── Many-path cache ─────────────────────────────────────────────────────

  ManyPathScene? _scene;
  String? _sceneKey;
  String? _offsetKey;
  List<double> _sweepA = const <double>[];
  List<double> _sweepB = const <double>[];
  FadeStats? _fade;
  PowerHistogram? _hist;
  int _revision = 0;

  void _ensureManyPaths() {
    final String key = '$_seed|$_count|${_env.name}|${_band.name}';
    final String offKey = '$key|$_offsetLambda';
    if (_offsetKey == offKey) return;
    if (_sceneKey != key) {
      _scene = ManyPathScene.generate(
        seed: _seed,
        count: _count,
        environment: _env,
      );
      _sweepA = _scene!.sweepDb(_band, kManyPathSamples);
      _hist = PowerHistogram.of(_sweepA);
      _sceneKey = key;
    }
    _sweepB = _scene!.sweepDb(_band, kManyPathSamples, offset: offsetMeters);
    _fade = FadeStats.from(_sweepA, _sweepB);
    _offsetKey = offKey;
    _revision++;
  }

  ManyPathScene get scene {
    _ensureManyPaths();
    return _scene!;
  }

  FadeStats get fade {
    _ensureManyPaths();
    return _fade!;
  }

  PowerHistogram get histogram {
    _ensureManyPaths();
    return _hist!;
  }

  // ── What the stage draws ────────────────────────────────────────────────

  /// Received power at the receiver, dB: against the direct copy alone in
  /// the two-path modes, against the average in many-path mode.
  double get receivedDb => isManyPaths
      ? scene.normalizedPowerDb(_x, _band)
      : MultipathMath.relativePowerDb(twoPaths, _band.k, _directLength);

  /// Phasors, normalized: the direct copy is 1 + 0j in the two-path modes;
  /// in many-path mode the unit circle is the average (RMS) amplitude.
  List<Complex> get phasors {
    if (isManyPaths) {
      final List<MultipathPath> ps = scene.pathsAt(_x);
      double mean = 0;
      for (final MultipathPath p in ps) {
        mean += p.coefficient.abs2 / (p.length * p.length);
      }
      final double rms = math.sqrt(mean);
      return <Complex>[
        for (final MultipathPath p in ps)
          MultipathMath.contribution(p, _band.k).scale(1 / rms),
      ];
    }
    final List<MultipathPath> ps = twoPaths;
    return MultipathMath.normalizedPhasors(
      ps,
      _band.k,
      MultipathMath.contribution(ps.first, _band.k),
    );
  }

  /// Trace A for the plot (antenna A in many-path mode).
  List<double> get traceA {
    switch (_mode) {
      case MultipathMode.oneWall:
        return twoRay.sweepDb(gamma, _band, kTwoPathSamples);
      case MultipathMode.standingWave:
        return standing.sweepDb(gamma, _band, kTwoPathSamples);
      case MultipathMode.manyPaths:
        _ensureManyPaths();
        return _sweepA;
    }
  }

  /// Trace B (antenna B), many-path mode only.
  List<double>? get traceB {
    if (!isManyPaths) return null;
    _ensureManyPaths();
    return _sweepB;
  }

  /// Changes whenever a plotted trace changes, for cheap repaint checks.
  int get plotRevision {
    if (!isManyPaths) return Object.hash(_mode, _band, gammaMagnitude);
    _ensureManyPaths();
    return Object.hash(_mode, _revision);
  }

  // ── Delays ──────────────────────────────────────────────────────────────

  /// Every copy's extra path, latest first (one row in two-path modes).
  List<MultipathDelayRow> get delayRows {
    if (!isManyPaths) {
      final List<MultipathPath> ps = twoPaths;
      return <MultipathDelayRow>[
        (name: 'Reflected', extraMeters: ps[1].length - ps[0].length),
      ];
    }
    final List<double> extras = scene.extraLengths(_x);
    return <MultipathDelayRow>[
      for (int i = 0; i < extras.length; i++)
        (name: 'Path ${i + 1}', extraMeters: extras[i]),
    ]..sort(
      (MultipathDelayRow a, MultipathDelayRow b) =>
          b.extraMeters.compareTo(a.extraMeters),
    );
  }

  /// How many copies arrive after the guard interval.
  int get latePaths => delayRows
      .where(
        (MultipathDelayRow r) => MultipathMath.exceedsGuardInterval(
          MultipathMath.delayNs(r.extraMeters),
        ),
      )
      .length;

  // ── Formatting (shared by stage, controls and copy) ─────────────────────

  static String db(double v) {
    if (v <= kPowerFloorDb + 1) return 'null';
    final String s = v.toStringAsFixed(1);
    if (s == '-0.0' || s == '0.0') return '0.0 dB';
    return v > 0 ? '+$s dB' : '$s dB';
  }

  static String cm(double meters, [int decimals = 1]) =>
      '${(meters * 100).toStringAsFixed(decimals)} cm';

  static String m(double meters) {
    if (meters < 1) return cm(meters);
    return '${meters.toStringAsFixed(meters < 10 ? 2 : 1)} m';
  }

  static String ns(double v) =>
      v < 10 ? '${v.toStringAsFixed(2)} ns' : '${v.toStringAsFixed(0)} ns';

  static String pct(double f) => '${(f * 100).toStringAsFixed(1)}%';

  /// Phase of [c] in degrees, -180 to 180.
  static String deg(Complex c) {
    final int d = (c.arg * 180 / math.pi).round();
    return '${d == -180 ? 180 : d} deg';
  }

  // ── Copy payload (GL-003 §8.16) ────────────────────────────────────────

  String copyText() {
    final StringBuffer b = StringBuffer()
      ..writeln('Multipath Simulator')
      ..writeln('Mode: ${_mode.label}')
      ..writeln(
        'Band: ${_band.label}, wavelength ${cm(_band.wavelength, 2)}, '
        'half wavelength ${cm(_band.wavelength / 2, 2)}',
      );
    if (!isManyPaths) {
      final double extra = delayRows.first.extraMeters;
      b
        ..writeln(
          'Wall: ${_material.label}, reflection coefficient magnitude '
          '${gammaMagnitude.toStringAsFixed(2)}',
        )
        ..writeln(
          _mode == MultipathMode.oneWall
              ? 'Receiver: ${cm(_t)} along the 1 m track'
              : 'Receiver: ${cm(_d)} from the wall',
        )
        ..writeln('Received: ${db(receivedDb)} vs the direct path alone')
        ..writeln(
          'Reflected copy: ${m(extra)} longer, '
          '${ns(MultipathMath.delayNs(extra))} late',
        );
      return b.toString().trimRight();
    }
    final FadeStats f = fade;
    b
      ..writeln('Reflectors: $_count (${_env.label}, layout $_seed)')
      ..writeln('Antenna A at ${cm(_x)}: ${db(receivedDb)} vs the average')
      ..writeln(
        'Antenna B offset: ${_offsetLambda.toStringAsFixed(2)} '
        'wavelengths (${cm(offsetMeters)})',
      )
      ..writeln('Below -10 dB, A: ${pct(f.fractionA)}')
      ..writeln('Below -10 dB, B: ${pct(f.fractionB)}')
      ..writeln('Below -10 dB, both at once: ${pct(f.fractionBoth)}')
      ..writeln('Rayleigh prediction for one antenna: 9.5%')
      ..writeln('Paths past the 0.8 us guard interval: $latePaths of $_count');
    return b.toString().trimRight();
  }
}
