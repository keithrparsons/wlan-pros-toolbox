// Tests for the Ethernet Cable reference screen.
//
// The dataset is ported verbatim from the RF Tools PWA (app.js ETH_DATA,
// view data-tool="ethernet"). These tests assert the load-bearing anchor rows
// so a future edit cannot silently drift a value away from the PWA, plus one
// phone-viewport widget test (see test/widget_test.dart _withViewport)
// confirming the read-only screen renders without a RenderFlex overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/ethernet_cable_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Ethernet categories — match PWA app.js ETH_DATA', () {
    EthCable rowFor(String cat) =>
        EthernetCableScreen.ethData.firstWhere((EthCable e) => e.category == cat);

    test('six cable categories', () {
      expect(EthernetCableScreen.ethData.length, 6);
    });

    test('Cat6A is 10 Gbps to 100m at 500 MHz with full 802.3bt PoE', () {
      final EthCable e = rowFor('Cat6A');
      expect(e.maxSpeed, '10 Gbps');
      expect(e.maxMhz, 500);
      expect(e.dist10g, '100m');
      expect(e.poe, '802.3bt (all)');
      expect(e.shielding, 'F/UTP, S/FTP');
    });

    test('Cat5e is 1 Gbps at 100 MHz, no 10G distance', () {
      final EthCable e = rowFor('Cat5e');
      expect(e.maxSpeed, '1 Gbps');
      expect(e.maxMhz, 100);
      expect(e.dist1g, '100m');
      expect(e.dist10g, 'N/A');
    });

    test('Cat6 carries 10G only to 55m at 250 MHz', () {
      final EthCable e = rowFor('Cat6');
      expect(e.maxMhz, 250);
      expect(e.dist10g, '55m');
    });

    test('Cat8 is 25/40 Gbps, 30m at 10G, 2000 MHz, no 1G distance', () {
      final EthCable e = rowFor('Cat8');
      expect(e.maxSpeed, '25/40 Gbps');
      expect(e.maxMhz, 2000);
      expect(e.dist10g, '30m');
      expect(e.dist1g, 'N/A');
    });

    test('Cat7A is 40 Gbps at 1000 MHz', () {
      final EthCable e = rowFor('Cat7A');
      expect(e.maxSpeed, '40 Gbps');
      expect(e.maxMhz, 1000);
    });

    test('no em dash or Unicode minus ships in any cell', () {
      for (final EthCable e in EthernetCableScreen.ethData) {
        for (final String field in [
          e.category,
          e.maxSpeed,
          e.dist1g,
          e.dist10g,
          e.poe,
          e.shielding,
          e.use,
        ]) {
          expect(field.contains('—'), isFalse, reason: 'no em dash in "$field"');
          expect(field.contains('−'), isFalse,
              reason: 'no Unicode minus in "$field"');
        }
      }
      expect(EthernetCableScreen.footnote.contains('—'), isFalse);
    });
  });

  group('EthernetCableScreen widget', () {
    testWidgets('renders title and key cells in a phone viewport',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const EthernetCableScreen(),
          ),
        );

        expect(find.text('Ethernet Cable'), findsWidgets);
        expect(find.text('6 cable categories'), findsOneWidget);
        // Cat6A anchor cells render verbatim from the PWA.
        expect(find.text('Cat6A'), findsOneWidget);
        expect(find.text('500'), findsOneWidget);
        expect(find.text('802.3bt (all)'), findsOneWidget);
        // Read-only reference: no inputs.
        expect(find.byType(TextField), findsNothing);
      });
    });
  });

  testWidgets('renders without overflow at 320/375/768/1280 widths',
      (tester) async {
    for (final double width in <double>[320, 375, 768, 1280]) {
      await _withViewport(tester, Size(width, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const EthernetCableScreen(),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
      });
    }
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors test/widget_test.dart _withViewport so the read-only reference
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
