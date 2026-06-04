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

    // --- Latency / jitter / loss ---
    yield const QualityProgress(QualityPhase.latency, 0.1);
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
    yield const QualityProgress(QualityPhase.download, 0.4);
    try {
      // Stage-level wall-clock backstop. The probe's per-transfer deadlines are
      // the primary guard; this is defense-in-depth so a future seam regression
      // can never freeze the whole tool at the download stage (the 40%-freeze
      // class of bug). Budget covers a parallel download window + an upload
      // window, each already hard-capped inside the probe, plus slack.
      final t = await throughputProbe.measure().timeout(_throughputStageBudget);
      yield const QualityProgress(QualityPhase.upload, 0.7);
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
      yield const QualityProgress(QualityPhase.upload, 0.7);
      metrics
        ..add(_failed(MetricIds.download, 'Download', 'Mbps'))
        ..add(_failed(MetricIds.upload, 'Upload', 'Mbps'));
    }

    // --- Responsiveness ---
    yield const QualityProgress(QualityPhase.upload, 0.85);
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
    yield const QualityProgress(QualityPhase.complete, 1.0);
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
