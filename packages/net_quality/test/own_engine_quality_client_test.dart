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
        downloadStreamCount: 1,
        downloader: (uri, max) async => 50 * 1000 * 1000,
        uploader: (uri, bytes, max) async => bytes,
        // 50MB/4s = 100 Mbps download -> excellent (single stream window).
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        // 10MB/2s = 40 Mbps upload -> excellent.
        timer: _passthroughTimer(const Duration(seconds: 2)),
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
        downloadStreamCount: 1,
        maxRetries: 0,
        downloader: (uri, max) async => 0,
        uploader: (uri, bytes, max) async => 0,
        windowTimer: _passthroughTimer(const Duration(seconds: 1)),
        timer: _passthroughTimer(const Duration(seconds: 1)),
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
        downloadStreamCount: 1,
        downloader: (uri, max) async => throw Exception('net down'),
        uploader: (uri, bytes, max) async => bytes,
        windowTimer: _passthroughTimer(Duration.zero),
        timer: _passthroughTimer(Duration.zero),
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
        downloadStreamCount: 1,
        maxRetries: 0,
        downloader: (uri, max) async => 0, // hiccuped CDN: 0 bytes, no throw
        uploader: (uri, bytes, max) async => bytes,
        windowTimer: _passthroughTimer(const Duration(seconds: 1)),
        timer: _passthroughTimer(const Duration(seconds: 1)),
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

    test(
        'throughput stage emits smooth, monotonic, multi-step elapsed progress',
        () async {
      // Real wall-clock download + upload windows so the engine's periodic
      // ticker fires several times inside each band, climbing the bar instead
      // of freezing at 0.40 until the stage returns (the 40%-freeze fix).
      final latency = LatencyProbe(
        host: 'h',
        samples: 2,
        connector: constConnector(10),
      );
      final throughput = ThroughputProbe(
        downloadStreamCount: 1,
        downloadBytes: 50 * 1000 * 1000,
        uploadBytes: 10 * 1000 * 1000,
        // Each transfer takes ~450ms of real time; with a ~120ms tick that is
        // several intermediate emits per band. Real Stopwatch timing seams (no
        // passthrough) so the reported rate is computed from the actual window.
        downloader: (uri, max) async {
          await Future<void>.delayed(const Duration(milliseconds: 450));
          return 50 * 1000 * 1000;
        },
        uploader: (uri, bytes, max) async {
          await Future<void>.delayed(const Duration(milliseconds: 450));
          return bytes;
        },
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

      final progress = await client.measure().toList();

      // Monotonic, never decreasing, ends at complete = 1.0.
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i].fraction,
            greaterThanOrEqualTo(progress[i - 1].fraction),
            reason: 'progress must never go backwards');
      }
      expect(progress.last.phase, QualityPhase.complete);
      expect(progress.last.fraction, 1.0);

      // The download band [0.40, 0.70) must produce MULTIPLE intermediate
      // emits between the 0.40 start and the 0.70 band end — i.e. the bar
      // actually climbs through the window, not 0.40 → freeze → 0.70.
      final downloadClimb = progress
          .where((p) =>
              p.phase == QualityPhase.download &&
              p.fraction > 0.40 &&
              p.fraction < 0.70)
          .toList();
      expect(downloadClimb.length, greaterThanOrEqualTo(2),
          reason: 'download stage must climb in multiple steps');

      // The upload band [0.70, 0.90) must likewise produce intermediate emits.
      final uploadClimb = progress
          .where((p) =>
              p.phase == QualityPhase.upload &&
              p.fraction > 0.70 &&
              p.fraction < 0.90)
          .toList();
      expect(uploadClimb.length, greaterThanOrEqualTo(2),
          reason: 'upload stage must climb in multiple steps');

      // No emit ever overshoots its band: nothing exceeds 0.90 until the
      // post-throughput 0.90 pivot, and nothing exceeds 1.0 at all.
      expect(progress.every((p) => p.fraction <= 1.0), isTrue);

      // The measurement still completed correctly under real timing.
      final result = client.lastResult!;
      expect(result.metric(MetricIds.download)!.grade, isNot(QualityGrade.unavailable));
      expect(result.metric(MetricIds.upload)!.grade, isNot(QualityGrade.unavailable));
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
        downloadStreamCount: 1,
        downloadBytes: 50 * 1000 * 1000,
        uploadBytes: 10 * 1000 * 1000,
        downloadEndpoints: <Uri>[
          Uri.parse('https://first.test/down'), // throws (transient)
          Uri.parse('https://second.test/down'), // 50 MB -> 100 Mbps
        ],
        downloader: (uri, max) async {
          calls++;
          if (uri.host == 'first.test') {
            throw const ThroughputUnmeasurable('transient');
          }
          return 50 * 1000 * 1000;
        },
        uploader: (uri, bytes, max) async => bytes,
        // Single shared window for the (retried) download = 4s -> 100 Mbps;
        // upload window = 2s -> 40 Mbps.
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
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

/// A timer that runs the body and reports a fixed duration. Used for both the
/// per-attempt seam and the parallel-download window seam.
ElapsedTimer _passthroughTimer(Duration d) {
  return (body) async {
    await body();
    return d;
  };
}
