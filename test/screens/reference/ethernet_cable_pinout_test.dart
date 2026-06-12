// Tests for the RJ-45 pinout section of the consolidated Ethernet Cable &
// Connector screen.
//
// The pinout merged into EthernetCableScreen 2026-06-12 (was its own
// ethernet-pinout tile). The PINOUT dataset is still ported verbatim from the
// RF Tools PWA (app.js `const PINOUT`). These tests assert the load-bearing
// anchor pins so a future edit cannot silently drift the wiring away from the
// PWA, plus phone-viewport widget tests confirming the pinout section toggles
// and renders without a RenderFlex overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/ethernet_cable_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('T568B pinout — match PWA app.js PINOUT.T568B', () {
    PinoutPin pinFor(int n) => EthernetCableScreen
        .pinout[WiringStandard.t568b]!
        .firstWhere((PinoutPin p) => p.pin == n);

    test('pin 1 is Orange / White, pair 2, TX+', () {
      final PinoutPin p = pinFor(1);
      expect(p.colorName, 'Orange / White');
      expect(p.pair, 2);
      expect(p.function, 'TX+');
    });

    test('pin 2 is Orange, pair 2, TX-', () {
      final PinoutPin p = pinFor(2);
      expect(p.colorName, 'Orange');
      expect(p.pair, 2);
      expect(p.function, 'TX-');
    });

    test('pin 3 is Green / White, pair 3, RX+', () {
      final PinoutPin p = pinFor(3);
      expect(p.colorName, 'Green / White');
      expect(p.pair, 3);
      expect(p.function, 'RX+');
    });

    test('pin 6 is Green, pair 3, RX-', () {
      final PinoutPin p = pinFor(6);
      expect(p.colorName, 'Green');
      expect(p.pair, 3);
      expect(p.function, 'RX-');
    });
  });

  group('T568A pinout — match PWA app.js PINOUT.T568A', () {
    PinoutPin pinFor(int n) => EthernetCableScreen
        .pinout[WiringStandard.t568a]!
        .firstWhere((PinoutPin p) => p.pin == n);

    test('pin 1 is Green / White, pair 3, TX+ (the A/B swap vs T568B)', () {
      final PinoutPin p = pinFor(1);
      expect(p.colorName, 'Green / White');
      expect(p.pair, 3);
      expect(p.function, 'TX+');
    });

    test('pin 3 is Orange / White, pair 2, RX+', () {
      final PinoutPin p = pinFor(3);
      expect(p.colorName, 'Orange / White');
      expect(p.pair, 2);
      expect(p.function, 'RX+');
    });
  });

  group('dataset integrity', () {
    test('each standard has exactly 8 pins, numbered 1–8 in order', () {
      for (final WiringStandard s in WiringStandard.values) {
        final List<PinoutPin> pins = EthernetCableScreen.pinout[s]!;
        expect(pins.length, 8, reason: '${s.name} must have 8 pins');
        expect(
          pins.map((PinoutPin p) => p.pin).toList(),
          <int>[1, 2, 3, 4, 5, 6, 7, 8],
        );
      }
    });

    test('pins 4, 5, 7, 8 are identical across both standards', () {
      // Only pairs 2 and 3 swap between A and B; the Blue (pair 1) and Brown
      // (pair 4) wires are the same on both, verbatim from the PWA.
      final List<PinoutPin> b = EthernetCableScreen.pinout[WiringStandard.t568b]!;
      final List<PinoutPin> a = EthernetCableScreen.pinout[WiringStandard.t568a]!;
      for (final int n in <int>[4, 5, 7, 8]) {
        final PinoutPin pb = b.firstWhere((PinoutPin p) => p.pin == n);
        final PinoutPin pa = a.firstWhere((PinoutPin p) => p.pin == n);
        expect(pa.colorName, pb.colorName, reason: 'pin $n color');
        expect(pa.pair, pb.pair, reason: 'pin $n pair');
        expect(pa.function, pb.function, reason: 'pin $n function');
      }
    });

    test('four pair colors are defined (1 blue, 2 orange, 3 green, 4 brown)', () {
      expect(EthernetCableScreen.pairColors.keys.toList()..sort(),
          <int>[1, 2, 3, 4]);
    });

    test('no em dash or Unicode minus in any wire color or function', () {
      for (final WiringStandard s in WiringStandard.values) {
        for (final PinoutPin p in EthernetCableScreen.pinout[s]!) {
          expect(p.colorName.contains('—'), isFalse, reason: 'no em dash');
          expect(p.colorName.contains('−'), isFalse, reason: 'no Unicode minus');
          expect(p.function.contains('—'), isFalse, reason: 'no em dash');
          expect(p.function.contains('−'), isFalse, reason: 'no Unicode minus');
        }
      }
      expect(EthernetCableScreen.pinoutFootnote.contains('—'), isFalse);
    });
  });

  group('EthernetCableScreen pinout section widget', () {
    testWidgets('renders title, toggle, and T568B pins in a phone viewport',
        (tester) async {
      await _withViewport(tester, const Size(375, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const EthernetCableScreen(),
          ),
        );
        await tester.pump();

        // App-bar title plus the section header and toggle segments.
        expect(find.text('Ethernet Cable & Connector'), findsWidgets);
        expect(find.text('RJ-45 pinout'), findsWidgets);
        expect(find.text('T568B'), findsWidgets);
        expect(find.text('T568A'), findsWidgets);

        // Default standard is T568B: its pin-1 wire color and TX+ render.
        expect(find.text('Orange / White'), findsWidgets);
        expect(find.text('TX+'), findsOneWidget);

        // Read-only reference: no inputs.
        expect(find.byType(TextField), findsNothing);
      });
    });

    testWidgets('tapping T568A swaps to the A wiring (pin 1 = Green / White)',
        (tester) async {
      await _withViewport(tester, const Size(375, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const EthernetCableScreen(),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('T568A'));
        await tester.pumpAndSettle();

        // After the swap, pin 1 carries the Green / White wire and still TX+.
        expect(find.text('Green / White'), findsWidgets);
        expect(find.text('TX+'), findsOneWidget);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths',
        (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 2600), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const EthernetCableScreen(),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
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
