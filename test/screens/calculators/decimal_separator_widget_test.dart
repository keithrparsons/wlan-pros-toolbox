// Widget smoke tests for the EU decimal-separator fix, driven through a real
// calculator screen so both the input formatter (comma no longer stripped as a
// dead key) and the parse path (`tryParseFlexibleDouble`) are exercised end to
// end. `enterText` runs the field's inputFormatters before setting the value,
// so a stripped comma would surface here.
//
// The Antenna Length screen is representative: an unsigned-decimal frequency
// field and a velocity-factor field, with a deterministic rendered result
// (full wavelength to 4 dp) that distinguishes 14,2 (→ 14.2 MHz → 21.1121 m)
// from a mis-parse to 142 MHz (→ 2.1112 m).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_length_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('EU decimal separator — Antenna Length', () {
    testWidgets('comma frequency 14,2 is accepted and parses as 14.2 MHz',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const AntennaLengthScreen(),
        ),
      );

      final Finder freqField = find.byType(TextField).first;
      await tester.enterText(freqField, '14,2');
      await tester.pump();

      // Formatter kept the comma (did not strip it to a dead key / to '142').
      expect(
        (tester.widget<TextField>(freqField)).controller!.text,
        '14,2',
      );

      // Result computed correctly: 14.2 MHz → full wavelength 21.1121 m.
      // A mis-parse to 142 MHz would render 2.1112 m instead.
      expect(find.text('21.1121'), findsWidgets);
      expect(find.text('Half-wave dipole'), findsOneWidget);
    });

    testWidgets('comma velocity factor 0,5 parses (not rejected)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const AntennaLengthScreen(),
        ),
      );

      // Frequency in period form so only the VF field carries the comma.
      await tester.enterText(find.byType(TextField).first, '2400');
      // Second field is the velocity factor.
      await tester.enterText(find.byType(TextField).at(1), '0,5');
      await tester.pump();

      // VF 0,5 parsed to 0.5 → the physical-length label reflects VF 0.500.
      // If the comma had been rejected the field would fall to its invalid
      // state and this label would not render.
      expect(find.textContaining('VF 0.500'), findsWidgets);
    });
  });
}
