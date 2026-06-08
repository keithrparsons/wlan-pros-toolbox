// Tests for the International Power Plugs reference screen — page 4 of 6 in the
// Power & Cooling category.
//
// Three layers, mirroring power_phasing_screen_test.dart:
//   1. Data fidelity (GL-005): the typed const datasets match Pax's verified
//      research brief (Topic 5) — the IEC type-to-standard mapping, the CEE 7
//      family breakout, and the load-bearing Type I safety caveat (Argentina
//      reverses line and neutral), plus the no-em-dash / GL-004 voice rules.
//   2. Catalog + help registration: the catalog carries the international-plugs
//      tool in the Power & Cooling category with its route registered, and the
//      help store has a matching international-plugs entry. (Larry wires these
//      registrations in at integration; the test guards them.)
//   3. Widget render: the read-only screen renders title, both tables, and the
//      prominent Type I warning callout across phone/tablet/desktop widths with
//      no RenderFlex overflow, and the concept-graphic band renders exactly the
//      bundled count (zero when none built, one when present) — proving graceful
//      degradation.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/power_phasing_diagrams.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/international_plugs_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('IEC plug types — match the research brief (Topic 5)', () {
    PlugType byStandard(String standard) => InternationalPlugsScreen.plugTypes
        .firstWhere((PlugType p) => p.standard == standard);

    test('Europlug (Type C) is 2.5A and unearthed, not a 16A connector', () {
      final PlugType c = byStandard('CEE 7/16 (Europlug)');
      expect(c.type, 'C');
      expect(c.current, '2.5A');
      expect(c.voltageClass, '230V');
    });

    test('Schuko (Type F) and French (Type E) are the 16A earthed European plugs',
        () {
      final PlugType f = byStandard('CEE 7/4 (Schuko)');
      expect(f.type, 'F');
      expect(f.current, '16A');
      final PlugType e = byStandard('CEE 7/5 (French)');
      expect(e.type, 'E');
      expect(e.current, '16A');
    });

    test('UK (Type G, BS 1363) is 13A and fused', () {
      final PlugType g = byStandard('BS 1363');
      expect(g.type, 'G');
      expect(g.current, '13A (fused)');
    });

    test('BS 546 appears twice: Type D 5A (India) and Type M 15A (South Africa)',
        () {
      final PlugType d = byStandard('BS 546 (5A)');
      expect(d.type, 'D');
      expect(d.current, '5A');
      final PlugType m = byStandard('BS 546 (15A)');
      expect(m.type, 'M');
      expect(m.current, '15A');
      expect(d.type == m.type, isFalse, reason: 'D and M must not collapse');
    });

    test('the three Type I cluster members are present and labeled by standard',
        () {
      final Iterable<PlugType> typeI = InternationalPlugsScreen.plugTypes
          .where((PlugType p) => p.type == 'I');
      expect(typeI.length, 3);
      expect(
        typeI.any((PlugType p) => p.standard == 'AS/NZS 3112'),
        isTrue,
      );
      expect(
        typeI.any((PlugType p) => p.standard.contains('CPCS-CCC')),
        isTrue,
      );
      expect(
        typeI.any((PlugType p) => p.standard.contains('IRAM 2073')),
        isTrue,
      );
    });

    test('Switzerland Type J (SEV 1011) and Italy Type L (CEI 23-50) present',
        () {
      final PlugType j = byStandard('SEV 1011 / SN 441011');
      expect(j.type, 'J');
      final PlugType l = byStandard('CEI 23-50');
      expect(l.type, 'L');
    });

    test('A and B are the 120V North American types; the rest are ~230V', () {
      final PlugType a = byStandard('NEMA 1-15 (ungrounded)');
      final PlugType b = byStandard('NEMA 5-15 (grounded)');
      expect(a.voltageClass, '120V');
      expect(b.voltageClass, '120V');
      for (final PlugType p in InternationalPlugsScreen.plugTypes) {
        if (p.type != 'A' && p.type != 'B') {
          expect(p.voltageClass, '230V', reason: '${p.standard} should be 230V');
        }
      }
    });

    test('no em dash anywhere in the typed data', () {
      for (final PlugType p in InternationalPlugsScreen.plugTypes) {
        for (final String s in <String>[p.standard, p.countries, p.current]) {
          expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        }
      }
      for (final Cee7Member m in InternationalPlugsScreen.cee7Family) {
        expect(m.note.contains('—'), isFalse, reason: 'em dash in "${m.note}"');
      }
    });
  });

  group('CEE 7 European family — four plugs, three letters plus the hybrid', () {
    test('CEE 7/7 is the E/F hybrid that fits both French and Schuko sockets',
        () {
      final Cee7Member hybrid = InternationalPlugsScreen.cee7Family
          .firstWhere((Cee7Member m) => m.designation == 'CEE 7/7');
      expect(hybrid.type, 'E/F');
      expect(hybrid.note.toLowerCase().contains('hybrid'), isTrue);
    });

    test('four members; Europlug is the 2.5A entry', () {
      expect(InternationalPlugsScreen.cee7Family.length, 4);
      final Cee7Member europlug = InternationalPlugsScreen.cee7Family
          .firstWhere((Cee7Member m) => m.designation == 'CEE 7/16');
      expect(europlug.type, 'C');
      expect(europlug.current, '2.5A');
    });
  });

  group('Type I safety warning — the load-bearing caveat', () {
    test('title names the not-interchangeable fact', () {
      expect(
        InternationalPlugsScreen.typeIWarningTitle
            .toLowerCase()
            .contains('not safely interchangeable'),
        isTrue,
      );
    });

    test('body states the Argentina line/neutral reversal explicitly', () {
      final String body = InternationalPlugsScreen.typeIWarningBody;
      expect(body.contains('Argentina'), isTrue);
      expect(body.toLowerCase().contains('reversed'), isTrue);
      expect(body.contains('AS/NZS 3112'), isTrue);
      expect(body.contains('IRAM 2073'), isTrue);
      // GL-004: ASCII only, no em dash, "Access Point" never "router".
      expect(body.contains('—'), isFalse);
      expect(body.toLowerCase().contains('router'), isFalse);
    });
  });

  group('catalog + router + help registration', () {
    test('Power & Cooling category carries the live international-plugs tool',
        () {
      final ToolCategory cat = kToolCategories
          .firstWhere((ToolCategory c) => c.id == 'power-cooling');
      expect(cat.title, 'Power & Cooling');
      final ToolEntry tool =
          cat.tools.firstWhere((ToolEntry t) => t.id == 'international-plugs');
      expect(tool.isLive, isTrue);
      expect(tool.routeName, '/tools/international-plugs');
    });

    test('international-plugs route resolves to a registered builder', () {
      expect(
        AppRouter.routes.containsKey('/tools/international-plugs'),
        isTrue,
      );
    });
  });

  group('InternationalPlugsScreen widget', () {
    setUp(() {
      // No concept-graphic SVG bundled by default → band renders nothing, and
      // the page must still ship fully working.
      PowerPhasingDiagrams.debugSetBundled(const <String>{});
    });
    tearDown(() {
      PowerPhasingDiagrams.debugReset();
    });

    testWidgets('renders title, both tables, and the Type I warning',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(375, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const InternationalPlugsScreen(),
          ),
        );

        expect(find.text('International Power Plugs'), findsWidgets);
        expect(find.text('IEC World Plugs letter system'), findsOneWidget);
        expect(find.text('CEE 7 European family'), findsOneWidget);
        expect(
          find.text(InternationalPlugsScreen.typeIWarningTitle),
          findsOneWidget,
        );
        // Read-only reference: no inputs.
        expect(find.byType(TextField), findsNothing);
        // No bundled graphic → no SvgPicture (graceful degradation).
        expect(find.byType(SvgPicture), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths',
        (WidgetTester tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 2600), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const InternationalPlugsScreen(),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });

    testWidgets('renders exactly the bundled graphic count (dark)',
        (WidgetTester tester) async {
      // The one concept graphic bundled → exactly one SvgPicture band (dark path
      // uses SvgPicture.asset). Proves the graphic-slot wiring.
      PowerPhasingDiagrams.debugSetBundled(<String>{
        PowerPhasingDiagrams.path(InternationalPlugsScreen.graphicAsset),
      });
      addTearDown(() => PowerPhasingDiagrams.debugReset());

      await _withViewport(tester, const Size(375, 2600), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const InternationalPlugsScreen(),
          ),
        );
        await tester.pump();
        expect(find.byType(SvgPicture), findsOneWidget);
      });
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors power_phasing_screen_test._withViewport so the read-only reference
/// renders at phone width without a RenderFlex overflow.
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
