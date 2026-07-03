import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

/// A self-contained M-Lab **NDT7** throughput client — the Toolbox's
/// *authoritative* internet-throughput engine.
///
/// NDT7 is a single-stream TCP throughput measurement against a real, remote
/// M-Lab server placed at an interconnection point (not inside the user's ISP).
/// It is congestion-aware and single-stream *by design*, so it cannot be
/// inflated by piling on parallel flows the way consumer speed tests are. It
/// reads **below** Ookla/Fast on impaired paths on purpose — that lower number
/// is the honest one. See the 2026-07-03 research brief
/// (`Deliverables/2026-07-03-toolbox-internet-throughput-no-server.md`).
///
/// This is a NEW engine, entirely separate from the Cloudflare-based
/// `ThroughputProbe`. It shares that class's honesty contract: an unmeasurable
/// transfer raises a typed exception ([Ndt7Unmeasurable]) rather than reporting
/// a fabricated `0 Mbps`.
///
/// ### Protocol, in three steps
///
/// 1. **Locate.** `GET https://locate.measurementlab.net/v2/nearest/ndt/ndt7`
///    returns a JSON `results[]`, each entry carrying `urls` keyed by
///    `wss:///ndt/v7/download` and `wss:///ndt/v7/upload` (each already includes
///    a signed access token). The first entry with both URLs is the primary; the
///    rest are fallbacks.
/// 2. **Download.** Open the `wss` download URL. The server streams binary
///    messages (throwaway data) and periodically sends TEXT JSON "measurement"
///    messages. The authoritative download rate is **all received bytes × 8 /
///    elapsed seconds** over the ~10 s window, computed client-side.
/// 3. **Upload.** Open the `wss` upload URL and send binary frames as fast as
///    the socket accepts (respecting backpressure) for ~10 s. Here the SERVER
///    sends TEXT JSON measurements reporting how many bytes *it* received; the
///    authoritative upload rate is the **server's** reported bytes / elapsed —
///    not the client's send count.
///
/// ### Testability
///
/// Every side effect is an injectable seam so the protocol logic runs with no
/// real network (mirrors how `ThroughputProbe` injects `downloader` / `timer` /
/// `livenessProbe`):
///
/// * [locateFetcher] — performs the Locate HTTPS GET, returns a
///   [Ndt7LocateResponse]. Default uses `package:http`.
/// * [connector] — opens an [Ndt7Socket] for a `wss` URL. Default wraps
///   `web_socket_channel`.
/// * [downloadTimer] — measures the download window's wall-clock elapsed.
/// * [clock] — the wall clock used for deadlines. Default `DateTime.now`.
///
/// The shared protocol path imports no `dart:io`, so it compiles for web.
class Ndt7Client {
  /// The M-Lab Locate API v2 endpoint for the nearest NDT7 servers.
  static final Uri defaultLocateUrl = Uri.parse(
    'https://locate.measurementlab.net/v2/nearest/ndt/ndt7',
  );

  /// The NDT7 WebSocket subprotocol. Both endpoints MUST be opened with it.
  static const String subprotocol = 'net.measurementlab.ndt.v7';

  /// Key of the secure download URL inside a Locate result's `urls` map.
  static const String downloadUrlKey = 'wss:///ndt/v7/download';

  /// Key of the secure upload URL inside a Locate result's `urls` map.
  static const String uploadUrlKey = 'wss:///ndt/v7/upload';

  /// The Locate API URL to query. Overridable for tests / a private M-Lab pool.
  final Uri locateUrl;

  /// Target duration of each measurement window (~10 s per the NDT7 spec). The
  /// download loop stops reading, and the upload loop stops sending, once this
  /// elapses.
  final Duration measurementDuration;

  /// Slack added on top of [measurementDuration] to form the HARD deadline that
  /// bounds a stage. A stalled socket that never delivers a byte (or never
  /// closes) can't hang the stage past `measurementDuration + deadlineSlack`.
  /// Mirrors `ThroughputProbe`'s `_transferDeadlineSlack`.
  final Duration deadlineSlack;

