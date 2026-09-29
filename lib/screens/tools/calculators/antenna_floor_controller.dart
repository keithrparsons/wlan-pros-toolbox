// State for the Floor coverage view of the Wi-Fi Classroom "Antenna Pattern"
// tool (antenna-pattern), spec 46 (myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/46-mount-height.md).
//
// The antenna itself stays in AntennaPatternLab: the Floor coverage view
// shows whatever antenna the lab holds, with its mounting. This object adds
// only what the floor needs (mount height, both transmit powers, band,
// path-loss exponent, where the client stands) and which view the stage
// shows. It listens to the lab, so a gain slider moved in the antenna card
// redraws the floor.
//
// PRESETS are our own, from Keith's teaching (PLAN.md, Feature 7), each one
// thing away from the 9 m dipole so the class sees one change at a time:
// the office ceiling; the same dipole on a warehouse ceiling; a higher-gain
// omni there; more power there; a directional aimed down. Every slider stays
// free afterwards, and the preset picker then reads "Your own settings".
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/floor_coverage_model.dart';
import '../../../services/wifi_lab/uplink_downlink_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';
import 'antenna_pattern_model.dart';

export '../../../services/wifi_lab/floor_coverage_model.dart';

/// What the Antenna Pattern stage shows.
enum AntennaStageView {
  pattern('3D pattern'),
  floor('Floor coverage');

  const AntennaStageView(this.label);
  final String label;
}

/// A starting point for the floor view. Each sets the antenna, its mounting
/// (ceiling), the mount height and the AP's transmit power, and nothing else.
enum FloorPreset {
  office(
    label: 'Office, dipole',
    heightM: 3,
    kind: AntennaModelKind.dipole,
    apTxDbm: 20,
  ),
  warehouseDipole(
    label: 'Warehouse, dipole',
    heightM: 9,
    kind: AntennaModelKind.dipole,
    apTxDbm: 20,
  ),
  warehouseHighGainOmni(
    label: 'Warehouse, 8 dBi omni',
    heightM: 9,
    kind: AntennaModelKind.omni,
    apTxDbm: 20,
  ),
  warehouseMorePower(
    label: 'Warehouse, +6 dB power',
    heightM: 9,
    kind: AntennaModelKind.dipole,
    apTxDbm: 26,
  ),
  warehouseDirectional(
    label: 'Warehouse, directional',
    heightM: 9,
    kind: AntennaModelKind.directional,
    apTxDbm: 20,
  );

  const FloorPreset({
    required this.label,
    required this.heightM,
    required this.kind,
    required this.apTxDbm,
  });

  final String label;
  final double heightM;
  final AntennaModelKind kind;
  final double apTxDbm;

  /// The higher-gain omni's gain, dBi (Omni, set by gain).
  static const double omniGainDbi = 8;

  /// The directional's beamwidths, degrees, and floors, dB (the lab's own
  /// defaults: a 65 by 65 degree patch or sector).
  static const double directionalBeamDeg = 65;
  static const double directionalFloorDb = 30;

  /// One sentence on what this step shows, for the controls.
  String get point => switch (this) {
    FloorPreset.office =>
      'A dipole on a 3 m office ceiling. The floor is close to the horizon of '
          'the pattern almost everywhere, so it is well covered.',
    FloorPreset.warehouseDipole =>
      'The same dipole on a 9 m warehouse ceiling. Straight down is the dipole\'s '
          'null, so a hole opens under the AP and the near floor gets less.',
    FloorPreset.warehouseHighGainOmni =>
      'An 8 dBi omni at 9 m. A higher-gain omni takes gain from the downward angles and puts it at '
          'the horizon, over the floor\'s head. The floor under it gets less.',
    FloorPreset.warehouseMorePower =>
      'The 9 m dipole with the AP 6 dB louder. More power lifts every '
          'downlink number by 6 dB. The uplink does not '
          'move: the AP hears the clients no better than before.',
    FloorPreset.warehouseDirectional =>
      'A directional on the 9 m ceiling, aimed at the floor, puts its gain where '
          'the clients are.',
  };
}

