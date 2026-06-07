// DnsLookupService unit tests — exercise the success / empty / error result
// states, PTR reverse-name construction, and type/label mapping, all with a
// fake resolver so no live DoH request is made.

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/dns_lookup_service.dart';

void main() {
  group('lookup result states', () {
    test('returns records on success', () async {
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required resolver}) async => <RRecord>[
          RRecord(name: 'example.com', rType: 1, ttl: 300, data: '93.184.216.34'),
        ],
      );
      final DnsLookupResult r = await svc.lookup(
        rawQuery: 'example.com',
        type: DnsRecordType.a,
      );
      expect(r.isError, isFalse);
      expect(r.isEmpty, isFalse);
      expect(r.records.single.data, '93.184.216.34');
      expect(r.records.single.type, 'A');
      expect(r.records.single.ttl, 300);
    });

    test('null resolver response → empty state (not error)', () async {
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required resolver}) async => null,
      );
      final DnsLookupResult r = await svc.lookup(
        rawQuery: 'no-records.example',
        type: DnsRecordType.mx,
      );
      expect(r.isError, isFalse);
      expect(r.isEmpty, isTrue);
    });

    test('empty list response → empty state', () async {
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required resolver}) async => <RRecord>[],
      );
      final DnsLookupResult r = await svc.lookup(
        rawQuery: 'example.com',
        type: DnsRecordType.txt,
      );
      expect(r.isEmpty, isTrue);
    });

    test('resolver throwing → error state with message', () async {
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required resolver}) async =>
            throw Exception('network down'),
      );
      final DnsLookupResult r = await svc.lookup(
        rawQuery: 'example.com',
        type: DnsRecordType.a,
      );
      expect(r.isError, isTrue);
      expect(r.errorMessage, contains('Lookup failed'));
    });

    test('blank query → validation error before any resolve', () async {
      bool called = false;
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required resolver}) async {
          called = true;
          return <RRecord>[];
        },
      );
      final DnsLookupResult r =
          await svc.lookup(rawQuery: '   ', type: DnsRecordType.a);
      expect(r.isError, isTrue);
      expect(called, isFalse);
    });
  });

  group('PTR / reverse DNS', () {
    test('IPv4 PTR queries the in-addr.arpa name', () async {
      String? queried;
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required resolver}) async {
          queried = name;
          return <RRecord>[
            RRecord(name: name, rType: 12, ttl: 60, data: 'dns.google'),
          ];
        },
      );
      final DnsLookupResult r = await svc.lookup(
        rawQuery: '8.8.8.8',
        type: DnsRecordType.ptr,
      );
      expect(queried, '8.8.8.8.in-addr.arpa');
      expect(r.records.single.data, 'dns.google');
    });

    test('invalid IP for PTR → validation error, resolver not called',
        () async {
      bool called = false;
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required resolver}) async {
          called = true;
          return <RRecord>[];
        },
      );
      final DnsLookupResult r = await svc.lookup(
        rawQuery: 'not-an-ip',
        type: DnsRecordType.ptr,
      );
      expect(r.isError, isTrue);
      expect(called, isFalse);
    });

    test('IPv6 PTR builds a nibble-reversed ip6.arpa name', () async {
      String? queried;
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required resolver}) async {
          queried = name;
          return <RRecord>[];
        },
      );
      await svc.lookup(rawQuery: '2001:4860:4860::8888', type: DnsRecordType.ptr);
      expect(queried, endsWith('.ip6.arpa'));
      // 32 reversed nibbles + ip6.arpa.
      expect(queried!.split('.').length, 32 + 2);
      // Last nibble of the address (8) becomes the first label.
      expect(queried!.startsWith('8.'), isTrue);
    });
  });

  group('resolver selection', () {
    test('three resolvers are offered: Google, Cloudflare, Quad9', () {
      expect(DohResolver.values, <DohResolver>[
        DohResolver.google,
        DohResolver.cloudflare,
        DohResolver.quad9,
      ]);
    });

    test('each resolver carries an IP-tagged label', () {
      expect(DohResolver.google.label, 'Google (8.8.8.8)');
      expect(DohResolver.cloudflare.label, 'Cloudflare (1.1.1.1)');
      expect(DohResolver.quad9.label, 'Quad9 (9.9.9.9)');
    });

    test('Google/Cloudflare map to a basic_utils provider; Quad9 does not', () {
      expect(DohResolver.google.provider, DnsApiProvider.GOOGLE);
      expect(DohResolver.cloudflare.provider, DnsApiProvider.CLOUDFLARE);
      // Quad9 is not a basic_utils provider — reading .provider must fail loud
      // rather than silently fall back to Google.
      expect(() => DohResolver.quad9.provider, throwsStateError);
    });

    test('only Quad9 exposes a direct JSON DoH endpoint (HTTPS, keyless)', () {
      expect(DohResolver.google.jsonEndpoint, isNull);
      expect(DohResolver.cloudflare.jsonEndpoint, isNull);
      expect(DohResolver.quad9.jsonEndpoint,
          'https://dns.quad9.net:5053/dns-query');
      // GL-008: HTTPS only.
      expect(DohResolver.quad9.jsonEndpoint!.startsWith('https://'), isTrue);
    });

    test('the selected resolver is threaded to the resolver seam', () async {
      DohResolver? seen;
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required resolver}) async {
          seen = resolver;
          return <RRecord>[
            RRecord(name: 'example.com', rType: 1, ttl: 60, data: '9.9.9.9'),
          ];
        },
      );
      final DnsLookupResult r = await svc.lookup(
        rawQuery: 'example.com',
        type: DnsRecordType.a,
        resolver: DohResolver.quad9,
      );
      expect(seen, DohResolver.quad9);
      // The result echoes the resolver it ran against (drives the summary line).
      expect(r.resolver, DohResolver.quad9);
      expect(r.records.single.data, '9.9.9.9');
    });

    test('a Quad9 query that resolves nothing is the empty state, not an error',
        () async {
      // Quad9 returns no answer for a blocked/malicious domain. That is the
      // honest empty result (GL-005), never a synthesized failure.
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required resolver}) async => null,
      );
      final DnsLookupResult r = await svc.lookup(
        rawQuery: 'malware.example',
        type: DnsRecordType.a,
        resolver: DohResolver.quad9,
      );
      expect(r.isError, isFalse);
      expect(r.isEmpty, isTrue);
      expect(r.resolver, DohResolver.quad9);
    });
  });

  group('type labels', () {
    test('each record type carries a UI label and an RRecordType', () {
      expect(DnsRecordType.aaaa.label, 'AAAA');
      expect(DnsRecordType.ptr.label, 'PTR (rDNS)');
      expect(DnsRecordType.mx.rrType, RRecordType.MX);
    });

    test('advanced types carry labels and the right wire type', () {
      expect(DnsRecordType.srv.label, 'SRV');
      expect(DnsRecordType.caa.label, 'CAA');
      expect(DnsRecordType.spf.label, 'SPF');
      expect(DnsRecordType.srv.rrType, RRecordType.SRV);
      expect(DnsRecordType.caa.rrType, RRecordType.CAA);
      // SPF is queried as TXT (RFC 7208), not the deprecated type-99.
      expect(DnsRecordType.spf.rrType, RRecordType.TXT);
    });
  });

  group('SRV parsing', () {
    test('parses priority/weight/port/target from wire form', () {
      final SrvData? srv = SrvData.parse('10 60 5060 sipserver.example.com.');
      expect(srv, isNotNull);
      expect(srv!.priority, 10);
      expect(srv.weight, 60);
      expect(srv.port, 5060);
      expect(srv.target, 'sipserver.example.com.');
      expect(srv.display, contains('sipserver.example.com.:5060'));
      expect(srv.display, contains('prio 10'));
      expect(srv.display, contains('weight 60'));
    });

    test('tolerates extra whitespace between fields', () {
      final SrvData? srv = SrvData.parse('  0   5   443    host.tld  ');
      expect(srv, isNotNull);
      expect(srv!.port, 443);
      expect(srv.target, 'host.tld');
    });

    test('rejects malformed SRV data', () {
      expect(SrvData.parse('10 60 5060'), isNull); // missing target
      expect(SrvData.parse('a b c d'), isNull); // non-numeric
      expect(SrvData.parse(''), isNull);
    });

    test('end-to-end SRV lookup keeps the wire data on the record', () async {
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required resolver}) async => <RRecord>[
          RRecord(
            name: '_sip._tcp.example.com',
            rType: 33,
            ttl: 120,
            data: '10 60 5060 sipserver.example.com.',
          ),
        ],
      );
      final DnsLookupResult r = await svc.lookup(
        rawQuery: '_sip._tcp.example.com',
        type: DnsRecordType.srv,
      );
      expect(r.isError, isFalse);
      expect(r.records.single.type, 'SRV');
      expect(r.records.single.ttl, 120);
      expect(SrvData.parse(r.records.single.data)!.port, 5060);
    });
  });

  group('CAA parsing', () {
    test('parses flags/tag/value with a quoted value', () {
      final CaaData? caa = CaaData.parse('0 issue "letsencrypt.org"');
      expect(caa, isNotNull);
      expect(caa!.flags, 0);
      expect(caa.tag, 'issue');
      expect(caa.value, 'letsencrypt.org');
      expect(caa.display, 'issue "letsencrypt.org"  (flags 0)');
    });

    test('parses a critical (flag 128) iodef record', () {
      final CaaData? caa =
          CaaData.parse('128 iodef "mailto:security@example.com"');
      expect(caa, isNotNull);
      expect(caa!.flags, 128);
      expect(caa.tag, 'iodef');
      expect(caa.value, 'mailto:security@example.com');
    });

    test('tolerates an unquoted value', () {
      final CaaData? caa = CaaData.parse('0 issuewild ;');
      expect(caa, isNotNull);
      expect(caa!.tag, 'issuewild');
    });

    test('rejects malformed CAA data', () {
      expect(CaaData.parse('issue "letsencrypt.org"'), isNull); // no flags int
      expect(CaaData.parse(''), isNull);
    });

    test('end-to-end CAA lookup labels the row CAA', () async {
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required resolver}) async => <RRecord>[
          RRecord(
            name: 'example.com',
            rType: 257,
            ttl: 3600,
            data: '0 issue "letsencrypt.org"',
          ),
        ],
      );
      final DnsLookupResult r = await svc.lookup(
        rawQuery: 'example.com',
        type: DnsRecordType.caa,
      );
      expect(r.records.single.type, 'CAA');
      expect(CaaData.parse(r.records.single.data)!.tag, 'issue');
    });
  });

  group('SPF (read from TXT)', () {
    test('SPF query targets TXT and keeps only the v=spf1 line', () async {
      RRecordType? wireType;
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required resolver}) async {
          wireType = type;
          return <RRecord>[
            RRecord(
              name: 'example.com',
              rType: 16,
              ttl: 300,
              data: '"google-site-verification=abc123"',
            ),
            RRecord(
              name: 'example.com',
              rType: 16,
              ttl: 300,
              data: '"v=spf1 include:_spf.google.com ~all"',
            ),
          ];
        },
      );
      final DnsLookupResult r = await svc.lookup(
        rawQuery: 'example.com',
        type: DnsRecordType.spf,
      );
      // Queried as TXT on the wire.
      expect(wireType, RRecordType.TXT);
      // Only the SPF policy survives the filter, unquoted, labeled SPF.
      expect(r.records.length, 1);
      expect(r.records.single.type, 'SPF');
      expect(r.records.single.data, 'v=spf1 include:_spf.google.com ~all');
    });

    test('no SPF policy among TXT records → empty state, not error', () async {
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required resolver}) async => <RRecord>[
          RRecord(
            name: 'example.com',
            rType: 16,
            ttl: 300,
            data: '"docusign=xyz"',
          ),
        ],
      );
      final DnsLookupResult r = await svc.lookup(
        rawQuery: 'example.com',
        type: DnsRecordType.spf,
      );
      expect(r.isError, isFalse);
      expect(r.isEmpty, isTrue);
    });

    test('joins multi-chunk quoted TXT into one SPF string', () async {
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required resolver}) async => <RRecord>[
          RRecord(
            name: 'example.com',
            rType: 16,
            ttl: 300,
            data: '"v=spf1 include:a.example " "include:b.example ~all"',
          ),
        ],
      );
      final DnsLookupResult r = await svc.lookup(
        rawQuery: 'example.com',
        type: DnsRecordType.spf,
      );
      expect(r.records.single.data,
          'v=spf1 include:a.example include:b.example ~all');
    });
  });

  group('dig-style sweep (lookupAll)', () {
    test('sweep queries the dig type order, PTR/SPF excluded', () {
      // The sweep is over hostname records; PTR (IP query) and SPF (a TXT
      // filter) are not top-level sections.
      expect(DnsLookupService.digTypeOrder, <DnsRecordType>[
        DnsRecordType.soa,
        DnsRecordType.ns,
        DnsRecordType.a,
        DnsRecordType.aaaa,
        DnsRecordType.mx,
        DnsRecordType.txt,
        DnsRecordType.srv,
        DnsRecordType.caa,
      ]);
      expect(DnsLookupService.digTypeOrder.contains(DnsRecordType.ptr), isFalse);
      expect(DnsLookupService.digTypeOrder.contains(DnsRecordType.spf), isFalse);
    });

    test('returns one section per type, in dig order', () async {
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required resolver}) async => <RRecord>[],
      );
      final DnsDigResult dig = await svc.lookupAll(rawQuery: 'example.com');
      expect(dig.sections.length, DnsLookupService.digTypeOrder.length);
      expect(
        dig.sections.map((DnsDigSection s) => s.type).toList(),
        DnsLookupService.digTypeOrder,
      );
    });

    test('aggregates records across types and counts them', () async {
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required resolver}) async {
          switch (type) {
            case RRecordType.A:
              return <RRecord>[
                RRecord(name: 'example.com', rType: 1, ttl: 300, data: '1.2.3.4'),
                RRecord(name: 'example.com', rType: 1, ttl: 300, data: '5.6.7.8'),
              ];
            case RRecordType.MX:
              return <RRecord>[
                RRecord(
                    name: 'example.com',
                    rType: 15,
                    ttl: 3600,
                    data: '10 mail.example.com'),
              ];
            default:
              return <RRecord>[];
          }
        },
      );
      final DnsDigResult dig = await svc.lookupAll(rawQuery: 'example.com');
      expect(dig.isError, isFalse);
      expect(dig.isAllEmpty, isFalse);
      expect(dig.recordCount, 3);
      // Only A and MX came back non-empty, A before MX per dig order.
      expect(
        dig.nonEmptySections.map((DnsDigSection s) => s.type).toList(),
        <DnsRecordType>[DnsRecordType.a, DnsRecordType.mx],
      );
    });

    test('all types empty → isAllEmpty (not an error)', () async {
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required resolver}) async => null,
      );
      final DnsDigResult dig = await svc.lookupAll(rawQuery: 'nothing.example');
      expect(dig.isError, isFalse);
      expect(dig.isAllEmpty, isTrue);
      expect(dig.recordCount, 0);
      expect(dig.nonEmptySections, isEmpty);
    });

    test('a per-type failure is isolated, other records still resolve',
        () async {
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required resolver}) async {
          if (type == RRecordType.TXT) {
            throw Exception('TXT path blocked');
          }
          if (type == RRecordType.A) {
            return <RRecord>[
              RRecord(name: 'example.com', rType: 1, ttl: 60, data: '9.9.9.9'),
            ];
          }
          return <RRecord>[];
        },
      );
      final DnsDigResult dig = await svc.lookupAll(rawQuery: 'example.com');
      // The whole sweep did not fail just because TXT did.
      expect(dig.isError, isFalse);
      expect(dig.recordCount, 1);
      final DnsDigSection txt =
          dig.sections.firstWhere((DnsDigSection s) => s.type == DnsRecordType.txt);
      expect(txt.isError, isTrue);
      final DnsDigSection a =
          dig.sections.firstWhere((DnsDigSection s) => s.type == DnsRecordType.a);
      expect(a.records.single.data, '9.9.9.9');
    });

    test('blank query → whole-sweep validation error, resolver never called',
        () async {
      bool called = false;
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required resolver}) async {
          called = true;
          return <RRecord>[];
        },
      );
      final DnsDigResult dig = await svc.lookupAll(rawQuery: '   ');
      expect(dig.isError, isTrue);
      expect(dig.errorMessage, isNotNull);
      expect(called, isFalse);
    });
  });
}
