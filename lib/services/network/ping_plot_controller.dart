// PingPlotController — the sustained-run controller behind the Ping Plotter
// tool (Wave B, 2026-06-04). It does NOT open any socket itself: it drives the
// ALREADY-SHIPPED TCP-handshake ping engine (PingService) and folds each reply
// into a BOUNDED, time-stamped rolling window plus running stats for the live
// latency-trend chart.
//
// WHY REUSE PingService (not ICMP, not a new transport): PingService is the one
// ping engine that runs on every shipping target — iOS AND the macOS App
// Sandbox (where real ICMP needs a subprocess the sandbox blocks, GL-008). The
// Ping Plotter's job is a continuous latency trend, so the cross-platform,
// device-verifiable engine is the right primitive. The engine's `count: 0`
// continuous mode + per-reply running PingStats already exist; this controller
// adds the time axis, the bounded retention window, jitter, and a clean
// start/stop/dispose lifecycle. No new ping code, no new entitlement.
//
// CORRECTNESS RISK (brief §27): the main risk is a leaked probe loop / stream
// after the screen is disposed. This controller owns exactly one subscription
// and one cancel Completer; [stop] and [dispose] both tear them down, and
// [dispose] also signals the engine's cooperative cancel so no further probe is
// launched. Every lifecycle path is unit-tested with an injected stream so no
// real socket ever opens.
//
// HONESTY (GL-005): a dropped/timed-out probe is recorded as a real gap
// (`PingSample.lost`), never as a fabricated 0 ms. The chart and the loss%
// reflect those gaps; nothing is invented to fill them.

import 'dart:async';

import 'ping_service.dart';

/// One plotted point on the latency trend: a probe that landed (with an RTT) or
/// a probe that was lost (no RTT — an honest gap, never a faked 0).
class PingSample {
  const PingSample({
    required this.sequence,
    required this.elapsed,
    required this.rttMs,
    required this.lost,
    this.errorLabel,
  });

  /// 1-based probe sequence number (monotonic across the whole run, even after
  /// older samples scroll out of the retained window).
  final int sequence;

  /// Time since the run started, used as the chart's X value. Monotonic.
  final Duration elapsed;

  /// Round-trip time in milliseconds for a landed probe, or null when [lost].
  final double? rttMs;

  /// True when this probe produced no reply (timeout / unreachable). A lost
  /// sample carries a null [rttMs] — it is drawn as a gap marker, not a 0.
  final bool lost;

  /// Short honest reason a probe was lost ('timeout' / 'unreachable' / ...),
  /// or null on a successful sample. Surfaced verbatim (GL-005).
  final String? errorLabel;
}

/// Immutable snapshot of the plot state after the most recent sample. Recomputed
/// on each reply over the RETAINED WINDOW (not the whole run) so the chart and
/// the readout always describe the same visible data.
class PingPlotState {
  const PingPlotState({
    required this.samples,
    required this.windowSent,
    required this.windowReceived,
    required this.minMs,
    required this.avgMs,
    required this.maxMs,
    required this.jitterMs,
    required this.lastMs,
    required this.totalSent,
    required this.totalReceived,
  });

  /// The retained, in-order window of samples (oldest first). Length is capped
  /// at the controller's window size.
  final List<PingSample> samples;

  /// Sent / received counts WITHIN the retained window — these back the chart's
  /// visible loss%. Total run counts are [totalSent] / [totalReceived].
  final int windowSent;
  final int windowReceived;

  /// Min / avg / max RTT (ms) over the landed samples in the window, or null
  /// when the window holds no successful sample yet.
  final double? minMs;
  final double? avgMs;
  final double? maxMs;

  /// Mean absolute difference between consecutive landed RTTs in the window
  /// (ms) — the live jitter readout. Null until there are >= 2 landed samples.
  final double? jitterMs;

  /// The most recent landed RTT (ms), or null when the last sample was lost or
  /// the window is empty. Drives the "current" readout.
  final double? lastMs;

