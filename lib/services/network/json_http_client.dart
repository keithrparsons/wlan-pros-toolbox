// JsonHttpClient — a thin, testable HTTPS-GET-returning-JSON helper shared by
// the API-backed tools (BGP/ASN Lookup, IP Geolocation).
//
// WHY A SHARED HELPER: both API tools need the same shape — an HTTPS GET with a
// connect timeout, a User-Agent the public APIs ask for, a bounded response
// read, JSON decode, and a precise error taxonomy (timeout / rate-limit /
// transport / bad-JSON). Centralizing it keeps the two services thin and gives
// the unit tests a single seam ([JsonFetcher]) to script responses against
// without touching the network.
//
// TRANSPORT: dart:io HttpClient (same primitive http_header_service uses), NOT
// the `http` package — the project deliberately has no `http` dependency and
// the dart:io client already carries the connect-timeout + ATS idioms. Because
// dart:io does not exist on web, anything built on this helper is native-only;
// the API tools gate to NetworkUnavailableView on web rather than ship a
// silently-CORS-failing browser tool.
//
// HTTPS ONLY: [get] rejects any non-https URL up front. Cleartext http:// trips
// iOS App Transport Security; both API endpoints we target are https, and we
// refuse to fetch over http so an accidental http URL fails loud, not silent.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Why a JSON fetch failed, so a tool can render a precise, non-apologetic
/// state instead of a generic error.
enum JsonHttpErrorKind {
  /// Bad/empty URL, or a non-https scheme (refused before any I/O).
  badUrl,

  /// The connection or read exceeded the timeout.
  timeout,

  /// The API answered with HTTP 429 (or otherwise signalled rate limiting).
  rateLimited,

  /// The API answered with a non-2xx, non-429 status.
  httpStatus,

  /// Socket/DNS/TLS-level failure reaching the host.
  transport,

  /// 2xx body did not parse as JSON (or was not a JSON object).
  badJson,
}

/// A typed failure carrying a user-facing [message] and the [kind] so the UI
/// can branch (e.g. offer a retry on [timeout]/[rateLimited]).
class JsonHttpException implements Exception {
  const JsonHttpException(this.kind, this.message, {this.statusCode});

  final JsonHttpErrorKind kind;
  final String message;

  /// HTTP status when [kind] is [JsonHttpErrorKind.httpStatus] or
  /// [JsonHttpErrorKind.rateLimited], else null.
  final int? statusCode;

  @override
  String toString() => 'JsonHttpException($kind, $message)';
}

/// The injectable network seam: issue one GET, return the decoded JSON map.
/// Throwing a [JsonHttpException] lets tests script every error branch.
typedef JsonFetcher = Future<Map<String, dynamic>> Function(
  Uri url,
  Duration timeout,
);

/// HTTPS-GET → JSON map helper with a precise error taxonomy.
class JsonHttpClient {
  JsonHttpClient({JsonFetcher? fetcher, String? userAgent})
      : userAgent = userAgent ?? defaultUserAgent,
        _fetch = fetcher ??
            ((Uri url, Duration timeout) =>
                _runFetch(url, timeout, userAgent ?? defaultUserAgent, maxBodyBytes));

  final JsonFetcher _fetch;

  /// Public APIs (RIPEstat, ipinfo.io, geojs.io) ask callers to identify
  /// themselves; a
  /// stable UA keeps us off anonymous-client rate buckets.
  final String userAgent;

  static const String defaultUserAgent =
      'WLANProsToolbox/1.0 (+https://wlanpros.com)';

  /// Cap on the response body we will buffer — these JSON payloads are a few
  /// KB; this guards against a hostile/oversized response.
  static const int maxBodyBytes = 1 << 20; // 1 MiB

  /// Fetch [rawUrl] as JSON. Throws [JsonHttpException] on any failure.
  Future<Map<String, dynamic>> getJson(
    String rawUrl, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final Uri? uri = parseHttpsUrl(rawUrl);
    if (uri == null) {
      throw const JsonHttpException(
        JsonHttpErrorKind.badUrl,
        'Internal error: a tool requested a non-HTTPS URL.',
      );
    }
    return _fetch(uri, timeout);
  }

  /// Parse and require an https URL with a host. Exposed for tests.
  static Uri? parseHttpsUrl(String raw) {
    final String s = raw.trim();
    if (s.isEmpty) return null;
    final Uri? uri = Uri.tryParse(s);
    if (uri == null) return null;
    if (uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return uri;
  }

  static Future<Map<String, dynamic>> _runFetch(
    Uri url,
    Duration timeout,
    String userAgent,
    int maxBytes,
  ) async {
    final HttpClient client = HttpClient();
    client.connectionTimeout = timeout;
    try {
      final HttpClientRequest req = await client.getUrl(url);
      req.headers.set(HttpHeaders.userAgentHeader, userAgent);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final HttpClientResponse resp = await req.close().timeout(timeout);

      final int status = resp.statusCode;
      if (status == 429) {
        await resp.drain<void>();
        throw const JsonHttpException(
          JsonHttpErrorKind.rateLimited,
          'The lookup API is rate-limiting requests right now. '
              'Wait a minute and try again.',
          statusCode: 429,
        );
      }
      if (status < 200 || status >= 300) {
        await resp.drain<void>();
        throw JsonHttpException(
          JsonHttpErrorKind.httpStatus,
          'The lookup API returned HTTP $status.',
          statusCode: status,
        );
      }

      final String body = await _readBounded(resp, maxBytes, timeout);
      final Object? decoded;
      try {
        decoded = jsonDecode(body);
      } on FormatException {
        throw const JsonHttpException(
          JsonHttpErrorKind.badJson,
          'The lookup API returned a response that was not valid JSON.',
        );
      }
      if (decoded is! Map<String, dynamic>) {
        throw const JsonHttpException(
          JsonHttpErrorKind.badJson,
          'The lookup API returned an unexpected JSON shape.',
        );
      }
      return decoded;
    } on JsonHttpException {
      rethrow;
    } on TimeoutException {
      throw JsonHttpException(
        JsonHttpErrorKind.timeout,
        'The lookup timed out after ${timeout.inSeconds}s.',
      );
    } on SocketException catch (e) {
      throw JsonHttpException(
        JsonHttpErrorKind.transport,
        'Could not reach the lookup API: ${_short(e.message)}.',
      );
    } on HandshakeException catch (e) {
      throw JsonHttpException(
        JsonHttpErrorKind.transport,
        'TLS handshake with the lookup API failed: ${_short(e.message)}.',
      );
    } on Object catch (e) {
      throw JsonHttpException(
        JsonHttpErrorKind.transport,
        _short(e.toString()),
      );
    } finally {
      client.close(force: false);
    }
  }

  static Future<String> _readBounded(
    HttpClientResponse resp,
    int maxBytes,
    Duration timeout,
  ) async {
    final List<int> bytes = <int>[];
    await for (final List<int> chunk in resp.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) {
        throw const JsonHttpException(
          JsonHttpErrorKind.badJson,
          'The lookup API response was unexpectedly large.',
        );
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _short(String s) {
    final String t = s.trim();
    return t.length > 160 ? '${t.substring(0, 160)}…' : t;
  }
}
