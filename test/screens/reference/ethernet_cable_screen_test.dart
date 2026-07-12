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

    test('Cat6 carries 10G to 37-55m at 250 MHz', () {
      // RE-SOURCED 2026-07-11. Was a flat '55m'. Both numbers are real: 55 m is
      // the favorable-alien-crosstalk case, 37 m is the dense-bundle planning
      // distance — and the structured-cabling screen had been saying so all
      // along, so the app contradicted itself across two screens. In a real
      // ceiling that gap is the install failing, so the planning number leads.
      final EthCable e = rowFor('Cat6');
      expect(e.maxMhz, 250);
      expect(e.dist10g, '37-55m');
    });

    test('Cat8 is 25/40 Gbps, runs 1G/10G to 100m, 2000 MHz', () {
      final EthCable e = rowFor('Cat8');
      expect(e.maxSpeed, '25/40 Gbps');
      expect(e.maxMhz, 2000);
      // Cat8 carries the lower rates the full 100 m channel; the 25/40G design
      // rate (limited to ~30 m) is captured in the use note + footnote.
      expect(e.dist1g, '100m');
      expect(e.dist10g, '100m');
      expect(e.use, contains('30 m'));
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
    testWidgets('renders consolidated title, both section headers, and key '
        'cells in a phone viewport', (tester) async {
      // Taller viewport: the consolidated tool now carries the pinout section
      // beneath the cable chart.
      await _withViewport(tester, const Size(375, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const EthernetCableScreen(),
          ),
        );

        // Consolidated 2026-06-12 — retitled "Ethernet Cable & Connector".
        expect(find.text('Ethernet Cable & Connector'), findsWidgets);
        // Two clear sections.
        expect(find.text('Cable categories'), findsWidgets);
        expect(find.text('RJ-45 pinout'), findsWidgets);
        expect(find.text('6 cable categories'), findsOneWidget);
        // Cat6A anchor cells render verbatim from the PWA. 'Cat6A' now appears
        // in both the cable-categories table and the multigig minimum-cabling
        // table added in the 2026-06-08 improvement, so it renders more than
        // once.
        expect(find.text('Cat6A'), findsWidgets);
        expect(find.text('500'), findsOneWidget);
        expect(find.text('802.3bt (all)'), findsOneWidget);
        // The folded-in pinout: T568B default pin-1 wiring renders.
        expect(find.text('T568B'), findsWidgets);
        expect(find.text('Orange / White'), findsWidgets);
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
