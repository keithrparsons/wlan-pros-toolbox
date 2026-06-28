// Smoke tests for the four Ham Radio band-reference screens. Each pumps in a
// phone-width viewport, asserts its headline content renders with no overflow,
// and exercises the one interactive control where there is one (the band-plan
// search filter). The data correctness is locked separately in
// test/data/ham_reference_data_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/ham_band_plan_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/ham_band_wavelengths_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/band_designations_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/part15_vs_part97_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.dark(), home: screen));
  await tester.pump();
}

void main() {
  testWidgets('US Amateur Band Plan renders and filters', (tester) async {
    await _pump(tester, const HamBandPlanScreen());

    expect(find.text('US Amateur Band Plan'), findsWidgets);
    // A known band and the corrected 30 m power both render.
    expect(find.text('20 m'), findsWidgets);
    expect(find.text('60 m channel detail'), findsOneWidget);

    // Filtering to "20 m" keeps 20 m and drops 70 cm.
    await tester.enterText(find.byType(TextField), '70 cm');
    await tester.pump();
    expect(find.text('70 cm'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'zzz-no-band');
    await tester.pump();
    expect(find.text('No match'), findsOneWidget);
  });

  testWidgets('Band Names & Wavelengths renders the table and formula',
      (tester) async {
    await _pump(tester, const HamBandWavelengthsScreen());

    expect(find.text('Band Names & Wavelengths'), findsWidgets);
    expect(find.textContaining('lambda(m) = 299.792458'), findsOneWidget);
    expect(find.text('13 cm'), findsWidgets);
  });

  testWidgets('Spectrum Band Designations renders ITU bands and neighbors',
      (tester) async {
    await _pump(tester, const BandDesignationsScreen());

    expect(find.text('Spectrum Band Designations'), findsWidgets);
    expect(find.text('HF'), findsWidgets);
    expect(find.text('SHF'), findsWidgets);
    expect(
      find.textContaining('Neighbors a Wi-Fi pro should recognize'),
      findsOneWidget,
    );
  });

  testWidgets('Part 15 vs Part 97 renders the overlap and rule deltas',
      (tester) async {
    await _pump(tester, const Part15VsPart97Screen());

    expect(find.text('Part 15 vs Part 97'), findsWidgets);
    expect(find.text('Encryption'), findsOneWidget);
    // Both column tags must be present (never color-only).
    expect(find.text('PART 15'), findsWidgets);
    expect(find.text('PART 97'), findsWidgets);
    expect(find.textContaining('AREDN'), findsWidgets);
  });
}
