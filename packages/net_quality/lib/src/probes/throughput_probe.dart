import 'dart:async';
import 'dart:io';

/// Downloads from [uri] for at most [maxDuration] and returns the number of
/// bytes received. The injectable download seam.
typedef Downloader = Future<int> Function(Uri uri, Duration maxDuration);

/// Uploads [bytes] of payload to [uri] for at most [maxDuration] and returns
/// the number of bytes sent. The injectable upload seam.
typedef Uploader = Future<int> Function(
  Uri uri,
  int bytes,
  Duration maxDuration,
);

/// Measures wall-clock elapsed time for a body of work. The injectable timing
/// seam so throughput math is deterministic in tests.
typedef ElapsedTimer = Future<Duration> Function(
  Future<void> Function() body,
);

/// Aggregated throughput statistics.
class ThroughputStats {
  /// Download rate, megabits per second.
  final double downloadMbps;

  /// Upload rate, megabits per second.
  final double uploadMbps;

  /// Bytes downloaded.
  final int downloadBytes;

  /// Bytes uploaded.
  final int uploadBytes;

  /// Wall-clock time spent downloading.
  final Duration elapsedDownload;

  /// Wall-clock time spent uploading.
  final Duration elapsedUpload;

  /// Creates throughput statistics.
  const ThroughputStats({
    required this.downloadMbps,
    required this.uploadMbps,
    required this.downloadBytes,
    required this.uploadBytes,
    required this.elapsedDownload,
    required this.elapsedUpload,
  });

  @override
  String toString() =>
      'ThroughputStats(down ${downloadMbps.toStringAsFixed(1)}Mbps, '
      'up ${uploadMbps.toStringAsFixed(1)}Mbps, '
      '${downloadBytes}B/${uploadBytes}B)';
}

/// Thrown when a transfer completes without producing a usable measurement
/// (non-2xx status, empty body, or a zero-byte transfer). Surfaced so the
/// quality client reports an honest "couldn't measure" instead of a fake
/// 0 Mbps. See GL-005 / GL-008: an unmeasurable transfer is not "0".
class ThroughputUnmeasurable implements Exception {
  /// Human-readable reason the transfer could not be measured.
  final String reason;

  /// Creates the exception with a [reason].
  const ThroughputUnmeasurable(this.reason);

  @override
  String toString() => 'ThroughputUnmeasurable: $reason';
}

/// Measures download and upload throughput against swappable endpoints.
///
/// Defaults use the Cloudflare speed endpoints. All network access goes through
/// the [downloader] and [uploader] seams and timing through [timer], so the
/// rate math can be unit-tested with no real network.
class ThroughputProbe {
  /// Approximate download payload size in bytes (~25 MB by default).
  final int downloadBytes;

  /// Approximate upload payload size in bytes (~10 MB by default).
  final int uploadBytes;

  /// Download endpoint. The literal '{n}' in the path is replaced with
  /// [downloadBytes]. Cloudflare honors '?bytes=' so the default uses that.
  final Uri downloadEndpoint;

  /// Upload endpoint.
  final Uri uploadEndpoint;

  /// Hard cap on each transfer (per attempt).
  final Duration maxDuration;

  /// Maximum number of retry attempts after the first failed attempt. With the
  /// default of 2, each direction is tried up to 3 times total before giving
  /// up (which surfaces an honest "couldn't measure", never a fake 0).
  final int maxRetries;

  /// Smallest byte count that counts as a real transfer. A successful response
  /// at or below this floor is treated as a failure (e.g. an empty/hiccuped
  /// CDN response), not graded as 0 Mbps.
  final int minBytesFloor;

  /// Download seam.
  final Downloader downloader;

  /// Upload seam.
  final Uploader uploader;

  /// Timing seam.
  final ElapsedTimer timer;

  /// Creates a throughput probe.
  ThroughputProbe({
    this.downloadBytes = 25 * 1000 * 1000,
    this.uploadBytes = 10 * 1000 * 1000,
    Uri? downloadEndpoint,
    Uri? uploadEndpoint,
    this.maxDuration = const Duration(seconds: 10),
    this.maxRetries = 2,
    this.minBytesFloor = 0,
    Downloader? downloader,
    Uploader? uploader,
    ElapsedTimer? timer,
  })  : downloadEndpoint = downloadEndpoint ??
            Uri.parse(
                'https://speed.cloudflare.com/__down?bytes=$downloadBytes'),
        uploadEndpoint =
            uploadEndpoint ?? Uri.parse('https://speed.cloudflare.com/__up'),
        downloader = downloader ?? _defaultDownloader,
        uploader = uploader ?? _defaultUploader,
        timer = timer ?? _defaultTimer;

