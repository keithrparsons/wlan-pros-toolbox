// Tests for the Antenna Length calculator.
//
// Verified against the spec's worked sanity checks, all with the EXACT
// c = 299.792458 (MHz*m form):
//   14.2 MHz  -> lambda ~ 21.11 m; half-wave dipole ~ 33 ft (VF 0.95) and 468/f
//   146 MHz   -> quarter-wave vertical ~ 19-20 in
//   2400 MHz  -> quarter-wave vertical ~ 3 cm
// Plus the frequency<->wavelength inverse round-trip.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_length_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Antenna Length math (pure) — exact c = 299.792458', () {
    test('14.2 MHz wavelength is ~21.11 m', () {
      expect(AntennaLengthScreen.wavelengthMeters(14.2),
          closeTo(21.1121, 1e-3));
    });

    test('frequency <-> wavelength inverse round-trips', () {
      final double lambda = AntennaLengthScreen.wavelengthMeters(14.2);
      expect(AntennaLengthScreen.frequencyMHz(lambda), closeTo(14.2, 1e-9));
      // 21.1 m -> ~14.2 MHz (spec anchor).
      expect(AntennaLengthScreen.frequencyMHz(21.1), closeTo(14.21, 1e-2));
    });

    test('14.2 MHz half-wave dipole is ~33 ft (VF 0.95) and the 468 rule agrees',
        () {
      final double lambda = AntennaLengthScreen.wavelengthMeters(14.2);
      final double m = AntennaLengthScreen.halfWaveDipoleMeters(lambda, 0.95);
      expect(AntennaLengthScreen.metersToFeet(m), closeTo(32.9, 0.3));
      expect(AntennaLengthScreen.dipoleRuleOfThumbFeet(14.2),
          closeTo(32.96, 0.05));
      // the two figures are within a few inches of each other
      expect(
        (AntennaLengthScreen.metersToFeet(m) -
                AntennaLengthScreen.dipoleRuleOfThumbFeet(14.2))
            .abs(),
        lessThan(0.3),
      );
    });

    test('146 MHz quarter-wave vertical is ~19-20 inches', () {
      final double lambda = AntennaLengthScreen.wavelengthMeters(146);
      final double m = AntennaLengthScreen.quarterWaveMeters(lambda, 0.95);
      final double inches = AntennaLengthScreen.metersToInches(m);
      expect(inches, greaterThan(19.0));
      expect(inches, lessThan(20.0));
      // 234/f rule, converted to inches, lands in the same window.
      final double ruleIn =
          AntennaLengthScreen.quarterRuleOfThumbFeet(146) * 12.0;
      expect(ruleIn, greaterThan(19.0));
      expect(ruleIn, lessThan(20.0));
    });

    test('2400 MHz quarter-wave vertical is ~3 cm', () {
      final double lambda = AntennaLengthScreen.wavelengthMeters(2400);
      final double m = AntennaLengthScreen.quarterWaveMeters(lambda, 0.95);
      // ~0.0297 m = ~2.97 cm, i.e. about 3 cm.
      expect(m * 100.0, closeTo(3.0, 0.2));
    });

    test('rule-of-thumb constants are 468 and 234', () {
      expect(AntennaLengthScreen.dipoleRuleOfThumbFeet(1.0), 468.0);
      expect(AntennaLengthScreen.quarterRuleOfThumbFeet(1.0), 234.0);
    });

    test('GHz-scale frequency still resolves (2.4 GHz path)', () {
      // 2400 MHz wavelength ~ 0.12491 m.
      expect(AntennaLengthScreen.wavelengthMeters(2400),
          closeTo(0.12491, 1e-4));
    });
  });

  group('AntennaLengthScreen widget', () {
    testWidgets('renders title and the empty prompt before input',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const AntennaLengthScreen(),
        ),
      );
      expect(find.text('Antenna Length'), findsWidgets);
      // Frequency field + VF field both present in the default frequency mode.
      expect(find.byType(TextField), findsNWidgets(2));
      // No antenna cards until a frequency is entered.
      expect(find.text('Half-wave dipole'), findsNothing);
    });

    testWidgets('entering a frequency renders the antenna cards',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const AntennaLengthScreen(),
        ),
      );
      // First TextField is the frequency input (VF is the second).
      await tester.enterText(find.byType(TextField).first, '14.2');
      await tester.pump();
      expect(find.text('Half-wave dipole'), findsOneWidget);
      expect(find.text('Quarter-wave vertical'), findsOneWidget);
      expect(find.textContaining('Full wavelength'), findsOneWidget);
    });
  });
}
