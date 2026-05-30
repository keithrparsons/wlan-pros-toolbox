// Tests for the Midpoint (geographic) calculator.
//
// The math is verified against the RF Tools PWA reference (app.js
// sphereMidpoint, called by calcMidpoint). Expected values were computed from
// that exact formula so the native app and PWA agree to the decimal:
//   sphereMidpoint(33.9416, -118.4085, 40.6413, -73.7781)
//     → lat 39.45688757383132, lon -97.14145572736561   (LAX → JFK)
//   sphereMidpoint(0, 0, 0, 90)        → lat 0,            lon 45
//   sphereMidpoint(40, -75, 40, -75)   → lat 40,           lon -75
//   sphereMidpoint(10, 170, 10, -170)  → lat 10.151081711, lon -180
//
// One widget test confirms the screen pumps and renders, wrapped in a
// phone-sized viewport to avoid RenderFlex overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/midpoint_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Midpoint math (pure) — matches PWA app.js sphereMidpoint', () {
    test('LAX → JFK midpoint matches the PWA to the decimal', () {
      final MidpointResult m = MidpointScreen.sphereMidpoint(
        33.9416,
        -118.4085,
        40.6413,
        -73.7781,
      );
      expect(m.lat, closeTo(39.45688757383132, 1e-9));
      expect(m.lon, closeTo(-97.14145572736561, 1e-9));
    });

    test('equator: (0,0) and (0,90) → (0,45)', () {
      final MidpointResult m = MidpointScreen.sphereMidpoint(0, 0, 0, 90);
      expect(m.lat, closeTo(0, 1e-12));
      expect(m.lon, closeTo(45, 1e-9));
    });

    test('identical points → that point', () {
      final MidpointResult m = MidpointScreen.sphereMidpoint(40, -75, 40, -75);
      expect(m.lat, closeTo(40, 1e-9));
      expect(m.lon, closeTo(-75, 1e-9));
    });

    test('across the antimeridian wraps longitude into (−180, 180]', () {
      // (10,170) and (10,-170): midpoint sits on the dateline at lon -180,
      // never +180 — the ((deg + 540) % 360) - 180 normalization.
      final MidpointResult m = MidpointScreen.sphereMidpoint(10, 170, 10, -170);
      expect(m.lat, closeTo(10.151081711048134, 1e-9));
      expect(m.lon, closeTo(-180, 1e-9));
    });
  });

  group('MidpointScreen widget', () {
    testWidgets('renders title, point headings, and result tags',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const MidpointScreen(),
          ),
        );

        expect(find.text('Midpoint'), findsWidgets);
        expect(find.text('Point A'), findsOneWidget);
        expect(find.text('Point B'), findsOneWidget);
        expect(find.text('Great-circle midpoint'), findsOneWidget);
        // Four coordinate inputs: lat/lon for each of the two points.
        expect(find.byType(TextField), findsNWidgets(4));
      });
    });

    testWidgets('typing both points renders the midpoint at 6 decimals',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const MidpointScreen(),
          ),
        );

        final Finder fields = find.byType(TextField);
        // Order: lat A, lon A, lat B, lon B.
        await tester.enterText(fields.at(0), '0');
        await tester.enterText(fields.at(1), '0');
        await tester.enterText(fields.at(2), '0');
        await tester.enterText(fields.at(3), '90');
        await tester.pump();

        // (0,0) ↔ (0,90) → (0, 45), formatted to 6 places.
        expect(find.text('0.000000'), findsOneWidget);
        expect(find.text('45.000000'), findsOneWidget);
      });
    });

    testWidgets('clearing an input blanks the result to an em-free dash',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const MidpointScreen(),
          ),
        );

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '0');
        await tester.enterText(fields.at(1), '0');
        await tester.enterText(fields.at(2), '0');
        await tester.enterText(fields.at(3), '90');
        await tester.pump();
        expect(find.text('45.000000'), findsOneWidget);

        // Clear one field → both outputs blank to the dash (no crash).
        await tester.enterText(fields.at(3), '');
        await tester.pump();
        expect(find.text('45.000000'), findsNothing);
        expect(find.text('—'), findsNWidgets(2));
      });
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors test/widget_test.dart `_withViewport` so widget tests run in a
/// phone-sized viewport and never log a RenderFlex overflow.
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
