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
import 'dart:typed_data';

import 'package:http/http.dart' as http;

// Phase C model imports. These service files declare the display models the
// native tools already parse into; on WEB they import `dart:io` too, but the
// current Flutter web toolchain tolerates a `dart:io` import as long as no
// dart:io *object* is constructed at runtime — and we only ever touch the pure
// model constructors below, never the socket-backed Service methods. So the Pi
// path renders through the exact same models as native, keeping one screen and
// one render path per tool (contract §NEW-backend-endpoints).
import 'arp_ndp_service.dart' show Neighbor;
import 'bgp_asn_service.dart' show BgpAsnResult, BgpQueryKind;
import 'http_header_service.dart'
    show HeaderEntry, HttpHeaderResult, HttpHop, HttpMethod;
import 'ip_geo_service.dart' show IpGeoProvider, IpGeoResult;
import 'lan_discovery/device_type.dart' show DeviceType;
import 'lan_discovery/lan_discovery_engine.dart' show DiscoveryResult;
import 'lan_discovery/lan_host.dart' show LanHost;
import 'packet_sender_service.dart'
    show PacketErrorKind, PacketResult, PacketTransport;
import 'ping_plot_controller.dart' show PingPlotState, PingSample;
import 'ping_sweep_service.dart' show SweepHostResult;
import 'port_scan_service.dart' show PortResult, PortStatus;
import 'ssl_inspect_service.dart'
    show CertValidity, DnField, InspectedCertificate, SslInspectResult;
import 'wake_on_lan_service.dart' show WakeOnLanResult;
import 'whois_service.dart' show WhoisHighlight, WhoisResult;

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
    this.jitterMs,
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

  /// `conntest` only: the internet-target jitter in milliseconds, when the Pi
  /// computed it (JSON `jitter_ms`). Null when the Pi could not compute a jitter
  /// figure — honest-null, never zero-filled (GL-005). The gateway hop does not
  /// carry a jitter and the traceroute path never sets it.
  final double? jitterMs;

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
      jitterMs: _toDouble(json['jitter_ms']),
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

/// One managed, scan-capable radio the Pi can run a neighbor scan on, from
/// `/toolboxapi/scan-interfaces`. A multi-NIC WLAN Pi (e.g. the onboard BE200
/// alongside a USB Panda) exposes more than one; the Nearby AP Scan screen
/// offers a picker so the user chooses which radio scans. CLEAN fields only —
/// the Pi reports the kernel interface name and its driver, nothing more.
class PiScanInterface {
  const PiScanInterface({required this.name, this.driver});

  /// The kernel interface name (e.g. "wlan0"). Never empty.
  final String name;

  /// The driver bound to the radio (e.g. "mt7921u", "iwlwifi"), or null when
  /// the Pi did not report one — honest-null, never guessed (GL-005).
  final String? driver;

  /// The picker label: "wlan1 (iwlwifi)" when a driver is known, else the bare
  /// interface name.
  String get label => driver == null ? name : '$name ($driver)';

