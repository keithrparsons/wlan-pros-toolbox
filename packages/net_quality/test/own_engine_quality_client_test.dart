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
        warmUp: Duration.zero,
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

      // Time-weighted bands (sized to real ~10s stage durations): download
      // [0.06, 0.40), upload [0.40, 0.72), responsiveness [0.72, 1.0). The
      // instant metrics only reach ~0.06 — the bar eases up, no leap to 0.40.
      final instantEmits = progress
          .where((p) => p.phase == QualityPhase.latency)
          .toList();
      expect(instantEmits.every((p) => p.fraction <= 0.06), isTrue,
          reason: 'instant metrics must stay in the thin front band, not 0.40');

      // The download band [0.06, 0.40) must produce MULTIPLE intermediate emits
      // between the 0.06 start and the 0.40 band end — i.e. the bar actually
      // climbs through the window, not start → freeze → end.
      final downloadClimb = progress
          .where((p) =>
              p.phase == QualityPhase.download &&
              p.fraction > 0.06 &&
              p.fraction < 0.40)
          .toList();
      expect(downloadClimb.length, greaterThanOrEqualTo(2),
          reason: 'download stage must climb in multiple steps');

      // The upload band [0.40, 0.72) must likewise produce intermediate emits.
      final uploadClimb = progress
          .where((p) =>
              p.phase == QualityPhase.upload &&
              p.fraction > 0.40 &&
              p.fraction < 0.72)
          .toList();
      expect(uploadClimb.length, greaterThanOrEqualTo(2),
          reason: 'upload stage must climb in multiple steps');

      // No emit ever overshoots: nothing exceeds 1.0 at all.
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
        warmUp: Duration.zero,
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

    test('carries the per-provider download diagnostics onto QualityResult',
        () async {
      // Three providers over a 4s window: two fast (30 MB -> 60 Mbps) and one
      // throttled (5 MB -> 10 Mbps). The throttled one is rejected, so the
      // headline (sum-of-survivors) is 120 Mbps and the median-of-survivors is
      // 60 Mbps. All three appear in downloadProviderRates with their flags.
      final latency = LatencyProbe(
        host: 'h',
        samples: 2,
        connector: constConnector(10),
      );
      final throughput = ThroughputProbe(
        downloadStreamCount: 3,
        warmUp: Duration.zero,
        uploadBytes: 10 * 1000 * 1000,
        downloadEndpoints: <Uri>[
          Uri.parse('https://fast1.test/down'),
          Uri.parse('https://fast2.test/down'),
          Uri.parse('https://throttled.test/down'),
        ],
        downloader: (uri, max) async =>
            uri.host == 'throttled.test' ? 5 * 1000 * 1000 : 30 * 1000 * 1000,
        uploader: (uri, bytes, max) async => bytes,
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

      // All three providers carried through, each flagged.
      expect(result.downloadProviderRates, hasLength(3));
      final byHost = <String, ProviderRate>{
        for (final p in result.downloadProviderRates) p.host: p,
      };
      expect(byHost['fast1.test']!.mbps, closeTo(60.0, 0.0001));
      expect(byHost['fast1.test']!.includedInAggregate, isTrue);
      expect(byHost['throttled.test']!.mbps, closeTo(10.0, 0.0001));
      expect(byHost['throttled.test']!.includedInAggregate, isFalse);

      // Both aggregations exposed; headline metric stays sum-of-survivors.
      expect(result.downloadSumOfSurvivors, closeTo(120.0, 0.0001));
      expect(result.downloadMedianOfSurvivors, closeTo(60.0, 0.0001));
      expect(result.metric(MetricIds.download)!.value, closeTo(120.0, 0.0001));
      expect(result.downloadSumOfSurvivors,
          closeTo(result.metric(MetricIds.download)!.value!, 0.0001));
    });

    test('download diagnostics are empty/null when the download stage fails',
        () async {
      final latency = LatencyProbe(
        host: 'h',
        samples: 2,
        connector: constConnector(10),
      );
      final throughput = ThroughputProbe(
        downloadStreamCount: 1,
        maxRetries: 0,
        throughputRetries: 0,
        downloadEndpoints: <Uri>[Uri.parse('https://only.test/down')],
        downloader: (uri, max) async =>
            throw const ThroughputUnmeasurable('down'),
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
      expect(result.downloadProviderRates, isEmpty);
      expect(result.downloadSumOfSurvivors, isNull);
      expect(result.downloadMedianOfSurvivors, isNull);
    });
  });

  group('OwnEngineQualityClient.runResilientRpmLoad (RPM load resilience)', () {
    test('falls back past a flaky first endpoint (Cloudflare) so RPM still runs',
        () async {
      // The download POOL's first provider (Cloudflare) flakes, but the RPM
      // single-flow load must NOT fail — it walks to the next provider.
      final hit = <String>[];
      final probe = ThroughputProbe(
        downloadEndpoints: <Uri>[
          Uri.parse('https://speed.cloudflare.com/__down?bytes=1'), // flaky
          Uri.parse('https://proof.ovh.net/files/1Gb.dat'), // healthy
          Uri.parse('https://cachefly.cachefly.net/100mb.test'),
        ],
        downloader: (uri, max) async {
          hit.add(uri.host);
          if (uri.host == 'speed.cloudflare.com') {
            throw const ThroughputUnmeasurable('cloudflare flaked');
          }
          return 50 * 1000 * 1000;
        },
      );

      // Completes without throwing (RPM would have gone Unavailable otherwise).
      await OwnEngineQualityClient.runResilientRpmLoad(probe);

      // Tried Cloudflare first, then stopped at the first healthy provider —
      // it stays SINGLE-FLOW (did not fan out to the whole pool).
      expect(hit, <String>['speed.cloudflare.com', 'proof.ovh.net']);
    });

    test('healthy first endpoint is used alone (single-flow, no fan-out)',
        () async {
      final hit = <String>[];
      final probe = ThroughputProbe(
        downloadEndpoints: <Uri>[
          Uri.parse('https://a.test/down'),
          Uri.parse('https://b.test/down'),
        ],
        downloader: (uri, max) async {
          hit.add(uri.host);
          return 50 * 1000 * 1000;
        },
      );
      await OwnEngineQualityClient.runResilientRpmLoad(probe);
      expect(hit, <String>['a.test']); // only the first, single flow
    });

    test('throws only when EVERY provider fails (honest, never a fake value)',
        () async {
      final probe = ThroughputProbe(
        downloadEndpoints: <Uri>[
          Uri.parse('https://a.test/down'),
          Uri.parse('https://b.test/down'),
        ],
        downloader: (uri, max) async =>
            throw const ThroughputUnmeasurable('all down'),
      );
      await expectLater(
        OwnEngineQualityClient.runResilientRpmLoad(probe),
        throwsA(isA<ThroughputUnmeasurable>()),
      );
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
