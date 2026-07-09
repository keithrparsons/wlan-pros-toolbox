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

/// One reachability hop from `conntest` (the internet target or the gateway).
///
/// `target` is the probed address (the internet target's IP, or the gateway's
/// IP). Latency fields are null when the hop was unreachable or the Pi did not
/// report them — never zero-filled.
class PiHop {
  const PiHop({
    required this.target,
    required this.reachable,
    this.avgMs,
    this.minMs,
    this.maxMs,
    this.lossPct,
  });

  final String? target;
  final bool reachable;
  final double? avgMs;
  final double? minMs;
  final double? maxMs;
  final double? lossPct;

  /// Parses an internet/gateway hop. The internet hop names its address under
  /// `target`; the gateway hop under `ip`.
  factory PiHop.fromJson(Map<String, dynamic> json) {
    return PiHop(
      target: (json['target'] ?? json['ip']) as String?,
      reachable: (json['reachable'] as bool?) ?? false,
      avgMs: _toDouble(json['avg_ms']),
      minMs: _toDouble(json['min_ms']),
      maxMs: _toDouble(json['max_ms']),
      lossPct: _toDouble(json['loss_pct']),
    );
  }
}

/// The DNS-resolution timing from `conntest`. `ms` is null when the Pi did not
/// resolve the probe host.
class PiDns {
  const PiDns({required this.host, required this.ms});

  final String? host;
  final double? ms;

  factory PiDns.fromJson(Map<String, dynamic> json) {
    return PiDns(
      host: json['host'] as String?,
      ms: _toDouble(json['ms']),
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