/// Ranges of the floor controls.
const double kFloorApTxMin = UdConfig.apTxMin;
const double kFloorApTxMax = UdConfig.apTxMax;
const double kFloorClientTxMin = UdConfig.clientTxMin;
const double kFloorClientTxMax = UdConfig.clientTxMax;
const double kFloorExponentMin = UdConfig.exponentMin;
const double kFloorExponentMax = UdConfig.exponentMax;

/// The client position slider's reach along the floor, m.
const double kFloorClientMaxM = 35;

/// The readout distances along the floor, m.
const List<double> kFloorReadoutsM = <double>[0, 10, 20, 30];

class FloorCoverageController extends ChangeNotifier {
  FloorCoverageController({
    required this.lab,
    AntennaStageView initialView = AntennaStageView.pattern,
  }) : _view = initialView {
    lab.addListener(_labChanged);
  }

  final AntennaPatternLab lab;

  AntennaStageView _view;
  double _heightM = FloorPreset.office.heightM;
  double _apTxDbm = UdConfig.defaultApTxDbm;
  double _clientTxDbm = UdConfig.defaultClientTxDbm;
  WifiBand _band = WifiBand.band5;
  double _exponent = UdConfig.defaultExponent;
  double _clientXM = 10;

  AntennaStageView get view => _view;
  double get heightM => _heightM;
  double get apTxDbm => _apTxDbm;
  double get clientTxDbm => _clientTxDbm;
  WifiBand get band => _band;
  double get exponent => _exponent;
  double get clientXM => _clientXM;

  /// The client's antenna gain, dBi: fixed, the Uplink vs Downlink default
  /// (a phone-class antenna).
  double get clientGainDbi => UdConfig.defaultClientGainDbi;

  bool get showingFloor => _view == AntennaStageView.floor;

  // ── The link, cached per change ───────────────────────────────────────

  int _revision = 0;
  int _linkRevision = -1;
  int _linkLabRevision = -1;
  FloorLink? _link;
  FloorCell? _cell;

  /// Bumped on every change to what the floor view draws (its own inputs or
  /// the lab's antenna).
  int get revision => _revision + lab.revision;

  void _refresh() {
    if (_linkRevision == _revision && _linkLabRevision == lab.revision) return;
    final PatternResult? r = lab.result;
    _link = r == null
        ? null
        : FloorLink(
            grid: r.grid,
            turned: lab.rotatedForMount,
            heightM: _heightM,
            band: _band,
            apTxDbm: _apTxDbm,
            clientTxDbm: _clientTxDbm,
            clientGainDbi: clientGainDbi,
            exponent: _exponent,
          );
    _cell = _link?.cell();
    _linkRevision = _revision;
    _linkLabRevision = lab.revision;
  }

  /// Null only while the lab has no pattern (an import not yet read).
  FloorLink? get link {
    _refresh();
    return _link;
  }

  /// The floor at or above -67 dBm, or null with no pattern.
  FloorCell? get cell {
    _refresh();
    return _cell;
  }

  /// The point where the client stands.
  FloorPoint? get client => link?.at(_clientXM);

  /// The AP antenna's gain toward the client as Uplink vs Downlink can take
  /// it (its AP gain slider runs 0 to 8 dBi).
  double? get carriedApGainDbi {
    final FloorPoint? p = client;
    if (p == null) return null;
    return p.gainDbi.clamp(UdConfig.apGainMin, UdConfig.apGainMax).toDouble();
  }

  /// True when the gain toward the client falls outside what Uplink vs
  /// Downlink takes, so the carried value differs from the one shown here.
  bool get carriedGainClamped {
    final FloorPoint? p = client;
    final double? c = carriedApGainDbi;
    return p != null && c != null && (p.gainDbi - c).abs() > 0.05;
  }

  /// The link to open in Uplink vs Downlink: this band, both powers, the
  /// client's antenna, the exponent, the slant distance to the client and
  /// the AP gain toward it. Built through UdConfig's own setters, so its
  /// ranges apply.
  UdConfig? get uplinkDownlinkConfig {
    final FloorPoint? p = client;
    final double? g = carriedApGainDbi;
    if (p == null || g == null) return null;
    return const UdConfig()
        .withBand(_band)
        .withApGain(g)
        .withApTx(_apTxDbm)
        .withClientTx(_clientTxDbm)
        .withClientGain(clientGainDbi)
        .withExponent(_exponent)
        .withClientDistance(p.slantM);
  }

