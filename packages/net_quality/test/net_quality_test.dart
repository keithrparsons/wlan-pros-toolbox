import 'package:net_quality/net_quality.dart';
import 'package:test/test.dart';

void main() {
  group('MockQualityClient', () {
    test('is available', () {
      expect(MockQualityClient().isAvailable, isTrue);
    });

    test('emits phases in order ending complete=1.0', () async {
      final client = MockQualityClient();
      final events = await client.measure(includeThroughput: true).toList();

      expect(
        events.map((e) => e.phase).toList(),
        <QualityPhase>[
          QualityPhase.latency,
          QualityPhase.download,
          QualityPhase.upload,
          QualityPhase.complete,
        ],
      );
      expect(events.last.fraction, 1.0);

      // Fraction is monotonic non-decreasing.
      for (var i = 1; i < events.length; i++) {
        expect(events[i].fraction, greaterThanOrEqualTo(events[i - 1].fraction));
      }
    });

    test('sets lastResult after measure', () async {
      final client = MockQualityClient();
      expect(client.lastResult, isNull);
      await client.measure(includeThroughput: true).drain<void>();
      expect(client.lastResult, isNotNull);
      expect(client.lastResult!.source, QualitySource.mock);
    });

    test('default result has the six graded transport metrics', () async {
      final client = MockQualityClient();
      await client.measure(includeThroughput: true).drain<void>();
      final result = client.lastResult!;

      final ids = result.metrics.map((m) => m.id).toList();
      expect(ids, <String>[
        MetricIds.latency,
        MetricIds.jitter,
        MetricIds.loss,
        MetricIds.download,
        MetricIds.upload,
        MetricIds.responsiveness,
      ]);

      for (final m in result.metrics) {
        expect(m.grade, isNot(QualityGrade.unavailable));
        expect(m.value, isNotNull);
      }

      expect(result.metric(MetricIds.latency)!.grade, QualityGrade.excellent);
      expect(result.metric(MetricIds.upload)!.grade, QualityGrade.good);
      expect(result.metric(MetricIds.responsiveness)!.grade, QualityGrade.good);
    });

    test('honors an injected scripted result', () async {
      final scripted = QualityResult(
        source: QualitySource.mock,
        measuredAt: DateTime.utc(2030, 6, 6),
        metrics: const <QualityMetric>[
          QualityMetric(
            id: MetricIds.latency,
            label: 'Latency',
            value: 200,
            unit: 'ms',
            grade: QualityGrade.poor,
          ),
        ],
      );
      final client = MockQualityClient(scriptedResult: scripted);
      await client.measure(includeThroughput: true).drain<void>();

      expect(client.lastResult, same(scripted));
      expect(client.lastResult!.metrics.single.grade, QualityGrade.poor);
      expect(client.lastResult!.measuredAt, DateTime.utc(2030, 6, 6));
    });
  });

  group('QualityMetric', () {
    test('unavailable sets value null and grade unavailable', () {
      const m = QualityMetric.unavailable(
        id: MetricIds.snr,
        label: 'SNR',
        unit: 'dB',
        note: 'Not exposed on iOS',
      );
      expect(m.value, isNull);
      expect(m.grade, QualityGrade.unavailable);
      expect(m.isAvailable, isFalse);
      expect(m.toJson()['note'], 'Not exposed on iOS');
    });

    test('isAvailable true for a real value', () {
      const m = QualityMetric(
        id: MetricIds.latency,
        label: 'Latency',
        value: 12,
        unit: 'ms',
        grade: QualityGrade.excellent,
      );
      expect(m.isAvailable, isTrue);
    });

    test('toJson omits note when null', () {
      const m = QualityMetric(
        id: MetricIds.loss,
        label: 'Loss',
        value: 0,
        unit: '%',
        grade: QualityGrade.excellent,
      );
      expect(m.toJson().containsKey('note'), isFalse);
      expect(m.toJson()['grade'], 'excellent');
    });
  });

  group('QualityResult', () {
    test('metric() returns null for an absent id', () {
      final result = QualityResult(
        source: QualitySource.ownEngine,
        measuredAt: DateTime.utc(2026, 1, 1),
        metrics: const <QualityMetric>[
          QualityMetric(
            id: MetricIds.latency,
            label: 'Latency',
            value: 10,
            unit: 'ms',
            grade: QualityGrade.excellent,
          ),
        ],
      );
      expect(result.metric(MetricIds.download), isNull);
      expect(result.metric(MetricIds.latency), isNotNull);
    });

    test('toJson shape', () {
      final result = QualityResult(
        source: QualitySource.ownEngine,
        measuredAt: DateTime.utc(2026, 1, 1),
        metrics: const <QualityMetric>[
          QualityMetric(
            id: MetricIds.latency,
            label: 'Latency',
            value: 10,
            unit: 'ms',
            grade: QualityGrade.excellent,
          ),
        ],
      );
      final json = result.toJson();
      expect(json['source'], 'ownEngine');
      expect(json['measuredAt'], '2026-01-01T00:00:00.000Z');
      expect((json['metrics'] as List).length, 1);
    });
  });

  group('QualityGradeLabel', () {
    test('labels', () {
      expect(QualityGrade.excellent.label, 'Excellent');
      expect(QualityGrade.good.label, 'Good');
      expect(QualityGrade.fair.label, 'Fair');
      expect(QualityGrade.poor.label, 'Poor');
      expect(QualityGrade.unavailable.label, 'Unavailable');
    });
  });
}
