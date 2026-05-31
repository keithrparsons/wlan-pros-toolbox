import 'package:net_quality/net_quality.dart';
import 'package:test/test.dart';

void main() {
  group('MockQualityClient', () {
    test('is available', () {
      expect(MockQualityClient().isAvailable, isTrue);
    });

    test('emits phases in order ending at complete with fraction 1.0', () async {
      final client = MockQualityClient();
      final ticks = await client.measure().toList();

      expect(ticks.map((t) => t.phase), [
        QualityPhase.latency,
        QualityPhase.download,
        QualityPhase.upload,
        QualityPhase.complete,
      ]);
      expect(ticks.last.fraction, 1.0);
    });

    test('populates lastResult after measuring, tagged as mock', () async {
      final client = MockQualityClient();
      expect(client.lastResult, isNull);
      await client.measure().drain<void>();
      expect(client.lastResult, isNotNull);
      expect(client.lastResult!.qualityScore, inInclusiveRange(0, 100));
      expect(client.lastResult!.source, QualitySource.mock);
    });

    test('honors an injected scripted result', () async {
      final scripted = QualityResult(
        qualityScore: 42,
        responsiveness: 40,
        latencyMs: 99.0,
        jitterMs: 12.0,
        packetLossPct: 1.5,
        downloadMbps: 10.0,
        uploadMbps: 3.0,
        source: QualitySource.mock,
        measuredAt: DateTime.utc(2026, 1, 1),
      );
      final client = MockQualityClient(scriptedResult: scripted);
      await client.measure().drain<void>();
      expect(client.lastResult!.qualityScore, 42);
      expect(client.lastResult!.downloadMbps, 10.0);
    });
  });

  group('QualityResult', () {
    test('serializes to json with all fields including source', () {
      final result = QualityResult(
        qualityScore: 87,
        responsiveness: 82,
        latencyMs: 14.0,
        jitterMs: 2.3,
        packetLossPct: 0.0,
        downloadMbps: 512.4,
        uploadMbps: 48.7,
        source: QualitySource.ownEngine,
        measuredAt: DateTime.utc(2026, 1, 1),
      );
      final json = result.toJson();
      expect(json.keys, containsAll([
        'qualityScore',
        'responsiveness',
        'latencyMs',
        'jitterMs',
        'packetLossPct',
        'downloadMbps',
        'uploadMbps',
        'source',
        'measuredAt',
      ]));
      expect(json['source'], 'ownEngine');
      expect(json['measuredAt'], '2026-01-01T00:00:00.000Z');
    });
  });
}