  /// Run-lifetime counts (NOT window-bounded), so the summary can report the
  /// true totals even after the window has scrolled.
  final int totalSent;
  final int totalReceived;

  /// Loss as a fraction 0..1 over the retained window. Zero when nothing sent.
  double get windowLossFraction =>
      windowSent == 0 ? 0 : (windowSent - windowReceived) / windowSent;

  /// Loss as a fraction 0..1 over the whole run. Zero when nothing sent.
  double get totalLossFraction =>
      totalSent == 0 ? 0 : (totalSent - totalReceived) / totalSent;

  /// Landed RTTs in window order — feeds the chart line.
  List<double> get landedRttsMs => <double>[
        for (final PingSample s in samples)
          if (!s.lost && s.rttMs != null) s.rttMs!,
      ];

  static const PingPlotState empty = PingPlotState(
    samples: <PingSample>[],
    windowSent: 0,
    windowReceived: 0,
    minMs: null,
    avgMs: null,
    maxMs: null,
    jitterMs: null,
    lastMs: null,
    totalSent: 0,
    totalReceived: 0,
  );
}

/// Drives a sustained ping run and maintains a bounded plot window.
///
/// Lifecycle contract:
///   - [start] begins a continuous run; [states] emits a new [PingPlotState]
///     per probe. Calling [start] while already running is a no-op.
///   - [stop] ends the run, tears down the subscription, and signals the
///     engine's cancel so no further probe launches. The retained state stays
///     readable after a stop (a finished run keeps its chart).
///   - [dispose] stops (if running) and closes the [states] stream. After
///     dispose the controller is inert.
///
/// The [pingStreamFactory] seam lets tests inject a synthetic PingProgress
/// stream, so the bounded window, jitter math, dropped-packet handling, and
/// every teardown path are verified WITHOUT opening a socket.
class PingPlotController {
  PingPlotController({
    PingService? service,
    int windowSize = 60,
    Stream<PingProgress> Function({
      required String host,
      required int port,
      required Duration interval,
      required Duration timeout,
      Future<void>? cancel,
    })? pingStreamFactory,
  })  : assert(windowSize > 0, 'windowSize must be positive'),
        _windowSize = windowSize,
        _service = service ?? PingService(),
        // Keep the public param name clean (`pingStreamFactory`) rather than
        // leaking the private field name into the constructor signature.
        _pingStreamFactory = pingStreamFactory; // ignore: prefer_initializing_formals

  final PingService _service;
  final int _windowSize;
  final Stream<PingProgress> Function({
    required String host,
    required int port,
    required Duration interval,
    required Duration timeout,
    Future<void>? cancel,
  })? _pingStreamFactory;

  final StreamController<PingPlotState> _states =
      StreamController<PingPlotState>.broadcast();

  StreamSubscription<PingProgress>? _sub;
  Completer<void>? _cancel;
  final Stopwatch _clock = Stopwatch();

  // Bounded window of samples (oldest first), plus run-lifetime totals and the
  // jitter scratch (previous landed RTT) so the fold stays O(1) per reply.
  final List<PingSample> _window = <PingSample>[];
  int _seq = 0;
  int _totalSent = 0;
  int _totalReceived = 0;
  bool _running = false;
  bool _disposed = false;

  /// Live plot-state stream — one event per probe.
  Stream<PingPlotState> get states => _states.stream;

  /// True between [start] and [stop]/[dispose].
  bool get running => _running;

  /// The current snapshot (the latest emitted state, or empty before any run).
  PingPlotState get state => _snapshot();

  /// The retained window size (max samples kept for the chart).
  int get windowSize => _windowSize;

