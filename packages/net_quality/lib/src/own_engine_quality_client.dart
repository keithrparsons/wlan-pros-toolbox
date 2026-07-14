import 'dart:async';
import 'dart:io';

import 'probes/latency_probe.dart';
import 'probes/responsiveness_probe.dart';
import 'probes/throughput_probe.dart';
import 'quality_client.dart';
import 'quality_grade.dart';
import 'quality_metric.dart';
import 'quality_result.dart';
import 'scoring.dart';

/// The real pure-Dart [QualityClient]: composes the latency, throughput, and
/// responsiveness probes, grades each dimension, and emits a [QualityResult].
///
/// Probes are injected, so the whole engine runs deterministically in tests
/// with no real network. A probe that throws does not abort the measurement;
/// its metrics are reported as [QualityGrade.unavailable] instead.
class OwnEngineQualityClient implements QualityClient {
  /// Latency, jitter, and loss probe.
  final LatencyProbe latencyProbe;

  /// Download and upload probe.
  final ThroughputProbe throughputProbe;

  /// Loaded-responsiveness probe.
  final ResponsivenessProbe responsivenessProbe;

  /// Clock seam; defaults to [DateTime.now].
  final DateTime Function() clock;

  /// Stage-level wall-clock backstop for the whole throughput measurement
  /// (parallel download window + single upload window, each already hard-capped
  /// inside the probe). Defense-in-depth against the 40%-freeze class of bug:
  /// even a regressed/unbounded probe path cannot hang the tool past this. Set
  /// generously to never pre-empt a healthy real measurement — it is a safety
  /// net, not a tuning knob. Derived from the probe's per-transfer cap so it
  /// scales when the probe is reconfigured, AND from its whole-window retry
  /// budget so a single automatic retry of a stalled window is never clipped by
  /// the backstop (the backstop only fires on a genuine unbounded hang, not on
  /// a sanctioned retry). Two stages (download + upload), each able to run
  /// `1 + throughputRetries` windows.
  Duration get _throughputStageBudget =>
      throughputProbe.maxDuration *
          (2 * (1 + throughputProbe.throughputRetries)) +
      const Duration(seconds: 20);

  QualityResult? _lastResult;

  /// Highest fraction emitted so far this run, so [_emit] can guarantee the bar
  /// never goes backwards even if a stage finishes early or a band is re-entered.
  double _maxFraction = 0;

  /// Cadence of the elapsed-time progress ticker during a throughput window.
  /// ~120ms is smooth to the eye without flooding the stream/UI.
  static const Duration _tickInterval = Duration(milliseconds: 120);

  // --- Progress band map (time-weighted, not stage-count-weighted) ---
  //
  // The bar is allocated by EXPECTED STAGE DURATION, not by number of stages, so
  // its speed matches where the real time goes. Measured on macOS + iOS against
  // one.one.one.one / Cloudflare CDN, a typical healthy run spends roughly:
  //   - instant metrics (latency/jitter/loss): ~0.3–1.0 s  (10 sequential TCP
  //     connects)                                        → ~1–2 % of wall time
  //   - download window: ThroughputProbe.maxDuration      = ~10 s  → ~1/3
  //   - upload window:   ThroughputProbe.maxDuration      = ~10 s  → ~1/3
  //   - responsiveness:  idle baseline + a full ~10 s loaded window
  //                                                       = ~10 s  → ~1/3
  //
  // So instead of the old [0→0.40 instant][0.40→0.70 dl][0.70→0.90 ul]
  // [0.90→1.0 tail] map (which leapt to 40 % in under a second, then crawled,
  // and crammed the multi-second responsiveness stage into the last 10 %), the
  // bands below ease the bar to ~6 % quickly, then climb steadily and
  // continuously through the three slow ~10 s stages. Each slow band is filled
  // by real elapsed/maxDuration interpolation, and every emit is monotonic via
  // [_emit] and clamped to its band end (never overshoots).
  static const ({double start, double end}) _latencyBand =
      (start: 0.0, end: 0.06);
  static const ({double start, double end}) _downloadBand =
      (start: 0.06, end: 0.40);
  static const ({double start, double end}) _uploadBand =
      (start: 0.40, end: 0.72);
  static const ({double start, double end}) _responsivenessBand =
      (start: 0.72, end: 1.0);

