// AntennaConnectorService unit tests — JSON parsing (incl. malformed-row
// tolerance), group ordering in FILE ORDER (never alphabetized), free-text
// search across every field, and the three editorial sections (vendor trends,
// size order, top-6). Most tests use a small in-memory fixture; the last group
// loads the REAL bundled asset to prove all 19 connectors parse, the editorial
// sections survive, and the DART entry is named WITHOUT a spelled-out acronym.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/connectors/antenna_connector_service.dart';

// Fixture: two groups in a deliberate (non-alphabetical) order, with a malformed
// row (missing connector name) that must be dropped, one RP variant, plus all
// three editorial sections.
const String _fixture = '''
{
  "schema_version": 1,
  "title": "Antenna Connectors",
  "source": "test fixture",
  "note": "An intro framing note.",
  "connector_count": 3,
  "connectors": [
    {
      "id": "rp-sma", "connector": "RP-SMA",
      "full_name": "Reverse-Polarity SMA",
      "group": "Enterprise (panel/external)",
      "reverse_polarity": "Yes (this is the RP variant of SMA)",
      "typical_wifi_use": "Consumer Wi-Fi routers and adapters",
      "indoor_outdoor": "Mostly indoor",
      "coupling": "Threaded",
      "size": "~8 mm across flats",
      "rf_path": "Single coax (1 RF path)",
      "impedance": "50 ohm",
      "frequency": "Up to 18 GHz",
      "mating": "Mates only with RP-SMA.",
      "notes": "Most common connector on consumer Wi-Fi gear."
    },
    {
      "id": "sma", "connector": "SMA",
      "full_name": "SubMiniature version A",
      "group": "Enterprise (panel/external)",
      "reverse_polarity": "No (RP-SMA is the reverse-polarity version)",
      "typical_wifi_use": "RF test gear and antennas",
      "indoor_outdoor": "Both",
      "coupling": "Threaded",
      "impedance": "50 ohm",
      "frequency": "DC to 18 GHz",
      "mating": "Mates only with standard SMA.",
      "notes": "Standard RF connector for test/lab hardware."
    },
    {
      "id": "n-type", "connector": "N-Type",
      "full_name": "Type-N",
      "group": "Outdoor / point-to-point",
      "reverse_polarity": "No",
      "typical_wifi_use": "Outdoor APs and bridges",
      "indoor_outdoor": "Excellent outdoor",
      "coupling": "Threaded, weatherproof",
      "impedance": "50 ohm",
      "frequency": "Up to ~11 GHz",
      "mating": "Mates only with standard N.",
      "notes": "Rugged, weather resistant, low loss."
    },
    {
      "id": "broken", "connector": "",
      "group": "Outdoor / point-to-point"
    }
  ],
  "vendor_trends": [
    { "vendor": "Cisco Systems", "common_connector": "RP-TNC; DART" },
    { "vendor": "Ubiquiti", "common_connector": "RP-SMA" }
  ],
  "size_order_largest_to_smallest": [ "N-Type", "SMA / RP-SMA" ],
  "size_order_note": "A practical Wi-Fi-relevant ladder.",
  "troubleshooting_class_top_6": {
    "intro": "The connectors your students are most likely to encounter:",
    "connectors": [
      { "connector": "RP-SMA", "context": "consumer Wi-Fi" },
      { "connector": "N-Type", "context": "outdoor antennas" }
    ],
    "coverage_note": "These cover most field encounters (field estimate)."
  }
}
''';

AntennaConnectorService _svc() => AntennaConnectorService.fromJson(_fixture);

