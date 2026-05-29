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
        resolver: (name, type, {required provider}) async => <RRecord>[
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
        resolver: (name, type, {required provider}) async => null,
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
        resolver: (name, type, {required provider}) async => <RRecord>[],
      );
      final DnsLookupResult r = await svc.lookup(
        rawQuery: 'example.com',
        type: DnsRecordType.txt,
      );
      expect(r.isEmpty, isTrue);
    });

    test('resolver throwing → error state with message', () async {
      final DnsLookupService svc = DnsLookupService(
        resolver: (name, type, {required provider}) async =>
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
        resolver: (name, type, {required provider}) async {
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
        resolver: (name, type, {required provider}) async {
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
        resolver: (name, type, {required provider}) async {
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
        resolver: (name, type, {required provider}) async {
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

  group('type labels', () {
    test('each record type carries a UI label and an RRecordType', () {
      expect(DnsRecordType.aaaa.label, 'AAAA');
      expect(DnsRecordType.ptr.label, 'PTR (rDNS)');
      expect(DnsRecordType.mx.rrType, RRecordType.MX);
    });
  });
}
