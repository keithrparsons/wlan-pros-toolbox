import 'package:net_quality/net_quality.dart';
import 'package:test/test.dart';

void main() {
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

  group('ThroughputProbe.measure', () {
    test('composes download and upload with injected seams', () async {
      final probe = ThroughputProbe(
        downloadBytes: 50 * 1000 * 1000,
        uploadBytes: 10 * 1000 * 1000,
        downloader: (uri, max) async => 50 * 1000 * 1000,
        uploader: (uri, bytes, max) async => bytes,
        // Deterministic: download took 4s, upload took 2s.
        timer: _scriptedTimer(const <Duration>[
          Duration(seconds: 4),
          Duration(seconds: 2),
        ]),
      );
      final s = await probe.measure();
      expect(s.downloadBytes, 50 * 1000 * 1000);
      expect(s.uploadBytes, 10 * 1000 * 1000);
      // 50 MB * 8 / 4s / 1e6 = 100 Mbps.
      expect(s.downloadMbps, closeTo(100.0, 0.0001));
      // 10 MB * 8 / 2s / 1e6 = 40 Mbps.
      expect(s.uploadMbps, closeTo(40.0, 0.0001));
      expect(s.elapsedDownload, const Duration(seconds: 4));
      expect(s.elapsedUpload, const Duration(seconds: 2));
    });

    test('zero-byte download is treated as a failure, not 0 Mbps', () async {
      final probe = ThroughputProbe(
        maxRetries: 0,
        downloader: (uri, max) async => 0, // empty/hiccuped response
        uploader: (uri, bytes, max) async => bytes,
        timer: _passthroughTimer(const Duration(seconds: 1)),
      );
      await expectLater(probe.measure(), throwsA(isA<ThroughputUnmeasurable>()));
    });

    test('non-2xx-style failure (thrown by seam) is not 0 Mbps', () async {
      final probe = ThroughputProbe(
        maxRetries: 0,
        downloader: (uri, max) async =>
            throw const ThroughputUnmeasurable('download HTTP 429'),
        uploader: (uri, bytes, max) async => bytes,
        timer: _passthroughTimer(const Duration(seconds: 1)),
      );
      await expectLater(probe.measure(), throwsA(isA<ThroughputUnmeasurable>()));
    });

    test('retry-then-success: first attempt fails, second yields real Mbps',
        () async {
      var calls = 0;
      final probe = ThroughputProbe(
        downloadBytes: 50 * 1000 * 1000,
        uploadBytes: 10 * 1000 * 1000,
        downloader: (uri, max) async {
          calls++;
          if (calls == 1) throw const ThroughputUnmeasurable('transient 503');
          return 50 * 1000 * 1000;
        },
        uploader: (uri, bytes, max) async => bytes,
        timer: _passthroughTimer(const Duration(seconds: 4)),
      );
      final s = await probe.measure();
      expect(calls, 2); // failed once, then succeeded
      // 50 MB * 8 / 4s / 1e6 = 100 Mbps -> a real measurement, not 0.
      expect(s.downloadMbps, closeTo(100.0, 0.0001));
      expect(s.downloadBytes, 50 * 1000 * 1000);
    });

    test('all attempts fail: throws after exhausting retries', () async {
      var calls = 0;
      final probe = ThroughputProbe(
        maxRetries: 2, // 1 + 2 = 3 attempts total
        downloader: (uri, max) async {
          calls++;
          throw const ThroughputUnmeasurable('rate limited');
        },
        uploader: (uri, bytes, max) async => bytes,
        timer: _passthroughTimer(const Duration(seconds: 1)),
      );
      await expectLater(probe.measure(), throwsA(isA<ThroughputUnmeasurable>()));
      expect(calls, 3);
    });

    test('zero-byte response is retried before giving up', () async {
      var calls = 0;
      final probe = ThroughputProbe(
        maxRetries: 2,
        downloader: (uri, max) async {
          calls++;
          return 0; // every attempt empty
        },
        uploader: (uri, bytes, max) async => bytes,
        timer: _passthroughTimer(const Duration(seconds: 1)),
      );
      await expectLater(probe.measure(), throwsA(isA<ThroughputUnmeasurable>()));
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

/// Returns a timer that runs each body and reports the scripted durations in
/// order, regardless of real wall-clock time.
ElapsedTimer _scriptedTimer(List<Duration> durations) {
  var i = 0;
  return (body) async {
    await body();
    return durations[i++];
  };
}
