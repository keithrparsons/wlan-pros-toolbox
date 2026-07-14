// HttpHeaderService — issue a HEAD or GET request, follow and RECORD the
// redirect chain hop-by-hop, and return the final status line plus all
// response headers.
//
// WHY MANUAL REDIRECT FOLLOWING (deliberate, documented decision):
//
// Dart's `HttpClient` will follow redirects internally when
// `followRedirects = true`, but it does NOT hand back the intermediate
// responses — you only see the final one. The entire point of this tool is to
// SHOW each hop (status + Location). So we set `followRedirects = false` and
// follow the chain ourselves, recording one [HttpHop] per response, until we
// hit a non-redirect status or the [maxRedirects] cap. This gives the user the
// full 301→302→200 story instead of just the destination.
//
// WHY HEAD→GET FALLBACK: HEAD is the default because it returns headers without
// a body — cheaper and exactly what a header inspector wants. But some servers
// reject HEAD (405 Method Not Allowed) or mis-handle it. When HEAD yields 405
// (and the caller did not explicitly ask for HEAD-only), we transparently retry
// the SAME url with GET so the user still gets headers. The UI notes when this
// fallback fired.
//
// Platform note (iOS App Transport Security): cleartext `http://` requests are
// blocked by ATS on iOS unless an exception is declared. We do NOT add a
// blanket ATS exception (that weakens every request in the app). On iOS an
// http:// target therefore fails at the socket layer; we surface that as a
// clear, specific error rather than a generic failure.
//
// Web safety: imports `dart:io` (HttpClient). Gated behind
// `NetworkSupport.httpHeadersSupported` at the UI layer; never reached on web.

import 'dart:async';
import 'dart:io';

/// HTTP method the inspector issues.
enum HttpMethod { head, get }

extension HttpMethodLabel on HttpMethod {
  String get label => this == HttpMethod.head ? 'HEAD' : 'GET';
}

/// One header line, normalized for display. Multi-value headers are joined
/// with ", " by the HTTP stack; we keep them as a single readable string.
class HeaderEntry {
  const HeaderEntry({required this.name, required this.value});

  /// Header name in its original-ish casing (lower-cased by dart:io, then
  /// title-cased here for readability — e.g. "content-type" → "Content-Type").
  final String name;
  final String value;
}

/// One response in the chain: a hop. A redirect hop carries a [location]; the
/// final hop does not.
class HttpHop {
  const HttpHop({
    required this.method,
    required this.url,
    required this.statusCode,
    required this.reasonPhrase,
    required this.location,
    required this.headers,
    required this.elapsedMs,
  });

  /// Method used for THIS hop (matters when HEAD fell back to GET).
  final HttpMethod method;
  final String url;
  final int statusCode;
  final String reasonPhrase;

  /// The `Location` header value for a redirect hop, else null.
  final String? location;

  /// All response headers for this hop.
  final List<HeaderEntry> headers;

  /// Time this single request/response took, in milliseconds.
  final int elapsedMs;

  bool get isRedirect => statusCode >= 300 && statusCode < 400;

  /// "200 OK" style status line.
  String get statusLine => '$statusCode $reasonPhrase'.trim();
}

/// Outcome of an inspection. Success carries the ordered hop chain (final hop
/// last). A connection/protocol problem is a failure with a precise message.
class HttpHeaderResult {
  const HttpHeaderResult._({
    required this.requestedUrl,
    required this.hops,
    this.headFellBackToGet = false,
    this.redirectLimitHit = false,
    this.errorMessage,
  });

  factory HttpHeaderResult.success({
    required String requestedUrl,
    required List<HttpHop> hops,
    required bool headFellBackToGet,
    required bool redirectLimitHit,
  }) =>
      HttpHeaderResult._(
        requestedUrl: requestedUrl,
        hops: hops,
        headFellBackToGet: headFellBackToGet,
        redirectLimitHit: redirectLimitHit,
      );

  factory HttpHeaderResult.failure({
    required String requestedUrl,
    required String message,
  }) =>
      HttpHeaderResult._(
        requestedUrl: requestedUrl,
        hops: const <HttpHop>[],
        errorMessage: message,
      );

  final String requestedUrl;

  /// Ordered redirect chain; the last entry is the final (non-redirect)
  /// response. Empty only on failure.
  final List<HttpHop> hops;

