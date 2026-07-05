// Tests for the LED Decoder screen — the INTERACTIVE cross-vendor AP status-LED
// decoder (Field & Trade Reference set, 2026-07-05).
//
// Layers:
//   1. Data fidelity (GL-005): the typed const dataset carries the voice-gated,
//      fact-confirmed facts verbatim (the cross-vendor color collisions, the
//      per-vendor forks, the confidence markers), plus the no-em-dash / "Wi-Fi"
//      glyph rules across all rendered prose.
//   2. The lab-confirm honesty guard: EXACTLY six rows carry
//      LedConfidence.labConfirm, and every one renders the honest marker
//      (kLabConfirmMarker) with NO invented color — never guessed. The visual
//      indicator honors the same rule: a lab-confirm row's indicators are all
//      LedColor.unknown (a neutral "?"), never a fabricated color.
//   3. The visual indicator (colored ball): every row carries at least one
//      structured indicator; by-design rows carry the neutral "no distinct
//      signal" glyph; the reduced-motion path swaps the flashing pulse for a
//      static halo cue so solid-vs-flashing still reads without motion.
//   4. Confidence chips are DEBUG-ONLY (Keith-directed): present under
//      kDebugMode, absent in release — while the lab-confirm disclosure TEXT
//      stays visible in both build modes.
//   5. Registration + widget render + DRILL-DOWN, no RenderFlex overflow at
//      320/375/768/1280 in BOTH dark and light themes.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/led_decoder_data.dart';
import 'package:wlan_pros_toolbox/data/reference_images.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/led_decoder_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/dark_raster_diagram_card.dart';