  /// Smallest upload frame, in bytes (8 KiB). The upload starts here and grows
  /// toward [maxUploadMessageBytes] as more data is sent, per the NDT7 spec's
  /// adaptive message-size guidance.
  final int minUploadMessageBytes;

  /// Largest upload frame, in bytes (64 KiB). The task pins the frame range to
  /// 8–64 KB; the NDT7 spec permits larger, but a 64 KiB ceiling keeps memory
  /// bounded across all five platforms including web.
  final int maxUploadMessageBytes;

  /// Fetches the Locate API response. Injectable so server discovery is
  /// unit-tested with no network. Defaults to a `package:http` GET.
  final Ndt7LocateFetcher locateFetcher;

  /// Opens an [Ndt7Socket] for a `wss` URL. Injectable so the protocol logic is
  /// driven by a fake socket in tests. Defaults to a `web_socket_channel` adapter.
  final Ndt7SocketConnector connector;

  /// Measures the wall-clock elapsed of the download window. Injectable so the
  /// download rate math is deterministic in tests (mirrors `ThroughputProbe`'s
  /// `windowTimer`). Defaults to a real [Stopwatch].
  final Ndt7ElapsedTimer downloadTimer;

  /// The wall clock used for the soft window deadline. Injectable for tests.
  /// Defaults to [DateTime.now].
  final DateTime Function() clock;

  /// Whether to run the upload stage. Defaults to **false**: download is the
  /// honest headline number nearly everyone cares about, the upload stage adds
  /// ~10s and is the memory-/parse-fragile path (it OOM-crashed iOS via
  /// unbounded send queuing and the real server's measurement JSON didn't parse
  /// the same as the test fake). Kept behind a flag — not deleted — so upload
  /// can be re-enabled as an optional secondary metric once it's made reliable.
  final bool measureUpload;

  /// Creates an NDT7 client. All seams default to real implementations; pass a
  /// fake [locateFetcher] / [connector] / [downloadTimer] / [clock] to drive the
  /// protocol logic with no network.
  Ndt7Client({
    Uri? locateUrl,
    this.measurementDuration = const Duration(seconds: 10),
    this.deadlineSlack = const Duration(seconds: 5),
    this.measureUpload = false,
    this.minUploadMessageBytes = 8 * 1024,
    this.maxUploadMessageBytes = 64 * 1024,
    Ndt7LocateFetcher? locateFetcher,
    Ndt7SocketConnector? connector,
    Ndt7ElapsedTimer? downloadTimer,
    DateTime Function()? clock,
  })  : assert(
          minUploadMessageBytes > 0 &&
              maxUploadMessageBytes >= minUploadMessageBytes,
          'upload frame bounds must be positive and ordered',
        ),
        locateUrl = locateUrl ?? defaultLocateUrl,
        locateFetcher = locateFetcher ?? _defaultLocateFetcher,
        connector = connector ?? _defaultConnector,
        downloadTimer = downloadTimer ?? _defaultElapsedTimer,
        clock = clock ?? DateTime.now;

  /// Pure throughput math: bits over seconds, in megabits per second. Returns
  /// `0.0` when [elapsed] is zero or negative to avoid divide-by-zero (callers
  /// treat a genuinely unmeasurable transfer as an exception, not a `0`).
  static double mbpsFor(int bytes, Duration elapsed) {
    final seconds = elapsed.inMicroseconds / 1e6;
    if (seconds <= 0) return 0.0;
    return bytes * 8 / seconds / 1e6;
  }

