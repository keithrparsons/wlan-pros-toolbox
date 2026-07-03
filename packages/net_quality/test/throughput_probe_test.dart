import 'dart:async';
import 'dart:io';

import 'package:net_quality/net_quality.dart';
import 'package:test/test.dart';

void main() {
  _registerRealTransportRegressionTests();

  group('ThroughputProbe.mbpsFor', () {
    test('25 MB over 2.0s is 100.0 Mbps', () {
      final mbps = ThroughputProbe.mbpsFor(
        25 * 1000 * 1000,
        const Duration(seconds: 2),
      );
      expect(mbps, closeTo(100.0, 0.0001));
    });

    test('divide-by-zero guard returns 0.0', () {
      expect(ThroughputProbe.mbpsFor(1000000, Duration.zero), 0.0);
    });

    test('zero bytes returns 0.0', () {
      expect(ThroughputProbe.mbpsFor(0, const Duration(seconds: 5)), 0.0);
    });
  });

  group('ThroughputProbe defaults', () {
    test('ships a DIVERSE multi-provider pool (not all one provider)', () {
      final probe = ThroughputProbe();
      expect(probe.downloadEndpoints.length, greaterThanOrEqualTo(5));
      final hosts = probe.downloadEndpoints.map((u) => u.host).toSet();
      // Several independent providers/networks — the whole point of the rework.
      expect(hosts.length, greaterThanOrEqualTo(5));
      expect(probe.downloadEndpoints.first.host, 'speed.cloudflare.com');
      // No single provider dominates the first (concurrent) slots: the first
      // downloadStreamCount endpoints are all distinct hosts.
      final firstN = probe.downloadEndpoints
          .take(probe.downloadStreamCount)
          .map((u) => u.host)
          .toList();
      expect(firstN.toSet().length, firstN.length,
          reason: 'each concurrent stream must start on a distinct provider');
    });

    test('download stream count defaults to 5 and is configurable', () {
      expect(ThroughputProbe().downloadStreamCount, 5);
      expect(ThroughputProbe(downloadStreamCount: 3).downloadStreamCount, 3);
      expect(ThroughputProbe(downloadStreamCount: 1).downloadStreamCount, 1);
    });

    test('window is ~15s, warm-up ~3s, and both are configurable', () {
      expect(ThroughputProbe().maxDuration, const Duration(seconds: 15));
      expect(ThroughputProbe().warmUp, const Duration(seconds: 3));
      expect(
        ThroughputProbe(
          maxDuration: const Duration(seconds: 20),
          warmUp: const Duration(seconds: 5),
        ).maxDuration,
        const Duration(seconds: 20),
      );
    });

    test('outlier + aggregation defaults', () {
      expect(ThroughputProbe().outlierRejectionFraction, 0.5);
      expect(kDefaultOutlierRejectionFraction, 0.5);
      expect(ThroughputProbe().downloadAggregation,
          DownloadAggregation.sumOfSurvivors);
    });

    test('downloadEndpoint getter exposes the first endpoint (load gen seam)',
        () {
      final probe = ThroughputProbe();
      expect(probe.downloadEndpoint, probe.downloadEndpoints.first);
      expect(probe.uploadEndpoint, probe.uploadEndpoints.first);
    });
  });

  group('ThroughputProbe.aggregateDownloadRates — outlier rejection (pure)', () {
    List<ProviderRate> rates(Map<String, double> m) => <ProviderRate>[
          for (final e in m.entries)
            ProviderRate(host: e.key, mbps: e.value, includedInAggregate: true),
        ];

    test('all providers cluster -> all kept, summed', () {
      final r = ThroughputProbe.aggregateDownloadRates(
        rates(<String, double>{'a': 100, 'b': 110, 'c': 95}),
      );
      expect(r.providers.every((p) => p.includedInAggregate), isTrue);
      expect(r.mbps, closeTo(305.0, 0.0001)); // sum of survivors (default)
    });

    test('one throttled provider (< 50% of median) is DROPPED', () {
      // median of [100,110,20] = 100; threshold = 50; 20 < 50 -> dropped.
      final r = ThroughputProbe.aggregateDownloadRates(
        rates(<String, double>{'fast1': 100, 'fast2': 110, 'throttled': 20}),
      );
      final dropped =
          r.providers.where((p) => !p.includedInAggregate).map((p) => p.host);
      expect(dropped, <String>['throttled']);
      // Only the survivors are summed; the throttled server can't drag it down.
      expect(r.mbps, closeTo(210.0, 0.0001));
    });

    test('median-of-survivors aggregation mode', () {
      final r = ThroughputProbe.aggregateDownloadRates(
        rates(<String, double>{'fast1': 100, 'fast2': 110, 'throttled': 20}),
        mode: DownloadAggregation.medianOfSurvivors,
      );
      // Survivors [100,110] -> median 105.
      expect(r.mbps, closeTo(105.0, 0.0001));
    });

    test('never wipes out the pack: the max always survives', () {
      // Even a wildly spread set keeps at least the top provider.
      final r = ThroughputProbe.aggregateDownloadRates(
        rates(<String, double>{'a': 5, 'b': 6, 'c': 500}),
      );
      expect(r.providers.where((p) => p.includedInAggregate), isNotEmpty);
      expect(r.mbps, greaterThan(0.0));
    });

    test('empty input -> 0 with no providers (caller treats as unmeasurable)',
        () {
      final r = ThroughputProbe.aggregateDownloadRates(<ProviderRate>[]);
      expect(r.mbps, 0.0);
      expect(r.providers, isEmpty);
    });

    test('threshold is tunable via rejectionFraction', () {
      // With a 0.9 fraction, even a mild laggard (70 vs median 100) is dropped.
      final r = ThroughputProbe.aggregateDownloadRates(
        rates(<String, double>{'a': 100, 'b': 100, 'c': 70}),
        rejectionFraction: 0.9,
      );
      final dropped =
          r.providers.where((p) => !p.includedInAggregate).map((p) => p.host);
      expect(dropped, <String>['c']);
    });
  });

  group('ThroughputProbe.measure — parallel download aggregation', () {
    test('two streams of known byte counts SUM (not average) over the window',
        () async {
      // Each stream returns 30 MB. Steady window is 4s (warm-up 0 in the test).
      // Aggregate must be the SUM: (30+30) MB * 8 / 4s / 1e6 = 120 Mbps. The
      // AVERAGE of the two per-stream rates (each 60 Mbps) would be 60 — NOT it.
      const perStream = 30 * 1000 * 1000;
      final probe = ThroughputProbe(
        downloadStreamCount: 2,
        warmUp: Duration.zero,
        downloader: (uri, max) async => perStream,
        uploader: (uri, bytes, max) async => bytes,
        uploadBytes: 10 * 1000 * 1000,
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      final s = await probe.measure();

      expect(s.downloadStreams, 2);
      expect(s.downloadBytes, 2 * perStream); // summed steady bytes
      expect(s.downloadMbps, closeTo(120.0, 0.0001)); // the SUM
      const perStreamRate = 60.0;
      expect(s.downloadMbps, isNot(closeTo(perStreamRate, 0.5)));
      expect(s.providerRates, hasLength(2));
      expect(s.providerRates.every((p) => p.includedInAggregate), isTrue);
      // 10 MB * 8 / 2s / 1e6 = 40 Mbps upload.
      expect(s.uploadMbps, closeTo(40.0, 0.0001));
    });

    test('single-stream config reports just that one stream', () async {
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        warmUp: Duration.zero,
        downloader: (uri, max) async => 50 * 1000 * 1000,
        uploader: (uri, bytes, max) async => bytes,
        uploadBytes: 10 * 1000 * 1000,
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      final s = await probe.measure();
      expect(s.downloadStreams, 1);
      expect(s.downloadBytes, 50 * 1000 * 1000);
      // 50 MB * 8 / 4s / 1e6 = 100 Mbps.
      expect(s.downloadMbps, closeTo(100.0, 0.0001));
      expect(s.uploadMbps, closeTo(40.0, 0.0001));
    });

    test('a throttled provider is dropped from the reported aggregate',
        () async {
      // Three distinct providers. Two deliver 30 MB (60 Mbps over 4s); one is
      // throttled to 5 MB (10 Mbps). Median = 60, threshold = 30, so the 10 Mbps
      // outlier is EXCLUDED and can't drag the number down.
      final probe = ThroughputProbe(
        downloadStreamCount: 3,
        warmUp: Duration.zero,
        downloadEndpoints: <Uri>[
          Uri.parse('https://fast1.test/down'),
          Uri.parse('https://fast2.test/down'),
          Uri.parse('https://throttled.test/down'),
        ],
        downloader: (uri, max) async =>
            uri.host == 'throttled.test' ? 5 * 1000 * 1000 : 30 * 1000 * 1000,
        uploader: (uri, bytes, max) async => bytes,
        uploadBytes: 10 * 1000 * 1000,
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      final s = await probe.measure();
      // All three delivered bytes (real connections)...
      expect(s.downloadStreams, 3);
      // ...but only the two fast survivors are summed: 60 + 60 = 120 Mbps.
      expect(s.downloadMbps, closeTo(120.0, 0.0001));
      expect(s.downloadBytes, 2 * 30 * 1000 * 1000);
      // Diagnostics expose exactly which provider was dropped.
      final dropped = s.droppedProviders.map((p) => p.host);
      expect(dropped, <String>['throttled.test']);
    });

    test('providers that all cluster are ALL kept', () async {
      final bytesByHost = <String, int>{
        'a.test': 30 * 1000 * 1000, // 60 Mbps
        'b.test': 28 * 1000 * 1000, // 56 Mbps
        'c.test': 31 * 1000 * 1000, // 62 Mbps
      };
      final probe = ThroughputProbe(
        downloadStreamCount: 3,
        warmUp: Duration.zero,
        downloadEndpoints: <Uri>[
          Uri.parse('https://a.test/down'),
          Uri.parse('https://b.test/down'),
          Uri.parse('https://c.test/down'),
        ],
        downloader: (uri, max) async => bytesByHost[uri.host]!,
        uploader: (uri, bytes, max) async => bytes,
        uploadBytes: 10 * 1000 * 1000,
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      final s = await probe.measure();
      expect(s.droppedProviders, isEmpty);
      expect(s.providerRates.every((p) => p.includedInAggregate), isTrue);
      // 60 + 56 + 62 = 178 Mbps.
      expect(s.downloadMbps, closeTo(178.0, 0.0001));
    });

    test('median-of-survivors aggregation switch changes the reported number',
        () async {
      final probe = ThroughputProbe(
        downloadStreamCount: 3,
        warmUp: Duration.zero,
        downloadAggregation: DownloadAggregation.medianOfSurvivors,
        downloadEndpoints: <Uri>[
          Uri.parse('https://fast1.test/down'),
          Uri.parse('https://fast2.test/down'),
          Uri.parse('https://throttled.test/down'),
        ],
        downloader: (uri, max) async =>
            uri.host == 'throttled.test' ? 5 * 1000 * 1000 : 30 * 1000 * 1000,
        uploader: (uri, bytes, max) async => bytes,
        uploadBytes: 10 * 1000 * 1000,
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      final s = await probe.measure();
      expect(s.aggregation, DownloadAggregation.medianOfSurvivors);
      // Survivors 60 & 60 -> median 60 (not the sum, 120).
      expect(s.downloadMbps, closeTo(60.0, 0.0001));
    });

    test('one stream fails -> falls back to next endpoint; survivors aggregate',
        () async {
      final probe = ThroughputProbe(
        downloadStreamCount: 2,
        warmUp: Duration.zero,
        downloadEndpoints: <Uri>[
          Uri.parse('https://primary.test/down'), // fails
          Uri.parse('https://second.test/down'), // ok
          Uri.parse('https://third.test/down'), // ok (stream 0 fallback)
        ],
        downloader: (uri, max) async {
          if (uri.host == 'primary.test') {
            throw const ThroughputUnmeasurable('primary 503');
          }
          return 20 * 1000 * 1000;
        },
        uploader: (uri, bytes, max) async => bytes,
        uploadBytes: 10 * 1000 * 1000,
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      final s = await probe.measure();
      expect(s.downloadStreams, 2);
      expect(s.downloadBytes, 2 * 20 * 1000 * 1000);
      // (20+20) MB * 8 / 4s / 1e6 = 80 Mbps.
      expect(s.downloadMbps, closeTo(80.0, 0.0001));
    });

    test('one stream fully fails -> aggregate from the one survivor, never 0',
        () async {
      var calls = 0;
      final probe = ThroughputProbe(
        downloadStreamCount: 2,
        warmUp: Duration.zero,
        maxRetries: 0,
        downloadEndpoints: <Uri>[
          Uri.parse('https://good.test/down'),
          Uri.parse('https://bad.test/down'),
        ],
        downloader: (uri, max) async {
          calls++;
          if (uri.host == 'bad.test') {
            throw const ThroughputUnmeasurable('bad endpoint');
          }
          return 25 * 1000 * 1000;
        },
        uploader: (uri, bytes, max) async => bytes,
        uploadBytes: 10 * 1000 * 1000,
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      final s = await probe.measure();
      expect(s.downloadStreams, 1);
      expect(s.downloadBytes, 25 * 1000 * 1000);
      // 25 MB * 8 / 4s / 1e6 = 50 Mbps — honest, not 0.
      expect(s.downloadMbps, closeTo(50.0, 0.0001));
      expect(s.downloadMbps, greaterThan(0.0));
      expect(calls, 2);
    });

    test('ALL endpoints/streams fail -> ThroughputUnmeasurable, never 0',
        () async {
      final probe = ThroughputProbe(
        downloadStreamCount: 2,
        downloadEndpoints: <Uri>[
          Uri.parse('https://a.test/down'),
          Uri.parse('https://b.test/down'),
          Uri.parse('https://c.test/down'),
        ],
        downloader: (uri, max) async =>
            throw const ThroughputUnmeasurable('all down'),
        uploader: (uri, bytes, max) async => bytes,
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      await expectLater(
        probe.measure(),
        throwsA(isA<ThroughputUnmeasurable>()),
      );
    });

    test('zero-byte (floored) responses on every endpoint -> Unmeasurable',
        () async {
      final probe = ThroughputProbe(
        downloadStreamCount: 2,
        downloadEndpoints: <Uri>[
          Uri.parse('https://a.test/down'),
          Uri.parse('https://b.test/down'),
        ],
        downloader: (uri, max) async => 0, // empty/hiccuped everywhere
        uploader: (uri, bytes, max) async => bytes,
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      await expectLater(
        probe.measure(),
        throwsA(isA<ThroughputUnmeasurable>()),
      );
    });
  });

  group('ThroughputProbe.measure — warm-up (steady-state) discard', () {
    test('rate is computed over window MINUS warm-up (ramp discarded)',
        () async {
      // The injected downloader returns the steady-state bytes for the window.
      // With a 15s window and 3s warm-up, the steady window is 12s, so 120 MB
      // of steady bytes => 120 MB * 8 / 12s / 1e6 = 80 Mbps (NOT /15s = 64).
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        maxDuration: const Duration(seconds: 15),
        warmUp: const Duration(seconds: 3),
        downloader: (uri, max) async => 120 * 1000 * 1000,
        uploader: (uri, bytes, max) async => bytes,
        uploadBytes: 10 * 1000 * 1000,
        windowTimer: _passthroughTimer(const Duration(seconds: 15)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      final s = await probe.measure();
      expect(s.elapsedDownload, const Duration(seconds: 12));
      expect(s.downloadMbps, closeTo(80.0, 0.0001));
    });

    test('warm-up >= window is guarded: whole window measured, never negative',
        () async {
      // A short window (2s) with a longer warm-up (3s): the guard measures the
      // whole window rather than dividing by a negative steady elapsed.
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        maxDuration: const Duration(seconds: 2),
        warmUp: const Duration(seconds: 3),
        downloader: (uri, max) async => 25 * 1000 * 1000,
        uploader: (uri, bytes, max) async => bytes,
        uploadBytes: 10 * 1000 * 1000,
        windowTimer: _passthroughTimer(const Duration(seconds: 2)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      final s = await probe.measure();
      expect(s.elapsedDownload, const Duration(seconds: 2));
      // 25 MB * 8 / 2s / 1e6 = 100 Mbps.
      expect(s.downloadMbps, closeTo(100.0, 0.0001));
    });
  });

  group('ThroughputProbe.measure — whole-window retry (stall, then success)',
      () {
    test(
        'download window stalls on every endpoint the first time, then the '
        'retry re-opens a fresh window and measures a real rate (not 0)',
        () async {
      var pass = 0;
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        warmUp: Duration.zero,
        maxRetries: 0, // no inner endpoint fallback, so the WHOLE window fails
        throughputRetries: 1, // one outer retry of the window
        downloadEndpoints: <Uri>[Uri.parse('https://only.test/down')],
        downloader: (uri, max) async {
          pass++;
          if (pass == 1) {
            throw const ThroughputUnmeasurable('transient stall');
          }
          return 50 * 1000 * 1000;
        },
        uploader: (uri, bytes, max) async => bytes,
        uploadBytes: 10 * 1000 * 1000,
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      final s = await probe.measure();
      expect(pass, 2);
      // 50 MB * 8 / 4s / 1e6 = 100 Mbps — a real measurement, not "Not measured".
      expect(s.downloadMbps, closeTo(100.0, 0.0001));
      expect(s.downloadBytes, 50 * 1000 * 1000);
    });

    test('healthy run does NOT retry — the retry budget is paid only on a stall',
        () async {
      var calls = 0;
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        throughputRetries: 1,
        downloadEndpoints: <Uri>[Uri.parse('https://only.test/down')],
        downloader: (uri, max) async {
          calls++;
          return 50 * 1000 * 1000;
        },
        uploader: (uri, bytes, max) async => bytes,
        uploadBytes: 10 * 1000 * 1000,
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      await probe.measure();
      expect(calls, 1);
    });

    test('still unmeasurable after the retry → ThroughputUnmeasurable, never 0',
        () async {
      var calls = 0;
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        maxRetries: 0,
        throughputRetries: 1,
        downloadEndpoints: <Uri>[Uri.parse('https://only.test/down')],
        downloader: (uri, max) async {
          calls++;
          throw const ThroughputUnmeasurable('still stalled');
        },
        uploader: (uri, bytes, max) async => bytes,
        windowTimer: _passthroughTimer(const Duration(seconds: 1)),
        timer: _passthroughTimer(const Duration(seconds: 1)),
      );
      await expectLater(
        probe.measure(),
        throwsA(isA<ThroughputUnmeasurable>()),
      );
      expect(calls, 2);
    });

    test(
        'the retry NEVER unbounds the run: a persistently-stalled window plus '
        'one retry still aborts within ~2x the hard deadline, never hangs',
        () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((socket) {/* accept, send nothing */});
      addTearDown(() async => server.close());

      const maxDuration = Duration(seconds: 2);
      const upperBound = Duration(seconds: 22);
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        maxRetries: 0,
        throughputRetries: 1,
        maxDuration: maxDuration,
        downloadEndpoints: <Uri>[
          Uri.parse('http://127.0.0.1:${server.port}/down'),
        ],
      );
      final sw = Stopwatch()..start();
      await expectLater(
        probe.measure(),
        throwsA(isA<ThroughputUnmeasurable>()),
      );
      sw.stop();
      expect(sw.elapsed, lessThan(upperBound),
          reason: 'retry must stay bounded, never hang');
    });

    test('throughputRetries: 0 disables the retry (one window, then give up)',
        () async {
      var calls = 0;
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        maxRetries: 0,
        throughputRetries: 0,
        downloadEndpoints: <Uri>[Uri.parse('https://only.test/down')],
        downloader: (uri, max) async {
          calls++;
          throw const ThroughputUnmeasurable('stalled');
        },
        uploader: (uri, bytes, max) async => bytes,
        windowTimer: _passthroughTimer(const Duration(seconds: 1)),
        timer: _passthroughTimer(const Duration(seconds: 1)),
      );
      await expectLater(
        probe.measure(),
        throwsA(isA<ThroughputUnmeasurable>()),
      );
      expect(calls, 1);
    });
  });

  group('ThroughputProbe.measure — upload fallback (single stream)', () {
    test('upload tries the next endpoint on failure', () async {
      var calls = 0;
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        uploadBytes: 10 * 1000 * 1000,
        uploadEndpoints: <Uri>[
          Uri.parse('https://up-primary.test/up'),
          Uri.parse('https://up-backup.test/up'),
        ],
        downloader: (uri, max) async => 50 * 1000 * 1000,
        uploader: (uri, bytes, max) async {
          calls++;
          if (uri.host == 'up-primary.test') {
            throw const ThroughputUnmeasurable('upload 502');
          }
          return bytes;
        },
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      final s = await probe.measure();
      expect(calls, 2); // primary failed, backup succeeded
      expect(s.uploadBytes, 10 * 1000 * 1000);
      expect(s.uploadMbps, closeTo(40.0, 0.0001));
    });

    test('zero-byte upload is treated as a failure, not 0 Mbps', () async {
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        maxRetries: 0,
        downloader: (uri, max) async => 50 * 1000 * 1000,
        uploader: (uri, bytes, max) async => 0, // rejected/empty
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        timer: _passthroughTimer(const Duration(seconds: 1)),
      );
      await expectLater(
        probe.measure(),
        throwsA(isA<ThroughputUnmeasurable>()),
      );
    });
  });

  group('ThroughputProbe — self-hosted Rung-2 fallback (degrades gracefully)',
      () {
    test('feature flag defaults OFF (the fallback ships dormant)', () {
      expect(ThroughputProbe().selfHostedFallbackEnabled, isFalse);
    });

    test('base URL is the single named WLAN Pros endpoint constant', () {
      expect(kSpeedTestFallbackBaseUrl, 'https://speedtest.wlanpros.com');
      expect(speedTestFallbackDownloadEndpoint().host, 'speedtest.wlanpros.com');
      expect(speedTestFallbackDownloadEndpoint().path, '/downloading');
      expect(speedTestFallbackUploadEndpoint().path, '/upload');
    });

    test(
        'flag OFF: liveness probe is NEVER consulted and Cloudflare stays '
        'primary (no extra traffic to our box)', () async {
      var livenessCalls = 0;
      final hitHosts = <String>{};
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        livenessProbe: (uri, timeout) async {
          livenessCalls++;
          return true;
        },
        downloader: (uri, max) async {
          hitHosts.add(uri.host);
          return 50 * 1000 * 1000;
        },
        uploader: (uri, bytes, max) async {
          hitHosts.add(uri.host);
          return bytes;
        },
        uploadBytes: 10 * 1000 * 1000,
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      await probe.measure();
      expect(livenessCalls, 0, reason: 'no probe when the flag is off');
      expect(hitHosts, contains('speed.cloudflare.com'));
      expect(hitHosts, isNot(contains('speedtest.wlanpros.com')),
          reason: 'our box must never be hit while the flag is off');
    });

    test(
        'flag ON but endpoint NOT live (probe false, the state today): falls '
        'straight through to the shipped chains, never hits our box, still '
        'measures a real rate from Cloudflare', () async {
      final hitHosts = <String>{};
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        warmUp: Duration.zero,
        selfHostedFallbackEnabled: true,
        livenessProbe: (uri, timeout) async => false,
        downloader: (uri, max) async {
          hitHosts.add(uri.host);
          return 50 * 1000 * 1000; // Cloudflare answers normally.
        },
        uploader: (uri, bytes, max) async {
          hitHosts.add(uri.host);
          return bytes;
        },
        uploadBytes: 10 * 1000 * 1000,
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      final s = await probe.measure();
      expect(s.downloadMbps, closeTo(100.0, 0.0001));
      expect(hitHosts, contains('speed.cloudflare.com'));
      expect(hitHosts, isNot(contains('speedtest.wlanpros.com')),
          reason: 'a not-live Rung 2 must never be appended to the chain');
    });

    test(
        'flag ON, endpoint NOT live, AND Cloudflare/CDN all fail: honest '
        'ThroughputUnmeasurable (the existing online-could-not-measure terminal '
        'state), never a fake 0, never our box', () async {
      final hitHosts = <String>{};
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        maxRetries: 2,
        throughputRetries: 0,
        selfHostedFallbackEnabled: true,
        livenessProbe: (uri, timeout) async => false,
        downloader: (uri, max) async {
          hitHosts.add(uri.host);
          throw const ThroughputUnmeasurable('all public CDNs down');
        },
        uploader: (uri, bytes, max) async => bytes,
        windowTimer: _passthroughTimer(const Duration(seconds: 1)),
        timer: _passthroughTimer(const Duration(seconds: 1)),
      );
      await expectLater(
        probe.measure(),
        throwsA(isA<ThroughputUnmeasurable>()),
      );
      expect(hitHosts, isNot(contains('speedtest.wlanpros.com')),
          reason: 'not-live Rung 2 must not be tried even when Rung 1 fails');
    });

    test(
        'a liveness probe that THROWS is treated as not-live (defensive): the '
        'run still completes on the shipped chains, never hangs or hard-fails',
        () async {
      final hitHosts = <String>{};
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        warmUp: Duration.zero,
        selfHostedFallbackEnabled: true,
        livenessProbe: (uri, timeout) async =>
            throw StateError('probe blew up'),
        downloader: (uri, max) async {
          hitHosts.add(uri.host);
          return 50 * 1000 * 1000;
        },
        uploader: (uri, bytes, max) async => bytes,
        uploadBytes: 10 * 1000 * 1000,
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      final s = await probe.measure();
      expect(s.downloadMbps, closeTo(100.0, 0.0001));
      expect(hitHosts, isNot(contains('speedtest.wlanpros.com')));
    });

    test(
        'flag ON and endpoint LIVE (the go-live state): Rung 2 is APPENDED as '
        'the LAST fallback (Cloudflare still primary, our box used only after '
        'the public CDNs fail)', () async {
      var livenessCalls = 0;
      final attemptedHosts = <String>[];
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        warmUp: Duration.zero,
        maxRetries: 9,
        throughputRetries: 0,
        selfHostedFallbackEnabled: true,
        livenessProbe: (uri, timeout) async {
          livenessCalls++;
          expect(uri.toString(), kSpeedTestFallbackBaseUrl);
          return true; // box answers 200
        },
        downloader: (uri, max) async {
          attemptedHosts.add(uri.host);
          if (uri.host == 'speedtest.wlanpros.com') {
            expect(uri.queryParameters.containsKey('r'), isTrue);
            return 40 * 1000 * 1000;
          }
          throw const ThroughputUnmeasurable('public CDN down');
        },
        uploader: (uri, bytes, max) async => bytes,
        uploadBytes: 10 * 1000 * 1000,
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      final s = await probe.measure();
      expect(livenessCalls, 1);
      expect(attemptedHosts.first, 'speed.cloudflare.com');
      expect(attemptedHosts.last, 'speedtest.wlanpros.com');
      // 40 MB * 8 / 4s / 1e6 = 80 Mbps, measured via the live fallback.
      expect(s.downloadMbps, closeTo(80.0, 0.0001));
    });
  });

  group('ThroughputProbe — Rung-2 fallback client header (X-Toolbox-Client)',
      () {
    test('the shared token + header name are the agreed constants', () {
      expect(kSpeedTestFallbackClientHeader, 'X-Toolbox-Client');
      expect(
        kSpeedTestFallbackClientToken,
        'a3a1b5c6faa2711e9f3cd90bf6dca0c89040d1404bd02591',
      );
    });

    test('the host gate admits ONLY the fallback host, not the CDNs', () {
      expect(
        ThroughputProbe.isFallbackRequest(speedTestFallbackDownloadEndpoint()),
        isTrue,
      );
      expect(
        ThroughputProbe.isFallbackRequest(speedTestFallbackUploadEndpoint()),
        isTrue,
      );
      expect(
        ThroughputProbe.isFallbackRequest(
          Uri.parse('$kSpeedTestFallbackBaseUrl/downloading?r=42'),
        ),
        isTrue,
      );
      expect(
        ThroughputProbe.isFallbackRequest(
          Uri.parse('https://speed.cloudflare.com/__down?bytes=100'),
        ),
        isFalse,
      );
      expect(
        ThroughputProbe.isFallbackRequest(
          Uri.parse('https://speed.cloudflare.com/__up'),
        ),
        isFalse,
      );
      expect(
        ThroughputProbe.isFallbackRequest(
          Uri.parse('https://proof.ovh.net/files/100Mb.dat'),
        ),
        isFalse,
      );
    });

    test(
        'real download to the FALLBACK host puts X-Toolbox-Client on the wire '
        '(end to end, via the real default transport)', () async {
      final headers = await _captureRequestHeaders(
        requestUri: speedTestFallbackDownloadEndpoint(),
        isUpload: false,
      );
      expect(
        headers['x-toolbox-client'],
        'a3a1b5c6faa2711e9f3cd90bf6dca0c89040d1404bd02591',
        reason: 'fallback download must carry the shared client header',
      );
    });

    test(
        'real upload to the FALLBACK host puts X-Toolbox-Client on the wire '
        '(end to end, via the real default transport)', () async {
      final headers = await _captureRequestHeaders(
        requestUri: speedTestFallbackUploadEndpoint(),
        isUpload: true,
      );
      expect(
        headers['x-toolbox-client'],
        'a3a1b5c6faa2711e9f3cd90bf6dca0c89040d1404bd02591',
        reason: 'fallback upload must carry the shared client header',
      );
    });

    test(
        'real download to a NON-fallback (CDN) host does NOT leak the header',
        () async {
      final headers = await _captureRequestHeaders(
        requestUri: Uri.parse('https://speed.cloudflare.com/__down?bytes=1'),
        isUpload: false,
      );
      expect(
        headers.containsKey('x-toolbox-client'),
        isFalse,
        reason: 'the client token must never reach the public CDNs',
      );
    });

    test('real upload to a NON-fallback (CDN) host does NOT leak the header',
        () async {
      final headers = await _captureRequestHeaders(
        requestUri: Uri.parse('https://speed.cloudflare.com/__up'),
        isUpload: true,
      );
      expect(
        headers.containsKey('x-toolbox-client'),
        isFalse,
        reason: 'the client token must never reach the public CDNs',
      );
    });

    test(
        'native (non-web) still applies the header: the web guard does not '
        'suppress it on the VM', () {
      expect(
        identical(0, 0.0),
        isFalse,
        reason: 'on the native VM the web guard must be inert, so the '
            'fallback client header is still applied',
      );
    });
  });

  group('ThroughputProbe.measure — honesty (preserved from prior fix)', () {
    test('zero-byte download is treated as a failure, not 0 Mbps', () async {
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        maxRetries: 0,
        downloader: (uri, max) async => 0, // empty/hiccuped response
        uploader: (uri, bytes, max) async => bytes,
        windowTimer: _passthroughTimer(const Duration(seconds: 1)),
        timer: _passthroughTimer(const Duration(seconds: 1)),
      );
      await expectLater(
          probe.measure(), throwsA(isA<ThroughputUnmeasurable>()));
    });

    test('non-2xx-style failure (thrown by seam) is not 0 Mbps', () async {
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        maxRetries: 0,
        downloader: (uri, max) async =>
            throw const ThroughputUnmeasurable('download HTTP 429'),
        uploader: (uri, bytes, max) async => bytes,
        windowTimer: _passthroughTimer(const Duration(seconds: 1)),
        timer: _passthroughTimer(const Duration(seconds: 1)),
      );
      await expectLater(
          probe.measure(), throwsA(isA<ThroughputUnmeasurable>()));
    });

    test('retry-then-success: first endpoint fails, fallback yields real Mbps',
        () async {
      var calls = 0;
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        warmUp: Duration.zero,
        uploadBytes: 10 * 1000 * 1000,
        downloadEndpoints: <Uri>[
          Uri.parse('https://first.test/down'),
          Uri.parse('https://second.test/down'),
        ],
        downloader: (uri, max) async {
          calls++;
          if (uri.host == 'first.test') {
            throw const ThroughputUnmeasurable('transient 503');
          }
          return 50 * 1000 * 1000;
        },
        uploader: (uri, bytes, max) async => bytes,
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      final s = await probe.measure();
      expect(calls, 2); // failed once, then succeeded on fallback
      // 50 MB * 8 / 4s / 1e6 = 100 Mbps -> a real measurement, not 0.
      expect(s.downloadMbps, closeTo(100.0, 0.0001));
      expect(s.downloadBytes, 50 * 1000 * 1000);
    });

    test('all attempts fail: throws after exhausting fallbacks', () async {
      var calls = 0;
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        maxRetries: 2,
        throughputRetries: 0,
        downloadEndpoints: <Uri>[
          Uri.parse('https://a.test/down'),
          Uri.parse('https://b.test/down'),
          Uri.parse('https://c.test/down'),
        ],
        downloader: (uri, max) async {
          calls++;
          throw const ThroughputUnmeasurable('rate limited');
        },
        uploader: (uri, bytes, max) async => bytes,
        windowTimer: _passthroughTimer(const Duration(seconds: 1)),
        timer: _passthroughTimer(const Duration(seconds: 1)),
      );
      await expectLater(
          probe.measure(), throwsA(isA<ThroughputUnmeasurable>()));
      expect(calls, 3);
    });

    test('zero-byte response is retried/fallen-back before giving up',
        () async {
      var calls = 0;
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        maxRetries: 2,
        throughputRetries: 0,
        downloadEndpoints: <Uri>[
          Uri.parse('https://a.test/down'),
          Uri.parse('https://b.test/down'),
          Uri.parse('https://c.test/down'),
        ],
        downloader: (uri, max) async {
          calls++;
          return 0; // every endpoint empty
        },
        uploader: (uri, bytes, max) async => bytes,
        windowTimer: _passthroughTimer(const Duration(seconds: 1)),
        timer: _passthroughTimer(const Duration(seconds: 1)),
      );
      await expectLater(
          probe.measure(), throwsA(isA<ThroughputUnmeasurable>()));
      expect(calls, 3);
    });
  });
}

