// ToolHelp loader + model tests.
//
// Coverage:
// - The pure parser (ToolHelpStore.fromJson): a well-formed fixture, malformed
//   entries dropped, garbage document → empty-but-valid, null algorithm/example
//   preserved as null, field notes preserved verbatim (GL-005).
// - The REAL bundled asset (assets/help/tool_help.json): parses to exactly 97
//   entries, and every key matches a catalog tool id (the lookup contract),
//   except for a small allowlist of known non-catalog help ids.
// - helpForId() reads the cached store and returns null for an unknown id.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help_loader.dart';

const String _fixture = '''
{
  "version": "1.0",
  "generatedFrom": "test",
  "tools": {
    "fspl": {
      "name": "Free Space Path Loss",
      "category": "Calculators & Tools",
      "purpose": "Computes path loss.",
      "whyHere": "Start of a link budget.",
      "howToUse": ["Enter frequency.", "Enter distance.", "Read dB."],
      "inputs": [
        { "name": "Frequency", "unit": "GHz", "range": "must be > 0" },
        { "name": "Distance", "unit": "km", "range": "must be > 0" }
      ],
      "algorithm": "FSPL(dB) = 20·log10(f) + 20·log10(d) + 92.45",
      "example": "5 GHz, 1 km -> 106.4 dB.",
      "fieldNotes": ["Free space only. Real links lose more."],
      "source": "fspl_screen.dart"
    },
    "wifi-channels": {
      "name": "Wi-Fi Channels",
      "category": "Quick Reference",
      "purpose": "Lists channels by band.",
      "whyHere": "Look up a channel fast.",
      "howToUse": [],
      "inputs": [],
      "algorithm": null,
      "example": null,
      "fieldNotes": ["DFS channels may require radar avoidance."],
      "source": "wifi_channels_screen.dart"
    },
    "broken-no-name": {
      "category": "Quick Reference",
      "purpose": "no name -> dropped"
    }
  }
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ToolHelpStore.fromJson (pure parse)', () {
    final ToolHelpStore store = ToolHelpStore.fromJson(_fixture);

    test('parses the well-formed entries and drops the broken one', () {
      // fspl + wifi-channels parse; broken-no-name (no name) is dropped.
      expect(store.count, 2);
      expect(store.forId('fspl'), isNotNull);
      expect(store.forId('wifi-channels'), isNotNull);
      expect(store.forId('broken-no-name'), isNull);
    });

    test('maps every field of a full entry', () {
      final ToolHelp h = store.forId('fspl')!;
      expect(h.id, 'fspl');
      expect(h.name, 'Free Space Path Loss');
      expect(h.category, 'Calculators & Tools');
      expect(h.purpose, contains('path loss'));
      expect(h.whyHere, contains('link budget'));
      expect(h.howToUse, hasLength(3));
      expect(h.inputs, hasLength(2));
      expect(h.inputs.first.name, 'Frequency');
      expect(h.inputs.first.unit, 'GHz');
      expect(h.inputs.first.range, 'must be > 0');
      expect(h.algorithm, contains('FSPL(dB)'));
      expect(h.example, contains('106.4 dB'));
      expect(h.fieldNotes, hasLength(1));
      expect(h.source, 'fspl_screen.dart');
    });

    test('preserves null algorithm/example and empty lists', () {
      final ToolHelp h = store.forId('wifi-channels')!;
      expect(h.algorithm, isNull);
      expect(h.example, isNull);
      expect(h.howToUse, isEmpty);
      expect(h.inputs, isEmpty);
      // Field notes are preserved verbatim (GL-005), never dropped.
      expect(h.fieldNotes, <String>['DFS channels may require radar avoidance.']);
    });

    test('algorithmReadsAsFormula is true for a formula, false otherwise', () {
      expect(store.forId('fspl')!.algorithmReadsAsFormula, isTrue);
      // wifi-channels has a null algorithm -> not a formula.
      expect(store.forId('wifi-channels')!.algorithmReadsAsFormula, isFalse);
    });

    test('garbage documents yield an empty-but-valid store', () {
      expect(ToolHelpStore.fromJson('[]').count, 0);
      expect(ToolHelpStore.fromJson('{"nope": true}').count, 0);
      expect(ToolHelpStore.fromJson('not json at all').count, 0);
    });
  });

  group('real bundled asset (assets/help/tool_help.json)', () {
    late ToolHelpStore store;

    setUpAll(() async {
      final String raw = await rootBundle.loadString(kToolHelpAsset);
      store = ToolHelpStore.fromJson(raw);
    });

    test('parses to exactly 98 entries', () {
      // 98 = 95 (origin/main: 93 + Antenna Connectors + Optical Transceivers)
      // + 2 backfilled v1.1 help entries (PLMN ID Reference and the Wi-Fi
      // Authentication Glossary) + 1 v1.1 Guides entry: Dual Orbs on WLAN Pi
      // (added 2026-06-05).
      expect(store.count, 98);
    });

    // Help ids that intentionally have NO catalog tile but still ship a help
    // entry, because they back a screen reached by a route other than a
    // category tile.
    //
    // - test-my-connection: the merged consumer tool (Test My Connection + the
    //   pro Wi-Fi vs Internet folded into one screen, Keith 2026-06-04). It is
    //   reached via the home consumer hero, NOT a catalog tile, but its screen
    //   renders ToolHelpFooter(toolId: 'test-my-connection'), so the help entry
    //   must stay and is exempt from the catalog-match requirement.
    const Set<String> nonCatalogHelpIds = <String>{'test-my-connection'};

    test('every help key matches a catalog tool id', () {
      // Build the set of all catalog tool ids (not category ids).
      final Set<String> catalogToolIds = <String>{
        for (final ToolCategory c in kToolCategories)
          for (final ToolEntry t in c.tools) t.id,
      };
      for (final ToolHelp h in store.all) {
        if (nonCatalogHelpIds.contains(h.id)) continue;
        expect(
          catalogToolIds.contains(h.id),
          isTrue,
          reason: 'help id "${h.id}" has no matching catalog tool id',
        );
      }
    });

    test('every entry carries a non-empty name, purpose, and source', () {
      for (final ToolHelp h in store.all) {
        expect(h.name, isNotEmpty, reason: '${h.id} name');
        expect(h.purpose, isNotEmpty, reason: '${h.id} purpose');
        expect(h.source, isNotEmpty, reason: '${h.id} source');
      }
    });
  });

  group('helpForId + cache', () {
    test('reads the injected store and returns null for an unknown id', () {
      final ToolHelpStore store = ToolHelpStore.fromJson(_fixture);
      ToolHelpLoader.debugSetStore(store);
      addTearDown(() => ToolHelpLoader.debugSetStore(null));

      expect(helpForId('fspl'), isNotNull);
      expect(helpForId('does-not-exist'), isNull);
    });

    test('helpForId is null before any store is loaded', () {
      ToolHelpLoader.debugSetStore(null);
      expect(helpForId('fspl'), isNull);
    });
  });

  group('asset shape sanity (top-level JSON)', () {
    test('document has a tools object keyed by string ids', () async {
      final String raw = await rootBundle.loadString(kToolHelpAsset);
      final Object? decoded = jsonDecode(raw);
      expect(decoded, isA<Map<String, dynamic>>());
      final Map<String, dynamic> map = decoded as Map<String, dynamic>;
      expect(map['tools'], isA<Map<String, dynamic>>());
    });
  });
}
