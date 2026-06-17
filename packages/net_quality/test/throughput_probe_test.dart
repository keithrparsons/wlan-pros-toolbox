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
    test('ships >= 3 independent download endpoints, not all Cloudflare', () {
      final probe = ThroughputProbe();
      expect(probe.downloadEndpoints.length, greaterThanOrEqualTo(3));
      final hosts = probe.downloadEndpoints.map((u) => u.host).toSet();
      // Distinct providers — the whole point of multi-CDN fallback.
      expect(hosts.length, greaterThanOrEqualTo(3));
      expect(probe.downloadEndpoints.first.host, 'speed.cloudflare.com');
    });

    test('download stream count defaults to 2 and is configurable', () {
      expect(ThroughputProbe().downloadStreamCount, 2);
      expect(ThroughputProbe(downloadStreamCount: 3).downloadStreamCount, 3);
      expect(ThroughputProbe(downloadStreamCount: 1).downloadStreamCount, 1);
    });

    test('downloadEndpoint getter exposes the first endpoint (load gen seam)',
        () {
      final probe = ThroughputProbe();
      expect(probe.downloadEndpoint, probe.downloadEndpoints.first);
      expect(probe.uploadEndpoint, probe.uploadEndpoints.first);
    });
  });

  group('ThroughputProbe.measure — parallel-summed download', () {
    test('two streams of known byte counts SUM (not average) over the window',
        () async {
      // Each stream returns 30 MB. The shared window is 4s. Aggregate must be
      // the SUM: (30+30) MB * 8 / 4s / 1e6 = 120 Mbps. The AVERAGE of the two
      // per-stream rates (each 30MB/4s = 60 Mbps) would be 60 Mbps — explicitly
      // NOT what we report.
      const perStream = 30 * 1000 * 1000;
      final probe = ThroughputProbe(
        downloadStreamCount: 2,
        downloader: (uri, max) async => perStream,
        uploader: (uri, bytes, max) async => bytes,
        uploadBytes: 10 * 1000 * 1000,
        // Window: 4s for the parallel download. Upload: 2s.
        windowTimer: _passthroughTimer(const Duration(seconds: 4)),
        timer: _passthroughTimer(const Duration(seconds: 2)),
      );
      final s = await probe.measure();

      expect(s.downloadStreams, 2);
      expect(s.downloadBytes, 2 * perStream); // summed bytes
      expect(s.downloadMbps, closeTo(120.0, 0.0001)); // the SUM
      // Guard: it is NOT the per-stream average (which would be 60 Mbps).
      const perStreamRate = 60.0;
      expect(s.downloadMbps, isNot(closeTo(perStreamRate, 0.5)));
      // 10 MB * 8 / 2s / 1e6 = 40 Mbps upload.
      expect(s.uploadMbps, closeTo(40.0, 0.0001));
    });

    test('single-stream config reports just that one stream', () async {
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
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

    test('one stream fails -> falls back to next endpoint; aggregate uses the '
        'survivors', () async {
      // Three endpoints. Stream 0 starts at endpoints[0], stream 1 at
      // endpoints[1]. We make endpoints[0] fail; stream 0 falls back to its
      // next endpoint and succeeds. Both streams ultimately contribute bytes.
      final probe = ThroughputProbe(
        downloadStreamCount: 2,
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
      // Both streams succeeded (stream 0 via fallback, stream 1 directly).
      expect(s.downloadStreams, 2);
      expect(s.downloadBytes, 2 * 20 * 1000 * 1000);
      // (20+20) MB * 8 / 4s / 1e6 = 80 Mbps.
      expect(s.downloadMbps, closeTo(80.0, 0.0001));
    });

    test('one stream fully fails (no fallback succeeds) -> aggregate from the '
        'one survivor, never 0', () async {
      // Single endpoint per direction so the failing stream has nowhere to fall
      // back; the surviving stream still produces an honest aggregate.
      var calls = 0;
      final probe = ThroughputProbe(
        downloadStreamCount: 2,
        maxRetries: 0,
        // Two endpoints: stream 0 -> good.test, stream 1 -> bad.test.
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
      // Only the good stream contributed.
      expect(s.downloadStreams, 1);
      expect(s.downloadBytes, 25 * 1000 * 1000);
      // 25 MB * 8 / 4s / 1e6 = 50 Mbps — a real, honest value, not 0.
      expect(s.downloadMbps, closeTo(50.0, 0.0001));
      expect(s.downloadMbps, greaterThan(0.0));
      // maxRetries 0 -> each stream tries exactly one endpoint.
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

  group('ThroughputProbe.measure — whole-window retry (stall, then success)',
      () {
    test(
        'download window stalls on every endpoint the first time, then the '
        'retry re-opens a fresh window and measures a real rate (not 0)',
        () async {
      // The hotel transient: the whole parallel download window stalls out
      // (every endpoint fails), then a moment later it measures fine. With one
      // automatic retry the stall is absorbed and a real number comes back.
      var pass = 0;
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
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
      // Two passes: the stalled window, then the successful retry window.
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
      // Exactly one download call: a healthy window is never re-run, so a normal
      // run never doubles in time.
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
      // 1 initial window + 1 retry window = 2 download attempts.
      expect(calls, 2);
    });

    test(
        'the retry NEVER unbounds the run: a persistently-stalled window plus '
        'one retry still aborts within ~2x the hard deadline, never hangs',
        () async {
      // Defense-in-depth: even with the default retry, a real hung endpoint
      // must abort within roughly two hard-deadline windows, not hang forever.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((socket) {/* accept, send nothing */});
      addTearDown(() async => server.close());

      const maxDuration = Duration(seconds: 2);
      // One window aborts at maxDuration + 5s slack = 7s; one retry => ~14s.
      // Allow headroom but prove it is bounded, not hung.
      const upperBound = Duration(seconds: 22);
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        maxRetries: 0,
        throughputRetries: 1, // the default — exercised end to end
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
      expect(calls, 1); // no retry
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
        // Isolate the INNER per-endpoint fallback count here; the OUTER
        // whole-window retry has its own group above.
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
      // One stream, 3 endpoints, maxRetries 2 -> 3 attempts.
      expect(calls, 3);
    });

    test('zero-byte response is retried/fallen-back before giving up',
        () async {
      var calls = 0;
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        maxRetries: 2,
        // Isolate the INNER per-endpoint fallback count (floor-failure is
        // retried, not accepted as 0); the OUTER window retry is tested above.
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
      expect(calls, 3); // floor-failure was retried, not accepted as 0
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

/// Regression guard for the shipped 40%-freeze: the REAL default downloader /
/// uploader (not an injected seam) must never hang on a stalled endpoint. These
/// run against loopback servers that complete the TCP handshake (so
/// HttpClient.connectionTimeout is satisfied) but then never send response
/// headers, or stall mid-body — the exact conditions that froze the download
/// stage at 40% on macOS + iOS. The transfer must ABORT within the hard
/// deadline, never block forever.
void _registerRealTransportRegressionTests() {
  group('ThroughputProbe — real transport hard-deadline (40%-freeze guard)', () {
    // Short maxDuration so the test's bound (maxDuration + 5s slack) stays well
    // under the default test timeout, while still proving the deadline fires.
    const maxDuration = Duration(seconds: 2);
    // The probe aborts at maxDuration + _transferDeadlineSlack (5s) = 7s.
    // Allow headroom but assert it is bounded, not hung.
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
        // Never close: the response stream stalls awaiting the rest.
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
        // Isolate the per-transfer hard deadline (one window): the outer
        // whole-window retry is exercised in its own group above.
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
        // Isolate the per-transfer hard deadline (one window); outer retry
        // is tested above.
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
      // Stream starts on the hung server, then falls back to a seam-injected
      // healthy endpoint. The whole measure() must complete bounded.
      final probe = ThroughputProbe(
        downloadStreamCount: 1,
        maxRetries: 1,
        maxDuration: maxDuration,
        downloadEndpoints: <Uri>[
          Uri.parse('http://127.0.0.1:${noHeaderServer.port}/down'), // hangs
          Uri.parse('https://healthy.test/down'), // fallback
        ],
        // Inject a healthy downloader ONLY for the fallback host; let the real
        // default handle the loopback host so its hard deadline is exercised.
        downloader: (uri, max) async {
          if (uri.host == 'healthy.test') return 25 * 1000 * 1000;
          // Delegate to the real transport for the loopback (hung) endpoint.
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
