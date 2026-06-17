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

/// The two sub-stages a throughput measurement passes through, in order.
/// Emitted via [ThroughputProbe.measure]'s `onStage` callback so a caller can
/// drive smooth elapsed-time progress that pivots its target band the moment
/// the download window ends and the upload window begins.
enum ThroughputStage {
  /// The parallel download window is about to start.
  download,

  /// The single-stream upload window is about to start.
  upload,
}

/// Aggregated throughput statistics.
class ThroughputStats {
  /// Download rate, megabits per second.
  final double downloadMbps;

  /// Upload rate, megabits per second.
  final double uploadMbps;

  /// Bytes downloaded (summed across all concurrent download streams).
  final int downloadBytes;

  /// Bytes uploaded.
  final int uploadBytes;

  /// Wall-clock time spent downloading (the parallel-window elapsed).
  final Duration elapsedDownload;

  /// Wall-clock time spent uploading.
  final Duration elapsedUpload;

  /// Number of download streams that produced a usable measurement. With the
  /// parallel-summed approach this is 1 or 2 (or more, if configured); the
  /// reported [downloadMbps] is the aggregate of these streams over the shared
  /// window, not a per-stream average.
  final int downloadStreams;

  /// Creates throughput statistics.
  const ThroughputStats({
    required this.downloadMbps,
    required this.uploadMbps,
    required this.downloadBytes,
    required this.uploadBytes,
    required this.elapsedDownload,
    required this.elapsedUpload,
    this.downloadStreams = 1,
  });

  @override
  String toString() =>
      'ThroughputStats(down ${downloadMbps.toStringAsFixed(1)}Mbps '
      'over $downloadStreams stream(s), '
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
/// Download uses a parallel-summed, multi-CDN strategy (the Ookla / Fast.com
/// model): [downloadStreamCount] concurrent download streams run within ONE
/// shared measurement window, each against a DIFFERENT endpoint from an ordered
/// [downloadEndpoints] fallback list. The reported download rate is the SUM of
/// all streams' bytes over the wall-clock window, divided into Mbps. Two flows
/// share the link and each gets ~half its capacity, so summing their byte
/// counts over the shared window yields the true aggregate throughput;
/// averaging would under-report by ~half.
///
/// Upload is a single stream with the same multi-CDN fallback chain (the only
/// verified reliable large-POST sink is Cloudflare `__up`; a second independent
/// upload sink was not found, so upload is honest single-stream-with-fallback
/// rather than faked parallelism).
///
/// All network access goes through the [downloader] and [uploader] seams and
/// timing through [timer] (and the parallel-window timing through
/// [windowTimer]), so the rate math can be unit-tested with no real network.
class ThroughputProbe {
  /// Approximate download payload size in bytes, PER STREAM (~25 MB default).
  final int downloadBytes;

  /// Approximate upload payload size in bytes (~10 MB by default).
  final int uploadBytes;

  /// Ordered list of independent download endpoints. The probe assigns the
  /// first [downloadStreamCount] healthy endpoints to concurrent streams and
  /// uses the remainder as fallbacks when a stream's endpoint fails.
  ///
  /// The literal '{n}' in a path/query is replaced with [downloadBytes] so an
  /// endpoint that honors a byte-count parameter (Cloudflare) gets a sized
  /// request; fixed-size endpoints (OVH, Cachefly) ignore it.
  final List<Uri> downloadEndpoints;

  /// Ordered list of upload endpoints. Single stream; tries the next on
  /// failure. Defaults to Cloudflare `__up` (the only verified large-POST sink).
  final List<Uri> uploadEndpoints;

  /// Number of concurrent download streams to run in the shared window.
  /// Defaults to 2 (the Ookla / Fast.com aggregate-capacity model).
  final int downloadStreamCount;

  /// Hard cap on each transfer (per attempt). For the parallel download this is
  /// the WHOLE shared window, not per-stream, so the parallel run does not
  /// double the time budget.
  final Duration maxDuration;

