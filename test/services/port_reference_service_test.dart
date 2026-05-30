// PortReferenceService unit tests — JSON parsing (incl. malformed-row
// tolerance), exact port-number lookup, service-name + description substring
// search, and the empty-result honesty path. The service is built from an
// in-memory JSON string so no asset load is needed.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/port_reference_service.dart';

const String _fixture = '''
{
  "ports": [
    { "port": 22, "protocols": ["tcp"], "name": "ssh", "description": "Secure Shell" },
    { "port": 53, "protocols": ["tcp", "udp"], "name": "dns", "description": "Domain Name System" },
    { "port": 443, "protocols": ["tcp", "udp"], "name": "https", "description": "HTTP over TLS; UDP carries HTTP/3 (QUIC)" },
    { "port": 1812, "protocols": ["udp"], "name": "radius", "description": "RADIUS authentication (802.1X / WPA2-Enterprise)" },
    { "port": 5060, "protocols": ["udp", "tcp"], "name": "sip", "description": "Session Initiation Protocol" }
  ]
}
''';

void main() {
  final PortReferenceService svc = PortReferenceService.fromJson(_fixture);

  group('parse', () {
    test('loads every well-formed row', () {
      expect(svc.count, 5);
      expect(svc.all.map((e) => e.port), containsAll(<int>[22, 53, 443, 1812, 5060]));
    });

    test('maps protocols, name, and description', () {
      final PortEntry dns = svc.search('53').single;
      expect(dns.name, 'dns');
      expect(dns.protocols, <PortProtocol>[PortProtocol.tcp, PortProtocol.udp]);
      expect(dns.protocolLabel, 'TCP/UDP');
      expect(dns.description, contains('Domain Name System'));
    });

    test('drops malformed rows but keeps the good ones', () {
      const String bad = '''
      {
        "ports": [
          { "port": 80, "protocols": ["tcp"], "name": "http", "description": "HTTP" },
          { "protocols": ["tcp"], "name": "no-port", "description": "missing port" },
          { "port": 70000, "protocols": ["tcp"], "name": "out-of-range", "description": "bad port" },
          { "port": 81, "protocols": [], "name": "no-proto", "description": "no protocols" },
          { "port": 82, "protocols": ["tcp"], "name": "", "description": "empty name" },
          { "port": 8080, "protocols": ["tcp"], "name": "http-alt", "description": "alt HTTP" }
        ]
      }
      ''';
      final PortReferenceService s = PortReferenceService.fromJson(bad);
      expect(s.count, 2);
      expect(s.all.map((e) => e.port), <int>[80, 8080]);
    });

    test('coerces a string port number', () {
      const String strPort =
          '{ "ports": [ { "port": "123", "protocols": ["udp"], "name": "ntp", "description": "NTP" } ] }';
      final PortReferenceService s = PortReferenceService.fromJson(strPort);
      expect(s.search('123').single.name, 'ntp');
    });

    test('garbage document yields an empty-but-valid service', () {
      expect(PortReferenceService.fromJson('[]').count, 0);
      expect(PortReferenceService.fromJson('{"nope": true}').count, 0);
    });
  });

  group('search by port number', () {
    test('exact numeric match returns that port', () {
      final List<PortEntry> r = svc.search('443');
      expect(r.length, 1);
      expect(r.single.name, 'https');
    });

    test('a number with no match returns empty, not a fabricated row', () {
      expect(svc.search('9999'), isEmpty);
    });

    test('numeric query is exact, not substring (443 does not match 4)', () {
      // '4' is not a port in the fixture → empty, even though 443 contains '4'.
      expect(svc.search('4'), isEmpty);
    });
  });

  group('search by service-name substring', () {
    test('case-insensitive name substring matches', () {
      // "SSH" → only the ssh entry's name contains it (case-insensitive).
      expect(svc.search('SSH').single.name, 'ssh');
      expect(svc.search('dns').single.name, 'dns');
      // "HTTPS" matches the https name but not the http/3 mention elsewhere.
      expect(svc.search('https').single.name, 'https');
    });

    test('matches against the description too', () {
      // "radius" lives in the name; "802.1X" lives only in its description.
      final List<PortEntry> r = svc.search('802.1X');
      expect(r.single.name, 'radius');
    });

    test('results come back sorted by ascending port number', () {
      // Both sip (5060) and https (443) descriptions contain "TLS"/"Protocol"?
      // Use "protocol" which appears in sip's description and https's.
      final List<PortEntry> r = svc.search('Protocol');
      // dns "Domain Name System" has no "protocol"; sip + https do not both...
      // Assert ordering generically on a multi-hit query: search "tcp"? names
      // don't contain it. Use a guaranteed multi-hit: substring "s".
      final List<PortEntry> many = svc.search('s');
      final List<int> ports = many.map((e) => e.port).toList();
      final List<int> sorted = List<int>.of(ports)..sort();
      expect(ports, sorted);
      expect(r, isNotNull);
    });
  });

  group('empty / whole-list query', () {
    test('empty query returns the full list, sorted by port', () {
      final List<PortEntry> r = svc.search('');
      expect(r.length, svc.count);
      expect(r.first.port, 22);
      expect(r.last.port, 5060);
    });

    test('whitespace-only query is treated as empty', () {
      expect(svc.search('   ').length, svc.count);
    });

    test('a name substring with no match returns empty', () {
      expect(svc.search('zzznotaservice'), isEmpty);
    });
  });
}
