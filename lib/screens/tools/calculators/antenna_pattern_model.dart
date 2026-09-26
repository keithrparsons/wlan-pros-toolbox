// State for the Wi-Fi Lab "Antenna Pattern" tool (antenna-pattern).
//
// Keith's standing rule (spec 00): the screen is a STAGE (the 3D surface and
// the two polar cuts, AntennaPatternStage) and CONTROLS (inputs and readouts,
// AntennaPatternControls), both over this one object, so a presenter layout
// can place them side by side unchanged.
//
// Two notifiers, on purpose:
//   - AntennaPatternLab itself: every input. A change bumps [revision], and
//     the gain grid and the 3D mesh are rebuilt once, lazily, on next read.
//   - [view]: the camera only. Dragging to rotate touches nothing but this,
//     so a frame of rotation repaints the 3D painter and rebuilds no widget
//     and no grid.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../services/wifi_lab/antenna_pattern_formats.dart';
import '../../../services/wifi_lab/antenna_pattern_math.dart';
import '../../../widgets/presenter/presenter_actions.dart';
import 'antenna_pattern_mesh.dart';

enum AntennaModelKind {
  dipole('Half-wave dipole'),
  omni('Omni, set by gain'),
  collinear('Collinear omni (array)'),
  directional('Directional (patch or sector)'),
  imported('Imported pattern file');

  const AntennaModelKind(this.label);
  final String label;

  bool get isParametric => this != imported;
}

enum AntennaMount {
  ceiling('Ceiling'),
  wall('Wall');

  const AntennaMount(this.label);
  final String label;
}

/// Generated example files: our own, from closed-form models, so the exact
/// 3D answer is known and reconstruction error can be measured. No vendor
/// file is bundled.
enum PatternExample {
  dipole('Half-wave dipole (MSI)'),
  collinear('Collinear, 4 elements, 6° tilt (MSI)'),
  sector('Sector 65° × 65°, 3GPP element (MSI)'),
  tiltedSector('Sector 30° × 30°, 10° mechanical tilt (MSI)'),
  tiltedSectorNsma('Same tilted sector, as NSMA');

  const PatternExample(this.label);
  final String label;

  PatternShape get shape => switch (this) {
    PatternExample.dipole => const DipoleShape(),
    PatternExample.collinear => const CollinearShape(
      elements: 4,
      spacingWl: 0.75,
      tiltDeg: 6,
    ),
    PatternExample.sector => const SectorShape(
      hBeamwidthDeg: 65,
      vBeamwidthDeg: 65,
      frontToBackDb: 30,
      sideLobeDb: 30,
      tiltDeg: 0,
    ),
    PatternExample.tiltedSector ||
    PatternExample.tiltedSectorNsma => const SectorShape(
      hBeamwidthDeg: 30,
      vBeamwidthDeg: 30,
      frontToBackDb: 25,
      sideLobeDb: 20,
      tiltDeg: 10,
    ),
  };

  String fileText(PatternCuts cuts) => switch (this) {
    PatternExample.dipole => writeMsi(cuts, name: 'Generated dipole'),
    PatternExample.collinear => writeMsi(
      cuts,
      name: 'Generated collinear 4x0.75',
      tilt: 'ELECTRICAL 6',
    ),
    PatternExample.sector => writeMsi(cuts, name: 'Generated sector 65x65'),
    PatternExample.tiltedSector => writeMsi(
      cuts,
      name: 'Generated sector 30x30',
      tilt: 'MECHANICAL 10',
    ),
    PatternExample.tiltedSectorNsma => writeNsma(
      cuts,
      model: 'Generated sector 30x30, 10 deg mechanical tilt',
    ),
  };
}