  /// Maximum number of fallback substitutions per download stream after its
  /// first endpoint fails, bounded so the run never loops forever. Also the
  /// retry budget for the single upload stream.
  final int maxRetries;

  /// Number of times to re-run a WHOLE throughput sub-stage (the parallel
  /// download window, or the upload window) from scratch after it produced no
  /// usable measurement, before giving up with [ThroughputUnmeasurable].
  ///
  /// This is the OUTER retry, distinct from [maxRetries] (the inner per-stream
  /// endpoint fallback). [maxRetries] swaps endpoints WITHIN one window; this
  /// re-opens a FRESH window when that whole window stalled out (the hotel
  /// transient: latency/jitter/loss/RPM all succeeded, only the throughput
  /// window stalled, then a minute later it measured fine). It extends the
  /// existing CDN-stall handling rather than duplicating its deadlines: each
  /// retried window is bounded by the SAME [maxDuration] + [_transferDeadlineSlack]
  /// per transfer, so the cost is paid ONLY on a stall, never on the healthy
  /// path. Defaults to 1: one automatic retry, so a single transient stall is
  /// absorbed without doubling a normal run's time.
  final int throughputRetries;

  /// Smallest byte count that counts as a real transfer. A successful response
  /// at or below this floor is treated as a failure (e.g. an empty/hiccuped
  /// CDN response), not graded as 0 Mbps.
  final int minBytesFloor;

  /// Download seam.
  final Downloader downloader;

  /// Upload seam.
  final Uploader uploader;

  /// Per-attempt timing seam (used for the single upload stream).
  final ElapsedTimer timer;

  /// Shared-window timing seam: measures wall-clock across the whole parallel
  /// download window. Injectable so the parallel-sum math is deterministic.
  final ElapsedTimer windowTimer;

  /// The first download endpoint, kept for the responsiveness load generator
  /// (which drives a single download flow as its load source).
  Uri get downloadEndpoint => downloadEndpoints.first;

  /// The first upload endpoint.
  Uri get uploadEndpoint => uploadEndpoints.first;

  /// Default ordered download endpoints. Three independent providers, all
  /// HTTPS, all no-auth, all verified to return a sized 2xx payload:
  ///   1. Cloudflare  — honors `?bytes=N` (configurable), proven primary.
  ///   2. OVH proof   — fixed 100 MB file, plain HTTPS GET.
  ///   3. Cachefly    — fixed 100 MB file, plain HTTPS GET.
  static List<Uri> _defaultDownloadEndpoints(int bytes) => <Uri>[
        Uri.parse('https://speed.cloudflare.com/__down?bytes=$bytes'),
        Uri.parse('https://proof.ovh.net/files/100Mb.dat'),
        Uri.parse('https://cachefly.cachefly.net/100mb.test'),
      ];

  /// Creates a throughput probe.
  ThroughputProbe({
    this.downloadBytes = 25 * 1000 * 1000,
    this.uploadBytes = 10 * 1000 * 1000,
    List<Uri>? downloadEndpoints,
    List<Uri>? uploadEndpoints,
    this.downloadStreamCount = 2,
    this.maxDuration = const Duration(seconds: 10),
    this.maxRetries = 2,
    this.throughputRetries = 1,
    this.minBytesFloor = 0,
    Downloader? downloader,
    Uploader? uploader,
    ElapsedTimer? timer,
    ElapsedTimer? windowTimer,
  })  : assert(downloadStreamCount >= 1, 'need at least one download stream'),
        assert(throughputRetries >= 0, 'retry budget cannot be negative'),
        downloadEndpoints =
            (downloadEndpoints != null && downloadEndpoints.isNotEmpty)
                ? List<Uri>.unmodifiable(downloadEndpoints)
                : List<Uri>.unmodifiable(_defaultDownloadEndpoints(
                    downloadBytes,
                  )),
        uploadEndpoints =
            (uploadEndpoints != null && uploadEndpoints.isNotEmpty)
                ? List<Uri>.unmodifiable(uploadEndpoints)
                : List<Uri>.unmodifiable(<Uri>[
                    Uri.parse('https://speed.cloudflare.com/__up'),
                  ]),
        downloader = downloader ?? _defaultDownloader,
        uploader = uploader ?? _defaultUploader,
        timer = timer ?? _defaultTimer,
        windowTimer = windowTimer ?? _defaultTimer;

