// Tests for the Noise Floor calculator.
//
// The math is verified against the RF Tools PWA reference (app.js calcNoise):
//   T(K)    = tempC + 273.15
//   bwHz    = bw_MHz × 1e6
//   thermal = 10·log10(k · T · bwHz) + 30      (k = 1.380649e-23 J/K)
//   rxFloor = thermal + nfDb
//   rule    = -174 + 10·log10(bwHz)
// Expected values below were computed from that exact formula so the native app
// and PWA agree to the decimal.
//
// One widget test confirms the screen pumps and renders in a phone viewport.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/noise_floor_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Noise floor math (pure) — matches PWA app.js calcNoise', () {
    test('20 MHz thermal floor at 20°C is about -101 dBm (NF 0)', () {
      // kTB only, no noise figure: the canonical 20 MHz thermal floor.
      expect(
        NoiseFloorScreen.thermalDbm(20, 20),
        closeTo(-100.91796823136968, 1e-9),
      );
      // At NF 0 the receiver floor equals the thermal floor.
      expect(
        NoiseFloorScreen.rxFloorDbm(20, 20, 0),
        closeTo(NoiseFloorScreen.thermalDbm(20, 20), 1e-12),
      );
    });

    test('20 MHz thermal floor at 25°C', () {
      expect(
        NoiseFloorScreen.thermalDbm(20, 25),
        closeTo(-100.84451907976026, 1e-9),
      );
    });

    test('Rx noise floor adds the noise figure on top of thermal', () {
      final double thermal = NoiseFloorScreen.thermalDbm(20, 20);
      expect(
        NoiseFloorScreen.rxFloorDbm(20, 20, 7),
        closeTo(thermal + 7, 1e-12),
      );
      expect(
        NoiseFloorScreen.rxFloorDbm(20, 20, 7),
        closeTo(-93.91796823136968, 1e-9),
      );
    });

    test('doubling bandwidth raises the thermal floor by ~3.01 dB', () {
      final double bw20 = NoiseFloorScreen.thermalDbm(20, 20);
      final double bw40 = NoiseFloorScreen.thermalDbm(40, 20);
      expect(bw40 - bw20, closeTo(3.010299956639813, 1e-9));
    });

    test('160 MHz thermal floor at 20°C', () {
      expect(
        NoiseFloorScreen.thermalDbm(160, 20),
        closeTo(-91.88706836145025, 1e-9),
      );
    });

    test('rule of thumb uses -174 dBm/Hz independent of temperature', () {
      expect(
        NoiseFloorScreen.ruleOfThumbDbm(20),
        closeTo(-100.98970004336019, 1e-9),
      );
      expect(
        NoiseFloorScreen.ruleOfThumbDbm(320),
        closeTo(-88.94850021680094, 1e-9),
      );
    });
  });

  group('NoiseFloorScreen widget', () {
    testWidgets('renders title, input labels, and result rows', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const NoiseFloorScreen(),
        ),
      );
      await tester.pump();

      expect(find.text('Noise Floor'), findsWidgets);
      expect(find.text('Channel bandwidth'), findsOneWidget);
      expect(find.text('Receiver noise figure'), findsOneWidget);
      expect(find.text('Temperature'), findsOneWidget);
      expect(find.text('Thermal noise (kTB)'), findsOneWidget);
      expect(find.text('Rx noise floor'), findsOneWidget);
      expect(find.text('Rule of thumb'), findsOneWidget);
    });

    testWidgets('defaults (20 MHz, NF 7, 20°C) render the expected floors',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const NoiseFloorScreen(),
        ),
      );
      await tester.pump();

      // Thermal -100.9, Rx floor -93.9 at the prefilled defaults.
      expect(find.text('-100.9'), findsOneWidget);
      expect(find.text('-93.9'), findsOneWidget);
    });

    testWidgets('clearing the noise figure blanks the outputs to a dash',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const NoiseFloorScreen(),
        ),
      );
      await tester.pump();

      final Finder fields = find.byType(TextField);
      // First TextField is the noise figure (bandwidth is an AppSelect).
      await tester.enterText(fields.at(0), '');
      await tester.pump();

      // All three outputs blank to the em-free dash; none render a number.
      expect(find.text('-100.9'), findsNothing);
      expect(find.text('—'), findsNWidgets(3));
    });
  });
}