/// Ranges of the controls.
const double kOmniGainMin = 2.15;
const double kOmniGainMax = 15;
const double kOmniTiltMax = 15;
const int kCollinearMaxElements = 8;
const double kSpacingMin = 0.25;
const double kSpacingMax = 1.0;
const double kCollinearTiltMax = 15;
const double kHBeamMin = 15;
const double kHBeamMax = 180;
const double kVBeamMin = 10;
const double kVBeamMax = 120;
const double kLevelMin = 10; // front-to-back and side-lobe level, dB
const double kLevelMax = 40;
const double kSectorTiltMax = 30;
const double kShapingMin = 0.5;
const double kShapingMax = 2;

/// Reconstruction error of both methods against a known truth.
class MethodErrors {
  const MethodErrors(this.summing, this.crossWeighted);
  final ReconstructionError summing;
  final ReconstructionError crossWeighted;

  ReconstructionError of(ReconstructionMethod m) =>
      m == ReconstructionMethod.summing ? summing : crossWeighted;
}

/// Everything the stage and the readouts show for one set of inputs.
class PatternResult {
  PatternResult({
    required this.grid,
    required this.estimated,
    this.parsed,
    this.errors,
  }) : cuts = grid.toCuts();

  final GainGrid grid;
  final PatternCuts cuts;

  /// True for an imported file: the 3D is estimated from two cuts.
  final bool estimated;
  final ParsedPattern? parsed;

  /// Present only for a generated example (the exact 3D is known).
  final MethodErrors? errors;

  late final double topDbi = scaleTopDbi(grid.peakDbi);
  late final ({double dbi, int theta, int phi}) worstRear = grid.worstRear();
}

class AntennaPatternLab extends ChangeNotifier {
  AntennaPatternLab({AntennaModelKind initialKind = AntennaModelKind.omni})
    : _kind = initialKind;

  AntennaModelKind _kind;
  AntennaMount _mount = AntennaMount.ceiling;

  double _omniGainDbi = 8;
  double _omniTiltDeg = 0;

  int _elements = 4;
  double _spacingWl = 0.75;
  double _collinearTiltDeg = 0;

  double _hBeamDeg = 65;
  double _vBeamDeg = 65;
  double _frontToBackDb = 30;
  double _sideLobeDb = 30;
  double _sectorTiltDeg = 0;

  String _importText = '';
  int _importTextRevision = 0;
  ParsedPattern? _parsed;
  String? _importError;
  PatternExample? _example;
  String? _exampleText;
  GainGrid? _exampleTruth;
  MethodErrors? _exampleErrors;
  ReconstructionMethod _method = ReconstructionMethod.summing;
  double _shaping = 1;

  double _polarizationDeg = 0;

  int _revision = 0;

  /// The camera. Rotation and zoom live here and never touch [revision].
  final ValueNotifier<OrbitView> view = ValueNotifier<OrbitView>(
    OrbitView.initial,
  );

  AntennaModelKind get kind => _kind;
  AntennaMount get mount => _mount;
  double get omniGainDbi => _omniGainDbi;
  double get omniTiltDeg => _omniTiltDeg;
  int get elements => _elements;
  double get spacingWl => _spacingWl;
  double get collinearTiltDeg => _collinearTiltDeg;
  double get hBeamDeg => _hBeamDeg;
  double get vBeamDeg => _vBeamDeg;
  double get frontToBackDb => _frontToBackDb;
  double get sideLobeDb => _sideLobeDb;
  double get sectorTiltDeg => _sectorTiltDeg;
  String get importText => _importText;

  /// Bumped when the import text is replaced from outside the text field (an
  /// example), so the field can pick the new text up.
  int get importTextRevision => _importTextRevision;
  ParsedPattern? get parsed => _parsed;
  String? get importError => _importError;
  PatternExample? get example => _example;
  ReconstructionMethod get method => _method;
  double get shaping => _shaping;
  double get polarizationDeg => _polarizationDeg;
  int get revision => _revision;

  /// The example whose exact 3D is known, while the loaded text is still
  /// exactly the generated file.
  bool get hasTruth =>
      _exampleTruth != null && _importText == _exampleText && _parsed != null;

  /// ITU 31,000 estimate of the directional model's gain from its beamwidths.
  double get directionalBeamwidthGainDbi =>
      gainFromBeamwidthsDbi(_hBeamDeg, _vBeamDeg);

