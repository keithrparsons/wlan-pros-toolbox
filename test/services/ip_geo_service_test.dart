// IpGeoService unit tests — ipinfo.io primary + geojs.io fallback parsing, the
// provider-fallback strategy (ipinfo no-coords / ipinfo error → geojs), the
// org/loc/ASN parsing, coordinate/map-URL derivation, and the transport error
// taxonomy via the injectable JsonFetcher seam (no network).
//
// Provider swap (2026-06): ipwho.is dropped (it resolved to the ISP registry /
// datacenter location, empirically wrong); ipinfo.io + geojs.io both locate the
// real egress and agree. Both are keyless + HTTPS.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ip_geo_service.dart';
import 'package:wlan_pros_toolbox/services/network/json_http_client.dart';

JsonFetcher fixed(Map<String, dynamic> body) =>
    (Uri url, Duration timeout) async => body;

JsonFetcher throwing(JsonHttpException e) =>
    (Uri url, Duration timeout) async => throw e;

/// Routes by host so a single client can serve ipinfo.io and geojs.io different
/// bodies — the seam the fallback strategy needs to be exercised end to end.
JsonFetcher routed({
  Map<String, dynamic>? ipinfo,
  Map<String, dynamic>? geojs,
  JsonHttpException? ipinfoThrows,
  JsonHttpException? geojsThrows,
}) {
  return (Uri url, Duration timeout) async {
    final bool isIpinfo = url.host.contains('ipinfo');
    if (isIpinfo) {
      if (ipinfoThrows != null) throw ipinfoThrows;
      return ipinfo ?? <String, dynamic>{};
    }
    if (geojsThrows != null) throw geojsThrows;
    return geojs ?? <String, dynamic>{};
  };
}

Map<String, dynamic> _ipinfoBody() => <String, dynamic>{
      'ip': '8.8.8.8',
      'city': 'Mountain View',
      'region': 'California',
      'country': 'US',
      'loc': '37.4224,-122.0842',
      'org': 'AS15169 Google LLC',
      'postal': '94043',
      'timezone': 'America/Los_Angeles',
    };

Map<String, dynamic> _geojsBody() => <String, dynamic>{
      'ip': '8.8.8.8',
      'country': 'United States',
      'country_code': 'US',
      'region': 'California',
      'city': 'Mountain View',
      'latitude': '37.4224',
      'longitude': '-122.0842',
      'accuracy': 5,
      'organization_name': 'Google LLC',
      'organization': 'AS15169 Google LLC',
      'asn': 15169,
      'timezone': 'America/Los_Angeles',
    };