  /// Begin a sustained run against [host]:[port]. No-op if already running or
  /// disposed. Resets the window so a new run starts from a clean chart.
  void start({
    required String host,
    int port = PingService.defaultPort,
    Duration interval = const Duration(seconds: 1),
    Duration timeout = const Duration(seconds: 2),
  }) {
    if (_running || _disposed) return;

    _window.clear();
    _seq = 0;
    _totalSent = 0;
    _totalReceived = 0;
    _running = true;
    _clock
      ..reset()
      ..start();

    final Completer<void> cancel = Completer<void>();
    _cancel = cancel;

    final Stream<PingProgress> Function({
      required String host,
      required int port,
      required Duration interval,
      required Duration timeout,
      Future<void>? cancel,
    })? factory = _pingStreamFactory;
    final Stream<PingProgress> stream = factory != null
        ? factory(
            host: host,
            port: port,
            interval: interval,
            timeout: timeout,
            cancel: cancel.future,
          )
        : _service.ping(
            host: host,
            port: port,
            count: 0, // continuous until cancelled
            interval: interval,
            timeout: timeout,
            cancel: cancel.future,
          );

    _sub = stream.listen(
      _onProgress,
      onError: (Object e, StackTrace st) {
        if (!_states.isClosed) _states.addError(e, st);
        _teardown();
      },
      onDone: _teardown,
    );
  }

  /// Stop the run. Tears down the subscription, signals the engine cancel, and
  /// stops the clock. Retained state stays readable.
  void stop() => _teardown();

  /// Stop (if running) and close the stream. The controller is inert after.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _teardown();
    _states.close();
  }

  void _onProgress(PingProgress p) {
    if (_disposed) return;
    final PingReply r = p.reply;
    _seq++;
    _totalSent++;

    final bool lost = !(r.success && r.rtt != null);
    final double? rttMs =
        lost ? null : r.rtt!.inMicroseconds / 1000.0;
    if (!lost) _totalReceived++;

    _window.add(PingSample(
      sequence: _seq,
      elapsed: _clock.elapsed,
      rttMs: rttMs,
      lost: lost,
      errorLabel: lost ? (r.errorLabel ?? 'no reply') : null,
    ));
    // Bound the retained window — drop the oldest as it overflows so memory and
    // the chart stay fixed-size on a long run.
    while (_window.length > _windowSize) {
      _window.removeAt(0);
    }

    if (!_states.isClosed) _states.add(_snapshot());
  }

  /// Recompute the immutable snapshot over the retained window. Pure aside from
  /// reading the window/totals — no I/O.
  PingPlotState _snapshot() {
    int wSent = 0;
    int wReceived = 0;
    double? mn;
    double? mx;
    double sum = 0;
    int landed = 0;
    double? lastLanded;
    double? prevLanded;
    double jitterSum = 0;
    int jitterPairs = 0;

    for (final PingSample s in _window) {
      wSent++;
      if (s.lost || s.rttMs == null) {
        // A lost sample breaks the consecutive-RTT chain for jitter — the next
        // landed sample does not pair across the gap.
        prevLanded = null;
        continue;
      }
      wReceived++;
      final double v = s.rttMs!;
      landed++;
      sum += v;
      if (mn == null || v < mn) mn = v;
      if (mx == null || v > mx) mx = v;
      if (prevLanded != null) {
        jitterSum += (v - prevLanded).abs();
        jitterPairs++;
      }
      prevLanded = v;
      lastLanded = v;
    }

    // "last" reflects the literal most-recent sample: null if it was a loss.
    final PingSample? tail = _window.isEmpty ? null : _window.last;
    final double? lastMs =
        (tail != null && !tail.lost) ? tail.rttMs : null;

    return PingPlotState(
      samples: List<PingSample>.unmodifiable(_window),
      windowSent: wSent,
      windowReceived: wReceived,
      minMs: mn,
      avgMs: landed == 0 ? null : sum / landed,
      maxMs: mx,
      jitterMs: jitterPairs == 0 ? null : jitterSum / jitterPairs,
      lastMs: lastMs ?? (tail != null && tail.lost ? null : lastLanded),
      totalSent: _totalSent,
      totalReceived: _totalReceived,
    );
  }

  void _teardown() {
    _running = false;
    _clock.stop();
    final Completer<void>? cancel = _cancel;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
    _cancel = null;
    _sub?.cancel();
    _sub = null;
  }
}
