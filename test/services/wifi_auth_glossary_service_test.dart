// Wi-Fi Authentication Glossary — bundled-asset health tests. Mirrors the "real
// bundled asset" group of glossary_service_test.dart but against the sibling
// dataset (assets/data/wifi_auth_glossary.json), proving all 58 authentication
// terms parse, group into their 7 curated categories in file order, search
// works, and the dataset is internally consistent (unique ids, every term in
// exactly one group). The GlossaryService is shared, so only the asset and its
// content are new — these tests guard the wiring and the data.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/glossary/glossary_service.dart';

void main() {
  // Load the actual bundled JSON from disk (not via rootBundle, so no Flutter
  // binding is needed) and prove the production dataset is healthy.
  GlossaryService loadReal() {
    final File asset = File('assets/data/wifi_auth_glossary.json');
    expect(
      asset.existsSync(),
      isTrue,
      reason: 'bundled asset must exist at assets/data/wifi_auth_glossary.json',
    );
    return GlossaryService.fromJson(asset.readAsStringSync());
  }

  group('real bundled asset', () {
    test('parses all 58 terms', () {
      expect(loadReal().count, 58);
    });

    test('reads the title from the document', () {
      expect(loadReal().title, 'Wi-Fi Authentication Glossary');
    });

    test('groups into the 7 curated categories in first-seen (file) order', () {
      final GlossaryService real = loadReal();
      const List<String> expected = <String>[
        'Core Authentication',
        'EAP & Key Exchange',
        'Roaming & Passpoint',
        'Identity & Credentials',
        'Cellular / 3GPP',
        'Security & Encryption',
        'Network Fundamentals',
      ];
      expect(real.categoryCount, 7);
      expect(real.categoriesInOrder, expected);
      // grouped() must report the same order.
      expect(
        real.grouped().map((GlossaryGroup g) => g.category).toList(),
        expected,
      );
    });

    test('every term lands in exactly one group; counts sum to 58', () {
      final GlossaryService real = loadReal();
      final int sum = real
          .grouped()
          .fold<int>(0, (int acc, GlossaryGroup g) => acc + g.count);
      expect(sum, 58);
    });

    test('term ids are unique (no collisions across the dataset)', () {
      final GlossaryService real = loadReal();
      final Set<String> ids =
          real.all.map((GlossaryTerm t) => t.id).toSet();
      expect(ids.length, real.count);
    });

    test('spot-check: RADIUS carries its full-name expansion in term', () {
      final GlossaryTerm? radius = loadReal().byId('radius');
      expect(radius, isNotNull);
      expect(radius!.abbr, 'RADIUS');
      expect(radius.category, 'Core Authentication');
      expect(radius.definition.contains('AAA'), isTrue);
    });

    test('spot-check: the two PSK acronym-collision terms both exist', () {
      final GlossaryService real = loadReal();
      // Pre-Shared Key (auth) and Phase Shift Keying (modulation) share the
      // abbreviation PSK but are distinct curated entries with distinct ids.
      final GlossaryTerm? psk = real.byId('psk-auth');
      final GlossaryTerm? pskMod = real.byId('psk-modulation');
      expect(psk, isNotNull);
      expect(pskMod, isNotNull);
      expect(psk!.abbr, 'PSK');
      expect(pskMod!.abbr, 'PSK');
      expect(psk.term, 'Pre-Shared Key');
      expect(pskMod.term, 'Phase Shift Keying');
    });

    group('search', () {
      test('matches on abbr, case-insensitive', () {
        final GlossaryService real = loadReal();
        final List<GlossaryTerm> r = real.search('eapol');
        expect(r.length, 1);
        expect(r.first.id, 'eapol');
      });

      test('matches on definition text', () {
        final GlossaryService real = loadReal();
        expect(
          real.search('Passpoint').any((GlossaryTerm t) => t.id == 'hs2-0'),
          isTrue,
        );
      });

      test('unmatched query returns empty (never fabricates)', () {
        expect(loadReal().search('zzznotapresentword'), isEmpty);
      });

      test('empty query returns all 58 terms in file order', () {
        expect(loadReal().search('   ').length, 58);
      });
    });
  });
}
