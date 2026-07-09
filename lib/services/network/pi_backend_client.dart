// PiBackendClient — same-origin REST adapter for the WLAN Pi hosting backend.
//
// When the Toolbox WEB build is served FROM a WLAN Pi, an nginx vhost exposes a
// same-origin signing proxy at `/toolboxapi/` (RECON.md §9). That proxy signs
// requests to the Pi's `wlanpi-core` API (HMAC secret stays server-side) and
// runs the connection test on the Pi itself. A browser cannot open the raw /
// TCP / UDP sockets `dart:io` needs, so the network tools route their work
// through these REST calls instead — the scan pattern, generalized.
//
// SCOPE: this client only ever runs on WEB, behind `kIsWeb && PiBackend.available`
// (see pi_backend.dart). On Netlify (no backend) `PiBackend.available` stays
// false and none of this is reached, so the identical web bundle behaves
// exactly as before. On native (iOS/macOS/Android/Windows) the probe is a no-op
// and `available` stays false, so native behavior is byte-for-byte unchanged.
//
// TRANSPORT: `package:http` (BrowserClient on web via `fetch`). Same-origin GETs
// so there is no CORS surface and no key on the client. Every endpoint is anchored
// at the server ROOT (`/toolboxapi/...`) regardless of the app's base-href, because
// the proxy is mounted at the root by nginx.
//
// HONESTY (GL-005 / GL-008): each model carries only what the Pi actually
// reports. Fields the Pi does not provide are null, and the UI renders an honest
// "not available via the Pi sensor" state rather than a fabricated value.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown when a `/toolboxapi/` call fails (non-200, malformed body, timeout).
/// The tool screens surface it through their existing error state.
class PiBackendException implements Exception {
  const PiBackendException(this.message);

  final String message;

  @override
  String toString() => 'PiBackendException: $message';
}

/// One hop / probe summary from the Pi. Shared across three endpoints, since all
/// three describe "an address that was probed and how it answered":
///   * `conntest` — the internet target or the gateway ([PiHop.fromJson]);
///   * `ping` — the aggregate of N ICMP echoes to one host ([PiHop.fromJson],
///     which also fills [sent] / [received] / [count]);
///   * `traceroute` — one hop on the path ([PiHop.fromTracerouteJson], which
///     fills [hopNumber] and the single-probe [ms]).
///
/// `target` is the probed address (the internet target's IP, the gateway's IP,
/// the ping host, or the traceroute hop's IP). Latency fields are null when the
/// hop was unreachable or the Pi did not report them — never zero-filled.
class PiHop {
  const PiHop({
    required this.target,
    required this.reachable,
    this.avgMs,
    this.minMs,
    this.maxMs,
    this.lossPct,
    this.sent,
    this.received,
    this.count,
    this.hopNumber,
    this.ms,
  });

  final String? target;
  final bool reachable;
  final double? avgMs;
  final double? minMs;
  final double? maxMs;
  final double? lossPct;

  /// `ping` only: echoes sent / received and the requested count. Null on the
  /// conntest and traceroute paths (those do not report an echo count).
  final int? sent;
  final int? received;
  final int? count;

  /// `traceroute` only: 1-based hop number, and this hop's single round-trip
  /// time in milliseconds. Null on the conntest and ping paths.
  final int? hopNumber;
  final double? ms;

  /// Parses a conntest hop (`target`/`ip` + `reachable` + min/avg/max/loss) OR a
  /// `ping` aggregate (the same fields plus `sent`/`received`/`count`). The
  /// conntest hop names its address under `target`; the gateway hop under `ip`;
  /// the ping aggregate under `target`.
  factory PiHop.fromJson(Map<String, dynamic> json) {
    return PiHop(
      target: (json['target'] ?? json['ip']) as String?,
      reachable: (json['reachable'] as bool?) ?? false,
      avgMs: _toDouble(json['avg_ms']),
      minMs: _toDouble(json['min_ms']),
      maxMs: _toDouble(json['max_ms']),
      lossPct: _toDouble(json['loss_pct']),
      sent: _toInt(json['sent']),
      received: _toInt(json['received']),
      count: _toInt(json['count']),
    );
  }

