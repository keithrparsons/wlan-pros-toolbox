// Tests for the EIRP calculator.
//
// Two layers:
//   1. Pure-math tests against hand-checked values, asserting the native math
//      matches the RF Tools PWA calcEIRP() to the decimal (dBm + W/mW unit
//      handling, and the empty/invalid → null contract).
//   2. A widget smoke test that pumps EirpScreen and confirms it renders the
//      input labels, formula, and the empty-state "—" result.
//
// Follows the style of test/screens/labeled_field_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eirp_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('EIRP math (pure)', () {
    test('dBm input: TX − loss + gain in the log domain', () {
      // PWA placeholders: 20 dBm − 1.5 dB + 14 dBi = 32.5 dBm.
      final double? eirp = EirpScreen.eirpDbm(
        power: 20,
        unit: EirpPowerUnit.dBm,
        lossDb: 1.5,
        gainDbi: 14,
      );
      expect(eirp, isNotNull);
      expect(eirp!, closeTo(32.5, 1e-9));
    });

    test('zero loss and gain returns the TX power unchanged', () {
      final double? eirp = EirpScreen.eirpDbm(
        power: 23,
        unit: EirpPowerUnit.dBm,
        lossDb: 0,
        gainDbi: 0,
      );
      expect(eirp!, closeTo(23.0, 1e-9));
    });

    test('W input converts to dBm before the dB arithmetic', () {
      // 1 W = 30 dBm; with no loss/gain the EIRP is 30 dBm.
      final double? eirp = EirpScreen.eirpDbm(
        power: 1,
        unit: EirpPowerUnit.w,
        lossDb: 0,
        gainDbi: 0,
      );
      expect(eirp!, closeTo(30.0, 1e-9));
    });

    test('mW input converts to dBm before the dB arithmetic', () {
      // 100 mW = 20 dBm; +6 dBi, −1 dB → 25 dBm.
      final double? eirp = EirpScreen.eirpDbm(
        power: 100,
        unit: EirpPowerUnit.mW,
        lossDb: 1,
        gainDbi: 6,
      );
      expect(eirp!, closeTo(25.0, 1e-9));
    });

    test('negative TX power and gain are valid (handheld / low-gain antennas)',
        () {
      // −10 dBm − 0 dB + 2 dBi = −8 dBm.
      final double? eirp = EirpScreen.eirpDbm(
        power: -10,
        unit: EirpPowerUnit.dBm,
        lossDb: 0,
        gainDbi: 2,
      );
      expect(eirp!, closeTo(-8.0, 1e-9));
    });

    test('W <= 0 yields a non-finite log and returns null', () {
      // wattsTodBm(0) = 10*log10(0) = -inf → not finite → null.
      final double? eirp = EirpScreen.eirpDbm(
        power: 0,
        unit: EirpPowerUnit.w,
        lossDb: 0,
        gainDbi: 0,
      );
      expect(eirp, isNull);
    });

    test('eirpWatts mirrors the PWA dBmToWatts conversion', () {
      // 30 dBm = 1 W exactly.
      expect(EirpScreen.eirpWatts(30), closeTo(1.0, 1e-9));
      // 32.5 dBm ≈ 1.7783 W.
      expect(EirpScreen.eirpWatts(32.5), closeTo(1.7782794, 1e-6));
      // 0 dBm = 0.001 W (1 mW).
      expect(EirpScreen.eirpWatts(0), closeTo(0.001, 1e-12));
    });
  });

  group('EirpScreen widget', () {
    testWidgets('renders inputs, formula, and the empty-state result',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const EirpScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // App bar title.
      expect(find.text('EIRP'), findsWidgets);

      // Input labels.
      expect(find.text('TX Power'), findsOneWidget);
      expect(find.text('Cable Loss'), findsOneWidget);
      expect(find.text('Antenna Gain'), findsOneWidget);

      // Formula card.
      expect(
        find.text('EIRP = TX power − cable loss + antenna gain'),
        findsOneWidget,
      );

      // Empty state: the dBm result shows the em-dash placeholder, not a value.
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('typing valid inputs produces a finite dBm result',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const EirpScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final Finder fields = find.byType(TextField);
      // Order: TX power, cable loss, antenna gain.
      await tester.enterText(fields.at(0), '20');
      await tester.enterText(fields.at(1), '1.5');
      await tester.enterText(fields.at(2), '14');
      await tester.pumpAndSettle();

      // 20 − 1.5 + 14 = 32.5 dBm, formatted at 1 decimal.
      expect(find.text('32.5'), findsOneWidget);
    });
  });
}
