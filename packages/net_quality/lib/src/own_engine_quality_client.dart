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
  /// scales when the probe is reconfigured.
  Duration get _throughputStageBudget =>
      throughputProbe.maxDuration * 2 + const Duration(seconds: 20);

  QualityResult? _lastResult;

  /// Highest fraction emitted so far this run, so [_emit] can guarantee the bar
  /// never goes backwards even if a stage finishes early or a band is re-entered.
  double _maxFraction = 0;

  /// Cadence of the elapsed-time progress ticker during a throughput window.
  /// ~120ms is smooth to the eye without flooding the stream/UI.
  static const Duration _tickInterval = Duration(milliseconds: 120);

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
      loadGenerator: () async {
        await throughputProbe.downloader(
          throughputProbe.downloadEndpoint,
          throughputProbe.maxDuration,
        );
      },
    );

    return OwnEngineQualityClient(
      latencyProbe: latencyProbe,
      throughputProbe: throughputProbe,
      responsivenessProbe: responsivenessProbe,
      clock: clock,
    );
  }

  @override
  bool get isAvailable => true;

  @override
  QualityResult? get lastResult => _lastResult;

  @override
  Stream<QualityProgress> measure() async* {
    final metrics = <QualityMetric>[];
    _maxFraction = 0;

    // --- Latency / jitter / loss ---
    yield _emit(QualityPhase.latency, 0.1);
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
    // through each measurement window — download fills 0.40→0.70 and upload
    // fills 0.70→0.90, each interpolated by elapsed/maxDuration. The probe's
    // `onStage` callback pivots the active band at the download→upload boundary.
    // Progress is clamped to the band end (never overshoots) and the whole
    // sequence is monotonic via [_emit]. Early completion of a stage simply
    // stops climbing at that band's end fraction; the next yield carries it on.
    // The CDN-fix hard deadlines still hold: a stalled endpoint aborts the
    // stage inside the probe (and `_throughputStageBudget` is the outer
    // backstop), after which the bar advances to the stage's end as before.
    yield _emit(QualityPhase.download, 0.4);
    yield* _runThroughputStage(metrics);

    // --- Responsiveness ---
    yield _emit(QualityPhase.upload, 0.9);
    try {
      final r = await responsivenessProbe.measure();
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
  /// controller. The download band fills 0.40→0.70 and the upload band
  /// 0.70→0.90, each `currentBandStart + span * (elapsed / maxDuration)`,
  /// clamped to the band end so it never overshoots into the next stage. All
  /// emits go through [_emit] so the bar stays monotonic.
  Stream<QualityProgress> _runThroughputStage(
    List<QualityMetric> metrics,
  ) {
    const downloadBand = (start: 0.40, end: 0.70);
    const uploadBand = (start: 0.70, end: 0.90);

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

  /// Builds an unavailable metric for a probe that threw.
  static QualityMetric _failed(String id, String label, String unit) =>
      QualityMetric.unavailable(
        id: id,
        label: label,
        unit: unit,
        note: 'Measurement failed',
      );
}