  // ── Presets ───────────────────────────────────────────────────────────

  /// The preset the current settings equal, or null ("Your own settings").
  FloorPreset? get preset {
    for (final FloorPreset p in FloorPreset.values) {
      if (_matches(p)) return p;
    }
    return null;
  }

  bool _near(double a, double b) => (a - b).abs() < 1e-6;

  bool _matches(FloorPreset p) {
    if (lab.kind != p.kind || lab.mount != AntennaMount.ceiling) return false;
    if (!_near(_heightM, p.heightM) || !_near(_apTxDbm, p.apTxDbm)) {
      return false;
    }
    return switch (p.kind) {
      AntennaModelKind.omni =>
        _near(lab.omniGainDbi, FloorPreset.omniGainDbi) &&
            _near(lab.omniTiltDeg, 0),
      AntennaModelKind.directional =>
        _near(lab.hBeamDeg, FloorPreset.directionalBeamDeg) &&
            _near(lab.vBeamDeg, FloorPreset.directionalBeamDeg) &&
            _near(lab.frontToBackDb, FloorPreset.directionalFloorDb) &&
            _near(lab.sideLobeDb, FloorPreset.directionalFloorDb) &&
            _near(lab.sectorTiltDeg, 0),
      _ => true,
    };
  }

  /// Sets the antenna (in the lab), ceiling mounting, height and AP power.
  /// The client's power, the band, the exponent and the client's place stay
  /// where the reader put them.
  void applyPreset(FloorPreset p) {
    lab.setKind(p.kind);
    lab.setMount(AntennaMount.ceiling);
    switch (p.kind) {
      case AntennaModelKind.omni:
        lab.setOmniGain(FloorPreset.omniGainDbi);
        lab.setOmniTilt(0);
      case AntennaModelKind.directional:
        lab.setHBeam(FloorPreset.directionalBeamDeg);
        lab.setVBeam(FloorPreset.directionalBeamDeg);
        lab.setFrontToBack(FloorPreset.directionalFloorDb);
        lab.setSideLobe(FloorPreset.directionalFloorDb);
        lab.setSectorTilt(0);
      case AntennaModelKind.dipole:
      case AntennaModelKind.collinear:
      case AntennaModelKind.imported:
        break;
    }
    _heightM = p.heightM;
    _apTxDbm = p.apTxDbm;
    _changed();
  }

  /// The next preset after the current one (the first when none matches).
  void nextPreset() {
    final FloorPreset? now = preset;
    const List<FloorPreset> all = FloorPreset.values;
    applyPreset(now == null ? all.first : all[(now.index + 1) % all.length]);
  }

  // ── Setters ───────────────────────────────────────────────────────────

  void _changed() {
    _revision++;
    notifyListeners();
  }

  void _labChanged() => notifyListeners();

  void setView(AntennaStageView v) {
    if (v == _view) return;
    _view = v;
    _changed();
  }

  void toggleView() =>
      setView(showingFloor ? AntennaStageView.pattern : AntennaStageView.floor);

  /// Mount height, m, held to the slider's 0.5 m notches.
  void setHeight(double m) {
    final double snapped =
        (m.clamp(kMountHeightMinM, kMountHeightMaxM) / kMountHeightStepM)
            .roundToDouble() *
        kMountHeightStepM;
    if (_near(snapped, _heightM)) return;
    _heightM = snapped;
    _changed();
  }

  void nudgeHeight(int dir) => setHeight(_heightM + dir * kMountHeightStepM);

  void setApTx(double v) {
    _apTxDbm = v.clamp(kFloorApTxMin, kFloorApTxMax).roundToDouble();
    _changed();
  }

  void setClientTx(double v) {
    _clientTxDbm = v
        .clamp(kFloorClientTxMin, kFloorClientTxMax)
        .roundToDouble();
    _changed();
  }

  void setBand(WifiBand b) {
    if (b == _band) return;
    _band = b;
    _changed();
  }

