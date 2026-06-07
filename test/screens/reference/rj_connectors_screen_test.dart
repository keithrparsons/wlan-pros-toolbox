// Tests for the RJ Connectors reference screen (Batch 5).
//
// Two layers:
//  1. Data assertions against the public const the UI renders — locks the
//     positions/conductors (RJ45 = 8P8C, RJ11 = 6P2C) and the load-bearing
//     EPISTEMIC-HONESTY fact (RJ45 is colloquial for 8P8C).
//  2. Widget tests in phone/tablet/desktop viewports — title + representative
//     rows render; the Ethernet Pinout cross-link routes; no overflow.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/connector_diagrams.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/ethernet_pinout_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/rj_connectors_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('RJ connector dataset', () {
    test('ships RJ11, RJ45 (8P8C) and an RJ48 family member', () {
      final Set<String> names =
          RjConnectorsScreen.connectors.map((RjConnectorEntry c) => c.name)
              .toSet();
      expect(names, containsAll(<String>['RJ11', 'RJ14', 'RJ25',
          'RJ45 (8P8C)', 'RJ48']));
    });

    test('RJ11 is 6P2C: 6 positions, 2 conductors', () {
      final RjConnectorEntry rj11 = RjConnectorsScreen.connectors
          .firstWhere((RjConnectorEntry c) => c.name == 'RJ11');
      expect(rj11.modular, '6P2C');
      expect(rj11.positions, 6);
      expect(rj11.conductors, 2);
    });

    test('RJ45 is 8P8C: 8 positions, 8 conductors', () {
      final RjConnectorEntry rj45 = RjConnectorsScreen.connectors
          .firstWhere((RjConnectorEntry c) => c.name == 'RJ45 (8P8C)');
      expect(rj45.modular, '8P8C');
      expect(rj45.positions, 8);
      expect(rj45.conductors, 8);
    });

    test('RJ48 reuses the 8P8C body (different assignment)', () {
      final RjConnectorEntry rj48 = RjConnectorsScreen.connectors
          .firstWhere((RjConnectorEntry c) => c.name == 'RJ48');
      expect(rj48.modular, '8P8C');
      expect(rj48.typicalUse.toLowerCase(), contains('t1'));
    });

    // EPISTEMIC HONESTY: "RJ45" is colloquial for the 8P8C modular connector.
    test('RJ45 note states it is the colloquial name for 8P8C', () {
      final RjConnectorEntry rj45 = RjConnectorsScreen.connectors
          .firstWhere((RjConnectorEntry c) => c.name == 'RJ45 (8P8C)');
      expect(rj45.typicalUse.toLowerCase(), contains('8p8c'));
      expect(rj45.typicalUse.toLowerCase(), contains('colloquial'));
    });

    test('intro and footnote cross-reference Ethernet Pinout, not duplicate', () {
      expect(RjConnectorsScreen.footnote, contains('Ethernet Pinout'));
      expect(RjConnectorsScreen.footnote.toLowerCase(),
          contains('not the wiring'));
      // The screen must NOT contain T568A/B pin-color content (that lives in the
      // Ethernet Pinout tool). No connector note mentions a wire color pair.
      for (final RjConnectorEntry c in RjConnectorsScreen.connectors) {
        expect(c.typicalUse.toLowerCase(), isNot(contains('t568')));
      }
    });

    test('positions are always >= conductors', () {
      for (final RjConnectorEntry c in RjConnectorsScreen.connectors) {
        expect(c.conductors, lessThanOrEqualTo(c.positions),
            reason: '${c.name} cannot have more conductors than positions');
      }
    });

    // Each connector carries a stable diagram id matching a shipped SVG so the
    // per-connector line drawing resolves. The eight ids are the filenames in
    // assets/connector-diagrams/.
    test('every connector maps to a known diagram id', () {
      final List<String> ids = RjConnectorsScreen.connectors
          .map((RjConnectorEntry c) => c.diagramId)
          .toList();
      expect(ids, <String>[
        'rj11',
        'rj14',
        'rj25',
        'rj45-8p8c',
        'rj48',
        'rj48c',
        'rj48x',
        'rj9-rj22',
      ]);
      // Ids are unique (no two cards collide on the same drawing).
      expect(ids.toSet().length, ids.length);
    });
  });

  group('RjConnectorsScreen widget', () {
    setUp(() {
      // Default: nothing bundled, so the diagram slots collapse and the
      // data-only screen renders (matches the resolver's pre-load behavior).
      ConnectorDiagrams.debugSetBundled(const <String>{});
    });

    tearDown(ConnectorDiagrams.debugReset);

    testWidgets('renders title and representative connectors in a phone '
        'viewport', (WidgetTester tester) async {
      await _withViewport(tester, const Size(375, 1400), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const RjConnectorsScreen(),
          ),
        );
        await tester.pump();

        expect(find.text('RJ Connectors'), findsOneWidget);
        expect(find.text('RJ11'), findsWidgets);
        expect(find.text('RJ45 (8P8C)'), findsWidgets);
        // The modular-body badge renders.
        expect(find.text('8P8C'), findsWidgets);
      });
    });

    testWidgets('cross-link card routes to the Ethernet Pinout tool', (
      WidgetTester tester,
    ) async {
      await _withViewport(tester, const Size(375, 1400), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            initialRoute: AppRouter.rjConnectors,
            routes: AppRouter.routes,
          ),
        );
        await tester.pumpAndSettle();

        // Bring the cross-link card into view, then tap it.
        final Finder link = find.text('Need the wiring?');
        await tester.ensureVisible(link);
        await tester.pumpAndSettle();
        await tester.tap(link);
        await tester.pumpAndSettle();

        expect(find.byType(EthernetPinoutScreen), findsOneWidget);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths', (
      WidgetTester tester,
    ) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 1600), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const RjConnectorsScreen(),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });

    testWidgets('connector diagrams are omitted when none are bundled', (
      WidgetTester tester,
    ) async {
      ConnectorDiagrams.debugSetBundled(const <String>{});
      await _withViewport(tester, const Size(375, 1400), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const RjConnectorsScreen(),
          ),
        );
        await tester.pump();
        // No per-connector SVG drawings render when the bundle is empty.
        expect(find.byType(SvgPicture), findsNothing);
      });
    });

    testWidgets('each connector with a bundled diagram renders one drawing', (
      WidgetTester tester,
    ) async {
      // Bundle all eight RJ drawings. Dark mode renders SvgPicture.asset
      // directly (one per connector card).
      ConnectorDiagrams.debugSetBundled(<String>{
        for (final RjConnectorEntry c in RjConnectorsScreen.connectors)
          'assets/connector-diagrams/${c.diagramId}.svg',
      });
      await _withViewport(tester, const Size(375, 4000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const RjConnectorsScreen(),
          ),
        );
        await tester.pump();
        expect(
          find.byType(SvgPicture),
          findsNWidgets(RjConnectorsScreen.connectors.length),
        );
      });
    });
  });
}

/// Run [body] with the test view sized to [size], then restore.
Future<void> _withViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await body();
}
