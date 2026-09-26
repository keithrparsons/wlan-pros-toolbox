// State for the Wi-Fi Classroom Room Propagation simulator (room-propagation).
//
// One ChangeNotifier holds every input and the computed maps, so the screen's
// halves stay independent widgets: RoomPropagationStage (the plan, the heat
// map, the close-up) and RoomPropagationControls / RoomPropagationReadouts
// each listen to the same controller. The phone layout stacks them; a
// presenter layout can put them side by side without either knowing about the
// other.
//
// COMPUTE. The two maps are computed only when what they depend on changes:
//   - the average map: walls, AP, band/channel, polarization, reflection
//     order, diffraction. NOT the EIRP (it is stored as path gain and the
//     EIRP is added when drawn) and NOT the client.
//   - the close-up: the same, plus the client (it is centered on it).
// Each run goes to a background isolate through [RoomFieldRunner] (Flutter's
// `compute`), because at reflection order 2 the maps take a few hundred
// milliseconds. While one run is in flight, further changes are coalesced
// into one follow-up run, so dragging the AP never queues a backlog. The
// client readouts are one point each and are computed here, synchronously.
//
// All physics lives in lib/services/wifi_lab/room_propagation_model.dart.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/room_propagation_model.dart';
import '../../../services/wifi_lab/wall_slab_physics.dart';
import '../../../widgets/presenter/presenter_actions.dart';
import 'room_propagation_presets.dart';

/// Stable catalog tool id: backs the route, the help entry and the tests.
const String kRoomPropagationToolId = 'room-propagation';

/// Runs one field job. The default sends it to a background isolate; tests
/// pass a synchronous one.
typedef RoomFieldRunner = Future<RoomFieldResult> Function(RoomFieldJob job);

Future<RoomFieldResult> _isolateRunner(RoomFieldJob job) =>
    compute(computeRoomField, job);

/// Average-map cell size, m (spec: state the grid size).
const double kRoomCellM = 0.2;

/// Most walls a plan may hold. Second-order reflections grow with the square
/// of the wall count: 16 walls at two bounces measured 1.9 s for the map and
/// 1.7 s for the close-up on the build Mac (AOT, 2026-09-25); the presets at
/// two bounces take 0.2 to 0.8 s and 0.1 to 0.7 s. A phone is slower; the
/// plan says Computing meanwhile and the UI never blocks.
const int kMaxWalls = 16;

/// Shortest wall the draw tool makes, m.
const double kMinWallM = 0.3;

/// Drawing snaps to this grid, m.
const double kSnapM = 0.1;

/// A drawn end snaps onto an existing wall end this close, m.
const double kEndpointSnapM = 0.3;

/// EIRP slider bounds, dBm.
const double kEirpMin = 0;
const double kEirpMax = 36;

/// What a drag or tap on the plan does.
enum RoomTool {
  move('Move', 'Move the AP and client'),
  wall('Wall', 'Draw walls'),
  door('Door', 'Add doorways'),
  select('Select', 'Select a wall');

  const RoomTool(this.label, this.menuLabel);

  final String label;
  final String menuLabel;
}

/// Which marker a drag is moving.
enum RoomMarker { ap, client }

/// Default channel per band (the same as Wi-Fi Through a Wall: 6, 100, 117,
/// which sit at 2.437, 5.500 and 6.535 GHz).
int roomDefaultChannel(WifiBand band) => switch (band) {
  WifiBand.band24 => 6,
  WifiBand.band5 => 100,
  WifiBand.band6 => 117,
};

/// One row of the three-band comparison.
typedef RoomBandRow = ({WifiBand band, int channel, PointReport report});

class RoomPropagationController extends ChangeNotifier {
  RoomPropagationController({
    RoomFieldRunner? runner,
    int presetIndex = 0,
    bool autoCompute = true,
  }) : _runner = runner ?? _isolateRunner {
    _applyPreset(presetIndex);
    if (autoCompute) _request(average: true);
  }

  final RoomFieldRunner _runner;
  bool _disposed = false;

  // ── Plan ────────────────────────────────────────────────────────────────

