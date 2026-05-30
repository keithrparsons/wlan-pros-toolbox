// Tests for the Cable Loss calculator.
//
// The math is verified against the RF Tools PWA reference (app.js calcCable +
// cableLossPer100ft + CABLE_DATA):
//   per100ft(f) interpolated on a sqrt(f) axis across manufacturer knots,
//                clamped at the low end, sqrt-extrapolated above the top knot;
//   totalLoss = per100ft × length_ft / 100, with m ×3.28084 to ft and GHz
//                ×1000 to MHz.
// Expected values below were computed from that exact algorithm so the native
// app and PWA agree to the decimal.
//
// One widget test confirms the screen pumps and renders its cards.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/cable_loss_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Cable loss per-100ft (pure) — matches PWA cableLossPer100ft', () {
    test('exact knot returns the spec value (LMR-400 at 2400 MHz)', () {
      expect(
        CableLossScreen.cableLossPer100ft('LMR-400', 2400),
        closeTo(3.9, 1e-9),
      );
    });

    test('interpolates on the sqrt(f) axis (LMR-400 at 2000 MHz)', () {
      expect(
        CableLossScreen.cableLossPer100ft('LMR-400', 2000),
        closeTo(3.483971601653905, 1e-9),
      );
    });

    test('clamps to the lowest knot at or below the first frequency', () {
      // At the first knot exactly, and below it, both return pts.first[1].
      expect(CableLossScreen.cableLossPer100ft('LMR-400', 100), closeTo(0.7, 1e-9));
      expect(CableLossScreen.cableLossPer100ft('LMR-400', 50), closeTo(0.7, 1e-9));
    });

    test('sqrt-extrapolates above the top knot (LMR-400 at 6000 MHz)', () {
      expect(
        CableLossScreen.cableLossPer100ft('LMR-400', 6000),
        closeTo(6.415012272330055, 1e-9),
      );
    });

    test('extrapolates an RG cable beyond its 2400 MHz top knot', () {
      // RG-58 tops out at 2400 MHz; 8000 MHz extrapolates on sqrt(f).
      expect(
        CableLossScreen.cableLossPer100ft('RG-58', 8000),
        closeTo(39.71397488376698, 1e-9),
      );
    });

    test('unknown cable type returns null (no crash)', () {
      expect(CableLossScreen.cableLossPer100ft('NOT-A-CABLE', 2400), isNull);
    });
  });

  group('Total loss + unit normalization — matches PWA calcCable', () {
    test('GHz converts to MHz at 1000x', () {
      expect(CableLossScreen.freqToMHz(2.4, CableFreqUnit.ghz), closeTo(2400, 1e-9));
      expect(CableLossScreen.freqToMHz(900, CableFreqUnit.mhz), closeTo(900, 1e-9));
    });

    test('metres convert to feet at 3.28084 ft/m', () {
      expect(CableLossScreen.lengthToFeet(10, CableLengthUnit.m), closeTo(32.8084, 1e-9));
      expect(CableLossScreen.lengthToFeet(25, CableLengthUnit.ft), closeTo(25, 1e-9));
    });

    test('LMR-400 at 2.4 GHz over 25 ft is 0.975 dB', () {
      final double per100 =
          CableLossScreen.cableLossPer100ft('LMR-400', 2400)!;
      final double lenFt = CableLossScreen.lengthToFeet(25, CableLengthUnit.ft);
      expect(CableLossScreen.totalLossDb(per100, lenFt), closeTo(0.975, 1e-9));
    });

    test('LMR-400 at 2.4 GHz over 10 m equals the ft-converted run', () {
      final double per100 =
          CableLossScreen.cableLossPer100ft('LMR-400', 2400)!;
      final double lenFt = CableLossScreen.lengthToFeet(10, CableLengthUnit.m);
      expect(CableLossScreen.totalLossDb(per100, lenFt), closeTo(1.2795276, 1e-7));
    });

    test('CABLE_DATA list mirrors the PWA select order and default', () {
      expect(CableLossScreen.cableTypes.first, 'LMR-100A');
      expect(CableLossScreen.cableTypes.last, 'RG-214');
      expect(CableLossScreen.cableTypes.length, 10);
      expect(CableLossScreen.defaultCable, 'LMR-400');
    });
  });

  group('CableLossScreen widget', () {
    testWidgets('renders title, input labels, and result unit', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const CableLossScreen(),
        ),
      );

      expect(find.text('Cable Loss'), findsWidgets);
      expect(find.text('Cable type'), findsOneWidget);
      expect(find.text('Frequency'), findsOneWidget);
      expect(find.text('Cable length'), findsOneWidget);
      expect(find.text('Total cable loss'), findsOneWidget);
      // Two text inputs: frequency and length.
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('typing valid inputs renders a finite dB result',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const CableLossScreen(),
        ),
      );

      final Finder fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '2.4'); // GHz default
      await tester.enterText(fields.at(1), '25'); // ft default, LMR-400 default
      await tester.pump();

      // LMR-400 at 2.4 GHz over 25 ft → 0.975 dB; IEEE-754 toStringAsFixed(2)
      // renders 0.97 (the stored double is just under 0.975). PWA fmt(x, 2)
      // uses JS toFixed, which rounds the same stored value identically.
      expect(find.text('0.97'), findsOneWidget);
      // Per-100ft coefficient at 2.4 GHz for LMR-400 is 3.90 dB.
      expect(find.text('3.90'), findsOneWidget);
    });

    testWidgets('clearing an input blanks the result to an em-free dash',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const CableLossScreen(),
        ),
      );

      final Finder fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '2.4');
      await tester.enterText(fields.at(1), '25');
      await tester.pump();
      expect(find.text('0.97'), findsOneWidget);

      // Clear the length field → output blanks (no crash, shows the dash).
      await tester.enterText(fields.at(1), '');
      await tester.pump();
      expect(find.text('0.98'), findsNothing);
      // Both total and per-100ft blank to the dash.
      expect(find.text('—'), findsNWidgets(2));
    });
  });
}
