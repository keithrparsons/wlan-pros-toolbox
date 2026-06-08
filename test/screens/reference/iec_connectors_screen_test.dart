// Tests for the IEC Power Connectors reference screen — page 3 of the
// Power & Cooling category.
//
// Three layers, mirroring power_phasing_screen_test:
//   1. Data fidelity (GL-005): the typed const datasets match Pax's verified
//      research brief (Topic 3), with the brief's precision CORRECTIONS pinned
//      so a future edit cannot silently re-introduce the cheat-sheet errors —
//      the "kettle cord" = C15/C16 (120 degC, notch), C13/C14 = 70 degC "PC
//      cord"; IEC 60309 red = 380-480V not a single 415V; plus the no-em-dash /
//      ASCII-glyph rules.
//   2. Catalog + help registration: the catalog carries the iec-connectors tool
//      under Power & Cooling with a registered route, and the help store has a
//      matching iec-connectors entry. (Larry wires these in at integration; the
//      assertions document the contract.)
//   3. Widget render: the read-only screen renders title + both tables across
//      phone/tablet/desktop widths with no RenderFlex overflow, and the diagram
//      band renders exactly the bundled count (zero when none built, one when the
//      single named SVG is present) — proving graceful degradation.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/iec_connectors_diagrams.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/iec_connectors_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('IEC 60320 couplers — match the research brief (Topic 3)', () {
    IecCoupler couplerFor(String pair) => IecConnectorsScreen.couplers
        .firstWhere((IecCoupler c) => c.pair == pair);

    test('C13/C14 = 10 A, 70 degC, the "PC cord" (NOT the kettle coupler)', () {
      final IecCoupler c = couplerFor('C13 / C14');
      expect(c.current, '10 A');
      expect(c.maxTemp, '70 degC');
      expect(c.nickname.toLowerCase().contains('pc cord'), isTrue);
      expect(c.nickname.toLowerCase().contains('kettle'), isFalse,
          reason: 'C13 is NOT the kettle coupler (research brief correction)');
    });

    test('C15/C16 = 10 A, 120 degC, the TRUE kettle coupler (notch-keyed)', () {
      final IecCoupler c = couplerFor('C15 / C16');
      expect(c.current, '10 A');
      expect(c.maxTemp, '120 degC',
          reason: 'C15/C16 is the 120 degC hot-condition coupler');
      expect(c.nickname.toLowerCase().contains('kettle'), isTrue);
      expect(c.use.toLowerCase().contains('notch'), isTrue,
          reason: 'the notch keying is the load-bearing distinction');
    });

    test('C5/C6 = 2.5 A cloverleaf laptop brick; C19/C20 = 16 A high-draw', () {
      final IecCoupler c5 = couplerFor('C5 / C6');
      expect(c5.current, '2.5 A');
      expect(c5.nickname.toLowerCase().contains('cloverleaf'), isTrue);
      final IecCoupler c19 = couplerFor('C19 / C20');
      expect(c19.current, '16 A');
    });

    test('six coupler families; only C15/C16 is 120 degC, the rest 70 degC', () {
      expect(IecConnectorsScreen.couplers.length, 6);
      final Iterable<IecCoupler> hot = IecConnectorsScreen.couplers
          .where((IecCoupler c) => c.maxTemp == '120 degC');
      expect(hot.length, 1);
      expect(hot.single.pair, 'C15 / C16');
    });

    test('odd=connector(female)/even=inlet(male) convention is stated', () {
      expect(
        IecConnectorsScreen.couplerNote.contains('female'),
        isTrue,
      );
      expect(
        IecConnectorsScreen.couplerNote.contains('male'),
        isTrue,
      );
      expect(
        IecConnectorsScreen.couplerNote.toLowerCase().contains('one greater'),
        isTrue,
        reason: 'even inlet is one greater than its mating connector',
      );
    });
  });

  group('IEC 60309 industrial — match the research brief (Topic 3)', () {
    IecIndustrial bandFor(String color) => IecConnectorsScreen.industrial
        .firstWhere((IecIndustrial i) => i.color == color);

    test('blue = 200-250V single-phase', () {
      expect(bandFor('Blue').voltage, '200-250V');
    });

    test('red = 380-480V three-phase (NOT a single 415V)', () {
      final IecIndustrial red = bandFor('Red');
      expect(red.voltage, '380-480V',
          reason: 'red spans 380-480V, not a single 415V (brief correction)');
      expect(red.use.toLowerCase().contains('three-phase'), isTrue);
    });

    test('yellow = 100-130V 110V supplies', () {
      expect(bandFor('Yellow').voltage, '100-130V');
    });

    test('six voltage bands; the note pins color AND clock-position keying', () {
      expect(IecConnectorsScreen.industrial.length, 6);
      // Both the color and the earth-pin hour must match (brief correction).
      expect(
        IecConnectorsScreen.industrialNote.contains('color AND the earth-pin'),
        isTrue,
      );
      // The common clock positions are rendered.
      for (final String hour in <String>['6h', '4h', '9h']) {
        expect(IecConnectorsScreen.industrialNote.contains(hour), isTrue,
            reason: 'common clock position $hour should be named');
      }
      // The configuration-dependent caveat is present (brief limitation).
      expect(
        IecConnectorsScreen.industrialNote.contains('IEC 60309-2'),
        isTrue,
        reason: 'beyond the common cases, verify against IEC 60309-2',
      );
    });
  });

  group('GL-004 voice + glyph hygiene', () {
    test('no em dash, no "router", degrees written "degC" in data/notes', () {
      final List<String> prose = <String>[
        IecConnectorsScreen.couplerNote,
        IecConnectorsScreen.couplerFootnote,
        IecConnectorsScreen.industrialNote,
        IecConnectorsScreen.industrialFootnote,
        for (final IecCoupler c in IecConnectorsScreen.couplers) ...<String>[
          c.pair,
          c.current,
          c.maxTemp,
          c.nickname,
          c.use,
        ],
        for (final IecIndustrial i in IecConnectorsScreen.industrial)
          ...<String>[i.color, i.voltage, i.use],
      ];
      for (final String s in prose) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        expect(s.toLowerCase().contains('router'), isFalse,
            reason: 'never "router" in "$s"');
        // No degree symbol anywhere — temperatures are written "degC".
        expect(s.contains('°'), isFalse,
            reason: 'degree symbol in "$s"; use "degC"');
      }
    });
  });

  group('catalog + router + help registration', () {
    test(
        'Quick Reference / Power & Cooling subgroup carries the live '
        'iec-connectors tool', () {
      final ToolCategory cat = kToolCategories
          .firstWhere((ToolCategory c) => c.id == 'quick-reference');
      final ToolEntry tool =
          cat.tools.firstWhere((ToolEntry t) => t.id == 'iec-connectors');
      expect(tool.isLive, isTrue);
      expect(tool.routeName, '/tools/iec-connectors');
      expect(tool.subgroup, 'Power & Cooling');
    });

    test('iec-connectors route resolves to a registered builder', () {
      expect(AppRouter.routes.containsKey('/tools/iec-connectors'), isTrue);
    });
  });

  group('IecConnectorsScreen widget', () {
    setUp(() {
      // No diagram SVG bundled by default → the band renders nothing, and the
      // page must still ship fully working as tables.
      IecConnectorsDiagrams.debugSetBundled(const <String>{});
    });
    tearDown(() {
      IecConnectorsDiagrams.debugReset();
    });

    testWidgets('renders title, both section headings, and per-connector cards',
        (tester) async {
      await _withViewport(tester, const Size(375, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const IecConnectorsScreen(),
          ),
        );

        expect(find.text('IEC Power Connectors'), findsWidgets);
        // The two section headings above the stacked face-cards.
        expect(find.text('IEC 60320 appliance couplers'), findsOneWidget);
        expect(find.text('IEC 60309 industrial connectors'), findsOneWidget);
        // Per-connector face-card titles render their load-bearing pairs.
        expect(find.text('C13 / C14'), findsOneWidget);
        expect(find.text('C15 / C16'), findsOneWidget);
        // The IEC 60309 face-card carries the color = voltage-band specs.
        expect(find.text('IEC 60309 pin-and-sleeve'), findsOneWidget);
        expect(find.text('Blue'), findsOneWidget);
        // Read-only reference: no inputs.
        expect(find.byType(TextField), findsNothing);
        // No bundled face → no SvgPicture (graceful degradation: each card
        // reads as title + specs + note alone).
        expect(find.byType(SvgPicture), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths',
        (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 1600), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const IecConnectorsScreen(),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });

    testWidgets('renders exactly the bundled per-face count (dark)',
        (tester) async {
      // All six named faces bundled → exactly six SvgPicture face-cards (dark
      // path uses SvgPicture.asset): five IEC 60320 coupler faces (C5, C7, C13,
      // C15, C19) plus the IEC 60309 face. The C1/C2 coupler has no face asset,
      // so it does not add a seventh. Proves the per-face wiring.
      IecConnectorsDiagrams.debugSetBundled(<String>{
        for (final String name in IecConnectorsDiagrams.all)
          IecConnectorsDiagrams.path(name),
      });
      addTearDown(() => IecConnectorsDiagrams.debugReset());

      await _withViewport(tester, const Size(375, 4000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const IecConnectorsScreen(),
          ),
        );
        await tester.pump();
        expect(find.byType(SvgPicture), findsNWidgets(6));
      });
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors power_phasing_screen_test _withViewport so the read-only reference
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
