// Tests for the LED Decoder screen — the INTERACTIVE cross-vendor AP status-LED
// decoder (Field & Trade Reference set, 2026-07-05).
//
// Four layers:
//   1. Data fidelity (GL-005): the typed const dataset carries the voice-gated,
//      fact-confirmed facts verbatim (the cross-vendor color collisions, the
//      per-vendor forks, the confidence markers), plus the no-em-dash / "Wi-Fi"
//      glyph rules across all rendered prose.
//   2. The lab-confirm honesty guard: EXACTLY six rows carry
//      LedConfidence.labConfirm, and every one renders the honest marker
//      (kLabConfirmMarker) with NO invented color — never guessed.
//   3. Registration: a live Quick Reference tile in the proposed "Vendor &
//      Hardware" subgroup, a registered route builder, a keyword set, and a help
//      entry (count asserted in tool_help_loader_test).
//   4. Widget render + DRILL-DOWN: the vendor picker renders; tapping a vendor
//      drills into its detail (single-line vendor) or line picker (multi-line
//      vendor); the collision warning shows up front; no RenderFlex overflow at
//      320/375/768/1280 in BOTH dark and light themes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/led_decoder_data.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/led_decoder_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

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

  group('lab-confirm honesty guard (GL-005)', () {
    // The six rows the content flags as genuinely undocumented. Never guess a
    // color for these; render the honest marker.
    List<LedStateRow> allRows() => <LedStateRow>[
          for (final LedVendor v in kLedVendors)
            for (final LedModelLine l in v.lines) ...l.rows,
        ];

    test('there are EXACTLY six lab-confirm rows', () {
      final Iterable<LedStateRow> lab = allRows()
          .where((LedStateRow r) => r.confidence == LedConfidence.labConfirm);
      expect(lab.length, 6);
    });

    test('every lab-confirm row shows the honest marker, not a color', () {
      for (final LedStateRow r in allRows()) {
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
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const LedDecoderScreen()),
        );
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
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const LedDecoderScreen()),
        );
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
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const LedDecoderScreen()),
        );
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
            await tester.pumpWidget(
              MaterialApp(theme: theme, home: const LedDecoderScreen()),
            );
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
}

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
