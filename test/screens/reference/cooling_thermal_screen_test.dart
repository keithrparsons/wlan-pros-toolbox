// Tests for the Cooling & Thermal reference screen — page 3 of the
// Power & Cooling category. Mirrors power_phasing_screen_test.dart.
//
// Three layers:
//   1. Data fidelity (GL-005): the typed const datasets match the two verified
//      anchor conversions (1 W = 3.412 BTU/hr; 1 ton = 12,000 BTU/hr ~= 3,517
//      W) and the IT-load-to-heat-to-cooling relationship from Pax's research
//      brief. Every conversion row is checked to derive correctly from the
//      anchors, so the table cannot silently drift. Plus the no-em-dash /
//      ASCII-glyph rules.
//   2. Catalog + help registration: the Power & Cooling category carries a live
//      cooling-thermal tool whose route is registered, and the help store has a
//      matching cooling-thermal entry.
//   3. Widget render: the read-only TABLES-ONLY screen renders title + both
//      tables across phone/tablet/desktop widths with no RenderFlex overflow,
//      and carries NO diagram (no SvgPicture) — this page has no graphic.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/cooling_thermal_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Conversions derive from the two anchors (build brief)', () {
    /// Parse the leading number from a display string like `3,412 BTU/hr` or
    /// `0.00028 tons` into a double, dropping thousands commas and the unit.
    double leadingNumber(String s) {
      final RegExpMatch? m =
          RegExp(r'^[\d.,]+').firstMatch(s.replaceAll(',', ''));
      return double.parse(m!.group(0)!);
    }

    ThermalConversion convFor(String watts) => CoolingThermalScreen.conversions
        .firstWhere((ThermalConversion c) => c.watts == watts);

    test('anchor note states 1 W = 3.412 BTU/hr and 1 ton = 12,000 BTU/hr', () {
      final String note = CoolingThermalScreen.anchorNote;
      expect(note.contains('1 W = 3.412 BTU/hr'), isTrue);
      expect(note.contains('12,000 BTU/hr'), isTrue);
      expect(note.contains('3,517 W'), isTrue);
    });

    test('every row: BTU/hr ~= watts x 3.412', () {
      for (final ThermalConversion c in CoolingThermalScreen.conversions) {
        final double w = leadingNumber(c.watts);
        final double btu = leadingNumber(c.btuPerHour);
        // Display values are rounded for the table, so allow rounding slack.
        expect((btu - w * 3.412).abs() <= 1.0, isTrue,
            reason: '${c.watts}: ${c.btuPerHour} != ${w * 3.412} BTU/hr');
      }
    });

    test('every row: tons ~= BTU/hr / 12,000', () {
      for (final ThermalConversion c in CoolingThermalScreen.conversions) {
        final double btu = leadingNumber(c.btuPerHour);
        final double tons = leadingNumber(c.tons);
        expect((tons - btu / 12000.0).abs() <= 0.01, isTrue,
            reason: '${c.btuPerHour}: ${c.tons} != ${btu / 12000.0} tons');
      }
    });

    test('the 1-ton anchor row reads 3,517 W = 12,000 BTU/hr = 1 ton', () {
      final ThermalConversion c = convFor('3,517 W');
      expect(c.btuPerHour, '12,000 BTU/hr');
      expect(c.tons, '1 ton');
    });

    test('the 1 kW row reads 3,412 BTU/hr, 0.284 tons', () {
      final ThermalConversion c = convFor('1,000 W');
      expect(c.btuPerHour, '3,412 BTU/hr');
      expect(c.tons, '0.284 tons');
    });
  });

  group('IT load to heat to cooling relationship (research brief)', () {
    test('three steps: load->heat, heat->cooling, size the plant', () {
      expect(CoolingThermalScreen.heatChain.length, 3);
      final HeatRelation step1 = CoolingThermalScreen.heatChain.first;
      expect(step1.relationship.contains('Heat (W) = IT load (W)'), isTrue);
    });

    test('airflow note carries the standard sensible-heat formula', () {
      final String note = CoolingThermalScreen.airflowNote;
      expect(note.contains('1.08 x CFM x delta-T'), isTrue);
      expect(note.contains('CFM = BTU/hr / (1.08 x delta-T)'), isTrue);
      // 1 kW across a 20 deg F rise ~= 158 CFM (3412 / (1.08 x 20) = 158).
      expect(note.contains('158 CFM'), isTrue);
    });
  });

  group('GL-004 voice — ASCII glyphs only, no em dash, no router', () {
    test('no em dash, degree, or delta glyph anywhere', () {
      final List<String> all = <String>[
        CoolingThermalScreen.anchorNote,
        CoolingThermalScreen.airflowNote,
        CoolingThermalScreen.footnote,
        for (final ThermalConversion c
            in CoolingThermalScreen.conversions) ...<String>[
          c.watts,
          c.btuPerHour,
          c.tons,
          c.note,
        ],
        for (final HeatRelation h in CoolingThermalScreen.heatChain) ...<String>[
          h.step,
          h.relationship,
          h.detail,
        ],
      ];
      for (final String s in all) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        expect(s.contains('°'), isFalse, reason: 'degree glyph in "$s"');
        expect(s.contains('Δ'), isFalse, reason: 'delta glyph in "$s"');
        expect(s.toLowerCase().contains('router'), isFalse);
      }
    });
  });

  group('catalog + router + help registration', () {
    test(
        'Quick Reference / Power & Cooling subgroup carries the live '
        'cooling-thermal tool', () {
      final ToolCategory cat = kToolCategories
          .firstWhere((ToolCategory c) => c.id == 'quick-reference');
      final ToolEntry tool =
          cat.tools.firstWhere((ToolEntry t) => t.id == 'cooling-thermal');
      expect(tool.isLive, isTrue);
      expect(tool.routeName, '/tools/cooling-thermal');
      expect(tool.subgroup, 'Power & Cooling');
    });

    test('cooling-thermal route resolves to a registered builder', () {
      expect(AppRouter.routes.containsKey('/tools/cooling-thermal'), isTrue);
    });
  });

  group('CoolingThermalScreen widget', () {
    testWidgets('renders title and both tables, no diagram', (tester) async {
      await _withViewport(tester, const Size(375, 1600), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const CoolingThermalScreen(),
          ),
        );

        expect(find.text('Cooling & Thermal'), findsWidgets);
        expect(find.text('Watts / BTU per hour / tons'), findsOneWidget);
        expect(find.text('IT load to heat to cooling'), findsOneWidget);
        // Read-only reference: no inputs.
        expect(find.byType(TextField), findsNothing);
        // Tables-only page: this screen carries no graphic at all.
        expect(find.byType(SvgPicture), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths',
        (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 1800), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const CoolingThermalScreen(),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors power_phasing_screen_test _withViewport.
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