  /// Parses one `traceroute` hop: `{"hop":1,"ip":"10.0.10.1","ms":0.4}`. A hop
  /// that did not answer arrives with a null `ip` (and no `ms`); we mark it
  /// unreachable rather than zero-filling a latency (GL-005).
  factory PiHop.fromTracerouteJson(Map<String, dynamic> json) {
    final String? ip = json['ip'] as String?;
    final double? ms = _toDouble(json['ms']);
    return PiHop(
      target: ip,
      reachable: ip != null && ip.isNotEmpty,
      hopNumber: _toInt(json['hop']),
      ms: ms,
      // Mirror the single-probe RTT into avg/min/max so any hop consumer that
      // reads the aggregate fields still sees the one measured value.
      avgMs: ms,
      minMs: ms,
      maxMs: ms,
    );
  }
}

/// A DNS timing/result from the Pi. Shared across two endpoints:
///   * `conntest` — just the resolve time for a probe host ([PiDns.fromJson]);
///   * `dns` — a full record lookup (`type` + `answers` + `count` + `query_ms`)
///     via [PiDns.fromLookupJson].
///
/// `ms` is null when the conntest path did not resolve the probe host; on the
/// lookup path the timing lives in [queryMs] and `ms` stays null.
class PiDns {
  const PiDns({
    required this.host,
    required this.ms,
    this.type,
    this.answers = const <String>[],
    this.count,
    this.queryMs,
  });

  final String? host;
  final double? ms;

  /// `dns` lookup only: the queried record type, the resolved answers (empty is
  /// a valid negative result, not an error — GL-005), the answer count the Pi
  /// reported, and the query time in milliseconds.
  final String? type;
  final List<String> answers;
  final int? count;
  final double? queryMs;

  factory PiDns.fromJson(Map<String, dynamic> json) {
    return PiDns(
      host: json['host'] as String?,
      ms: _toDouble(json['ms']),
    );
  }

  /// Parses a `dns` lookup:
  /// `{"host":"cloudflare.com","type":"A","answers":[...],"count":2,
  ///   "query_ms":36.8,"raw":"..."}`. A resolvable name with no records of the
  /// requested type returns an empty `answers` list — a normal negative result.
  factory PiDns.fromLookupJson(Map<String, dynamic> json) {
    final List<dynamic> raw =
        (json['answers'] as List<dynamic>?) ?? const <dynamic>[];
    return PiDns(
      host: json['host'] as String?,
      ms: null,
      type: json['type'] as String?,
      answers: raw
          .whereType<String>()
          .where((String s) => s.isNotEmpty)
          .toList(growable: false),
      count: _toInt(json['count']),
      queryMs: _toDouble(json['query_ms']),
    );
  }
}

/// The full `conntest` result: the internet hop, the gateway hop, DNS timing,
/// and the method string the Pi reports so the UI can attribute it honestly.
class PiConntestResult {
  const PiConntestResult({
    required this.internet,
    required this.gateway,
    required this.dns,
    this.method,
  });

  final PiHop internet;
  final PiHop gateway;
  final PiDns dns;
  final String? method;

