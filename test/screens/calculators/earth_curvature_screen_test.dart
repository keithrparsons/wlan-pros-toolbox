// Tests for the Earth Curvature Bulge calculator.
//
// The math is verified against the RF Tools PWA reference (app.js calcEarth):
//   Re_eff(km) = 6371 · k
//   bulge(m)   = (d_km² · 1000) / (8 · Re_eff)
//   bulge(ft)  = bulge(m) · 3.28084
// with the PWA unit conversion toKm (mi ×1.60934). Expected values below were
// computed from that exact formula so the native app and PWA agree.
//
// One widget test confirms the screen pumps and renders its cards.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/earth_curvature_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Earth curvature math (pure) — matches PWA app.js calcEarth', () {
    test('20 km at k = 4/3 standard', () {
      expect(
        EarthCurvatureScreen.bulgeMeters(20, KFactor.fourThirds.value),
        closeTo(5.887518026108316, 1e-9),
      );
    });

    test('10 km at k = 4/3 standard', () {
      expect(
        EarthCurvatureScreen.bulgeMeters(10, KFactor.fourThirds.value),
        closeTo(1.471879506527079, 1e-9),
      );
    });

    test('geometric k = 1.0 bulges more than 4/3 refraction', () {
      final double geometric =
          EarthCurvatureScreen.bulgeMeters(20, KFactor.geometric.value);
      final double standard =
          EarthCurvatureScreen.bulgeMeters(20, KFactor.fourThirds.value);
      expect(geometric, closeTo(7.848061528802385, 1e-9));
      expect(geometric, greaterThan(standard));
    });

    test('bulge scales with the square of distance', () {
      final double atTen =
          EarthCurvatureScreen.bulgeMeters(10, KFactor.fourThirds.value);
      final double atTwenty =
          EarthCurvatureScreen.bulgeMeters(20, KFactor.fourThirds.value);
      // Double the path → 4x the bulge.
      expect(atTwenty / atTen, closeTo(4.0, 1e-9));
    });

    test('meters-to-feet uses the PWA 3.28084 factor', () {
      final double m =
          EarthCurvatureScreen.bulgeMeters(20, KFactor.fourThirds.value);
      expect(
        EarthCurvatureScreen.metersToFeet(m),
        closeTo(19.31600464077721, 1e-9),
      );
    });
  });

  group('Unit normalization — matches PWA toKm', () {
    test('miles convert to km', () {
      expect(EarthCurvatureScreen.pathToKm(1, PathUnit.mi),
          closeTo(1.60934, 1e-12));
      expect(EarthCurvatureScreen.pathToKm(20, PathUnit.km), 20);
    });

    test('5 mi at k = 4/3 matches the converted km path', () {
      final double km = EarthCurvatureScreen.pathToKm(5, PathUnit.mi);
      expect(
        EarthCurvatureScreen.bulgeMeters(km, KFactor.fourThirds.value),
        closeTo(0.953032867923071, 1e-9),
      );
    });
  });

  group('KFactor presets mirror the PWA ec-kfactor select', () {
    test('values match the PWA option set', () {
      expect(KFactor.fourThirds.value, 1.333);
      expect(KFactor.geometric.value, 1.0);
      expect(KFactor.twoThirds.value, 0.667);
      expect(KFactor.superrefraction.value, 2.0);
    });
  });

  group('EarthCurvatureScreen widget', () {
    testWidgets('renders title, input label, and result units', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const EarthCurvatureScreen(),
        ),
      );

      expect(find.text('Earth Curvature'), findsWidgets);
      expect(find.text('Path Length'), findsOneWidget);
      expect(find.text('Earth bulge at midpoint'), findsOneWidget);
      // One text input: path length.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('typing a valid path renders finite m and ft results',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const EarthCurvatureScreen(),
        ),
      );

      await tester.enterText(find.byType(TextField), '20'); // km, k = 4/3
      await tester.pump();

      // 20 km at k = 4/3 → 5.89 m / 19.32 ft at 2-decimal PWA formatting.
      expect(find.text('5.89'), findsOneWidget);
      expect(find.text('19.32'), findsOneWidget);
    });

    testWidgets('clearing the path blanks the result to an em-free dash',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const EarthCurvatureScreen(),
        ),
      );

      await tester.enterText(find.byType(TextField), '20');
      await tester.pump();
      expect(find.text('5.89'), findsOneWidget);

      // Clear the field → both outputs blank to the dash (no crash).
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.text('5.89'), findsNothing);
      expect(find.text('—'), findsNWidgets(2));
    });
  });
}
