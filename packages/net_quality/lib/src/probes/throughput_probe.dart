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

  /// Hard cap on each transfer.
  final Duration maxDuration;

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
  Future<ThroughputStats> measure() async {
    var dlBytes = 0;
    final dlElapsed = await timer(() async {
      dlBytes = await downloader(downloadEndpoint, maxDuration);
    });

    var ulBytes = 0;
    final ulElapsed = await timer(() async {
      ulBytes = await uploader(uploadEndpoint, uploadBytes, maxDuration);
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
  static Future<int> _defaultDownloader(Uri uri, Duration maxDuration) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      var total = 0;
      final deadline = DateTime.now().add(maxDuration);
      await for (final chunk in response) {
        total += chunk.length;
        if (DateTime.now().isAfter(deadline)) break;
      }
      return total;
    } finally {
      client.close(force: true);
    }
  }

  /// Default upload: sends [bytes] of payload, counting bytes written, stopping
  /// at [maxDuration].
  static Future<int> _defaultUploader(
    Uri uri,
    int bytes,
    Duration maxDuration,
  ) async {
    final client = HttpClient();
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
      await response.drain<void>();
      return sent;
    } finally {
      client.close(force: true);
    }
  }
}
