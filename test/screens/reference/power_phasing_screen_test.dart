// Tests for the Power Phasing reference screen — pilot page for the new
// Power & Cooling category.
//
// Three layers:
//   1. Data fidelity (GL-005): the typed const datasets match Pax's verified
//      research brief (Topic 2) — the load-bearing 208-vs-240 facts a future
//      edit must not silently drift, plus the no-em-dash / ASCII-glyph rules.
//   2. Catalog + help registration: the catalog carries the new Power & Cooling
//      category with a live power-phasing tool whose route is registered, and
//      the help store has a matching power-phasing entry.
//   3. Widget render: the read-only screen renders title + both tables across
//      phone/tablet/desktop widths with no RenderFlex overflow, and the waveform
//      bands render exactly the bundled count (zero when none built, three when
//      all three are present) — proving graceful degradation.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/power_phasing_diagrams.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/power_phasing_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Power topologies — match the research brief (Topic 2)', () {
    PowerTopology topoFor(String name) => PowerPhasingScreen.topologies
        .firstWhere((PowerTopology t) => t.name == name);

    test('single-phase 120V = one hot, 120V L-N, no hot-to-hot pair', () {
      final PowerTopology t = topoFor('Single-phase 120V');
      expect(t.hots, 'One');
      expect(t.lineToNeutral, '120V');
      expect(t.lineToLine, '—');
      expect(t.phaseAngle, '—');
      expect(t.assetName, PowerPhasingDiagrams.single120v);
    });

    test('split-phase 120/240V = two hots, 180 deg, 240V hot-to-hot', () {
      final PowerTopology t = topoFor('Split-phase 120/240V');
      expect(t.hots, 'Two');
      expect(t.lineToNeutral, '120V');
      expect(t.lineToLine, '240V');
      expect(t.phaseAngle, '180 deg');
      expect(t.assetName, PowerPhasingDiagrams.split240v);
      // Single-phase, not two-phase; neutral, not ground (research brief).
      expect(t.notes.contains('single-phase'), isTrue);
      expect(t.notes.contains('neutral'), isTrue);
    });

    test('three-phase wye 208V = three hots, 120 deg, 208V line-to-line', () {
      final PowerTopology t = topoFor('Three-phase wye 208V');
      expect(t.hots, 'Three');
      expect(t.lineToNeutral, '120V');
      expect(t.lineToLine, '208V');
      expect(t.phaseAngle, '120 deg');
      expect(t.assetName, PowerPhasingDiagrams.three208v);
      // The sqrt(3) relationship is stated, not just asserted.
      expect(t.notes.contains('square root of 3'), isTrue);
      expect(t.notes.contains('208V'), isTrue);
    });

    test('three topologies, the three named assets, no em dash anywhere', () {
      expect(PowerPhasingScreen.topologies.length, 3);
      expect(
        PowerPhasingScreen.topologies.map((PowerTopology t) => t.assetName),
        PowerPhasingDiagrams.all,
      );
      for (final PowerTopology t in PowerPhasingScreen.topologies) {
        for (final String s in <String>[t.name, t.notes, t.where]) {
          expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        }
      }
    });
  });

  group('208V vs 240V comparison — the load-bearing distinction', () {
    PhasingComparison cmpFor(String attr) => PowerPhasingScreen.comparison
        .firstWhere((PhasingComparison c) => c.attribute == attr);

    test('phase angle: split 180 deg vs wye 120 deg', () {
      final PhasingComparison c = cmpFor('Phase angle between hots');
      expect(c.split240, '180 deg');
      expect(c.wye208, '120 deg');
    });

    test('hot-to-hot: split 240V vs wye 208V', () {
      final PhasingComparison c = cmpFor('Hot-to-hot voltage');
      expect(c.split240, '240V');
      expect(c.wye208, '208V');
    });

    test('hot-to-neutral is 120V on both', () {
      final PhasingComparison c = cmpFor('Hot-to-neutral');
      expect(c.split240, '120V');
      expect(c.wye208, '120V');
    });

    test('five comparison rows; the note states they are not interchangeable',
        () {
      expect(PowerPhasingScreen.comparison.length, 5);
      expect(
        PowerPhasingScreen.comparisonNote.contains('not interchangeable'),
        isTrue,
      );
      expect(
        PowerPhasingScreen.comparisonNote.contains('13 percent'),
        isTrue,
        reason: '240V gear runs ~13% low on 208V (research brief)',
      );
      // GL-004: ASCII only, no em dash, "Access Point" never "router".
      expect(PowerPhasingScreen.comparisonNote.contains('—'), isFalse);
    });

    test('copy: GL-004 voice — Access Point, no router, no em dash', () {
      for (final PowerTopology t in PowerPhasingScreen.topologies) {
        expect(t.notes.toLowerCase().contains('router'), isFalse);
      }
      // Single-phase note names the Access Point as the served device.
      final PowerTopology single = PowerPhasingScreen.topologies
          .firstWhere((PowerTopology t) => t.name == 'Single-phase 120V');
      expect(single.notes.contains('Access Point'), isTrue);
    });
  });

  group('catalog + router + help registration', () {
    test(
        'Quick Reference / Power & Cooling subgroup carries the live '
        'power-phasing tool', () {
      final ToolCategory cat = kToolCategories
          .firstWhere((ToolCategory c) => c.id == 'quick-reference');
      final ToolEntry tool =
          cat.tools.firstWhere((ToolEntry t) => t.id == 'power-phasing');
      expect(tool.isLive, isTrue);
      expect(tool.routeName, '/tools/power-phasing');
      expect(tool.subgroup, 'Power & Cooling');
    });

    test('power-phasing route resolves to a registered builder', () {
      expect(AppRouter.routes.containsKey('/tools/power-phasing'), isTrue);
    });
  });

  group('PowerPhasingScreen widget', () {
    setUp(() {
      // No waveform SVGs bundled by default → bands render nothing, and the
      // page must still ship fully working.
      PowerPhasingDiagrams.debugSetBundled(const <String>{});
    });
    tearDown(() {
      PowerPhasingDiagrams.debugReset();
    });

    testWidgets('renders title, topology names, and the comparison table',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(375, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const PowerPhasingScreen(),
          ),
        );

        expect(find.text('Power Phasing'), findsWidgets);
        expect(find.text('Single-phase 120V'), findsOneWidget);
        expect(find.text('Split-phase 120/240V'), findsOneWidget);
        // "Three-phase wye 208V" appears twice — the topology card title and the
        // comparison-table column header — so match widgets, not exactly one.
        expect(find.text('Three-phase wye 208V'), findsWidgets);
        expect(find.text('208V vs 240V'), findsOneWidget);
        // Read-only reference: no inputs.
        expect(find.byType(TextField), findsNothing);
        // No bundled waveforms → no SvgPicture (graceful degradation).
        expect(find.byType(SvgPicture), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths',
        (WidgetTester tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 1400), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const PowerPhasingScreen(),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });

    testWidgets('renders exactly the bundled waveform count (dark)',
        (WidgetTester tester) async {
      // All three waveforms bundled → exactly three SvgPicture bands (dark path
      // uses SvgPicture.asset). Proves the per-topology band wiring.
      PowerPhasingDiagrams.debugSetBundled(<String>{
        for (final String name in PowerPhasingDiagrams.all)
          PowerPhasingDiagrams.path(name),
      });
      addTearDown(() => PowerPhasingDiagrams.debugReset());

      await _withViewport(tester, const Size(375, 1400), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const PowerPhasingScreen(),
          ),
        );
        await tester.pump();
        expect(find.byType(SvgPicture), findsNWidgets(3));
      });
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors the poe_reference_screen_test _withViewport so the read-only
/// reference renders at phone width without a RenderFlex overflow.
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