  /// Builds a monotonic [QualityProgress]: clamps [fraction] to never drop below
  /// the highest already emitted, then records the new high-water mark.
  QualityProgress _emit(QualityPhase phase, double fraction) {
    final clamped = fraction < _maxFraction ? _maxFraction : fraction;
    _maxFraction = clamped;
    return QualityProgress(phase, clamped);
  }

  /// Creates a client from explicit probes.
  OwnEngineQualityClient({
    required this.latencyProbe,
    required this.throughputProbe,
    required this.responsivenessProbe,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  /// Builds a client targeting [host] with real probes.
  ///
  /// Responsiveness uses a TCP-connect RTT to [host]:[port] as its latency
  /// sampler and the throughput download as its load generator.
  factory OwnEngineQualityClient.forHost(
    String host, {
    int port = 443,
    DateTime Function()? clock,
  }) {
    final latencyProbe = LatencyProbe(host: host, port: port);
    final throughputProbe = ThroughputProbe();

    Future<Duration> sampleRtt() async {
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 2),
      );
      sw.stop();
      socket.destroy();
      return sw.elapsed;
    }

    final responsivenessProbe = ResponsivenessProbe(
      latencySampler: sampleRtt,
      loadGenerator: () => runResilientRpmLoad(throughputProbe),
    );

    return OwnEngineQualityClient(
      latencyProbe: latencyProbe,
      throughputProbe: throughputProbe,
      responsivenessProbe: responsivenessProbe,
      clock: clock,
    );
  }

  /// Runs the SINGLE-FLOW load for the responsiveness (RPM) stage, resilient to
  /// a flaky provider.
  ///
  /// RPM is single-flow BY DESIGN — it must never fan out into the parallel
  /// download pool. But it also must not fail just because one provider (e.g.
  /// Cloudflare, [ThroughputProbe.downloadEndpoints] index 0) is throttling us:
  /// the download POOL falls back fine, yet a load call pinned to a single flaky
  /// endpoint would throw and drag RPM to "Unavailable". So this walks the same
  /// diverse pool in order and stops at the FIRST endpoint whose single download
  /// flow runs. Only when EVERY endpoint fails does it throw (honest: no load
  /// could be generated, so RPM is genuinely unmeasurable) — never a fake value.
  static Future<void> runResilientRpmLoad(ThroughputProbe probe) async {
    Object? lastError;
    for (final endpoint in probe.downloadEndpoints) {
      try {
        // One healthy single-flow load for the whole RPM window is enough.
        await probe.downloader(endpoint, probe.maxDuration);
        return;
      } catch (e) {
        lastError = e; // try the next provider
      }
    }
    throw lastError ??
        const ThroughputUnmeasurable(
          'RPM load: no download endpoint available',
        );
  }

  @override
  bool get isAvailable => true;

  @override
  QualityResult? get lastResult => _lastResult;

  /// The note stamped on every metric the caller declined to measure. It names
  /// the REASON, so the UI never has to guess whether a null is "we failed" or
  /// "we did not try" (GL-005, the two kinds of null).
  static const String kSkippedNote = 'Not measured: the speed test was skipped '
      'to save cellular data';

