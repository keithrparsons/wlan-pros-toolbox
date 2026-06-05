// IpGeoService — IP geolocation over ipinfo.io (primary) + geojs.io (fallback).
//
// API CHOICE (revised): ipinfo.io primary, get.geojs.io fallback. Both are
// free, keyless/unauthenticated, and HTTPS — so they clear iOS App Transport
// Security and GL-008's "HTTPS, keyless" rule. We dropped ipwho.is because it
// resolves to the ISP's registry/datacenter location (empirically wrong: it put
// a Utah egress in Virginia), while BOTH ipinfo.io and geojs.io correctly locate
// the real physical egress and agree on coordinates. ip-api.com is also accurate
// but its free tier is non-commercial-only, so it is explicitly NOT used.
//
//   ipinfo.io
//     self        → https://ipinfo.io/json
//     specific IP → https://ipinfo.io/{ip}/json
//     JSON: {ip, city, region, country, loc:"lat,lng", org:"AS396325 Name…",
//            postal, timezone}. `loc` is split into lat/lon; `org` is parsed
//            into an ASN ("AS396325") + org/ISP name ("Fusion Networks…").
//
//   geojs.io
//     self        → https://get.geojs.io/v1/ip/geo.json
//     specific IP → https://get.geojs.io/v1/ip/geo/{ip}.json
//     JSON: {ip, country, country_code, region, city, latitude, longitude,
//            accuracy, organization_name, organization, asn, timezone}.
//
// LOGIC: try ipinfo first; if it throws (timeout / rate-limit / transport /
// bad-JSON) OR returns no usable lat/lon, fall back to geojs. If BOTH fail,
// return an honest [IpGeoResult.failure] — never a fabricated coordinate
// (GL-005). The failure carried back is geojs's (the last word), so the user
// sees the most recent real error.
//
// "MY IP": an empty query hits each provider's self endpoint, geolocating the
// caller's public egress IP — the default the brief asks for.
//
// MAP: a full interactive map is out of scope this session. The screen shows
// lat/long as selectable mono data plus a copyable "lat,long" string and an
// external maps URL ([mapsUrl]) the user can open.
//
// WEB: built on JsonHttpClient → dart:io, native-only; the screen gates web to
// NetworkUnavailableView.
//
// HONESTY: every field is nullable; a field a provider does not return renders
// "Not available". Nothing is invented.

import 'json_http_client.dart';

/// Which provider produced a result, so callers/tests can reason about the
/// source and the screen can stay honest about provenance if it ever needs to.
enum IpGeoProvider {
  /// ipinfo.io — the primary, accurate-egress provider.
  ipinfo,

  /// get.geojs.io — the fallback, also accurate-egress.
  geojs,
}

/// Structured geolocation result. Success carries the populated fields;
/// failure carries [errorMessage] (+ [errorKind] for branching).
class IpGeoResult {
  const IpGeoResult._({
    required this.query,
    this.provider,
    this.ip,
    this.ipVersion,
    this.country,
    this.countryCode,
    this.region,
    this.city,
    this.postal,
    this.latitude,
    this.longitude,
    this.timezone,
    this.utcOffset,
    this.isp,
    this.org,
    this.asn,
    this.asnName,
    this.errorMessage,
    this.errorKind,
  });

  factory IpGeoResult.success({
    required String query,
    required IpGeoProvider provider,
    String? ip,
    String? ipVersion,
    String? country,
    String? countryCode,
    String? region,
    String? city,
    String? postal,
    double? latitude,
    double? longitude,
    String? timezone,
    String? utcOffset,
    String? isp,
    String? org,
    String? asn,
    String? asnName,
  }) =>
      IpGeoResult._(
        query: query,
        provider: provider,
        ip: ip,
        ipVersion: ipVersion,
        country: country,
        countryCode: countryCode,
        region: region,
        city: city,
        postal: postal,
        latitude: latitude,
        longitude: longitude,
        timezone: timezone,
        utcOffset: utcOffset,
        isp: isp,
        org: org,
        asn: asn,
        asnName: asnName,
      );

