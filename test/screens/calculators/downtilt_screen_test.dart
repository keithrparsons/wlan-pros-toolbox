// Tests for the Antenna Downtilt calculator.
//
// The math is verified against the RF Tools PWA reference (app.js calcDowntilt):
//   angle = atan(height_m / coverage_m) · 180/π
// with the PWA unit conversions toMeters (ft ×0.3048, km ×1000). Expected
// values below were computed from that exact formula so the native app and PWA
// agree to the decimal.
//
// One widget test confirms the screen pumps and renders its cards.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/downtilt_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Downtilt math (pure) — matches PWA app.js calcDowntilt', () {
    test('equal height and coverage is exactly 45 degrees', () {
      expect(DowntiltScreen.downtiltDeg(10, 10), closeTo(45.0, 1e-9));
    });

    test('30 m height at 200 m coverage', () {
      expect(
        DowntiltScreen.downtiltDeg(30, 200),
        closeTo(8.530765609948133, 1e-9),
      );
    });

    test('3 m height at 10 m coverage', () {
      expect(
        DowntiltScreen.downtiltDeg(3, 10),
        closeTo(16.69924423399362, 1e-9),
      );
    });

    test('shorter coverage at fixed height steepens the tilt', () {
      final double near = DowntiltScreen.downtiltDeg(30, 200);
      final double far = DowntiltScreen.downtiltDeg(30, 500);
      expect(far, closeTo(3.4336303624505224, 1e-9));
      expect(near, greaterThan(far));
    });

    test('result stays below 90 degrees for any positive inputs', () {
      expect(DowntiltScreen.downtiltDeg(1000, 1), lessThan(90.0));
      expect(DowntiltScreen.downtiltDeg(1, 1000), greaterThan(0.0));
    });
  });

  group('Unit normalization — matches PWA toMeters', () {
    test('feet convert to meters for height', () {
      expect(
        DowntiltScreen.heightToMeters(100, HeightUnit.ft),
        closeTo(30.48, 1e-9),
      );
      expect(DowntiltScreen.heightToMeters(30, HeightUnit.m), 30);
    });

    test('feet and km convert to meters for coverage', () {
      expect(
        DowntiltScreen.coverageToMeters(100, CoverageUnit.ft),
        closeTo(30.48, 1e-9),
      );
      expect(
        DowntiltScreen.coverageToMeters(1, CoverageUnit.km),
        closeTo(1000.0, 1e-9),
      );
      expect(DowntiltScreen.coverageToMeters(200, CoverageUnit.m), 200);
    });

    test('100 ft height at 200 m coverage', () {
      final double angle = DowntiltScreen.downtiltDeg(
        DowntiltScreen.heightToMeters(100, HeightUnit.ft),
        DowntiltScreen.coverageToMeters(200, CoverageUnit.m),
      );
      expect(angle, closeTo(8.665202012273554, 1e-9));
    });

    test('matches the closed-form atan for a known angle', () {
      // tan(30°) ratio → 30 degrees out.
      final double h = math.tan(30 * math.pi / 180);
      expect(DowntiltScreen.downtiltDeg(h, 1), closeTo(30.0, 1e-9));
    });
  });

  group('DowntiltScreen widget', () {
    testWidgets('renders title, input labels, and result unit', (tester) async {
      await _withViewport(tester, const Size(390, 844), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DowntiltScreen(),
          ),
        );

        expect(find.text('Downtilt'), findsWidgets);
        expect(find.text('Antenna height (AGL)'), findsOneWidget);
        expect(find.text('Target coverage distance'), findsOneWidget);
        expect(find.text('Downtilt angle'), findsOneWidget);
        // Two text inputs: height and coverage.
        expect(find.byType(TextField), findsNWidgets(2));
      });
    });

    testWidgets('typing valid inputs renders a finite degree result',
        (tester) async {
      await _withViewport(tester, const Size(390, 844), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DowntiltScreen(),
          ),
        );

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '30'); // m default
        await tester.enterText(fields.at(1), '200'); // m default
        await tester.pump();

        // 30 m at 200 m → 8.53° at 2-decimal PWA formatting.
        expect(find.text('8.53'), findsOneWidget);
      });
    });

    testWidgets('clearing an input blanks the result to an em-free dash',
        (tester) async {
      await _withViewport(tester, const Size(390, 844), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DowntiltScreen(),
          ),
        );

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '10');
        await tester.enterText(fields.at(1), '10');
        await tester.pump();
        expect(find.text('45.00'), findsOneWidget);

        // Clear the coverage field → output blanks (no crash, shows the dash).
        await tester.enterText(fields.at(1), '');
        await tester.pump();
        expect(find.text('45.00'), findsNothing);
        expect(find.text('—'), findsOneWidget);
      });
    });
  });
}

/// Run [body] with the test view sized to [size], then restore. Mirrors the
/// `_withViewport` helper in test/widget_test.dart so DowntiltScreen lays out
/// on a realistic phone width instead of the 800x600 default, where the wider
/// downtilt labels overflowed the input-row.
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