  @override
  Stream<QualityProgress> measure({required bool includeThroughput}) async* {
    final metrics = <QualityMetric>[];
    _maxFraction = 0;

    // --- Latency / jitter / loss ---
    // The instant metrics finish in well under a second, so they only get a thin
    // front slice — the bar eases up to ~6 % here instead of leaping to 40 %.
    yield _emit(QualityPhase.latency, _latencyBand.start + 0.02);
    try {
      final s = await latencyProbe.measure();
      if (s.received == 0) {
        // No successful samples: latency and jitter are unmeasurable, but loss
        // is a real, reportable result (100 percent).
        metrics
          ..add(QualityMetric.unavailable(
            id: MetricIds.latency,
            label: 'Latency',
            unit: 'ms',
            note: 'No samples succeeded',
          ))
          ..add(QualityMetric.unavailable(
            id: MetricIds.jitter,
            label: 'Jitter',
            unit: 'ms',
            note: 'No samples succeeded',
          ))
          ..add(QualityMetric(
            id: MetricIds.loss,
            label: 'Loss',
            value: s.lossPct,
            unit: '%',
            grade: QualityScoring.gradeLossPct(s.lossPct),
          ));
      } else {
        metrics
          ..add(QualityMetric(
            id: MetricIds.latency,
            label: 'Latency',
            value: s.avgMs,
            unit: 'ms',
            grade: QualityScoring.gradeLatencyMs(s.avgMs),
          ))
          ..add(QualityMetric(
            id: MetricIds.jitter,
            label: 'Jitter',
            value: s.jitterMs,
            unit: 'ms',
            grade: QualityScoring.gradeJitterMs(s.jitterMs),
          ))
          ..add(QualityMetric(
            id: MetricIds.loss,
            label: 'Loss',
            value: s.lossPct,
            unit: '%',
            grade: QualityScoring.gradeLossPct(s.lossPct),
          ));
      }
    } catch (_) {
      metrics
        ..add(_failed(MetricIds.latency, 'Latency', 'ms'))
        ..add(_failed(MetricIds.jitter, 'Jitter', 'ms'))
        ..add(_failed(MetricIds.loss, 'Loss', '%'));
    }

    // --- Throughput ---
    // Honest elapsed-based progress: instead of one 0.40 emit that then freezes
    // until the whole stage returns, a periodic timer climbs the bar SMOOTHLY
    // through each measurement window — download fills the download band and
    // upload fills the upload band, each interpolated by elapsed/maxDuration.
    // The probe's `onStage` callback pivots the active band at the
    // download→upload boundary. Progress is clamped to the band end (never
    // overshoots) and the whole sequence is monotonic via [_emit]. Early
    // completion of a stage simply stops climbing at that band's end fraction;
    // the next yield carries it on. The CDN-fix hard deadlines still hold: a
    // stalled endpoint aborts the stage inside the probe (and
    // `_throughputStageBudget` is the outer backstop), after which the bar
    // advances to the stage's end as before.
    // THE TWO DATA-HUNGRY STAGES, BOTH GATED TOGETHER (Keith, 2026-07-13).
    //
    // NEITHER IS BYTE-BOUNDED. The throughput stage opens a fixed ~15 s window
    // and keeps re-requesting until it closes, so it transfers `rate x window` —
    // the faster the link, the more data it burns. The responsiveness stage is
    // just as expensive and far less obvious: its LOAD GENERATOR is another
    // full-window single-flow download ([runResilientRpmLoad]). Skipping the
    // "speed test" while leaving RPM running would still burn ~15 s of data at
    // full rate, so the two are gated as one unit.
    //
    // What survives when they are skipped: latency, jitter and loss, which are
    // small TCP-connect samples. That is a genuinely useful result, and it is
    // what a user who declines the data cost still gets.
    if (includeThroughput) {
      yield _emit(QualityPhase.download, _downloadBand.start);
      yield* _runThroughputStage(metrics);

      // --- Responsiveness ---
      // The loaded-responsiveness stage runs a full ~10 s load window, so it gets
      // its own ~1/3 band and the SAME elapsed-time ticker as the throughput
      // stages — it climbs smoothly across the back third rather than jumping to
      // 0.90 and sitting frozen while the load runs (the old behavior).
      yield _emit(QualityPhase.responsiveness, _responsivenessBand.start);
      yield* _runResponsivenessStage(metrics);
    } else {
      // HONESTLY UNAVAILABLE, WITH THE REASON. Not zero, not omitted: a metric
      // we chose not to take is a different null from one we tried and failed to
      // take, and the note is what lets the UI say which (GL-005).
      metrics
        ..add(const QualityMetric.unavailable(
          id: MetricIds.download,
          label: 'Download',
          unit: 'Mbps',
          note: kSkippedNote,
        ))
        ..add(const QualityMetric.unavailable(
          id: MetricIds.upload,
          label: 'Upload',
          unit: 'Mbps',
          note: kSkippedNote,
        ))
        ..add(const QualityMetric.unavailable(
          id: MetricIds.responsiveness,
          label: 'Responsiveness',
          unit: 'RPM',
          note: kSkippedNote,
        ));
    }

    _lastResult = QualityResult(
      metrics: metrics,
      source: QualitySource.ownEngine,
      measuredAt: clock(),
    );
    yield _emit(QualityPhase.complete, 1.0);
  }

