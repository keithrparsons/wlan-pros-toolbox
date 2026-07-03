import 'probes/throughput_probe.dart' show ProviderRate;
import 'quality_metric.dart';

/// Where a [QualityResult] came from.
enum QualitySource {
  /// Deterministic scripted data for tests and previews.
  mock,

  /// The real pure-Dart probe engine.
  ownEngine,
}

/// The outcome of one measurement: a list of individually graded metrics, the
/// source that produced them, and when it ran.
///
/// This model deliberately omits two things by design:
///   * A reliability pillar. Reliability needs continuous monitoring over time
///     (sustained loss, dropouts, route changes) that a single one-shot test
///     cannot honestly provide, so we do not report it.
///   * A single composite score. We grade each dimension individually; there
///     is no Orb measurement SDK and no honest way to roll the dimensions into
///     one headline number, so we do not.
class QualityResult {
  /// The graded metrics, transport dimensions first.
  final List<QualityMetric> metrics;

  /// What produced this result.
  final QualitySource source;

  /// When the measurement completed.
  final DateTime measuredAt;

  /// TEMPORARY tuning diagnostic (own-engine only): the per-provider download
  /// rates behind the headline Download metric, each flagged with whether it
  /// survived outlier rejection. Empty on the mock path and whenever the
  /// download stage failed. Lets a real-link run be pasted back with a full
  /// per-provider breakdown for tuning; strip before ship.
  final List<ProviderRate> downloadProviderRates;

  /// TEMPORARY tuning diagnostic: the sum of the surviving providers' rates
  /// (the current headline aggregation), in Mbps. Null when unavailable.
  final double? downloadSumOfSurvivors;

  /// TEMPORARY tuning diagnostic: the median of the surviving providers' rates,
  /// in Mbps (the alternative single-stream-style aggregation). Null when
  /// unavailable.
  final double? downloadMedianOfSurvivors;

  /// Creates a result.
  const QualityResult({
    required this.metrics,
    required this.source,
    required this.measuredAt,
    this.downloadProviderRates = const <ProviderRate>[],
    this.downloadSumOfSurvivors,
    this.downloadMedianOfSurvivors,
  });

  /// Returns the metric whose [QualityMetric.id] matches [id], or null.
  QualityMetric? metric(String id) {
    for (final m in metrics) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// JSON form.
  Map<String, Object?> toJson() => <String, Object?>{
        'source': source.name,
        'measuredAt': measuredAt.toIso8601String(),
        'metrics': metrics.map((m) => m.toJson()).toList(),
        if (downloadProviderRates.isNotEmpty)
          'downloadProviderRates': <Map<String, Object?>>[
            for (final p in downloadProviderRates)
              <String, Object?>{
                'host': p.host,
                'mbps': p.mbps,
                'includedInAggregate': p.includedInAggregate,
              },
          ],
        if (downloadSumOfSurvivors != null)
          'downloadSumOfSurvivors': downloadSumOfSurvivors,
        if (downloadMedianOfSurvivors != null)
          'downloadMedianOfSurvivors': downloadMedianOfSurvivors,
      };

  @override
  String toString() =>
      'QualityResult(${source.name}, ${metrics.length} metrics, '
      '$measuredAt)';
}
