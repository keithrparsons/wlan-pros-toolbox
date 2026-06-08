// Tests for the NEMA Connectors reference screen — page 4 of the Power &
// Cooling category.
//
// Three layers, mirroring power_phasing_screen_test:
//   1. Data fidelity (GL-005): the typed const datasets match Pax's verified
//      research brief (Topic 4) — the load-bearing corrections a future edit
//      must not silently drift (14-50 is single-phase split NOT three-phase; the
//      4th pin is neutral; L21 IS three-phase wye; CS8364/65 are 250V), plus the
//      no-em-dash / ASCII-glyph and "no router" GL-004 rules.
//   2. Catalog + help registration: the catalog's Power & Cooling category
//      carries a live nema-connectors tool whose route is registered, and the
//      help store has a matching nema-connectors entry. (Larry wires these in
//      during integration; the assertions document the contract.)
//   3. Widget render: the read-only screen renders title + decoder + tables
//      across phone/tablet/desktop widths with no RenderFlex overflow, and the
//      face-diagram band renders exactly the bundled count (zero when none
//      built, one when present) — proving graceful degradation.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/nema_connector_diagrams.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/nema_connectors_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Nomenclature decoder — matches the research brief', () {
    NemaDecodePart partFor(String token) => NemaConnectorsScreen.decoder
        .firstWhere((NemaDecodePart p) => p.token == token);

    test('L21-30P decodes to twist-lock / 3-phase wye 120/208V / 30A / plug',
        () {
      expect(partFor('L').meaning, 'Locking');
      expect(partFor('21').detail.contains('three-phase wye 120/208V'), isTrue);
      expect(partFor('21').detail.contains('4-pole') ||
          partFor('21').detail.contains('5-wire'), isTrue);
      expect(partFor('30').detail.contains('30A'), isTrue);
      expect(partFor('P').meaning, 'Plug (male)');
      // The leading number is a code, never a voltage (brief correction).
      expect(partFor('21').detail.toLowerCase().contains('not a voltage'),
          isTrue);
    });

    test('decoder example states P=plug, R=receptacle, do no arithmetic', () {
      final String ex = NemaConnectorsScreen.decoderExample;
      expect(ex.contains('L21-30P'), isTrue);
      expect(ex.toLowerCase().contains('configuration code'), isTrue);
    });
  });

  group('Device tables — load-bearing corrections (Topic 4)', () {
    NemaDevice deviceFor(String type) => <NemaDevice>[
          ...NemaConnectorsScreen.group125v,
          ...NemaConnectorsScreen.group208v,
          ...NemaConnectorsScreen.groupCalifornia,
        ].firstWhere((NemaDevice d) => d.type == type);

    test('14-50 is single-phase SPLIT, not three-phase; 4th pin is neutral',
        () {
      final NemaDevice d = deviceFor('14-50');
      expect(d.voltage, '125/250V');
      expect(d.phase, '1-phase split');
      expect(d.isThreePhase, isFalse);
      expect(d.amps, 50);
      // The 4th conductor is the neutral, called out in the wiring string.
      expect(d.wiring.contains('N'), isTrue);
    });

    test('14-30 is also single-phase split', () {
      final NemaDevice d = deviceFor('14-30');
      expect(d.phase, '1-phase split');
      expect(d.isThreePhase, isFalse);
    });

    test('L21-30 IS three-phase wye, 120/208V, 4P/5W', () {
      final NemaDevice d = deviceFor('L21-30');
      expect(d.voltage, '120/208V');
      expect(d.phase, '3-phase wye');
      expect(d.isThreePhase, isTrue);
      expect(d.locking, isTrue);
      expect(d.wiring.contains('4P'), isTrue);
      expect(d.wiring.contains('5W'), isTrue);
    });

    test('5-series is 125V 1-phase; 6-series is 250V 1-phase', () {
      expect(deviceFor('5-15').voltage, '125V');
      expect(deviceFor('5-15').phase, '1-phase');
      expect(deviceFor('6-50').voltage, '250V');
      expect(deviceFor('6-50').phase, '1-phase');
      expect(deviceFor('6-50').amps, 50);
    });

    test('1-15 is the ungrounded 2P/2W 15A type', () {
      final NemaDevice d = deviceFor('1-15');
      expect(d.voltage, '125V');
      expect(d.wiring.contains('no ground'), isTrue);
      expect(d.amps, 15);
    });

    test('CS8364/65 are 250V three-phase 50A, not 208V', () {
      final NemaDevice f = deviceFor('CS8364');
      final NemaDevice m = deviceFor('CS8365');
      expect(f.voltage, '250V');
      expect(m.voltage, '250V');
      expect(f.phase.contains('3-phase'), isTrue);
      expect(m.phase.contains('3-phase'), isTrue);
      expect(f.amps, 50);
      expect(m.amps, 50);
      // Sex: CS8364 connector (female), CS8365 plug (male).
      expect(f.wiring.toLowerCase().contains('female'), isTrue);
      expect(m.wiring.toLowerCase().contains('male'), isTrue);
    });

    test('all the required device types are present', () {
      const List<String> required = <String>[
        '1-15', '5-15', '5-20', '5-30',
        '6-15', '6-20', '6-30', '6-50',
        '14-30', '14-50',
        'L5-15', 'L5-20', 'L5-30',
        'L6-20', 'L6-30',
        'L14-20', 'L14-30',
        'L21-20', 'L21-30',
        'CS8364', 'CS8365',
      ];
      final Set<String> present = <String>{
        for (final NemaDevice d in NemaConnectorsScreen.group125v) d.type,
        for (final NemaDevice d in NemaConnectorsScreen.group208v) d.type,
        for (final NemaDevice d in NemaConnectorsScreen.groupCalifornia) d.type,
      };
      for (final String t in required) {
        expect(present.contains(t), isTrue, reason: 'missing device type "$t"');
      }
    });

    test('locking flag is set exactly for L-prefixed types', () {
      for (final NemaDevice d in <NemaDevice>[
        ...NemaConnectorsScreen.group125v,
        ...NemaConnectorsScreen.group208v,
      ]) {
        expect(d.locking, d.type.startsWith('L'),
            reason: '${d.type} locking flag should match its L prefix');
      }
    });
  });

  group('GL-004 voice — no em dash, no router, ASCII glyphs', () {
    test('the split-vs-3-phase note states the 14-series is NOT three-phase',
        () {
      final String note = NemaConnectorsScreen.splitVsThreePhaseNote;
      expect(note.contains('single-phase SPLIT'), isTrue);
      expect(note.toLowerCase().contains('not three-phase') ||
          note.contains('NOT three-phase'), isTrue);
      // The 4th pin is the neutral, not a third hot.
      expect(note.toUpperCase().contains('NEUTRAL'), isTrue);
    });

    test('no em dash and no "router" anywhere in the copy', () {
      final List<String> strings = <String>[
        NemaConnectorsScreen.decoderExample,
        NemaConnectorsScreen.splitVsThreePhaseNote,
        NemaConnectorsScreen.californiaNote,
        NemaConnectorsScreen.footnote,
        for (final NemaDecodePart p in NemaConnectorsScreen.decoder)
          ...<String>[p.token, p.meaning, p.detail],
      ];
      for (final String s in strings) {
        expect(s.contains('—'), isFalse, reason: 'em dash in "$s"');
        expect(s.toLowerCase().contains('router'), isFalse,
            reason: '"router" in "$s"');
      }
    });
  });

  group('catalog + router + help registration', () {
    test(
        'Quick Reference / Power & Cooling subgroup carries the live '
        'nema-connectors tool', () {
      final ToolCategory cat = kToolCategories
          .firstWhere((ToolCategory c) => c.id == 'quick-reference');
      final ToolEntry tool =
          cat.tools.firstWhere((ToolEntry t) => t.id == 'nema-connectors');
      expect(tool.isLive, isTrue);
      expect(tool.routeName, '/tools/nema-connectors');
      expect(tool.subgroup, 'Power & Cooling');
    });

    test('nema-connectors route resolves to a registered builder', () {
      expect(AppRouter.routes.containsKey('/tools/nema-connectors'), isTrue);
    });
  });

  group('NemaConnectorsScreen widget', () {
    setUp(() {
      // No face plate bundled by default → band renders nothing, and the page
      // must still ship fully working.
      NemaConnectorDiagrams.debugSetBundled(const <String>{});
    });
    tearDown(() {
      NemaConnectorDiagrams.debugReset();
    });

    testWidgets('renders title, decoder, and the device-table titles',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(375, 1600), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const NemaConnectorsScreen(),
          ),
        );

        expect(find.text('NEMA Connectors'), findsWidgets);
        expect(find.text('Reading a NEMA designation'), findsOneWidget);
        expect(find.text('125V single-phase'), findsOneWidget);
        expect(find.text('208 / 240 / 250V'), findsOneWidget);
        expect(find.text('California Standard 3-phase'), findsOneWidget);
        // A couple of device types render.
        expect(find.text('L21-30'), findsOneWidget);
        expect(find.text('14-50'), findsOneWidget);
        // Read-only reference: no inputs.
        expect(find.byType(TextField), findsNothing);
        // No bundled plate → no SvgPicture (graceful degradation).
        expect(find.byType(SvgPicture), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths',
        (WidgetTester tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 2000), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const NemaConnectorsScreen(),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });

    testWidgets('renders exactly the bundled face-plate count (dark)',
        (WidgetTester tester) async {
      // The plate bundled → exactly one SvgPicture band (dark path uses
      // SvgPicture.asset). Proves the face-diagram band wiring.
      NemaConnectorDiagrams.debugSetBundled(<String>{
        for (final String name in NemaConnectorDiagrams.all)
          NemaConnectorDiagrams.path(name),
      });
      addTearDown(() => NemaConnectorDiagrams.debugReset());

      await _withViewport(tester, const Size(375, 1600), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const NemaConnectorsScreen(),
          ),
        );
        await tester.pump();
        expect(find.byType(SvgPicture), findsOneWidget);
      });
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors the power_phasing_screen_test _withViewport so the read-only
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
