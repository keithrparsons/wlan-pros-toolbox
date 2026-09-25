// State for the Wi-Fi Lab DFS and Radar simulator (dfs-simulator).
//
// One ChangeNotifier holds every input, the computed hour and the clock, so
// the two halves of the screen stay independent widgets: DfsSimulatorStage
// (channel strip and timeline) and DfsSimulatorControls (inputs and
// readouts) each listen to this one object. The phone layout stacks them; a
// presenter layout can place them side by side (spec 00).
//
// All DFS rules and the run itself live in lib/services/wifi_lab/
// dfs_model.dart. The hour is computed whole whenever an input changes or
// the student presses "Radar now" (which adds the current time to the
// config), and the clock only moves a cursor through it. The stage draws
// only what has happened up to the cursor, so nothing ahead is given away.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/dfs_model.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kDfsSimulatorToolId = 'dfs-simulator';

/// Simulated seconds per real second.
enum DfsClockSpeed {
  x1('1x (real time)', 1),
  x10('10x', 10),
  x60('60x (1 min per second)', 60),
  x300('300x (5 min per second)', 300);

  const DfsClockSpeed(this.label, this.factor);

  final String label;
  final double factor;
}

/// How much of the hour the timeline shows.
enum DfsTimelineView {
  hour('Whole hour'),
  zoom('3 minutes');

  const DfsTimelineView(this.label);

  final String label;
}

/// Seconds moved by one press of Step.
const double kDfsStepSeconds = 10;

/// Width of the zoomed timeline window, seconds.
const double kDfsZoomWindowS = 180;

class DfsSimulatorController extends ChangeNotifier {
  DfsSimulatorController({required TickerProvider vsync, DfsConfig? initial})
    : _config = initial ?? const DfsConfig() {
    _run = simulateDfs(_config);
    _ticker = vsync.createTicker(_onTick);
  }

  DfsConfig _config;
  late DfsRun _run;
  late final Ticker _ticker;

  double _timeS = 0;
  bool _playing = false;
  Duration _lastElapsed = Duration.zero;
  DfsClockSpeed _speed = DfsClockSpeed.x10;
  DfsTimelineView _view = DfsTimelineView.hour;

  // ── Read side ─────────────────────────────────────────────────────────────

  DfsConfig get config => _config;
  DfsRun get run => _run;
  bool get playing => _playing;
  DfsClockSpeed get speed => _speed;
  DfsTimelineView get view => _view;
  double get timeS => _timeS;

  bool get atEnd => _timeS >= kDfsHorizonS;
  bool get atStart => _timeS <= 0 && _config.manualRadarS.isEmpty;

  ApSegment get segment =>
      _run.segmentAt(math.min(_timeS, kDfsHorizonS - 1e-6));

  /// Radar hits that have happened by now.
  List<RadarHit> get hitsSoFar => _run.hitsUpTo(_timeS);

  RadarHit? get lastHit {
    final List<RadarHit> h = hitsSoFar;
    return h.isEmpty ? null : h.last;
  }

  List<ChannelBlock> get blocksNow => _run.blocksAt(_timeS);

  /// "Radar now" does something only on a DFS channel, and not while the AP
  /// is already leaving one.
  bool get canRadarNow => !atEnd && _run.radarActionableAt(_timeS);

  /// Why "Radar now" is off, in words, or null when it is on.
  String? get radarDisabledReason {
    if (atEnd) return 'The hour is over. Restart to run again.';
    final ApSegment s = segment;
    if (s.phase == ApPhase.moving) {
      return 'The AP is already leaving channel ${placementLabel(s.channel)}.';
    }
    if (!placementIsDfs(_config.region, s.channel)) {
      return 'Channel ${placementLabel(s.channel)} is not a DFS channel, so '
          'the AP does not have to listen for radar here.';
    }
    return null;
  }

  /// The zoomed window: the last 2.5 minutes and the next 30 s.
  (double, double) get window {
    if (_view == DfsTimelineView.hour) return (0, kDfsHorizonS);
    final double start = (_timeS - kDfsZoomWindowS * 5 / 6).clamp(
      0.0,
      kDfsHorizonS - kDfsZoomWindowS,
    );
    return (start, start + kDfsZoomWindowS);
  }

  List<BondedChannel> get startChoices =>
      dfsPlacements(_config.region, _config.widthMHz);

  BondedChannel get startPlacement => _config.startPlacement;

  // ── Clock ─────────────────────────────────────────────────────────────────

  void togglePlay() {
    if (_playing) {
      _pause();
    } else {
      if (atEnd) _restartClock();
      _playing = true;
      _lastElapsed = Duration.zero;
      _ticker.start();
    }
    notifyListeners();
  }

  void _pause() {
    _playing = false;
    if (_ticker.isActive) _ticker.stop();
  }

  /// Pause without toggling (app backgrounded).
  void pause() {
    if (!_playing) return;
    _pause();
    notifyListeners();
  }

  void step() {
    _pause();
    _timeS = math.min(kDfsHorizonS, _timeS + kDfsStepSeconds);
    notifyListeners();
  }