  /// Runs the throughput probe while a periodic ticker emits smooth,
  /// elapsed-based progress, and folds the resulting metrics into [metrics].
  ///
  /// A [StreamController] bridges the timer (which cannot `yield` from the
  /// generator) to this stream: the ticker pushes interpolated fractions and
  /// the probe future, once awaited, pushes the final metrics and closes the
  /// controller. The download band fills [_downloadBand] and the upload band
  /// [_uploadBand], each `currentBandStart + span * (elapsed / maxDuration)`,
  /// clamped to the band end so it never overshoots into the next stage. All
  /// emits go through [_emit] so the bar stays monotonic.
  Stream<QualityProgress> _runThroughputStage(
    List<QualityMetric> metrics,
  ) {
    const downloadBand = _downloadBand;
    const uploadBand = _uploadBand;

    final controller = StreamController<QualityProgress>();
    final maxDuration = throughputProbe.maxDuration;

    // The active band and the wall-clock start of the current window. The probe
    // calls back synchronously at each stage boundary so these flip in lockstep
    // with the real download→upload transition.
    var bandStart = downloadBand.start;
    var bandEnd = downloadBand.end;
    var stageStartedAt = clock();
    var phase = QualityPhase.download;

    void onStage(ThroughputStage stage) {
      switch (stage) {
        case ThroughputStage.download:
          bandStart = downloadBand.start;
          bandEnd = downloadBand.end;
          phase = QualityPhase.download;
        case ThroughputStage.upload:
          // Snap the bar to the download band's end before the upload band
          // begins, so the download stage never reads as unfinished.
          if (!controller.isClosed) {
            controller.add(_emit(QualityPhase.download, downloadBand.end));
          }
          bandStart = uploadBand.start;
          bandEnd = uploadBand.end;
          phase = QualityPhase.upload;
      }
      stageStartedAt = clock();
    }

    Timer? ticker;
    void tick(_) {
      if (controller.isClosed) return;
      final elapsed = clock().difference(stageStartedAt);
      final span = bandEnd - bandStart;
      final ratio = maxDuration.inMicroseconds <= 0
          ? 1.0
          : elapsed.inMicroseconds / maxDuration.inMicroseconds;
      final clampedRatio = ratio < 0
          ? 0.0
          : ratio > 1
              ? 1.0
              : ratio;
      // Stop a hair short of the band end while the stage is still running, so
      // the natural "stage complete" snap (above / below) is what reaches the
      // band boundary — the ticker never claims a stage finished early.
      final target = bandStart + span * clampedRatio;
      final capped = target > bandEnd ? bandEnd : target;
      controller.add(_emit(phase, capped));
    }

    Future<void> drive() async {
      ticker = Timer.periodic(_tickInterval, tick);
      try {
        // Stage-level wall-clock backstop. The probe's per-transfer deadlines
        // are the primary guard; this is defense-in-depth so a seam regression
        // can never freeze the whole tool at the download stage (the 40%-freeze
        // class of bug). Budget covers a parallel download window + an upload
        // window, each already hard-capped inside the probe, plus slack.
        final t = await throughputProbe
            .measure(onStage: onStage)
            .timeout(_throughputStageBudget);
        ticker?.cancel();
        // Snap to the upload band end on success.
        if (!controller.isClosed) {
          controller.add(_emit(QualityPhase.upload, uploadBand.end));
        }
        metrics
          ..add(QualityMetric(
            id: MetricIds.download,
            label: 'Download',
            value: t.downloadMbps,
            unit: 'Mbps',
            grade: QualityScoring.gradeDownloadMbps(t.downloadMbps),
          ))
          ..add(QualityMetric(
            id: MetricIds.upload,
            label: 'Upload',
            value: t.uploadMbps,
            unit: 'Mbps',
            grade: QualityScoring.gradeUploadMbps(t.uploadMbps),
          ));
      } catch (_) {
        ticker?.cancel();
        if (!controller.isClosed) {
          controller.add(_emit(QualityPhase.upload, uploadBand.end));
        }
        metrics
          ..add(_failed(MetricIds.download, 'Download', 'Mbps'))
          ..add(_failed(MetricIds.upload, 'Upload', 'Mbps'));
      } finally {
        ticker?.cancel();
        if (!controller.isClosed) await controller.close();
      }
    }

    // Cancel the ticker if the consumer stops listening early (screen disposed).
    controller.onCancel = () => ticker?.cancel();

    unawaited(drive());
    return controller.stream;
  }