  /// The presets plus an empty plan to draw on.
  static final List<RoomPreset> presets = <RoomPreset>[
    ...kRoomPresets,
    const RoomPreset(
      label: 'Empty plan',
      lesson:
          'No walls at all: free space. Draw your own walls with the Wall '
          'tool.',
      widthM: kPlanMaxWidthM,
      heightM: kPlanMaxHeightM,
      walls: <RoomWall>[],
      ap: P2(6, 7.5),
      client: P2(14, 7.5),
    ),
  ];

  int _preset = 0;
  late double _widthM;
  late double _heightM;
  late List<RoomWall> _walls;
  late P2 _ap;
  late P2 _client;

  int get presetIndex => _preset;
  RoomPreset get preset => presets[_preset];
  double get widthM => _widthM;
  double get heightM => _heightM;
  List<RoomWall> get walls => List<RoomWall>.unmodifiable(_walls);
  P2 get ap => _ap;
  P2 get client => _client;

  void _applyPreset(int i) {
    _preset = i.clamp(0, presets.length - 1);
    final RoomPreset p = presets[_preset];
    _widthM = p.widthM;
    _heightM = p.heightM;
    _walls = List<RoomWall>.of(p.walls);
    _ap = p.ap;
    _client = p.client;
    _selected = null;
    _message = null;
    _draft = null;
  }

  /// Loads preset [i] (also used to reset the current one).
  void loadPreset(int i) {
    _applyPreset(i);
    _geometryChanged();
  }

  P2 _clampToPlan(P2 p) => P2(
    p.x.clamp(0.0, _widthM).toDouble(),
    p.y.clamp(0.0, _heightM).toDouble(),
  );

  void moveAp(P2 p) {
    final P2 c = _clampToPlan(p);
    if (c == _ap) return;
    _ap = c;
    _geometryChanged();
  }

  void moveClient(P2 p) {
    final P2 c = _clampToPlan(p);
    if (c == _client) return;
    _client = c;
    _message = null;
    _reports = null;
    _request(average: false);
    notifyListeners();
  }

  // ── Radio ───────────────────────────────────────────────────────────────

  WifiBand _band = WifiBand.band24;
  int _channel = 6;
  double _eirp = 20;
  Polarization _pol = Polarization.te;
  int _order = 1;
  bool _diffraction = true;

  WifiBand get band => _band;
  int get channel => _channel;
  double get eirpDbm => _eirp;
  Polarization get polarization => _pol;
  int get reflectionOrder => _order;
  bool get diffraction => _diffraction;

  /// Channel center frequency, MHz.
  int get freqMHz => centerFrequencyMHzForBand(_band, _channel)!;
  double get lambda => 299792458 / (freqMHz * 1e6);

  set band(WifiBand b) {
    if (b == _band) return;
    _band = b;
    _channel = roomDefaultChannel(b);
    _radioChanged();
  }

  set channel(int c) {
    if (c == _channel) return;
    _channel = c;
    _radioChanged();
  }

  /// EIRP moves the whole map up or down by the same dB; nothing recomputes.
  set eirpDbm(double v) {
    final double c = v.clamp(kEirpMin, kEirpMax).roundToDouble();
    if (c == _eirp) return;
    _eirp = c;
    notifyListeners();
  }

  set polarization(Polarization p) {
    if (p == _pol) return;
    _pol = p;
    _radioChanged();
  }

  set reflectionOrder(int o) {
    final int c = o.clamp(0, 2);
    if (c == _order) return;
    _order = c;
    _radioChanged();
  }

  set diffraction(bool v) {
    if (v == _diffraction) return;
    _diffraction = v;
    _radioChanged();
  }

  RoomRadio radioAt(double freqMHz) => RoomRadio(
    freqMHz: freqMHz,
    polarization: _pol,
    reflectionOrder: _order,
    diffraction: _diffraction,
  );

  RoomRadio get radio => radioAt(freqMHz.toDouble());

  // ── Overlays ────────────────────────────────────────────────────────────

  bool _fresnel = true;
  bool _shadows = true;
  bool _closeUp = true;