void main() {
  group('parseIpinfo — success', () {
    test('maps every field, splitting loc and org', () {
      final IpGeoResult r =
          IpGeoService.parseIpinfo(_ipinfoBody(), query: '8.8.8.8');
      expect(r.isError, isFalse);
      expect(r.provider, IpGeoProvider.ipinfo);
      expect(r.ip, '8.8.8.8');
      expect(r.ipVersion, 'IPv4');
      expect(r.city, 'Mountain View');
      expect(r.region, 'California');
      expect(r.country, 'US');
      expect(r.postal, '94043');
      expect(r.latitude, closeTo(37.4224, 0.0001));
      expect(r.longitude, closeTo(-122.0842, 0.0001));
      expect(r.timezone, 'America/Los_Angeles');
      expect(r.isp, 'Google LLC');
      expect(r.org, 'Google LLC');
      expect(r.asn, 'AS15169');
    });

    test('locationLine, coordinatePair, mapsUrl derive correctly', () {
      final IpGeoResult r =
          IpGeoService.parseIpinfo(_ipinfoBody(), query: '8.8.8.8');
      expect(r.locationLine, 'Mountain View, California, US');
      expect(r.hasCoordinates, isTrue);
      expect(r.coordinatePair, '37.422400,-122.084200');
      expect(r.mapsUrl, contains('openstreetmap.org'));
      expect(r.mapsUrl, contains('mlat=37.4224'));
    });

    test('org without a leading AS number → name only, null ASN', () {
      final IpGeoResult r = IpGeoService.parseIpinfo(
        <String, dynamic>{
          'ip': '1.1.1.1',
          'org': 'Cloudflare, Inc.',
          'loc': '-33.8688,151.2093',
        },
        query: '1.1.1.1',
      );
      expect(r.asn, isNull);
      expect(r.org, 'Cloudflare, Inc.');
      expect(r.latitude, closeTo(-33.8688, 0.0001));
    });

    test('missing loc → null coordinates, not fabricated', () {
      final IpGeoResult r = IpGeoService.parseIpinfo(
        <String, dynamic>{'ip': '1.1.1.1', 'country': 'AU'},
        query: '1.1.1.1',
      );
      expect(r.hasCoordinates, isFalse);
      expect(r.coordinatePair, isNull);
      expect(r.mapsUrl, isNull);
      expect(r.asn, isNull);
    });

    test('IPv6 address is detected from shape', () {
      final IpGeoResult r = IpGeoService.parseIpinfo(
        <String, dynamic>{
          'ip': '2001:4860:4860::8888',
          'loc': '37.4,-122.0',
        },
        query: '2001:4860:4860::8888',
      );
      expect(r.ipVersion, 'IPv6');
    });

    test('error object → input-rejection failure with null kind', () {
      final IpGeoResult r = IpGeoService.parseIpinfo(
        <String, dynamic>{
          'error': <String, dynamic>{
            'title': 'Wrong ip',
            'message': 'Please provide a valid IP address',
          },
        },
        query: 'bogus',
      );
      expect(r.isError, isTrue);
      expect(r.errorKind, isNull);
      expect(r.errorMessage, contains('bogus'));
    });
  });

  group('parseGeojs — success', () {
    test('maps every field, coercing string lat/long and int asn', () {
      final IpGeoResult r =
          IpGeoService.parseGeojs(_geojsBody(), query: '8.8.8.8');
      expect(r.isError, isFalse);
      expect(r.provider, IpGeoProvider.geojs);
      expect(r.ip, '8.8.8.8');
      expect(r.city, 'Mountain View');
      expect(r.region, 'California');
      expect(r.country, 'United States');
      expect(r.countryCode, 'US');
      expect(r.latitude, closeTo(37.4224, 0.0001));
      expect(r.longitude, closeTo(-122.0842, 0.0001));
      expect(r.asn, 'AS15169');
      expect(r.org, 'Google LLC');
      expect(r.timezone, 'America/Los_Angeles');
    });

    test('numeric lat/long are accepted too', () {
      final IpGeoResult r = IpGeoService.parseGeojs(
        <String, dynamic>{
          'ip': '9.9.9.9',
          'latitude': 40.0,
          'longitude': -75.0,
        },
        query: '9.9.9.9',
      );
      expect(r.latitude, 40.0);
      expect(r.longitude, -75.0);
    });

    test('missing org/asn → null, not fabricated', () {
      final IpGeoResult r = IpGeoService.parseGeojs(
        <String, dynamic>{'ip': '1.1.1.1', 'country': 'Australia'},
        query: '1.1.1.1',
      );
      expect(r.asn, isNull);
      expect(r.org, isNull);
      expect(r.hasCoordinates, isFalse);
    });
  });

  group('isPlausibleQuery — client-side pre-validation', () {
    test('accepts IPv4, IPv6, and dotted hostnames', () {
      expect(IpGeoService.isPlausibleQuery('8.8.8.8'), isTrue);
      expect(IpGeoService.isPlausibleQuery('1.1.1.1'), isTrue);
      expect(IpGeoService.isPlausibleQuery('2001:4860:4860::8888'), isTrue);
      expect(IpGeoService.isPlausibleQuery('example.com'), isTrue);
      expect(IpGeoService.isPlausibleQuery('sub.example.co.uk'), isTrue);
      expect(IpGeoService.isPlausibleQuery('  8.8.8.8  '), isTrue);
    });

    test('rejects whitespace, junk, out-of-range octets, bare labels', () {
      expect(IpGeoService.isPlausibleQuery('my computer'), isFalse);
      expect(IpGeoService.isPlausibleQuery('????'), isFalse);
      expect(IpGeoService.isPlausibleQuery('999.999.999.999'), isFalse);
      expect(IpGeoService.isPlausibleQuery('256.1.1.1'), isFalse);
      expect(IpGeoService.isPlausibleQuery('localhost'), isFalse);
      expect(IpGeoService.isPlausibleQuery('8.8.8'), isFalse);
    });
  });

  group('lookup — provider strategy', () {
    test('ipinfo success with coords is used; geojs not consulted', () async {
      bool geojsHit = false;
      final IpGeoService svc = IpGeoService(
        client: JsonHttpClient(
          fetcher: (Uri url, Duration timeout) async {
            if (url.host.contains('geojs')) geojsHit = true;
            return _ipinfoBody();
          },
        ),
      );
      final IpGeoResult r = await svc.lookup(rawQuery: '8.8.8.8');
      expect(r.isError, isFalse);
      expect(r.provider, IpGeoProvider.ipinfo);
      expect(geojsHit, isFalse, reason: 'primary sufficed; no fallback call');
    });

    test('empty query labels result as my IP and hits ipinfo self endpoint',
        () async {
      Uri? seen;
      final IpGeoService svc = IpGeoService(
        client: JsonHttpClient(
          fetcher: (Uri url, Duration timeout) async {
            seen = url;
            return _ipinfoBody();
          },
        ),
      );
      final IpGeoResult r = await svc.lookup(rawQuery: '');
      expect(r.isError, isFalse);
      expect(r.query, '(my IP)');
      expect(seen?.host, contains('ipinfo'));
      expect(seen?.path, '/json');
    });

    test('ipinfo error (transport) → falls back to geojs', () async {
      final IpGeoService svc = IpGeoService(
        client: JsonHttpClient(
          fetcher: routed(
            ipinfoThrows: const JsonHttpException(
              JsonHttpErrorKind.transport,
              'no route to host',
            ),
            geojs: _geojsBody(),
          ),
        ),
      );
      final IpGeoResult r = await svc.lookup(rawQuery: '8.8.8.8');
      expect(r.isError, isFalse);
      expect(r.provider, IpGeoProvider.geojs);
      expect(r.hasCoordinates, isTrue);
    });

    test('ipinfo success but no loc → falls back to geojs for coordinates',
        () async {
      final IpGeoService svc = IpGeoService(
        client: JsonHttpClient(
          fetcher: routed(
            ipinfo: <String, dynamic>{'ip': '8.8.8.8', 'country': 'US'},
            geojs: _geojsBody(),
          ),
        ),
      );
      final IpGeoResult r = await svc.lookup(rawQuery: '8.8.8.8');
      expect(r.provider, IpGeoProvider.geojs);
      expect(r.hasCoordinates, isTrue);
    });

    test('both providers fail → honest failure, no fabricated coordinate',
        () async {
      final IpGeoService svc = IpGeoService(
        client: JsonHttpClient(
          fetcher: routed(
            ipinfoThrows: const JsonHttpException(
              JsonHttpErrorKind.timeout,
              'ipinfo timed out',
            ),
            geojsThrows: const JsonHttpException(
              JsonHttpErrorKind.transport,
              'geojs unreachable',
            ),
          ),
        ),
      );
      final IpGeoResult r = await svc.lookup(rawQuery: '8.8.8.8');
      expect(r.isError, isTrue);
      expect(r.hasCoordinates, isFalse);
      // The last attempt (geojs) is surfaced.
      expect(r.errorKind, JsonHttpErrorKind.transport);
    });

    test('invalid input is rejected before any network call', () async {
      bool fetched = false;
      final IpGeoService svc = IpGeoService(
        client: JsonHttpClient(
          fetcher: (Uri url, Duration timeout) async {
            fetched = true;
            return _ipinfoBody();
          },
        ),
      );
      final IpGeoResult r = await svc.lookup(rawQuery: 'not an ip');
      expect(fetched, isFalse, reason: 'must short-circuit before fetching');
      expect(r.isError, isTrue);
      expect(r.errorKind, isNull, reason: 'null kind = check your input');
      expect(r.errorMessage, contains('IP address or hostname'));
    });

    test('ipinfo input-rejection (null kind) does not trigger a fallback',
        () async {
      bool geojsHit = false;
      final IpGeoService svc = IpGeoService(
        client: JsonHttpClient(
          fetcher: (Uri url, Duration timeout) async {
            if (url.host.contains('geojs')) geojsHit = true;
            return <String, dynamic>{
              'error': <String, dynamic>{
                'title': 'Wrong ip',
                'message': 'invalid',
              },
            };
          },
        ),
      );
      final IpGeoResult r = await svc.lookup(rawQuery: '203.0.113.1');
      expect(r.isError, isTrue);
      expect(r.errorKind, isNull);
      expect(geojsHit, isFalse, reason: 'input rejection short-circuits');
    });
  });
}
