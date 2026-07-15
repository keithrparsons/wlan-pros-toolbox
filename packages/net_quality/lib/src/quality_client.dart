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
  ///
  /// Meaningless when [indeterminate] is true — hold the last determinate value
  /// for layout if you must, but do not present it as a claim about how far
  /// along the run is.
  final double fraction;

  /// True when the engine no longer knows how much longer this stage will take,
  /// so the UI must show an INDETERMINATE state rather than a number.
  ///
  /// WHY THIS EXISTS (Keith, 2026-07-14). Every stage ticks its band by
  /// `elapsed / expectedWindow`. When a stage OUTRUNS its expected window the
  /// ratio clamps to 1.0, and from that moment every tick emits the SAME
  /// fraction — the bar sits on one number, sometimes for tens of seconds. That
  /// is a frozen bar, and a frozen bar reads as a HANG. (Measured on the real
  /// engine: a load 6x its window produced 10 emits, 3 distinct, then SEVEN
  /// consecutive identical emits at 0.99.)
  ///
  /// The honest fix is NOT a bigger denominator — that is just a better guess.
  /// Once a stage outruns its known window the remaining time is genuinely
  /// UNKNOWN, and the bar must say so. A determinate bar that advances on a
  /// timer while nothing is happening is the same species of lie as a stale
  /// LIVE badge: it asserts knowledge the app does not have.
  final bool indeterminate;

  /// Creates a progress event.
  const QualityProgress(
    this.phase,
    this.fraction, {
    this.indeterminate = false,
  });

  @override
  String toString() => 'QualityProgress(${phase.name}, '
      '${indeterminate ? 'indeterminate' : fraction.toStringAsFixed(2)})';
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
  /// A Wi-Fi professional on an expensive roaming plan must never have an app
  /// silently burn that. Test My Connection warns, then passes `false` here unless
  /// the user explicitly consents.
  ///
  /// DO NOT restate the data cost in prose here. It is DERIVED from the probe
  /// constants in [CellularDataCost], and a re-derivation guard test fails if the
  /// constants drift away from the sentence the user is shown. A figure copied
  /// into a comment is a figure that goes stale silently — which is exactly what
  /// happened to the "about 30 seconds" claim when the RPM stage stopped running
  /// on cellular.
  /// [includeThroughput] IS REQUIRED, AND HAS NO DEFAULT. THIS IS LOAD-BEARING.
  ///
  /// It used to default to `true`. A default on THIS declaration is a default on
  /// the only interface through which the bytes are ever spent, so any caller
  /// could burn 50-500 MB of a user's cellular data by simply not knowing the
  /// parameter existed — which is exactly what `NetworkQualityScreen` did
  /// (`_client.measure()`, bare, no warning, no decline path, on a shipped and
  /// iOS-live tool). Test My Connection's gate was never the whole gate; it was
  /// one caller being careful while the door stood open.
  ///
  /// Required means the COMPILER asks the question at every call site. Do not add
  /// a default back to silence the analyzer: the analyzer complaining IS the
  /// control working.
  ///
  /// [includeResponsiveness] gates the RPM stage SPECIFICALLY. Pass `false` on a
  /// cellular link. It is REQUIRED for exactly the same reason
  /// [includeThroughput] is: the RPM stage's load generator is a FULL-RATE
  /// DOWNLOAD, ADDITIONAL to the throughput stage, so this parameter also spends
  /// the user's money. A default here would be a default on a spend.
  ///
  /// WHY NOT JUST SHORTEN THE WINDOW ON CELLULAR (Keith, 2026-07-14). Because a
  /// shorter load window is not merely "less accurate" — it is BIASED, and it is
  /// biased in the flattering direction. The load is what saturates the link; cut
  /// it short and the link never fully loads, so loaded latency is UNDERSTATED
  /// and `rpm = 60000 / loadedAvg` comes out TOO HIGH. The app would report a
  /// number better than the truth, which is the exact failure this codebase
  /// exists to not repeat.
  ///
  /// RPM is an ADJUNCT to what these tools are for. Declining to measure an
  /// adjunct is a legitimate answer, and it is the honest one: it is faster, it
  /// spends less cellular data, and it makes no claim it cannot back. The skipped
  /// metric comes back UNAVAILABLE with a note that names the CHOICE and its
  /// REASON — never a failure string, never a fabricated zero.
  Stream<QualityProgress> measure({
    required bool includeThroughput,
    required bool includeResponsiveness,
  });

  /// The most recent successful result, or null if no measurement has
  /// completed yet.
  QualityResult? get lastResult;
}
