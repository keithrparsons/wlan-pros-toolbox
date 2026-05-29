// BgpAsnService — BGP / ASN lookup over the RIPEstat Data API.
//
// API CHOICE: RIPEstat (https://stat.ripe.net/data/...).
//  - Free, NO API key, HTTPS-only. (https mandatory — cleartext trips iOS ATS.)
//  - Operated by the RIPE NCC (a Regional Internet Registry), so the data is
//    authoritative and the service is stable and high-availability.
//  - Three small endpoints cover the brief's fields:
//      * network-info       → the announcing prefix + ASN(s) for an IP.
//      * as-overview        → AS holder/name, type, RIR (registry), announced?.
//      * prefix-overview    → ASNs announcing a prefix + the prefix block.
//      * (peers/upstreams)  → asn-neighbours gives left/right neighbours, which
//                             we map to upstream/peer counts where present.
//  - bgpview.io was the alternative; rejected because its free tier is more
//    aggressively rate-limited and historically less reliable than RIPEstat,
//    and RIPEstat's per-resource endpoints map cleanly to the fields we show.
//
// INPUT: an IPv4/IPv6 address OR an ASN ("AS15169", "15169", or "as15169").
//  - IP path:  network-info (→ prefix + asn) then as-overview(asn).
//  - ASN path: as-overview(asn) then asn-neighbours(asn) for peer/upstream.
//
// WEB: built on JsonHttpClient → dart:io, so this is native-only. The screen
// gates web to NetworkUnavailableView rather than depend on RIPEstat CORS (we
// did not verify permissive CORS, so we do not ship a maybe-broken web tool).
//
// HONESTY: every field is nullable; a datum the API omits renders as
// "Not available", never a fabricated value.

import 'json_http_client.dart';

/// Whether the user typed an IP or an ASN — drives which endpoints we call.
enum BgpQueryKind { ip, asn }

/// Structured result of a BGP/ASN lookup. Success carries the populated fields;
/// a failure is represented by [errorMessage] (and [errorKind] for branching).
class BgpAsnResult {
  const BgpAsnResult._({
    required this.query,
    required this.kind,
    this.asn,
    this.holder,
    this.announcedPrefix,
    this.country,
    this.registry,
    this.asnType,
    this.isAnnounced,
    this.upstreamCount,
    this.peerCount,
    this.downstreamCount,
    this.relatedAsns = const <String>[],
    this.errorMessage,
    this.errorKind,
  });

  factory BgpAsnResult.success({
    required String query,
    required BgpQueryKind kind,
    String? asn,
    String? holder,
    String? announcedPrefix,
    String? country,
    String? registry,
    String? asnType,
    bool? isAnnounced,
    int? upstreamCount,
    int? peerCount,
    int? downstreamCount,
    List<String> relatedAsns = const <String>[],
  }) =>
      BgpAsnResult._(
        query: query,
        kind: kind,
        asn: asn,
        holder: holder,
        announcedPrefix: announcedPrefix,
        country: country,
        registry: registry,
        asnType: asnType,
        isAnnounced: isAnnounced,
        upstreamCount: upstreamCount,
        peerCount: peerCount,
        downstreamCount: downstreamCount,
        relatedAsns: relatedAsns,
      );

  factory BgpAsnResult.failure({
    required String query,
    required BgpQueryKind kind,
    required String message,
    JsonHttpErrorKind? errorKind,
  }) =>
      BgpAsnResult._(
        query: query,
        kind: kind,
        errorMessage: message,
        errorKind: errorKind,
      );

  final String query;
  final BgpQueryKind kind;

  /// "AS15169" form, or null if the API did not resolve one.
  final String? asn;
  final String? holder;
  final String? announcedPrefix;
  final String? country;
  final String? registry;
  final String? asnType;

  /// Whether the prefix/ASN is currently seen in the global routing table.
  final bool? isAnnounced;

  /// Neighbour counts from asn-neighbours (only on the ASN path).
  final int? upstreamCount;
  final int? peerCount;
  final int? downstreamCount;

  /// Other ASNs announcing the same prefix (IP path), if any.
  final List<String> relatedAsns;

  final String? errorMessage;
  final JsonHttpErrorKind? errorKind;