  factory IpGeoResult.failure({
    required String query,
    required String message,
    JsonHttpErrorKind? errorKind,
  }) =>
      IpGeoResult._(
        query: query,
        errorMessage: message,
        errorKind: errorKind,
      );

  final String query;

  /// Which provider produced a successful result; null on failure.
  final IpGeoProvider? provider;

  final String? ip;
  final String? ipVersion;
  final String? country;
  final String? countryCode;
  final String? region;
  final String? city;
  final String? postal;
  final double? latitude;
  final double? longitude;
  final String? timezone;
  final String? utcOffset;
  final String? isp;
  final String? org;
  final String? asn;
  final String? asnName;

  final String? errorMessage;
  final JsonHttpErrorKind? errorKind;

  bool get isError => errorMessage != null;

  bool get hasCoordinates => latitude != null && longitude != null;

  /// "lat,long" — the copyable coordinate string for the "view on map"
  /// affordance, or null when coordinates are missing.
  String? get coordinatePair => hasCoordinates
      ? '${latitude!.toStringAsFixed(6)},${longitude!.toStringAsFixed(6)}'
      : null;

  /// An external maps URL the user can open (OpenStreetMap — keyless, no
  /// tracking redirect). Null when coordinates are missing.
  String? get mapsUrl => hasCoordinates
      ? 'https://www.openstreetmap.org/?mlat=${latitude!}&mlon=${longitude!}#map=12/${latitude!}/${longitude!}'
      : null;

  /// A one-line "City, Region, Country" summary, omitting missing parts.
  String? get locationLine {
    final List<String> parts = <String>[
      ?city,
      ?region,
      ?country,
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }
}

class IpGeoService {
  IpGeoService({JsonHttpClient? client}) : _client = client ?? JsonHttpClient();

  final JsonHttpClient _client;

  static const String _ipinfoBase = 'https://ipinfo.io';
  static const String _geojsBase = 'https://get.geojs.io/v1/ip/geo';

  /// Look up [rawQuery]; an empty query geolocates the caller's public IP.
  /// Never throws — failures come back as [IpGeoResult.failure].
  ///
  /// Provider strategy: ipinfo.io first; if it errors, rate-limits, or returns
  /// no usable lat/lon, fall back to geojs.io. If both fail, the geojs failure
  /// (the last attempt) is returned. A coordinate is never fabricated.
  Future<IpGeoResult> lookup({required String rawQuery}) async {
    final String query = rawQuery.trim();

    // Pre-validate non-empty input before spending a network round-trip on a
    // value that can't be an IP or a hostname. A client-side rejection carries
    // a null [errorKind], which the shared error card renders as the
    // "Check your input" state — distinct from a real network/API failure.
    if (query.isNotEmpty && !_looksLikeIpOrHost(query)) {
      return IpGeoResult.failure(
        query: query,
        message: 'That does not look like an IP address or hostname. '
            'Enter something like 8.8.8.8, 2001:4860:4860::8888, or '
            'example.com — or leave it blank to locate your own IP.',
        // null kind == client-side input rejection.
      );
    }

    final String label = query.isEmpty ? '(my IP)' : query;

    // ─── Primary: ipinfo.io ──────────────────────────────────────────────
    final IpGeoResult primary = await _tryIpinfo(query: query, label: label);
    // A *usable* primary result is a non-error WITH coordinates. ipinfo can
    // 200 with city-level text but no `loc` for some addresses; treat that as
    // "no usable lat/lon" and fall through to geojs rather than ship a
    // coordinate-less result when a second provider might have one.
    if (!primary.isError && primary.hasCoordinates) {
      return primary;
    }
    // An input-rejection from the primary (null kind, e.g. an address geojs
    // would also reject) is not worth a second round-trip — surface it.
    if (primary.isError && primary.errorKind == null) {
      return primary;
    }

    // ─── Fallback: geojs.io ──────────────────────────────────────────────
    final IpGeoResult fallback = await _tryGeojs(query: query, label: label);
    if (!fallback.isError && fallback.hasCoordinates) {
      return fallback;
    }

    // Neither produced a usable located result. Prefer to return a real error.
    // If the fallback errored, surface it (the user's latest real failure). If
    // the fallback merely lacked coordinates but the primary succeeded without
    // them, return the primary so at least the textual fields render.
    if (fallback.isError) {
      if (!primary.isError) return primary; // primary had partial data.
      return fallback;
    }
    return fallback; // located-less success — fields without coordinates.
  }

