// WlanPiSession — the cross-cutting wrapper around the WLAN Pi REST API.
//
// EXPERIMENTAL / COMPANION MODE. This is the thin service that owns the
// concerns a generated transport client would not: token lifecycle, HMAC
// signing, rate-limit/backoff, version detection, and the connection state
// machine. It is built against the PUBLIC wlanpi-core source (BSD-3) routes,
// confirmed 2026-06-05:
//
//   POST   /api/v1/auth/token            -> Token {access_token, token_type}
//   GET    /api/v1/system/device/info    -> DeviceInfo
//   GET    /api/v1/system/device/stats   -> DeviceStats
//   GET    /api/v1/network/info/         -> NetworkInfo
//   POST   /api/v1/profiler/start        -> {success: bool}
//   GET    /api/v1/profiler/status       -> Status
//   POST   /api/v1/profiler/stop         -> Stop
//
// ════════════════════════════════════════════════════════════════════════════
// STUBBED PENDING MONDAY'S ON-DEVICE SPIKE — the real handshake is NOT here yet.
// ════════════════════════════════════════════════════════════════════════════
// Two things genuinely cannot be confirmed without a running device, and are
// therefore deliberately STUBBED below (each throws/returns a clearly-labeled
// `WlanPiNotYetWired` until Monday):
//
//   1. THE TOKEN HANDSHAKE. `POST /auth/token` takes `{"device_id": "..."}` and
//      returns `{"access_token", "token_type": "bearer"}` (CONFIRMED from
//      schemas/auth/auth.py). What is NOT confirmed: what an EXTERNAL client
//      presents to be ISSUED that token in the first place. The route depends on
//      `verify_auth_wrapper`, and core/auth.py shows external requests require a
//      JWT bearer — i.e. there is a bootstrapping/pairing step (a shared secret,
//      a key shown in the front-panel menu, or a `signing_key` exchange via
//      `POST /auth/signing_key`, which is itself HMAC-gated). The exact
//      bootstrap credential is the #1 thing Monday must capture.
//
//   2. THE HMAC SCHEME — confirmed in shape, unconfirmed in application to
//      EXTERNAL calls. From core/auth.py the signature is:
//        header:    X-Request-Signature
//        algorithm: HMAC-SHA256, hex digest
//        canonical: "{METHOD}\n{PATH}\n{QUERY_STRING}\n{BODY}"
//        compare:   hmac.compare_digest (constant-time)
//      core/auth.py ALSO states: OTG requests bypass auth; localhost uses HMAC;
//      EXTERNAL requests require a valid JWT bearer. So an external LAN client
//      likely authenticates with the BEARER token alone and HMAC is the
//      localhost/internal path — BUT the `signing_key` issuance endpoints are
//      HMAC-gated, so the bootstrap may still require it. Monday confirms which
//      path an external client actually takes. The HMAC computation is
//      IMPLEMENTED below (it matches the documented canonical form) but is NOT
//      invoked on requests until the spike says it is needed.
//
// SECURITY: tokens + secrets are held in memory only for the session. They are
// NEVER logged, NEVER echoed, and NEVER written to a session-log. If persistence
// is ever added it goes to the OS secure store (flutter_secure_storage /
// Keychain), never SharedPreferences or a plist. Every debug surface masks them.

import 'dart:async';
import 'dart:convert';

import '../../data/wlanpi/wlanpi_connection_state.dart';
import '../../data/wlanpi/wlanpi_models.dart';

/// Thrown by the parts of the session that are STUBBED until Monday's spike.
/// The UI renders this as the friendly "auth-needed / not yet wired" state, not
/// a crash. Carries no secret material.
class WlanPiNotYetWired implements Exception {
  const WlanPiNotYetWired(this.what);

  /// Which capability is not wired yet (for the friendly screen + the dev TODO).
  final String what;

  @override
  String toString() => 'WlanPiNotYetWired($what)';
}

/// Why a session/transport call failed — mirrors the JsonHttpClient taxonomy so
/// the UI can branch (retry on timeout/rateLimited, re-auth on unauthorized).
enum WlanPiErrorKind {
  badUrl,
  timeout,
  rateLimited,
  unauthorized,
  hmacMismatch,
  httpStatus,
  transport,
  badJson,
  unsupportedVersion,
  notYetWired,
}

/// A typed failure with a user-facing message and the kind, never a token dump.
class WlanPiException implements Exception {
  const WlanPiException(this.kind, this.message, {this.statusCode, this.retryAfter});

  final WlanPiErrorKind kind;
  final String message;
  final int? statusCode;

  /// Parsed from a 429 `Retry-After` header when present (design spec §2.3).
  final Duration? retryAfter;

  @override
  String toString() => 'WlanPiException($kind, $message)';
}