  bool get isError => errorMessage != null;

  /// True when the API answered cleanly but resolved no ASN — an "empty" state
  /// distinct from an error (e.g. a private/bogon IP not in the routing table).
  bool get isEmpty =>
      !isError && asn == null && announcedPrefix == null && holder == null;
}

class BgpAsnService {
  BgpAsnService({JsonHttpClient? client})
      : _client = client ?? JsonHttpClient();

  final JsonHttpClient _client;

  static const String _base = 'https://stat.ripe.net/data';

  /// Classify a raw query string as an IP or an ASN. Exposed for tests.
  static BgpQueryKind? classify(String raw) {
    final String s = raw.trim();
    if (s.isEmpty) return null;
    if (_asnNumber(s) != null) return BgpQueryKind.asn;
    if (_looksLikeIp(s)) return BgpQueryKind.ip;
    return null;
  }

  /// Normalize an ASN input ("AS15169", "as15169", "15169") to its number, or
  /// null when it is not an ASN. Exposed for tests.
  static int? _asnNumber(String raw) {
    String s = raw.trim().toLowerCase();
    if (s.startsWith('as')) s = s.substring(2);
    if (s.isEmpty) return null;
    final int? n = int.tryParse(s);
    if (n == null || n < 0 || n > 4294967295) return null;
    return n;
  }

  static bool _looksLikeIp(String s) {
    // Cheap shape check; RIPEstat does the authoritative parse server-side.
    if (s.contains(':')) {
      return RegExp(r'^[0-9a-fA-F:]+$').hasMatch(s) && s.length >= 2;
    }
    final List<String> parts = s.split('.');
    if (parts.length != 4) return false;
    for (final String p in parts) {
      final int? o = int.tryParse(p);
      if (o == null || o < 0 || o > 255) return false;
    }
    return true;
  }

  /// Run a lookup for [rawQuery]. Never throws — failures come back as
  /// [BgpAsnResult.failure].
  Future<BgpAsnResult> lookup({required String rawQuery}) async {
    final String query = rawQuery.trim();
    final BgpQueryKind? kind = classify(query);
    if (kind == null) {
      return BgpAsnResult.failure(
        query: query,
        kind: BgpQueryKind.ip,
        message: 'Enter a valid IPv4/IPv6 address or an ASN (e.g. AS15169).',
      );
    }
    try {
      return kind == BgpQueryKind.asn
          ? await _lookupAsn(query)
          : await _lookupIp(query);
    } on JsonHttpException catch (e) {
      return BgpAsnResult.failure(
        query: query,
        kind: kind,
        message: e.message,
        errorKind: e.kind,
      );
    }
  }

  Future<BgpAsnResult> _lookupIp(String ip) async {
    final Map<String, dynamic> net = await _get('network-info', ip);
    final Map<String, dynamic> data = _dataOf(net);
    final String? prefix = _str(data['prefix']);
    final List<String> asns = _strList(data['asns']);
    final String? asn = asns.isEmpty ? null : _asnLabel(asns.first);

    String? holder;
    String? country;
    String? registry;
    String? asnType;
    bool? announced;
    if (asn != null) {
      final BgpAsnResult ov = await _asOverview(asns.first);
      holder = ov.holder;
      country = ov.country;
      registry = ov.registry;
      asnType = ov.asnType;
      announced = ov.isAnnounced;
    }

    return BgpAsnResult.success(
      query: ip,
      kind: BgpQueryKind.ip,
      asn: asn,
      holder: holder,
      announcedPrefix: prefix,
      country: country,
      registry: registry,
      asnType: asnType,
      isAnnounced: announced,
      relatedAsns:
          asns.length > 1 ? asns.skip(1).map(_asnLabel).toList() : const [],
    );
  }