  double get polarizationLossDb => polarizationMismatchLossDb(_polarizationDeg);

  /// Whether the 3D is turned 90° from the pattern's own frame for [mount].
  /// An omni's own frame is ceiling-mounted (axis vertical); a directional's
  /// is wall-mounted (front horizontal). An imported file counts as an omni
  /// when its horizontal cut stays within 3 dB.
  bool get rotatedForMount {
    final bool omniFrame = switch (_kind) {
      AntennaModelKind.directional => false,
      AntennaModelKind.imported => _parsed?.cuts.looksOmni ?? false,
      _ => true,
    };
    final AntennaMount native = omniFrame
        ? AntennaMount.ceiling
        : AntennaMount.wall;
    return _mount != native;
  }

  // ── Derived, cached per revision ────────────────────────────────────────

  PatternResult? _result;
  int _resultRevision = -1;
  PatternMesh? _mesh;
  int _meshRevision = -1;

  /// Null only in the imported mode before anything was read.
  PatternResult? get result {
    if (_resultRevision != _revision) {
      _result = _compute();
      _resultRevision = _revision;
    }
    return _result;
  }

  PatternMesh? get mesh {
    if (_meshRevision != _revision) {
      final PatternResult? r = result;
      _mesh = r == null
          ? null
          : PatternMesh.build(r.grid, rotated: rotatedForMount);
      _meshRevision = _revision;
    }
    return _mesh;
  }

  PatternShape? get _parametricShape => switch (_kind) {
    AntennaModelKind.dipole => const DipoleShape(),
    AntennaModelKind.omni => OmniF1336Shape(
      gainDbi: _omniGainDbi,
      tiltDeg: _omniTiltDeg,
    ),
    AntennaModelKind.collinear => CollinearShape(
      elements: _elements,
      spacingWl: _spacingWl,
      tiltDeg: _collinearTiltDeg,
    ),
    AntennaModelKind.directional => SectorShape(
      hBeamwidthDeg: _hBeamDeg,
      vBeamwidthDeg: _vBeamDeg,
      frontToBackDb: _frontToBackDb,
      sideLobeDb: _sideLobeDb,
      tiltDeg: _sectorTiltDeg,
    ),
    AntennaModelKind.imported => null,
  };

  PatternResult? _compute() {
    final PatternShape? shape = _parametricShape;
    if (shape != null) {
      return PatternResult(grid: GainGrid.fromShape(shape), estimated: false);
    }
    final ParsedPattern? p = _parsed;
    if (p == null) return null;
    double peak = p.gainDbi;
    if (_shaping != 1) {
      // A what-if: keep the file's efficiency, move the gain by the change
      // in directivity, so the reshaped pattern radiates the same power.
      final double d1 = GainGrid.fromShape(
        ReconstructedShape(p.cuts, _method),
      ).directivityDbi;
      final double dp = GainGrid.fromShape(
        ReconstructedShape(p.cuts, _method, shaping: _shaping),
      ).directivityDbi;
      peak += dp - d1;
    }
    return PatternResult(
      grid: GainGrid.fromShape(
        ReconstructedShape(p.cuts, _method, shaping: _shaping),
        peakDbi: peak,
      ),
      estimated: true,
      parsed: p,
      errors: hasTruth ? _exampleErrors : null,
    );
  }

  void _changed() {
    _revision++;
    notifyListeners();
  }

  // ── Setters ─────────────────────────────────────────────────────────────

  void setKind(AntennaModelKind k) {
    if (k == _kind) return;
    _kind = k;
    _changed();
  }

  void setMount(AntennaMount m) {
    if (m == _mount) return;
    _mount = m;
    _changed();
  }

  void setOmniGain(double v) {
    _omniGainDbi = v.clamp(kOmniGainMin, kOmniGainMax);
    _changed();
  }

  void setOmniTilt(double v) {
    _omniTiltDeg = v.clamp(0, kOmniTiltMax);
    _changed();
  }