  /// Runs the full measurement: Locate, then the download window, then the
  /// upload window. Returns the combined [Ndt7Result].
  ///
  /// The download runs against the first Locate target whose download socket
  /// opens; the upload runs against the first target whose upload socket opens.
  /// Remaining targets are fallbacks. Any unrecoverable failure — no server from
  /// Locate, every socket failing, or a window that transferred nothing — raises
  /// [Ndt7Unmeasurable] (or its [Ndt7NoServerAvailable] subtype), never a
  /// fabricated `0 Mbps`.
  Future<Ndt7Result> measure() async {
    final targets = await locate();

    // Download is the primary, honest number and must succeed for a result.
    final download = await _runDownload(targets);

    // Upload is best-effort and OFF by default ([measureUpload]). It is never
    // allowed to fail the whole test or crash: a good download stands on its
    // own, and its fields are simply null when upload was skipped or failed.
    _StageOutcome? upload;
    if (measureUpload) {
      try {
        upload = await _runUpload(targets);
      } catch (_) {
        upload = null;
      }
    }

    return Ndt7Result(
      downloadMbps: mbpsFor(download.bytes, download.elapsed),
      uploadMbps: upload == null ? null : mbpsFor(upload.bytes, upload.elapsed),
      downloadBytes: download.bytes,
      uploadBytes: upload?.bytes,
      elapsedDownload: download.elapsed,
      elapsedUpload: upload?.elapsed,
      serverHost: download.serverHost,
    );
  }

