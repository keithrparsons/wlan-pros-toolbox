import 'quality_result.dart';

/// Lifecycle of a running measurement, for the UI to render progress.
enum QualityPhase { idle, latency, download, upload, complete, failed }

/// A progress tick emitted while a measurement runs.
class QualityProgress {
  final QualityPhase phase;

  /// 0.0-1.0 overall completion.
  final double fraction;

  const QualityProgress(this.phase, this.fraction);
}

/// The single seam between the toolbox and any measurement backend.
///
/// The toolbox talks only to this interface. [MockQualityClient] satisfies it
/// today with synthetic data; the real dart:io engine will satisfy the same
/// contract with no UI changes.
abstract interface class QualityClient {
  /// True when this backend can actually run a measurement on the current
  /// platform. A backend that is unavailable returns false rather than
  /// throwing, so the UI can show an honest "unavailable" state.
  bool get isAvailable;

  /// Runs one measurement, emitting [QualityProgress] ticks, and resolves with
  /// the final [QualityResult]. Throws [StateError] if [isAvailable] is false.
  Stream<QualityProgress> measure();

  /// The result of the most recent completed measurement, or null.
  QualityResult? get lastResult;
}