  Future<IpGeoResult> _tryIpinfo({
    required String query,
    required String label,
  }) async {
    final String url = query.isEmpty
        ? '$_ipinfoBase/json'
        : '$_ipinfoBase/${Uri.encodeComponent(query)}/json';
    try {
      final Map<String, dynamic> json = await _client.getJson(url);
      return parseIpinfo(json, query: label);
    } on JsonHttpException catch (e) {
      return IpGeoResult.failure(
        query: label,
        message: e.message,
        errorKind: e.kind,
      );
    }
  }

  Future<IpGeoResult> _tryGeojs({
    required String query,
    required String label,
  }) async {
    final String url = query.isEmpty
        ? '$_geojsBase.json'
        : '$_geojsBase/${Uri.encodeComponent(query)}.json';
    try {
      final Map<String, dynamic> json = await _client.getJson(url);
      return parseGeojs(json, query: label);
    } on JsonHttpException catch (e) {
      return IpGeoResult.failure(
        query: label,
        message: e.message,
        errorKind: e.kind,
      );
    }
  }

  /// Parse an ipinfo.io JSON body into a result. ipinfo signals a bad address
  /// with an `error` object (or an HTTP status the client already mapped), and
  /// returns `loc:"lat,lng"` + `org:"AS#### Name"` on success. Exposed for unit
  /// tests — no network.
  static IpGeoResult parseIpinfo(
    Map<String, dynamic> json, {
    required String query,
  }) {
    // ipinfo answers 200 + {"error": {...}} for a bogus/unroutable address.
    final Object? error = json['error'];
    if (error != null) {
      final Map<String, dynamic> em = _mapOf(error);
      final String? title = _str(em['title']);
      final String? message = _str(em['message']);
      return IpGeoResult.failure(
        query: query,
        message: 'The address "$query" could not be located'
            '${title != null ? ' ($title)' : ''}'
            '${message != null ? ': $message' : ''}. '
            'Check that it is a valid IP address or hostname and try again.',
        // null kind == treat as an input rejection (the API understood us,
        // the address is just not locatable).
      );
    }

    final (double? lat, double? lon) = _splitLoc(_str(json['loc']));
    final (String? asn, String? orgName) = _splitOrg(_str(json['org']));

    return IpGeoResult.success(
      query: query,
      provider: IpGeoProvider.ipinfo,
      ip: _str(json['ip']),
      // ipinfo does not return an explicit IP version; infer it cheaply from
      // the address shape rather than inventing a label.
      ipVersion: _ipVersionOf(_str(json['ip'])),
      country: _str(json['country']),
      countryCode: _str(json['country']), // ipinfo's `country` IS the code.
      region: _str(json['region']),
      city: _str(json['city']),
      postal: _str(json['postal']),
      latitude: lat,
      longitude: lon,
      timezone: _str(json['timezone']),
      // ipinfo's free tier does not return a UTC offset string.
      utcOffset: null,
      isp: orgName,
      org: orgName,
      asn: asn,
      asnName: orgName,
    );
  }

