// PublicIpService — the ONE shared "what is my public IP?" fetcher.
//
// WHY A SHARED HELPER: the Interface Info tool shows the device's public IP
// beneath its local IPv4, and the IP Geolocation tool needs the same datum when
// the user asks to locate "my IP". Rather than duplicate the HTTP call, both
// route through this single source.
//
// TRANSPORT: a plain-text HTTPS GET via dart:io HttpClient — the same primitive
// JsonHttpClient uses. NOT the `http` package (the project deliberately has no
// `http` dependency). Because dart:io does not exist on web, anything built on
// this is native-only; the callers already gate web to their download-the-app
// fallback.
//
// HTTPS ONLY (GL-008): cleartext http:// trips iOS App Transport Security, so
// every endpoint here is https and the helper refuses any non-https URL.
//
// KEYLESS (GL-008): ipify and icanhazip are free, no-account, no-key, plain-text
// "echo my IP" endpoints. ipify is primary; icanhazip is the fallback when ipify
// is unreachable. Both return the caller's public IP as a bare string (IPv4 or
// IPv6), which we trim and validate before returning.
//
// HONESTY (GL-005): on any failure (no internet, blocked, both endpoints down)
// the result is null and the caller shows an explicit "Unavailable" state —
// never a fabricated or stale address.

import 'dart:async';
import 'dart:io';

/// Fetches the device's public IP as a bare string. Injectable [fetcher] seam so
/// unit tests script responses without touching the network.
class PublicIpService {
  PublicIpService({PlainTextFetcher? fetcher})
      : _fetch = fetcher ?? _runFetch;

  final PlainTextFetcher _fetch;

  /// ipify primary, icanhazip fallback. Both echo the caller's public IP as a
  /// bare plain-text string over HTTPS, keyless.
  static const List<String> endpoints = <String>[
    'https://api.ipify.org',
    'https://icanhazip.com',
  ];

  /// Public APIs ask callers to identify themselves; a stable UA keeps us off
  /// anonymous-client rate buckets and mirrors [JsonHttpClient].
  static const String userAgent =
      'WLANProsToolbox/1.0 (+https://wlanpros.com)';

  /// Returns the device's public IP (IPv4 or IPv6), or null when neither
  /// endpoint could be reached / parsed. Never throws.
  Future<String?> fetch({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    for (final String endpoint in endpoints) {
      try {
        final String body = await _fetch(endpoint, timeout);
        final String? ip = _parse(body);
        if (ip != null) return ip;
      } catch (_) {
        // Try the next endpoint; only a total failure returns null.
      }
    }
    return null;
  }

  /// Extracts a bare IPv4 or IPv6 address from a plain-text body, or null when
  /// the body is empty or not a recognizable address. Exposed for unit tests.
  static String? _parse(String body) {
    final String s = body.trim();
    if (s.isEmpty) return null;
    // ipify/icanhazip echo a single bare address. Take the first non-empty line
    // defensively in case a fallback ever appends a trailing newline or note.
    final String first = s.split(RegExp(r'\s+')).first.trim();
    if (first.isEmpty) return null;
    if (_isIpv4(first) || _isIpv6(first)) return first;
    return null;
  }

  /// Test hook for [_parse].
  static String? parseForTest(String body) => _parse(body);

  static bool _isIpv4(String q) {
    final List<String> parts = q.split('.');
    if (parts.length != 4) return false;
    for (final String p in parts) {
      if (p.isEmpty || p.length > 3) return false;
      final int? n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  static bool _isIpv6(String q) {
    // Must contain a colon and only hex/colon characters (optional zone id).
    if (!q.contains(':')) return false;
    return RegExp(r'^[0-9a-fA-F:]+(%[0-9a-zA-Z]+)?$').hasMatch(q);
  }

  /// Default plain-text HTTPS GET. Refuses any non-https URL up front (ATS).
  static Future<String> _runFetch(String rawUrl, Duration timeout) async {
    final Uri? uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('Public IP endpoint must be a valid https URL.');
    }
    final HttpClient client = HttpClient();
    client.connectionTimeout = timeout;
    try {
      final HttpClientRequest req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, userAgent);
      req.headers.set(HttpHeaders.acceptHeader, 'text/plain');
      final HttpClientResponse resp = await req.close().timeout(timeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        await resp.drain<void>();
        throw HttpException('Public IP lookup returned HTTP ${resp.statusCode}.');
      }
      // The body is a few bytes; read it bounded for safety.
      final List<int> bytes = <int>[];
      await for (final List<int> chunk in resp.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > 4096) break; // a public IP is < 50 bytes; guard runaway
      }
      return String.fromCharCodes(bytes);
    } finally {
      client.close(force: false);
    }
  }
}

/// The injectable network seam: issue one GET, return the bare body text.
typedef PlainTextFetcher = Future<String> Function(String url, Duration timeout);
