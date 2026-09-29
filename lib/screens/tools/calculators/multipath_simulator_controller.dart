// State for the Wi-Fi Classroom Multipath Simulator (multipath-simulator).
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
import 'package:flutter/services.dart';

import '../../../services/wifi_lab/multipath_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';

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

/// Antenna counts the Combine readouts offer.
const List<int> kDiversityAntennaCounts = <int>[2, 4];

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
  CombineMethod _combine = CombineMethod.aOnly;
  int _antennas = 2;

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

  /// How the antennas are combined (Many paths).
  CombineMethod get combine => _combine;
  set combine(CombineMethod v) => _set(() => _combine = v);

  /// A only, then Selection, then MRC, then back.
  void cycleCombine() => combine =
      CombineMethod.values[(_combine.index + 1) % CombineMethod.values.length];

  /// How many antennas the receiver has (2 or 4). They sit one antenna B
  /// offset apart: B at +offset, C at +2 offset, D at +3 offset.
  int get antennaCount => _antennas;
  set antennaCount(int v) =>
      _set(() => _antennas = kDiversityAntennaCounts.contains(v) ? v : 2);

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

  /// Presenter keyboard. Nothing animates, so there is no play, step or
  /// reset: Up and Down move the receiver (antenna A in Many paths) a
  /// sixteenth of a wavelength, so eight presses walk from one null to the
  /// next in any band.
  PresenterActions get presenterActions => PresenterActions(
    sliderDown: () => setPositionCm(positionCm - keyStepCm),
    sliderUp: () => setPositionCm(positionCm + keyStepCm),
    sliderLabel: 'Receiver position',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyC,
        keyLabel: 'C',
        description: 'Many paths: combine A only, Selection, MRC',
        onPressed: () {
          if (isManyPaths) cycleCombine();
        },
      ),
    ],
  );

  /// One presenter key press, cm: a sixteenth of the band's wavelength.
  double get keyStepCm => _band.wavelength * 100 / 16;

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
  String? _combineKey;
  List<double> _sweepA = const <double>[];
  List<double> _sweepB = const <double>[];

  /// Antennas B, C, D (as many as [antennaCount] asks for), B first.
  List<List<double>> _others = const <List<double>>[];
  List<double>? _combined;
  double _allFaded = 0;
  FadeStats? _fade;
  PowerHistogram? _hist;
  int _revision = 0;

  void _ensureManyPaths() {
    final String key = '$_seed|$_count|${_env.name}|${_band.name}';
    final String offKey = '$key|$_offsetLambda|$_antennas';
    final String comboKey = '$offKey|${_combine.name}';
    if (_combineKey == comboKey) return;
    if (_offsetKey != offKey) {
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
      _others = <List<double>>[
        for (int j = 1; j < _antennas; j++)
          _scene!.sweepDb(_band, kManyPathSamples, offset: j * offsetMeters),
      ];
      _sweepB = _others.first;
      _fade = FadeStats.from(_sweepA, _sweepB);
      // Every antenna faded at once: selection's own fade share.
      _allFaded = DiversityMath.fractionBelow(
        DiversityMath.combineDb(CombineMethod.selection, <List<double>>[
          _sweepA,
          ..._others,
        ]),
        kFadeThresholdDb,
      );
      _offsetKey = offKey;
    }
    _combined = _combine == CombineMethod.aOnly
        ? null
        : DiversityMath.combineDb(_combine, <List<double>>[
            _sweepA,
            ..._others,
          ]);
    _combineKey = comboKey;
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

  // ── Diversity ───────────────────────────────────────────────────────────

  /// True when a combining method is on (Many paths, not A only).
  bool get isCombining => isManyPaths && _combine != CombineMethod.aOnly;

  /// Share of the track where every antenna is below -10 dB at once.
  double get allFadedFraction {
    _ensureManyPaths();
    return _allFaded;
  }

  /// Share of the track where the combined signal is below -10 dB. A only
  /// reads antenna A.
  double get combinedFadeFraction {
    _ensureManyPaths();
    final List<double>? c = _combined;
    if (c == null) return _fade!.fractionA;
    return DiversityMath.fractionBelow(c, kFadeThresholdDb);
  }

  /// The textbook share below -10 dB for [method] with this many antennas
  /// (independent Rayleigh antennas).
  double rayleighFadeFraction(CombineMethod method) =>
      DiversityMath.outageAtDb(method, kFadeThresholdDb, _antennas);

  /// The textbook diversity gain at 1% for [method] with this many antennas.
  double rayleighGainDb(CombineMethod method) =>
      DiversityMath.gainDb(method, _antennas);

  /// The gain this track shows at 1%: the combined trace's 1% level minus
  /// antenna A's. Null when nothing is combined.
  double? get trackGainDb {
    _ensureManyPaths();
    final List<double>? c = _combined;
    if (c == null) return null;
    return DiversityMath.percentileDb(c, DiversityMath.gainOutage) -
        DiversityMath.percentileDb(_sweepA, DiversityMath.gainOutage);
  }

  /// The combined signal at the receiver, dB against one antenna's average.
  double get combinedDb {
    final ManyPathScene s = scene;
    return MultipathMath.powerRatioToDb(
      DiversityMath.combine(_combine, <double>[
        for (int j = 0; j < _antennas; j++)
          s.normalizedPower(_x + j * offsetMeters, _band),
      ]),
    );
  }

  /// Top of the plot's dB axis. Four antennas under MRC average +6 dB and
  /// peak past +10, so the axis grows to +20 for them.
  double get plotYMax =>
      isCombining && _combine == CombineMethod.mrc && _antennas == 4 ? 20 : 10;

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

  /// The combined trace, when a combining method is on.
  List<double>? get traceCombined {
    if (!isManyPaths) return null;
    _ensureManyPaths();
    return _combined;
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

  /// A short length in [u]: [cm] to [decimals] in metric, inches by the
  /// shared small rule in imperial.
  static String len(double meters, UnitSystem u, [int decimals = 1]) =>
      u.isMetric ? cm(meters, decimals) : LengthFormat(u).small(meters);

  /// An extra path length in [u]: [m] in metric; in imperial inches under a
  /// foot, else feet to two decimals under 10 ft, one above.
  static String path(double meters, UnitSystem u) {
    if (u.isMetric) return m(meters);
    final double ft = LengthUnits.metresToFeet(meters);
    if (ft < 1) return LengthFormat(u).small(meters);
    return '${ft.toStringAsFixed(ft < 10 ? 2 : 1)} ft';
  }

  /// A plain distance label, "1 m" / "3.3 ft", "10 m" / "33 ft".
  static String dist(double meters, UnitSystem u) =>
      LengthFormat(u).dist(meters);

  UnitSystem _units = UnitSystem.metric;

  /// Length units on screen. The scene stays in metres.
  UnitSystem get units => _units;

  void setUnits(UnitSystem u) {
    if (u == _units) return;
    _units = u;
    notifyListeners();
  }

  static String ns(double v) =>
      v < 10 ? '${v.toStringAsFixed(2)} ns' : '${v.toStringAsFixed(0)} ns';

  static String pct(double f) => '${(f * 100).toStringAsFixed(1)}%';

  /// [pct] for a textbook share that can be tiny: under 0.1% it keeps three
  /// decimals ("0.008%") instead of rounding to "0.0%", and under 0.001% it
  /// says so ("under 0.001%") rather than print a zero.
  static String pctFine(double f) {
    if (f <= 0 || f >= 0.001) return pct(f);
    if (f < 0.00001) return 'under 0.001%';
    return '${(f * 100).toStringAsFixed(3)}%';
  }

  /// A gain in dB, one decimal, no sign: "10.2 dB".
  static String gain(double v) => '${v.toStringAsFixed(1)} dB';

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
        'Band: ${_band.label}, wavelength ${len(_band.wavelength, _units, 2)}, '
        'half wavelength ${len(_band.wavelength / 2, _units, 2)}',
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
              ? 'Receiver: ${len(_t, _units)} along the '
                    '${dist(twoRay.trackLength, _units)} track'
              : 'Receiver: ${len(_d, _units)} from the wall',
        )
        ..writeln('Received: ${db(receivedDb)} vs the direct path alone')
        ..writeln(
          'Reflected copy: ${path(extra, _units)} longer, '
          '${ns(MultipathMath.delayNs(extra))} late',
        );
      return b.toString().trimRight();
    }
    final FadeStats f = fade;
    b
      ..writeln('Reflectors: $_count (${_env.label}, layout $_seed)')
      ..writeln(
        'Antenna A at ${len(_x, _units)}: ${db(receivedDb)} vs the average',
      )
      ..writeln(
        'Antenna B offset: ${_offsetLambda.toStringAsFixed(2)} '
        'wavelengths (${len(offsetMeters, _units)})',
      )
      ..writeln('Below -10 dB, A: ${pct(f.fractionA)}')
      ..writeln('Below -10 dB, B: ${pct(f.fractionB)}')
      ..writeln('Below -10 dB, both at once: ${pct(f.fractionBoth)}')
      ..writeln('Rayleigh prediction for one antenna: 9.5%')
      ..writeln('Antennas: $_antennas, combine: ${_combine.longName}');
    if (_antennas > 2) {
      b.writeln('Below -10 dB, all $_antennas at once: ${pct(allFadedFraction)}');
    }
    if (isCombining) {
      b
        ..writeln(
          'Below -10 dB, combined (${_combine.label}): '
          '${pct(combinedFadeFraction)}; Rayleigh predicts '
          '${pctFine(rayleighFadeFraction(_combine))}',
        )
        ..writeln(
          'Diversity gain at 1%, Rayleigh: '
          '${gain(rayleighGainDb(_combine))}; on this track: '
          '${gain(trackGainDb!)}',
        );
    }
    b.writeln('Paths past the 0.8 us guard interval: $latePaths of $_count');
    return b.toString().trimRight();
  }
}
