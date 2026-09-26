// State for the Wi-Fi Classroom Medium Access Simulator (medium-access-simulator).
//
// One ChangeNotifier holds the configuration, the engine run and the clock,
// so the tool's views are independent widgets over it (Keith, 2026-09-25: a
// stage and controls over one shared state object):
//   - MediumAccessSimulatorStage (medium_access_simulator_stage.dart)
//   - MediumAccessTransport, MediumAccessResults, MediumAccessStations,
//     MediumAccessRules, MediumAccessAbout
//                                (medium_access_simulator_controls.dart)
// The phone screen stacks them; the presenter layout puts the stage beside
// the controls, and both routes hold this SAME controller.
//
// THE CLOCK. The Ticker is constructed here directly, not from a widget's
// TickerProvider: a route under the presenter route is muted, and a run
// started on the phone screen must keep going when the instructor presents
// it. The timeline's ScrollController and label cache are NOT here: each view
// owns its own, because the phone screen stays mounted under the presenter.
//
// Moved from the screen's State on 2026-09-26 (presenter pilot); the
// behavior is unchanged. The engine is pure Dart
// (lib/services/wifi_lab/medium_access_engine.dart).

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../services/wifi_lab/medium_access_engine.dart';
import '../../../widgets/presenter/presenter_actions.dart';
import 'medium_access_timeline.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kMediumAccessToolId = 'medium-access-simulator';

/// Simulated air time per real second.
enum SimSpeed {
  crawl('0.1 ms per second', 100),
  slow('0.5 ms per second', 500),
  normal('2 ms per second', 2000),
  fast('20 ms per second', 20000),
  fastest('200 ms per second', 200000);

  const SimSpeed(this.label, this.usPerSecond);

  final String label;
  final int usPerSecond;
}

/// Offered-load choices; null is "always has a frame".
const List<double?> kMediumAccessLoads = <double?>[
  null,
  50,
  200,
  500,
  1000,
  2000,
];

const List<int> kMediumAccessFrameSizes = <int>[100, 500, 1000, 1500, 2304];

/// Slots the Ticker may advance in one frame, so a stalled frame cannot turn
/// into a long synchronous catch-up.
const int _kMaxSlotsPerFrame = 3000;

class MediumAccessSimulatorController extends ChangeNotifier {
  MediumAccessSimulatorController({this.seed = 1}) {
    _engine = _buildEngine();
    _ticker = Ticker(_onTick, debugLabel: 'medium-access');
  }

  /// Seed for every random draw. Same seed, same run.
  final int seed;
  bool _disposed = false;

  // ── Configuration ──────────────────────────────────────────────────────
  List<StationConfig> _stations = const <StationConfig>[
    StationConfig(),
    StationConfig(),
    StationConfig(),
  ];
  AccessMode _mode = AccessMode.dcf;
  bool _hidden = false;
  bool _rts = false;
  int _frameBytes = 1500;
  int _rateMbps = 54;

  // ── Run state ──────────────────────────────────────────────────────────
  late MediumAccessEngine _engine;
  late final Ticker _ticker;
  bool _playing = false;
  Duration _lastElapsed = Duration.zero;
  double _carryUs = 0;
  SimSpeed _speed = SimSpeed.crawl;
  TimelineZoom _zoom = TimelineZoom.slots;

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── Read-only state ────────────────────────────────────────────────────

  List<StationConfig> get stations => _stations;
  AccessMode get mode => _mode;
  bool get dcf => _mode == AccessMode.dcf;
  bool get hidden => _hidden;
  bool get rts => _rts;
  int get frameBytes => _frameBytes;
  int get rateMbps => _rateMbps;
  MediumAccessEngine get engine => _engine;
  bool get playing => _playing;
  SimSpeed get speed => _speed;
  TimelineZoom get zoom => _zoom;

  MediumAccessConfig get config => MediumAccessConfig(
    stations: _stations,
    mode: _mode,
    hiddenNode: _hidden && _stations.length > 1,
    rtsCts: _rts,
    frameBytes: _frameBytes,
    phyRateMbps: _rateMbps,
    seed: seed,
  );

