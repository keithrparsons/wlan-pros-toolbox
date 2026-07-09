// Phase B PiBackendClient coverage — ping / traceroute / dnsLookup.
//
// These exercise the three new same-origin REST calls against the EXACT JSON
// shapes verified live on Pi-A (2026-07-09, felix-brief-pi-phase-b.md). A
// MockClient stands in for the browser fetch so no Pi is needed. The load-
// bearing checks: (1) each shape parses into the right model; (2) the
// dns-lookup catalog id maps to the `/toolboxapi/dns` route, NOT `dns-lookup`;
// (3) empty answers / unreachable are normal negative results, not errors;
// (4) a non-200 surfaces as a PiBackendException the screens can render.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wlan_pros_toolbox/services/network/pi_backend_client.dart';

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        headers: <String, String>{'content-type': 'application/json'});

PiBackendClient _client(MockClient mock) =>
    PiBackendClient(httpClient: mock, base: Uri.parse('http://pi.local/'));

void main() {
  group('ping()', () {
    test('parses the aggregate and hits /toolboxapi/ping with host+count', () async {
      late Uri seen;
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        seen = req.url;
        return _json(<String, dynamic>{
          'target': '1.1.1.1',
          'count': 3,
          'sent': 3,
          'received': 3,
          'loss_pct': 0.0,
          'reachable': true,
          'min_ms': 4.6,
          'avg_ms': 4.698,
          'max_ms': 4.8,
          'raw': '...ping output...',
        });
      }));

      final PiHop hop = await client.ping(host: '1.1.1.1', count: 3);

      expect(seen.path, '/toolboxapi/ping');
      expect(seen.queryParameters['host'], '1.1.1.1');
      expect(seen.queryParameters['count'], '3');
      expect(hop.target, '1.1.1.1');
      expect(hop.reachable, isTrue);
      expect(hop.sent, 3);
      expect(hop.received, 3);
      expect(hop.count, 3);
      expect(hop.lossPct, 0.0);
      expect(hop.avgMs, closeTo(4.698, 1e-9));
      expect(hop.minMs, 4.6);
      expect(hop.maxMs, 4.8);
    });

    test('clamps count into the Pi bound (1..20)', () async {
      late Uri seen;
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        seen = req.url;
        return _json(<String, dynamic>{'reachable': false});
      }));

      await client.ping(host: 'x', count: 999);
      expect(seen.queryParameters['count'], '20');
      await client.ping(host: 'x', count: 0);
      expect(seen.queryParameters['count'], '1');
    });

    test('unreachable host is a normal negative result, not an error', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        return _json(<String, dynamic>{
          'target': '10.0.0.9',
          'sent': 3,
          'received': 0,
          'loss_pct': 100.0,
          'reachable': false,
        });
      }));

      final PiHop hop = await client.ping(host: '10.0.0.9');
      expect(hop.reachable, isFalse);
      expect(hop.received, 0);
      expect(hop.lossPct, 100.0);
      expect(hop.avgMs, isNull); // never zero-filled
    });
  });

  group('traceroute()', () {
    test('parses hops in order and hits /toolboxapi/traceroute', () async {
      late Uri seen;
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        seen = req.url;
        return _json(<String, dynamic>{
          'target': '1.1.1.1',
          'max_hops': 8,
          'hops': <dynamic>[
            <String, dynamic>{'hop': 1, 'ip': '10.0.10.1', 'ms': 0.4},
            <String, dynamic>{'hop': 2, 'ip': '203.0.113.1', 'ms': 5.1},
          ],
          'raw': '...',
        });
      }));

      final List<PiHop> hops =
          await client.traceroute(host: '1.1.1.1', maxHops: 8);

      expect(seen.path, '/toolboxapi/traceroute');
      expect(seen.queryParameters['host'], '1.1.1.1');
      expect(seen.queryParameters['max_hops'], '8');
      expect(hops, hasLength(2));
      expect(hops.first.hopNumber, 1);
      expect(hops.first.target, '10.0.10.1');
      expect(hops.first.ms, 0.4);
      expect(hops.first.reachable, isTrue);
      expect(hops[1].target, '203.0.113.1');
    });

    test('a hop with no ip is unreachable and not zero-filled', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        return _json(<String, dynamic>{
          'target': 'x',
          'hops': <dynamic>[
            <String, dynamic>{'hop': 3},
          ],
        });
      }));

      final List<PiHop> hops = await client.traceroute(host: 'x');
      expect(hops.single.target, isNull);
      expect(hops.single.reachable, isFalse);
      expect(hops.single.ms, isNull);
    });
  });

  group('dnsLookup()', () {
    test('the dns-lookup tool maps to the /toolboxapi/dns route', () async {
      late Uri seen;
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        seen = req.url;
        return _json(<String, dynamic>{
          'host': 'cloudflare.com',
          'type': 'A',
          'answers': <dynamic>['104.16.133.229', '104.16.132.229'],
          'count': 2,
          'query_ms': 36.8,
          'raw': '...',
        });
      }));

      final PiDns dns = await client.dnsLookup(host: 'cloudflare.com', type: 'A');

      // Load-bearing: the route is `dns`, NEVER `dns-lookup`.
      expect(seen.path, '/toolboxapi/dns');
      expect(seen.path, isNot(contains('dns-lookup')));
      expect(seen.queryParameters['host'], 'cloudflare.com');
      expect(seen.queryParameters['type'], 'A');
      expect(dns.type, 'A');
      expect(dns.answers, <String>['104.16.133.229', '104.16.132.229']);
      expect(dns.count, 2);
      expect(dns.queryMs, closeTo(36.8, 1e-9));
    });

    test('a resolvable name with no records returns empty answers, not an error',
        () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        return _json(<String, dynamic>{
          'host': 'example.com',
          'type': 'MX',
          'answers': <dynamic>[],
          'count': 0,
          'query_ms': 12.0,
        });
      }));

      final PiDns dns = await client.dnsLookup(host: 'example.com', type: 'MX');
      expect(dns.answers, isEmpty);
      expect(dns.count, 0);
    });
  });

  group('error contract', () {
    test('a non-200 surfaces as a PiBackendException', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        return _json(<String, dynamic>{'detail': 'bad host'}, status: 400);
      }));

      expect(
        () => client.dnsLookup(host: '', type: 'A'),
        throwsA(isA<PiBackendException>()),
      );
    });
  });
}
