import 'quality_result.dart';

/// Phases a one-shot measurement passes through, in order.
enum QualityPhase {
  /// Nothing measured yet.
  idle,

  /// Measuring latency, jitter, and loss.
  latency,

  /// Measuring download throughput.
  download,

  /// Measuring upload throughput.
  upload,

  /// Measuring loaded responsiveness (latency under load).
  responsiveness,

  /// Measurement finished successfully; [QualityClient.lastResult] is set.
  complete,

  /// Measurement failed before producing a result.
  failed,
}

/// A progress event emitted during a measurement.
class QualityProgress {
  /// Current phase.
  final QualityPhase phase;

  /// Overall completion fraction in the range 0.0 to 1.0, monotonic.
  final double fraction;

  /// Creates a progress event.
  const QualityProgress(this.phase, this.fraction);

  @override
  String toString() =>
      'QualityProgress(${phase.name}, ${fraction.toStringAsFixed(2)})';
}

/// The single seam between the toolbox and any measurement backend.
///
/// Implementations include a deterministic [mock] for tests and previews and a
/// real pure-Dart engine. The toolbox depends only on this interface, never on
/// a concrete probe, so the backend can be swapped without touching the UI.
abstract interface class QualityClient {
  /// Whether this client can run a measurement on the current platform.
  ///
  /// A client may be unavailable, for example, in an environment with no
  /// network stack. Implementations report this honestly rather than throwing.
  bool get isAvailable;

  /// Runs one measurement, emitting [QualityProgress] events as it goes and
  /// completing when finished.
  ///
  /// On success the stream ends after a [QualityPhase.complete] event and
  /// [lastResult] holds the graded result. On failure the stream ends after a
  /// [QualityPhase.failed] event.
  Stream<QualityProgress> measure();

  /// The most recent successful result, or null if no measurement has
  /// completed yet.
  QualityResult? get lastResult;
}