  /// Parse a geojs.io JSON body into a result. geojs returns numeric (or
  /// numeric-string) `latitude`/`longitude`, an `asn` integer, and the org name
  /// in `organization_name`/`organization`. Exposed for unit tests — no network.
  static IpGeoResult parseGeojs(
    Map<String, dynamic> json, {
    required String query,
  }) {
    final double? lat = _num(json['latitude']);
    final double? lon = _num(json['longitude']);
    final String? orgName =
        _str(json['organization_name']) ?? _str(json['organization']);
    final String? asnRaw = _str(json['asn']);

    return IpGeoResult.success(
      query: query,
      provider: IpGeoProvider.geojs,
      ip: _str(json['ip']),
      ipVersion: _ipVersionOf(_str(json['ip'])),
      country: _str(json['country']),
      countryCode: _str(json['country_code']),
      region: _str(json['region']),
      city: _str(json['city']),
      // geojs does not return a postal code in the geo response.
      postal: null,
      latitude: lat,
      longitude: lon,
      timezone: _str(json['timezone']),
      utcOffset: null,
      isp: orgName,
      org: orgName,
      asn: asnRaw == null ? null : _asnLabel(asnRaw),
      asnName: orgName,
    );
  }

  /// Cheap client-side sanity check: does [query] plausibly look like an IPv4
  /// address, an IPv6 address, or a DNS hostname? This is a pre-filter to avoid
  /// a wasted round-trip on obvious junk (spaces, "????", "my computer"), NOT a
  /// strict validator — the providers remain the authority on resolvability.
  /// Exposed for unit tests.
  static bool isPlausibleQuery(String query) => _looksLikeIpOrHost(query.trim());

  // ─── Parsing helpers ──────────────────────────────────────────────────────

  /// Split ipinfo's `loc:"lat,lng"` into a typed pair. Returns (null, null)
  /// when absent or malformed — never a partial/invented coordinate.
  static (double?, double?) _splitLoc(String? loc) {
    if (loc == null) return (null, null);
    final List<String> parts = loc.split(',');
    if (parts.length != 2) return (null, null);
    final double? lat = double.tryParse(parts[0].trim());
    final double? lon = double.tryParse(parts[1].trim());
    if (lat == null || lon == null) return (null, null);
    return (lat, lon);
  }

  /// Split ipinfo's `org:"AS#### Name…"` into (asn, name). When the string does
  /// not lead with an AS number, the whole value is the name and the ASN is
  /// null. Returns (null, null) when the field is absent.
  static (String?, String?) _splitOrg(String? org) {
    if (org == null) return (null, null);
    final RegExpMatch? m =
        RegExp(r'^(AS\d+)\s+(.*)$', caseSensitive: false).firstMatch(org);
    if (m == null) {
      // No leading AS number — the whole field is the org/ISP name.
      return (null, org);
    }
    final String asn = m.group(1)!.toUpperCase();
    final String name = m.group(2)!.trim();
    return (asn, name.isEmpty ? null : name);
  }

  /// IPv4 vs IPv6 from the address shape, or null when the IP is absent. A
  /// colon means IPv6; four dotted octets means IPv4. We do not invent a label
  /// for anything that matches neither.
  static String? _ipVersionOf(String? ip) {
    if (ip == null) return null;
    if (ip.contains(':')) return 'IPv6';
    if (_isIpv4(ip)) return 'IPv4';
    return null;
  }

  static bool _looksLikeIpOrHost(String q) {
    if (q.isEmpty || q.length > 253) return false;
    // No whitespace anywhere in a real IP or hostname.
    if (RegExp(r'\s').hasMatch(q)) return false;
    if (_isIpv4(q)) return true;
    // IPv6: hex groups and colons (optionally a zone/scope id). Loose by design.
    if (q.contains(':') && RegExp(r'^[0-9a-fA-F:]+(%[0-9a-zA-Z]+)?$').hasMatch(q)) {
      return true;
    }
    // Hostname: dot-separated labels, alphanumerics + hyphen, must contain a dot
    // (a bare single label like "localhost" isn't geolocatable via the API).
    return RegExp(
      r'^(?=.{1,253}$)([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+'
      r'[a-zA-Z]{2,}$',
    ).hasMatch(q);
  }

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

  static String _asnLabel(String n) {
    final String t = n.trim().toUpperCase();
    return t.startsWith('AS') ? t : 'AS$t';
  }

  static Map<String, dynamic> _mapOf(Object? v) =>
      v is Map<String, dynamic> ? v : <String, dynamic>{};

  static String? _str(Object? v) {
    if (v == null) return null;
    final String s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static double? _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }
}
