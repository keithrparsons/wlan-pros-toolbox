import 'quality_client.dart';
import 'quality_result.dart';

/// A deterministic, network-free [QualityClient] for building and testing the
/// UI before the real engine exists. Emits a scripted progress sequence and a
/// fixed result so widget tests and the standalone harness are reproducible.
class MockQualityClient implements QualityClient {
  final QualityResult _scriptedResult;
  QualityResult? _lastResult;

  MockQualityClient({QualityResult? scriptedResult})
      : _scriptedResult = scriptedResult ?? _defaultResult;

  static final QualityResult _defaultResult = QualityResult(
    qualityScore: 87,
    responsiveness: 82,
    latencyMs: 14.0,
    jitterMs: 2.3,
    packetLossPct: 0.0,
    downloadMbps: 512.4,
    uploadMbps: 48.7,
    source: QualitySource.mock,
    // Fixed timestamp keeps tests deterministic.
    measuredAt: DateTime.utc(2026, 1, 1),
  );

  @override
  bool get isAvailable => true;

  @override
  QualityResult? get lastResult => _lastResult;

  @override
  Stream<QualityProgress> measure() async* {
    yield const QualityProgress(QualityPhase.latency, 0.1);
    yield const QualityProgress(QualityPhase.download, 0.5);
    yield const QualityProgress(QualityPhase.upload, 0.85);
    _lastResult = _scriptedResult;
    yield const QualityProgress(QualityPhase.complete, 1.0);
  }
}
