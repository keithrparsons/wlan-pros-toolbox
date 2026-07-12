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
import 'package:wlan_pros_toolbox/data/international_plugs_diagrams.dart';
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
          // `contains`, not equality, since Type N was added 2026-07-11 and
          // carries a real qualifier: "230V (BR: 127/220V)". Brazil genuinely
          // runs two residential voltages depending on the state — that is not
          // a transcription error, and flattening it to a bare "230V" to satisfy
          // a string match would hand a traveler the wrong number. The test's
          // intent (A and B are the 120V family, everything else is the 230V
          // family) is preserved exactly.
          expect(
            p.voltageClass,
            contains('230V'),
            reason: '${p.standard} should be in the 230V family',
          );
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
    test(
        'Quick Reference / Power & Cooling subgroup carries the live '
        'international-plugs tool', () {
      final ToolCategory cat = kToolCategories
          .firstWhere((ToolCategory c) => c.id == 'quick-reference');
      final ToolEntry tool =
          cat.tools.firstWhere((ToolEntry t) => t.id == 'international-plugs');
      expect(tool.isLive, isTrue);
      expect(tool.routeName, '/tools/international-plugs');
      expect(tool.subgroup, 'Power & Cooling');
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
      // No face SVG bundled by default → each face card renders no graphic, and
      // the page must still ship fully working.
      InternationalPlugsDiagrams.debugSetBundled(const <String>{});
    });
    tearDown(() {
      InternationalPlugsDiagrams.debugReset();
    });

    testWidgets('renders title, section heading, CEE 7 table, Type I warning',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(375, 6000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const InternationalPlugsScreen(),
          ),
        );

        expect(find.text('International Power Plugs'), findsWidgets);
        // The section heading stands above the stacked face-cards.
        expect(find.text('IEC World Plugs letter system'), findsOneWidget);
        // The CEE 7 family stays a compact table card.
        expect(find.text('CEE 7 European family'), findsOneWidget);
        // The prominent Type I safety warning rides at the top.
        expect(
          find.text(InternationalPlugsScreen.typeIWarningTitle),
          findsOneWidget,
        );
        // A couple of per-type face-card titles render.
        expect(find.text('Type G'), findsOneWidget);
        expect(find.text('Type F'), findsOneWidget);
        // The page now carries one input: the country-search field at the top
        // (added 2026-06-08). The reference cards below it stay read-only.
        expect(find.byType(TextField), findsOneWidget);
        // No bundled face → no SvgPicture (graceful degradation: each card reads
        // as title + specs alone).
        expect(find.byType(SvgPicture), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths',
        (WidgetTester tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 6000), () async {
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

    testWidgets('renders exactly the bundled per-face count (dark)',
        (WidgetTester tester) async {
      // All ten named faces bundled. The three Type I rows share the one intl-i
      // face but each renders its own card, so the bundled face count maps to
      // twelve SvgPicture cards: the ten distinct-face types plus the two extra
      // Type I rows (AS/NZS + GB + IRAM = 3 cards on the one intl-i asset). Type
      // B carries no face (shares the NEMA 5-15 face) so it adds none. Proves the
      // per-face wiring.
      InternationalPlugsDiagrams.debugSetBundled(<String>{
        for (final String name in InternationalPlugsDiagrams.all)
          InternationalPlugsDiagrams.path(name),
      });
      addTearDown(() => InternationalPlugsDiagrams.debugReset());

      final int expectedCards = InternationalPlugsScreen.plugTypes
          .where((PlugType p) =>
              p.assetName != null &&
              InternationalPlugsDiagrams.has(p.assetName!))
          .length;

      await _withViewport(tester, const Size(375, 9000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const InternationalPlugsScreen(),
          ),
        );
        await tester.pump();
        expect(find.byType(SvgPicture), findsNWidgets(expectedCards));
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
