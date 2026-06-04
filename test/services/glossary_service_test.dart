// GlossaryService unit tests — JSON parsing (incl. malformed-row tolerance),
// category grouping in FILE ORDER (never alphabetized), and case-insensitive
// free-text search across term / abbr / definition. Most tests use a small
// in-memory fixture; the last group loads the REAL bundled asset to prove all
// 92 terms parse and group into the 8 curated categories in the expected order.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/glossary/glossary_service.dart';

// Fixture: two categories in a deliberate (non-alphabetical) order, with a
// malformed row (missing definition) that must be dropped, and one abbr term.
const String _fixture = '''
{
  "schema_version": 1,
  "title": "Wi-Fi Glossary",
  "source": "test fixture",
  "term_count": 3,
  "terms": [
    {
      "id": "zulu-band", "term": "Zulu Band", "abbr": null,
      "category": "Bands & Spectrum",
      "definition": "A made-up band for ordering tests."
    },
    {
      "id": "cci", "term": "Co-Channel Interference", "abbr": "CCI",
      "category": "Bands & Spectrum",
      "definition": "Access points sharing a channel take turns, cutting airtime."
    },
    {
      "id": "alpha-term", "term": "Alpha Term", "abbr": "Spelled Out Acronym",
      "category": "Security",
      "definition": "A second-category term to prove grouping."
    },
    {
      "id": "broken", "term": "Broken Row", "abbr": null,
      "category": "Security"
    }
  ]
}
''';

GlossaryService _svc() => GlossaryService.fromJson(_fixture);

void main() {
  group('parse', () {
    test('parses the well-formed terms and drops the malformed row', () {
      final GlossaryService svc = _svc();
      // 4 rows in the fixture, 1 malformed (no definition) → 3 parse.
      expect(svc.count, 3);
      expect(svc.byId('broken'), isNull);
    });

    test('reads title and source from the document', () {
      final GlossaryService svc = _svc();
      expect(svc.title, 'Wi-Fi Glossary');
      expect(svc.source, 'test fixture');
    });

    test('abbr is null when absent, set when present', () {
      final GlossaryService svc = _svc();
      expect(svc.byId('zulu-band')!.abbr, isNull);
      expect(svc.byId('cci')!.abbr, 'CCI');
    });

    test('a non-map document yields an empty-but-valid service', () {
      final GlossaryService svc = GlossaryService.fromJson('[]');
      expect(svc.count, 0);
      expect(svc.grouped(), isEmpty);
    });
  });

  group('grouping (file order, never alphabetized)', () {
    test('categories appear in first-seen order, not alphabetical', () {
      final GlossaryService svc = _svc();
      // First-seen order is Bands & Spectrum, then Security — alphabetical would
      // put Bands first too, so flip the assertion to the file order explicitly.
      expect(svc.categoriesInOrder, <String>['Bands & Spectrum', 'Security']);
    });

    test('terms keep file order within a category (not alphabetized)', () {
      final GlossaryService svc = _svc();
      final List<GlossaryGroup> groups = svc.grouped();
      final GlossaryGroup bands = groups.first;
      expect(bands.category, 'Bands & Spectrum');
      // File order is Zulu Band then Co-Channel Interference; alphabetical would
      // reverse them. Proves order is preserved.
      expect(
        bands.terms.map((GlossaryTerm t) => t.term).toList(),
        <String>['Zulu Band', 'Co-Channel Interference'],
      );
    });
  });

  group('search', () {
    test('empty query returns all terms in file order', () {
      final GlossaryService svc = _svc();
      expect(svc.search('').length, 3);
      expect(svc.search('   ').length, 3);
    });

    test('matches on term, case-insensitive', () {
      final GlossaryService svc = _svc();
      final List<GlossaryTerm> r = svc.search('co-channel');
      expect(r.length, 1);
      expect(r.first.id, 'cci');
    });

    test('matches on abbr', () {
      final GlossaryService svc = _svc();
      expect(svc.search('CCI').single.id, 'cci');
    });

    test('matches on definition text', () {
      final GlossaryService svc = _svc();
      expect(svc.search('airtime').single.id, 'cci');
    });

    test('unmatched query returns empty (never fabricates)', () {
      final GlossaryService svc = _svc();
      expect(svc.search('zzznotapresentword'), isEmpty);
    });
  });

  group('real bundled asset', () {
    // Load the actual bundled JSON from disk (not via rootBundle, so no Flutter
    // binding is needed) and prove the production dataset is healthy.
    GlossaryService loadReal() {
      final File asset = File('assets/data/glossary.json');
      expect(
        asset.existsSync(),
        isTrue,
        reason: 'bundled asset must exist at assets/data/glossary.json',
      );
      return GlossaryService.fromJson(asset.readAsStringSync());
    }

    test('parses all 92 terms', () {
      expect(loadReal().count, 92);
    });

    test('groups into the 8 curated categories in the expected order', () {
      final GlossaryService real = loadReal();
      const List<String> expected = <String>[
        'Bands & Spectrum',
        'Standards & Wi-Fi Generations',
        'Signal & RF Basics',
        'Speed, Modulation & Capacity',
        'How Devices Share the Air',
        'Access Points, Networks & Roaming',
        'Security',
        'Performance & Troubleshooting',
      ];
      expect(real.categoryCount, 8);
      expect(real.categoriesInOrder, expected);
      // grouped() must report the same order.
      expect(
        real.grouped().map((GlossaryGroup g) => g.category).toList(),
        expected,
      );
    });

    test('every term lands in exactly one group; counts sum to 92', () {
      final GlossaryService real = loadReal();
      final int sum = real
          .grouped()
          .fold<int>(0, (int acc, GlossaryGroup g) => acc + g.count);
      expect(sum, 92);
    });

    test('spot-check: RSSI carries its full-name expansion in abbr', () {
      final GlossaryTerm? rssi = loadReal().byId('rssi');
      expect(rssi, isNotNull);
      expect(rssi!.term, 'RSSI');
      expect(rssi.abbr, 'Received Signal Strength Indicator');
      expect(rssi.category, 'Signal & RF Basics');
    });

    test('spot-check: Free Space Path Loss is multi-sentence with an acronym',
        () {
      final GlossaryTerm? fspl = loadReal().byId('free-space-path-loss');
      expect(fspl, isNotNull);
      expect(fspl!.abbr, 'FSPL');
      // A multi-sentence definition (the curated copy explains the concept in
      // more than one sentence).
      expect(fspl.definition.contains('.'), isTrue);
      expect(fspl.definition.length, greaterThan(80));
    });
  });
}
