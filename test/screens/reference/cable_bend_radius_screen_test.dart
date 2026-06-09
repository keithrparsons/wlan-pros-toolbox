// Tests for the Cable Bend Radius & Pull Tension reference screen.
//
// Three layers, mirroring iec_connectors_screen_test / nema_connectors_screen_test:
//   1. Data fidelity (GL-005): the typed const datasets match Pax's verified
//      research brief, with the brief's CRITICAL honesty corrections pinned so a
//      future edit cannot silently re-introduce the standards errors —
//        * 4x OD installed (UTP) and 25 lbf / 110 N pull are TIA-568;
//        * the 8x-during-pull copper figure is ISO 11801 / practice, NOT TIA;
//        * the fiber "datasheet wins" caveat is present and visible;
//        * the 0.5 in untwist is a TIA standard;
//      plus the no-em-dash / "Wi-Fi" / US-spelling glyph rules.
//   2. Glyph + voice hygiene (GL-004): no em dash, no "router", no "WiFi" in any
//      data or note string.
//   3. Widget render: the read-only screen renders title + section headings + key
//      values ("4" and "25 lbf") across phone/tablet widths with no RenderFlex
//      overflow, and each concept graphic renders exactly the bundled count
//      (zero when none built, the bundled count when present) — proving graceful
//      degradation via BendDiagrams.debugSetBundled.
//
// NOTE: catalog/router/help registration is Larry's central wiring step (this
// build touches no shared file), so this test deliberately does NOT assert the
// catalog entry — that contract is verified after Larry registers the tool.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/bend_diagrams.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/cable_bend_radius_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Bend radius — match the research brief (copper + fiber)', () {
    BendLimit copperFor(String condition) => CableBendRadiusScreen.copperBend
        .firstWhere((BendLimit b) => b.condition.contains(condition));

    test('installed UTP = >= 4x OD, attributed to TIA-568 (standard)', () {
      final BendLimit b = copperFor('Installed');
      expect(b.limit.contains('4x OD'), isTrue);
      expect(b.basis, LimitBasis.standard);
      expect(b.source, 'TIA-568');
    });

    test('8x-during-pull is ISO 11801 / practice, NOT attributed to TIA', () {
      final BendLimit b = copperFor('During pull');
      expect(b.limit.contains('8x OD'), isTrue);
      expect(b.basis, LimitBasis.practice,
          reason: 'the 8x pull figure is a rule of thumb, not a TIA clause');
      expect(b.source.toLowerCase().contains('iso 11801'), isTrue);
      expect(b.source.toUpperCase().contains('TIA'), isFalse,
          reason: 'CRITICAL: 8x pull must never read as TIA (brief correction)');
    });

    test('fiber datasheet-wins caveat is present and load-bearing', () {
      final String caveat = CableBendRadiusScreen.fiberDatasheetNote;
      expect(caveat.toLowerCase().contains('datasheet'), isTrue);
      expect(caveat.toLowerCase().contains('binding'), isTrue,
          reason: 'the datasheet is the binding number (brief honesty note)');
      // The 10x/20x rule-of-thumb vs G.657 bare-fiber distinction is stated.
      expect(caveat.contains('10x') || caveat.contains('20x'), isTrue);
    });

    test('G.657 bend-insensitive radii are present (10 mm down to 2 mm)', () {
      final List<String> limits = CableBendRadiusScreen.fiberBend
          .map((BendLimit b) => b.limit)
          .toList();
      expect(limits.any((String l) => l.contains('10 mm')), isTrue);
      expect(limits.any((String l) => l.contains('2 mm')), isTrue);
    });
  });

  group('Pull tension — match the research brief', () {
    InstallLimit pullFor(String name) => CableBendRadiusScreen.pullTension
        .firstWhere((InstallLimit l) => l.name.contains(name));

    test('4-pair UTP = 25 lbf (110 N), TIA-568 §10.6.3.2 (standard)', () {
      final InstallLimit l = pullFor('4-pair UTP');
      expect(l.value.contains('25 lbf'), isTrue);
      expect(l.value.contains('110 N'), isTrue);
      expect(l.basis, LimitBasis.standard);
      expect(l.source.contains('TIA-568'), isTrue);
    });

    test('fiber pull tension is per-datasheet, not a single published number',
        () {
      final InstallLimit l = pullFor('Fiber');
      expect(l.value.toLowerCase().contains('datasheet'), isTrue);
      expect(l.basis, LimitBasis.practice);
    });

    test('over-pull consequences and conservative-margin framing are stated',
        () {
      final String note = CableBendRadiusScreen.pullNote.toLowerCase();
      expect(note.contains('stretch'), isTrue);
      expect(note.contains('attenuation'), isTrue);
      expect(note.contains('next'), isTrue);
      // The failure thresholds are flagged as illustrative, not a spec.
      expect(note.contains('illustration') || note.contains('not a spec'),
          isTrue);
    });
  });

  group('Related install limits — match the research brief', () {
    InstallLimit limitFor(String name) => CableBendRadiusScreen.installLimits
        .firstWhere((InstallLimit l) => l.name.contains(name));

    test('max untwist = <= 0.5 in (13 mm), TIA-568-B.1 (standard)', () {
      final InstallLimit l = limitFor('untwist');
      expect(l.value.contains('0.5 in'), isTrue);
      expect(l.value.contains('13 mm'), isTrue);
      expect(l.basis, LimitBasis.standard);
      expect(l.source.contains('TIA-568-B.1'), isTrue);
    });

    test('cable-tie limit = no sheath deformation (standard + practice)', () {
      final InstallLimit l = limitFor('Cable-tie');
      expect(l.value.toLowerCase().contains('deformation'), isTrue);
      expect(l.basis, LimitBasis.standard);
    });
  });

  group('GL-004 voice + glyph hygiene', () {
    test('no em dash, no "router", no "WiFi" anywhere in data/notes', () {
      final List<String> prose = <String>[
        CableBendRadiusScreen.leadNote,
        CableBendRadiusScreen.kinkNote,
        CableBendRadiusScreen.fiberDatasheetNote,
        CableBendRadiusScreen.pullNote,
        CableBendRadiusScreen.pullFiberNote,
        CableBendRadiusScreen.installNote,
        for (final BendLimit b in <BendLimit>[
          ...CableBendRadiusScreen.copperBend,
          ...CableBendRadiusScreen.fiberBend,
        ]) ...<String>[b.condition, b.limit, b.source],
        for (final InstallLimit l in <InstallLimit>[
          ...CableBendRadiusScreen.pullTension,
          ...CableBendRadiusScreen.installLimits,
        ]) ...<String>[l.name, l.value, l.source],
      ];
      for (final String s in prose) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        expect(s.toLowerCase().contains('router'), isFalse,
            reason: 'never "router" in "$s"');
        expect(s.contains('WiFi'), isFalse,
            reason: 'use "Wi-Fi", never "WiFi", in "$s"');
      }
    });
  });

  group('CableBendRadiusScreen widget', () {
    setUp(() {
      // No concept graphic bundled by default → each LargeGraphic renders
      // nothing, and the page must still ship fully working as text + tables.
      BendDiagrams.debugSetBundled(const <String>{});
    });
    tearDown(() {
      BendDiagrams.debugReset();
    });

    testWidgets('renders title, section headings, and key values', (
      tester,
    ) async {
      await _withViewport(tester, const Size(375, 3000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const CableBendRadiusScreen(),
          ),
        );

        expect(find.text('Bend Radius & Pull Tension'), findsWidgets);
        // The three section headings.
        expect(find.text('Minimum bend radius'), findsOneWidget);
        expect(find.text('Maximum pull tension'), findsOneWidget);
        expect(find.text('Related install limits'), findsOneWidget);
        // The two load-bearing values render: the "4" (>= 4x OD) and "25 lbf".
        expect(find.text('>= 4x OD'), findsOneWidget);
        expect(find.text('25 lbf (110 N)'), findsOneWidget);
        // Read-only reference: no inputs.
        expect(find.byType(TextField), findsNothing);
        // No bundled graphic → no SvgPicture (graceful degradation: each section
        // reads as text + tables alone).
        expect(find.byType(SvgPicture), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768 widths', (
      tester,
    ) async {
      for (final double width in <double>[320, 375, 768]) {
        await _withViewport(tester, Size(width, 2400), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const CableBendRadiusScreen(),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });

    testWidgets('renders exactly the bundled concept-graphic count (dark)', (
      tester,
    ) async {
      // Both named graphics bundled → exactly two SvgPicture concept graphics
      // (dark path uses SvgPicture.asset): the arc-vs-kink and the pull-tension
      // gauge. Proves the per-graphic wiring + graceful degradation.
      BendDiagrams.debugSetBundled(<String>{
        for (final String name in BendDiagrams.all) BendDiagrams.path(name),
      });
      addTearDown(() => BendDiagrams.debugReset());

      await _withViewport(tester, const Size(375, 4000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const CableBendRadiusScreen(),
          ),
        );
        await tester.pump();
        expect(find.byType(SvgPicture), findsNWidgets(2));
      });
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors iec_connectors_screen_test._withViewport so the read-only reference
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