  bool get showFresnel => _fresnel;
  bool get showShadows => _shadows;
  bool get showCloseUp => _closeUp;

  set showFresnel(bool v) => _setFlag(() => _fresnel = v);
  set showShadows(bool v) => _setFlag(() => _shadows = v);
  set showCloseUp(bool v) {
    if (v == _closeUp) return;
    _closeUp = v;
    if (v) _request(average: false);
    notifyListeners();
  }

  void _setFlag(VoidCallback f) {
    f();
    notifyListeners();
  }

  // ── Editing ─────────────────────────────────────────────────────────────

  RoomTool _tool = RoomTool.move;
  int? _selected;
  WallMaterial _newMaterial = WallMaterial.plasterboard;
  double _newThicknessMm = 13;
  (P2, P2)? _draft;
  String? _message;

  RoomTool get tool => _tool;
  set tool(RoomTool t) {
    if (t == _tool) return;
    _tool = t;
    _draft = null;
    _message = null;
    notifyListeners();
  }

  /// Index of the selected wall, if any.
  int? get selectedWall =>
      (_selected != null && _selected! < _walls.length) ? _selected : null;

  RoomWall? get selected {
    final int? i = selectedWall;
    return i == null ? null : _walls[i];
  }

  void selectWall(int? i) {
    final int? c = (i != null && i >= 0 && i < _walls.length) ? i : null;
    if (c == _selected) return;
    _selected = c;
    _message = null;
    notifyListeners();
  }

  /// Material and thickness for the next wall drawn.
  WallMaterial get newMaterial => _newMaterial;
  double get newThicknessMm => _newThicknessMm;

  /// The wall being dragged out, if any.
  (P2, P2)? get draft => _draft;

  /// A one-line note about the last edit that did not happen (too short,
  /// too many walls, no wall there). Cleared by the next edit.
  String? get message => _message;

  /// Sets the material of the selected wall, or of new walls when none is
  /// selected.
  void setMaterial(WallMaterial m) {
    final int? i = selectedWall;
    if (i == null) {
      _newMaterial = m;
      notifyListeners();
      return;
    }
    _replace(i, _walls[i].copyWith(material: m));
  }

  /// Sets the thickness of the selected wall, or of new walls when none is
  /// selected. Callers validate 1 to 500 mm first.
  void setThicknessMm(double mm) {
    final int? i = selectedWall;
    if (i == null) {
      _newThicknessMm = mm;
      notifyListeners();
      return;
    }
    _replace(i, _walls[i].copyWith(thicknessMm: mm));
  }

  WallMaterial get editMaterial => selected?.material ?? _newMaterial;
  double get editThicknessMm => selected?.thicknessMm ?? _newThicknessMm;

  void _replace(int i, RoomWall w) {
    if (_walls[i] == w) return;
    _walls[i] = w;
    _geometryChanged();
  }

  void deleteSelected() {
    final int? i = selectedWall;
    if (i == null) return;
    _walls.removeAt(i);
    _selected = null;
    _geometryChanged();
  }

  /// Adds a doorway to the selected wall at its middle.
  void addDoorToSelected() {
    final int? i = selectedWall;
    if (i == null) return;
    _addDoor(i, _walls[i].length / 2);
  }

  void removeDoorsFromSelected() {
    final int? i = selectedWall;
    if (i == null || _walls[i].doors.isEmpty) return;
    _replace(i, _walls[i].copyWith(doors: const <DoorGap>[]));
  }

  bool _addDoor(int i, double s) {
    final RoomWall w = _walls[i];
    const double half = kDoorWidthM / 2;
    if (w.length < kDoorWidthM + 0.1) {
      _message = 'That wall is too short for a 0.9 m doorway.';
      notifyListeners();
      return false;
    }
    final double c = s.clamp(half, w.length - half).toDouble();
    for (final DoorGap d in w.doors) {
      if ((d.centerM - c).abs() < (d.widthM + kDoorWidthM) / 2) {
        _message = 'There is already a doorway there.';
        notifyListeners();
        return false;
      }
    }
    _message = null;
    _replace(
      i,
      w.copyWith(
        doors: <DoorGap>[
          ...w.doors,
          DoorGap(centerM: c),
        ],
      ),
    );
    return true;
  }

