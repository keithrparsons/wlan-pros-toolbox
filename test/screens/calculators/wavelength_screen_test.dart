// Tests for the Wavelength calculator.
//
// The math is verified against the RF Tools PWA reference (app.js
// calcWavelength):
//   lambda_m  = 300 / f_MHz
//   lambda_cm = lambda_m * 100
//   lambda_ft = lambda_m * 3.28084
//   lambda_in = lambda_ft * 12
// with the PWA unit conversion toMHz (GHz ×1000). Expected values below were
// computed from that exact formula so the native app and PWA agree.
//
// One widget test confirms the screen pumps and renders its cards.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wavelength_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Wavelength math (pure) — matches PWA app.js calcWavelength', () {
    test('2.4 GHz (2400 MHz) is 0.125 m exactly', () {
      expect(WavelengthScreen.wavelengthMeters(2400), closeTo(0.125, 1e-12));
    });

    test('5 GHz (5000 MHz) is 0.06 m', () {
      expect(WavelengthScreen.wavelengthMeters(5000), closeTo(0.06, 1e-12));
    });

    test('6 GHz (6000 MHz) is 0.05 m', () {
      expect(WavelengthScreen.wavelengthMeters(6000), closeTo(0.05, 1e-12));
    });

    test('300 MHz is 1 m exactly (the constant anchor)', () {
      expect(WavelengthScreen.wavelengthMeters(300), closeTo(1.0, 1e-12));
    });

    test('cm, ft, and in derive from metres', () {
      expect(WavelengthScreen.wavelengthCm(2400), closeTo(12.5, 1e-9));
      expect(WavelengthScreen.wavelengthFeet(2400), closeTo(0.410105, 1e-6));
      expect(WavelengthScreen.wavelengthInches(2400), closeTo(4.92126, 1e-5));
    });
  });

  group('Unit normalization — matches PWA toMHz', () {
    test('GHz multiplies by 1000 to MHz', () {
      expect(WavelengthScreen.freqToMHz(2.4, WlFreqUnit.ghz), closeTo(2400, 1e-9));
      expect(WavelengthScreen.freqToMHz(2400, WlFreqUnit.mhz), 2400);
    });

    test('2.4 GHz and 2400 MHz yield the same wavelength', () {
      final double fromGHz = WavelengthScreen.wavelengthMeters(
        WavelengthScreen.freqToMHz(2.4, WlFreqUnit.ghz),
      );
      final double fromMHz = WavelengthScreen.wavelengthMeters(
        WavelengthScreen.freqToMHz(2400, WlFreqUnit.mhz),
      );
      expect(fromGHz, closeTo(fromMHz, 1e-12));
    });
  });

  group('WavelengthScreen widget', () {
    testWidgets('renders title, input label, and result units', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const WavelengthScreen(),
        ),
      );

      expect(find.text('Wavelength'), findsWidgets);
      expect(find.text('Frequency'), findsOneWidget);
      expect(find.text('m'), findsWidgets);
      expect(find.text('cm'), findsOneWidget);
      // One frequency input field.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('typing a valid frequency renders finite results',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const WavelengthScreen(),
        ),
      );

      // MHz is the default unit; 2400 MHz → 0.1250 m at 4-decimal formatting.
      await tester.enterText(find.byType(TextField), '2400');
      await tester.pump();
      expect(find.text('0.1250'), findsOneWidget);
      expect(find.text('12.50'), findsOneWidget);
    });

    testWidgets('clearing the input blanks results to an em-free dash',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const WavelengthScreen(),
        ),
      );

      await tester.enterText(find.byType(TextField), '2400');
      await tester.pump();
      expect(find.text('0.1250'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.text('0.1250'), findsNothing);
      // Four outputs all blank to the dash.
      expect(find.text('—'), findsNWidgets(4));
    });
  });
}
