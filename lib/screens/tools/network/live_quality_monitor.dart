// Foreground live monitor for the Network Quality screen.
//
// While the Network Quality screen is mounted, this controller samples the
// CHEAP latency trio (latency / jitter / loss) on a fixed interval using the
// standalone `LatencyProbe` — which does NOT trigger any download, so the data
// cost stays single-digit MB over a long session. It keeps a bounded in-memory
// history per metric and notifies listeners so the metric card redraws as
// samples land.
//
// The EXPENSIVE trio (download / upload / responsiveness) is never auto-looped:
// it is fed only when the user taps "Run test" and the one-shot completes
// (`addFullResult`). Those histories are therefore sparse by design.
//
// Lifecycle = the "clears on leave" decision (Keith, 2026-05-31, spec §1):
// the screen owns one monitor, `start()`s it in `initState`, and `dispose()`s
// it in its own `dispose()`. On dispose the timer is cancelled and the histories
// are gone. No background execution, no persistence, no per-network history.
//
// Test seams (spec §2): the latency sampler is injectable (default = a real
// `LatencyProbe` against the screen's target host) and the periodic tick can be
// driven deterministically via `tickNow()`, so no test hits the real network or
// wall-clock-waits the interval.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:net_quality/net_quality.dart';

/// One point in a metric's live history: when it was taken, the value in the
/// metric's native unit, and the engine grade for that value.
@immutable
class MetricSample {
  /// When this sample was taken.
  final DateTime at;

  /// Measured value in the metric's native unit (ms, %, Mbps, RPM).
  final double value;

  /// Engine grade for [value] at the time of sampling.
  final QualityGrade grade;

  /// Creates a metric sample.
  const MetricSample({
    required this.at,
    required this.value,
    required this.grade,
  });
}

/// Injectable latency-sampler seam. Returns aggregated latency statistics for
/// one tick. Implementations may throw; the monitor treats a throw as a fully
/// lost tick (loss = 100 %) and keeps looping.
typedef LatencySampler = Future<LatencyStats> Function();

/// A foreground, in-memory live trend monitor for the six transport metrics.
///
/// Listen to it from the Network Quality screen. It is a [ChangeNotifier]: on
/// every appended sample (live tick or one-shot result) it calls
/// [notifyListeners].
class LiveQualityMonitor extends ChangeNotifier {
  /// Maximum samples retained per metric. At the 30 s default interval this is
  /// one hour of live trail for the latency trio — plenty for a foreground
  /// session, and it bounds memory (spec §2).
  static const int historyCap = 120;

  /// The six metric ids this monitor tracks, in display order.
  static const List<String> metricIds = <String>[
    MetricIds.latency,
    MetricIds.jitter,
    MetricIds.loss,
    MetricIds.download,
    MetricIds.upload,
    MetricIds.responsiveness,
  ];

  /// How often the cheap latency loop fires while running. Injectable so tests
  /// can use a short interval; the timer itself is never waited on in tests
  /// (they drive [tickNow] directly).
  final Duration interval;

  /// The latency sampler used on each tick. Injected in tests with a fake; in
  /// production a closure over a real [LatencyProbe].
  final LatencySampler _sampler;

  // Per-metric bounded histories. Oldest first; trimmed from the front.
  final Map<String, List<MetricSample>> _history = <String, List<MetricSample>>{
    for (final String id in metricIds) id: <MetricSample>[],
  };

  Timer? _timer;
  bool _running = false;
  bool _disposed = false;

  /// Creates a live monitor.
  ///
  /// [sampler] is the cheap per-tick latency seam. Provide [latencyProbe] (or
  /// neither, and pass a [host]) instead to build the default real sampler. In
  /// production the screen passes a probe over its target host; in tests the
  /// fake [sampler] is passed so no socket is opened.
  LiveQualityMonitor({
    LatencySampler? sampler,
    LatencyProbe? latencyProbe,
    String host = 'one.one.one.one',
    this.interval = const Duration(seconds: 30),
  }) : _sampler = sampler ??
            _probeSampler(latencyProbe ?? LatencyProbe(host: host, samples: 5));

  /// Builds the default sampler: a single [LatencyProbe.measure] per tick.
  static LatencySampler _probeSampler(LatencyProbe probe) => probe.measure;

  /// Whether the live loop is currently sampling (false while paused or before
  /// [start], or after [dispose]).
  bool get isRunning => _running;

  /// Read-only view of one metric's history (oldest first). Returns an empty
  /// list for an unknown id.
  List<MetricSample> historyFor(String metricId) =>
      List<MetricSample>.unmodifiable(_history[metricId] ?? const <MetricSample>[]);

