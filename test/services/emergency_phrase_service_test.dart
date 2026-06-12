// EmergencyPhraseService tests — data integrity + parse/group/search behavior.
//
// Two scopes:
//  1. Pure-Dart unit tests against in-memory fixtures (parse, drop-malformed,
//     group order, search across all five languages, draft-flag surfacing).
//  2. The REAL bundled asset (assets/data/emergency_phrases.json): every phrase
//     carries all five languages with no empties, ids are unique, the dataset is
//     flagged draft-needs-review, and the curated group order holds.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/emergency_phrases_screen.dart';
import 'package:wlan_pros_toolbox/services/phrases/emergency_phrase_service.dart';

const String _fixture = '''
{
  "title": "Test Phrases",
  "translation_status": "draft-needs-review",
  "translation_note": "Draft only.",
  "languages": [
    { "code": "en", "label": "English", "native": "English" },
    { "code": "es", "label": "Spanish", "native": "Español" },
    { "code": "fr", "label": "French", "native": "Français" },
    { "code": "it", "label": "Italian", "native": "Italiano" },
    { "code": "de", "label": "German", "native": "Deutsch" }
  ],
  "phrases": [
    { "id": "help", "category": "Medical", "en": "Help!", "es": "¡Ayuda!", "fr": "Au secours !", "it": "Aiuto!", "de": "Hilfe!" },
    { "id": "thanks", "category": "Basics", "en": "Thank you.", "es": "Gracias.", "fr": "Merci.", "it": "Grazie.", "de": "Danke." },
    { "id": "sorry", "category": "Basics", "en": "Sorry.", "es": "Lo siento.", "fr": "Désolé.", "it": "Scusa.", "de": "Entschuldigung." },
    { "id": "bad-missing-de", "category": "Basics", "en": "x", "es": "x", "fr": "x", "it": "x" },
    { "id": "bad-empty-fr", "category": "Basics", "en": "x", "es": "x", "fr": "   ", "it": "x", "de": "x" },
    { "id": "", "category": "Basics", "en": "x", "es": "x", "fr": "x", "it": "x", "de": "x" }
  ]
}
''';

