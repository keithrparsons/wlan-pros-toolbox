// Tests for the Final Point (Destination) calculator.
//
// The math is verified against the RF Tools PWA reference (app.js
// destinationPt / calcFinalPoint) with EARTH_KM = 6371 and the PWA toKm unit
// conversions (mi ×1.60934, m ÷1000). Expected values were computed from that
// exact formula so the native app and PWA agree to the rendered 6-decimal
// precision.
//
// One widget test confirms the screen pumps and renders inside a phone-sized
// viewport without RenderFlex overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/final_point_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Final Point math (pure) — matches PWA app.js destinationPt', () {
    test('uses the PWA earth radius constant 6371 km', () {
      expect(FinalPointScreen.earthRadiusKm, 6371);
    });

    test('Los Angeles, bearing 45°, 10 km', () {
      // From the PWA destinationPt(34.052, -118.243, 45, 10).
      final DestinationPoint d =
          FinalPointScreen.destination(34.052, -118.243, 45, 10);
      expect(d.latitude, closeTo(34.11556775982694, 1e-9));
      expect(d.longitude, closeTo(-118.1661899733229, 1e-9));
      // Matches the PWA fmtCoord dd.toFixed(6).
      expect(d.latitude.toStringAsFixed(6), '34.115568');
      expect(d.longitude.toStringAsFixed(6), '-118.166190');
    });

    test('equator, due east, ~1° of arc', () {
      // 111.195 km ≈ 1° of arc at R = 6371. Heading 90° moves longitude east.
      final DestinationPoint d =
          FinalPointScreen.destination(0, 0, 90, 111.195);
      expect(d.latitude, closeTo(0.0, 1e-6));
      expect(d.longitude, closeTo(1.000001, 1e-6));
    });

    test('equator, due north, ~1° of arc', () {
      final DestinationPoint d =
          FinalPointScreen.destination(0, 0, 0, 111.195);
      expect(d.latitude, closeTo(1.000001, 1e-6));
      expect(d.longitude, closeTo(0.0, 1e-9));
    });

    test('longitude wraps to (-180, 180]', () {
      // Start near the antimeridian heading east crosses into negative lon.
      final DestinationPoint d =
          FinalPointScreen.destination(0, 179.9, 90, 50);
      expect(d.longitude, lessThan(0));
      expect(d.longitude, greaterThan(-180));
    });
  });

  group('Distance normalization — matches PWA toKm', () {
    test('miles and meters convert to km', () {
      expect(FinalPointScreen.distToKm(1, FpDistUnit.mi), closeTo(1.60934, 1e-12));
      expect(FinalPointScreen.distToKm(100, FpDistUnit.m), closeTo(0.1, 1e-12));
      expect(FinalPointScreen.distToKm(10, FpDistUnit.km), 10);
    });

    test('1 mile equals 1.60934 km of travel for the same bearing', () {
      final DestinationPoint mi = FinalPointScreen.destination(
        0,
        0,
        0,
        FinalPointScreen.distToKm(1, FpDistUnit.mi),
      );
      final DestinationPoint km = FinalPointScreen.destination(0, 0, 0, 1.60934);
      expect(mi.latitude, closeTo(km.latitude, 1e-12));
    });
  });

  group('FinalPointScreen widget', () {
    testWidgets('renders title, input labels, and result lines', (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const FinalPointScreen(),
          ),
        );

        expect(find.text('Final Point'), findsWidgets);
        expect(find.text('Start latitude'), findsOneWidget);
        expect(find.text('Start longitude'), findsOneWidget);
        expect(find.text('Bearing'), findsOneWidget);
        expect(find.text('Distance'), findsOneWidget);
        expect(find.text('Destination'), findsOneWidget);
        // Four text inputs: lat, lon, bearing, distance.
        expect(find.byType(TextField), findsNWidgets(4));
        // No result yet — both coord lines show the em-free dash.
        expect(find.text('—'), findsNWidgets(2));
      });
    });

    testWidgets('typing valid inputs renders the destination coordinates',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const FinalPointScreen(),
          ),
        );

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '34.052'); // lat
        await tester.enterText(fields.at(1), '-118.243'); // lon
        await tester.enterText(fields.at(2), '45'); // bearing
        await tester.enterText(fields.at(3), '10'); // distance km
        await tester.pump();

        expect(find.text('34.115568'), findsOneWidget);
        expect(find.text('-118.166190'), findsOneWidget);
      });
    });

    testWidgets('clearing an input blanks the result to em-free dashes',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const FinalPointScreen(),
          ),
        );

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '0');
        await tester.enterText(fields.at(1), '0');
        await tester.enterText(fields.at(2), '90');
        await tester.enterText(fields.at(3), '111.195');
        await tester.pump();
        expect(find.text('1.000001'), findsOneWidget);

        // Clear distance → both outputs blank (no crash).
        await tester.enterText(fields.at(3), '');
        await tester.pump();
        expect(find.text('1.000001'), findsNothing);
        expect(find.text('—'), findsNWidgets(2));
      });
    });

    testWidgets('out-of-range latitude blanks the result', (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const FinalPointScreen(),
          ),
        );

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '120'); // invalid lat
        await tester.enterText(fields.at(1), '0');
        await tester.enterText(fields.at(2), '45');
        await tester.enterText(fields.at(3), '10');
        await tester.pump();

        // |lat| > 90 → no result, both lines show the dash.
        expect(find.text('—'), findsNWidgets(2));
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