/// A timer that runs the body and always reports a fixed duration, regardless
/// of how many attempts are made.
ElapsedTimer _passthroughTimer(Duration d) {
  return (body) async {
    await body();
    return d;
  };
}

/// Runs the REAL default downloader / uploader against a loopback server while
/// the request URI keeps its public host (so the host gate sees the true host),
/// captures the raw request headers off the wire, and returns them lower-cased.
Future<Map<String, String>> _captureRequestHeaders({
  required Uri requestUri,
  required bool isUpload,
}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final captured = Completer<List<String>>();

  server.listen((socket) {
    final buffer = StringBuffer();
    socket.listen(
      (data) {
        buffer.write(String.fromCharCodes(data));
        if (buffer.toString().contains('\r\n\r\n')) {
          final head = buffer.toString().split('\r\n\r\n').first;
          if (!captured.isCompleted) captured.complete(head.split('\r\n'));
          socket.write('HTTP/1.1 200 OK\r\n'
              'Content-Type: application/octet-stream\r\n'
              'Content-Length: 1\r\n'
              'Connection: close\r\n\r\n'
              'x');
          socket.destroy();
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );
  });

  HttpClient makeClient() => HttpClient()
    ..connectionFactory = (uri, proxyHost, proxyPort) =>
        Socket.startConnect(InternetAddress.loopbackIPv4, server.port);

  final probe = ThroughputProbe(
    downloadStreamCount: 1,
    maxRetries: 0,
    throughputRetries: 0,
    uploadBytes: 4 * 1024,
    maxDuration: const Duration(seconds: 3),
    downloadEndpoints: <Uri>[requestUri],
    uploadEndpoints: <Uri>[requestUri],
    httpClientFactory: makeClient,
  );

  try {
    if (isUpload) {
      await probe.uploader(requestUri, 4 * 1024, const Duration(seconds: 3));
    } else {
      await probe.downloader(requestUri, const Duration(milliseconds: 200));
    }
  } catch (_) {
    // We only care about the request head, captured before any failure.
  }

  final lines = await captured.future.timeout(const Duration(seconds: 5));
  await server.close();

  final headers = <String, String>{};
  for (final line in lines.skip(1)) {
    final idx = line.indexOf(':');
    if (idx <= 0) continue;
    final name = line.substring(0, idx).trim().toLowerCase();
    final value = line.substring(idx + 1).trim();
    headers[name] = value;
  }
  return headers;
}

/// Regression guard for the shipped 40%-freeze: the REAL default downloader /
/// uploader (not an injected seam) must never hang on a stalled endpoint.
void _registerRealTransportRegressionTests() {
  group('ThroughputProbe — real transport hard-deadline (40%-freeze guard)', () {
    const maxDuration = Duration(seconds: 2);
    const upperBound = Duration(seconds: 12);

    late ServerSocket noHeaderServer; // accepts, never responds
    late ServerSocket stallServer; // sends headers + 1 chunk, then stalls

    setUp(() async {
      noHeaderServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      noHeaderServer.listen((socket) {
        // Hold the socket open; deliberately send nothing.
      });

      stallServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      stallServer.listen((socket) {
        socket.listen((_) {}, onError: (_) {}, cancelOnError: false);
        socket.write('HTTP/1.1 200 OK\r\n'
            'Content-Type: application/octet-stream\r\n'
            'Content-Length: 1000000\r\n'
            'Connection: keep-alive\r\n\r\n');
        socket.add(List<int>.filled(1024, 0)); // one chunk, then silence
      });
    });

    tearDown(() async {
      await noHeaderServer.close();
      await stallServer.close();
    });

    test('download aborts (does not hang) when headers never arrive', () async {
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        maxRetries: 0,
        throughputRetries: 0,
        maxDuration: maxDuration,
        downloadEndpoints: <Uri>[
          Uri.parse('http://127.0.0.1:${noHeaderServer.port}/down'),
        ],
      );
      final sw = Stopwatch()..start();
      await expectLater(
        probe.measure(),
        throwsA(isA<ThroughputUnmeasurable>()),
      );
      sw.stop();
      expect(sw.elapsed, lessThan(upperBound),
          reason: 'must abort within the hard deadline, not hang');
    });

    test('download aborts (does not hang) when the body stalls mid-stream',
        () async {
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        maxRetries: 0,
        throughputRetries: 0,
        maxDuration: maxDuration,
        downloadEndpoints: <Uri>[
          Uri.parse('http://127.0.0.1:${stallServer.port}/down'),
        ],
      );
      final sw = Stopwatch()..start();
      await expectLater(
        probe.measure(),
        throwsA(isA<ThroughputUnmeasurable>()),
      );
      sw.stop();
      expect(sw.elapsed, lessThan(upperBound),
          reason: 'must abort within the hard deadline, not hang');
    });

    test(
        'a stalled endpoint falls back to a healthy one within the bound '
        '(stage completes, never freezes)', () async {
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        maxRetries: 1,
        maxDuration: maxDuration,
        downloadEndpoints: <Uri>[
          Uri.parse('http://127.0.0.1:${noHeaderServer.port}/down'), // hangs
          Uri.parse('https://healthy.test/down'), // fallback
        ],
        downloader: (uri, max) async {
          if (uri.host == 'healthy.test') return 25 * 1000 * 1000;
          return _realDownload(uri, max);
        },
        uploader: (uri, bytes, max) async => bytes,
        uploadBytes: 10 * 1000 * 1000,
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      final sw = Stopwatch()..start();
      final s = await probe.measure();
      sw.stop();
      expect(s.downloadBytes, 25 * 1000 * 1000);
      expect(s.downloadMbps, greaterThan(0.0));
      expect(sw.elapsed, lessThan(upperBound),
          reason: 'fallback must engage within the hard deadline');
    });
  });
}

/// Drives the real default downloader through a throwaway probe instance so the
/// fallback test can exercise the actual hard-deadline transport for the hung
/// loopback endpoint while seam-injecting the healthy one.
Future<int> _realDownload(Uri uri, Duration max) {
  final passthrough = ThroughputProbe(
    downloadEndpoints: <Uri>[uri],
    maxDuration: max,
  );
  return passthrough.downloader(uri, max);
}