  Future<BgpAsnResult> _lookupAsn(String rawAsn) async {
    final int n = _asnNumber(rawAsn)!;
    final BgpAsnResult ov = await _asOverview('$n');

    int? up;
    int? peer;
    int? down;
    try {
      final Map<String, dynamic> nb = await _get('asn-neighbours', 'AS$n');
      final Map<String, dynamic> data = _dataOf(nb);
      final List<dynamic> neighbours =
          (data['neighbours'] as List<dynamic>?) ?? const <dynamic>[];
      int u = 0, p = 0, d = 0;
      for (final dynamic e in neighbours) {
        if (e is Map<String, dynamic>) {
          switch (_str(e['type'])) {
            case 'left':
              u++;
            case 'right':
              d++;
            case 'unknown':
              p++;
          }
        }
      }
      up = u;
      down = d;
      peer = p;
    } on JsonHttpException {
      // Neighbours are best-effort enrichment; a failure here leaves the counts
      // null (rendered "Not available") rather than failing the whole lookup.
    }

    return BgpAsnResult.success(
      query: rawAsn,
      kind: BgpQueryKind.asn,
      asn: 'AS$n',
      holder: ov.holder,
      country: ov.country,
      registry: ov.registry,
      asnType: ov.asnType,
      isAnnounced: ov.isAnnounced,
      announcedPrefix: ov.announcedPrefix,
      upstreamCount: up,
      peerCount: peer,
      downstreamCount: down,
    );
  }

  /// Fetch + parse as-overview for a bare ASN string. Returns a partial result
  /// carrying only the overview fields (the callers merge them).
  Future<BgpAsnResult> _asOverview(String asnNumber) async {
    final Map<String, dynamic> ov =
        await _get('as-overview', 'AS$asnNumber');
    final Map<String, dynamic> data = _dataOf(ov);
    return BgpAsnResult.success(
      query: asnNumber,
      kind: BgpQueryKind.asn,
      asn: _asnLabel(asnNumber),
      holder: _str(data['holder']),
      asnType: _str(data['type']),
      isAnnounced: data['announced'] is bool ? data['announced'] as bool : null,
      registry: _str(data['resource'])?.startsWith('AS') == true
          ? _str(data['block']?['resource']) ?? _str(_blockName(data))
          : _str(_blockName(data)),
      country: null,
    );
  }

  // RIPEstat as-overview nests RIR info under "block": {"name": "...", "desc":
  // "RIPE NCC ..."}. We surface the human "desc"/"name" as the registry.
  static String? _blockName(Map<String, dynamic> data) {
    final Object? block = data['block'];
    if (block is Map<String, dynamic>) {
      return _str(block['desc']) ?? _str(block['name']);
    }
    return null;
  }

  /// Parse the RIPEstat JSON-API parsing helpers exposed for tests.
  static Map<String, dynamic> _dataOf(Map<String, dynamic> json) {
    final Object? data = json['data'];
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  /// Build a RIPEstat parsed result directly from a decoded JSON map. Exposed
  /// for unit tests (no network).
  static BgpAsnResult parseAsOverview(
    Map<String, dynamic> json, {
    required String asnNumber,
  }) {
    final Map<String, dynamic> data = _dataOf(json);
    return BgpAsnResult.success(
      query: asnNumber,
      kind: BgpQueryKind.asn,
      asn: _asnLabel(asnNumber),
      holder: _str(data['holder']),
      asnType: _str(data['type']),
      isAnnounced: data['announced'] is bool ? data['announced'] as bool : null,
      registry: _blockName(data),
    );
  }

  /// Parse a network-info response (IP path) into the prefix + ASNs. Exposed
  /// for tests.
  static ({String? prefix, List<String> asns}) parseNetworkInfo(
    Map<String, dynamic> json,
  ) {
    final Map<String, dynamic> data = _dataOf(json);
    return (prefix: _str(data['prefix']), asns: _strList(data['asns']));
  }

  static String _asnLabel(String n) {
    final String t = n.trim().toUpperCase();
    return t.startsWith('AS') ? t : 'AS$t';
  }

  Future<Map<String, dynamic>> _get(String endpoint, String resource) {
    final Uri uri = Uri.parse(
      '$_base/$endpoint/data.json?resource=${Uri.encodeQueryComponent(resource)}&sourceapp=wlanprostoolbox',
    );
    return _client.getJson(uri.toString());
  }

  static String? _str(Object? v) {
    if (v == null) return null;
    final String s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static List<String> _strList(Object? v) {
    if (v is! List) return const <String>[];
    return v
        .map((Object? e) => e?.toString().trim() ?? '')
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
  }
}
