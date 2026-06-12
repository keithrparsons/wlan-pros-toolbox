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

    test('parses to exactly 140 entries', () {
      // 97 = 95 (origin/main: 93 + Antenna Connectors + Optical Transceivers)
      // + 2 backfilled v1.1 help entries (PLMN ID Reference and the Wi-Fi
      // Authentication Glossary).
      // 101 = + the full v1.1 consolidation, all added 2026-06-05: 2 Guides
      // how-tos (Dual Orbs on WLAN Pi, FreeRADIUS on WLAN Pi), 1 teaching
      // reference (Antenna Fundamentals), and the Wi-Fi Tools Comparison.
      // 102 = + the Wi-Fi Glossary help entry, backfilled 2026-06-05. It was the
      // one live catalog tile (id wifi-glossary) shipping with no help footer.
      // 103 = + the "How Strong Is Wi-Fi, Really?" Quick Reference screen
      // (id wifi-exposure-perspective), added 2026-06-05 — Wi-Fi vs sunlight RF
      // exposure in perspective.
      // v1.1.2 net change 2026-06-06: −3 removed (wifi-channels BF6-13,
      // rf-connectors BF6-18, capacity-planner BF5-13) + 1 added
      // (my-current-location BF5-16) = 103 − 3 + 1 = 101.
      // 115 = + the 2026-06-08 reference batch: 14 new Quick Reference screens
      // (ip-address-reference, cidr-table, naming-conventions, dns-record-types,
      // dhcp-options, http-methods, dscp-qos, eap-types, wifi-feature-matrix,
      // regulatory-domains, datetime-standards, data-units, hash-lengths,
      // regex-cheatsheet). The 5 improved existing screens edit tools that
      // already have help entries, so add no new entries. 101 + 14 = 115.
      // 121 = + the 6 Power & Cooling pages (power-phasing, ohms-law,
      // cooling-thermal, iec-connectors, nema-connectors, international-plugs),
      // merged in from feat/power-cooling-refs 2026-06-08. 115 + 6 = 121.
      // 124 = + the 3 new Cabling & Connectors reference pages (cable-bend-radius,
      // rack-units, screw-drives) 2026-06-08. The fiber-optic extension edits an
      // existing entry, so adds none. 121 + 3 = 124.
      // 125 = + the Markdown Cheatsheet (markdown-cheatsheet) 2026-06-09.
      // 126 = + Wi-Fi Standards Bodies (wifi-standards-bodies) 2026-06-09.
      // 128 = + the 2 new tools in the 1.4.0 consolidation 2026-06-09:
      // Speed Test Services (speedtest-services) + Nearby AP Scan
      // (nearby-ap-scan, Android-only). The H1/H2/M1+M2 features augment
      // existing tools (my-current-location, wifi-info, network-discovery) and
      // add no new help ids. 126 + 2 = 128.
      // 129 = + the Modulation Quick Reference (modulation) 2026-06-11: the
      // visual companion to the MCS Index table (six constellations + an EVM
      // explainer + an order→bits→SNR/EVM summary, eight dark-baked rasters).
      // 128 + 1 = 129.
      // 131 = + the 2 Telephone Signaling History modes added to the DTMF
      // Generator 2026-06-11: Blue Box (blue-box) + US Red Box (red-box). These
      // are MODES of the existing dtmf-generator screen, not new catalog tiles,
      // so they have no tile and are listed in nonCatalogHelpIds below. The DTMF
      // entry itself was extended in place (no new id). 129 + 2 = 131.
      // 132 = + the Morse Code encoder/decoder (morse-code), a new Utilities &
      // Generators tool 2026-06-12. 131 + 1 = 132.
      // 133 = + Emergency Phrases (emergency-phrases) 2026-06-12: a searchable,
      // grouped, offline travel/emergency phrase translator (EN + es/fr/it/de)
      // in the new Travel & Field Quick Reference subgroup. 132 + 1 = 133.
      // 135 = + the 2 NEW Tier-1 Apple Wi-Fi references (Pass 2a, 2026-06-12):
      // Apple Wi-Fi Support Tips (apple-wifi-tips) + macOS Menu-Bar Wi-Fi
      // (macos-menubar-wifi), both Wi-Fi & RF Quick Reference tiles. The two
      // enrichments in the same pass (the CLI Commands 3-column split and the
      // Wireshark 802.11 filter additions) edit EXISTING screens with existing
      // help ids, so they add no new entries. 133 + 2 = 135.
      // 140 = + the 5 NEW Tier-1 references (Pass 2b, 2026-06-12), all new Quick
      // Reference tiles: Keyboard Shortcuts (keyboard-shortcuts, Encoding),
      // Cable & Connector (cable-connector, Cabling & Connectors), Time Zones
      // (time-zone-maps, Time & Formats), Phonetic Alphabet (phonetic-alphabet,
      // Encoding), and Diffie-Hellman (diffie-hellman, Wi-Fi & RF). 135 + 5 = 140.
      expect(store.count, 140);
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
    // - blue-box / red-box: the two Telephone Signaling History MODES of the
    //   DTMF Generator (2026-06-11). They are reached by the in-screen mode
    //   selector on the dtmf-generator screen, not by their own catalog tile, so
    //   the dtmf_generator_screen renders ToolHelpFooter(toolId: 'blue-box' /
    //   'red-box') depending on the active mode. Their help entries must stay and
    //   are exempt from the catalog-match requirement.
    const Set<String> nonCatalogHelpIds = <String>{
      'test-my-connection',
      'blue-box',
      'red-box',
    };

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
