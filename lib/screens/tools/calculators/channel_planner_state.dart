// State for the Wi-Fi Lab Channel Planner (channel-planner).
//
// One ChangeNotifier holds the floor, the APs, the walls and the plan rules,
// and caches the analysis the stage and the controls both read. The stage and
// the controls never talk to each other, only to this object, so a phone can
// stack them and a presenter layout can put them side by side (spec 00).
// The numbers come from services/wifi_lab/channel_planner_model.dart.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../services/wifi_lab/channel_planner_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';

/// Stable catalog tool id: backs the route, the help entry and the tests.
const String kChannelPlannerToolId = 'channel-planner';

const int kMinAps = 2;
const int kMaxAps = 12;

/// Default floor, metres (spec 16).
const double kDefaultFloorW = 50;
const double kDefaultFloorH = 30;

/// Default AP spots on the 50 x 30 m floor: two rows of three.
const List<FloorPoint> _kDefaultSpots = <FloorPoint>[
  FloorPoint(9, 8),
  FloorPoint(25, 8),
  FloorPoint(41, 8),
  FloorPoint(9, 22),
  FloorPoint(25, 22),
  FloorPoint(41, 22),
];

/// Where a new AP goes: the first of these spots (scaled to the floor) not
/// within 6 m of another AP, else the center.
const List<(double, double)> _kNewSpots = <(double, double)>[
  (0.5, 0.5),
  (0.17, 0.5),
  (0.83, 0.5),
  (0.33, 0.25),
  (0.67, 0.25),
  (0.33, 0.75),
  (0.67, 0.75),
  (0.08, 0.12),
  (0.92, 0.12),
  (0.08, 0.88),
  (0.92, 0.88),
  (0.5, 0.12),
  (0.5, 0.88),
];

class _Ap {
  _Ap(this.position, this.width, this.channel);
  FloorPoint position;
  int width;
  ChannelOption? channel;
}

class ChannelPlannerState extends ChangeNotifier {
  ChannelPlannerState() {
    _reset();
  }

  PlanRules _rules = const PlanRules();
  int _width = 40;
  double _floorW = kDefaultFloorW;
  double _floorH = kDefaultFloorH;
  final List<_Ap> _aps = <_Ap>[];
  final List<Wall> _walls = <Wall>[];
  PropagationSettings _prop = const PropagationSettings();
  int? _selected = 0;
  bool _wallMode = false;
  Wall? _draftWall;
  String? _planNote;
  int _revision = 0;
  PlanAnalysis? _analysis;

  // ── Reads ──────────────────────────────────────────────────────────────

  PlanRules get rules => _rules;
  PlannerBand get band => _rules.band;
  int get width => _width;
  double get floorW => _floorW;
  double get floorH => _floorH;
  PropagationSettings get propagation => _prop;
  List<Wall> get walls => List<Wall>.unmodifiable(_walls);
  Wall? get draftWall => _draftWall;
  bool get wallMode => _wallMode;
  int? get selected => _selected;
  int get apCount => _aps.length;
  bool get canAdd => _aps.length < kMaxAps;
  bool get canRemove => _aps.length > kMinAps;
  int get revision => _revision;

  /// A note after Auto-plan ran, cleared by the next manual change.
  String? get planNote => _planNote;

  String apName(int i) => 'AP ${i + 1}';
  FloorPoint position(int i) => _aps[i].position;
  int apWidth(int i) => _aps[i].width;
  ChannelOption? channelOf(int i) => _aps[i].channel;

  List<PlannerAp> get aps => <PlannerAp>[
    for (final _Ap a in _aps) PlannerAp(a.position, a.channel),
  ];

  PlanAnalysis get analysis => _analysis ??= analyzePlan(
    aps: aps,
    walls: _walls,
    propagation: _prop,
    rules: _rules,
  );

  /// Channels a plan can reuse at the global width.
  int get available => channelsAvailable(_rules, _width);

  /// Counts at every width of this band, for the readout table.
  List<(int, int)> get availableByWidth => <(int, int)>[
    for (final int w in _rules.band.widths)
      (w, _rules.widths.contains(w) ? channelsAvailable(_rules, w) : 0),
  ];

  List<ChannelOption> optionsFor(int width) => channelOptions(_rules, width);

