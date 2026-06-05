// PlmnReferenceService unit tests — JSON parsing (incl. the load-bearing
// leading-zero string guard and malformed-row tolerance), digit search across
// mcc/mnc/plmn_id, carrier/operator substring search, MCC grouping, and the
// empty-result honesty path. The service is built from an in-memory JSON string
// so no asset load is needed.
//
// Plus a real-asset test that loads the bundled assets/data/plmn_us.json and
// asserts the full row count (376) and the leading-zero invariant on the actual
// shipped data.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/plmn_reference_service.dart';

const String _fixture = '''
{
  "_meta": { "count": 5, "statuses": ["operational", "not operational", "reserved", "unknown"] },
  "plmn": [
    { "mcc": "310", "mnc": "030", "plmn_id": "310030", "country": "United States", "region": "US", "carrier": "AT&T", "operator": "AT&T Mobility", "status": "unknown" },
    { "mcc": "310", "mnc": "004", "plmn_id": "310004", "country": "United States", "region": "US", "carrier": "Verizon", "operator": "Verizon Wireless", "status": "operational" },
    { "mcc": "310", "mnc": "260", "plmn_id": "310260", "country": "United States", "region": "US", "carrier": "T-Mobile", "operator": "T-Mobile US", "status": "operational" },
    { "mcc": "311", "mnc": "660", "plmn_id": "311660", "country": "United States", "region": "US", "carrier": "Metro by T-Mobile", "operator": "T-Mobile US", "status": "operational" },
    { "mcc": "314", "mnc": "100", "plmn_id": "314100", "country": "United States", "region": "US", "carrier": "Reserved for Public Safety", "operator": "Reserved for Public Safety", "status": "reserved" }
  ]
}
''';

