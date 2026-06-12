// GlossaryService unit tests — JSON parsing (incl. malformed-row tolerance),
// category grouping in FILE ORDER (never alphabetized), and case-insensitive
// free-text search across term / abbr / definition. Most tests use a small
// in-memory fixture; the last group loads the REAL bundled asset to prove all
// 92 terms parse and group into the 8 curated categories in the expected order.

import 'dart:convert';
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

/// Load the actual bundled JSON from disk (not via rootBundle, so no Flutter
/// binding is needed) and prove the production dataset is healthy.
GlossaryService _loadReal() {
  final File asset = File('assets/data/glossary.json');
  expect(
    asset.existsSync(),
    isTrue,
    reason: 'bundled asset must exist at assets/data/glossary.json',
  );
  return GlossaryService.fromJson(asset.readAsStringSync());
}

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
    test('parses all 92 terms', () {
      expect(_loadReal().count, 92);
    });

    test('groups into the 8 curated categories in the expected order', () {
      final GlossaryService real = _loadReal();
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
      final GlossaryService real = _loadReal();
      final int sum = real
          .grouped()
          .fold<int>(0, (int acc, GlossaryGroup g) => acc + g.count);
      expect(sum, 92);
    });

    test('spot-check: RSSI carries its full-name expansion in abbr', () {
      final GlossaryTerm? rssi = _loadReal().byId('rssi');
      expect(rssi, isNotNull);
      expect(rssi!.term, 'RSSI');
      expect(rssi.abbr, 'Received Signal Strength Indicator');
      expect(rssi.category, 'Signal & RF Basics');
    });

    test('spot-check: Free Space Path Loss is multi-sentence with an acronym',
        () {
      final GlossaryTerm? fspl = _loadReal().byId('free-space-path-loss');
      expect(fspl, isNotNull);
      expect(fspl!.abbr, 'FSPL');
      // A multi-sentence definition (the curated copy explains the concept in
      // more than one sentence).
      expect(fspl.definition.contains('.'), isTrue);
      expect(fspl.definition.length, greaterThan(80));
    });
  });

  // ── Multilingual (added 2026-06-12) ─────────────────────────────────────────
  group('multilingual definitions', () {
    test('GlossaryLanguage carries all five languages, English first', () {
      expect(GlossaryLanguage.values.first, GlossaryLanguage.en);
      expect(
        GlossaryLanguage.values.map((GlossaryLanguage l) => l.code).toList(),
        <String>['en', 'es', 'fr', 'it', 'de'],
      );
      // translated == the four non-English members.
      expect(GlossaryLanguage.translated.length, 4);
      expect(GlossaryLanguage.translated.contains(GlossaryLanguage.en), isFalse);
      expect(GlossaryLanguage.fromCode('de'), GlossaryLanguage.de);
      expect(GlossaryLanguage.fromCode('zz'), isNull);
    });

    test('definitionFor returns the localized text, falling back to English',
        () {
      const String fixture = '''
{
  "title": "Wi-Fi Glossary",
  "terms": [
    {
      "id": "ofdma", "term": "OFDMA", "abbr": "Orthogonal FDMA",
      "category": "Speed, Modulation & Capacity",
      "definition": "Serves several devices at once.",
      "definitions": {
        "es": "Atiende a varios dispositivos a la vez.",
        "fr": "Sert plusieurs appareils à la fois.",
        "it": "Serve più dispositivi alla volta.",
        "de": "Bedient mehrere Geräte gleichzeitig."
      },
      "translation_status": "draft-needs-review"
    },
    {
      "id": "no-translations", "term": "Untranslated", "abbr": null,
      "category": "Speed, Modulation & Capacity",
      "definition": "English only."
    }
  ]
}
''';
      final GlossaryService svc = GlossaryService.fromJson(fixture);
      final GlossaryTerm ofdma = svc.byId('ofdma')!;
      expect(ofdma.definitionFor(GlossaryLanguage.en), 'Serves several devices at once.');
      expect(ofdma.definitionFor(GlossaryLanguage.es), 'Atiende a varios dispositivos a la vez.');
      expect(ofdma.definitionFor(GlossaryLanguage.de), 'Bedient mehrere Geräte gleichzeitig.');
      expect(ofdma.hasTranslation(GlossaryLanguage.fr), isTrue);
      expect(ofdma.hasTranslation(GlossaryLanguage.en), isFalse);

      // The term/abbr always stay English, never translated.
      expect(ofdma.term, 'OFDMA');
      expect(ofdma.abbr, 'Orthogonal FDMA');

      // A term with no translations falls back to English for every language
      // (GL-005: never blank, never fabricated).
      final GlossaryTerm none = svc.byId('no-translations')!;
      for (final GlossaryLanguage l in GlossaryLanguage.values) {
        expect(none.definitionFor(l), 'English only.');
      }
      expect(none.hasTranslation(GlossaryLanguage.es), isFalse);
    });

    test('search matches localized definition text in the active language', () {
      const String fixture = '''
{
  "title": "Wi-Fi Glossary",
  "terms": [
    {
      "id": "ssid", "term": "SSID", "abbr": "Service Set Identifier",
      "category": "Access Points, Networks & Roaming",
      "definition": "The network name devices join.",
      "definitions": {
        "es": "El nombre de red al que se unen los dispositivos.",
        "fr": "Le nom de réseau auquel les appareils se connectent.",
        "it": "Il nome di rete a cui si collegano i dispositivi.",
        "de": "Der Netzwerkname, dem Geräte beitreten."
      }
    }
  ]
}
''';
      final GlossaryService svc = GlossaryService.fromJson(fixture);
      // English term still matches regardless of language.
      expect(svc.search('SSID', lang: GlossaryLanguage.es).single.id, 'ssid');
      // A Spanish word only present in the ES definition matches under ES.
      expect(svc.search('nombre', lang: GlossaryLanguage.es).single.id, 'ssid');
      // A German word matches under DE.
      expect(svc.search('Netzwerkname', lang: GlossaryLanguage.de).single.id, 'ssid');
      // A Spanish word does NOT match under English (default behaviour preserved).
      expect(svc.search('nombre'), isEmpty);
    });

    test('DATA INTEGRITY: every real term has all five languages, none empty',
        () {
      final GlossaryService real = _loadReal();
      expect(real.count, 92);
      for (final GlossaryTerm t in real.all) {
        // English (the canonical definition) is non-empty.
        expect(
          t.definition.trim().isNotEmpty,
          isTrue,
          reason: '${t.id} has an empty English definition',
        );
        // All five language keys are present and non-empty in `definitions`.
        for (final GlossaryLanguage l in GlossaryLanguage.values) {
          final String text = t.definitionFor(l);
          expect(
            text.trim().isNotEmpty,
            isTrue,
            reason: '${t.id} has an empty ${l.code} definition',
          );
        }
        // The four translated languages each carry a genuine translation (not a
        // silent English fallback).
        for (final GlossaryLanguage l in GlossaryLanguage.translated) {
          expect(
            t.hasTranslation(l),
            isTrue,
            reason: '${t.id} is missing a ${l.code} translation',
          );
        }
      }
    });

    test('DATA INTEGRITY: the dataset declares its draft-review flag', () {
      final File asset = File('assets/data/glossary.json');
      final Map<String, dynamic> doc =
          jsonDecode(asset.readAsStringSync()) as Map<String, dynamic>;
      // Top-level provenance flags.
      expect(doc['translation_status'], 'draft-needs-review');
      expect(doc['languages'], <String>['en', 'es', 'fr', 'it', 'de']);
      // Every term carries the same per-term flag.
      final List<dynamic> terms = doc['terms'] as List<dynamic>;
      expect(terms.length, 92);
      for (final dynamic row in terms) {
        final Map<String, dynamic> m = row as Map<String, dynamic>;
        expect(
          m['translation_status'],
          'draft-needs-review',
          reason: '${m['id']} is missing the draft-review flag',
        );
      }
    });
  });
}