  /// True when an initial HEAD got a 405 and we retried with GET.
  final bool headFellBackToGet;

  /// True when we stopped because the redirect chain exceeded the cap.
  final bool redirectLimitHit;

  final String? errorMessage;

  bool get isError => errorMessage != null;

  /// The terminal (non-redirect) hop, or null on failure / empty.
  HttpHop? get finalHop => hops.isEmpty ? null : hops.last;

  /// Total wall time across all hops, in milliseconds.
  int get totalMs => hops.fold<int>(0, (int sum, HttpHop h) => sum + h.elapsedMs);
}

/// Issues the request(s) and assembles the chain. The [opener] seam abstracts
/// the actual network call so [assembleChain] / the parsing logic can be
/// exercised in unit tests without a live server.
class HttpHeaderService {
  HttpHeaderService({HttpProbe? opener}) : _open = opener ?? _defaultOpen;

  final HttpProbe _open;

  /// Cap on redirects we will follow before giving up — protects against
  /// redirect loops and absurd chains.
  static const int defaultMaxRedirects = 10;

  static Future<RawHttpResponse> _defaultOpen(
    HttpMethod method,
    Uri url,
    Duration timeout,
  ) async {
    final HttpClient client = HttpClient();
    client.connectionTimeout = timeout;
    // We follow redirects ourselves so we can show each hop.
    try {
      final HttpClientRequest req = method == HttpMethod.head
          ? await client.headUrl(url)
          : await client.getUrl(url);
      req.followRedirects = false;
      final HttpClientResponse resp = await req.close().timeout(timeout);
      // Drain the body so the connection can be reused/closed cleanly; we only
      // care about headers/status, not content.
      await resp.drain<void>();

      final List<HeaderEntry> headers = <HeaderEntry>[];
      resp.headers.forEach((String name, List<String> values) {
        headers.add(
          HeaderEntry(name: _titleCase(name), value: values.join(', ')),
        );
      });
      headers.sort((HeaderEntry a, HeaderEntry b) => a.name.compareTo(b.name));

      return RawHttpResponse(
        statusCode: resp.statusCode,
        reasonPhrase: resp.reasonPhrase,
        location: resp.headers.value(HttpHeaders.locationHeader),
        headers: headers,
      );
    } finally {
      client.close(force: false);
    }
  }

  /// Inspect [rawUrl], following redirects and recording each hop.
  ///
  /// - [method] HEAD (default) or GET.
  /// - When HEAD is the default and a hop returns 405, we retry that hop with
  ///   GET ([headFellBackToGet] is set on the result).
  /// - [timeout] bounds each individual request.
  Future<HttpHeaderResult> inspect({
    required String rawUrl,
    HttpMethod method = HttpMethod.head,
    Duration timeout = const Duration(seconds: 10),
    int maxRedirects = defaultMaxRedirects,
  }) async {
    final Uri? start = _parseUrl(rawUrl);
    if (start == null) {
      return HttpHeaderResult.failure(
        requestedUrl: rawUrl.trim(),
        message: 'Enter a valid http:// or https:// URL.',
      );
    }

    final List<HttpHop> hops = <HttpHop>[];
    bool fellBack = false;
    Uri current = start;
    HttpMethod currentMethod = method;

    try {
      for (int i = 0; i <= maxRedirects; i++) {
        final Stopwatch sw = Stopwatch()..start();
        RawHttpResponse raw = await _open(currentMethod, current, timeout);
        sw.stop();

        // HEAD rejected → transparently retry this hop with GET (only when the
        // caller did not explicitly demand GET already, and only on 405).
        if (raw.statusCode == 405 &&
            currentMethod == HttpMethod.head &&
            method == HttpMethod.head) {
          fellBack = true;
          currentMethod = HttpMethod.get;
          final Stopwatch sw2 = Stopwatch()..start();
          raw = await _open(HttpMethod.get, current, timeout);
          sw2.stop();
          hops.add(_hop(HttpMethod.get, current, raw, sw2.elapsedMilliseconds));
        } else {
          hops.add(
            _hop(currentMethod, current, raw, sw.elapsedMilliseconds),
          );
        }

        final HttpHop last = hops.last;
        if (!last.isRedirect || last.location == null) {
          return HttpHeaderResult.success(
            requestedUrl: start.toString(),
            hops: hops,
            headFellBackToGet: fellBack,
            redirectLimitHit: false,
          );
        }

        // Resolve the next hop against the current URL (handles relative
        // Location values per RFC 7231 §7.1.2).
        final Uri? next = _resolveLocation(current, last.location!);
        if (next == null) {
          return HttpHeaderResult.success(
            requestedUrl: start.toString(),
            hops: hops,
            headFellBackToGet: fellBack,
            redirectLimitHit: false,
          );
        }
        current = next;
        // After a redirect, restore the user's chosen method for the next hop
        // (a one-off HEAD→GET fallback should not stick for the whole chain).
        currentMethod = method;
      }

      // Exhausted the redirect cap.
      return HttpHeaderResult.success(
        requestedUrl: start.toString(),
        hops: hops,
        headFellBackToGet: fellBack,
        redirectLimitHit: true,
      );
    } on SocketException catch (e) {
      return HttpHeaderResult.failure(
        requestedUrl: start.toString(),
        message: _socketMessage(start, e),
      );
    } on TimeoutException {
      return HttpHeaderResult.failure(
        requestedUrl: start.toString(),
        message: 'Request timed out after ${timeout.inSeconds}s.',
      );
    } on HandshakeException catch (e) {
      return HttpHeaderResult.failure(
        requestedUrl: start.toString(),
        message: 'TLS handshake failed: ${_short(e.message)}',
      );
    } on Object catch (e) {
      return HttpHeaderResult.failure(
        requestedUrl: start.toString(),
        message: _short(e.toString()),
      );
    }
  }