  bool get canAddStation => _stations.length < MediumAccessConfig.maxStations;
  bool get canRemoveStation =>
      _stations.length > MediumAccessConfig.minStations;

  MediumAccessEngine _buildEngine() => MediumAccessEngine(config);

  // ── Transport ──────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    final Duration dt = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    _carryUs += dt.inMicroseconds / 1e6 * _speed.usPerSecond;
    final int slots = (_carryUs / OfdmTiming.slotUs).floor();
    if (slots <= 0) return;
    _carryUs -= slots * OfdmTiming.slotUs;
    _engine.advanceSlots(slots.clamp(1, _kMaxSlotsPerFrame));
    _notify();
  }

  void togglePlay() {
    _playing = !_playing;
    if (_playing) {
      _lastElapsed = Duration.zero;
      _carryUs = 0;
      _ticker.start();
    } else {
      _ticker.stop();
    }
    _notify();
  }

  /// One 9 us slot (the Step button and the Right-arrow key).
  void step() {
    _engine.stepSlot();
    _notify();
  }

  /// Rebuild the run from the current configuration, keeping play state.
  void reset() {
    _engine = _buildEngine();
    _carryUs = 0;
    _notify();
  }

  void _reconfigure(VoidCallback change) {
    change();
    reset();
  }

  void setSpeed(SimSpeed s) {
    _speed = s;
    _notify();
  }

  /// The presenter keyboard's slider keys: one speed step down or up.
  void nudgeSpeed(int delta) {
    final int i = (_speed.index + delta).clamp(0, SimSpeed.values.length - 1);
    if (i != _speed.index) setSpeed(SimSpeed.values[i]);
  }

  void setZoom(TimelineZoom z) {
    _zoom = z;
    _notify();
  }

  // ── Configuration edits (each rebuilds the run) ────────────────────────

  void addStation() {
    if (!canAddStation) return;
    _reconfigure(
      () => _stations = <StationConfig>[..._stations, const StationConfig()],
    );
  }

  void removeStation(int i) {
    if (!canRemoveStation) return;
    _reconfigure(() {
      _stations = <StationConfig>[
        for (int j = 0; j < _stations.length; j++)
          if (j != i) _stations[j],
      ];
    });
  }

  void setAccessCategory(int i, AccessCategory ac) => _reconfigure(() {
    _stations = <StationConfig>[
      for (int j = 0; j < _stations.length; j++)
        j == i ? _stations[j].copyWith(accessCategory: ac) : _stations[j],
    ];
  });

  void setLoad(int i, double? framesPerSecond) => _reconfigure(() {
    _stations = <StationConfig>[
      for (int j = 0; j < _stations.length; j++)
        j == i
            ? _stations[j].copyWith(framesPerSecond: () => framesPerSecond)
            : _stations[j],
    ];
  });

  void setMode(AccessMode m) => _reconfigure(() => _mode = m);
  void setHidden(bool v) => _reconfigure(() => _hidden = v);
  void setRts(bool v) => _reconfigure(() => _rts = v);
  void setFrameBytes(int b) => _reconfigure(() => _frameBytes = b);
  void setRate(int r) => _reconfigure(() => _rateMbps = r);

  // ── Presenter keyboard ─────────────────────────────────────────────────

  PresenterActions get presenterActions => PresenterActions(
    playPause: togglePlay,
    step: step,
    reset: reset,
    sliderDown: () => nudgeSpeed(-1),
    sliderUp: () => nudgeSpeed(1),
    sliderLabel: 'Speed',
  );

  // ── Words ──────────────────────────────────────────────────────────────

  String acShort(StationSnapshot s) =>
      dcf ? 'DCF' : s.accessCategory.shortLabel;

  String acLabel(StationSnapshot s) =>
      dcf ? 'Legacy DCF' : s.accessCategory.label;

  static String fmtMs(int us) => '${(us / 1000).toStringAsFixed(3)} ms';

  /// A one-line, worded account of what every lane is doing right now.
  String statusLine() {
    final List<StationSnapshot> stations = _engine.stations;
    if (_engine.nowUs == 0) {
      return 'Paused at time zero. Press Play, or Step to move one slot.';
    }
    final Map<int, LaneSegment> latest = <int, LaneSegment>{};
    for (final LaneSegment s in _engine.segments.reversed) {
      if (s.endUs < _engine.nowUs) continue;
      latest.putIfAbsent(s.lane, () => s);
      if (latest.length == stations.length) break;
    }
    final List<String> parts = <String>[];
    final List<AirFrame> air = _engine.onAir;
    if (air.isEmpty) {
      parts.add('Medium idle.');
    } else {
      final String who = air
          .map(
            (AirFrame f) => f.fromAp
                ? 'AP sending ${f.kind == FrameKind.ack ? 'ACK' : 'CTS'}'
                : '${stationLetter(f.source)} sending '
                      '${f.kind == FrameKind.rts ? 'RTS' : 'data'}',
          )
          .join(', ');
      final bool clash =
          air.where((AirFrame f) => !f.fromAp).length > 1 ||
          air.any((AirFrame f) => f.corruptedAtAp);
      parts.add('Medium: $who${clash ? ', collision at the AP' : ''}.');
    }
    for (final StationSnapshot s in stations) {
      final LaneSegment? seg = latest[s.index];
      parts.add('${s.letter}: ${_describe(s, seg)}.');
    }
    return parts.join(' ');
  }

  String _describe(StationSnapshot s, LaneSegment? seg) {
    switch (s.phase) {
      case StationPhase.noFrame:
        return 'no frame queued';
      case StationPhase.transmitting:
        return 'transmitting';
      case StationPhase.awaitResponse:
        return _rts ? 'waiting for a response' : 'waiting for ACK';
      case StationPhase.contending:
        if (seg == null) return 'backoff ${s.backoff ?? 0}';
        switch (seg.activity) {
          case LaneActivity.aifs:
            return 'in ${dcf ? 'DIFS' : 'AIFS'}';
          case LaneActivity.eifs:
            return 'in EIFS';
          case LaneActivity.frozen:
            return 'frozen at ${seg.count}';
          case LaneActivity.nav:
            return 'deferring to NAV at ${seg.count}';
          case LaneActivity.backoff:
          case LaneActivity.transmit:
          case LaneActivity.awaitResponse:
            return 'backoff ${s.backoff ?? 0}';
        }
    }
  }

  // ── Copy ───────────────────────────────────────────────────────────────

  String? copyText() {
    final MediumAccessStats s = _engine.stats;
    if (s.elapsedUs == 0) return null;
    final StringBuffer b = StringBuffer()
      ..writeln('Medium Access Simulator (WLAN Pros Toolbox)')
      ..writeln(
        'Mode: ${dcf ? 'Legacy DCF' : 'EDCA'}; '
        'hidden node ${config.hiddenNode ? 'on' : 'off'}; '
        'RTS/CTS ${_rts ? 'on' : 'off'}; '
        '$_frameBytes bytes at $_rateMbps Mbps',
      )
      ..writeln('Simulated time: ${fmtMs(s.elapsedUs)}')
      ..writeln(
        'Delivered throughput: ${s.throughputMbps.toStringAsFixed(1)} Mbps',
      )
      ..writeln('Airtime busy: ${s.utilizationPercent.toStringAsFixed(1)} %')
      ..writeln(
        'Collision rate: ${s.collisionPercent.toStringAsFixed(1)} % '
        '(${s.failedAttempts} of ${s.attempts} accesses)',
      );
    for (final StationSnapshot st in _engine.stations) {
      b.writeln(
        'Station ${st.letter} (${acLabel(st)}): CW ${st.cw}, '
        'delivered ${st.delivered}, dropped ${st.dropped}',
      );
    }
    return b.toString().trimRight();
  }
}