  /// The wall within [tolerance] meters of [p], nearest first, with the
  /// distance along it. Null when none is that close.
  (int, double)? wallNear(P2 p, double tolerance) {
    (int, double)? best;
    double bestD = tolerance;
    for (int i = 0; i < _walls.length; i++) {
      final RoomWall w = _walls[i];
      final double l = w.length;
      if (l <= 0) continue;
      final P2 u = (w.b - w.a).scale(1 / l);
      final double s = (p - w.a).dot(u).clamp(0.0, l).toDouble();
      final double d = p.distanceTo(w.a + u.scale(s));
      if (d <= bestD) {
        bestD = d;
        best = (i, s);
      }
    }
    return best;
  }

  /// A tap with the Door tool.
  void tapDoor(P2 p, double tolerance) {
    final (int, double)? hit = wallNear(p, tolerance);
    if (hit == null) {
      _message = 'Tap on a wall to add a doorway.';
      notifyListeners();
      return;
    }
    _selected = hit.$1;
    _addDoor(hit.$1, hit.$2);
  }

  /// A tap with the Select tool.
  void tapSelect(P2 p, double tolerance) {
    final (int, double)? hit = wallNear(p, tolerance);
    selectWall(hit?.$1);
  }

  P2 _snap(P2 p) {
    for (final RoomWall w in _walls) {
      for (final P2 e in <P2>[w.a, w.b]) {
        if (e.distanceTo(p) <= kEndpointSnapM) return e;
      }
    }
    double r(double v) => (v / kSnapM).roundToDouble() * kSnapM;
    return _clampToPlan(P2(r(p.x), r(p.y)));
  }

  void startWall(P2 p) {
    final P2 a = _snap(p);
    _draft = (a, a);
    _message = null;
    notifyListeners();
  }

  void updateWall(P2 p) {
    final (P2, P2)? d = _draft;
    if (d == null) return;
    _draft = (d.$1, _snap(p));
    notifyListeners();
  }

  void endWall() {
    final (P2, P2)? d = _draft;
    _draft = null;
    if (d == null) return;
    if (d.$1.distanceTo(d.$2) < kMinWallM) {
      _message = 'Drag farther to draw a wall (at least 30 cm).';
      notifyListeners();
      return;
    }
    if (_walls.length >= kMaxWalls) {
      _message = 'This plan holds up to $kMaxWalls walls. Delete one first.';
      notifyListeners();
      return;
    }
    _walls.add(
      RoomWall(
        a: d.$1,
        b: d.$2,
        material: _newMaterial,
        thicknessMm: _newThicknessMm,
      ),
    );
    _selected = _walls.length - 1;
    _message = null;
    _geometryChanged();
  }

  void cancelWall() {
    if (_draft == null) return;
    _draft = null;
    notifyListeners();
  }

  // ── Compute pipeline ────────────────────────────────────────────────────

  FieldGrid? _average;
  FieldGrid? _ripple;
  int? _averageMs;
  int? _rippleMs;
  bool _inFlight = false;
  bool _pendingAverage = false;
  bool _pendingRipple = false;
  bool _averageStale = true;
  String? _error;
  int _revision = 0;

  /// Path-gain grid (add EIRP for dBm), or null before the first run.
  FieldGrid? get averageGrid => _average;

  /// Close-up grid, dB relative to the local average.
  FieldGrid? get rippleGrid => _ripple;

  int? get averageMs => _averageMs;
  int? get rippleMs => _rippleMs;

  /// True while a map is being computed.
  bool get computing => _inFlight;

  /// The last compute failure, in words; null when the maps are current.
  String? get error => _error;

  /// Changes whenever a map changes (cheap repaint checks).
  int get revision => _revision;

  void _geometryChanged() {
    _reports = null;
    _request(average: true);
    notifyListeners();
  }

  void _radioChanged() {
    _reports = null;
    _request(average: true);
    notifyListeners();
  }