  /// Occupied channels, lowest frequency first, each with its AP indexes.
  /// The stage and the spectrum strip color and pattern by this order.
  List<(ChannelGroup, List<int>)> get occupied {
    final Map<ChannelGroup, List<int>> m = <ChannelGroup, List<int>>{};
    for (int i = 0; i < _aps.length; i++) {
      final ChannelOption? c = _aps[i].channel;
      if (c == null) continue;
      m.putIfAbsent(c.group, () => <int>[]).add(i);
    }
    final List<(ChannelGroup, List<int>)> out = <(ChannelGroup, List<int>)>[
      for (final MapEntry<ChannelGroup, List<int>> e in m.entries)
        (e.key, e.value),
    ];
    out.sort(
      ((ChannelGroup, List<int>) a, (ChannelGroup, List<int>) b) =>
          a.$1.lowMHz.compareTo(b.$1.lowMHz) != 0
          ? a.$1.lowMHz.compareTo(b.$1.lowMHz)
          : a.$1.highMHz.compareTo(b.$1.highMHz),
    );
    return out;
  }

  /// Index of [g] in [occupied], the key for its color and pattern.
  int occupiedIndex(ChannelGroup g) {
    final List<(ChannelGroup, List<int>)> o = occupied;
    for (int i = 0; i < o.length; i++) {
      if (o[i].$1 == g) return i;
    }
    return -1;
  }

  /// APs with no channel because none of their width exists under the rules.
  List<int> get unassigned => <int>[
    for (int i = 0; i < _aps.length; i++)
      if (_aps[i].channel == null) i,
  ];

  // ── Writes ─────────────────────────────────────────────────────────────

  void _changed({bool keepNote = false}) {
    _analysis = null;
    if (!keepNote) _planNote = null;
    _revision++;
    notifyListeners();
  }

  void _reset() {
    _rules = const PlanRules();
    _width = 40;
    _floorW = kDefaultFloorW;
    _floorH = kDefaultFloorH;
    _prop = const PropagationSettings();
    _walls.clear();
    _aps.clear();
    _wallMode = false;
    _draftWall = null;
    // Everyone on one channel: the plan Auto-plan is there to fix.
    final List<ChannelOption> opts = channelOptions(_rules, _width);
    for (final FloorPoint p in _kDefaultSpots) {
      _aps.add(_Ap(p, _width, opts.isEmpty ? null : opts.first));
    }
    _selected = 0;
  }

  void reset() {
    _reset();
    _changed();
  }

  /// The option at [width] closest to [old]: same primary if it exists,
  /// otherwise the nearest center frequency. Null when none exist.
  ChannelOption? _nearest(ChannelOption? old, int width) {
    final List<ChannelOption> opts = channelOptions(_rules, width);
    if (opts.isEmpty) return null;
    if (old == null || old.band != _rules.band) return opts.first;
    for (final ChannelOption o in opts) {
      if (o == old) return o;
    }
    // Same primary, and prefer the same group when only the edges moved.
    final List<ChannelOption> same = opts
        .where((ChannelOption o) => o.primary == old.primary)
        .toList();
    if (same.isNotEmpty) {
      same.sort(
        (ChannelOption a, ChannelOption b) =>
            (a.group.centerFreqMHz - old.group.centerFreqMHz).abs().compareTo(
              (b.group.centerFreqMHz - old.group.centerFreqMHz).abs(),
            ),
      );
      return same.first;
    }
    final int f = centerMHz(old.band, old.primary);
    opts.sort(
      (ChannelOption a, ChannelOption b) => (centerMHz(a.band, a.primary) - f)
          .abs()
          .compareTo((centerMHz(b.band, b.primary) - f).abs()),
    );
    return opts.first;
  }

  void _revalidate() {
    if (!_rules.widths.contains(_width)) _width = _rules.widths.last;
    for (final _Ap a in _aps) {
      if (!_rules.widths.contains(a.width)) a.width = _width;
      a.channel = _nearest(a.channel, a.width);
    }
  }

  void setBand(PlannerBand b) {
    if (b == _rules.band) return;
    _rules = _rules.copyWith(band: b);
    if (!_rules.widths.contains(_width)) {
      _width = b == PlannerBand.band24 ? 20 : 40;
    }
    if (b == PlannerBand.band24) _width = 20;
    // A new band starts with everyone on one channel, like the default.
    final List<ChannelOption> opts = channelOptions(_rules, _width);
    for (final _Ap a in _aps) {
      a.width = _width;
      a.channel = opts.isEmpty ? null : opts.first;
    }
    _changed();
  }

  void setRegion(PlannerRegion r) {
    if (r == _rules.region) return;
    _rules = _rules.copyWith(region: r);
    _revalidate();
    _changed();
  }