  static HttpHop _hop(
    HttpMethod method,
    Uri url,
    RawHttpResponse raw,
    int elapsedMs,
  ) {
    return HttpHop(
      method: method,
      url: url.toString(),
      statusCode: raw.statusCode,
      reasonPhrase: raw.reasonPhrase,
      location: (raw.statusCode >= 300 && raw.statusCode < 400)
          ? raw.location
          : null,
      headers: raw.headers,
      elapsedMs: elapsedMs,
    );
  }

  /// Parse and validate a user-entered URL. Returns null when it is not an
  /// absolute http/https URL with a host. Exposed for tests.
  static Uri? _parseUrl(String raw) {
    String s = raw.trim();
    if (s.isEmpty) return null;
    // If no scheme, assume https:// so a bare "example.com" works.
    if (!s.contains('://')) s = 'https://$s';
    final Uri? uri = Uri.tryParse(s);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return uri;
  }

  /// Resolve a (possibly relative) Location against the current URL. Exposed
  /// for tests — relative-redirect handling is regression-prone.
  static Uri? _resolveLocation(Uri base, String location) {
    final String loc = location.trim();
    if (loc.isEmpty) return null;
    try {
      final Uri resolved = base.resolve(loc);
      if (resolved.scheme != 'http' && resolved.scheme != 'https') return null;
      if (resolved.host.isEmpty) return null;
      return resolved;
    } on Object {
      return null;
    }
  }

  static String _titleCase(String headerName) {
    return headerName
        .split('-')
        .map((String p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}')
        .join('-');
  }

  static String _socketMessage(Uri url, SocketException e) {
    if (url.scheme == 'http') {
      return 'Could not connect over http://. On iOS, cleartext HTTP is '
          'blocked by App Transport Security. Try the https:// URL. '
          '(${_short(e.message)})';
    }
    return 'Could not connect: ${_short(e.message)}.';
  }

  static String _short(String s) {
    final String t = s.trim();
    return t.length > 160 ? '${t.substring(0, 160)}…' : t;
  }
}

/// The minimal response shape the [HttpProbe] seam returns, decoupled from
/// dart:io so tests can fabricate responses.
class RawHttpResponse {
  const RawHttpResponse({
    required this.statusCode,
    required this.reasonPhrase,
    required this.location,
    required this.headers,
  });

  final int statusCode;
  final String reasonPhrase;
  final String? location;
  final List<HeaderEntry> headers;
}

/// The injectable network seam: issue one request, return one response.
typedef HttpProbe = Future<RawHttpResponse> Function(
  HttpMethod method,
  Uri url,
  Duration timeout,
);