  void _request({required bool average}) {
    if (average) {
      _pendingAverage = true;
      _averageStale = true;
    }
    if (_closeUp) _pendingRipple = true;
    if (!_pendingAverage && !_pendingRipple) return;
    if (_inFlight) return;
    _start();
  }

  /// Re-runs the last failed computation.
  void retry() {
    _error = null;
    _request(average: true);
    notifyListeners();
  }

  Future<void> _start() async {
    final bool wantAverage = _pendingAverage || _average == null;
    final bool wantRipple = _pendingRipple && _closeUp;
    _pendingAverage = false;
    _pendingRipple = false;
    if (!wantAverage && !wantRipple) return;
    _inFlight = true;
    final RoomFieldJob job = RoomFieldJob(
      walls: List<RoomWall>.of(_walls),
      ap: _ap,
      radio: radio,
      widthM: _widthM,
      heightM: _heightM,
      cellM: kRoomCellM,
      rippleCenter: wantRipple ? _client : null,
      includeAverage: wantAverage,
    );
    try {
      final RoomFieldResult r = await _runner(job);
      if (_disposed) return;
      if (r.average != null) {
        _average = r.average;
        _averageMs = r.averageMs;
        if (!_pendingAverage) _averageStale = false;
      }
      if (r.ripple != null) {
        _ripple = r.ripple;
        _rippleMs = r.rippleMs;
      }
      _error = null;
    } catch (e) {
      if (_disposed) return;
      _error = 'The map could not be computed ($e).';
    }
    _inFlight = false;
    _revision++;
    if (_pendingAverage || _pendingRipple) {
      _start();
    }
    notifyListeners();
  }

  /// True when the drawn average map is from older inputs than the screen
  /// shows (a newer run is on its way).
  bool get averageStale => _averageStale;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ── Readouts ────────────────────────────────────────────────────────────

  List<RoomBandRow>? _reports;

  RoomEngine _exactEngine(double fMHz) => RoomEngine(
    walls: _walls,
    ap: _ap,
    radio: radioAt(fMHz),
    exactCoefficients: true,
  );

  /// The client spot on all three bands; the current band uses the selected
  /// channel, the other two their default channel.
  List<RoomBandRow> get bandRows {
    return _reports ??= <RoomBandRow>[
      for (final WifiBand b in WifiBand.values)
        () {
          final int ch = b == _band ? _channel : roomDefaultChannel(b);
          final int f = centerFrequencyMHzForBand(b, ch)!;
          return (
            band: b,
            channel: ch,
            report: _exactEngine(f.toDouble()).report(_client),
          );
        }(),
    ];
  }

  /// The client readout at the selected channel.
  PointReport get clientReport =>
      bandRows.firstWhere((RoomBandRow r) => r.band == _band).report;

  /// Received power at the client's exact spot, dBm.
  double get clientDbm => _eirp + clientReport.coherentGainDb;

  /// Local-average received power at the client, dBm.
  double get clientAverageDbm => _eirp + clientReport.averageGainDb;

  /// First Fresnel-zone radius at the middle of the AP-to-client path, m.
  double get fresnelMidRadiusM {
    final double d = _ap.distanceTo(_client);
    if (d <= 0) return 0;
    return KnifeEdge.fresnelRadius(lambda: lambda, d1: d / 2, d2: d / 2);
  }