  /// Starts the cheap latency loop. Fires one sample IMMEDIATELY so the UI is
  /// not blank for the first interval (spec §2), then every [interval]. A
  /// second call while already running is a no-op.
  void start() {
    if (_disposed || _running) return;
    _running = true;
    _scheduleTimer();
    // Fire the first tick immediately; do not await — the screen rebuilds via
    // notifyListeners when it completes.
    unawaited(_tick());
  }

  /// Pauses the loop: the timer stops and the history freezes. Existing samples
  /// are kept. No-op if not running.
  void pause() {
    if (_disposed || !_running) return;
    _running = false;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  /// Resumes a paused loop. Fires one sample immediately (so resume feels
  /// responsive) and restarts the interval. No-op if already running.
  void resume() {
    if (_disposed || _running) return;
    _running = true;
    _scheduleTimer();
    unawaited(_tick());
    notifyListeners();
  }

  void _scheduleTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(_tick()));
  }

  /// Runs one cheap latency tick NOW, regardless of the timer. Tests call this
  /// to drive the loop deterministically without waiting the interval. Safe to
  /// call when paused (it still samples once). Returns when the sample lands.
  Future<void> tickNow() => _tick();

  /// One cheap tick: sample latency, derive the latency-trio values + grades
  /// from the SAME engine scoring the one-shot uses, append to the three
  /// histories, and notify. A throwing sampler (or a 100 %-loss result) records
  /// a lost tick and the loop continues — it must never stop the loop (spec §3).
  Future<void> _tick() async {
    LatencyStats stats;
    try {
      stats = await _sampler();
    } catch (_) {
      // A failed tick is a 100 %-loss data point. Latency/jitter are
      // unavailable for this tick; loss is recorded as 100 %. The loop lives.
      stats = const LatencyStats(
        avgMs: 0,
        minMs: 0,
        maxMs: 0,
        jitterMs: 0,
        lossPct: 100,
        sent: 0,
        received: 0,
      );
    }
    if (_disposed) return;

    final DateTime now = DateTime.now();
    final bool hasLatency = stats.received > 0;

    // Loss is always recorded (it is meaningful even at 100 %). Latency and
    // jitter are only recorded when at least one probe in the tick succeeded;
    // a fully-lost tick has no RTT to plot, so we skip those two rather than
    // plant a misleading zero.
    if (hasLatency) {
      _append(
        MetricIds.latency,
        MetricSample(
          at: now,
          value: stats.avgMs,
          grade: QualityScoring.gradeLatencyMs(stats.avgMs),
        ),
      );
      _append(
        MetricIds.jitter,
        MetricSample(
          at: now,
          value: stats.jitterMs,
          grade: QualityScoring.gradeJitterMs(stats.jitterMs),
        ),
      );
    }
    _append(
      MetricIds.loss,
      MetricSample(
        at: now,
        value: stats.lossPct,
        grade: QualityScoring.gradeLossPct(stats.lossPct),
      ),
    );

    notifyListeners();
  }

  /// Appends a sample to every metric history present in a completed one-shot
  /// [result] (spec §2). The expensive trio (download / upload / responsiveness)
  /// only ever gets points this way, which is why those sparklines are sparse.
  /// Unavailable metrics (null value) are skipped — a sparse-but-honest line.
  void addFullResult(QualityResult result) {
    if (_disposed) return;
    final DateTime now = result.measuredAt;
    bool appended = false;
    for (final String id in metricIds) {
      final QualityMetric? m = result.metric(id);
      if (m == null || m.value == null) continue;
      _append(
        id,
        MetricSample(at: now, value: m.value!, grade: m.grade),
        notify: false,
      );
      appended = true;
    }
    if (appended) notifyListeners();
  }

  /// Appends [sample] to [metricId]'s history, trimming from the front to keep
  /// at most [historyCap] points (ring-buffer semantics). [notify] lets a batch
  /// caller (addFullResult) defer to a single notification.
  void _append(String metricId, MetricSample sample, {bool notify = true}) {
    final List<MetricSample> list = _history[metricId]!;
    list.add(sample);
    if (list.length > historyCap) {
      list.removeRange(0, list.length - historyCap);
    }
    if (notify) notifyListeners();
  }

  /// Cancels the timer and frees the histories. After dispose the monitor is
  /// inert: start/resume/tick are no-ops. The screen calls this in its own
  /// dispose, which IS the "clears on leave" behavior (spec §2).
  @override
  void dispose() {
    _disposed = true;
    _running = false;
    _timer?.cancel();
    _timer = null;
    for (final List<MetricSample> list in _history.values) {
      list.clear();
    }
    super.dispose();
  }
}