  factory PiConntestResult.fromJson(Map<String, dynamic> json) {
    return PiConntestResult(
      internet: PiHop.fromJson(
        (json['internet'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      gateway: PiHop.fromJson(
        (json['gateway'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      dns: PiDns.fromJson(
        (json['dns'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      method: json['method'] as String?,
    );
  }
}

/// One BSS from the Pi's `scan` (a genuine off-channel neighbor scan run on the
/// Pi's radio). CLEAN fields only — the wlanpi-core scan does not expose a
/// per-BSS noise floor / SNR / MCS, so those are never modeled here (GL-005).
class PiScanNet {
  const PiScanNet({
    required this.ssid,
    required this.bssid,
    required this.signalDbm,
    required this.freqMhz,
    required this.keyMgmt,
  });

  /// Network name, or null for a hidden network (the Pi returns an empty string).
  final String? ssid;
  final String? bssid;
  final int signalDbm;
  final int freqMhz;
  final String? keyMgmt;

  /// Parses one `nets[]` entry. Returns null when a required field (signal or
  /// frequency) is missing, so a malformed entry is dropped, never guessed.
  static PiScanNet? fromJson(Map<String, dynamic> json) {
    final int? signal = (json['signal'] as num?)?.toInt();
    final int? freq = (json['freq'] as num?)?.toInt();
    if (signal == null || freq == null) return null;
    final String? rawSsid = json['ssid'] as String?;
    return PiScanNet(
      ssid: (rawSsid == null || rawSsid.isEmpty) ? null : rawSsid,
      bssid: json['bssid'] as String?,
      signalDbm: signal,
      freqMhz: freq,
      keyMgmt: json['key_mgmt'] as String?,
    );
  }
}

/// One IP address bound to a Pi interface.
class PiInterfaceAddress {
  const PiInterfaceAddress({
    required this.local,
    required this.prefixLen,
    required this.isIPv4,
  });

  final String local;
  final int? prefixLen;
  final bool isIPv4;

  /// "10.0.0.5/24" when a prefix is present, else the bare address.
  String get cidr => prefixLen == null ? local : '$local/$prefixLen';
}

/// One interface from the Pi's `interfaces` (the `ip -j addr`-shaped payload).
class PiInterface {
  const PiInterface({
    required this.name,
    required this.mac,
    required this.operState,
    required this.mtu,
    required this.linkSpeedMbps,
    required this.linkType,
    required this.addresses,
  });

  final String name;
  final String? mac;
  final String? operState;
  final int? mtu;
  final int? linkSpeedMbps;
  final String? linkType;
  final List<PiInterfaceAddress> addresses;

  factory PiInterface.fromJson(String name, Map<String, dynamic> json) {
    final List<dynamic> rawAddrs =
        (json['addr_info'] as List<dynamic>?) ?? const <dynamic>[];
    final List<PiInterfaceAddress> addrs = rawAddrs
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> a) {
      final String? local = a['local'] as String?;
      if (local == null || local.isEmpty) return null;
      return PiInterfaceAddress(
        local: local,
        prefixLen: (a['prefixlen'] as num?)?.toInt(),
        isIPv4: (a['family'] as String?) == 'inet',
      );
    }).whereType<PiInterfaceAddress>().toList(growable: false);

    return PiInterface(
      name: name,
      mac: json['address'] as String?,
      operState: json['operstate'] as String?,
      mtu: (json['mtu'] as num?)?.toInt(),
      linkSpeedMbps: (json['link_speed'] as num?)?.toInt(),
      linkType: json['link_type'] as String?,
      addresses: addrs,
    );
  }
}

/// Same-origin REST adapter for the Pi hosting backend. Web-only in practice
/// (guarded by `PiBackend.available`); every method is a plain GET to
/// `/toolboxapi/{endpoint}` anchored at the server root.
class PiBackendClient {
  PiBackendClient({http.Client? httpClient, Uri? base})
      : _http = httpClient ?? http.Client(),
        _base = base ?? Uri.base;

  final http.Client _http;
  final Uri _base;

  /// Root-anchored `/toolboxapi/{path}` on the SAME origin as the loaded page,
  /// independent of the app's base-href (the proxy is mounted at the root).
  Uri _endpoint(String path, {Map<String, String>? query}) {
    return Uri(
      scheme: _base.scheme,
      host: _base.host,
      port: _base.hasPort ? _base.port : null,
      path: '/toolboxapi/$path',
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }

  /// Pi-hosted probe: any 200 means a Pi backend is answering. Kept fast so the
  /// startup gate never stalls; callers apply their own outer timeout too.
  Future<bool> health() async {
    final http.Response resp =
        await _http.get(_endpoint('health')).timeout(const Duration(seconds: 2));
    return resp.statusCode == 200;
  }

  /// One-shot connection test run ON the Pi: gateway + internet latency/loss and
  /// DNS-resolution timing.
  Future<PiConntestResult> conntest() async {
    final Map<String, dynamic> json =
        await _getJsonObject('conntest', timeout: const Duration(seconds: 15));
    return PiConntestResult.fromJson(json);
  }

  /// Neighbor Wi-Fi scan run on the Pi's radio. Slower (the radio dwell can take
  /// several seconds), so it carries a generous timeout.
  Future<List<PiScanNet>> scan({String interface = 'wlan0'}) async {
    final Map<String, dynamic> json = await _getJsonObject(
      'scan',
      query: <String, String>{'interface': interface},
      timeout: const Duration(seconds: 25),
    );
    final List<dynamic> nets =
        (json['nets'] as List<dynamic>?) ?? const <dynamic>[];
    return nets
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> m) =>
            PiScanNet.fromJson(m.cast<String, dynamic>()))
        .whereType<PiScanNet>()
        .toList(growable: false);
  }

  /// The Pi's interface table (`ip -j addr`-shaped: a map of ifname -> [detail]).
  Future<List<PiInterface>> interfaces() async {
    final Map<String, dynamic> json =
        await _getJsonObject('interfaces', timeout: const Duration(seconds: 10));
    final List<PiInterface> out = <PiInterface>[];
    for (final MapEntry<String, dynamic> entry in json.entries) {
      final List<dynamic>? detail = entry.value as List<dynamic>?;
      if (detail == null || detail.isEmpty) continue;
      final Map<dynamic, dynamic>? first =
          detail.first as Map<dynamic, dynamic>?;
      if (first == null) continue;
      out.add(PiInterface.fromJson(entry.key, first.cast<String, dynamic>()));
    }
    return out;
  }

  /// ICMP ping run ON the Pi to [host], [count] echoes (clamped 1–20 to match
  /// the Pi's own bound). Returns the aggregate as a [PiHop] (reachable, loss,
  /// min/avg/max, sent/received). Ping can be slow, so the client timeout sits
  /// OUTSIDE the Pi's own: `count * 2 + 8`s.
  Future<PiHop> ping({required String host, int count = 5}) async {
    final int c = count.clamp(1, 20);
    final Map<String, dynamic> json = await _getJsonObject(
      'ping',
      query: <String, String>{'host': host, 'count': '$c'},
      timeout: Duration(seconds: c * 2 + 8),
    );
    return PiHop.fromJson(json);
  }

  /// Traceroute run ON the Pi to [host], up to [maxHops] (clamped 1–30 to match
  /// the Pi's own bound). Returns the hops in path order; a hop that did not
  /// answer carries a null target and is not zero-filled. Traceroute can be
  /// slow, so the client timeout sits OUTSIDE the Pi's own: `maxHops * 2 + 12`s.
  Future<List<PiHop>> traceroute({
    required String host,
    int maxHops = 30,
  }) async {
    final int m = maxHops.clamp(1, 30);
    final Map<String, dynamic> json = await _getJsonObject(
      'traceroute',
      query: <String, String>{'host': host, 'max_hops': '$m'},
      timeout: Duration(seconds: m * 2 + 12),
    );
    final List<dynamic> hops =
        (json['hops'] as List<dynamic>?) ?? const <dynamic>[];
    return hops
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> h) =>
            PiHop.fromTracerouteJson(h.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// DNS lookup run ON the Pi for [host], record [type] (A, AAAA, CNAME, MX, NS,
  /// TXT, SOA, PTR, SRV, CAA — one of the Pi's supported types).
  ///
  /// NAMING MISMATCH (deliberate): the CATALOG tool id is `dns-lookup` (that is
  /// what [PiBackend.servedToolIds] carries and what the tool-grid gate checks),
  /// but the PROXY ROUTE is `/toolboxapi/dns`. So this method hits the `dns`
  /// path even though the tool is `dns-lookup`. Do not "fix" one to match the
  /// other — they are intentionally different names.
  Future<PiDns> dnsLookup({
    required String host,
    required String type,
  }) async {
    final Map<String, dynamic> json = await _getJsonObject(
      'dns', // catalog id is `dns-lookup`; the proxy route is `dns`.
      query: <String, String>{'host': host, 'type': type},
      timeout: const Duration(seconds: 12),
    );
    return PiDns.fromLookupJson(json);
  }

  Future<Map<String, dynamic>> _getJsonObject(
    String path, {
    Map<String, String>? query,
    required Duration timeout,
  }) async {
    final http.Response resp =
        await _http.get(_endpoint(path, query: query)).timeout(timeout);
    if (resp.statusCode != 200) {
      throw PiBackendException('$path returned HTTP ${resp.statusCode}');
    }
    final Object? decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw PiBackendException('$path returned an unexpected body shape');
    }
    return decoded;
  }
}

double? _toDouble(Object? v) {
  if (v is num) return v.toDouble();
  return null;
}

int? _toInt(Object? v) {
  if (v is num) return v.toInt();
  return null;
}
