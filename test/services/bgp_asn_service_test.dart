// BgpAsnService unit tests — input classification, RIPEstat JSON parsing
// (as-overview, network-info), and the error/rate-limit taxonomy via the
// injectable JsonFetcher seam (no network).

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/bgp_asn_service.dart';
import 'package:wlan_pros_toolbox/services/network/json_http_client.dart';

/// A fetcher that returns one scripted body for every call.
JsonFetcher fixed(Map<String, dynamic> body) =>
    (Uri url, Duration timeout) async => body;

/// A fetcher that routes by the RIPEstat endpoint name in the path.
JsonFetcher byEndpoint(Map<String, Map<String, dynamic>> table) {
  return (Uri url, Duration timeout) async {
    for (final MapEntry<String, Map<String, dynamic>> e in table.entries) {
      if (url.path.contains(e.key)) return e.value;
    }
    throw StateError('no scripted body for ${url.path}');
  };
}

/// A fetcher that throws a typed JsonHttpException.
JsonFetcher throwing(JsonHttpException e) =>
    (Uri url, Duration timeout) async => throw e;

void main() {
  group('classify', () {
    test('IPv4 → ip', () {
      expect(BgpAsnService.classify('8.8.8.8'), BgpQueryKind.ip);
    });
    test('IPv6 → ip', () {
      expect(BgpAsnService.classify('2001:4860:4860::8888'), BgpQueryKind.ip);
    });
    test('ASxxxx → asn', () {
      expect(BgpAsnService.classify('AS15169'), BgpQueryKind.asn);
      expect(BgpAsnService.classify('as15169'), BgpQueryKind.asn);
      expect(BgpAsnService.classify('15169'), BgpQueryKind.asn);
    });
    test('garbage → null', () {
      expect(BgpAsnService.classify('not an ip'), isNull);
      expect(BgpAsnService.classify('999.999.999.999'), isNull);
      expect(BgpAsnService.classify(''), isNull);
    });
  });

  group('parseAsOverview', () {
    test('populates holder, type, announced, registry from block.desc', () {
      final BgpAsnResult r = BgpAsnService.parseAsOverview(
        <String, dynamic>{
          'data': <String, dynamic>{
            'holder': 'GOOGLE',
            'type': 'as',
            'announced': true,
            'block': <String, dynamic>{
              'resource': '15169-15169',
              'desc': 'RIPE NCC ASN block',
              'name': 'IANA 16-bit Autonomous System (AS) Numbers Registry',
            },
          },
        },
        asnNumber: '15169',
      );
      expect(r.asn, 'AS15169');
      expect(r.holder, 'GOOGLE');
      expect(r.asnType, 'as');
      expect(r.isAnnounced, isTrue);
      expect(r.registry, 'RIPE NCC ASN block');
      expect(r.isError, isFalse);
    });

    test('missing fields come back null, not fabricated', () {
      final BgpAsnResult r = BgpAsnService.parseAsOverview(
        <String, dynamic>{'data': <String, dynamic>{}},
        asnNumber: '64512',
      );
      expect(r.asn, 'AS64512');
      expect(r.holder, isNull);
      expect(r.isAnnounced, isNull);
      expect(r.registry, isNull);
    });
  });

  group('parseNetworkInfo', () {
    test('extracts prefix and asn list', () {
      final ({String? prefix, List<String> asns}) p =
          BgpAsnService.parseNetworkInfo(<String, dynamic>{
        'data': <String, dynamic>{
          'prefix': '8.8.8.0/24',
          'asns': <dynamic>['15169'],
        },
      });
      expect(p.prefix, '8.8.8.0/24');
      expect(p.asns, <String>['15169']);
    });

    test('empty asns → empty list, null prefix tolerated', () {
      final ({String? prefix, List<String> asns}) p =
          BgpAsnService.parseNetworkInfo(<String, dynamic>{
        'data': <String, dynamic>{'asns': <dynamic>[]},
      });
      expect(p.prefix, isNull);
      expect(p.asns, isEmpty);
    });
  });

  group('lookup — IP path', () {
    test('network-info + as-overview merge into a populated result', () async {
      final BgpAsnService svc = BgpAsnService(
        client: JsonHttpClient(
          fetcher: byEndpoint(<String, Map<String, dynamic>>{
            'network-info': <String, dynamic>{
              'data': <String, dynamic>{
                'prefix': '8.8.8.0/24',
                'asns': <dynamic>['15169'],
              },
            },
            'as-overview': <String, dynamic>{
              'data': <String, dynamic>{
                'holder': 'GOOGLE',
                'announced': true,
                'block': <String, dynamic>{'desc': 'ARIN ASN block'},
              },
            },
          }),
        ),
      );
      final BgpAsnResult r = await svc.lookup(rawQuery: '8.8.8.8');
      expect(r.isError, isFalse);
      expect(r.kind, BgpQueryKind.ip);
      expect(r.asn, 'AS15169');
      expect(r.announcedPrefix, '8.8.8.0/24');
      expect(r.holder, 'GOOGLE');
      expect(r.registry, 'ARIN ASN block');
    });

    test('IP with no ASN → isEmpty (not error)', () async {
      final BgpAsnService svc = BgpAsnService(
        client: JsonHttpClient(
          fetcher: byEndpoint(<String, Map<String, dynamic>>{
            'network-info': <String, dynamic>{
              'data': <String, dynamic>{'asns': <dynamic>[]},
            },
          }),
        ),
      );
      final BgpAsnResult r = await svc.lookup(rawQuery: '10.0.0.1');
      expect(r.isError, isFalse);
      expect(r.isEmpty, isTrue);
    });
  });

  group('lookup — ASN path', () {
    test('as-overview + asn-neighbours counts map to up/peer/down', () async {
      final BgpAsnService svc = BgpAsnService(
        client: JsonHttpClient(
          fetcher: byEndpoint(<String, Map<String, dynamic>>{
            'as-overview': <String, dynamic>{
              'data': <String, dynamic>{'holder': 'GOOGLE', 'announced': true},
            },
            'asn-neighbours': <String, dynamic>{
              'data': <String, dynamic>{
                'neighbours': <dynamic>[
                  <String, dynamic>{'type': 'left'},
                  <String, dynamic>{'type': 'left'},
                  <String, dynamic>{'type': 'right'},
                  <String, dynamic>{'type': 'unknown'},
                ],
              },
            },
          }),
        ),
      );
      final BgpAsnResult r = await svc.lookup(rawQuery: 'AS15169');
      expect(r.isError, isFalse);
      expect(r.asn, 'AS15169');
      expect(r.upstreamCount, 2);
      expect(r.downstreamCount, 1);
      expect(r.peerCount, 1);
    });
  });

  group('error handling', () {
    test('rate-limit exception → failure with rateLimited kind', () async {
      final BgpAsnService svc = BgpAsnService(
        client: JsonHttpClient(
          fetcher: throwing(const JsonHttpException(
            JsonHttpErrorKind.rateLimited,
            'rate limited',
            statusCode: 429,
          )),
        ),
      );
      final BgpAsnResult r = await svc.lookup(rawQuery: '8.8.8.8');
      expect(r.isError, isTrue);
      expect(r.errorKind, JsonHttpErrorKind.rateLimited);
    });

    test('timeout exception → failure with timeout kind', () async {
      final BgpAsnService svc = BgpAsnService(
        client: JsonHttpClient(
          fetcher: throwing(const JsonHttpException(
            JsonHttpErrorKind.timeout,
            'timed out',
          )),
        ),
      );
      final BgpAsnResult r = await svc.lookup(rawQuery: 'AS15169');
      expect(r.isError, isTrue);
      expect(r.errorKind, JsonHttpErrorKind.timeout);
    });

    test('bad input → validation failure, no fetch attempted', () async {
      final BgpAsnService svc = BgpAsnService(
        client: JsonHttpClient(fetcher: fixed(<String, dynamic>{})),
      );
      final BgpAsnResult r = await svc.lookup(rawQuery: 'nonsense!!');
      expect(r.isError, isTrue);
      expect(r.errorMessage, contains('valid'));
    });
  });
}