  void _restartClock() {
    _timeS = 0;
    if (_config.manualRadarS.isNotEmpty) {
      _config = _config.copyWith(manualRadarS: const <double>[]);
      _run = simulateDfs(_config);
    }
  }

  /// Back to 0:00; clears the radar the student added.
  void restart() {
    _pause();
    _restartClock();
    notifyListeners();
  }

  void seek(double seconds) {
    _pause();
    _timeS = seconds.clamp(0.0, kDfsHorizonS);
    notifyListeners();
  }

  set speed(DfsClockSpeed s) {
    if (s == _speed) return;
    _speed = s;
    notifyListeners();
  }

  set view(DfsTimelineView v) {
    if (v == _view) return;
    _view = v;
    notifyListeners();
  }

  void _onTick(Duration elapsed) {
    final double dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    // A stalled frame cannot jump more than half a real second.
    _timeS += math.min(dt, 0.5) * _speed.factor;
    if (_timeS >= kDfsHorizonS) {
      _timeS = kDfsHorizonS;
      _pause();
    }
    notifyListeners();
  }

  // ── Radar ─────────────────────────────────────────────────────────────────

  /// Radar detected now. Keeps the clock where it is.
  void radarNow() {
    if (!canRadarNow) return;
    _apply(
      _config.copyWith(manualRadarS: <double>[..._config.manualRadarS, _timeS]),
    );
  }

  // ── Inputs ────────────────────────────────────────────────────────────────

  void _apply(DfsConfig next) {
    if (next == _config) return;
    _config = next;
    _run = simulateDfs(next);
    notifyListeners();
  }

  set region(DfsRegion r) {
    // Keep the starting channel if the new plan has it at this width.
    final bool keeps = dfsPlacements(
      r,
      _config.widthMHz,
    ).any((BondedChannel p) => p.components.contains(_config.startChannel));
    _apply(
      _config.copyWith(
        region: r,
        startChannel: keeps
            ? _config.startChannel
            : dfsPlacements(r, _config.widthMHz)
                  .firstWhere(
                    (BondedChannel p) => placementIsDfs(r, p),
                    orElse: () => dfsPlacements(r, _config.widthMHz).first,
                  )
                  .components
                  .first,
      ),
    );
  }

  set widthMHz(int w) {
    if (w == _config.widthMHz) return;
    final DfsConfig probe = _config.copyWith(widthMHz: w);
    _apply(probe.copyWith(startChannel: probe.startPlacement.components.first));
  }

  set start(BondedChannel p) =>
      _apply(_config.copyWith(startChannel: p.components.first));

  set policy(NewChannelPolicy p) => _apply(_config.copyWith(policy: p));

  set radarPerHour(double r) => _apply(_config.copyWith(radarPerHour: r));

  /// A new random radar pattern (next seed).
  void newRandomRadar() => _apply(_config.copyWith(seed: _config.seed + 1));

  set eirpDbm(double v) => _apply(_config.copyWith(eirpDbm: v));

  // ── Copy ──────────────────────────────────────────────────────────────────

  String copyText() {
    final DfsConfig c = _config;
    final DfsRules r = c.region.rules;
    final BondedChannel s = startPlacement;
    final StringBuffer b = StringBuffer()
      ..writeln('DFS and Radar (WLAN Pros Toolbox, teaching model)')
      ..writeln(
        'Region ${c.region.label}, start channel ${placementLabel(s)} at '
        '${c.widthMHz} MHz'
        '${placementIsDfs(c.region, s) ? ' (DFS)' : ' (not DFS)'}, '
        'policy: ${c.policy.label}',
      )
      ..writeln(
        'Random radar: '
        '${c.radarPerHour == 0 ? 'off' : '${c.radarPerHour.toStringAsFixed(0)} per hour'}',
      )
      ..writeln(
        'Rules: CAC ${fmtSpan(r.cacS)}'
        '${r.weatherCacS != r.cacS ? ' (${fmtSpan(r.weatherCacS)} in 5600-5650 MHz)' : ''}, '
        'closing ${fmtSpan(r.closingS)}, move ${fmtSpan(r.moveS)}, '
        'non-occupancy ${fmtSpan(r.nonOccupancyS)}',
      )
      ..writeln('At ${fmtClock(_timeS)}:')
      ..writeln(
        '  Time to first transmission: '
        '${_run.firstTxS == null ? 'not within the hour' : fmtSpan(_run.firstTxS!)}',
      );
    for (final RadarHit h in hitsSoFar) {
      b.writeln(
        '  ${fmtClock(h.timeS)} radar on ${placementLabel(h.channel)}'
        '${h.duringCac ? ' during its CAC' : ''}, moved to '
        '${placementLabel(h.next)} at ${h.next.widthMHz} MHz'
        '${h.nextCacS > 0 ? ' (CAC ${fmtSpan(h.nextCacS)})' : ' (no CAC)'}, '
        'outage '
        '${h.resumeS != null && h.resumeS! <= _timeS ? fmtSpan(h.outageS!) : 'still running'}',
      );
    }
    for (final ChannelBlock bl in blocksNow) {
      b.writeln(
        '  Blocked: ${bl.channels.join(', ')} until ${fmtClock(bl.untilS)}',
      );
    }
    return b.toString().trimRight();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