  void setExponent(double v) {
    _exponent =
        (v.clamp(kFloorExponentMin, kFloorExponentMax) * 10).roundToDouble() /
        10;
    _changed();
  }

  void setClientX(double m) {
    _clientXM = (m.clamp(0, kFloorClientMaxM) * 10).roundToDouble() / 10;
    _changed();
  }

  // ── Presenter keys ────────────────────────────────────────────────────

  static final LogicalKeyboardKey viewKey = LogicalKeyboardKey.keyV;

  PresenterExtraKey get _viewKey => PresenterExtraKey(
    key: viewKey,
    keyLabel: 'V',
    description: showingFloor ? 'Show the 3D pattern' : 'Show floor coverage',
    onPressed: toggleView,
  );

  /// The floor view's keys: Up and Down move the mount height, Right steps
  /// to the next preset, R goes back to the first, V switches the view.
  /// The 3D view keeps the lab's keys and adds V.
  PresenterActions get presenterActions {
    if (!showingFloor) {
      final PresenterActions a = lab.presenterActions;
      return PresenterActions(
        playPause: a.playPause,
        playPauseLabel: a.playPauseLabel,
        step: a.step,
        stepLabel: a.stepLabel,
        reset: a.reset,
        sliderDown: a.sliderDown,
        sliderUp: a.sliderUp,
        sliderLabel: a.sliderLabel,
        extra: <PresenterExtraKey>[...a.extra, _viewKey],
      );
    }
    return PresenterActions(
      step: nextPreset,
      stepLabel: 'Next preset',
      reset: () => applyPreset(FloorPreset.values.first),
      sliderDown: () => nudgeHeight(-1),
      sliderUp: () => nudgeHeight(1),
      sliderLabel: 'Mount height',
      extra: <PresenterExtraKey>[_viewKey],
    );
  }

  /// What the presenter layout depends on: the view, the antenna (the floor
  /// panel names it) and the lab's slider. The kind is needed on its own:
  /// an omni and a directional share the slider name "Gain".
  Object get presenterKey => (_view, lab.kind, lab.mainSliderLabel);

  @override
  void dispose() {
    lab.removeListener(_labChanged);
    super.dispose();
  }
}

// ── Formatting ───────────────────────────────────────────────────────────

/// A length, metric first and imperial in parentheses: "9.0 m (29.5 ft)".
/// Under 20 m one decimal, beyond that whole numbers.
String fmtFloorLength(double m) {
  final double ft = m / 0.3048;
  if (m < 20) {
    return '${m.toStringAsFixed(1)} m (${ft.toStringAsFixed(1)} ft)';
  }
  return '${m.round()} m (${ft.round()} ft)';
}

/// The floor target, whole dB: "\u221267 dBm".
String get fmtFloorTarget =>
    '${kFloorTargetDbm.round().toString().replaceFirst('-', '\u2212')} dBm';

/// A level in dBm with a true minus sign, one decimal.
String fmtFloorDbm(double v) {
  final String s = v.toStringAsFixed(1);
  final String t = s == '-0.0' ? '0.0' : s;
  return '${t.startsWith('-') ? '−${t.substring(1)}' : t} dBm';
}

/// A gain or loss in dB with a true minus sign, one decimal.
String fmtFloorDb(double v) {
  final String s = v.toStringAsFixed(1);
  final String t = s == '-0.0' ? '0.0' : s;
  return t.startsWith('-') ? '−${t.substring(1)}' : t;
}

/// Where a readout distance sits: "Directly below" or "10 m (33 ft) out".
String fmtFloorWhere(double xM) =>
    xM == 0 ? 'Directly below' : '${fmtFloorLength(xM)} out';

/// The floor cell in words for readouts and copy.
String floorCellWords(FloorCell c) {
  final double? r = c.radiusM;
  if (r == null) {
    return 'None: no floor within ${kFloorSearchM.round()} m reaches '
        '$fmtFloorTarget';
  }
  final String reach = c.reachesSearchEdge
      ? 'beyond ${kFloorSearchM.round()} m'
      : fmtFloorLength(r);
  return reach;
}