  /// Pure throughput math: bits over seconds, in megabits per second.
  ///
  /// Returns 0.0 when [elapsed] is zero or negative to avoid divide-by-zero.
  static double mbpsFor(int bytes, Duration elapsed) {
    final seconds = elapsed.inMicroseconds / 1e6;
    if (seconds <= 0) return 0.0;
    return bytes * 8 / seconds / 1e6;
  }

  /// Runs the parallel-summed download then the single-stream upload and
  /// computes both rates.
  ///
  /// Download: [downloadStreamCount] streams run concurrently in ONE window,
  /// each against a distinct endpoint. Per-stream endpoint failures fall back
  /// to the next healthy endpoint (bounded by [maxRetries]). The reported rate
  /// is `(sum of all successful streams' bytes) * 8 / windowSeconds / 1e6`. If
  /// EVERY stream fails (all endpoints exhausted) a [ThroughputUnmeasurable]
  /// propagates out so the caller reports an honest "couldn't measure", never a
  /// fabricated 0 Mbps.
  ///
  /// Upload: a single stream with the multi-CDN fallback chain; tries the next
  /// upload endpoint on failure, up to `1 + [maxRetries]` attempts.
  ///
  /// [onStage], when given, fires synchronously immediately before each
  /// sub-stage begins ([ThroughputStage.download] then
  /// [ThroughputStage.upload]). It exists purely so a caller can drive smooth
  /// elapsed-time progress that pivots its target band at the download→upload
  /// boundary; it never affects the measurement itself, and a throwing callback
  /// must not abort the run (callers keep it trivial). [onStage] fires once per
  /// sub-stage even when [throughputRetries] re-opens a stalled window, so the
  /// progress bar is not yanked backwards by a retry.
  ///
  /// Each sub-stage is retried up to [throughputRetries] times when the WHOLE
  /// window stalled out (every endpoint exhausted). The retry re-opens a fresh
  /// window against the same endpoint chain, bounded by the same per-transfer
  /// deadlines — so the only path that pays the retry cost is the stall, never
  /// a healthy run. A sub-stage that still cannot measure after its retries
  /// propagates [ThroughputUnmeasurable] (download) so the caller reports an
  /// honest "couldn't measure", never a fabricated 0 Mbps.
  Future<ThroughputStats> measure({
    void Function(ThroughputStage stage)? onStage,
  }) async {
    onStage?.call(ThroughputStage.download);
    final dl = await _withRetry(_measureParallelDownload);

    onStage?.call(ThroughputStage.upload);
    var ulBytes = 0;
    final ulElapsed = await _withRetry(() => _measureUploadWithFallback(
          (max, uri) async {
            ulBytes = await uploader(uri, uploadBytes, max);
            return ulBytes;
          },
        ));

    return ThroughputStats(
      downloadMbps: mbpsFor(dl.totalBytes, dl.elapsed),
      uploadMbps: mbpsFor(ulBytes, ulElapsed),
      downloadBytes: dl.totalBytes,
      uploadBytes: ulBytes,
      elapsedDownload: dl.elapsed,
      elapsedUpload: ulElapsed,
      downloadStreams: dl.successfulStreams,
    );
  }

