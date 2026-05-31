/// Where a [QualityResult]'s numbers came from. Recorded so the UI can label
/// results honestly and never show an Orb/Ookla mark next to values we computed
/// ourselves. (No Orb measurement SDK exists — see the 2026-05-31 feasibility
/// brief.)
enum QualitySource {
  /// Synthetic data from [MockQualityClient]; never shown as a real result.
  mock,

  /// Computed by our own dart:io engine.
  ownEngine,
}

/// The outcome of a single one-shot network-quality measurement.
///
/// Deliberately omits a "reliability" pillar: reliability requires continuous
/// monitoring over time and cannot be produced by a one-shot test, so claiming
/// it would be dishonest. We measure what a single run can actually establish.
class QualityResult {
  /// Our overall quality score, 0-100 (higher is better). This is OUR
  /// computation, not an Orb Score.
  final int qualityScore;

  /// Responsiveness sub-score, 0-100: latency under working load
  /// (RFC 9097 / RPM-style). Our computation.
  final int responsiveness;

  /// Idle round-trip latency, milliseconds.
  final double latencyMs;

  /// Latency variation, milliseconds.
  final double jitterMs;

  /// Packet loss, percent (0-100).
  final double packetLossPct;

  /// Download throughput, megabits per second.
  final double downloadMbps;

  /// Upload throughput, megabits per second.
  final double uploadMbps;

  /// Provenance of these numbers.
  final QualitySource source;

  /// When the measurement completed.
  final DateTime measuredAt;

  const QualityResult({
    required this.qualityScore,
    required this.responsiveness,
    required this.latencyMs,
    required this.jitterMs,
    required this.packetLossPct,
    required this.downloadMbps,
    required this.uploadMbps,
    required this.source,
    required this.measuredAt,
  });

  Map<String, Object> toJson() => {
        'qualityScore': qualityScore,
        'responsiveness': responsiveness,
        'latencyMs': latencyMs,
        'jitterMs': jitterMs,
        'packetLossPct': packetLossPct,
        'downloadMbps': downloadMbps,
        'uploadMbps': uploadMbps,
        'source': source.name,
        'measuredAt': measuredAt.toIso8601String(),
      };

  @override
  String toString() => 'QualityResult(score: $qualityScore, '
      'down: ${downloadMbps.toStringAsFixed(1)} Mbps, '
      'up: ${uploadMbps.toStringAsFixed(1)} Mbps, '
      'latency: ${latencyMs.toStringAsFixed(0)} ms, '
      'source: ${source.name})';
}