  /// Parses one `interfaces[]` entry. Returns null when the name is missing, so
  /// a malformed entry is dropped, never guessed.
  static PiScanInterface? fromJson(Map<String, dynamic> json) {
    final String? name = json['name'] as String?;
    if (name == null || name.isEmpty) return null;
    final String? driver = json['driver'] as String?;
    return PiScanInterface(
      name: name,
      driver: (driver == null || driver.isEmpty) ? null : driver,
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

/// The Pi's own uplink throughput (Pi → internet), measured on the Pi against a
/// vendor-neutral public endpoint. Distinct from the browser↔Pi Wi-Fi-hop
/// figure (see [PiBackendClient.deviceToPiDownloadMbps] /
/// [PiBackendClient.deviceToPiUploadMbps]) — the two are NEVER conflated
/// (Keith decision + [[project_throughput_methodology]]).
///
/// Either leg can come back null with a matching `*Error` string when the Pi's
/// probe to the public endpoint failed; a failed leg is honest-null, never a
/// fabricated 0 (GL-005 / GL-008).
class PiThroughputResult {
  const PiThroughputResult({
    this.downloadMbps,
    this.uploadMbps,
    this.server,
    this.method,
    this.downloadError,
    this.uploadError,
  });

  final double? downloadMbps;
  final double? uploadMbps;
  final String? server;
  final String? method;
  final String? downloadError;
  final String? uploadError;

  factory PiThroughputResult.fromJson(Map<String, dynamic> json) {
    return PiThroughputResult(
      downloadMbps: _toDouble(json['download_mbps']),
      uploadMbps: _toDouble(json['upload_mbps']),
      server: json['server'] as String?,
      method: json['method'] as String?,
      downloadError: json['download_error'] as String?,
      uploadError: json['upload_error'] as String?,
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
        await _http.get(_endpoint('health')).timeout(const Duration(seconds: 5));
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

  /// The Pi's managed, scan-capable radios via `/toolboxapi/scan-interfaces`
  /// (wlan0 first). Feeds the Nearby AP Scan radio picker on a multi-NIC Pi; the
  /// chosen [PiScanInterface.name] is threaded back into [scan]'s `interface`.
  Future<List<PiScanInterface>> scanInterfaces() async {
    final Map<String, dynamic> json = await _getJsonObject(
      'scan-interfaces',
      timeout: const Duration(seconds: 10),
    );
    final List<dynamic> list =
        (json['interfaces'] as List<dynamic>?) ?? const <dynamic>[];
    return list
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> m) =>
            PiScanInterface.fromJson(m.cast<String, dynamic>()))
        .whereType<PiScanInterface>()
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

  // ── Phase C: new REST-backed tools ─────────────────────────────────────────

  /// SSL/TLS certificate inspection run ON the Pi via `/toolboxapi/ssl`. Bridges
  /// the Pi's parsed-cert JSON into the SAME [SslInspectResult] the native TLS
  /// path builds, so the screen renders identically. A cert that is expired /
  /// not-yet-valid is still a successful inspection (the derived [CertValidity]
  /// carries the verdict); only a connection/parse failure (`certificate:null`)
  /// is an error. Cipher is leaf-only-null on both paths (honest, GL-005).
  Future<SslInspectResult> sslInspect({
    required String host,
    int port = 443,
  }) async {
    final Map<String, dynamic> json = await _getJsonObject(
      'ssl',
      query: <String, String>{'host': host, 'port': '$port'},
      timeout: const Duration(seconds: 15),
    );
    final String h = (json['host'] as String?) ?? host;
    final int p = _toInt(json['port']) ?? port;
    final Map<String, dynamic>? cert =
        (json['certificate'] as Map?)?.cast<String, dynamic>();
    if (cert == null) {
      final Object? err = json['error'];
      return SslInspectResult.failure(
        host: h,
        port: p,
        message: (err is String && err.isNotEmpty)
            ? err
            : 'The WLAN Pi could not retrieve a certificate for $h:$p.',
      );
    }
    final DateTime? notBefore = _parseUtc(cert['not_before']);
    final DateTime? notAfter = _parseUtc(cert['not_after']);
    if (notBefore == null || notAfter == null) {
      return SslInspectResult.failure(
        host: h,
        port: p,
        message: 'The WLAN Pi returned a certificate without valid dates.',
      );
    }
    final String? subjectCn = _blankNull(cert['subject_cn'] as String?);
    final String? subjectOrg = _blankNull(cert['subject_org'] as String?);
    final String? issuerCn = _blankNull(cert['issuer_cn'] as String?);
    final String? issuerOrg = _blankNull(cert['issuer_org'] as String?);
    final InspectedCertificate inspected = InspectedCertificate(
      subjectCommonName: subjectCn,
      subjectOrg: subjectOrg,
      issuerCommonName: issuerCn,
      issuerOrg: issuerOrg,
      subjectFields: _dnFields(subjectCn, subjectOrg),
      issuerFields: _dnFields(issuerCn, issuerOrg),
      validity: CertValidity.compute(
        notBefore: notBefore,
        notAfter: notAfter,
        now: DateTime.now().toUtc(),
      ),
      serialNumber: _groupHex(cert['serial'] as String?),
      signatureAlgorithm: _blankNull(cert['sig_algo'] as String?),
      publicKeyAlgorithm: _blankNull(cert['pubkey_algo'] as String?),
      publicKeyBits: _toInt(cert['pubkey_bits']),
      sha256Fingerprint: _groupHex(cert['sha256'] as String?),
      sha1Fingerprint: _groupHex(cert['sha1'] as String?),
      subjectAltNames: _strList(cert['sans']),
      pem: (cert['pem'] as String?) ?? '',
    );
    return SslInspectResult.success(
      host: h,
      port: p,
      certificate: inspected,
      alpn: _blankNull(json['alpn'] as String?),
      handshakeMs: _toDouble(json['handshake_ms'])?.round() ?? 0,
    );
  }

  /// HTTP header inspection run ON the Pi via `/toolboxapi/httphead`. Bridges the
  /// Pi's recorded redirect chain into the native [HttpHeaderResult] so the hop
  /// list, header table, and HEAD→GET fallback note render unchanged.
  Future<HttpHeaderResult> httpHeaders({required String url}) async {
    final Map<String, dynamic> json = await _getJsonObject(
      'httphead',
      query: <String, String>{'url': url},
      timeout: const Duration(seconds: 20),
    );
    final String requested = (json['requested_url'] as String?) ?? url;
    final Object? err = json['error'];
    if (err is String && err.isNotEmpty) {
      return HttpHeaderResult.failure(requestedUrl: requested, message: err);
    }
    final List<dynamic> hopsJson =
        (json['hops'] as List<dynamic>?) ?? const <dynamic>[];
    final List<HttpHop> hops = hopsJson
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> raw) {
      final Map<String, dynamic> h = raw.cast<String, dynamic>();
      final List<dynamic> hdrs =
          (h['headers'] as List<dynamic>?) ?? const <dynamic>[];
      return HttpHop(
        method: (h['method'] as String?)?.toUpperCase() == 'GET'
            ? HttpMethod.get
            : HttpMethod.head,
        url: (h['url'] as String?) ?? requested,
        statusCode: _toInt(h['status']) ?? 0,
        reasonPhrase: (h['reason'] as String?) ?? '',
        location: _blankNull(h['location'] as String?),
        headers: hdrs
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) => HeaderEntry(
                  name: (e['name'] as String?) ?? '',
                  value: (e['value'] as String?) ?? '',
                ))
            .toList(growable: false),
        elapsedMs: _toDouble(h['elapsed_ms'])?.round() ?? 0,
      );
    }).toList(growable: false);
    if (hops.isEmpty) {
      return HttpHeaderResult.failure(
        requestedUrl: requested,
        message: 'The WLAN Pi returned no response for $requested.',
      );
    }
    return HttpHeaderResult.success(
      requestedUrl: requested,
      hops: hops,
      headFellBackToGet: (json['head_fell_back_to_get'] as bool?) ?? false,
      redirectLimitHit: (json['redirect_limit_hit'] as bool?) ?? false,
    );
  }

