// Tests for the OSI Model reference screen.
//
// Dataset assertions guard the 7-layer table against silent drift from the Pax
// research deliverable + Keith's decisions (neutral keyword column; ARP at L2).
// A widget smoke confirms the read-only screen renders without a RenderFlex
// overflow across phone/tablet/desktop widths.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/osi_model_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('OSI layers — match the Pax research dataset', () {
    OsiLayer layerFor(int n) =>
        OsiModelScreen.layers.firstWhere((OsiLayer l) => l.num == n);

    test('seven layers, numbered 7 down to 1', () {
      expect(OsiModelScreen.layers.length, 7);
      expect(
        OsiModelScreen.layers.map((OsiLayer l) => l.num).toList(),
        <int>[7, 6, 5, 4, 3, 2, 1],
      );
    });

    test('L7 Application, L1 Physical, L4 Transport names', () {
      expect(layerFor(7).name, 'Application');
      expect(layerFor(4).name, 'Transport');
      expect(layerFor(1).name, 'Physical');
    });

    test('PDUs: L4 Segment, L3 Packet, L2 Frame, L1 Bit', () {
      expect(layerFor(4).pdu, 'Segment');
      expect(layerFor(3).pdu, 'Packet');
      expect(layerFor(2).pdu, 'Frame');
      expect(layerFor(1).pdu, 'Bit');
    });

    test('ARP sits at Layer 2 (Keith decision #1)', () {
      expect(layerFor(2).protocols.contains('ARP'), isTrue);
      // ARP must NOT also appear at L3.
      expect(layerFor(3).protocols.contains('ARP'), isFalse);
    });

    test('neutral keyword column (no custom mnemonic)', () {
      expect(layerFor(3).keyword, 'Routing');
      expect(layerFor(2).keyword, 'Framing');
      expect(layerFor(1).keyword, 'Bits');
    });

    test('802.3 / 802.11 casing, no em dash anywhere', () {
      expect(layerFor(2).protocols.contains('802.3'), isTrue);
      expect(layerFor(2).protocols.contains('802.11'), isTrue);
      for (final OsiLayer l in OsiModelScreen.layers) {
        expect(l.protocols.contains('—'), isFalse, reason: 'no em dash');
        expect(l.hardware.contains('—'), isFalse, reason: 'no em dash');
      }
    });
  });

  group('OsiModelScreen widget', () {
    testWidgets('renders the title, intro, and an anchor layer row',
        (tester) async {
      await _withViewport(tester, const Size(375, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const OsiModelScreen()),
        );
        expect(find.text('OSI Model'), findsWidgets);
        expect(find.text('The 7 layers'), findsOneWidget);
        // 'Application' and 'Physical' now each render in both the 7-layer OSI
        // table and the TCP/IP-mapping table added in the 2026-06-08
        // improvement, so they appear more than once.
        expect(find.text('Application'), findsWidgets);
        expect(find.text('Physical'), findsWidgets);
        expect(find.byType(TextField), findsNothing); // read-only
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths',
        (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 1400), () async {
          await tester.pumpWidget(
            MaterialApp(theme: AppTheme.dark(), home: const OsiModelScreen()),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });
  });
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
