import 'own_engine_quality_client.dart';
import 'quality_client.dart';
import 'quality_grade.dart';
import 'quality_metric.dart';
import 'quality_result.dart';

/// A deterministic [QualityClient] for tests and UI previews.
///
/// It performs no network I/O. It emits a fixed progress sequence and exposes a
/// scripted [QualityResult]. The default script is a healthy connection.
class MockQualityClient implements QualityClient {
  /// The result this client reports. Override to script other scenarios.
  final QualityResult scriptedResult;

  QualityResult? _lastResult;

  /// Creates a mock client. Pass [scriptedResult] to override the default
  /// healthy-connection script.
  MockQualityClient({QualityResult? scriptedResult})
      : scriptedResult = scriptedResult ?? _defaultResult();

  @override
  bool get isAvailable => true;

  @override
  QualityResult? get lastResult => _lastResult;

  /// Whether the last [measure] call was asked to include the throughput stages.
  /// Exposed so a test can assert that the data-hungry stages were NOT requested
  /// without consent — the consent gate is only real if the bytes never move.
  bool lastIncludeThroughput = true;

  @override
  Stream<QualityProgress> measure({bool includeThroughput = true}) async* {
    lastIncludeThroughput = includeThroughput;
    yield const QualityProgress(QualityPhase.latency, 0.25);
    if (includeThroughput) {
      yield const QualityProgress(QualityPhase.download, 0.5);
      yield const QualityProgress(QualityPhase.upload, 0.75);
    }
    // Mirror the real engine: the gated metrics come back honestly unavailable
    // with the "not measured" reason, never as a fabricated zero and never
    // silently dropped.
    _lastResult = includeThroughput
        ? scriptedResult
        : _withoutThroughput(scriptedResult);
    yield const QualityProgress(QualityPhase.complete, 1.0);
  }

  /// Replaces the three data-hungry metrics with their honest unavailable form,
  /// preserving the cheap latency / jitter / loss samples that DID run.
  static QualityResult _withoutThroughput(QualityResult r) {
    const Set<String> gated = <String>{
      MetricIds.download,
      MetricIds.upload,
      MetricIds.responsiveness,
    };
    return QualityResult(
      source: r.source,
      measuredAt: r.measuredAt,
      metrics: <QualityMetric>[
        for (final QualityMetric m in r.metrics)
          if (!gated.contains(m.id))
            m
          else
            QualityMetric.unavailable(
              id: m.id,
              label: m.label,
              unit: m.unit,
              note: OwnEngineQualityClient.kSkippedNote,
            ),
      ],
    );
  }

  /// The default healthy-connection script: six graded transport metrics.
  static QualityResult _defaultResult() => QualityResult(
        source: QualitySource.mock,
        measuredAt: DateTime.utc(2026, 1, 1),
        metrics: const <QualityMetric>[
          QualityMetric(
            id: MetricIds.latency,
            label: 'Latency',
            value: 14,
            unit: 'ms',
            grade: QualityGrade.excellent,
          ),
          QualityMetric(
            id: MetricIds.jitter,
            label: 'Jitter',
            value: 2.3,
            unit: 'ms',
            grade: QualityGrade.excellent,
          ),
          QualityMetric(
            id: MetricIds.loss,
            label: 'Loss',
            value: 0,
            unit: '%',
            grade: QualityGrade.excellent,
          ),
          QualityMetric(
            id: MetricIds.download,
            label: 'Download',
            value: 512.4,
            unit: 'Mbps',
            grade: QualityGrade.excellent,
          ),
          QualityMetric(
            id: MetricIds.upload,
            label: 'Upload',
            value: 48.7,
            unit: 'Mbps',
            grade: QualityGrade.good,
          ),
          QualityMetric(
            id: MetricIds.responsiveness,
            label: 'Responsiveness',
            value: 820,
            unit: 'RPM',
            grade: QualityGrade.good,
          ),
        ],
      );
}