  /// WHOIS lookup run ON the Pi via `/toolboxapi/whois` (pure-Python TCP/43 on
  /// the Pi). Bridges the raw record + highlights + server chain into the native
  /// [WhoisResult]; the `isEmpty` no-match state is derived by the model.
  Future<WhoisResult> whois({required String query}) async {
    final Map<String, dynamic> json = await _getJsonObject(
      'whois',
      query: <String, String>{'query': query},
      timeout: const Duration(seconds: 15),
    );
    final String q = (json['query'] as String?) ?? query;
    final Object? err = json['error'];
    final List<String> servers = _strList(json['servers_queried']);
    if (err is String && err.isNotEmpty) {
      return WhoisResult.failure(
        query: q,
        message: err,
        serversQueried: servers,
      );
    }
    final List<dynamic> hl =
        (json['highlights'] as List<dynamic>?) ?? const <dynamic>[];
    return WhoisResult.success(
      query: q,
      rawRecord: (json['raw'] as String?)?.trim() ?? '',
      highlights: hl
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> e) => WhoisHighlight(
                label: (e['label'] as String?) ?? '',
                value: (e['value'] as String?) ?? '',
              ))
          .where((WhoisHighlight w) => w.label.isNotEmpty && w.value.isNotEmpty)
          .toList(growable: false),
      serversQueried: servers,
    );
  }

  /// IP geolocation run ON the Pi via `/toolboxapi/ipgeo` (keyless ipinfo /
  /// geojs proxy). Bridges the flattened JSON into the native [IpGeoResult]; any
  /// field the source omits stays null and renders "Not available" (GL-005).
  Future<IpGeoResult> ipGeo({required String query}) async {
    final Map<String, dynamic> json = await _getJsonObject(
      'ipgeo',
      query: <String, String>{'query': query},
      timeout: const Duration(seconds: 15),
    );
    final String q = (json['query'] as String?) ?? query;
    final Object? err = json['error'];
    if (err is String && err.isNotEmpty) {
      return IpGeoResult.failure(query: q, message: err);
    }
    return IpGeoResult.success(
      query: q,
      provider: (json['provider'] as String?) == 'geojs'
          ? IpGeoProvider.geojs
          : IpGeoProvider.ipinfo,
      ip: _blankNull(json['ip'] as String?),
      ipVersion: _ipVersionLabel(json['ip_version'] as String?),
      country: _blankNull(json['country'] as String?),
      countryCode: _blankNull(json['country_code'] as String?),
      region: _blankNull(json['region'] as String?),
      city: _blankNull(json['city'] as String?),
      postal: _blankNull(json['postal'] as String?),
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      timezone: _blankNull(json['timezone'] as String?),
      utcOffset: _blankNull(json['utc_offset'] as String?),
      isp: _blankNull(json['isp'] as String?),
      org: _blankNull(json['org'] as String?),
      asn: _blankNull(json['asn'] as String?),
      asnName: _blankNull(json['asn_name'] as String?),
    );
  }

  /// BGP / ASN lookup run ON the Pi via `/toolboxapi/bgpasn` (keyless RIPEstat
  /// proxy). Bridges into the native [BgpAsnResult]. NOTE (honest-null, Mack):
  /// on the ASN path `announced_prefix` can be null when the RIPEstat payload
  /// exceeded the Pi's 256 KB cap; the IP path returns it fine. `country` /
  /// `registry` may also be null — both render "Not available".
  Future<BgpAsnResult> bgpAsn({required String query}) async {
    final Map<String, dynamic> json = await _getJsonObject(
      'bgpasn',
      query: <String, String>{'query': query},
      timeout: const Duration(seconds: 15),
    );
    final String q = (json['query'] as String?) ?? query;
    final BgpQueryKind kind =
        (json['kind'] as String?) == 'asn' ? BgpQueryKind.asn : BgpQueryKind.ip;
    final Object? err = json['error'];
    if (err is String && err.isNotEmpty) {
      return BgpAsnResult.failure(query: q, kind: kind, message: err);
    }
    return BgpAsnResult.success(
      query: q,
      kind: kind,
      asn: _blankNull(json['asn'] as String?),
      holder: _blankNull(json['holder'] as String?),
      announcedPrefix: _blankNull(json['announced_prefix'] as String?),
      country: _blankNull(json['country'] as String?),
      registry: _blankNull(json['registry'] as String?),
      asnType: _blankNull(json['asn_type'] as String?),
      isAnnounced: json['is_announced'] as bool?,
      upstreamCount: _toInt(json['upstream_count']),
      peerCount: _toInt(json['peer_count']),
      downstreamCount: _toInt(json['downstream_count']),
      relatedAsns: _strList(json['related_asns']),
    );
  }

  /// The Pi's live neighbor table via `/toolboxapi/neigh` (`ip -j neigh`). One
  /// read, no active probe (contract §6): each entry becomes a [Neighbor] with
  /// `fromArpTable:true` and a null RTT (a table read did not time anything).
  Future<List<Neighbor>> neighbors() async {
    final Map<String, dynamic> json = await _getJsonObject(
      'neigh',
      timeout: const Duration(seconds: 12),
    );
    final List<dynamic> list =
        (json['neighbors'] as List<dynamic>?) ?? const <dynamic>[];
    return list
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> raw) {
          final Map<String, dynamic> n = raw.cast<String, dynamic>();
          final String ip = (n['ip'] as String?) ?? '';
          if (ip.isEmpty) return null;
          return Neighbor(
            ip: ip,
            mac: _blankNull(n['mac'] as String?),
            rttMs: null,
            fromArpTable: true,
          );
        })
        .whereType<Neighbor>()
        .toList(growable: false);
  }

  /// TCP-connect port scan run ON the Pi via `/toolboxapi/portscan`. Returns the
  /// final [PortResult] list (one-shot, no streaming). [ports] is a
  /// comma-separated list (≤128 per the Pi's cap).
  Future<List<PortResult>> portScan({
    required String host,
    required String ports,
  }) async {
    final Map<String, dynamic> json = await _getJsonObject(
      'portscan',
      query: <String, String>{'host': host, 'ports': ports},
      timeout: const Duration(seconds: 40),
    );
    final List<dynamic> results =
        (json['results'] as List<dynamic>?) ?? const <dynamic>[];
    return results
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> raw) {
          final Map<String, dynamic> r = raw.cast<String, dynamic>();
          final int? port = _toInt(r['port']);
          if (port == null) return null;
          return PortResult(
            port: port,
            status: _portStatus(r['status'] as String?),
            serviceName: _blankNull(r['service'] as String?),
            elapsed: Duration(
              microseconds:
                  ((_toDouble(r['elapsed_ms']) ?? 0) * 1000).round(),
            ),
          );
        })
        .whereType<PortResult>()
        .toList(growable: false);
  }

  /// Liveness sweep run ON the Pi via `/toolboxapi/pingsweep`. Returns only the
  /// responders as [SweepHostResult] (one-shot). A CIDR over the Pi's 256-host
  /// cap returns a 400 whose message is surfaced through [PiBackendException]
  /// (the screen shows it: "range too large for the Pi path; use the native app").
  Future<List<SweepHostResult>> pingSweep({
    required String cidr,
    String ports = '443',
  }) async {
    final Map<String, dynamic> json = await _getJsonObject(
      'pingsweep',
      query: <String, String>{'cidr': cidr, 'ports': ports},
      timeout: const Duration(seconds: 40),
    );
    final List<dynamic> hosts =
        (json['hosts'] as List<dynamic>?) ?? const <dynamic>[];
    return hosts
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> raw) {
          final Map<String, dynamic> h = raw.cast<String, dynamic>();
          final String host = (h['host'] as String?) ?? '';
          if (host.isEmpty) return null;
          final double? rttMs = _toDouble(h['rtt_ms']);
          return SweepHostResult(
            host: host,
            responded: (h['responded'] as bool?) ?? true,
            rtt: rttMs == null
                ? null
                : Duration(microseconds: (rttMs * 1000).round()),
          );
        })
        .whereType<SweepHostResult>()
        .toList(growable: false);
  }

  /// LAN host + service discovery run ON the Pi via `/toolboxapi/discovery`
  /// (the Pi derives its own /24 and connect-scans it). Bridges into the native
  /// [DiscoveryResult]; device type is left `unknown` (the Pi does not classify).
  Future<DiscoveryResult> discovery() async {
    final Map<String, dynamic> json = await _getJsonObject(
      'discovery',
      timeout: const Duration(seconds: 40),
    );
    final List<dynamic> hostsJson =
        (json['hosts'] as List<dynamic>?) ?? const <dynamic>[];
    final List<LanHost> hosts = hostsJson
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> raw) {
          final Map<String, dynamic> h = raw.cast<String, dynamic>();
          final String ip = (h['ip'] as String?) ?? '';
          if (ip.isEmpty) return null;
          final Set<int> openPorts = <int>{
            for (final Object? p
                in (h['open_ports'] as List<dynamic>?) ?? const <dynamic>[])
              if (_toInt(p) != null) _toInt(p)!,
          };
          return LanHost(
            ip: ip,
            openPorts: openPorts,
            hostname: _blankNull(h['hostname'] as String?),
            mac: _blankNull(h['mac'] as String?),
            vendor: _blankNull(h['vendor'] as String?),
            deviceType: DeviceType.unknown,
          );
        })
        .whereType<LanHost>()
        .toList(growable: false);
    return DiscoveryResult(
      hosts: hosts,
      subnetLabel: (json['subnet_label'] as String?) ?? '',
      selfIp: _blankNull(json['self_ip'] as String?),
      gateway: _blankNull(json['gateway'] as String?),
      error: _blankNull(json['error'] as String?),
    );
  }

  /// Bounded ping series run ON the Pi via `/toolboxapi/pingseries`. Returns the
  /// WHOLE series folded into a static [PingPlotState] (no live streaming on the
  /// Pi path). A lost sample carries a null RTT and is drawn as a gap, never a
  /// faked 0 (GL-005). The Pi gives no per-sample timestamp, so the chart X axis
  /// is the 1-based sequence.
  Future<PingPlotState> pingSeries({
    required String host,
    int count = 20,
  }) async {
    final int c = count.clamp(1, 30);
    final Map<String, dynamic> json = await _getJsonObject(
      'pingseries',
      query: <String, String>{'host': host, 'count': '$c'},
      timeout: Duration(seconds: c * 2 + 12),
    );
    final List<dynamic> samplesJson =
        (json['samples'] as List<dynamic>?) ?? const <dynamic>[];
    final List<PingSample> samples = <PingSample>[];
    double? lastLanded;
    for (final Object? entry in samplesJson) {
      if (entry is! Map) continue;
      final Map<String, dynamic> s = entry.cast<String, dynamic>();
      final int seq = _toInt(s['seq']) ?? (samples.length + 1);
      final bool lost = (s['lost'] as bool?) ?? false;
      final double? rttMs = lost ? null : _toDouble(s['rtt_ms']);
      if (!lost && rttMs != null) lastLanded = rttMs;
      samples.add(PingSample(
        sequence: seq,
        elapsed: Duration(seconds: seq),
        rttMs: rttMs,
        lost: lost,
        errorLabel: lost ? 'no reply' : null,
      ));
    }
    final int sent = _toInt(json['sent']) ?? samples.length;
    final int received = _toInt(json['received']) ??
        samples.where((PingSample s) => !s.lost).length;
    return PingPlotState(
      samples: List<PingSample>.unmodifiable(samples),
      windowSent: sent,
      windowReceived: received,
      minMs: _toDouble(json['min_ms']),
      avgMs: _toDouble(json['avg_ms']),
      maxMs: _toDouble(json['max_ms']),
      jitterMs: _toDouble(json['jitter_ms']),
      lastMs: samples.isNotEmpty && !samples.last.lost
          ? samples.last.rttMs
          : lastLanded,
      totalSent: sent,
      totalReceived: received,
    );
  }

  /// The Pi's own uplink throughput (Pi → internet) via `/toolboxapi/throughput`.
  /// Feeds the net-quality / test-my-connection "Pi → Internet" row. Bounded
  /// ~10 s per leg on the Pi; a failed leg comes back null with a `*Error`.
  Future<PiThroughputResult> throughput() async {
    final Map<String, dynamic> json = await _getJsonObject(
      'throughput',
      timeout: const Duration(seconds: 35),
    );
    return PiThroughputResult.fromJson(json);
  }

  /// Wake-on-LAN magic packet sent from the Pi via POST `/toolboxapi/wol`.
  /// Success asserts only that the packet was SENT (WoL is unacknowledged) —
  /// [WakeOnLanResult.sent], never a claim the target woke.
  Future<WakeOnLanResult> wakeOnLan({
    required String mac,
    String broadcast = '255.255.255.255',
    int port = 9,
  }) async {
    final Map<String, dynamic> json = await _postJsonObject(
      'wol',
      body: <String, dynamic>{
        'mac': mac,
        'broadcast': broadcast,
        'port': port,
      },
      timeout: const Duration(seconds: 12),
    );
    final String normMac = (json['mac'] as String?) ?? mac;
    final String bcast = (json['broadcast'] as String?) ?? broadcast;
    final int p = _toInt(json['port']) ?? port;
    final Object? err = json['error'];
    if (err is String && err.isNotEmpty) {
      return WakeOnLanResult.failure(
        message: err,
        normalizedMac: normMac,
        broadcast: bcast,
        port: p,
      );
    }
    return WakeOnLanResult.sent(
      normalizedMac: normMac,
      broadcast: bcast,
      port: p,
      bytesSent: _toInt(json['bytes_sent']) ?? 0,
    );
  }

  /// Custom TCP/UDP payload sent from the Pi via POST `/toolboxapi/packet`. The
  /// [payload] bytes are hex-encoded for the wire; the reply is hex-decoded back
  /// to bytes so the native [PacketResult] renders identically. Bounded to a
  /// single connected send (Vex): no streaming, no raw/spoof.
  Future<PacketResult> packetSend({
    required PacketTransport transport,
    required String host,
    required int port,
    required List<int> payload,
  }) async {
    final Map<String, dynamic> json = await _postJsonObject(
      'packet',
      body: <String, dynamic>{
        'transport': transport == PacketTransport.tcp ? 'tcp' : 'udp',
        'host': host,
        'port': port,
        'payload_hex': _bytesToHex(payload),
      },
      timeout: const Duration(seconds: 15),
    );
    final Duration elapsed =
        Duration(milliseconds: _toInt(json['elapsed_ms']) ?? 0);
    final Object? err = json['error'];
    if (err is String && err.isNotEmpty) {
      return PacketResult.failure(
        transport: transport,
        host: host,
        port: port,
        kind: PacketErrorKind.other,
        message: err,
        bytesSent: _toInt(json['bytes_sent']) ?? 0,
        elapsed: elapsed,
      );
    }
    final List<int> received = _hexToBytes(json['received_hex'] as String?);
    return PacketResult.ok(
      transport: transport,
      host: host,
      port: port,
      bytesSent: _toInt(json['bytes_sent']) ?? payload.length,
      received: received,
      elapsed: elapsed,
      timedOut: (json['timed_out'] as bool?) ?? received.isEmpty,
    );
  }

  /// The browser↔Pi Wi-Fi-hop DOWNLOAD figure: streams [bytes] of incompressible
  /// data from GET `/toolboxapi/garbage?size=` and times the transfer, returning
  /// megabits/second. This is the LOCAL hop (this device to the Pi), measured
  /// same-origin in the browser — clearly distinct from the Pi→internet
  /// [throughput] figure. Never conflated (Keith decision).
  Future<double> deviceToPiDownloadMbps({int bytes = 8 * 1024 * 1024}) async {
    final Uri uri = _endpoint('garbage', query: <String, String>{'size': '$bytes'});
    final Stopwatch sw = Stopwatch()..start();
    final http.Response resp =
        await _http.get(uri).timeout(const Duration(seconds: 30));
    sw.stop();
    if (resp.statusCode != 200) {
      throw PiBackendException('garbage returned HTTP ${resp.statusCode}');
    }
    return _mbps(resp.bodyBytes.length, sw.elapsedMicroseconds);
  }

  /// The browser↔Pi Wi-Fi-hop UPLOAD figure: POSTs [bytes] to
  /// `/toolboxapi/perfsink` (which stream-discards the body) and times it,
  /// returning megabits/second. Same LOCAL hop as [deviceToPiDownloadMbps].
  Future<double> deviceToPiUploadMbps({int bytes = 4 * 1024 * 1024}) async {
    final Uint8List payload = Uint8List(bytes);
    final Stopwatch sw = Stopwatch()..start();
    final http.Response resp = await _http
        .post(
          _endpoint('perfsink'),
          headers: const <String, String>{
            'Content-Type': 'application/octet-stream',
          },
          body: payload,
        )
        .timeout(const Duration(seconds: 30));
    sw.stop();
    if (resp.statusCode != 200) {
      throw PiBackendException('perfsink returned HTTP ${resp.statusCode}');
    }
    return _mbps(bytes, sw.elapsedMicroseconds);
  }

  static double _mbps(int bytes, int elapsedMicros) {
    if (elapsedMicros <= 0 || bytes <= 0) return 0;
    final double seconds = elapsedMicros / 1000000.0;
    return (bytes * 8) / seconds / 1000000.0;
  }

  Future<Map<String, dynamic>> _getJsonObject(
    String path, {
    Map<String, String>? query,
    required Duration timeout,
  }) async {
    final http.Response resp =
        await _http.get(_endpoint(path, query: query)).timeout(timeout);
    return _decodeOrThrow(path, resp);
  }

  Future<Map<String, dynamic>> _postJsonObject(
    String path, {
    required Map<String, dynamic> body,
    required Duration timeout,
  }) async {
    final http.Response resp = await _http
        .post(
          _endpoint(path),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);
    return _decodeOrThrow(path, resp);
  }

  /// Decode a JSON object body, or throw [PiBackendException]. On a non-200, the
  /// server's own `error` message (e.g. the ping-sweep "range too large" 400) is
  /// surfaced when present so the screen can show a precise reason.
  Map<String, dynamic> _decodeOrThrow(String path, http.Response resp) {
    if (resp.statusCode != 200) {
      String detail = 'HTTP ${resp.statusCode}';
      try {
        final Object? body = jsonDecode(resp.body);
        if (body is Map && body['error'] is String &&
            (body['error'] as String).isNotEmpty) {
          detail = body['error'] as String;
        }
      } on Object {
        // Non-JSON error body — keep the status-code detail.
      }
      throw PiBackendException('$path failed: $detail');
    }
    final Object? decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw PiBackendException('$path returned an unexpected body shape');
    }
    return decoded;
  }
}

