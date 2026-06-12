// Tests for the Tier-1 reference screens wired in Pass 2b (2026-06-12):
//   keyboard-shortcuts, time-zone-maps, phonetic-alphabet, diffie-hellman.
//
// The former Pass-2b `cable-connector` tile was consolidated 2026-06-12 into
// the existing `ethernet-cable` tool (retitled "Ethernet Cable & Connector").
// Its Cat 7 ISO/IEC-Class-F caveat fidelity now asserts against
// EthernetCableScreen.cat7Caveat; the pinout pair-swap fidelity is covered by
// ethernet_cable_pinout_test.dart.
//
// Three layers, mirroring the established per-screen reference tests:
//   1. Data fidelity (GL-005): the typed const datasets carry the load-bearing
//      facts and caveats from the staged DATA (ICAO "Alfa"/"Juliett"; the Cat 7
//      ISO/IEC-Class-F-not-TIA caveat; the WPA3 SAE tie-in; standard-time
//      offsets), plus the no-em-dash rule across all rendered prose.
//   2. Registration: each new tool has a catalog tile (right subgroup), a
//      registered route builder, a keyword set, and a help entry. Count guard is
//      asserted in tool_help_loader_test (135 -> 140).
//   3. Widget render: each read-only screen renders its title and key content
//      across phone/tablet/desktop widths, in BOTH dark and light themes, with no
//      RenderFlex overflow; the embedded-PNG screens omit the image card when the
//      asset is not bundled (graceful degradation) and show exactly one when it
//      is.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/diffie_hellman_data.dart';
import 'package:wlan_pros_toolbox/data/keyboard_shortcuts_data.dart';
import 'package:wlan_pros_toolbox/data/phonetic_alphabet_data.dart';
import 'package:wlan_pros_toolbox/data/reference_images.dart';
import 'package:wlan_pros_toolbox/data/time_zones_data.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/diffie_hellman_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/ethernet_cable_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/keyboard_shortcuts_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/phonetic_alphabet_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/time_zones_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/dark_raster_diagram_card.dart';