  /// Runs [run] and, when it raises [ThroughputUnmeasurable] (the whole window
  /// stalled out, every endpoint exhausted), re-runs it from scratch up to
  /// [throughputRetries] times before letting the last failure propagate. A
  /// successful run returns immediately, so the healthy path never pays the
  /// retry cost. Only [ThroughputUnmeasurable] is retried; any other error
  /// (a programming fault) propagates at once rather than being silently
  /// re-attempted.
  Future<T> _withRetry<T>(Future<T> Function() run) async {
    final int attempts = throughputRetries + 1;
    ThroughputUnmeasurable lastError =
        const ThroughputUnmeasurable('no throughput attempt made');
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        return await run();
      } on ThroughputUnmeasurable catch (e) {
        lastError = e;
      }
    }
    throw lastError;
  }

  /// Runs [downloadStreamCount] concurrent download streams in a single shared
  /// window and SUMS their bytes. Each stream owns a slice of the ordered
  /// endpoint list and substitutes the next endpoint on failure (bounded).
  ///
  /// Returns the summed bytes, the wall-clock window elapsed, and how many
  /// streams succeeded. Throws [ThroughputUnmeasurable] when no stream produced
  /// any usable bytes.
  Future<_DownloadOutcome> _measureParallelDownload() async {
    // Bound the number of streams to the endpoints we actually have.
    final streamCount = downloadStreamCount > downloadEndpoints.length
        ? downloadEndpoints.length
        : downloadStreamCount;

    // Partition the ordered endpoint list across streams so two streams never
    // hammer the SAME endpoint, while leftover endpoints become per-stream
    // fallbacks. Stream i starts at endpoints[i] and round-robins through the
    // list for its fallbacks, skipping back to its own start ordering.
    final perStreamEndpoints = _partitionEndpoints(streamCount);

    final streamBytes = List<int>.filled(streamCount, 0);

    final elapsed = await windowTimer(() async {
      await Future.wait<void>(<Future<void>>[
        for (var i = 0; i < streamCount; i++)
          _runOneDownloadStream(perStreamEndpoints[i], maxDuration).then(
            (bytes) => streamBytes[i] = bytes,
            // A stream that exhausts its endpoints contributes 0 and does not
            // abort the window; the aggregate is computed from the survivors.
            onError: (Object _) => streamBytes[i] = 0,
          ),
      ]);
    });

    final totalBytes = streamBytes.fold<int>(0, (a, b) => a + b);
    final successfulStreams = streamBytes.where((b) => b > minBytesFloor).length;

    if (totalBytes <= minBytesFloor) {
      throw ThroughputUnmeasurable(
        'all $streamCount download stream(s) failed across '
        '${downloadEndpoints.length} endpoint(s)',
      );
    }

    return _DownloadOutcome(
      totalBytes: totalBytes,
      elapsed: elapsed,
      successfulStreams: successfulStreams,
    );
  }

  /// Builds the ordered endpoint try-list for each of [streamCount] streams.
  /// Stream i prefers endpoints[i] first, then the remaining endpoints in
  /// rotation, so concurrent streams hit DIFFERENT providers and each stream
  /// has a fallback chain.
  List<List<Uri>> _partitionEndpoints(int streamCount) {
    final n = downloadEndpoints.length;
    return <List<Uri>>[
      for (var i = 0; i < streamCount; i++)
        <Uri>[for (var k = 0; k < n; k++) downloadEndpoints[(i + k) % n]],
    ];
  }

  /// Runs one download stream against an ordered [endpoints] try-list. Returns
  /// the bytes of the first endpoint that yields a usable transfer. On failure
  /// (throw, or bytes at or below [minBytesFloor]) substitutes the next
  /// endpoint, bounded to `1 + [maxRetries]` attempts. Throws when exhausted.
  Future<int> _runOneDownloadStream(
    List<Uri> endpoints,
    Duration windowDuration,
  ) async {
    Object lastError = const ThroughputUnmeasurable('no endpoints for stream');
    final attempts =
        (maxRetries + 1) < endpoints.length ? (maxRetries + 1) : endpoints.length;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final uri = endpoints[attempt];
      try {
        final bytes = await downloader(uri, windowDuration);
        if (bytes <= minBytesFloor) {
          throw ThroughputUnmeasurable(
            'empty transfer from $uri ($bytes bytes <= floor $minBytesFloor)',
          );
        }
        return bytes;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError;
  }

  /// Runs the single upload [transfer] under the [timer] seam against the
  /// ordered [uploadEndpoints], substituting the next endpoint on failure
  /// (throw or bytes at or below [minBytesFloor]). Bounded to `1 + [maxRetries]`
  /// attempts. Returns the elapsed time of the first success; throws the last
  /// error when all attempts/endpoints are exhausted.
  Future<Duration> _measureUploadWithFallback(
    Future<int> Function(Duration maxDuration, Uri uri) transfer,
  ) async {
    Object lastError = const ThroughputUnmeasurable('no upload attempts made');
    final attempts = maxRetries + 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final uri = uploadEndpoints[attempt % uploadEndpoints.length];
      try {
        var bytes = 0;
        final elapsed = await timer(() async {
          bytes = await transfer(maxDuration, uri);
        });
        if (bytes <= minBytesFloor) {
          throw ThroughputUnmeasurable(
            'empty upload ($bytes bytes <= floor $minBytesFloor)',
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

  /// Hard ceiling added to [maxDuration] to bound the connect + response-header
  /// phase. [maxDuration] only bounds the byte-streaming window; an endpoint
  /// that completes the TCP handshake (so [HttpClient.connectionTimeout] is
  /// satisfied) but never sends response headers, or stalls mid-body, would
  /// otherwise hang forever and freeze the whole stage. The wall-clock
  /// `.timeout()` below guarantees every transfer either completes or aborts
  /// within `maxDuration + _transferDeadlineSlack`, so the download stage can
  /// never freeze. See the 40%-freeze regression.
  static const Duration _transferDeadlineSlack = Duration(seconds: 5);

  /// Default download: streams the response, counting bytes, stopping at
  /// [maxDuration].
  ///
  /// Throws [ThroughputUnmeasurable] when the endpoint returns a non-2xx
  /// status (e.g. Cloudflare rate-limiting), an empty body, OR when the whole
  /// transfer (connect + headers + body) exceeds the hard wall-clock deadline,
  /// so a hung/stalled endpoint becomes an honest, recoverable failure (the
  /// caller falls back to the next endpoint) instead of freezing the stage.
  /// Accepts both 200 and 206 (range/partial) since some CDN files are served
  /// via ranges.
  static Future<int> _defaultDownloader(Uri uri, Duration maxDuration) async {
    final hardDeadline = maxDuration + _transferDeadlineSlack;
    try {
      return await _downloadOnce(uri, maxDuration).timeout(
        hardDeadline,
        onTimeout: () => throw ThroughputUnmeasurable(
          'download exceeded hard deadline '
          '(${hardDeadline.inSeconds}s) from $uri',
        ),
      );
    } on TimeoutException {
      // Defensive: any TimeoutException surfacing from a lower layer is still a
      // recoverable "couldn't measure", never a fake 0 Mbps or a hang.
      throw ThroughputUnmeasurable('download timed out from $uri');
    }
  }

  static Future<int> _downloadOnce(Uri uri, Duration maxDuration) async {
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
  /// status, no bytes were sent, OR when the whole transfer exceeds the hard
  /// wall-clock deadline (a sink that accepts the connection but never ACKs the
  /// POST or never returns a response would otherwise hang the stage). A
  /// timed-out upload becomes an honest, recoverable failure, never a fake
  /// 0 Mbps.
  static Future<int> _defaultUploader(
    Uri uri,
    int bytes,
    Duration maxDuration,
  ) async {
    final hardDeadline = maxDuration + _transferDeadlineSlack;
    try {
      return await _uploadOnce(uri, bytes, maxDuration).timeout(
        hardDeadline,
        onTimeout: () => throw ThroughputUnmeasurable(
          'upload exceeded hard deadline '
          '(${hardDeadline.inSeconds}s) to $uri',
        ),
      );
    } on TimeoutException {
      throw ThroughputUnmeasurable('upload timed out to $uri');
    }
  }

  static Future<int> _uploadOnce(
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

/// Internal result of the parallel download window.
class _DownloadOutcome {
  final int totalBytes;
  final Duration elapsed;
  final int successfulStreams;

  const _DownloadOutcome({
    required this.totalBytes,
    required this.elapsed,
    required this.successfulStreams,
  });
}
