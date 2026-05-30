// Tests for the Lat/Long Conversion tool.
//
// Conversions are verified against the RF Tools PWA reference (app.js
// ddToDmsParts + fmtCoord, lines 156-180):
//   DD  = dd.toFixed(6)
//   DDM = "{deg}° {(min + sec/60).toFixed(4)}' {dir}"
//   DMS = "{deg}° {min}' {sec.toFixed(2)}" {dir}"
// The canonical anchor: 40.7128 DD → 40° 42.768' → 40° 42' 46.08".
//
// One widget test confirms the screen pumps and renders, wrapped in a
// phone-sized viewport to avoid RenderFlex overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/lat_long_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('Lat/Long parts (pure) — matches PWA ddToDmsParts', () {
    test('40.7128 splits to 40° 42\' 46.08"', () {
      expect(LatLongScreen.degreesPart(40.7128), 40);
      expect(LatLongScreen.minutesPart(40.7128), 42);
      expect(LatLongScreen.secondsPart(40.7128), closeTo(46.08, 1e-6));
    });

    test('decimal minutes for DDM = min + sec/60', () {
      // 42 + 46.08/60 = 42.768
      expect(
        LatLongScreen.decimalMinutesPart(40.7128),
        closeTo(42.768, 1e-6),
      );
    });

    test('parts use the absolute value (negative degrees, west)', () {
      // -74.0060 → degrees 74, the sign lives only in the direction letter.
      expect(LatLongScreen.degreesPart(-74.0060), 74);
      expect(LatLongScreen.minutesPart(-74.0060), 0);
      expect(LatLongScreen.secondsPart(-74.0060), closeTo(21.6, 1e-6));
    });
  });

  group('Direction letters — matches PWA fmtCoord', () {
    test('latitude sign picks N / S', () {
      expect(LatLongScreen.direction(40.7128, CoordAxis.latitude), 'N');
      expect(LatLongScreen.direction(-33.8688, CoordAxis.latitude), 'S');
      expect(LatLongScreen.direction(0, CoordAxis.latitude), 'N'); // >= 0 → N
    });

    test('longitude sign picks E / W', () {
      expect(LatLongScreen.direction(151.2093, CoordAxis.longitude), 'E');
      expect(LatLongScreen.direction(-74.0060, CoordAxis.longitude), 'W');
      expect(LatLongScreen.direction(0, CoordAxis.longitude), 'E'); // >= 0 → E
    });
  });

  group('format() — PWA-exact strings', () {
    test('40.7128 latitude formats DD / DDM / DMS', () {
      final CoordFormats? f =
          LatLongScreen.format(40.7128, CoordAxis.latitude);
      expect(f, isNotNull);
      expect(f!.dd, '40.712800');
      expect(f.ddm, "40° 42.7680' N");
      expect(f.dms, "40° 42' 46.08\" N");
    });

    test('-74.0060 longitude formats with W and absolute parts', () {
      final CoordFormats? f =
          LatLongScreen.format(-74.0060, CoordAxis.longitude);
      expect(f, isNotNull);
      expect(f!.dd, '-74.006000');
      expect(f.ddm, "74° 0.3600' W");
      expect(f.dms, "74° 0' 21.60\" W");
    });

    test('exact whole degree renders zero minutes and seconds', () {
      final CoordFormats? f = LatLongScreen.format(45, CoordAxis.latitude);
      expect(f, isNotNull);
      expect(f!.dd, '45.000000');
      expect(f.ddm, "45° 0.0000' N");
      expect(f.dms, "45° 0' 0.00\" N");
    });
  });

  group('Range guards — matches PWA calcLatLong', () {
    test('latitude beyond ±90 returns null', () {
      expect(LatLongScreen.format(91, CoordAxis.latitude), isNull);
      expect(LatLongScreen.format(-90.0001, CoordAxis.latitude), isNull);
      expect(LatLongScreen.format(90, CoordAxis.latitude), isNotNull);
    });

    test('longitude beyond ±180 returns null', () {
      expect(LatLongScreen.format(181, CoordAxis.longitude), isNull);
      expect(LatLongScreen.format(-180.5, CoordAxis.longitude), isNull);
      expect(LatLongScreen.format(180, CoordAxis.longitude), isNotNull);
    });

    test('non-finite returns null', () {
      expect(LatLongScreen.format(double.nan, CoordAxis.latitude), isNull);
      expect(
        LatLongScreen.format(double.infinity, CoordAxis.longitude),
        isNull,
      );
    });
  });

  group('LatLongScreen widget', () {
    testWidgets('renders title, input labels, and format legend',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const LatLongScreen(),
          ),
        );

        expect(find.text('Lat / Long'), findsWidgets);
        expect(find.text('Latitude'), findsWidgets);
        expect(find.text('Longitude'), findsWidgets);
        expect(find.text('Formats'), findsOneWidget);
        // Two decimal-degree inputs: latitude and longitude.
        expect(find.byType(TextField), findsNWidgets(2));
      });
    });

    testWidgets('typing valid coordinates renders all three formats',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const LatLongScreen(),
          ),
        );

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '40.7128');
        await tester.enterText(fields.at(1), '-74.0060');
        await tester.pump();

        expect(find.text('40.712800'), findsOneWidget);
        expect(find.text("40° 42.7680' N"), findsOneWidget);
        expect(find.text("40° 42' 46.08\" N"), findsOneWidget);
        expect(find.text('-74.006000'), findsOneWidget);
        expect(find.text("74° 0.3600' W"), findsOneWidget);
        expect(find.text("74° 0' 21.60\" W"), findsOneWidget);
      });
    });

    testWidgets('clearing an input blanks that coordinate to a dash',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const LatLongScreen(),
          ),
        );

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '40.7128');
        await tester.pump();
        expect(find.text('40.712800'), findsOneWidget);

        // Clear the latitude field → its rows blank (no crash, dashes show).
        await tester.enterText(fields.at(0), '');
        await tester.pump();
        expect(find.text('40.712800'), findsNothing);
        // Six format rows total (3 lat + 3 lon), all blank now.
        expect(find.text('—'), findsNWidgets(6));
      });
    });

    testWidgets('out-of-range latitude blanks the latitude rows',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const LatLongScreen(),
          ),
        );

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '200'); // beyond ±90
        await tester.enterText(fields.at(1), '10');
        await tester.pump();

        // Latitude (3 rows) blank; longitude renders its DD value.
        expect(find.text('10.000000'), findsOneWidget);
        expect(find.text('—'), findsNWidgets(3));
      });
    });
  });
}

/// Run [body] with the test view sized to [size], then restore. Phone-sized
/// viewport keeps the result + legend cards from logging a RenderFlex overflow
/// (mirrors test/widget_test.dart _withViewport).
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