void main() {
  group('data fidelity (GL-005)', () {
    test(
      'Keyboard Shortcuts: six panels of facts, Greek includes lambda/ohms',
      () {
        // Four shortcut groups + the symbol + Greek panels.
        expect(kShortcutGroups.length, 4);
        expect(kMacSymbols, isNotEmpty);
        expect(kGreekLetters.length, 16);
        // The RF-relevant Greek letters the card is justified by.
        expect(
          kGreekLetters.any(
            (GreekRow g) => g.name == 'lambda' && g.lower == 'λ',
          ),
          isTrue,
        );
        expect(
          kGreekLetters.any(
            (GreekRow g) => g.name == 'omega' && g.lower == 'ω',
          ),
          isTrue,
        );
        // The degree-vs-ordinal caveat is carried, not silently dropped.
        expect(kMacSymbolsNote.toLowerCase().contains('ordinal'), isTrue);
      },
    );

    test(
      'Ethernet Cable & Connector: Cat 7 carries the ISO/IEC-Class-F not-TIA '
      'caveat (merged from cable-connector)',
      () {
        // The Cat 7 row exists in the survivor's category chart.
        final EthCable cat7 = EthernetCableScreen.ethData.firstWhere(
          (EthCable c) => c.category == 'Cat7',
        );
        expect(cat7.poe, 'Limited');
        // The non-TIA caveat is surfaced as a warning verdict on the screen.
        expect(
          EthernetCableScreen.cat7Caveat.toLowerCase().contains(
            'never ratified category 7',
          ),
          isTrue,
        );
        expect(
          EthernetCableScreen.cat7Caveat.contains('ISO/IEC Class F'),
          isTrue,
        );
        // Pinout: T568A and T568B differ only on pairs 2 & 3 (orange/green) at
        // pins 1,2,3,6 (the pair-swap fidelity, folded in from the pinout tile).
        final List<PinoutPin> b =
            EthernetCableScreen.pinout[WiringStandard.t568b]!;
        final List<PinoutPin> a =
            EthernetCableScreen.pinout[WiringStandard.t568a]!;
        expect(b.length, 8);
        expect(a.length, 8);
        expect(
          b[3].colorName,
          a[3].colorName,
          reason: 'pin 4 (blue) unchanged',
        );
        expect(
          b[6].colorName,
          a[6].colorName,
          reason: 'pin 7 (white/brown) unchanged',
        );
        expect(
          b[0].colorName == a[0].colorName,
          isFalse,
          reason: 'pin 1 swaps orange<->green between B and A',
        );
      },
    );

    test('Time Zones: offsets are standard time; US table has 6 zones', () {
      expect(kUtcOffsets, isNotEmpty);
      expect(kUsTimeZones.length, 6);
      expect(kTimeZonesDstNote.toLowerCase().contains('standard time'), isTrue);
      // India half-hour offset is present.
      expect(kUtcOffsets.any((UtcOffset o) => o.offset == 'UTC +5:30'), isTrue);
      // Arizona MST-year-round note carried on the Mountain row.
      final UsTimeZone mountain = kUsTimeZones.firstWhere(
        (UsTimeZone z) => z.zone == 'Mountain',
      );
      expect(mountain.daylight.toLowerCase().contains('arizona'), isTrue);
    });

    test(
      'Phonetic Alphabet: ICAO Alfa/Juliett spelling, 26 letters, no digits',
      () {
        expect(kPhoneticAlphabet.length, 26);
        final PhoneticLetter a = kPhoneticAlphabet.firstWhere(
          (PhoneticLetter p) => p.letter == 'A',
        );
        expect(a.word, 'Alfa', reason: 'ICAO official spelling, not Alpha');
        final PhoneticLetter j = kPhoneticAlphabet.firstWhere(
          (PhoneticLetter p) => p.letter == 'J',
        );
        expect(j.word, 'Juliett', reason: 'ICAO official spelling, double-t');
        // Morse is carried.
        expect(a.morse, '.-');
      },
    );

    test('Diffie-Hellman: paint analogy + math, tied to WPA3 SAE', () {
      expect(kDhStages, isNotEmpty);
      // The math is carried verbatim for the public mixtures.
      expect(
        kDhStages.any((DhStage s) => s.math.contains('A = g^a mod p')),
        isTrue,
      );
      // The WLAN tie-in names SAE / WPA3.
      expect(kDhWlanRelevance.contains('SAE'), isTrue);
      expect(kDhWlanRelevance.contains('WPA3'), isTrue);
    });

    test('no em dash in any rendered prose across the datasets', () {
      final List<String> prose = <String>[
        kMacSymbolsNote,
        EthernetCableScreen.cat7Caveat,
        EthernetCableScreen.pinoutFootnote,
        kUtcOffsetsNote,
        kTimeZonesDstNote,
        kPhoneticNote,
        ...kPhoneticLegend,
        kDhSummary,
        kDhEavesdropperVerdict,
        kDhWlanRelevance,
        for (final ShortcutGroup g in kShortcutGroups) ...<String>[
          g.title,
          for (final ShortcutRow r in g.rows) r.action,
        ],
        for (final UsTimeZone z in kUsTimeZones) z.daylight,
        for (final DhStage s in kDhStages) ...<String>[s.analogy, s.math],
      ];
      for (final String s in prose) {
        // The em-dash ROW in the Mac symbols panel is reference DATA (the literal
        // symbol the card teaches), excluded from this prose sweep on purpose.
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
      }
    });
  });

  group('registration (catalog + router + keywords)', () {
    // cable-connector removed 2026-06-12 (merged into ethernet-cable).
    const Map<String, String> subgroupById = <String, String>{
      'keyboard-shortcuts': 'Encoding',
      'time-zone-maps': 'Time & Formats',
      'phonetic-alphabet': 'Encoding',
      'diffie-hellman': 'Wi-Fi & RF',
      // Integration batch (2026-06-12): RF Bands + Wi-Fi HaLow, both Wi-Fi & RF.
      'rf-bands': 'Wi-Fi & RF',
      'wifi-halow': 'Wi-Fi & RF',
    };

    test(
      'each new tool is a live Quick Reference tile in the right subgroup',
      () {
        final ToolCategory qr = kToolCategories.firstWhere(
          (ToolCategory c) => c.id == 'quick-reference',
        );
        subgroupById.forEach((String id, String subgroup) {
          final ToolEntry t = qr.tools.firstWhere((ToolEntry e) => e.id == id);
          expect(t.isLive, isTrue, reason: '$id must be live');
          expect(t.routeName, '/tools/$id', reason: '$id route convention');
          expect(t.subgroup, subgroup, reason: '$id subgroup');
        });
      },
    );

    test('each new route resolves to a registered builder', () {
      for (final String id in subgroupById.keys) {
        expect(
          AppRouter.routes.containsKey('/tools/$id'),
          isTrue,
          reason: 'no registered route for $id',
        );
      }
    });

    test('each new tool carries a keyword set', () {
      for (final String id in subgroupById.keys) {
        expect(kToolKeywords.containsKey(id), isTrue, reason: '$id keywords');
        expect(kToolKeywords[id]!, isNotEmpty);
      }
    });
  });

  group('widget render (dark + light, no overflow)', () {
    setUp(() {
      // No reference PNG bundled by default -> the image card is omitted and the
      // page must still render fully as native text.
      ReferenceImages.debugSetBundled(const <String>{});
    });
    tearDown(ReferenceImages.debugReset);

    final List<(String, Widget)> screens = <(String, Widget)>[
      ('Keyboard Shortcuts', const KeyboardShortcutsScreen()),
      ('Time Zones', const TimeZonesScreen()),
      ('Phonetic Alphabet', const PhoneticAlphabetScreen()),
      ('Diffie-Hellman', const DiffieHellmanScreen()),
    ];

    for (final (String title, Widget screen) in screens) {
      testWidgets('$title renders its title in dark + light', (tester) async {
        for (final ThemeData theme in <ThemeData>[
          AppTheme.dark(),
          AppTheme.light(),
        ]) {
          await _withViewport(tester, const Size(375, 3200), () async {
            await tester.pumpWidget(MaterialApp(theme: theme, home: screen));
            await tester.pump();
            expect(find.text(title), findsWidgets);
            // Read-only references: no text inputs.
            expect(find.byType(TextField), findsNothing);
            // No PNG bundled -> no embedded image card.
            expect(find.byType(DarkRasterDiagramCard), findsNothing);
          });
        }
      });

      testWidgets('$title: no overflow at 320/375/768/1280 widths', (
        tester,
      ) async {
        for (final double width in <double>[320, 375, 768, 1280]) {
          await _withViewport(tester, Size(width, 2600), () async {
            await tester.pumpWidget(
              MaterialApp(theme: AppTheme.dark(), home: screen),
            );
            await tester.pump();
            expect(
              tester.takeException(),
              isNull,
              reason: '$title overflow at ${width}px',
            );
          });
        }
      });
    }

    testWidgets(
      'Phonetic Alphabet: per-letter blocks render with no overflow '
      '(dark + light) when bundled',
      (tester) async {
        // Bundle all 26 per-letter blocks AND the full plate, so every A-Z row
        // carries its leading thumbnail and the tall (72px) rows must lay out
        // without a RenderFlex overflow in either theme.
        ReferenceImages.debugSetBundled(<String>{
          ReferenceImages.pathFor('phonetic-alphabet'),
          for (final PhoneticLetter p in kPhoneticAlphabet)
            ReferenceImages.phoneticBlockPathFor(p.letter),
        });
        addTearDown(ReferenceImages.debugReset);

        for (final ThemeData theme in <ThemeData>[
          AppTheme.dark(),
          AppTheme.light(),
        ]) {
          await _withViewport(tester, const Size(375, 4200), () async {
            await tester.pumpWidget(
              MaterialApp(theme: theme, home: const PhoneticAlphabetScreen()),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);
            // One Image.asset per letter block + one for the full plate -> the
            // blocks are actually wired into the rows, not silently dropped.
            expect(
              find.byType(Image),
              findsAtLeastNWidgets(kPhoneticAlphabet.length),
            );
          });
        }
      },
    );

    testWidgets('embedded-PNG screens show one image card when bundled', (
      tester,
    ) async {
      ReferenceImages.debugSetBundled(<String>{
        ReferenceImages.pathFor('phonetic-alphabet'),
        ReferenceImages.pathFor('diffie-hellman'),
      });
      addTearDown(ReferenceImages.debugReset);

      final List<Widget> withImages = <Widget>[
        const PhoneticAlphabetScreen(),
        const DiffieHellmanScreen(),
      ];
      for (final Widget screen in withImages) {
        await _withViewport(tester, const Size(375, 3200), () async {
          await tester.pumpWidget(
            MaterialApp(theme: AppTheme.dark(), home: screen),
          );
          await tester.pump();
          expect(find.byType(DarkRasterDiagramCard), findsOneWidget);
        });
      }
    });

    testWidgets(
      'Time Zones shows BOTH the world and US map cards when bundled',
      (tester) async {
        // Time Zones now embeds two plates: the brand-rebuilt world map and the
        // new US map (the old crude "blobs" plate was retired).
        ReferenceImages.debugSetBundled(<String>{
          ReferenceImages.pathFor('time-zones-world'),
          ReferenceImages.pathFor('time-zones-us'),
        });
        addTearDown(ReferenceImages.debugReset);

        await _withViewport(tester, const Size(375, 3600), () async {
          await tester.pumpWidget(
            MaterialApp(theme: AppTheme.dark(), home: const TimeZonesScreen()),
          );
          await tester.pump();
          expect(find.byType(DarkRasterDiagramCard), findsNWidgets(2));
        });
      },
    );
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
Future<void> _withViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await body();
}