  void setDfs(bool on) {
    _rules = _rules.copyWith(dfs: on);
    _revalidate();
    _changed();
  }

  void setUnii4(bool on) {
    _rules = _rules.copyWith(unii4: on);
    _revalidate();
    _changed();
  }

  void setMask(TxMask m) {
    if (m == _rules.mask) return;
    _rules = _rules.copyWith(mask: m);
    _revalidate();
    _changed();
  }

  /// Set every AP to [w], keeping each primary where it can.
  void setWidth(int w) {
    if (!_rules.widths.contains(w)) return;
    _width = w;
    for (final _Ap a in _aps) {
      a.width = w;
      a.channel = _nearest(a.channel, w);
    }
    _changed();
  }

  /// The next width up ([dir] > 0) or down among the ones the rules allow.
  /// Nothing happens at either end.
  void nudgeWidth(int dir) {
    final List<int> ws = _rules.widths;
    final int at = ws.indexOf(_width);
    final int next = (at < 0 ? 0 : at) + dir.sign;
    if (next < 0 || next >= ws.length) return;
    setWidth(ws[next]);
  }

  /// Presenter keys (spec 00): R resets the floor; Up and Down step the
  /// channel width every AP uses. No clock, so no play or step.
  PresenterActions get presenterActions => PresenterActions(
    reset: reset,
    sliderDown: () => nudgeWidth(-1),
    sliderUp: () => nudgeWidth(1),
    sliderLabel: 'Channel width',
  );

  void setApWidth(int i, int w) {
    if (!_rules.widths.contains(w)) return;
    _aps[i].width = w;
    _aps[i].channel = _nearest(_aps[i].channel, w);
    _changed();
  }

  void setApChannel(int i, ChannelOption c) {
    _aps[i].channel = c;
    _changed();
  }

  void select(int? i) {
    if (i == _selected) return;
    _selected = i;
    _changed(keepNote: true);
  }

  FloorPoint _clamp(FloorPoint p) => FloorPoint(
    p.x.clamp(0.0, _floorW).toDouble(),
    p.y.clamp(0.0, _floorH).toDouble(),
  );

  void moveAp(int i, FloorPoint p) {
    _aps[i].position = _clamp(p);
    _changed();
  }

  void addAp() {
    if (!canAdd) return;
    FloorPoint spot = FloorPoint(_floorW / 2, _floorH / 2);
    for (final (double fx, double fy) in _kNewSpots) {
      final FloorPoint p = FloorPoint(fx * _floorW, fy * _floorH);
      if (_aps.every((_Ap a) => a.position.distanceTo(p) >= 6)) {
        spot = p;
        break;
      }
    }
    final List<ChannelOption> opts = channelOptions(_rules, _width);
    _aps.add(_Ap(spot, _width, opts.isEmpty ? null : opts.first));
    _selected = _aps.length - 1;
    _changed();
  }

  void removeAp(int i) {
    if (!canRemove) return;
    _aps.removeAt(i);
    if (_selected != null) {
      if (_selected == i) {
        _selected = math.min(i, _aps.length - 1);
      } else if (_selected! > i) {
        _selected = _selected! - 1;
      }
    }
    _changed();
  }

  void setFloorSize({double? w, double? h}) {
    _floorW = w ?? _floorW;
    _floorH = h ?? _floorH;
    for (final _Ap a in _aps) {
      a.position = _clamp(a.position);
    }
    for (int i = 0; i < _walls.length; i++) {
      final Wall wl = _walls[i];
      final FloorPoint a = _clamp(FloorPoint(wl.x1, wl.y1));
      final FloorPoint b = _clamp(FloorPoint(wl.x2, wl.y2));
      _walls[i] = Wall(a.x, a.y, b.x, b.y);
    }
    _walls.removeWhere((Wall w) => w.length < 0.5);
    _changed();
  }

  void setEirp(double v) {
    _prop = PropagationSettings(
      eirpDbm: v,
      exponent: _prop.exponent,
      wallLossDb: _prop.wallLossDb,
    );
    _changed();
  }

  void setExponent(double v) {
    _prop = PropagationSettings(
      eirpDbm: _prop.eirpDbm,
      exponent: v,
      wallLossDb: _prop.wallLossDb,
    );
    _changed();
  }

  void setWallLoss(double v) {
    _prop = PropagationSettings(
      eirpDbm: _prop.eirpDbm,
      exponent: _prop.exponent,
      wallLossDb: v,
    );
    _changed();
  }