  void setElements(int n) {
    _elements = n.clamp(1, kCollinearMaxElements);
    _changed();
  }

  void setSpacing(double v) {
    _spacingWl = v.clamp(kSpacingMin, kSpacingMax);
    _changed();
  }

  void setCollinearTilt(double v) {
    _collinearTiltDeg = v.clamp(0, kCollinearTiltMax);
    _changed();
  }

  void setHBeam(double v) {
    _hBeamDeg = v.clamp(kHBeamMin, kHBeamMax);
    _changed();
  }

  void setVBeam(double v) {
    _vBeamDeg = v.clamp(kVBeamMin, kVBeamMax);
    _changed();
  }

  /// Sets both beamwidths from a target gain with the ITU 31,000 rule,
  /// keeping their ratio, so the gain slider reshapes the beam.
  void setDirectionalGain(double dbi) {
    final double ratio = _hBeamDeg / _vBeamDeg;
    final double product =
        kItuPracticalConstant / math.pow(10, dbi / 10).toDouble();
    double v = math.sqrt(product / ratio);
    double h = v * ratio;
    h = h.clamp(kHBeamMin, kHBeamMax);
    v = v.clamp(kVBeamMin, kVBeamMax);
    _hBeamDeg = h.roundToDouble();
    _vBeamDeg = v.roundToDouble();
    _changed();
  }

  void setFrontToBack(double v) {
    _frontToBackDb = v.clamp(kLevelMin, kLevelMax);
    _changed();
  }

  void setSideLobe(double v) {
    _sideLobeDb = v.clamp(kLevelMin, kLevelMax);
    _changed();
  }

  void setSectorTilt(double v) {
    _sectorTiltDeg = v.clamp(0, kSectorTiltMax);
    _changed();
  }

  void setMethod(ReconstructionMethod m) {
    if (m == _method) return;
    _method = m;
    _changed();
  }

  void setShaping(double v) {
    _shaping = v.clamp(kShapingMin, kShapingMax);
    _changed();
  }

  void setPolarization(double deg) {
    _polarizationDeg = deg.clamp(0, 90);
    notifyListeners(); // no pattern change: nothing to rebuild
  }

  /// Reads pasted pattern text. On an error the last good pattern stays on
  /// screen and [importError] says why.
  void importPattern(String text) {
    _importText = text;
    if (text.trim().isEmpty) {
      _importError =
          'Nothing to read yet. Paste the text of an MSI or NSMA '
          'file, or pick an example.';
      _changed();
      return;
    }
    try {
      _parsed = parsePatternText(text);
      _importError = null;
      _shaping = 1;
    } on PatternParseException catch (e) {
      _importError = e.message;
    }
    _kind = AntennaModelKind.imported;
    _changed();
  }

  /// Loads one of our generated files, keeping its exact 3D as the truth.
  void loadExample(PatternExample e) {
    final GainGrid truth = GainGrid.fromShape(e.shape);
    final PatternCuts cuts = truth.toCuts();
    final String text = e.fileText(cuts);
    _example = e;
    _exampleText = text;
    _exampleTruth = truth;
    _importTextRevision++;
    importPattern(text);
    final ParsedPattern? p = _parsed;
    _exampleErrors = p == null ? null : _errorsAgainst(truth, p);
    _changed();
  }

  static MethodErrors _errorsAgainst(GainGrid truth, ParsedPattern p) {
    ReconstructionError of(ReconstructionMethod m) =>
        ReconstructionError.between(
          truth,
          GainGrid.fromShape(ReconstructedShape(p.cuts, m), peakDbi: p.gainDbi),
        );
    return MethodErrors(
      of(ReconstructionMethod.summing),
      of(ReconstructionMethod.crossWeighted),
    );
  }

