// Tests for the Distance and Bearing calculator.
//
// The math is verified against the RF Tools PWA reference (app.js
// calcDistBearing / haversineKm / bearingDeg) with EARTH_KM = 6371. Expected
// values below were computed from that exact formula so the native app and PWA
// agree to the decimal.
//
// One widget test confirms the screen pumps and renders its cards inside a
// phone-sized viewport (no RenderFlex overflow).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dist_bearing_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  // Reference pair: New York City → Los Angeles in decimal degrees.
  const double nycLat = 40.7128, nycLon = -74.0060;
  const double laLat = 34.0522, laLon = -118.2437;

  group('Haversine distance (pure) — matches PWA haversineKm, R=6371', () {
    test('earth radius constant matches the PWA', () {
      expect(DistBearingScreen.earthKm, 6371);
    });

    test('identical points are zero distance', () {
      expect(
        DistBearingScreen.haversineKm(nycLat, nycLon, nycLat, nycLon),
        closeTo(0, 1e-9),
      );
    });

    test('one degree of longitude at the equator is ~111.19 km', () {
      expect(
        DistBearingScreen.haversineKm(0, 0, 0, 1),
        closeTo(111.19492664455873, 1e-9),
      );
    });

    test('NYC to LA great-circle distance', () {
      expect(
        DistBearingScreen.haversineKm(nycLat, nycLon, laLat, laLon),
        closeTo(3935.746254609722, 1e-6),
      );
    });

    test('haversine is symmetric (A→B equals B→A)', () {
      final double ab = DistBearingScreen.haversineKm(nycLat, nycLon, laLat, laLon);
      final double ba = DistBearingScreen.haversineKm(laLat, laLon, nycLat, nycLon);
      expect(ab, closeTo(ba, 1e-9));
    });
  });

  group('Initial bearing (pure) — matches PWA bearingDeg, normalized [0,360)', () {
    test('due east at the equator is 90 degrees', () {
      expect(DistBearingScreen.bearingDeg(0, 0, 0, 1), closeTo(90, 1e-9));
    });

    test('due north is 0 degrees', () {
      expect(DistBearingScreen.bearingDeg(0, 0, 1, 0), closeTo(0, 1e-9));
    });

    test('NYC to LA initial bearing', () {
      expect(
        DistBearingScreen.bearingDeg(nycLat, nycLon, laLat, laLon),
        closeTo(273.6871323393308, 1e-9),
      );
    });

    test('reverse bearing is forward plus 180 mod 360', () {
      final double fwd =
          DistBearingScreen.bearingDeg(nycLat, nycLon, laLat, laLon);
      expect(
        DistBearingScreen.reverseBearingDeg(fwd),
        closeTo(93.68713233933079, 1e-9),
      );
    });

    test('reverse wraps below 360 (forward 90 → reverse 270)', () {
      expect(DistBearingScreen.reverseBearingDeg(90), closeTo(270, 1e-9));
    });
  });

  group('DistBearingScreen widget', () {
    testWidgets('renders title, point headers, and the distance readout',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DistBearingScreen(),
          ),
        );

        expect(find.text('Distance & Bearing'), findsWidgets);
        expect(find.text('Point 1'), findsOneWidget);
        expect(find.text('Point 2'), findsOneWidget);
        expect(find.text('Great-circle distance'), findsOneWidget);
        expect(find.text('Initial bearing'), findsOneWidget);
        // Four coordinate inputs: lat1, lon1, lat2, lon2.
        expect(find.byType(TextField), findsNWidgets(4));
      });
    });

    testWidgets('typing both points renders the PWA-matched km and bearing',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DistBearingScreen(),
          ),
        );

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '40.7128'); // lat1
        await tester.enterText(fields.at(1), '-74.0060'); // lon1
        await tester.enterText(fields.at(2), '34.0522'); // lat2
        await tester.enterText(fields.at(3), '-118.2437'); // lon2
        await tester.pump();

        // km at 4 decimals and forward bearing at 1 decimal, per PWA fmt().
        expect(find.text('3935.7463'), findsOneWidget);
        expect(find.text('273.7°'), findsOneWidget);
        expect(find.text('93.7°'), findsOneWidget);
      });
    });

    testWidgets('clearing a field blanks the outputs to an em-free dash',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DistBearingScreen(),
          ),
        );

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '40.7128');
        await tester.enterText(fields.at(1), '-74.0060');
        await tester.enterText(fields.at(2), '34.0522');
        await tester.enterText(fields.at(3), '-118.2437');
        await tester.pump();
        expect(find.text('3935.7463'), findsOneWidget);

        // Clear longitude 2 → all outputs blank (no crash, dashes shown).
        await tester.enterText(fields.at(3), '');
        await tester.pump();
        expect(find.text('3935.7463'), findsNothing);
        expect(find.text('—'), findsWidgets);
      });
    });

    testWidgets('out-of-range latitude shows the validity note, not a result',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DistBearingScreen(),
          ),
        );

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '120'); // lat1 > 90
        await tester.enterText(fields.at(1), '0');
        await tester.enterText(fields.at(2), '0');
        await tester.enterText(fields.at(3), '0');
        await tester.pump();

        expect(find.text('Latitude must be −90 to 90.'), findsOneWidget);
      });
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors test/widget_test.dart `_withViewport` to avoid RenderFlex overflow.
Future<void> _withViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await body();
}
