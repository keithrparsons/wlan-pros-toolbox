// Tests for the RF Connectors reference screen.
//
// The dataset is ported verbatim from the RF Tools PWA (app.js RF_CONN_DATA,
// view data-tool="rfconn"). These tests assert the load-bearing rows so a
// future edit cannot silently drift a value away from the PWA, plus one phone-
// viewport widget test (see test/widget_test.dart _withViewport) confirming the
// read-only screen renders without a RenderFlex overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/rf_connectors_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('RF connectors — match PWA app.js RF_CONN_DATA', () {
    RfConnector connFor(String name) => RfConnectorsScreen.rfConnectors
        .firstWhere((RfConnector c) => c.name == name);

    test('nine connector rows, in PWA order', () {
      expect(RfConnectorsScreen.rfConnectors.length, 9);
      expect(
        RfConnectorsScreen.rfConnectors.map((RfConnector c) => c.name).toList(),
        <String>[
          'N-Type',
          'TNC',
          'BNC',
          'SMA',
          'RP-SMA',
          'MCX',
          'MMCX',
          'U.FL/IPEX',
          'F-Type',
        ],
      );
    });

    test('N-Type is the 50 ohm outdoor WLAN standard, DC-11 GHz, screw thread',
        () {
      final RfConnector c = connFor('N-Type');
      expect(c.impedance, '50Ω');
      expect(c.maxFreq, 'DC-11 GHz');
      expect(c.mating, 'Screw thread');
      expect(c.notes.contains('Outdoor WLAN standard'), isTrue);
    });

    test('SMA handles 2.4/5/6 GHz to DC-18 GHz', () {
      final RfConnector c = connFor('SMA');
      expect(c.impedance, '50Ω');
      expect(c.maxFreq, 'DC-18 GHz');
      expect(c.notes.contains('2.4, 5, and 6 GHz'), isTrue);
    });

    test('RP-SMA is the reversed-pin FCC Part 15 variant, NOT SMA-compatible',
        () {
      final RfConnector c = connFor('RP-SMA');
      expect(c.maxFreq, 'DC-18 GHz');
      expect(c.notes.contains('reversed'), isTrue);
      expect(c.notes.contains('NOT interchangeable with SMA'), isTrue);
    });

    test('U.FL/IPEX is the fragile internal-PCB connector, ~30 mate cycles',
        () {
      final RfConnector c = connFor('U.FL/IPEX');
      expect(c.mating, 'Push-snap (fragile)');
      expect(c.notes.contains('30 mate cycles'), isTrue);
    });

    test('F-Type is 75 ohm and flagged as an impedance mismatch for Wi-Fi', () {
      final RfConnector c = connFor('F-Type');
      expect(c.impedance, '75Ω');
      expect(c.isImpedanceMismatch, isTrue);
      expect(c.notes.contains('Do not use for WLAN'), isTrue);
    });

    test('only F-Type is a non-50-ohm impedance mismatch', () {
      final List<RfConnector> mismatched = RfConnectorsScreen.rfConnectors
          .where((RfConnector c) => c.isImpedanceMismatch)
          .toList();
      expect(mismatched.length, 1);
      expect(mismatched.single.name, 'F-Type');
    });

    test('all rows use ASCII hyphen-minus — no em dash, no Unicode minus', () {
      for (final RfConnector c in RfConnectorsScreen.rfConnectors) {
        for (final String field in <String>[
          c.name,
          c.impedance,
          c.maxFreq,
          c.mating,
          c.notes,
        ]) {
          expect(field.contains('—'), isFalse, reason: 'no em dash in $field');
          expect(field.contains('–'), isFalse, reason: 'no en dash in $field');
          expect(
            field.contains('−'),
            isFalse,
            reason: 'no Unicode minus in $field',
          );
        }
      }
    });
  });

  group('RfConnectorsScreen widget', () {
    testWidgets('renders title, heading, and key rows in a phone viewport',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const RfConnectorsScreen(),
          ),
        );

        expect(find.text('RF Connectors'), findsWidgets);
        expect(find.text('Coaxial RF Connectors'), findsOneWidget);
        // Anchor connector names render.
        expect(find.text('N-Type'), findsOneWidget);
        expect(find.text('SMA'), findsOneWidget);
        expect(find.text('RP-SMA'), findsOneWidget);
        expect(find.text('F-Type'), findsOneWidget);
        // The 75 ohm mismatch chip renders (only F-Type carries it).
        expect(find.text('75Ω'), findsOneWidget);
        // Read-only reference: no inputs.
        expect(find.byType(TextField), findsNothing);
      });
    });
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
