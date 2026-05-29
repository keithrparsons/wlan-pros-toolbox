// WhoisService unit tests — exercise referral-server parsing, highlight
// extraction, the IANA→registry→registrar hop sequence, and the empty/error
// taxonomy, all with a fake connector so no real TCP/43 sockets are opened.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/whois_service.dart';

void main() {
  group('parseReferralServer', () {
    test('parses an IANA refer: line', () {
      const String iana = '''
% IANA WHOIS server
domain:       COM
refer:        whois.verisign-grs.com
whois:        whois.verisign-grs.com
''';
      expect(
        WhoisService.parseReferralServer(iana),
        'whois.verisign-grs.com',
      );
    });

    test('falls back to whois: when refer: absent', () {
      const String rec = 'whois:        whois.nic.example\n';
      expect(WhoisService.parseReferralServer(rec), 'whois.nic.example');
    });

    test('strips scheme, port and path from the referral value', () {
      const String rec = 'refer: https://whois.example.com:43/path\n';
      expect(WhoisService.parseReferralServer(rec), 'whois.example.com');
    });

    test('is case-insensitive on the key', () {
      const String rec = 'Refer: whois.example.org\n';
      expect(WhoisService.parseReferralServer(rec), 'whois.example.org');
    });

    test('returns null when no referral present', () {
      const String rec = 'inetnum: 8.8.8.0 - 8.8.8.255\norg: Google\n';
      expect(WhoisService.parseReferralServer(rec), isNull);
    });
  });

  group('parseRegistrarServer', () {
    test('parses the Registrar WHOIS Server line', () {
      const String rec = 'Registrar WHOIS Server: whois.registrar.example\n';
      expect(
        WhoisService.parseRegistrarServer(rec),
        'whois.registrar.example',
      );
    });

    test('returns null when absent', () {
      expect(WhoisService.parseRegistrarServer('no such field'), isNull);
    });
  });

  group('parseHighlights', () {
    test('extracts registrar, dates, status, and name servers', () {
      const String rec = '''
Domain Name: EXAMPLE.COM
Registrar: Example Registrar, Inc.
Creation Date: 1995-08-14T04:00:00Z
Updated Date: 2023-08-14T07:01:44Z
Registry Expiry Date: 2024-08-13T04:00:00Z
Domain Status: clientTransferProhibited
Name Server: A.IANA-SERVERS.NET
Name Server: B.IANA-SERVERS.NET
''';
      final List<WhoisHighlight> h = WhoisService.parseHighlights(rec);
      final Map<String, String> byLabel = <String, String>{
        for (final WhoisHighlight x in h) x.label: x.value,
      };
      expect(byLabel['Registrar'], 'Example Registrar, Inc.');
      expect(byLabel['Created'], '1995-08-14T04:00:00Z');
      expect(byLabel['Updated'], '2023-08-14T07:01:44Z');
      expect(byLabel['Expires'], '2024-08-13T04:00:00Z');
      expect(byLabel['Status'], 'clientTransferProhibited');
      expect(
        byLabel['Name servers'],
        'a.iana-servers.net\nb.iana-servers.net',
      );
    });

    test('de-duplicates repeated name servers', () {
      const String rec = '''
nserver: ns1.example.com 192.0.2.1
nserver: NS1.EXAMPLE.COM
nserver: ns2.example.com
''';
      final List<WhoisHighlight> h = WhoisService.parseHighlights(rec);
      final WhoisHighlight ns =
          h.firstWhere((WhoisHighlight x) => x.label == 'Name servers');
      expect(ns.value, 'ns1.example.com\nns2.example.com');
    });

    test('omits fields that are absent (no blanks/zeros)', () {
      const String rec = 'Registrar: Only This\n';
      final List<WhoisHighlight> h = WhoisService.parseHighlights(rec);
      expect(h.length, 1);
      expect(h.single.label, 'Registrar');
    });
  });

  group('lookup referral flow', () {
    test('follows IANA → registry, recording both servers', () async {
      final List<String> seen = <String>[];
      final WhoisService svc = WhoisService(
        connector: (String server, String query, {required timeout}) async {
          seen.add(server);
          if (server == kIanaWhoisServer) {
            return 'refer: whois.verisign-grs.com\n';
          }
          return 'Domain Name: EXAMPLE.COM\nRegistrar: Verisign\n';
        },
      );
      final WhoisResult r = await svc.lookup(rawQuery: 'example.com');
      expect(r.isError, isFalse);
      expect(r.isEmpty, isFalse);
      expect(seen, <String>[kIanaWhoisServer, 'whois.verisign-grs.com']);
      expect(r.serversQueried,
          <String>[kIanaWhoisServer, 'whois.verisign-grs.com']);
      expect(r.rawRecord.contains('Registrar: Verisign'), isTrue);
    });

    test('follows the optional registrar hop when it returns a richer record',
        () async {
      final WhoisService svc = WhoisService(
        connector: (String server, String query, {required timeout}) async {
          switch (server) {
            case kIanaWhoisServer:
              return 'refer: whois.verisign-grs.com\n';
            case 'whois.verisign-grs.com':
              return 'Domain Name: EXAMPLE.COM\n'
                  'Registrar WHOIS Server: whois.registrar.example\n';
            default:
              return 'Domain Name: EXAMPLE.COM\n'
                  'Registrar: Full Registrar Record Inc.\n'
                  'Creation Date: 2000-01-01T00:00:00Z\n'
                  'Name Server: ns1.example.com\n';
          }
        },
      );
      final WhoisResult r = await svc.lookup(rawQuery: 'example.com');
      expect(r.serversQueried.length, 3);
      expect(r.serversQueried.last, 'whois.registrar.example');
      expect(r.rawRecord.contains('Full Registrar Record'), isTrue);
    });

    test('keeps the IANA record when there is no referral (IP case)',
        () async {
      final WhoisService svc = WhoisService(
        connector: (String server, String query, {required timeout}) async {
          return 'inetnum: 8.8.8.0 - 8.8.8.255\norg: Google LLC\n';
        },
      );
      final WhoisResult r = await svc.lookup(rawQuery: '8.8.8.8');
      expect(r.serversQueried, <String>[kIanaWhoisServer]);
      expect(r.rawRecord.contains('Google LLC'), isTrue);
    });

    test('empty query is a clear validation error', () async {
      final WhoisService svc = WhoisService(
        connector: (String server, String query, {required timeout}) async =>
            'unused',
      );
      final WhoisResult r = await svc.lookup(rawQuery: '   ');
      expect(r.isError, isTrue);
      expect(r.errorMessage, contains('Enter a domain'));
    });

    test('a no-match banner is classified as empty, not success', () async {
      final WhoisService svc = WhoisService(
        connector: (String server, String query, {required timeout}) async {
          if (server == kIanaWhoisServer) {
            return 'refer: whois.verisign-grs.com\n';
          }
          return 'No match for "NOPE.COM".\n';
        },
      );
      final WhoisResult r = await svc.lookup(rawQuery: 'nope.com');
      expect(r.isError, isFalse);
      expect(r.isEmpty, isTrue);
    });
  });
}