  /// Writes the current parametric antenna as an MSI file and imports it,
  /// so the student can see what two cuts lose.
  void rebuildFromTwoCuts() {
    final PatternShape? shape = _parametricShape;
    if (shape == null) return;
    final GainGrid truth = GainGrid.fromShape(shape);
    final PatternCuts cuts = truth.toCuts();
    final String text = writeMsi(
      cuts,
      name: 'This ${_kind.label.toLowerCase()}',
    );
    _example = null;
    _exampleText = text;
    _exampleTruth = truth;
    _importTextRevision++;
    importPattern(text);
    final ParsedPattern? p = _parsed;
    _exampleErrors = p == null ? null : _errorsAgainst(truth, p);
    _changed();
  }

  void resetView() {
    stopSpin();
    view.value = OrbitView.initial;
  }

  // ── Spin (the presenter's Play) ─────────────────────────────────────────
  //
  // A slow turn of the 3D view about the vertical, started only by the user
  // (Space in presenter mode), so reduced motion (GL-003 §8.8) has nothing
  // to stop: nothing moves unless asked. The Ticker is built directly, not
  // from a widget's TickerProvider, because the phone route under the
  // presenter is muted and the spin must keep going there.

  /// Degrees the view turns per second while spinning.
  static const double spinDegPerSecond = 30;

  /// Degrees one Step (Right arrow) turns the view.
  static const double stepDeg = 15;

  Ticker? _spinTicker;
  Duration _lastSpinTick = Duration.zero;
  bool _spinning = false;
  bool _disposed = false;

  bool get spinning => _spinning;

  void toggleSpin() => _spinning ? stopSpin() : startSpin();

  void startSpin() {
    if (_spinning || _disposed) return;
    _spinning = true;
    _lastSpinTick = Duration.zero;
    (_spinTicker ??= Ticker(_onSpin, debugLabel: 'antenna-spin')).start();
    notifyListeners();
  }

  void stopSpin() {
    if (!_spinning) return;
    _spinning = false;
    _spinTicker?.stop();
    if (!_disposed) notifyListeners();
  }

  void _onSpin(Duration elapsed) {
    final double dt = (elapsed - _lastSpinTick).inMicroseconds / 1e6;
    _lastSpinTick = elapsed;
    // A long stall (the app in the background) does not jump the view.
    view.value = view.value.rotated(-spinDegPerSecond * dt.clamp(0, 0.1), 0);
  }

  /// One step of the view, the same way the spin turns.
  void stepView() => view.value = view.value.rotated(-stepDeg, 0);

  // ── Presenter keys ──────────────────────────────────────────────────────

  /// What Up and Down move for the current antenna, or null (the dipole
  /// has no parameter; an import has nothing to shape until it is read).
  String? get mainSliderLabel => switch (_kind) {
    AntennaModelKind.dipole => null,
    AntennaModelKind.omni || AntennaModelKind.directional => 'Gain',
    AntennaModelKind.collinear => 'Elements',
    AntennaModelKind.imported => _parsed == null ? null : 'Shape',
  };

  /// The main slider one notch: 1 dB of gain, one element, or 0.05 of
  /// shape.
  void nudgeMain(int dir) {
    switch (_kind) {
      case AntennaModelKind.dipole:
        return;
      case AntennaModelKind.omni:
        setOmniGain(_omniGainDbi + dir);
      case AntennaModelKind.collinear:
        setElements(_elements + dir);
      case AntennaModelKind.directional:
        setDirectionalGain(
          (directionalBeamwidthGainDbi + dir).clamp(3.0, 21.0),
        );
      case AntennaModelKind.imported:
        if (_parsed != null) setShaping(_shaping + 0.05 * dir);
    }
  }

  /// Presenter keys: Space spins the 3D view, Right turns it one step, R
  /// resets it, Up and Down move the antenna's main setting.
  PresenterActions get presenterActions {
    final String? label = mainSliderLabel;
    return PresenterActions(
      playPause: toggleSpin,
      step: stepView,
      reset: resetView,
      sliderDown: label == null ? null : () => nudgeMain(-1),
      sliderUp: label == null ? null : () => nudgeMain(1),
      sliderLabel: label,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _spinTicker?.dispose();
    view.dispose();
    super.dispose();
  }
}
