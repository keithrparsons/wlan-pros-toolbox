// PublicIpService unit tests — plain-text parse (IPv4/IPv6), ipify→icanhazip
// fallback, and the honest null on total failure, via the injectable
// PlainTextFetcher seam (no network).

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/public_ip_service.dart';

PlainTextFetcher fixed(String body) =>
    (String url, Duration timeout) async => body;

void main() {
  group('parse', () {
    test('parses a bare IPv4', () {
      expect(PublicIpService.parseForTest('203.0.113.7'), '203.0.113.7');
    });

    test('trims surrounding whitespace / trailing newline', () {
      expect(PublicIpService.parseForTest('  203.0.113.7\n'), '203.0.113.7');
    });

    test('parses an IPv6 address', () {
      expect(
        PublicIpService.parseForTest('2001:4860:4860::8888'),
        '2001:4860:4860::8888',
      );
    });

    test('empty body → null', () {
      expect(PublicIpService.parseForTest(''), isNull);
      expect(PublicIpService.parseForTest('   \n '), isNull);
    });

    test('non-address body → null', () {
      expect(PublicIpService.parseForTest('rate limited, try later'), isNull);
      expect(PublicIpService.parseForTest('<html>error</html>'), isNull);
    });
  });

  group('fetch', () {
    test('returns the IP the (single) endpoint echoes', () async {
      final svc = PublicIpService(fetcher: fixed('198.51.100.42'));
      expect(await svc.fetch(), '198.51.100.42');
    });

    test('falls back to the second endpoint when the first fails', () async {
      int call = 0;
      final svc = PublicIpService(
        fetcher: (String url, Duration timeout) async {
          call++;
          // First endpoint (ipify) throws; second (icanhazip) answers.
          if (url == PublicIpService.endpoints.first) {
            throw const FormatException('ipify down');
          }
          return '198.51.100.99';
        },
      );
      expect(await svc.fetch(), '198.51.100.99');
      expect(call, 2);
    });

    test('falls back when the first endpoint returns junk', () async {
      final svc = PublicIpService(
        fetcher: (String url, Duration timeout) async {
          if (url == PublicIpService.endpoints.first) return 'not-an-ip';
          return '198.51.100.5';
        },
      );
      expect(await svc.fetch(), '198.51.100.5');
    });

    test('null when every endpoint fails (honest Unavailable)', () async {
      final svc = PublicIpService(
        fetcher: (String url, Duration timeout) async =>
            throw const FormatException('offline'),
      );
      expect(await svc.fetch(), isNull);
    });

    test('every endpoint is HTTPS (ATS / GL-008)', () {
      for (final String e in PublicIpService.endpoints) {
        expect(Uri.parse(e).scheme, 'https');
      }
    });
  });
}