  /// The swing of the close-up around the local average, dB (min, max), or
  /// null before it is computed.
  (double, double)? get rippleRange {
    final FieldGrid? g = _ripple;
    if (g == null) return null;
    double lo = double.infinity;
    double hi = double.negativeInfinity;
    for (final double v in g.values) {
      if (v <= kGainFloorDb) continue;
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    if (!lo.isFinite || !hi.isFinite) return null;
    return (lo, hi);
  }

  /// The wall nearest the client, for the half-wavelength ruler, with the
  /// distance to it (m). Null when there are no walls.
  (int, double)? get wallNearClient {
    final (int, double)? hit = wallNear(_client, double.infinity);
    if (hit == null) return null;
    final RoomWall w = _walls[hit.$1];
    return (hit.$1, _client.distanceTo(w.pointAt(hit.$2)));
  }

  // ── Formatting (shared by stage, controls and copy) ─────────────────────

  static String dbm(double v) =>
      v <= kGainFloorDb + 1 ? 'below -200 dBm' : '${fmt1(v)} dBm';

  static String fmt1(double v) {
    final String s = v.toStringAsFixed(1);
    return s == '-0.0' ? '0.0' : s;
  }

  static String signedDb(double v) {
    final String s = fmt1(v.abs());
    if (s == '0.0') return '0.0 dB';
    return v > 0 ? '+$s dB' : '-$s dB';
  }

  static String meters(double m) => m < 1
      ? '${(m * 100).toStringAsFixed(0)} cm'
      : '${m.toStringAsFixed(1)} m';

  static String cm(double m, [int decimals = 1]) =>
      '${(m * 100).toStringAsFixed(decimals)} cm';

  String wallName(int i) {
    final RoomWall w = _walls[i];
    return 'Wall ${i + 1}: ${w.material.label}, ${fmtMm(w.thicknessMm)} mm'
        '${w.doors.isEmpty ? '' : ', ${w.doors.length} doorway${w.doors.length == 1 ? '' : 's'}'}';
  }

  static String fmtMm(double mm) {
    if (mm < 20 && mm != mm.roundToDouble()) return mm.toStringAsFixed(1);
    return mm.toStringAsFixed(0);
  }

  // ── Copy payload (GL-003 §8.16) ────────────────────────────────────────

  String copyText() {
    final PointReport r = clientReport;
    final StringBuffer b = StringBuffer()
      ..writeln(
        'Room Propagation (image-ray model, ITU-R P.2040 walls, P.526 '
        'diffraction)',
      )
      ..writeln(
        'Plan: ${preset.label}, ${fmt1(_widthM)} x ${fmt1(_heightM)} m, '
        '${_walls.length} walls',
      )
      ..writeln(
        'Channel $_channel, $freqMHz MHz, EIRP ${_eirp.toStringAsFixed(0)} '
        'dBm, ${_pol.name.toUpperCase()}',
      )
      ..writeln(
        'Reflections: order $_order. Diffraction: '
        '${_diffraction ? 'on' : 'off'}',
      )
      ..writeln('Client ${meters(r.distanceM)} from the AP')
      ..writeln(
        'Received here: ${dbm(clientDbm)}; local average '
        '${dbm(clientAverageDbm)}',
      )
      ..writeln('Free-space loss: ${fmt1(r.fsplDb)} dB')
      ..writeln('Walls on the straight line: ${_lossText(r.wallLossDb)}');
    final double? dif = r.diffractionDb;
    if (_diffraction && dif != null) {
      b.writeln('Diffraction: ${signedDb(-dif)}');
    }
    final double? refl = r.reflectionsDb;
    if (refl != null && _order > 0) {
      b.writeln('Reflections: ${signedDb(refl)}');
    }
    b.writeln('Same spot, local average:');
    for (final RoomBandRow row in bandRows) {
      b.writeln(
        '  ${row.band.label} (ch ${row.channel}): '
        '${dbm(_eirp + row.report.averageGainDb)}',
      );
    }
    b.writeln(
      'Model values, not measurements. A 2D plan of a 3D model: no '
      'floor or ceiling bounce.',
    );
    return b.toString().trimRight();
  }

  static String _lossText(double v) =>
      !v.isFinite || v > 150 ? 'more than 150 dB' : '${fmt1(v)} dB';

  /// A loss in dB for display, capped.
  static String lossDb(double v) => _lossText(v);

  /// Presenter keyboard. Nothing animates here, so there is no play or
  /// step: R reloads the plan, and Up/Down move the EIRP 1 dB, which shifts
  /// the whole map with no recompute.
  PresenterActions get presenterActions => PresenterActions(
    reset: () => loadPreset(_preset),
    sliderDown: () => eirpDbm = _eirp - 1,
    sliderUp: () => eirpDbm = _eirp + 1,
    sliderLabel: 'AP EIRP',
  );
}