void main() {
  group('data fidelity (GL-005) — voice-gated copy verbatim', () {
    test('Cisco forks into two lines: Catalyst and Meraki', () {
      final LedVendor cisco =
          kLedVendors.firstWhere((LedVendor v) => v.id == 'cisco');
      expect(cisco.hasMultipleLines, isTrue);
      expect(cisco.lines.map((LedModelLine l) => l.id),
          containsAll(<String>['catalyst', 'meraki']));
    });

    test('Extreme ships TWO separate tables (IQ Engine and legacy WiNG)', () {
      final LedVendor extreme =
          kLedVendors.firstWhere((LedVendor v) => v.id == 'extreme');
      expect(extreme.lines.length, 2);
      expect(extreme.lines.map((LedModelLine l) => l.id),
          containsAll(<String>['iq-engine', 'wing']));
    });

    test('the headline color collision holds: solid green means opposites', () {
      // Meraki solid green = no clients; Ruckus radio green = clients present.
      final LedModelLine meraki = _line('cisco', 'meraki');
      final LedStateRow merakiHealthy = meraki.rows
          .firstWhere((LedStateRow r) => r.state == 'Healthy / operational');
      expect(merakiHealthy.signal.contains('Solid green = operational, no clients'),
          isTrue);
      final LedModelLine ruckus = _line('ruckus', 'indoor');
      final LedStateRow ruckusHealthy = ruckus.rows
          .firstWhere((LedStateRow r) => r.state == 'Healthy / operational');
      expect(ruckusHealthy.meaning.contains('green here means clients present'),
          isTrue);
    });

    test('MikroTik ships an honest note, never a table', () {
      final LedVendor mt =
          kLedVendors.firstWhere((LedVendor v) => v.id == 'mikrotik');
      expect(mt.honestNote, isNotNull);
      expect(mt.lines, isEmpty);
      expect(mt.honestNote!.contains('do not ship a defined enterprise'), isTrue);
    });

    test('by-design rows are marked byDesign, not a fabricated gap', () {
      // Meraki factory reset is a documented "no distinct signal".
      final LedStateRow merakiReset = _line('cisco', 'meraki')
          .rows
          .firstWhere((LedStateRow r) => r.state == 'Factory reset');
      expect(merakiReset.confidence, LedConfidence.byDesign);
      expect(merakiReset.signal.contains('No distinct signal (by design)'), isTrue);
    });

    test('consumer mesh (Orbi, Eero) is kept in its own class', () {
      expect(
        kLedVendors
            .firstWhere((LedVendor v) => v.id == 'orbi')
            .vendorClass,
        LedVendorClass.consumer,
      );
      expect(
        kLedVendors
            .firstWhere((LedVendor v) => v.id == 'eero')
            .vendorClass,
        LedVendorClass.consumer,
      );
    });

    test('no em dash in any rendered prose; "Wi-Fi" casing where used', () {
      final List<String> prose = <String>[
        kLedLead,
        kLedCollisionWarning,
        kLedStandingCaveat,
        kLedDeferNote,
        for (final LedVendor v in kLedVendors) ...<String>[
          v.name,
          if (v.honestNote != null) v.honestNote!,
          for (final LedModelLine l in v.lines) ...<String>[
            l.name,
            if (l.blurb != null) l.blurb!,
            if (l.extraNote != null) l.extraNote!,
            if (l.source != null) l.source!,
            for (final LedStateRow r in l.rows) ...<String>[
              r.state,
              r.signal,
              r.meaning,
            ],
          ],
        ],
      ];
      for (final String s in prose) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        expect(s.contains('WiFi'), isFalse, reason: 'must be "Wi-Fi" in "$s"');
      }
    });
  });

  group('visual indicator data (colored ball) — structured, not string-parsed', () {
    test('every state row carries at least one indicator', () {
      for (final LedStateRow r in _allRows()) {
        expect(r.indicators, isNotEmpty, reason: r.state);
      }
    });

    test('a documented row names, in words, every color it depicts', () {
      // The dot is never the only signal (§8.13 / WCAG 1.4.1): each real-color
      // indicator's color word appears in the row's signal text.
      const Map<LedColor, List<String>> words = <LedColor, List<String>>{
        LedColor.green: <String>['green'],
        LedColor.amber: <String>['amber', 'orange', 'yellow', 'rainbow'],
        LedColor.red: <String>['red'],
        LedColor.blue: <String>['blue'],
        LedColor.white: <String>['white', 'rainbow'],
        LedColor.purple: <String>['purple'],
        LedColor.magenta: <String>['magenta'],
      };
      for (final LedStateRow r in _allRows()) {
        final String signal = r.signal.toLowerCase();
        for (final LedIndicator i in r.indicators) {
          final List<String>? accepted = words[i.color];
          if (accepted == null) continue; // off / none / unknown carry no color
          expect(
            accepted.any(signal.contains),
            isTrue,
            reason: '"${r.state}" shows ${i.color} but its signal text names no '
                'matching color word: "${r.signal}"',
          );
        }
      }
    });

    test('by-design rows carry the neutral "no distinct signal" indicator', () {
      for (final LedStateRow r in _allRows()) {
        if (r.confidence != LedConfidence.byDesign) continue;
        expect(r.indicators, isNotEmpty, reason: r.state);
        for (final LedIndicator i in r.indicators) {
          expect(i.color, LedColor.none, reason: r.state);
        }
      }
    });

    test('no documented row invents an unknown indicator', () {
      for (final LedStateRow r in _allRows()) {
        if (r.confidence == LedConfidence.labConfirm) continue;
        for (final LedIndicator i in r.indicators) {
          expect(i.color == LedColor.unknown, isFalse, reason: r.state);
        }
      }
    });
  });

  group('lab-confirm honesty guard (GL-005)', () {
    // The six rows the content flags as genuinely undocumented. Never guess a
    // color for these; render the honest marker.
    test('there are EXACTLY six lab-confirm rows', () {
      final Iterable<LedStateRow> lab = _allRows()
          .where((LedStateRow r) => r.confidence == LedConfidence.labConfirm);
      expect(lab.length, 6);
    });

    test('every lab-confirm row shows the honest marker, not a color', () {
      for (final LedStateRow r in _allRows()) {
        if (r.confidence != LedConfidence.labConfirm) continue;
        // The signal is EXACTLY the honest marker — no invented color word.
        expect(r.signal, kLabConfirmMarker, reason: r.state);
        for (final String color in <String>[
          'green',
          'white',
          'blue',
          'amber',
          'orange',
          'red',
          'magenta',
          'purple',
          'yellow',
        ]) {
          expect(
            r.signal.toLowerCase().contains(color),
            isFalse,
            reason: 'lab-confirm row "${r.state}" must not name a color',
          );
        }
      }
    });

    test('every lab-confirm row indicator is the neutral unknown glyph, not a '
        'color', () {
      for (final LedStateRow r in _allRows()) {
        if (r.confidence != LedConfidence.labConfirm) continue;
        expect(r.indicators, isNotEmpty, reason: r.state);
        for (final LedIndicator i in r.indicators) {
          expect(i.color, LedColor.unknown,
              reason: 'lab-confirm "${r.state}" must not invent a color');
        }
      }
    });

    test('the six lab-confirm rows are the exact ones the content flags', () {
      final Set<String> labStates = <String>{
        for (final LedVendor v in kLedVendors)
          for (final LedModelLine l in v.lines)
            for (final LedStateRow r in l.rows)
              if (r.confidence == LedConfidence.labConfirm) '${v.id}/${l.id}/${r.state}',
      };
      expect(labStates, <String>{
        'aruba/campus/Firmware upgrading',
        'aruba/instant-on/Locate / blink-to-find',
        'extreme/iq-engine/Locate / blink-to-find',
        'extreme/iq-engine/Factory reset',
        'ruckus/indoor/Fault / error',
        'ruckus/indoor/Locate / blink-to-find',
      });
    });
  });

  group('registration (catalog + subgroup + router + keywords)', () {
    test('live Quick Reference tile in the proposed "Vendor & Hardware" subgroup',
        () {
      final ToolCategory qr = kToolCategories
          .firstWhere((ToolCategory c) => c.id == 'quick-reference');
      final ToolEntry t =
          qr.tools.firstWhere((ToolEntry e) => e.id == 'led-decoder');
      expect(t.isLive, isTrue);
      expect(t.routeName, '/tools/led-decoder');
      expect(t.title, 'LED Decoder');
      expect(t.subgroup, 'Vendor & Hardware');
    });

    test('"Vendor & Hardware" is a registered subgroup header', () {
      expect(
        kCategorySubgroupOrder['quick-reference']!.contains('Vendor & Hardware'),
        isTrue,
      );
    });

    test('no orphaned subgroup — grouping places the tool under its header', () {
      final ToolCategory qr = kToolCategories
          .firstWhere((ToolCategory c) => c.id == 'quick-reference');
      final List<ToolSection> sections = groupedCategoryTools(qr);
      for (final ToolSection s
          in sections.where((ToolSection s) => s.header == 'Other')) {
        expect(s.tools.any((ToolEntry e) => e.id == 'led-decoder'), isFalse);
      }
      final ToolSection vh = sections
          .firstWhere((ToolSection s) => s.header == 'Vendor & Hardware');
      expect(vh.tools.any((ToolEntry e) => e.id == 'led-decoder'), isTrue);
    });

    test('route resolves to a registered builder', () {
      expect(AppRouter.routes.containsKey('/tools/led-decoder'), isTrue);
    });

    test('carries a non-empty keyword set', () {
      expect(kToolKeywords.containsKey('led-decoder'), isTrue);
      expect(kToolKeywords['led-decoder']!.contains('meraki'), isTrue);
    });
  });

  group('widget render + drill-down (dark + light, no overflow)', () {
    testWidgets('vendor picker shows the collision warning up front, then drills',
        (tester) async {
      await _withViewport(tester, const Size(375, 4000), () async {
        await tester.pumpWidget(_app(AppTheme.dark()));
        await tester.pump();

        // Root: title + the up-front cross-vendor collision warning + vendors.
        expect(find.text('LED Decoder'), findsWidgets);
        expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
        expect(find.text('Cisco'), findsOneWidget);
        expect(find.text('MikroTik'), findsOneWidget);
        // Read-only reference: no text inputs anywhere.
        expect(find.byType(TextField), findsNothing);

        // Drill into a MULTI-LINE vendor -> the line picker, not a table yet.
        await tester.tap(find.text('Cisco'));
        await tester.pumpAndSettle();
        expect(find.text('Pick the model line'), findsOneWidget);
        expect(find.textContaining('Catalyst'), findsWidgets);

        // Drill into a line -> its state table.
        await tester.tap(find.textContaining('Meraki MR'));
        await tester.pumpAndSettle();
        expect(find.text('LED states'), findsOneWidget);
        expect(find.text('Factory reset'), findsWidgets);

        // Back to the line picker, then back to all vendors.
        await tester.tap(find.text('Cisco lines'));
        await tester.pumpAndSettle();
        expect(find.text('Pick the model line'), findsOneWidget);
        await tester.tap(find.text('All vendors'));
        await tester.pumpAndSettle();
        expect(find.text('MikroTik'), findsOneWidget);
      });
    });

    testWidgets('a single-line vendor jumps straight to its table', (tester) async {
      await _withViewport(tester, const Size(375, 4000), () async {
        await tester.pumpWidget(_app(AppTheme.dark()));
        await tester.pump();
        await tester.tap(find.text('Ubiquiti UniFi'));
        await tester.pumpAndSettle();
        // No line-picker step for a single-line vendor.
        expect(find.text('Pick the model line'), findsNothing);
        expect(find.text('LED states'), findsOneWidget);
      });
    });

    testWidgets('MikroTik shows the honest note, no table', (tester) async {
      await _withViewport(tester, const Size(375, 4000), () async {
        await tester.pumpWidget(_app(AppTheme.dark()));
        await tester.pump();
        await tester.tap(find.text('MikroTik'));
        await tester.pumpAndSettle();
        expect(find.text('No standardized status LEDs'), findsOneWidget);
        expect(find.text('LED states'), findsNothing);
      });
    });

    testWidgets('no overflow at 320/375/768/1280 in dark + light', (tester) async {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.dark(),
        AppTheme.light(),
      ]) {
        for (final double width in <double>[320, 375, 768, 1280]) {
          await _withViewport(tester, Size(width, 3600), () async {
            await tester.pumpWidget(_app(theme));
            await tester.pump();
            // Root picker.
            expect(tester.takeException(), isNull,
                reason: 'root overflow at ${width}px');
            // Drill into a multi-line vendor's longest table (Cisco Catalyst).
            await tester.tap(find.text('Cisco'));
            await tester.pumpAndSettle();
            await tester.tap(
              find.text('Catalyst / IOS-XE (controller or embedded wireless)'),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull,
                reason: 'detail overflow at ${width}px');
          });
        }
      }
    });
  });

  group('cross-vendor comparison plate (top-of-picker affordance)', () {
    // The plate id resolves under the convention-based ReferenceImages resolver
    // to assets/reference/led-master-comparison.png.
    const String platePath = 'assets/reference/led-master-comparison.png';

    testWidgets('when the PNG is bundled, the picker shows the tap-to-zoom '
        'comparison plate above the vendor list', (tester) async {
      ReferenceImages.debugSetBundled(<String>{platePath});
      addTearDown(ReferenceImages.debugReset);
      await _withViewport(tester, const Size(375, 4000), () async {
        await tester.pumpWidget(_app(AppTheme.dark()));
        await tester.pump();

        // The affordance: the section label + the DarkRasterDiagramCard + its
        // plain caption, sitting at the head of the vendor picker.
        expect(find.text('Cross-vendor comparison'), findsOneWidget);
        expect(find.byType(DarkRasterDiagramCard), findsOneWidget);
        expect(
          find.text('See the full cross-vendor comparison on one chart.'),
          findsOneWidget,
        );
        // The plate is a labeled operable zoom target for screen readers.
        expect(
          find.bySemanticsLabel('Zoom cross-vendor LED comparison chart'),
          findsOneWidget,
        );

        // The drill-down is intact — the vendor list still leads to a table.
        await tester.tap(find.text('Ubiquiti UniFi'));
        await tester.pumpAndSettle();
        expect(find.text('LED states'), findsOneWidget);
      });
    });

    testWidgets('tapping the plate opens the full-screen pinch-zoom view',
        (tester) async {
      ReferenceImages.debugSetBundled(<String>{platePath});
      addTearDown(ReferenceImages.debugReset);
      await _withViewport(tester, const Size(375, 4000), () async {
        await tester.pumpWidget(_app(AppTheme.dark()));
        await tester.pump();

        await tester.tap(find.byType(DarkRasterDiagramCard));
        await tester.pumpAndSettle();

        // The zoom lightbox: a pan/zoom viewer + a labeled close control.
        expect(find.byType(InteractiveViewer), findsOneWidget);
        expect(find.bySemanticsLabel('Close zoom'), findsOneWidget);
      });
    });

    testWidgets('when the PNG is NOT bundled, the plate is omitted and the '
        'drill-down still reads', (tester) async {
      ReferenceImages.debugSetBundled(<String>{}); // nothing bundled
      addTearDown(ReferenceImages.debugReset);
      await _withViewport(tester, const Size(375, 4000), () async {
        await tester.pumpWidget(_app(AppTheme.dark()));
        await tester.pump();

        // No plate, no broken box — just the drill-down.
        expect(find.byType(DarkRasterDiagramCard), findsNothing);
        expect(find.text('Cross-vendor comparison'), findsNothing);
        expect(find.text('Cisco'), findsOneWidget);

        await tester.tap(find.text('Cisco'));
        await tester.pumpAndSettle();
        expect(find.text('Pick the model line'), findsOneWidget);
      });
    });

    testWidgets('no overflow with the plate bundled at 320/375/768/1280 in '
        'dark + light', (tester) async {
      ReferenceImages.debugSetBundled(<String>{platePath});
      addTearDown(ReferenceImages.debugReset);
      for (final ThemeData theme in <ThemeData>[
        AppTheme.dark(),
        AppTheme.light(),
      ]) {
        for (final double width in <double>[320, 375, 768, 1280]) {
          await _withViewport(tester, Size(width, 4000), () async {
            await tester.pumpWidget(_app(theme));
            await tester.pump();
            expect(find.byType(DarkRasterDiagramCard), findsOneWidget);
            expect(tester.takeException(), isNull,
                reason: 'picker+plate overflow at ${width}px');
          });
        }
      }
    });
  });

  group('LED ball indicator (render + solid/flashing + reduced motion)', () {
    testWidgets(
        'reduced motion: each flashing indicator renders a static halo cue '
        'instead of animating', (tester) async {
      await _withViewport(tester, const Size(375, 4000), () async {
        // reduceMotion true -> no repeating pulse; flashing dots show the halo.
        await tester.pumpWidget(_app(AppTheme.dark(), reduceMotion: true));
        await tester.pump();
        await tester.tap(find.text('Ubiquiti UniFi'));
        await tester.pumpAndSettle();
        expect(find.text('LED states'), findsOneWidget);
        // UniFi has 7 flashing indicators across its rows (booting 1, firmware
        // 2, fault 2, locate 1, factory reset 1). Each renders one halo cue.
        expect(
          find.byKey(const ValueKey<String>('led-flash-halo')),
          findsNWidgets(7),
        );
      });
    });

    testWidgets(
        'motion on: the flashing pulse runs with no static halo and no '
        'exception', (tester) async {
      await _withViewport(tester, const Size(375, 4000), () async {
        // reduceMotion false -> ambient pulse loop; NEVER pumpAndSettle here (a
        // repeating animation never settles). Pump a couple of fixed frames.
        await tester.pumpWidget(_app(AppTheme.dark(), reduceMotion: false));
        await tester.pump();
        await tester.tap(find.text('Ubiquiti UniFi'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('LED states'), findsOneWidget);
        // The static halo cue is a reduced-motion-only affordance.
        expect(
          find.byKey(const ValueKey<String>('led-flash-halo')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        // Let the loop tick again without throwing.
        await tester.pump(const Duration(milliseconds: 250));
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('confidence chips are debug-only; disclosure text is always visible', () {
    testWidgets('under kDebugMode the confidence chips render', (tester) async {
      // flutter test runs in debug, so debugShowLedConfidenceChips defaults true.
      expect(debugShowLedConfidenceChips, isTrue);
      await _withViewport(tester, const Size(375, 4000), () async {
        await tester.pumpWidget(_app(AppTheme.dark()));
        await tester.pump();
        await tester.tap(find.text('Ruckus (indoor R / H series)'));
        await tester.pumpAndSettle();
        expect(find.text('Confirmed'), findsWidgets);
        expect(find.text('Lab-confirm'), findsWidgets);
        // The honest disclosure text is present too.
        expect(find.text(kLabConfirmMarker), findsWidgets);
      });
    });

    testWidgets(
        'in a release build the chips are absent but the lab-confirm disclosure '
        'stays visible', (tester) async {
      addTearDown(() => debugShowLedConfidenceChips = kDebugMode);
      debugShowLedConfidenceChips = false; // simulate a release build
      await _withViewport(tester, const Size(375, 4000), () async {
        await tester.pumpWidget(_app(AppTheme.dark()));
        await tester.pump();
        await tester.tap(find.text('Ruckus (indoor R / H series)'));
        await tester.pumpAndSettle();
        // No QA chips of any kind.
        expect(find.text('Confirmed'), findsNothing);
        expect(find.text('By design'), findsNothing);
        expect(find.text('Lab-confirm'), findsNothing);
        // But the genuine user disclosure for the undocumented states remains
        // (Ruckus indoor has two lab-confirm rows).
        expect(find.text(kLabConfirmMarker), findsWidgets);
      });
    });
  });
}

/// The reduced-motion (disableAnimations) wrapper is the DEFAULT for navigation
/// tests so a repeating blink loop can never hang pumpAndSettle. The one motion
/// test opts in with reduceMotion: false and drives fixed-duration pumps.
Widget _app(ThemeData theme, {bool reduceMotion = true}) {
  return MaterialApp(
    theme: theme,
    home: Builder(
      builder: (BuildContext context) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: const LedDecoderScreen(),
        );
      },
    ),
  );
}

List<LedStateRow> _allRows() => <LedStateRow>[
      for (final LedVendor v in kLedVendors)
        for (final LedModelLine l in v.lines) ...l.rows,
    ];

LedModelLine _line(String vendorId, String lineId) {
  final LedVendor v = kLedVendors.firstWhere((LedVendor v) => v.id == vendorId);
  return v.lines.firstWhere((LedModelLine l) => l.id == lineId);
}

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
