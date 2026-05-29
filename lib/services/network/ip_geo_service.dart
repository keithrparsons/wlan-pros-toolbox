// IpGeoService — IP geolocation over the ipwho.is API.
//
// API CHOICE: ipwho.is (https://ipwho.is/{ip} and https://ipwho.is/ for "my IP")
//  - Free, NO API key, HTTPS. (https mandatory — ip-api.com's free tier is
//    HTTP-only and would be blocked by iOS App Transport Security, so it is
//    explicitly NOT used.)
//  - One call returns everything the brief asks for: country/region/city,
//    lat/long, timezone, ISP/org/connection, and ASN — no second request.
//  - Signals failure in-band with {"success": false, "message": "..."}, which
//    we map to a clear error/rate-limit state rather than reading a 200 as OK.
//  - ipapi.co and ipinfo.io were the alternatives; ipwho.is was chosen because
//    it is keyless AND returns ASN + timezone in the same free response, while
//    ipapi.co splits some of that behind paid tiers and ipinfo.io's lite tier
//    needs a token for ASN. ipwho.is keeps us keyless with full coverage.
//
// "MY IP": an empty query hits https://ipwho.is/ (no path) which geolocates the
// caller's public IP — the default the brief asks for.
//
// MAP: a full interactive map is out of scope this session. The screen shows
// lat/long as selectable mono data plus a copyable "lat,long" string and an
// external maps URL ([mapsUrl]) the user can open. Interactive map = future.
//
// WEB: built on JsonHttpClient → dart:io, native-only; the screen gates web to
// NetworkUnavailableView (we did not verify ipwho.is CORS, so no maybe-broken
// browser tool).
//
// HONESTY: every field is nullable; missing data renders "Not available".

import 'json_http_client.dart';

/// Structured geolocation result. Success carries the populated fields;
/// failure carries [errorMessage] (+ [errorKind] for branching).
class IpGeoResult {
  const IpGeoResult._({
    required this.query,
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

  static const String _base = 'https://ipwho.is';

  /// Look up [rawQuery]; an empty query geolocates the caller's public IP.
  /// Never throws — failures come back as [IpGeoResult.failure].
  Future<IpGeoResult> lookup({required String rawQuery}) async {
    final String query = rawQuery.trim();
    final String url = query.isEmpty
        ? '$_base/'
        : '$_base/${Uri.encodeComponent(query)}';
    try {
      final Map<String, dynamic> json = await _client.getJson(url);
      return parse(json, query: query.isEmpty ? '(my IP)' : query);
    } on JsonHttpException catch (e) {
      return IpGeoResult.failure(
        query: query.isEmpty ? '(my IP)' : query,
        message: e.message,
        errorKind: e.kind,
      );
    }
  }

  /// Parse an ipwho.is JSON body into a result. Honors the in-band
  /// `success:false` failure shape (used for invalid IPs / rate limits).
  /// Exposed for unit tests — no network.
  static IpGeoResult parse(Map<String, dynamic> json, {required String query}) {
    final Object? success = json['success'];
    if (success == false) {
      final String? msg = _str(json['message']);
      final bool rateLimited =
          (msg ?? '').toLowerCase().contains('rate') ||
              (msg ?? '').toLowerCase().contains('limit');
      return IpGeoResult.failure(
        query: query,
        message: rateLimited
            ? 'The geolocation API is rate-limiting requests. Wait a minute '
                'and try again.'
            : (msg ?? 'The geolocation API could not resolve that IP.'),
        errorKind: rateLimited
            ? JsonHttpErrorKind.rateLimited
            : JsonHttpErrorKind.httpStatus,
      );
    }

    final Map<String, dynamic> conn = _mapOf(json['connection']);
    final Map<String, dynamic> tz = _mapOf(json['timezone']);
    final String? asnRaw = _str(conn['asn']);

    return IpGeoResult.success(
      query: query,
      ip: _str(json['ip']),
      ipVersion: _str(json['type']),
      country: _str(json['country']),
      countryCode: _str(json['country_code']),
      region: _str(json['region']),
      city: _str(json['city']),
      postal: _str(json['postal']),
      latitude: _num(json['latitude']),
      longitude: _num(json['longitude']),
      timezone: _str(tz['id']),
      utcOffset: _str(tz['utc']),
      isp: _str(conn['isp']),
      org: _str(conn['org']),
      asn: asnRaw == null ? null : _asnLabel(asnRaw),
      asnName: _str(conn['org']) ?? _str(conn['isp']),
    );
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