// ── Phase C bridging helpers (pure; shared by the model-mapping methods) ──────

String? _blankNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

List<String> _strList(Object? v) {
  if (v is! List) return const <String>[];
  return v
      .map((Object? e) => e?.toString().trim() ?? '')
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);
}

/// Build the ordered CN/O field list the SSL detail view renders, from the two
/// values the Pi provides (it does not send a full DN map).
List<DnField> _dnFields(String? cn, String? org) => <DnField>[
      if (cn != null && cn.isNotEmpty) DnField(label: 'CN', value: cn),
      if (org != null && org.isNotEmpty) DnField(label: 'O', value: org),
    ];

/// Uppercase colon-grouped hex (e.g. "6A:70:41:…"), matching the native cert
/// fingerprint/serial rendering. Accepts the Pi's lowercase, un-grouped hex.
String? _groupHex(String? raw) {
  if (raw == null) return null;
  final String hex = raw.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
  if (hex.isEmpty) return null;
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < hex.length; i += 2) {
    if (i > 0) out.write(':');
    out.write(hex.substring(i, (i + 2).clamp(0, hex.length)));
  }
  return out.toString();
}

/// Parse an ISO-8601 UTC timestamp the Pi emits (e.g. "2026-01-01T00:00:00Z").
DateTime? _parseUtc(Object? v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v)?.toUtc();
}

/// The Pi sends ip_version as "4"/"6"; the native model labels it "IPv4"/"IPv6".
String? _ipVersionLabel(String? v) {
  switch (v) {
    case '4':
      return 'IPv4';
    case '6':
      return 'IPv6';
    default:
      return null;
  }
}

PortStatus _portStatus(String? s) {
  switch (s) {
    case 'open':
      return PortStatus.open;
    case 'closed':
      return PortStatus.closed;
    default:
      return PortStatus.filtered;
  }
}

String _bytesToHex(List<int> bytes) {
  final StringBuffer sb = StringBuffer();
  for (final int b in bytes) {
    sb.write((b & 0xFF).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

List<int> _hexToBytes(String? hex) {
  if (hex == null) return const <int>[];
  final String clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  if (clean.length < 2) return const <int>[];
  final List<int> out = <int>[];
  for (int i = 0; i + 1 < clean.length; i += 2) {
    final int? b = int.tryParse(clean.substring(i, i + 2), radix: 16);
    if (b != null) out.add(b);
  }
  return out;
}

double? _toDouble(Object? v) {
  if (v is num) return v.toDouble();
  return null;
}

int? _toInt(Object? v) {
  if (v is num) return v.toInt();
  return null;
}
