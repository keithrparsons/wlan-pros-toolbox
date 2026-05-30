// Tests for the FSPL calculator.
//
// The math is verified against the RF Tools PWA reference (app.js calcFSPL):
//   loss = 20·log10(f_GHz) + 20·log10(d_km) + 92.45
// with the PWA unit conversions toGHz (MHz ÷1000) and toKm (mi ×1.60934,
// m ÷1000). Expected values below were computed from that exact formula so the
// native app and PWA agree to the decimal.
//
// One widget test confirms the screen pumps and renders its cards.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('FSPL math (pure) — matches PWA app.js calcFSPL', () {
    test('1 GHz at 1 km equals the 92.45 anchor exactly', () {
      // log10(1) = 0 on both terms, so the constant stands alone.
      expect(FsplScreen.fsplDb(1, 1), closeTo(92.45, 1e-9));
    });

    test('2.4 GHz at 1 km', () {
      expect(FsplScreen.fsplDb(2.4, 1), closeTo(100.05422483423212, 1e-9));
    });

    test('5 GHz at 1 km', () {
      expect(FsplScreen.fsplDb(5, 1), closeTo(106.42940008672038, 1e-9));
    });

    test('distance below 1 km drops the loss (100 m vs 1 km is -20 dB)', () {
      final double atKm = FsplScreen.fsplDb(2.4, 1);
      final double at100m = FsplScreen.fsplDb(2.4, 0.1);
      expect(at100m, closeTo(80.05422483423212, 1e-9));
      expect(atKm - at100m, closeTo(20.0, 1e-9));
    });
  });

  group('Unit normalization — matches PWA toGHz / toKm', () {
    test('MHz divides by 1000 to GHz', () {
      expect(FsplScreen.freqToGHz(2400, FreqUnit.mhz), closeTo(2.4, 1e-12));
      expect(FsplScreen.freqToGHz(5, FreqUnit.ghz), 5);
    });

    test('miles and meters convert to km', () {
      expect(FsplScreen.distToKm(1, DistUnit.mi), closeTo(1.60934, 1e-12));
      expect(FsplScreen.distToKm(100, DistUnit.m), closeTo(0.1, 1e-12));
      expect(FsplScreen.distToKm(1, DistUnit.km), 1);
    });

    test('2400 MHz at 1 km equals 2.4 GHz at 1 km', () {
      final double mhz = FsplScreen.fsplDb(
        FsplScreen.freqToGHz(2400, FreqUnit.mhz),
        FsplScreen.distToKm(1, DistUnit.km),
      );
      final double ghz = FsplScreen.fsplDb(
        FsplScreen.freqToGHz(2.4, FreqUnit.ghz),
        FsplScreen.distToKm(1, DistUnit.km),
      );
      expect(mhz, closeTo(ghz, 1e-9));
    });

    test('5 GHz at 1 mile', () {
      final double loss = FsplScreen.fsplDb(
        FsplScreen.freqToGHz(5, FreqUnit.ghz),
        FsplScreen.distToKm(1, DistUnit.mi),
      );
      expect(loss, closeTo(110.56235620207465, 1e-9));
    });
  });

  group('FsplScreen widget', () {
    testWidgets('renders title, input labels, and result unit', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const FsplScreen(),
        ),
      );

      expect(find.text('FSPL'), findsWidgets);
      expect(find.text('Frequency'), findsOneWidget);
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Free space path loss'), findsOneWidget);
      // Two text inputs: frequency and distance.
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('typing valid inputs renders a finite dB result', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const FsplScreen(),
        ),
      );

      final Finder fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '2.4'); // GHz default
      await tester.enterText(fields.at(1), '1'); // km default
      await tester.pump();

      // 2.4 GHz at 1 km → 100.1 dB at 1-decimal PWA formatting.
      expect(find.text('100.1'), findsOneWidget);
    });

    testWidgets('clearing an input blanks the result to an em-free dash',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const FsplScreen(),
        ),
      );

      final Finder fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '5');
      await tester.enterText(fields.at(1), '1');
      await tester.pump();
      expect(find.text('106.4'), findsOneWidget);

      // Clear the distance field → output blanks (no crash, shows the dash).
      await tester.enterText(fields.at(1), '');
      await tester.pump();
      expect(find.text('106.4'), findsNothing);
      expect(find.text('—'), findsOneWidget);
    });
  });
}