  /// Runs the responsiveness probe while the SAME elapsed-time ticker climbs
  /// the bar smoothly across [_responsivenessBand], then folds the metric into
  /// [metrics].
  ///
  /// The probe's load window is a single ~[ThroughputProbe.maxDuration]
  /// download, so the band is interpolated by `elapsed / maxDuration` — the bar
  /// crawls from 0.72 toward 1.0 instead of jumping to 0.90 and freezing while
  /// the ~10 s load runs (the old behavior). It is clamped a hair below the band
  /// end while running; the real "complete" emit (1.0) lands from [measure]
  /// after the metric is in hand. All emits go through [_emit] (monotonic).
  Stream<QualityProgress> _runResponsivenessStage(
    List<QualityMetric> metrics,
  ) {
    const band = _responsivenessBand;
    final controller = StreamController<QualityProgress>();
    final maxDuration = throughputProbe.maxDuration;
    final stageStartedAt = clock();

    Timer? ticker;
    void tick(_) {
      if (controller.isClosed) return;
      final elapsed = clock().difference(stageStartedAt);
      final span = band.end - band.start;
      final ratio = maxDuration.inMicroseconds <= 0
          ? 1.0
          : elapsed.inMicroseconds / maxDuration.inMicroseconds;
      final clampedRatio = ratio < 0
          ? 0.0
          : ratio > 1
              ? 1.0
              : ratio;
      // Stop a hair short of the band end while the stage runs, so the natural
      // completion emit (1.0, from [measure]) is what reaches 100 %.
      final target = band.start + span * clampedRatio;
      final ceiling = band.end - 0.01;
      final capped = target > ceiling ? ceiling : target;
      controller.add(_emit(QualityPhase.responsiveness, capped));
    }

    Future<void> drive() async {
      ticker = Timer.periodic(_tickInterval, tick);
      try {
        final r = await responsivenessProbe
            .measure()
            .timeout(_throughputStageBudget);
        metrics.add(QualityMetric(
          id: MetricIds.responsiveness,
          label: 'Responsiveness',
          value: r.rpm,
          unit: 'RPM',
          grade: QualityScoring.gradeResponsivenessRpm(r.rpm),
          note: 'Simplified single-flow estimate inspired by RFC 9097',
        ));
      } catch (_) {
        metrics.add(_failed(
          MetricIds.responsiveness,
          'Responsiveness',
          'RPM',
        ));
      } finally {
        ticker?.cancel();
        if (!controller.isClosed) await controller.close();
      }
    }

    // Cancel the ticker if the consumer stops listening early (screen disposed).
    controller.onCancel = () => ticker?.cancel();

    unawaited(drive());
    return controller.stream;
  }

  /// Builds an unavailable metric for a probe that threw.
  static QualityMetric _failed(String id, String label, String unit) =>
      QualityMetric.unavailable(
        id: id,
        label: label,
        unit: unit,
        note: 'Measurement failed',
      );
}