/// The minimum supported wlanpi-core / OS floor. 2.x (NEO2) has no core API;
/// the companion mode targets OS 3.x. The exact floor is confirmed at the spike.
class WlanPiSupport {
  const WlanPiSupport._();

  /// Major OS version floor. Below this, the mode shows the wrongVersion screen.
  static const int minOsMajor = 3;
}

/// The injectable transport seam so tests can script responses without a device
/// or network. Mirrors the `JsonFetcher` typedef pattern used elsewhere in the
/// app. Returns the decoded JSON map (or list-wrapped) and the response headers
/// so the session can read `Retry-After`.
typedef WlanPiTransport = Future<WlanPiHttpResponse> Function(
  WlanPiHttpRequest request,
);

/// A transport-level request the session hands to the [WlanPiTransport].
class WlanPiHttpRequest {
  const WlanPiHttpRequest({
    required this.method,
    required this.url,
    this.headers = const <String, String>{},
    this.body,
    this.timeout = const Duration(seconds: 12),
  });

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String? body;
  final Duration timeout;
}

/// A transport-level response handed back to the session.
class WlanPiHttpResponse {
  const WlanPiHttpResponse({
    required this.statusCode,
    required this.body,
    this.headers = const <String, String>{},
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;

  Map<String, dynamic> get json {
    final Object? decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const WlanPiException(
      WlanPiErrorKind.badJson,
      'The WLAN Pi returned an unexpected JSON shape.',
    );
  }
}

/// The session wrapper. Owns the token + HMAC + backoff + version gate around
/// the WLAN Pi REST API for one selected device.
class WlanPiSession {
  WlanPiSession({
    required this.candidate,
    WlanPiTransport? transport,
  }) : _transport = transport ?? _unwiredTransport;

  /// The device this session talks to (carries the `/api/v1` base URL).
  final WlanPiCandidate candidate;

  final WlanPiTransport _transport;

  // Token held in memory ONLY, for the session. Never logged, never persisted
  // here. Masked everywhere it could surface.
  WlanPiToken? _token;

  /// Whether an authenticated session currently exists.
  bool get isAuthenticated => _token != null;

  /// A masked view of the token state for any debug/UI surface. NEVER returns
  /// the token itself.
  String get maskedTokenState =>
      _token == null ? '<no token>' : '<bearer ••••${_safeTail(_token!.accessToken)}>';

  // ──────────────────────────────────────────────────────────────────────────
  // VERSION / FEATURE DETECTION (design spec §1.1, §2.5)
  // ──────────────────────────────────────────────────────────────────────────

  /// Validate the candidate by reading `/openapi.json`, confirm it is a
  /// wlanpi-core instance, and read its version to drive the version gate.
  ///
  /// STUBBED: the real fetch + spec parse is wired Monday once we have a device
  /// to read a real `/openapi.json` from. The PARSE shape is implemented in
  /// [parseOpenApiVersion] and unit-tested; only the live fetch is stubbed.
  Future<String> detectCoreVersion() async {
    throw const WlanPiNotYetWired('openapi.json version detection (live fetch)');
  }

  /// Parse the OS/core major version out of an OpenAPI `info` block. PURE +
  /// TESTED — this is the non-stubbed half of version detection. Accepts the
  /// `info.version` string FastAPI emits (e.g. "3.2.2") and returns the major.
  static int? parseOpenApiVersion(Map<String, dynamic> openApi) {
    final Object? info = openApi['info'];
    if (info is! Map) return null;
    final Object? version = info['version'];
    if (version == null) return null;
    final String s = version.toString();
    final Match? m = RegExp(r'(\d+)').firstMatch(s);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  /// Whether a parsed major version meets the supported floor.
  static bool isVersionSupported(int? major) =>
      major != null && major >= WlanPiSupport.minOsMajor;

  // ──────────────────────────────────────────────────────────────────────────
  // TOKEN LIFECYCLE (design spec §1.2, §2.3) — STUBBED pending Monday
  // ──────────────────────────────────────────────────────────────────────────

  /// Acquire a session token via `POST /api/v1/auth/token`.
  ///
  /// The REQUEST/RESPONSE shapes are confirmed:
  ///   request : `{"device_id": "<this client's id>"}`
  ///   response: `{"access_token": "...", "token_type": "bearer"}`
  ///
  /// STUBBED: what an EXTERNAL client presents to be ISSUED that token (the
  /// bootstrap credential / pairing) is unknown until Monday. We refuse to
  /// invent it. Calling this throws [WlanPiNotYetWired] so the UI shows the
  /// honest "auth handshake pending on-device spike" state.
  Future<void> authenticate({required String deviceId}) async {
    // The request body the device expects is already correct and ready:
    //   final body = jsonEncode(WlanPiTokenRequest(deviceId: deviceId).toJson());
    // The missing piece is the bootstrap credential the device requires to
    // ISSUE the token to an external client. Do NOT fabricate it.
    throw const WlanPiNotYetWired(
      'auth/token external-client bootstrap credential (the #1 Monday unknown)',
    );
  }

  /// Build the auth headers a confirmed-good request would carry. Implemented
  /// now so the wiring is one line on Monday: a bearer header, plus the HMAC
  /// signature header IF the spike confirms external calls need it.
  Map<String, String> buildAuthHeaders(WlanPiHttpRequest req, {String? hmacSecret}) {
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'WLANProsToolbox/1.0 (+https://wlanpros.com)',
    };
    final WlanPiToken? token = _token;
    if (token != null) {
      headers['Authorization'] = 'Bearer ${token.accessToken}';
    }
    // HMAC is computed only when a secret is supplied (the localhost/internal
    // path, or a bootstrap step). Monday confirms whether external LAN calls
    // need this at all. The computation itself matches the documented scheme.
    if (hmacSecret != null && hmacSecret.isNotEmpty) {
      headers['X-Request-Signature'] = computeHmacSignature(req, hmacSecret);
    }
    return headers;
  }

  /// Revoke the current token via `DELETE /api/v1/auth/token` and clear it.
  ///
  /// STUBBED transport; the route + body shape are confirmed (TokenRequest).
  Future<void> revoke() async {
    _token = null; // local clear is always safe and always happens
    // Live DELETE wired Monday once the token can actually be acquired.
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HMAC SIGNING (design spec §2.3) — computation IMPLEMENTED, application gated
  // ──────────────────────────────────────────────────────────────────────────

  /// Compute the request signature exactly as wlanpi-core's core/auth.py does:
  ///
  ///   canonical = "{METHOD}\n{PATH}\n{QUERY_STRING}\n{BODY}"
  ///   signature = hex( HMAC-SHA256( secret, canonical ) )
  ///   header    = X-Request-Signature
  ///
  /// This is source-accurate. It is NOT applied to live requests until Monday
  /// confirms external LAN calls require it (they may use bearer-only). Kept
  /// pure + unit-testable. STUB NOTE: returns a clearly-labeled placeholder
  /// rather than a real digest until the `crypto` dependency is wired (the real
  /// `Hmac(sha256, ...)` one-liner replaces the placeholder body on Monday — see
  /// the TODO; we do not add the dep in this device-independent scaffold pass).
  static String computeHmacSignature(WlanPiHttpRequest req, String secret) {
    final String canonical = canonicalRequestString(req);
    // ── Monday: replace with:
    //   import 'package:crypto/crypto.dart';
    //   return Hmac(sha256, utf8.encode(secret))
    //       .convert(utf8.encode(canonical)).toString();
    // Until the crypto dep is wired, return a non-secret placeholder marker so
    // nothing accidentally ships a fake-but-real-looking signature.
    return 'STUB-HMAC-SHA256(${canonical.hashCode.toRadixString(16)})';
  }

  /// Build the canonical string the signature is computed over. PURE + TESTED —
  /// this is the non-stubbed half of HMAC. Matches core/auth.py exactly.
  static String canonicalRequestString(WlanPiHttpRequest req) {
    final String method = req.method.toUpperCase();
    final String path = req.url.path;
    final String query = req.url.query; // empty string when none, per the scheme
    final String body = req.body ?? '';
    return '$method\n$path\n$query\n$body';
  }

  // ──────────────────────────────────────────────────────────────────────────
  // RATE LIMITING / RETRY-AFTER (design spec §2.3) — PARSE implemented + tested
  // ──────────────────────────────────────────────────────────────────────────

  /// Parse a `Retry-After` header (RFC: delta-seconds OR an HTTP-date). Returns
  /// null when absent/unparseable. PURE + TESTED — the device sets this on 429
  /// (slowapi). The backoff loop that consumes it is wired with the live reads.
  static Duration? parseRetryAfter(Map<String, String> headers) {
    final String? raw = _headerCaseInsensitive(headers, 'retry-after');
    if (raw == null || raw.trim().isEmpty) return null;
    final String v = raw.trim();
    final int? secs = int.tryParse(v);
    if (secs != null) return Duration(seconds: secs.clamp(0, 3600));
    final DateTime? when = DateTime.tryParse(v);
    if (when != null) {
      final Duration d = when.toUtc().difference(DateTime.now().toUtc());
      return d.isNegative ? Duration.zero : d;
    }
    return null;
  }

  /// Backoff with jitter for transient failures (5xx / network / 429 without a
  /// Retry-After). PURE + TESTED. Capped. Used by the live read loop Monday.
  static Duration backoffForAttempt(int attempt, {Duration base = const Duration(milliseconds: 400)}) {
    final int a = attempt.clamp(0, 6);
    final int factor = 1 << a; // 1,2,4,8,16,32,64
    final int ms = (base.inMilliseconds * factor).clamp(0, 30000);
    // Deterministic "jitter" seam: callers add randomness; the cap is what we test.
    return Duration(milliseconds: ms);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // READS — routes confirmed, transport STUBBED until token exists
  // ──────────────────────────────────────────────────────────────────────────

  /// `GET /api/v1/system/device/info`. STUBBED until authenticate() works.
  Future<WlanPiDeviceInfo> readDeviceInfo() async {
    _requireAuthOrStub();
    throw const WlanPiNotYetWired('system/device/info live read');
  }

  /// `GET /api/v1/system/device/stats`. STUBBED until authenticate() works.
  Future<WlanPiDeviceStats> readDeviceStats() async {
    _requireAuthOrStub();
    throw const WlanPiNotYetWired('system/device/stats live read');
  }

  /// `GET /api/v1/network/info/`. STUBBED until authenticate() works.
  Future<WlanPiNetworkInfo> readNetworkInfo() async {
    _requireAuthOrStub();
    throw const WlanPiNotYetWired('network/info live read');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PROFILER — routes confirmed; long-op modeled; transport STUBBED
  // ──────────────────────────────────────────────────────────────────────────

  /// Start a profiler run via `POST /api/v1/profiler/start`. Idempotency-guarded:
  /// does not fire a second start while one is in flight (design spec §2.4).
  /// STUBBED transport until auth works.
  Future<void> startProfiler() async {
    _requireAuthOrStub();
    if (_profilerInFlight) return; // idempotency guard — "ensure a run exists"
    throw const WlanPiNotYetWired('profiler/start live call');
  }

  bool _profilerInFlight = false;

  /// Poll `GET /api/v1/profiler/status` and map to a [ProfilerResult].
  /// STUBBED transport; the decoded capability FIELD NAMES are the Monday
  /// unknown (see ProfilerClientCapabilities). Until then the UI uses sample
  /// data, clearly labeled.
  Future<ProfilerResult> pollProfilerStatus() async {
    _requireAuthOrStub();
    throw const WlanPiNotYetWired('profiler/status live poll + capability decode');
  }

  /// Stop a run via `POST /api/v1/profiler/stop`.
  Future<void> stopProfiler() async {
    _profilerInFlight = false;
    // Live stop wired Monday.
  }

  // ──────────────────────────────────────────────────────────────────────────
  // internals
  // ──────────────────────────────────────────────────────────────────────────

  void _requireAuthOrStub() {
    if (_token == null) {
      // Reads require a token; until the handshake is wired, surface the honest
      // not-yet-wired state rather than pretending.
      throw const WlanPiNotYetWired('authenticated session (token handshake)');
    }
  }

  /// The single send seam every live call will route through on Monday: it
  /// attaches auth headers, dispatches via the injected [_transport], maps the
  /// status to the error taxonomy (401 -> unauthorized, 429 -> rateLimited with
  /// Retry-After, etc.), and returns the response. Implemented now so wiring the
  /// reads on Monday is a one-line `_send(...)` per route. The default transport
  /// throws [WlanPiNotYetWired] until a real client is injected, so this never
  /// silently no-ops.
  Future<WlanPiHttpResponse> send(
    WlanPiHttpRequest request, {
    String? hmacSecret,
  }) async {
    final Map<String, String> headers = <String, String>{
      ...request.headers,
      ...buildAuthHeaders(request, hmacSecret: hmacSecret),
    };
    final WlanPiHttpResponse resp = await _transport(
      WlanPiHttpRequest(
        method: request.method,
        url: request.url,
        headers: headers,
        body: request.body,
        timeout: request.timeout,
      ),
    );
    if (resp.statusCode == 401) {
      throw const WlanPiException(
        WlanPiErrorKind.unauthorized,
        'The WLAN Pi rejected the session token.',
        statusCode: 401,
      );
    }
    if (resp.statusCode == 429) {
      throw WlanPiException(
        WlanPiErrorKind.rateLimited,
        'The WLAN Pi is rate-limiting requests right now.',
        statusCode: 429,
        retryAfter: parseRetryAfter(resp.headers),
      );
    }
    return resp;
  }

  static String _safeTail(String s) =>
      s.length <= 4 ? '••••' : s.substring(s.length - 4);

  static String? _headerCaseInsensitive(Map<String, String> headers, String key) {
    final String lk = key.toLowerCase();
    for (final MapEntry<String, String> e in headers.entries) {
      if (e.key.toLowerCase() == lk) return e.value;
    }
    return null;
  }

  /// The default transport: refuses to do anything until a real one is injected
  /// (Monday). Fails loud and honest rather than silently no-op'ing.
  static Future<WlanPiHttpResponse> _unwiredTransport(WlanPiHttpRequest req) async {
    throw const WlanPiNotYetWired('HTTP transport (inject the real client on Monday)');
  }
}
