import 'package:net_quality/net_quality.dart';
import 'package:test/test.dart';

/// A latency connector that always returns the given RTT, or throws when null.
LatencyConnector constConnector(double? rttMs) {
  return (host, port, timeout) async {
    if (rttMs == null) throw Exception('lost');
    return Duration(microseconds: (rttMs * 1000).round());
  };
}

void main() {
  group('OwnEngineQualityClient', () {
    test('composes three probes into six graded metrics', () async {
      final latency = LatencyProbe(
        host: 'h',
        samples: 4,
        connector: constConnector(15), // excellent, jitter 0
      );
      final throughput = ThroughputProbe(
        downloader: (uri, max) async => 50 * 1000 * 1000,
        uploader: (uri, bytes, max) async => bytes,
        timer: _scriptedTimer(const <Duration>[
          Duration(seconds: 4), // 50MB/4s = 100 Mbps download -> excellent
          Duration(seconds: 2), // 10MB/2s = 40 Mbps upload -> excellent
        ]),
        uploadBytes: 10 * 1000 * 1000,
      );
      final responsiveness = ResponsivenessProbe(
        idleSamples: 1,
        loadedSamples: 1,
        latencySampler: () async => const Duration(milliseconds: 30),
        loadGenerator: () async {},
      );

      DateTime clock() => DateTime.utc(2026, 3, 15, 9, 30);
      final client = OwnEngineQualityClient(
        latencyProbe: latency,
        throughputProbe: throughput,
        responsivenessProbe: responsiveness,
        clock: clock,
      );

      expect(client.isAvailable, isTrue);

      final progress = await client.measure().toList();
      // Monotonic non-decreasing, ending at complete = 1.0.
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i].fraction,
            greaterThanOrEqualTo(progress[i - 1].fraction));
      }
      expect(progress.last.phase, QualityPhase.complete);
      expect(progress.last.fraction, 1.0);

      final result = client.lastResult!;
      expect(result.source, QualitySource.ownEngine);
      expect(result.measuredAt, DateTime.utc(2026, 3, 15, 9, 30));

      final ids = result.metrics.map((m) => m.id).toList();
      expect(ids, <String>[
        MetricIds.latency,
        MetricIds.jitter,
        MetricIds.loss,
        MetricIds.download,
        MetricIds.upload,
        MetricIds.responsiveness,
      ]);

      expect(result.metric(MetricIds.latency)!.grade, QualityGrade.excellent);
      expect(result.metric(MetricIds.loss)!.value, 0);
      expect(result.metric(MetricIds.download)!.grade, QualityGrade.excellent);
      expect(result.metric(MetricIds.upload)!.grade, QualityGrade.excellent);
      // 60000 / 30 = 2000 RPM -> excellent.
      expect(result.metric(MetricIds.responsiveness)!.grade,
          QualityGrade.excellent);
    });

    test('all-loss path: latency/jitter unavailable, loss 100% poor', () async {
      final latency = LatencyProbe(
        host: 'h',
        samples: 3,
        connector: constConnector(null), // every sample throws
      );
      final throughput = ThroughputProbe(
        // Single attempt: a zero-byte transfer is now treated as a failure,
        // so download/upload surface as unavailable (not graded 0). This test
        // asserts the latency/loss path, so keep throughput deterministic.
        maxRetries: 0,
        downloader: (uri, max) async => 0,
        uploader: (uri, bytes, max) async => 0,
        timer: _scriptedTimer(const <Duration>[
          Duration(seconds: 1),
          Duration(seconds: 1),
        ]),
      );
      final responsiveness = ResponsivenessProbe(
        idleSamples: 1,
        loadedSamples: 1,
        latencySampler: () async => const Duration(milliseconds: 500),
        loadGenerator: () async {},
      );

      final client = OwnEngineQualityClient(
        latencyProbe: latency,
        throughputProbe: throughput,
        responsivenessProbe: responsiveness,
        clock: () => DateTime.utc(2026, 1, 1),
      );

      await client.measure().drain<void>();
      final result = client.lastResult!;

      final lat = result.metric(MetricIds.latency)!;
      final jit = result.metric(MetricIds.jitter)!;
      final loss = result.metric(MetricIds.loss)!;

      expect(lat.grade, QualityGrade.unavailable);
      expect(lat.value, isNull);
      expect(jit.grade, QualityGrade.unavailable);
      expect(jit.value, isNull);
      expect(loss.value, 100);
      expect(loss.grade, QualityGrade.poor);
    });

    test('a throwing throughput probe yields unavailable metrics', () async {
      final latency = LatencyProbe(
        host: 'h',
        samples: 2,
        connector: constConnector(10),
      );
      final throughput = ThroughputProbe(
        downloader: (uri, max) async => throw Exception('net down'),
        uploader: (uri, bytes, max) async => bytes,
        timer: _throwingTimer(),
      );
      final responsiveness = ResponsivenessProbe(
        idleSamples: 1,
        loadedSamples: 1,
        latencySampler: () async => const Duration(milliseconds: 20),
        loadGenerator: () async {},
      );

      final client = OwnEngineQualityClient(
        latencyProbe: latency,
        throughputProbe: throughput,
        responsivenessProbe: responsiveness,
      );

      await client.measure().drain<void>();
      final result = client.lastResult!;

      expect(result.metric(MetricIds.download)!.grade,
          QualityGrade.unavailable);
      expect(result.metric(MetricIds.upload)!.grade, QualityGrade.unavailable);
      expect(result.metric(MetricIds.download)!.note, 'Measurement failed');
      // Latency still measured fine.
      expect(result.metric(MetricIds.latency)!.grade, QualityGrade.excellent);
    });

    test('zero-byte download reports download UNAVAILABLE, never graded 0',
        () async {
      final latency = LatencyProbe(
        host: 'h',
        samples: 2,
        connector: constConnector(10),
      );
      final throughput = ThroughputProbe(
        maxRetries: 0,
        downloader: (uri, max) async => 0, // hiccuped CDN: 0 bytes, no throw
        uploader: (uri, bytes, max) async => bytes,
        timer: _scriptedTimer(const <Duration>[
          Duration(seconds: 1),
          Duration(seconds: 1),
        ]),
      );
      final responsiveness = ResponsivenessProbe(
        idleSamples: 1,
        loadedSamples: 1,
        latencySampler: () async => const Duration(milliseconds: 20),
        loadGenerator: () async {},
      );

      final client = OwnEngineQualityClient(
        latencyProbe: latency,
        throughputProbe: throughput,
        responsivenessProbe: responsiveness,
      );

      await client.measure().drain<void>();
      final result = client.lastResult!;

      final dl = result.metric(MetricIds.download)!;
      // The bug: this used to be value 0.0 graded poor. Now it must be honest.
      expect(dl.grade, QualityGrade.unavailable);
      expect(dl.value, isNull);
      expect(dl.note, 'Measurement failed');
    });

    test('transient blip then success: download is graded with a real value',
        () async {
      var calls = 0;
      final latency = LatencyProbe(
        host: 'h',
        samples: 2,
        connector: constConnector(10),
      );
      final throughput = ThroughputProbe(
        downloadBytes: 50 * 1000 * 1000,
        uploadBytes: 10 * 1000 * 1000,
        downloader: (uri, max) async {
          calls++;
          if (calls == 1) throw const ThroughputUnmeasurable('transient');
          return 50 * 1000 * 1000;
        },
        uploader: (uri, bytes, max) async => bytes,
        // download: failed attempt (timer still runs the body) then success,
        // then the upload attempt -> three timer calls.
        timer: _scriptedTimer(const <Duration>[
          Duration(seconds: 4), // download attempt 1 (body throws)
          Duration(seconds: 4), // download attempt 2 -> 100 Mbps
          Duration(seconds: 2), // upload -> 40 Mbps
        ]),
      );
      final responsiveness = ResponsivenessProbe(
        idleSamples: 1,
        loadedSamples: 1,
        latencySampler: () async => const Duration(milliseconds: 20),
        loadGenerator: () async {},
      );

      final client = OwnEngineQualityClient(
        latencyProbe: latency,
        throughputProbe: throughput,
        responsivenessProbe: responsiveness,
      );

      await client.measure().drain<void>();
      final result = client.lastResult!;

      expect(calls, 2);
      final dl = result.metric(MetricIds.download)!;
      expect(dl.grade, QualityGrade.excellent);
      expect(dl.value, closeTo(100.0, 0.0001));
    });
  });
}

ElapsedTimer _scriptedTimer(List<Duration> durations) {
  var i = 0;
  return (body) async {
    await body();
    return durations[i++];
  };
}

ElapsedTimer _throwingTimer() {
  return (body) async {
    await body(); // body throws, propagates out of measure()
    return Duration.zero;
  };
}