void main() {
  final PlmnReferenceService svc = PlmnReferenceService.fromJson(_fixture);

  group('parse', () {
    test('loads every well-formed row', () {
      expect(svc.count, 5);
      expect(
        svc.all.map((e) => e.plmnId),
        containsAll(<String>['310004', '310030', '310260', '311660', '314100']),
      );
    });

    test('LOAD-BEARING: mnc keeps its leading zeros as a string', () {
      // The regression guard: "030" and "004" must survive parsing as strings,
      // never coerced to 30 / 4. A numeric cast here would corrupt the code.
      final PlmnEntry att = svc.byPlmnId('310030')!;
      expect(att.mnc, '030');
      expect(att.mnc, isA<String>());
      final PlmnEntry verizon = svc.byPlmnId('310004')!;
      expect(verizon.mnc, '004');
    });

    test('maps every field, including parent operator and status enum', () {
      final PlmnEntry tmo = svc.byPlmnId('310260')!;
      expect(tmo.mcc, '310');
      expect(tmo.mnc, '260');
      expect(tmo.carrier, 'T-Mobile');
      expect(tmo.operator, 'T-Mobile US');
      expect(tmo.region, 'US');
      expect(tmo.status, PlmnStatus.operational);
      expect(tmo.mccMncLabel, '310-260');
    });

    test('status wire tokens map to the enum; unknown is the safe fallback', () {
      expect(svc.byPlmnId('310004')!.status, PlmnStatus.operational);
      expect(svc.byPlmnId('310030')!.status, PlmnStatus.unknown);
      expect(svc.byPlmnId('314100')!.status, PlmnStatus.reserved);
      // A malformed/empty status never reads as operational.
      expect(PlmnStatusLabel.fromWire('garbage'), PlmnStatus.unknown);
      expect(PlmnStatusLabel.fromWire(''), PlmnStatus.unknown);
      expect(PlmnStatusLabel.fromWire('NOT OPERATIONAL'), PlmnStatus.notOperational);
    });

    test('drops malformed rows but keeps the good ones', () {
      const String bad = '''
      {
        "plmn": [
          { "mcc": "310", "mnc": "004", "plmn_id": "310004", "carrier": "Verizon", "operator": "Verizon Wireless", "status": "operational" },
          { "mnc": "030", "plmn_id": "310030", "carrier": "AT&T", "status": "unknown" },
          { "mcc": "310", "plmn_id": "310260", "carrier": "T-Mobile", "status": "operational" },
          { "mcc": "310", "mnc": "070", "carrier": "AT&T", "status": "operational" },
          { "mcc": "310", "mnc": "066", "plmn_id": "310066", "carrier": "", "status": "operational" },
          { "mcc": "311", "mnc": "660", "plmn_id": "311660", "carrier": "Metro by T-Mobile", "operator": "T-Mobile US", "status": "operational" }
        ]
      }
      ''';
      final PlmnReferenceService s = PlmnReferenceService.fromJson(bad);
      // Only the first (Verizon) and last (Metro) rows have all required fields.
      expect(s.count, 2);
      expect(s.all.map((e) => e.plmnId), <String>['310004', '311660']);
    });

    test('garbage document yields an empty-but-valid service', () {
      expect(PlmnReferenceService.fromJson('[]').count, 0);
      expect(PlmnReferenceService.fromJson('{"nope": true}').count, 0);
    });

    test('entries are sorted ascending by plmn_id regardless of asset order', () {
      // Fixture asset order is 030, 004, 260… — the service re-sorts to ascending.
      final List<String> ids = svc.all.map((e) => e.plmnId).toList();
      final List<String> sorted = List<String>.of(ids)..sort();
      expect(ids, sorted);
      expect(svc.all.first.plmnId, '310004');
    });
  });

  group('search by code (digit query)', () {
    test('MCC substring finds every code under that country code', () {
      final List<PlmnEntry> r = svc.search('310');
      expect(r.length, 3);
      expect(r.map((e) => e.plmnId), <String>['310004', '310030', '310260']);
    });

    test('MNC substring matches the mnc field', () {
      // "660" appears as the MNC of 311660.
      final List<PlmnEntry> r = svc.search('660');
      expect(r.single.plmnId, '311660');
    });

    test('full PLMN ID finds the exact code', () {
      expect(svc.search('310260').single.carrier, 'T-Mobile');
    });

    test('leading zeros are significant: "030" matches, "30" does not', () {
      // "030" is the AT&T MNC; "30" is a substring of no code/mnc in the fixture.
      expect(svc.search('030').single.plmnId, '310030');
      expect(svc.search('30').where((e) => e.mnc == '030'), isNotEmpty);
    });

    test('a digit query with no match returns empty, not a fabricated row', () {
      expect(svc.search('999999'), isEmpty);
    });
  });

  group('search by carrier / operator name', () {
    test('case-insensitive carrier substring matches', () {
      expect(svc.search('verizon').single.plmnId, '310004');
      expect(svc.search('T-MOBILE').map((e) => e.plmnId),
          containsAll(<String>['310260', '311660']));
    });

    test('matches the parent operator too', () {
      // "metro" is only in the carrier; "T-Mobile US" is the operator on two rows.
      final List<PlmnEntry> r = svc.search('T-Mobile US');
      expect(r.map((e) => e.plmnId), containsAll(<String>['310260', '311660']));
    });

    test('a name with no match returns empty', () {
      expect(svc.search('zzz-not-a-carrier'), isEmpty);
    });
  });

  group('grouping', () {
    test('groups by MCC ascending, omitting empty groups under a filter', () {
      final List<PlmnGroup> all = svc.grouped();
      expect(all.map((g) => g.mcc), <String>['310', '311', '314']);
      expect(all.first.count, 3);
      expect(svc.mccCount, 3);

      // Filtered grouping only includes MCCs that have a hit.
      final List<PlmnGroup> filtered = svc.grouped(svc.search('660'));
      expect(filtered.map((g) => g.mcc), <String>['311']);
    });
  });

  group('empty / whole-list query', () {
    test('empty query returns the full list, sorted by plmn_id', () {
      final List<PlmnEntry> r = svc.search('');
      expect(r.length, svc.count);
      expect(r.first.plmnId, '310004');
      expect(r.last.plmnId, '314100');
    });

    test('whitespace-only query is treated as empty', () {
      expect(svc.search('   ').length, svc.count);
    });
  });

  group('bundled asset', () {
    // Loads the actual shipped asset off disk (the same bytes pubspec bundles)
    // and asserts the row count and the leading-zero invariant on real data.
    test('assets/data/plmn_us.json parses to 376 entries with the count meta '
        'matching', () {
      final File f = File('assets/data/plmn_us.json');
      expect(f.existsSync(), isTrue,
          reason: 'bundled PLMN asset must exist at assets/data/plmn_us.json');
      final String raw = f.readAsStringSync();

      // _meta.count must equal the array length.
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
      final int metaCount =
          (decoded['_meta'] as Map<String, dynamic>)['count'] as int;
      final int arrayLen = (decoded['plmn'] as List<dynamic>).length;
      expect(metaCount, arrayLen);
      expect(arrayLen, 376);

      // Every row parses (no malformed rows in the shipped data).
      final PlmnReferenceService svc = PlmnReferenceService.fromJson(raw);
      expect(svc.count, 376);

      // 7 country codes, 310–316.
      expect(svc.mccCount, 7);
      expect(svc.grouped().map((g) => g.mcc),
          <String>['310', '311', '312', '313', '314', '315', '316']);

      // Leading-zero invariant on a real row.
      final PlmnEntry verizon = svc.byPlmnId('310004')!;
      expect(verizon.mnc, '004');
      expect(verizon.carrier, 'Verizon');
    });
  });
}
