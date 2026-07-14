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
  ///
  /// [includeThroughput] gates the two DATA-HUNGRY stages: the throughput
  /// measurement (download + upload) and the responsiveness (RPM) probe, whose
  /// load generator is itself a full-window download. When false, ONLY the cheap
  /// latency / jitter / loss samples run, and the four gated metrics come back
  /// as honestly UNAVAILABLE with a "not measured" note — never as a fabricated
  /// zero, and never as a silent omission.
  ///
  /// WHY THIS EXISTS (Keith, 2026-07-13). Neither stage is byte-bounded: each
  /// downloads for a fixed WINDOW at whatever rate the link achieves, so the data
  /// transferred scales with connection speed (see [ThroughputProbe.maxDuration]).
  /// On cellular that is roughly 50 MB on a slow link and 500 MB or more on fast
  /// 5G. A Wi-Fi professional on an expensive roaming plan must never have an app
  /// silently burn that. Test My Connection warns, then passes `false` here unless
  /// the user explicitly consents.
  Stream<QualityProgress> measure({bool includeThroughput = true});

  /// The most recent successful result, or null if no measurement has
  /// completed yet.
  QualityResult? get lastResult;
}