void main() {
  group('parse', () {
    test('parses the well-formed connectors and drops the malformed row', () {
      final AntennaConnectorService svc = _svc();
      // 4 rows in the fixture, 1 malformed (empty connector name) → 3 parse.
      expect(svc.count, 3);
      expect(svc.byId('broken'), isNull);
    });

    test('reads title, source, and intro from the document', () {
      final AntennaConnectorService svc = _svc();
      expect(svc.title, 'Antenna Connectors');
      expect(svc.source, 'test fixture');
      expect(svc.intro, 'An intro framing note.');
    });

    test('isReversePolarity is derived from the reverse_polarity text', () {
      final AntennaConnectorService svc = _svc();
      expect(svc.byId('rp-sma')!.isReversePolarity, isTrue);
      expect(svc.byId('sma')!.isReversePolarity, isFalse);
      expect(svc.byId('n-type')!.isReversePolarity, isFalse);
    });

    test('a non-map document yields an empty-but-valid service', () {
      final AntennaConnectorService svc = AntennaConnectorService.fromJson('[]');
      expect(svc.count, 0);
      expect(svc.grouped(), isEmpty);
      expect(svc.vendorTrends, isEmpty);
    });
  });

  group('grouping (file order, never alphabetized)', () {
    test('groups appear in first-seen order, not alphabetical', () {
      final AntennaConnectorService svc = _svc();
      expect(svc.groupsInOrder, <String>[
        'Enterprise (panel/external)',
        'Outdoor / point-to-point',
      ]);
      expect(svc.groupCount, 2);
    });

    test('connectors keep file order within a group', () {
      final AntennaConnectorService svc = _svc();
      final AntennaConnectorGroup first = svc.grouped().first;
      expect(first.group, 'Enterprise (panel/external)');
      expect(
        first.connectors.map((AntennaConnector c) => c.connector).toList(),
        <String>['RP-SMA', 'SMA'],
      );
    });

    test('every connector lands in exactly one group; counts sum to 3', () {
      final AntennaConnectorService svc = _svc();
      final int sum = svc
          .grouped()
          .fold<int>(0, (int acc, AntennaConnectorGroup g) => acc + g.count);
      expect(sum, 3);
    });
  });

  group('search', () {
    test('empty query returns all connectors in file order', () {
      final AntennaConnectorService svc = _svc();
      expect(svc.search('').length, 3);
      expect(svc.search('   ').length, 3);
    });

    test('matches on connector name, case-insensitive', () {
      final AntennaConnectorService svc = _svc();
      // "n-type" appears as a connector name only on the n-type row.
      final List<AntennaConnector> r = svc.search('N-TYPE');
      expect(r.length, 1);
      expect(r.first.id, 'n-type');
    });

    test('search spans every field, including reverse_polarity text', () {
      final AntennaConnectorService svc = _svc();
      // "rp-sma" matches the rp-sma row's name AND the sma row's
      // reverse_polarity note ("RP-SMA is the reverse-polarity version") — the
      // search is intentionally across all fields, never name-only.
      final List<AntennaConnector> r = svc.search('rp-sma');
      expect(r.map((AntennaConnector c) => c.id).toSet(),
          <String>{'rp-sma', 'sma'});
    });

    test('matches on any field (notes, coupling, frequency)', () {
      final AntennaConnectorService svc = _svc();
      expect(svc.search('weatherproof').single.id, 'n-type');
      expect(svc.search('consumer').single.id, 'rp-sma');
      expect(svc.search('11 GHz').single.id, 'n-type');
    });

    test('unmatched query returns empty (never fabricates)', () {
      final AntennaConnectorService svc = _svc();
      expect(svc.search('zzznotapresentword'), isEmpty);
    });
  });

  group('editorial sections', () {
    test('vendor trends parse in file order', () {
      final AntennaConnectorService svc = _svc();
      expect(svc.vendorTrends.length, 2);
      expect(svc.vendorTrends.first.vendor, 'Cisco Systems');
      expect(svc.vendorTrends.first.commonConnector, 'RP-TNC; DART');
    });

    test('size order + note parse', () {
      final AntennaConnectorService svc = _svc();
      expect(svc.sizeOrder, <String>['N-Type', 'SMA / RP-SMA']);
      expect(svc.sizeOrderNote, 'A practical Wi-Fi-relevant ladder.');
    });

    test('top-6 block parses intro, connectors, and coverage note', () {
      final AntennaConnectorService svc = _svc();
      expect(svc.troubleshootingTop6.isEmpty, isFalse);
      expect(svc.troubleshootingTop6.connectors.length, 2);
      expect(svc.troubleshootingTop6.connectors.first.connector, 'RP-SMA');
      expect(svc.troubleshootingTop6.connectors.first.context, 'consumer Wi-Fi');
      expect(
        svc.troubleshootingTop6.coverageNote,
        contains('field estimate'),
      );
    });
  });

  group('real bundled asset', () {
    AntennaConnectorService loadReal() {
      final File asset = File('assets/data/antenna_connectors.json');
      expect(
        asset.existsSync(),
        isTrue,
        reason:
            'bundled asset must exist at assets/data/antenna_connectors.json',
      );
      return AntennaConnectorService.fromJson(asset.readAsStringSync());
    }

    test('parses all 19 connectors', () {
      // 19 = 18 + F-Type, folded in 2026-06-06 (BF6-18) from the merged
      // RF Connectors tool.
      expect(loadReal().count, 19);
    });

    test('groups into the 4 curated groups in first-seen order', () {
      final AntennaConnectorService real = loadReal();
      const List<String> expected = <String>[
        'Enterprise (panel/external)',
        'Test & cellular (Wi-Fi-adjacent)',
        'Outdoor / point-to-point',
        'Board-level / internal',
      ];
      expect(real.groupCount, 4);
      expect(real.groupsInOrder, expected);
      expect(
        real.grouped().map((AntennaConnectorGroup g) => g.group).toList(),
        expected,
      );
    });

    test('every connector lands in one group; counts sum to 19', () {
      final AntennaConnectorService real = loadReal();
      final int sum = real
          .grouped()
          .fold<int>(0, (int acc, AntennaConnectorGroup g) => acc + g.count);
      expect(sum, 19);
    });

    test('the three editorial sections are populated', () {
      final AntennaConnectorService real = loadReal();
      expect(real.vendorTrends, isNotEmpty);
      expect(real.sizeOrder, isNotEmpty);
      expect(real.troubleshootingTop6.isEmpty, isFalse);
      expect(real.troubleshootingTop6.connectors.length, 6);
    });

    test(
      'DART is named verbatim and NOT spelled out as an acronym (GL-005)',
      () {
        final AntennaConnector? dart = loadReal().byId('dart');
        expect(dart, isNotNull);
        expect(dart!.connector, 'DART');
        // The full name is Cisco's descriptive label, not an expansion.
        expect(dart.fullName, 'Cisco Smart Antenna Connector (DART)');
        // No unverified acronym expansion is ever published in any field.
        const String forbidden = 'Direct Attached RF Technology';
        final String blob = <String>[
          dart.fullName,
          dart.typicalWifiUse,
          dart.mating,
          dart.notes,
        ].join(' ');
        expect(blob.contains(forbidden), isFalse,
            reason: 'the unverified DART expansion must never appear');
      },
    );

    test('every connector in the real asset is 50 ohm', () {
      final AntennaConnectorService real = loadReal();
      for (final AntennaConnector c in real.all) {
        expect(
          c.impedance.contains('50'),
          isTrue,
          reason: '${c.connector} impedance should be 50 ohm',
        );
      }
    });

    test('every connector in the real asset has size + RF-path populated', () {
      final AntennaConnectorService real = loadReal();
      for (final AntennaConnector c in real.all) {
        expect(c.size, isNotEmpty,
            reason: '${c.connector} should have a size');
        expect(c.rfPath, isNotEmpty,
            reason: '${c.connector} should have an RF path');
      }
    });

    test('DART carries its verbatim multi-path RF value (no fabrication)', () {
      final AntennaConnector? dart = loadReal().byId('dart');
      expect(dart, isNotNull);
      expect(dart!.rfPath, contains('8 RF'));
      expect(dart.rfPath, contains('16 digital'));
    });
  });

  group('size + RF-path fields', () {
    test('size and rf_path parse from the connector object', () {
      final AntennaConnector? c = _svc().byId('rp-sma');
      expect(c, isNotNull);
      expect(c!.size, '~8 mm across flats');
      expect(c.rfPath, 'Single coax (1 RF path)');
    });

    test('search spans the new size and rf_path fields', () {
      // A query that only matches the size string returns the connector.
      expect(_svc().search('across flats').map((AntennaConnector c) => c.id),
          contains('rp-sma'));
      // A query that only matches the RF-path string returns connectors.
      expect(_svc().search('single coax'), isNotEmpty);
    });
  });
}
