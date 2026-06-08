// Tests for the Ohm's Law & Power Wheel reference screen — page 2 of the
// Power & Cooling category. Mirrors power_phasing_screen_test.dart.
//
// Three layers:
//   1. Data fidelity (GL-005): the typed const datasets match Pax's verified
//      research brief (Topic 1) — the four core identities, the 12-form power
//      wheel, the single-phase vs three-phase power formulas, and the
//      power-factor caveat the brief flags. Plus the no-em-dash / ASCII-glyph
//      rules and the cheat-sheet error guard (the page must NOT present
//      P = V x I as universally giving watts in AC).
//   2. Catalog + help registration: the Power & Cooling category carries a live
//      ohms-law tool whose route is registered, and the help store has a
//      matching ohms-law entry.
//   3. Widget render: the read-only screen renders title + all three tables
//      across phone/tablet/desktop widths with no RenderFlex overflow, and the
//      wheel band renders exactly the bundled count (zero when none built, one
//      when present) — proving graceful degradation.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/ohms_law_diagrams.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/ohms_law_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Core relationships — match the research brief (Topic 1)', () {
    OhmsRelation relFor(String name) => OhmsLawScreen.relations
        .firstWhere((OhmsRelation r) => r.name == name);

    test("Ohm's law is V = I x R", () {
      expect(relFor("Ohm's law").formula, 'V = I x R');
    });

    test('the four core identities are present and correct', () {
      expect(OhmsLawScreen.relations.length, 4);
      expect(relFor('Power (base)').formula, 'P = V x I');
      expect(
        relFor('Power from current and resistance').formula,
        'P = I^2 x R',
      );
      expect(
        relFor('Power from voltage and resistance').formula,
        'P = V^2 / R',
      );
    });
  });

  group('Power wheel — the 12 forms (Topic 1)', () {
    WheelRow rowFor(String quantity) =>
        OhmsLawScreen.wheel.firstWhere((WheelRow w) => w.quantity == quantity);

    test('four quantities, twelve forms total', () {
      expect(OhmsLawScreen.wheel.length, 4);
      // Three forms per quantity = twelve algebraic rearrangements.
      final int forms = OhmsLawScreen.wheel.length * 3;
      expect(forms, 12);
    });

    test('V = I x R | P / I | sqrt(P x R)', () {
      final WheelRow v = rowFor('V (volts)');
      expect(v.formA, 'I x R');
      expect(v.formB, 'P / I');
      expect(v.formC, 'sqrt(P x R)');
    });

    test('I = V / R | P / V | sqrt(P / R)', () {
      final WheelRow i = rowFor('I (amps)');
      expect(i.formA, 'V / R');
      expect(i.formB, 'P / V');
      expect(i.formC, 'sqrt(P / R)');
    });

    test('R = V / I | V^2 / P | P / I^2', () {
      final WheelRow r = rowFor('R (ohms)');
      expect(r.formA, 'V / I');
      expect(r.formB, 'V^2 / P');
      expect(r.formC, 'P / I^2');
    });

    test('P = V x I | I^2 x R | V^2 / R', () {
      final WheelRow p = rowFor('P (watts)');
      expect(p.formA, 'V x I');
      expect(p.formB, 'I^2 x R');
      expect(p.formC, 'V^2 / R');
    });
  });

  group('Single-phase vs three-phase power + power factor (Topic 1)', () {
    PowerFormula pfFor(String system) => OhmsLawScreen.powerFormulas
        .firstWhere((PowerFormula p) => p.system == system);

    test('single-phase: S = V x I, P = V x I x cos(phi)', () {
      final PowerFormula p = pfFor('Single-phase');
      expect(p.apparent, 'S = V x I');
      expect(p.real, 'P = V x I x cos(phi)');
    });

    test('three-phase: S and P carry the sqrt(3) x V_LL x I_L term', () {
      final PowerFormula p = pfFor('Three-phase (balanced)');
      expect(p.apparent, 'S = sqrt(3) x V_LL x I_L');
      expect(p.real, 'P = sqrt(3) x V_LL x I_L x cos(phi)');
    });

    test('power-factor note states PF = 1 only for resistive/DC (the caveat)',
        () {
      final String note = OhmsLawScreen.powerFactorNote;
      expect(note.contains('resistive'), isTrue);
      expect(note.contains('DC'), isTrue);
      expect(note.contains('apparent power'), isTrue);
      expect(note.contains('VA'), isTrue);
      // Cheat-sheet error guard (research brief): the page must NOT present
      // P = V x I as universally giving watts on an AC reactive load.
      expect(note.contains('Do not read P = V x I as giving watts'), isTrue);
    });
  });

  group('GL-004 voice — ASCII glyphs only, no em dash, no router', () {
    test('no em dash anywhere in the datasets or notes', () {
      final List<String> all = <String>[
        for (final OhmsRelation r in OhmsLawScreen.relations) ...<String>[
          r.name,
          r.formula,
          r.solvesFor,
        ],
        for (final WheelRow w in OhmsLawScreen.wheel) ...<String>[
          w.quantity,
          w.formA,
          w.formB,
          w.formC,
        ],
        for (final PowerFormula p in OhmsLawScreen.powerFormulas) ...<String>[
          p.system,
          p.apparent,
          p.real,
        ],
        OhmsLawScreen.powerFactorNote,
        OhmsLawScreen.relationsFootnote,
        OhmsLawScreen.wheelFootnote,
      ];
      for (final String s in all) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        // No superscript or root glyph — ASCII caret + sqrt() only.
        expect(s.contains('²'), isFalse, reason: 'superscript in "$s"');
        expect(s.contains('√'), isFalse, reason: 'root glyph in "$s"');
        expect(s.toLowerCase().contains('router'), isFalse);
      }
    });
  });

  group('catalog + router + help registration', () {
    test('Power & Cooling category exists with the live ohms-law tool', () {
      final ToolCategory cat = kToolCategories
          .firstWhere((ToolCategory c) => c.id == 'power-cooling');
      expect(cat.title, 'Power & Cooling');
      final ToolEntry tool =
          cat.tools.firstWhere((ToolEntry t) => t.id == 'ohms-law');
      expect(tool.isLive, isTrue);
      expect(tool.routeName, '/tools/ohms-law');
    });

    test('ohms-law route resolves to a registered builder', () {
      expect(AppRouter.routes.containsKey('/tools/ohms-law'), isTrue);
    });
  });

  group('OhmsLawScreen widget', () {
    setUp(() {
      // No wheel SVG bundled by default → band renders nothing, and the page
      // must still ship fully working.
      OhmsLawDiagrams.debugSetBundled(const <String>{});
    });
    tearDown(() {
      OhmsLawDiagrams.debugReset();
    });

    testWidgets('renders title and all three tables', (tester) async {
      await _withViewport(tester, const Size(375, 1600), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const OhmsLawScreen(),
          ),
        );

        expect(find.text("Ohm's Law & Power Wheel"), findsWidgets);
        expect(find.text('Core relationships'), findsOneWidget);
        expect(find.text('Power wheel (12 forms)'), findsOneWidget);
        expect(find.text('Single-phase vs three-phase power'), findsOneWidget);
        // Read-only reference: no inputs.
        expect(find.byType(TextField), findsNothing);
        // No bundled wheel → no SvgPicture (graceful degradation).
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
              home: const OhmsLawScreen(),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });

    testWidgets('renders exactly the bundled wheel count (dark)',
        (tester) async {
      // Wheel bundled → exactly one SvgPicture band (dark path uses
      // SvgPicture.asset). Proves the wheel-band wiring.
      OhmsLawDiagrams.debugSetBundled(<String>{
        OhmsLawDiagrams.path(OhmsLawDiagrams.wheel),
      });
      addTearDown(OhmsLawDiagrams.debugReset);

      await _withViewport(tester, const Size(375, 1800), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const OhmsLawScreen(),
          ),
        );
        await tester.pump();
        expect(find.byType(SvgPicture), findsNWidgets(1));
      });
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
