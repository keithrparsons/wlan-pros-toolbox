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
      // 138 = − 2 from the 2026-06-12 Cabling consolidation: the ethernet-pinout
      // and cable-connector tiles were merged into ethernet-cable (retitled
      // "Ethernet Cable & Connector"), which keeps its single help entry. Their
      // two help entries were removed. 140 − 2 = 138.
      // 140 = + the 2 NEW Tier-1 references (integration batch, 2026-06-12):
      // RF Bands (rf-bands) and Wi-Fi HaLow (wifi-halow), both Wi-Fi & RF Quick
      // Reference tiles with their own help entries. 138 + 2 = 140.
      // 141 = + the Roaming Log (roaming-log) 2026-06-13: the foreground roam
      // recorder in Test Network, built on the shared WifiSignalSampler +
      // RoamDetector (Feature 2). The Cloud Apps reachability panel added the
      // same day lives on the existing test-my-connection screen (its help entry
      // was extended in place), so it adds no new help id. 140 + 1 = 141.
      // 142 = + Analyze Results (analyze-results) 2026-06-16: the in-app local
      // rule-engine report reached by the "Analyze my results" button on the
      // Test My Connection result screen (NOT a catalog tile), so it is exempt
      // from the catalog-match requirement via nonCatalogHelpIds below.
      // 141 + 1 = 142.
      // 143 = + Time Server (NTP) (ntp-time) 2026-06-21: an SNTP client in
      // Networking Tools (server time + signed clock offset + round-trip delay
      // over UDP/123). 142 + 1 = 143.
      // 144 = + Channel / Frequency (channel-frequency) 2026-06-27: bidirectional
      // Wi-Fi channel<->frequency converter in Calculators & Tools (Conversions),
      // built from the verified channel-plan.md sec 7 vectors. 143 + 1 = 144.
      // 146 = + the 2 Ham Radio pure-math tools (2026-06-28), both in the new
      // "Ham Radio" subgroup of Calculators & Tools: Antenna Length
      // (antenna-length) and Maidenhead Grid Square (maidenhead-grid).
      // 144 + 2 = 146.
      // 151 = + the 5 Ham Radio band references (2026-06-28): 4 Quick Reference
      // tiles in the new "Ham Radio" subgroup (US Amateur Band Plan
      // ham-band-plan, Band Names & Wavelengths ham-band-wavelengths, Spectrum
      // Band Designations band-designations, Part 15 vs Part 97 part15-part97)
      // plus 1 Educational Resources tile (Ham Radio Study Resources
      // ham-study-resources). 146 + 5 = 151.
      // 153 = + the 2 Ham Radio PDF reference cards (2026-06-28), both Quick
      // Reference tiles in the "Ham Radio" subgroup, rendered in the shared
      // PdfReferenceScreen: General License Frequency Chart
      // (general-license-frequency-chart) and Ham Radio General Exam Study Notes
      // (ham-radio-general-exam-study-notes). 151 + 2 = 153.
      // 154 = + Hear the Frequency (hear-frequency) 2026-06-28: the first
      // "Learn / RF intuition" tool in Calculators & Tools - a real-time tone
      // generator (flutter_soloud behind the ToneEngine seam) that bridges
      // audio pitch/octaves/harmonics to RF, with the honest limits flagged
      // (an octave is not a dB; RF harmonics are the unwanted kind). 153 + 1 = 154.
      // 155 = + the Spectrum Analysis teaching module (spectrum-analysis)
      // 2026-06-28: an in-app reference in Educational Resources (hub + 8 topic
      // screens: NIC-vs-spectrum, how it works, the knobs, the three views, a
      // nine-card interferer signature gallery, comparing captures, the tool
      // landscape, mitigation). The hub carries the one help footer. 154 + 1 = 155.
      // 156 = + Architectural Scale (architectural-scale) 2026-07-05: the pilot
      // tool of the AEC & Documentation field-reference set — a scale↔ratio and
      // drawn↔real converter (architectural / engineer's / metric scales), pure
      // on-device math in Calculators & Tools. 155 + 1 = 156.
      // 157 = + Enclosure Ratings (enclosure-ratings) 2026-07-05: the pilot
      // REFERENCE-screen entry of the Field & Trade Reference set — a read-only
      // IP (IEC 60529) / NEMA (NEMA 250) ingress-rating decoder in Quick
      // Reference (proposed "Codes & Safety" subgroup). 156 + 1 = 157.
      // 158 = + Hazardous Locations (hazardous-locations) 2026-07-05: Field
      // Reference #3 — a read-only Class/Division (NEC 500) and IEC Zone
      // recognize-and-defer reference in Quick Reference ("Codes & Safety").
      // 157 + 1 = 158.
      // 159 = + NEC Gotchas (nec-gotchas) 2026-07-05: Field Reference #4 — the
      // read-only recognize-and-defer set of NEC articles that bite a WLAN
      // install, in Quick Reference ("Codes & Safety"). 158 + 1 = 159.
      // 162 = + the next 3 Field & Trade Reference screens (2026-07-05), all
      // read-only in Quick Reference ("Codes & Safety"): Safety Basics
      // (safety-basics) PPE + ESD + recognize-and-STOP hazards; Plan-Set
      // Literacy (plan-set-literacy) sheet-number anatomy + the RCP as the AP
      // sheet (placement flagged for Keith, defaulted to Codes & Safety); Site
      // Access (site-access) the "Know Before You Go" pre-mobilization
      // checklist. 159 + 3 = 162.
      // 165 = + the last 3 Field & Trade Reference screens (2026-07-05), all
      // read-only text-reference (no decoder plate) in Quick Reference ("Codes &
      // Safety"): CAD & BIM Formats (cad-bim-formats) the format decode table +
      // LOD ladder + CAD-to-Wi-Fi-design import flow; Structured Cabling
      // (structured-cabling) the TIA/BICSI standards + 90 m channel + cable
      // categories; AEC Process & Glossary (aec-process-glossary) the AIA design
      // phases + the AEC shorthand. 162 + 3 = 165.
      expect(store.count, 165);
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
    // - analyze-results: the in-app local rule-engine report (2026-06-16),
    //   reached by the "Analyze my results" button on the test-my-connection
    //   result screen, NOT a catalog tile. Its screen renders
    //   ToolHelpFooter(toolId: 'analyze-results'), so the help entry must stay
    //   and is exempt from the catalog-match requirement.
    const Set<String> nonCatalogHelpIds = <String>{
      'test-my-connection',
      'blue-box',
      'red-box',
      'analyze-results',
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
