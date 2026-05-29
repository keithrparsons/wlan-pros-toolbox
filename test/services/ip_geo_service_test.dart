// IpGeoService unit tests — ipwho.is JSON parsing, the in-band success:false
// failure/rate-limit shape, coordinate/map-URL derivation, and the transport
// error taxonomy via the injectable JsonFetcher seam (no network).

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ip_geo_service.dart';
import 'package:wlan_pros_toolbox/services/network/json_http_client.dart';

JsonFetcher fixed(Map<String, dynamic> body) =>
    (Uri url, Duration timeout) async => body;

JsonFetcher throwing(JsonHttpException e) =>
    (Uri url, Duration timeout) async => throw e;

Map<String, dynamic> _fullBody() => <String, dynamic>{
      'ip': '8.8.8.8',
      'success': true,
      'type': 'IPv4',
      'country': 'United States',
      'country_code': 'US',
      'region': 'California',
      'city': 'Mountain View',
      'postal': '94043',
      'latitude': 37.42240,
      'longitude': -122.08421,
      'connection': <String, dynamic>{
        'asn': 15169,
        'org': 'Google LLC',
        'isp': 'Google LLC',
      },
      'timezone': <String, dynamic>{
        'id': 'America/Los_Angeles',
        'utc': '-07:00',
      },
    };

void main() {
  group('parse — success', () {
    test('maps every field from a full body', () {
      final IpGeoResult r = IpGeoService.parse(_fullBody(), query: '8.8.8.8');
      expect(r.isError, isFalse);
      expect(r.ip, '8.8.8.8');
      expect(r.ipVersion, 'IPv4');
      expect(r.city, 'Mountain View');
      expect(r.region, 'California');
      expect(r.country, 'United States');
      expect(r.postal, '94043');
      expect(r.latitude, closeTo(37.4224, 0.0001));
      expect(r.longitude, closeTo(-122.08421, 0.0001));
      expect(r.timezone, 'America/Los_Angeles');
      expect(r.utcOffset, '-07:00');
      expect(r.isp, 'Google LLC');
      expect(r.org, 'Google LLC');
      expect(r.asn, 'AS15169');
    });

    test('locationLine, coordinatePair, mapsUrl derive correctly', () {
      final IpGeoResult r = IpGeoService.parse(_fullBody(), query: '8.8.8.8');
      expect(r.locationLine, 'Mountain View, California, United States');
      expect(r.hasCoordinates, isTrue);
      expect(r.coordinatePair, '37.422400,-122.084210');
      expect(r.mapsUrl, contains('openstreetmap.org'));
      expect(r.mapsUrl, contains('mlat=37.4224'));
    });

    test('missing connection/timezone → null fields, not fabricated', () {
      final IpGeoResult r = IpGeoService.parse(
        <String, dynamic>{
          'ip': '1.1.1.1',
          'success': true,
          'country': 'Australia',
        },
        query: '1.1.1.1',
      );
      expect(r.country, 'Australia');
      expect(r.asn, isNull);
      expect(r.isp, isNull);
      expect(r.timezone, isNull);
      expect(r.hasCoordinates, isFalse);
      expect(r.coordinatePair, isNull);
      expect(r.mapsUrl, isNull);
    });

    test('string-typed lat/long are coerced to double', () {
      final IpGeoResult r = IpGeoService.parse(
        <String, dynamic>{
          'ip': '9.9.9.9',
          'success': true,
          'latitude': '40.0',
          'longitude': '-75.0',
        },
        query: '9.9.9.9',
      );
      expect(r.latitude, 40.0);
      expect(r.longitude, -75.0);
    });
  });

  group('parse — in-band failure', () {
    test('success:false with rate message → rateLimited error', () {
      final IpGeoResult r = IpGeoService.parse(
        <String, dynamic>{
          'success': false,
          'message': 'You have reached your rate limit.',
        },
        query: '8.8.8.8',
      );
      expect(r.isError, isTrue);
      expect(r.errorKind, JsonHttpErrorKind.rateLimited);
      expect(r.errorMessage, contains('rate'));
    });

    test('success:false with other message → httpStatus error', () {
      final IpGeoResult r = IpGeoService.parse(
        <String, dynamic>{
          'success': false,
          'message': 'Invalid IP address',
        },
        query: 'bogus',
      );
      expect(r.isError, isTrue);
      expect(r.errorKind, JsonHttpErrorKind.httpStatus);
      expect(r.errorMessage, 'Invalid IP address');
    });
  });

  group('lookup — service', () {
    test('empty query labels result as my IP', () async {
      final IpGeoService svc = IpGeoService(
        client: JsonHttpClient(fetcher: fixed(_fullBody())),
      );
      final IpGeoResult r = await svc.lookup(rawQuery: '');
      expect(r.isError, isFalse);
      expect(r.query, '(my IP)');
      expect(r.ip, '8.8.8.8');
    });

    test('transport exception → failure with transport kind', () async {
      final IpGeoService svc = IpGeoService(
        client: JsonHttpClient(
          fetcher: throwing(const JsonHttpException(
            JsonHttpErrorKind.transport,
            'no route to host',
          )),
        ),
      );
      final IpGeoResult r = await svc.lookup(rawQuery: '8.8.8.8');
      expect(r.isError, isTrue);
      expect(r.errorKind, JsonHttpErrorKind.transport);
    });
  });
}