void main() {
  group('parse + drop malformed', () {
    test('keeps well-formed rows and drops rows missing any language', () {
      final EmergencyPhraseService svc =
          EmergencyPhraseService.fromJson(_fixture);
      // 3 valid; 3 malformed (missing de, empty fr, empty id) dropped.
      expect(svc.count, 3);
      expect(svc.byId('help'), isNotNull);
      expect(svc.byId('bad-missing-de'), isNull);
      expect(svc.byId('bad-empty-fr'), isNull);
    });

    test('every surviving row has all five languages, non-empty', () {
      final EmergencyPhraseService svc =
          EmergencyPhraseService.fromJson(_fixture);
      for (final EmergencyPhrase p in svc.all) {
        for (final String code in <String>['en', 'es', 'fr', 'it', 'de']) {
          final String? v = p.forCode(code);
          expect(v, isNotNull, reason: '${p.id} missing $code');
          expect(v!.trim(), isNotEmpty, reason: '${p.id} empty $code');
        }
      }
    });

    test('title, languages, and draft flag are surfaced', () {
      final EmergencyPhraseService svc =
          EmergencyPhraseService.fromJson(_fixture);
      expect(svc.title, 'Test Phrases');
      expect(svc.isDraft, isTrue);
      expect(svc.translationStatus, kDraftNeedsReview);
      expect(svc.translationNote, 'Draft only.');
      expect(svc.sourceLanguage.code, 'en');
      expect(svc.targetLanguages.map((PhraseLanguage l) => l.code).toList(),
          <String>['es', 'fr', 'it', 'de']);
    });

    test('garbage / wrong-shape input yields an empty-but-valid service', () {
      expect(EmergencyPhraseService.fromJson('[]').count, 0);
      expect(EmergencyPhraseService.fromJson('not json').count, 0);
      expect(EmergencyPhraseService.fromJson('{"nope": true}').count, 0);
    });
  });

  group('grouping', () {
    test('groups appear in first-seen file order, not alphabetized', () {
      final EmergencyPhraseService svc =
          EmergencyPhraseService.fromJson(_fixture);
      final List<PhraseGroup> groups = svc.grouped();
      expect(groups.map((PhraseGroup g) => g.category).toList(),
          <String>['Medical', 'Basics']);
      expect(groups.first.count, 1);
      expect(groups.last.count, 2);
    });
  });

  group('search', () {
    test('empty query returns all in file order', () {
      final EmergencyPhraseService svc =
          EmergencyPhraseService.fromJson(_fixture);
      expect(svc.search('').length, svc.count);
      expect(svc.search('   ').length, svc.count);
    });

    test('matches across every language, case-insensitive', () {
      final EmergencyPhraseService svc =
          EmergencyPhraseService.fromJson(_fixture);
      expect(svc.search('help').single.id, 'help'); // English
      expect(svc.search('ayuda').single.id, 'help'); // Spanish
      expect(svc.search('SECOURS').single.id, 'help'); // French, upper
      expect(svc.search('grazie').single.id, 'thanks'); // Italian
      expect(svc.search('danke').single.id, 'thanks'); // German
    });

    test('no match returns empty, never a fabricated row', () {
      final EmergencyPhraseService svc =
          EmergencyPhraseService.fromJson(_fixture);
      expect(svc.search('zzznotpresent'), isEmpty);
    });
  });

  group('real bundled asset (assets/data/emergency_phrases.json)', () {
    late EmergencyPhraseService svc;
    late Map<String, dynamic> raw;

    setUpAll(() async {
      final String json =
          await rootBundle.loadString(kEmergencyPhrasesAsset);
      svc = EmergencyPhraseService.fromJson(json);
      raw = jsonDecode(json) as Map<String, dynamic>;
    });

    test('parses about 124 phrases (at least 100)', () {
      // Every row in the asset must be well-formed (none dropped), so the
      // service count equals the raw phrase count. Guards against a future edit
      // that drops a language and silently shrinks the list.
      final int rawCount = (raw['phrases'] as List).length;
      expect(svc.count, rawCount, reason: 'a row was dropped as malformed');
      expect(svc.count, greaterThanOrEqualTo(100));
    });

    test('every phrase carries all five languages, none empty', () {
      for (final EmergencyPhrase p in svc.all) {
        for (final String code in <String>['en', 'es', 'fr', 'it', 'de']) {
          final String? v = p.forCode(code);
          expect(v, isNotNull, reason: '${p.id} missing $code');
          expect(v!.trim(), isNotEmpty, reason: '${p.id} empty $code');
        }
      }
    });

    test('phrase ids are unique', () {
      final List<String> ids =
          svc.all.map((EmergencyPhrase p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('dataset is flagged draft-needs-review with a note', () {
      expect(svc.isDraft, isTrue,
          reason: 'translations must be flagged draft pending native review');
      expect(svc.translationStatus, kDraftNeedsReview);
      expect(svc.translationNote, isNotEmpty);
    });

    test('the five languages are EN + es/fr/it/de in order', () {
      expect(svc.languages.map((PhraseLanguage l) => l.code).toList(),
          <String>['en', 'es', 'fr', 'it', 'de']);
    });

    test('every phrase belongs to a known curated situation group', () {
      const Set<String> known = <String>{
        'Basics & courtesy',
        'Medical & help',
        'Directions',
        'Food & lodging',
        'Problems & requests',
        'On-site & technical',
        'Numbers & time',
      };
      for (final EmergencyPhrase p in svc.all) {
        expect(known.contains(p.category), isTrue,
            reason: '${p.id} has unexpected category "${p.category}"');
      }
      // And the section order is the curated one (first-seen), not alphabetical.
      expect(svc.categoryCount, known.length);
    });
  });
}