  /// Pure throughput math: bits over seconds, in megabits per second.
  ///
  /// Returns 0.0 when [elapsed] is zero or negative to avoid divide-by-zero.
  static double mbpsFor(int bytes, Duration elapsed) {
    final seconds = elapsed.inMicroseconds / 1e6;
    if (seconds <= 0) return 0.0;
    return bytes * 8 / seconds / 1e6;
  }

  /// Runs download then upload and computes both rates.
  ///
  /// Each direction is attempted up to `1 + [maxRetries]` times. A thrown
  /// transfer error or a successful-but-empty transfer (bytes at or below
  /// [minBytesFloor]) counts as a failed attempt and is retried. If every
  /// attempt fails, the final error propagates out of [measure] so the caller
  /// reports an honest "couldn't measure" — never a fabricated 0 Mbps.
  Future<ThroughputStats> measure() async {
    var dlBytes = 0;
    final dlElapsed = await _measureWithRetry((max) async {
      dlBytes = await downloader(downloadEndpoint, max);
      return dlBytes;
    });

    var ulBytes = 0;
    final ulElapsed = await _measureWithRetry((max) async {
      ulBytes = await uploader(uploadEndpoint, uploadBytes, max);
      return ulBytes;
    });

    return ThroughputStats(
      downloadMbps: mbpsFor(dlBytes, dlElapsed),
      uploadMbps: mbpsFor(ulBytes, ulElapsed),
      downloadBytes: dlBytes,
      uploadBytes: ulBytes,
      elapsedDownload: dlElapsed,
      elapsedUpload: ulElapsed,
    );
  }

  /// Runs [transfer] under the [timer] seam, retrying up to [maxRetries] extra
  /// times when it throws or returns a byte count at or below [minBytesFloor].
  /// Returns the elapsed time of the first successful attempt. Throws the last
  /// error (or a [ThroughputUnmeasurable]) when all attempts fail.
  Future<Duration> _measureWithRetry(
    Future<int> Function(Duration maxDuration) transfer,
  ) async {
    Object lastError = const ThroughputUnmeasurable('no attempts made');
    final attempts = maxRetries + 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        var bytes = 0;
        final elapsed = await timer(() async {
          bytes = await transfer(maxDuration);
        });
        if (bytes <= minBytesFloor) {
          throw ThroughputUnmeasurable(
            'empty transfer ($bytes bytes <= floor $minBytesFloor)',
          );
        }
        return elapsed;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError;
  }

  /// Default timing seam using a real [Stopwatch].
  static Future<Duration> _defaultTimer(
    Future<void> Function() body,
  ) async {
    final sw = Stopwatch()..start();
    await body();
    sw.stop();
    return sw.elapsed;
  }

  /// Default download: streams the response, counting bytes, stopping at
  /// [maxDuration].
  ///
  /// Throws [ThroughputUnmeasurable] when the endpoint returns a non-2xx
  /// status (e.g. Cloudflare rate-limiting) or an empty body, so a hiccuped
  /// request becomes an honest failure instead of a fake 0 Mbps.
  static Future<int> _defaultDownloader(Uri uri, Duration maxDuration) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Drain so the socket can be reused/closed cleanly, then fail.
        await response.drain<void>();
        throw ThroughputUnmeasurable(
          'download HTTP ${response.statusCode}',
        );
      }
      var total = 0;
      final deadline = DateTime.now().add(maxDuration);
      await for (final chunk in response) {
        total += chunk.length;
        if (DateTime.now().isAfter(deadline)) break;
      }
      if (total == 0) {
        throw const ThroughputUnmeasurable('download returned 0 bytes');
      }
      return total;
    } finally {
      client.close(force: true);
    }
  }

  /// Default upload: sends [bytes] of payload, counting bytes written, stopping
  /// at [maxDuration].
  ///
  /// Throws [ThroughputUnmeasurable] when the endpoint returns a non-2xx
  /// status or no bytes were sent, so a rejected upload becomes an honest
  /// failure instead of a fake 0 Mbps.
  static Future<int> _defaultUploader(
    Uri uri,
    int bytes,
    Duration maxDuration,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.binary;
      const chunkSize = 64 * 1024;
      final chunk = List<int>.filled(chunkSize, 0);
      var sent = 0;
      final deadline = DateTime.now().add(maxDuration);
      while (sent < bytes) {
        if (DateTime.now().isAfter(deadline)) break;
        final remaining = bytes - sent;
        final size = remaining < chunkSize ? remaining : chunkSize;
        request.add(size == chunkSize ? chunk : chunk.sublist(0, size));
        sent += size;
      }
      await request.flush();
      final response = await request.close();
      final status = response.statusCode;
      await response.drain<void>();
      if (status < 200 || status >= 300) {
        throw ThroughputUnmeasurable('upload HTTP $status');
      }
      if (sent == 0) {
        throw const ThroughputUnmeasurable('upload sent 0 bytes');
      }
      return sent;
    } finally {
      client.close(force: true);
    }
  }
}