  /// Queries the Locate API and returns the parsed, ordered list of NDT7
  /// targets. Throws [Ndt7NoServerAvailable] on an HTTP error, a malformed body,
  /// an API-level `error`, or an empty `results[]` — an honest "no server", not
  /// a fake `0`.
  Future<List<Ndt7Target>> locate() async {
    final Ndt7LocateResponse response;
    try {
      response = await locateFetcher(locateUrl);
    } catch (e) {
      throw Ndt7NoServerAvailable('Locate request failed: $e');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Ndt7NoServerAvailable(
        'Locate returned HTTP ${response.statusCode}',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (e) {
      throw Ndt7NoServerAvailable('Locate body was not valid JSON: $e');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const Ndt7NoServerAvailable('Locate body was not a JSON object');
    }

    // The API reports upstream failures as a top-level `error` object.
    if (decoded['error'] != null) {
      throw Ndt7NoServerAvailable('Locate error: ${decoded['error']}');
    }

    final results = decoded['results'];
    if (results is! List || results.isEmpty) {
      throw const Ndt7NoServerAvailable('Locate returned no servers');
    }

    final targets = <Ndt7Target>[];
    for (final entry in results) {
      final target = Ndt7Target.tryParse(entry);
      if (target != null) targets.add(target);
    }

    if (targets.isEmpty) {
      throw const Ndt7NoServerAvailable(
        'Locate results carried no usable wss download/upload URLs',
      );
    }
    return targets;
  }

  /// Runs the download window against [targets] in order, using the first whose
  /// socket opens. Throws [Ndt7Unmeasurable] when every target's socket fails or
  /// the winning socket delivered no bytes.
  Future<_StageOutcome> _runDownload(List<Ndt7Target> targets) async {
    Object lastError =
        const Ndt7Unmeasurable('no download target was attempted');
    for (final target in targets) {
      final Ndt7Socket socket;
      try {
        socket = await connector(target.downloadUrl, subprotocol);
      } catch (e) {
        lastError = Ndt7Unmeasurable('download socket failed to open: $e');
        continue;
      }
      try {
        return await _download(socket, target.host);
      } on Ndt7Unmeasurable catch (e) {
        // The socket opened but produced nothing usable; try the next target.
        lastError = e;
      } finally {
        await socket.close();
      }
    }
    throw lastError is Ndt7Unmeasurable
        ? lastError
        : Ndt7Unmeasurable('$lastError');
  }

  /// Reads binary + text frames for the measurement window, counts ALL received
  /// bytes, parses each TEXT frame as a server [Ndt7Measurement], and returns
  /// the client-side goodput. The window ends when the server closes the stream
  /// or the soft deadline passes; a hard deadline guarantees the read can't hang.
  Future<_StageOutcome> _download(Ndt7Socket socket, String host) async {
    var totalBytes = 0;
    final start = clock();
    final softDeadline = start.add(measurementDuration);

    final elapsed = await downloadTimer(() async {
      final completer = Completer<void>();
      late final StreamSubscription<dynamic> sub;

      void finish() {
        if (!completer.isCompleted) completer.complete();
      }

      sub = socket.messages.listen(
        (message) {
          if (message is List<int>) {
            totalBytes += message.length;
          } else if (message is String) {
            // Text measurement frames are also bytes on the wire; count them
            // toward the honest total, and parse them for TCPInfo/BBRInfo.
            totalBytes += utf8.encode(message).length;
            Ndt7Measurement.tryParse(message);
          }
          if (!clock().isBefore(softDeadline)) finish();
        },
        onError: (Object _) => finish(),
        onDone: finish,
        cancelOnError: true,
      );

      await completer.future
          .timeout(measurementDuration + deadlineSlack, onTimeout: finish);
      await sub.cancel();
    });

    if (totalBytes <= 0) {
      throw const Ndt7Unmeasurable('download received 0 bytes');
    }
    return _StageOutcome(bytes: totalBytes, elapsed: elapsed, serverHost: host);
  }

  /// Runs the upload window against [targets] in order, using the first whose
  /// socket opens. Throws [Ndt7Unmeasurable] when every target's socket fails or
  /// the server never reported a byte count.
  Future<_StageOutcome> _runUpload(List<Ndt7Target> targets) async {
    Object lastError =
        const Ndt7Unmeasurable('no upload target was attempted');
    for (final target in targets) {
      final Ndt7Socket socket;
      try {
        socket = await connector(target.uploadUrl, subprotocol);
      } catch (e) {
        lastError = Ndt7Unmeasurable('upload socket failed to open: $e');
        continue;
      }
      try {
        return await _upload(socket, target.host);
      } on Ndt7Unmeasurable catch (e) {
        lastError = e;
      } finally {
        await socket.close();
      }
    }
    throw lastError is Ndt7Unmeasurable
        ? lastError
        : Ndt7Unmeasurable('$lastError');
  }

  /// Sends binary frames as fast as the socket accepts (bounded by backpressure)
  /// for the measurement window, while listening for the server's TEXT
  /// measurement frames. The authoritative upload rate comes from the LAST
  /// server-reported byte count and elapsed — not the client's send count.
  Future<_StageOutcome> _upload(Ndt7Socket socket, String host) async {
    Ndt7Measurement? lastServerMeasurement;
    final sub = socket.messages.listen(
      (message) {
        if (message is String) {
          final m = Ndt7Measurement.tryParse(message);
          if (m != null && m.hasAppByteCount) lastServerMeasurement = m;
        }
      },
      onError: (Object _) {},
      cancelOnError: false,
    );

    final start = clock();
    final softDeadline = start.add(measurementDuration);
    final hardDeadline = start.add(measurementDuration + deadlineSlack);
    var messageSize = minUploadMessageBytes;
    var sentBytes = 0;
    // Reused zero-filled payload; the NDT7 spec only cares about byte volume,
    // not content. Grown in place as [messageSize] increases.
    var payload = List<int>.filled(messageSize, 0);

    try {
      while (clock().isBefore(softDeadline)) {
        // Fill the send buffer up to the backpressure bound (7× the current
        // message size, per the NDT7 spec), but never queue more than that per
        // event-loop turn — so even a socket that can't report bufferedAmount
        // (dart:io / web) stays memory-bounded. Then yield to let the socket
        // flush and to let server measurement frames arrive.
        final turnBudget = 7 * messageSize;
        var queuedThisTurn = 0;
        while (queuedThisTurn < turnBudget &&
            socket.bufferedAmount + queuedThisTurn < turnBudget &&
            clock().isBefore(softDeadline)) {
          socket.send(payload);
          sentBytes += messageSize;
          queuedThisTurn += messageSize;
        }

        // Grow the frame toward the ceiling once enough has been sent, matching
        // the NDT7 adaptive-message-size scheme.
        if (messageSize < maxUploadMessageBytes &&
            sentBytes >= 16 * messageSize) {
          messageSize =
              (messageSize * 2).clamp(minUploadMessageBytes, maxUploadMessageBytes);
          payload = List<int>.filled(messageSize, 0);
        }

        // Backstop: a socket that never drains can't spin past the hard deadline.
        if (!clock().isBefore(hardDeadline)) break;
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      await sub.cancel();
    }

    final measurement = lastServerMeasurement;
    if (measurement == null || !measurement.hasAppByteCount) {
      throw const Ndt7Unmeasurable(
        'upload server never reported a received-byte count',
      );
    }
    final serverBytes = measurement.appNumBytes!;
    final serverElapsed = measurement.appElapsed;
    if (serverBytes <= 0 || serverElapsed <= Duration.zero) {
      throw const Ndt7Unmeasurable(
        'upload server reported a zero-byte / zero-time measurement',
      );
    }
    return _StageOutcome(
      bytes: serverBytes,
      elapsed: serverElapsed,
      serverHost: host,
    );
  }

  // ----- Default seam implementations (kept off the shared/web-critical path
  // only through the abstractions above; http + web_socket_channel are both
  // web-safe). -----

  static Future<Ndt7LocateResponse> _defaultLocateFetcher(Uri url) async {
    final response = await http.get(url);
    return Ndt7LocateResponse(response.statusCode, response.body);
  }

  static Future<Ndt7Socket> _defaultConnector(
    Uri url,
    String protocol,
  ) async {
    final channel = WebSocketChannel.connect(url, protocols: <String>[protocol]);
    await channel.ready;
    return _WebSocketChannelAdapter(channel);
  }

  static Future<Duration> _defaultElapsedTimer(
    Future<void> Function() body,
  ) async {
    final sw = Stopwatch()..start();
    await body();
    sw.stop();
    return sw.elapsed;
  }
}

/// Performs the Locate API HTTPS GET and returns the raw response. Injectable so
/// server discovery is unit-tested with no network.
typedef Ndt7LocateFetcher = Future<Ndt7LocateResponse> Function(Uri url);

/// Opens a bidirectional message [Ndt7Socket] for a `wss` [url], negotiating the
/// given NDT7 sub[protocol]. Injectable so the protocol logic runs against a
/// fake socket in tests.
typedef Ndt7SocketConnector = Future<Ndt7Socket> Function(
  Uri url,
  String protocol,
);

/// Measures the wall-clock elapsed of a body of work. Injectable so throughput
/// math is deterministic in tests. Mirrors `ThroughputProbe`'s `ElapsedTimer`.
typedef Ndt7ElapsedTimer = Future<Duration> Function(
  Future<void> Function() body,
);

/// The raw Locate API response: HTTP status plus the undecoded body. Kept
/// minimal so the injected fetcher need not depend on any HTTP package's types.
class Ndt7LocateResponse {
  /// HTTP status code of the Locate response.
  final int statusCode;

  /// Undecoded response body (expected to be JSON on success).
  final String body;

  /// Creates a Locate response.
  const Ndt7LocateResponse(this.statusCode, this.body);
}

/// A bidirectional NDT7 message channel: a stream of incoming messages (each a
/// `List<int>` binary frame or a `String` text frame) plus a binary send path.
///
/// This abstraction is the seam that keeps the NDT7 protocol logic free of any
/// concrete WebSocket type, so it is both cross-platform and unit-testable.
abstract class Ndt7Socket {
  /// Incoming messages. Each event is a `List<int>` (binary) or `String` (text).
  Stream<dynamic> get messages;

  /// Enqueues a binary [data] frame for sending.
  void send(List<int> data);

  /// Best-effort count of bytes buffered in the send path but not yet written to
  /// the network. Returns `0` when the platform cannot report it (dart:io / web
  /// channels) — the upload loop stays memory-bounded regardless via its
  /// per-turn budget.
  int get bufferedAmount;

  /// Closes the socket. Idempotent; safe to call more than once.
  Future<void> close();
}

/// Adapts a `web_socket_channel` [WebSocketChannel] to the [Ndt7Socket] seam.
class _WebSocketChannelAdapter implements Ndt7Socket {
  final WebSocketChannel _channel;
  bool _closed = false;

  _WebSocketChannelAdapter(this._channel);

  @override
  Stream<dynamic> get messages => _channel.stream;

  @override
  void send(List<int> data) => _channel.sink.add(data);

  @override
  int get bufferedAmount => 0;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _channel.sink.close();
  }
}

/// A single NDT7 server target discovered via the Locate API, carrying the
/// tokenized secure download/upload WebSocket URLs.
class Ndt7Target {
  /// The M-Lab machine name (or, failing that, the download URL host).
  final String host;

  /// The tokenized `wss` download URL.
  final Uri downloadUrl;

  /// The tokenized `wss` upload URL.
  final Uri uploadUrl;

  /// Creates a target.
  const Ndt7Target({
    required this.host,
    required this.downloadUrl,
    required this.uploadUrl,
  });

  /// Parses one Locate `results[]` [entry] into a target, or returns `null` when
  /// it lacks a usable `wss` download+upload URL pair.
  static Ndt7Target? tryParse(Object? entry) {
    if (entry is! Map) return null;
    final urls = entry['urls'];
    if (urls is! Map) return null;

    final downloadRaw = urls[Ndt7Client.downloadUrlKey];
    final uploadRaw = urls[Ndt7Client.uploadUrlKey];
    if (downloadRaw is! String ||
        uploadRaw is! String ||
        downloadRaw.isEmpty ||
        uploadRaw.isEmpty) {
      return null;
    }

    final Uri downloadUrl;
    final Uri uploadUrl;
    try {
      downloadUrl = Uri.parse(downloadRaw);
      uploadUrl = Uri.parse(uploadRaw);
    } catch (_) {
      return null;
    }

    final machine = entry['machine'];
    final host = (machine is String && machine.isNotEmpty)
        ? machine
        : downloadUrl.host;

    return Ndt7Target(
      host: host,
      downloadUrl: downloadUrl,
      uploadUrl: uploadUrl,
    );
  }
}

/// A parsed NDT7 "measurement" message (the periodic TEXT JSON frame). Carries
/// the application-level byte count / elapsed (authoritative for upload) plus a
/// few TCPInfo/BBRInfo fields worth surfacing.
class Ndt7Measurement {
  /// Application-level bytes counted by the SENDER of these measurements (the
  /// server during upload; the server during download too). `null` when absent.
  final int? appNumBytes;

  /// Application-level elapsed time, in microseconds. `null` when absent.
  final int? appElapsedMicros;

  /// `TCPInfo.BytesReceived`, when present.
  final int? tcpBytesReceived;

  /// `TCPInfo.BytesAcked`, when present.
  final int? tcpBytesAcked;

  /// `"client"` or `"server"` — which side emitted the measurement.
  final String? origin;

  /// `"download"` or `"upload"`.
  final String? test;

  /// Creates a measurement.
  const Ndt7Measurement({
    this.appNumBytes,
    this.appElapsedMicros,
    this.tcpBytesReceived,
    this.tcpBytesAcked,
    this.origin,
    this.test,
  });

  /// Whether this measurement carries a usable application-level byte count and
  /// elapsed (the authoritative pair for the upload rate).
  bool get hasAppByteCount =>
      appNumBytes != null &&
      appNumBytes! > 0 &&
      appElapsedMicros != null &&
      appElapsedMicros! > 0;

  /// The application-level elapsed as a [Duration] (zero when absent).
  Duration get appElapsed => Duration(microseconds: appElapsedMicros ?? 0);

  /// Parses a TEXT measurement frame. Returns `null` when [text] is not a JSON
  /// object (a malformed frame must never abort a measurement).
  static Ndt7Measurement? tryParse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    final appInfo = decoded['AppInfo'];
    final tcpInfo = decoded['TCPInfo'];

    return Ndt7Measurement(
      appNumBytes: _asInt(appInfo is Map ? appInfo['NumBytes'] : null),
      appElapsedMicros:
          _asInt(appInfo is Map ? appInfo['ElapsedTime'] : null),
      tcpBytesReceived:
          _asInt(tcpInfo is Map ? tcpInfo['BytesReceived'] : null),
      tcpBytesAcked: _asInt(tcpInfo is Map ? tcpInfo['BytesAcked'] : null),
      origin: decoded['Origin'] is String ? decoded['Origin'] as String : null,
      test: decoded['Test'] is String ? decoded['Test'] as String : null,
    );
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}

/// The combined result of a full NDT7 measurement.
class Ndt7Result {
  /// Download rate, megabits per second (client-side goodput).
  final double downloadMbps;

  /// Upload rate, megabits per second (server-reported goodput). Null when the
  /// upload stage was skipped (the default) or could not be measured — the
  /// download stands on its own; never a fabricated 0.
  final double? uploadMbps;

  /// Total bytes received during the download window.
  final int downloadBytes;

  /// Bytes the SERVER reported receiving during the upload window. Null when
  /// upload was skipped or unmeasurable.
  final int? uploadBytes;

  /// Wall-clock elapsed of the download window.
  final Duration elapsedDownload;

  /// Server-reported elapsed of the upload window. Null when upload was skipped
  /// or unmeasurable.
  final Duration? elapsedUpload;

  /// The M-Lab server the measurement ran against.
  final String serverHost;

  /// Creates a result. Upload fields are optional — omitted/null when the upload
  /// stage did not run or could not be measured.
  const Ndt7Result({
    required this.downloadMbps,
    required this.downloadBytes,
    required this.elapsedDownload,
    required this.serverHost,
    this.uploadMbps,
    this.uploadBytes,
    this.elapsedUpload,
  });

  @override
  String toString() =>
      'Ndt7Result(down ${downloadMbps.toStringAsFixed(1)}Mbps, '
      'up ${uploadMbps == null ? "n/a" : "${uploadMbps!.toStringAsFixed(1)}Mbps"}, '
      'server $serverHost)';
}

/// Thrown when an NDT7 measurement cannot produce a usable number — a socket
/// error, a zero-byte transfer, or a stage that never reported. Surfaced so the
/// caller reports an honest "couldn't measure" instead of a fabricated `0 Mbps`
/// (mirrors `ThroughputUnmeasurable`; see GL-005 / GL-008).
class Ndt7Unmeasurable implements Exception {
  /// Human-readable reason the measurement could not be produced.
  final String reason;

  /// Creates the exception with a [reason].
  const Ndt7Unmeasurable(this.reason);

  @override
  String toString() => 'Ndt7Unmeasurable: $reason';
}

/// Thrown when the Locate API yields no usable server — an HTTP error, a
/// malformed body, an API `error`, or an empty `results[]`. A specific
/// [Ndt7Unmeasurable] subtype so callers can distinguish "no server to test
/// against" from "the test itself failed".
class Ndt7NoServerAvailable extends Ndt7Unmeasurable {
  /// Creates the exception with a [reason].
  const Ndt7NoServerAvailable(super.reason);

  @override
  String toString() => 'Ndt7NoServerAvailable: $reason';
}

/// Internal per-stage outcome (bytes + elapsed + which server answered).
class _StageOutcome {
  final int bytes;
  final Duration elapsed;
  final String serverHost;

  const _StageOutcome({
    required this.bytes,
    required this.elapsed,
    required this.serverHost,
  });
}
