// Tests for the Downtilt Coverage calculator.
//
// The math is verified against the RF Tools PWA reference (app.js
// calcDtCoverage):
//   farAngle  = tilt - beamwidth/2
//   nearAngle = tilt + beamwidth/2
//   edge      = height / tan(angle)
//   depth     = farEdge - nearEdge
// with the PWA height conversion toMeters (ft ×0.3048). Expected values below
// were computed from that exact formula so the native app and PWA agree to the
// decimal.
//
// One widget test confirms the screen pumps in a phone viewport and renders a
// finite result for valid inputs.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/downtilt_coverage_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Downtilt Coverage math (pure) — matches PWA app.js calcDtCoverage',
      () {
    test('30 m, 10° tilt, 15° beamwidth — finite near/far/depth', () {
      final DtCoverage? r =
          DowntiltCoverageScreen.coverage(30, 10, 15);
      expect(r, isNotNull);
      expect(r!.beamAboveHorizon, isFalse);
      expect(r.nearEdge, closeTo(95.14784407089638, 1e-9));
      expect(r.farEdge, closeTo(687.1129664529359, 1e-9));
      expect(r.depth, closeTo(591.9651223820395, 1e-9));
    });

    test('10 m, 8° tilt, 12° beamwidth', () {
      final DtCoverage? r = DowntiltCoverageScreen.coverage(10, 8, 12);
      expect(r, isNotNull);
      expect(r!.nearEdge, closeTo(40.107809335358446, 1e-9));
      expect(r.farEdge, closeTo(286.362532829156, 1e-9));
      expect(r.depth, closeTo(246.25472349379757, 1e-9));
    });

    test('beam above horizon when tilt <= beamwidth/2 (far edge unbounded)', () {
      // 6° tilt, 15° beamwidth → farAngle = 6 - 7.5 = -1.5° <= 0.
      final DtCoverage? r = DowntiltCoverageScreen.coverage(30, 6, 15);
      expect(r, isNotNull);
      expect(r!.beamAboveHorizon, isTrue);
      expect(r.farEdge, isNull);
      expect(r.depth, isNull);
      // Near edge stays finite.
      expect(r.nearEdge, closeTo(124.95899310271253, 1e-9));
    });

    test('depth equals far minus near', () {
      final DtCoverage? r = DowntiltCoverageScreen.coverage(30, 12, 10);
      expect(r, isNotNull);
      expect(r!.depth, closeTo(r.farEdge! - r.nearEdge, 1e-9));
    });

    test('non-positive height returns null', () {
      expect(DowntiltCoverageScreen.coverage(0, 10, 15), isNull);
      expect(DowntiltCoverageScreen.coverage(-5, 10, 15), isNull);
    });

    test('beamwidth outside the open 0..180 band returns null', () {
      expect(DowntiltCoverageScreen.coverage(30, 10, 0), isNull);
      expect(DowntiltCoverageScreen.coverage(30, 10, 180), isNull);
      expect(DowntiltCoverageScreen.coverage(30, 10, 200), isNull);
    });
  });

  group('Height normalization — matches PWA toMeters', () {
    test('feet convert to meters', () {
      expect(
        DowntiltCoverageScreen.heightToMeters(100, HeightUnit.ft),
        closeTo(30.48, 1e-9),
      );
      expect(DowntiltCoverageScreen.heightToMeters(30, HeightUnit.m), 30);
    });

    test('100 ft height matches 30.48 m height for the same geometry', () {
      final DtCoverage? ft = DowntiltCoverageScreen.coverage(
        DowntiltCoverageScreen.heightToMeters(100, HeightUnit.ft),
        10,
        15,
      );
      final DtCoverage? m = DowntiltCoverageScreen.coverage(
        DowntiltCoverageScreen.heightToMeters(30.48, HeightUnit.m),
        10,
        15,
      );
      expect(ft, isNotNull);
      expect(m, isNotNull);
      expect(ft!.nearEdge, closeTo(m!.nearEdge, 1e-9));
      expect(ft.farEdge!, closeTo(m.farEdge!, 1e-9));
    });
  });

  group('DowntiltCoverageScreen widget', () {
    testWidgets('renders title, input labels, and result rows', (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DowntiltCoverageScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Downtilt Coverage'), findsWidgets);
        expect(find.text('Antenna height (AGL)'), findsOneWidget);
        expect(find.text('Downtilt angle'), findsOneWidget);
        expect(find.text('Vertical beamwidth'), findsOneWidget);
        expect(find.text('Near edge'), findsOneWidget);
        expect(find.text('Far edge'), findsOneWidget);
        expect(find.text('Coverage depth'), findsOneWidget);
        // Three text inputs: height, tilt, beamwidth.
        expect(find.byType(TextField), findsNWidgets(3));
      });
    });

    testWidgets('typing valid inputs renders finite m/ft results',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DowntiltCoverageScreen(),
          ),
        );
        await tester.pumpAndSettle();

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '30'); // m default
        await tester.enterText(fields.at(1), '10'); // tilt °
        await tester.enterText(fields.at(2), '15'); // beamwidth °
        await tester.pump();

        // 30 m, 10°, 15° → near 95 m / 312 ft, far 687 m / 2254 ft.
        expect(find.text('95 m / 312 ft'), findsOneWidget);
        expect(find.text('687 m / 2254 ft'), findsOneWidget);
      });
    });

    testWidgets('clearing an input blanks results to an em-free dash',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DowntiltCoverageScreen(),
          ),
        );
        await tester.pumpAndSettle();

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '30');
        await tester.enterText(fields.at(1), '10');
        await tester.enterText(fields.at(2), '15');
        await tester.pump();
        expect(find.text('95 m / 312 ft'), findsOneWidget);

        // Clear beamwidth → all three outputs blank (no crash, dashes show).
        await tester.enterText(fields.at(2), '');
        await tester.pump();
        expect(find.text('95 m / 312 ft'), findsNothing);
        expect(find.text('—'), findsNWidgets(3));
      });
    });

    testWidgets('beam above horizon shows the infinity far-edge label',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DowntiltCoverageScreen(),
          ),
        );
        await tester.pumpAndSettle();

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '30');
        await tester.enterText(fields.at(1), '6'); // tilt < bw/2
        await tester.enterText(fields.at(2), '15');
        await tester.pump();

        expect(find.text('∞ (beam above horizon)'), findsOneWidget);
        // Near edge stays finite; depth blanks.
        expect(find.text('125 m / 410 ft'), findsOneWidget);
      });
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors the phone-viewport helper in test/widget_test.dart.
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
