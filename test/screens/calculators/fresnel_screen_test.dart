// Tests for the Fresnel Zone calculator.
//
// Math tests pin the pure functions to known values and to the RF Tools PWA
// reference (app.js calcFresnel): lambda = 0.3 / f_GHz, r = sqrt(lambda * d1 *
// d2 / (d1 + d2)), clearance = 0.6 * r. Native and PWA must agree to the
// decimal for the same physical input.
//
// Widget test confirms FresnelScreen pumps and renders. Follows the style in
// test/screens/labeled_field_test.dart.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fresnel_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Fresnel math (pure)', () {
    test('wavelength is 0.3 / f(GHz), matching the PWA', () {
      expect(FresnelScreen.wavelengthMeters(2.4), closeTo(0.125, 1e-9));
      expect(FresnelScreen.wavelengthMeters(5.0), closeTo(0.06, 1e-9));
      expect(FresnelScreen.wavelengthMeters(6.0), closeTo(0.05, 1e-9));
    });

    test('first-zone radius matches the closed form r = sqrt(λ·d1·d2/(d1+d2))',
        () {
      // 5 GHz, point 250 m from TX on a 1000 m path: d1=250, d2=750.
      const double freq = 5.0;
      const double d1 = 250.0;
      const double d2 = 750.0;
      final double lambda = 0.3 / freq;
      final double expected = math.sqrt(lambda * d1 * d2 / (d1 + d2));
      expect(
        FresnelScreen.firstZoneRadius(freqGHz: freq, d1Meters: d1, d2Meters: d2),
        closeTo(expected, 1e-9),
      );
    });

    test('midpoint radius over 1 km matches PWA fmt(_,1) anchor values', () {
      // These are the exact 1-decimal values the PWA renders for a 1 km path.
      FresnelResult mid(double f) =>
          FresnelScreen.compute(freqGHz: f, totalMeters: 1000.0)!;

      expect(mid(2.4).radiusMid, closeTo(5.59, 0.01));
      expect(mid(5.0).radiusMid, closeTo(3.87, 0.01));
      expect(mid(6.0).radiusMid, closeTo(3.54, 0.01));

      // Rounded to 1 decimal as the UI / PWA display them.
      expect(mid(2.4).radiusMid.toStringAsFixed(1), '5.6');
      expect(mid(5.0).radiusMid.toStringAsFixed(1), '3.9');
      expect(mid(6.0).radiusMid.toStringAsFixed(1), '3.5');
    });

    test('60% clearance is 0.6 × the radius', () {
      final FresnelResult r =
          FresnelScreen.compute(freqGHz: 5.8, totalMeters: 10000.0)!;
      expect(r.clearanceMid, closeTo(r.radiusMid * 0.6, 1e-12));
    });

    test('midpoint radius equals sqrt(λ · D / 4)', () {
      const double freq = 5.8;
      const double total = 10000.0;
      final double lambda = 0.3 / freq;
      final double expected = math.sqrt(lambda * total / 4);
      final FresnelResult r =
          FresnelScreen.compute(freqGHz: freq, totalMeters: total)!;
      expect(r.radiusMid, closeTo(expected, 1e-9));
    });

    test('at-point radius is asymmetric and below the midpoint maximum', () {
      final FresnelResult r = FresnelScreen.compute(
        freqGHz: 5.8,
        totalMeters: 10000.0,
        pointFromTxMeters: 1000.0,
      )!;
      expect(r.radiusAtPoint, isNotNull);
      // A point off-center always yields a smaller first-zone radius than the
      // midpoint maximum.
      expect(r.radiusAtPoint! < r.radiusMid, isTrue);
      expect(r.clearanceAtPoint, closeTo(r.radiusAtPoint! * 0.6, 1e-12));
    });

    test('null / non-positive inputs return null (PWA refuses to compute)', () {
      expect(FresnelScreen.compute(freqGHz: null, totalMeters: 1000), isNull);
      expect(FresnelScreen.compute(freqGHz: 5.0, totalMeters: null), isNull);
      expect(FresnelScreen.compute(freqGHz: 0, totalMeters: 1000), isNull);
      expect(FresnelScreen.compute(freqGHz: 5.0, totalMeters: 0), isNull);
      expect(
        FresnelScreen.compute(freqGHz: -1, totalMeters: 1000),
        isNull,
      );
    });

    test('point outside (0, D) is ignored; midpoint result still returned', () {
      // Point beyond the far end -> no at-point result, midpoint still valid.
      final FresnelResult r = FresnelScreen.compute(
        freqGHz: 5.0,
        totalMeters: 1000.0,
        pointFromTxMeters: 2000.0,
      )!;
      expect(r.radiusAtPoint, isNull);
      expect(r.clearanceAtPoint, isNull);
      expect(r.radiusMid, greaterThan(0));
    });
  });

  group('FresnelScreen widget', () {
    testWidgets('renders the app bar, inputs, and formula', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const FresnelScreen(),
        ),
      );

      expect(find.text('Fresnel Zone'), findsOneWidget);
      expect(find.text('Frequency'), findsOneWidget);
      expect(find.text('Total path distance'), findsOneWidget);
      expect(find.text('Point from TX'), findsOneWidget);
      expect(find.text('First zone radius'), findsWidgets);
    });

    testWidgets('live recompute renders a result for valid input',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const FresnelScreen(),
        ),
      );

      await tester.enterText(find.byType(TextField).at(0), '5.8');
      await tester.enterText(find.byType(TextField).at(1), '10000');
      await tester.pump();

      // sqrt((0.3/5.8) * 10000 / 4) ≈ 11.37 m -> "11.4 m" at 1 decimal.
      expect(find.text('11.4 m'), findsOneWidget);
    });

    testWidgets('invalid input blanks the output without crashing',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const FresnelScreen(),
        ),
      );

      await tester.enterText(find.byType(TextField).at(0), '5.8');
      await tester.enterText(find.byType(TextField).at(1), '');
      await tester.pump();

      expect(find.text('— m'), findsWidgets);
    });
  });
}