  // Walls

  void setWallMode(bool on) {
    _wallMode = on;
    _draftWall = null;
    _changed(keepNote: true);
  }

  static double _snap(double v) => (v * 2).roundToDouble() / 2;

  void startWall(FloorPoint p) {
    final FloorPoint c = _clamp(p);
    _draftWall = Wall(_snap(c.x), _snap(c.y), _snap(c.x), _snap(c.y));
    _changed(keepNote: true);
  }

  void dragWall(FloorPoint p) {
    final Wall? d = _draftWall;
    if (d == null) return;
    final FloorPoint c = _clamp(p);
    _draftWall = Wall(d.x1, d.y1, _snap(c.x), _snap(c.y));
    _changed(keepNote: true);
  }

  void endWall() {
    final Wall? d = _draftWall;
    _draftWall = null;
    if (d != null && d.length >= 1) _walls.add(d);
    _changed();
  }

  /// A wall straight across the floor, for keyboard and screen-reader users.
  void addWallAcross({required bool vertical}) {
    final int k = _walls.length;
    // Stagger repeated walls so they do not stack on one line.
    final double f = <double>[0.5, 0.33, 0.67, 0.25, 0.75][k % 5];
    _walls.add(
      vertical
          ? Wall(_floorW * f, 0, _floorW * f, _floorH)
          : Wall(0, _floorH * f, _floorW, _floorH * f),
    );
    _changed();
  }

  void removeWall(int i) {
    _walls.removeAt(i);
    _changed();
  }

  void clearWalls() {
    _walls.clear();
    _changed();
  }

  // Auto-plan

  void runAutoPlan() {
    final List<ChannelOption?> plan = autoPlan(
      positions: <FloorPoint>[for (final _Ap a in _aps) a.position],
      walls: _walls,
      propagation: _prop,
      rules: _rules,
      width: _width,
    );
    for (int i = 0; i < _aps.length; i++) {
      _aps[i].width = _width;
      _aps[i].channel = plan[i];
    }
    _analysis = null;
    final int used = occupied.length;
    _planNote = plan.every((ChannelOption? c) => c == null)
        ? null
        : 'Auto-plan put ${_aps.length} APs on $used of $available '
              'channel${available == 1 ? '' : 's'} at $_width MHz. Largest '
              'domain: ${analysis.largestDomain.length} '
              'AP${analysis.largestDomain.length == 1 ? '' : 's'}.';
    _changed(keepNote: true);
  }

  // ── Copy payload (GL-003 §8.16) ────────────────────────────────────────

  String copyText() {
    final PlanAnalysis a = analysis;
    final StringBuffer b = StringBuffer()
      ..writeln('Channel Planner')
      ..writeln(
        '${_rules.band.label}, ${_rules.region.label}, $_width MHz'
        '${_rules.band == PlannerBand.band5 ? ', DFS ${_rules.dfs ? 'on' : 'off'}' : ', ${_rules.mask.label}'}'
        '${_rules.band == PlannerBand.band5 && _rules.region == PlannerRegion.us ? ', U-NII-4 ${_rules.unii4 ? 'on' : 'off'}' : ''}',
      )
      ..writeln(
        'Floor ${_floorW.round()} x ${_floorH.round()} m, EIRP '
        '${_prop.eirpDbm.round()} dBm, n = ${_prop.exponent.toStringAsFixed(1)}, '
        '${_walls.length} wall${_walls.length == 1 ? '' : 's'} at '
        '${_prop.wallLossDb.round()} dB',
      )
      ..writeln('Channels available at $_width MHz: $available');
    for (int i = 0; i < _aps.length; i++) {
      final ChannelOption? c = _aps[i].channel;
      b.writeln(
        '${apName(i)}: ${c == null ? 'no channel' : c.longLabel} at '
        '(${_aps[i].position.x.round()}, ${_aps[i].position.y.round()}) m',
      );
    }
    b.writeln(
      'Largest contention domain: ${a.largestDomain.length} AP'
      '${a.largestDomain.length == 1 ? '' : 's'} '
      '(${a.largestDomain.map(apName).join(', ')}), '
      '${(a.largestShare * 100).round()}% airtime each',
    );
    for (final ApLink l in a.contending) {
      b.writeln(
        '${apName(l.a)} and ${apName(l.b)} contend: '
        '${l.rxDbm.toStringAsFixed(1)} dBm, ${l.ruleShort}',
      );
    }
    return b.toString().trimRight();
  }
}
