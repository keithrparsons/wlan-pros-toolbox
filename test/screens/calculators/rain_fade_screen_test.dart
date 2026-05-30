// Tests for the ITU Rain Fade calculator.
//
// The math is verified against the RF Tools PWA reference (app.js calcRainFade
// + interpolateITU + the ITU_RAIN P.838-3 table):
//   gamma = k · R^alpha               (specific attenuation, dB/km)
//   d0    = 35 · e^(-0.015·R)
//   L_eff = L / (1 + L/d0)            (effective path length, km)
//   A     = gamma · L_eff             (rain attenuation, dB)
// Expected values below were computed from those exact PWA coefficients and
// formulas so the native app and PWA agree to the decimal.
//
// One widget test confirms the screen pumps and renders its cards.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rain_fade_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('ITU coefficient lookup — matches PWA interpolateITU', () {
    test('exact table node returns its row verbatim (10 GHz, H)', () {
      final (k, alpha) =
          RainFadeScreen.interpolateITU(10, Polarization.horizontal);
      expect(k, closeTo(0.0101, 1e-12));
      expect(alpha, closeTo(1.276, 1e-12));
    });

    test('exact table node returns its row verbatim (40 GHz, V)', () {
      final (k, alpha) =
          RainFadeScreen.interpolateITU(40, Polarization.vertical);
      expect(k, closeTo(0.310, 1e-12));
      expect(alpha, closeTo(0.929, 1e-12));
    });

    test('11 GHz interpolates log-log between 10 and 12 GHz (H)', () {
      final (k, alpha) =
          RainFadeScreen.interpolateITU(11, Polarization.horizontal);
      expect(k, closeTo(0.013975930702919588, 1e-12));
      expect(alpha, closeTo(1.24515723676707, 1e-12));
    });

    test('below table range clamps to the first node (0.5 GHz → 1 GHz row)',
        () {
      final (k, alpha) =
          RainFadeScreen.interpolateITU(0.5, Polarization.horizontal);
      expect(k, closeTo(0.0000387, 1e-15));
      expect(alpha, closeTo(0.912, 1e-12));
    });

    test('above table range clamps to the last node (200 GHz → 100 GHz row)',
        () {
      final (k, alpha) =
          RainFadeScreen.interpolateITU(200, Polarization.vertical);
      expect(k, closeTo(1.06, 1e-12));
      expect(alpha, closeTo(0.744, 1e-12));
    });
  });

  group('Rain fade math (pure) — matches PWA calcRainFade', () {
    test('10 GHz, 25 mm/hr, 10 km, H', () {
      expect(
        RainFadeScreen.specificAttenuation(10, 25, Polarization.horizontal),
        closeTo(0.6138932029034252, 1e-9),
      );
      expect(
        RainFadeScreen.effectivePathKm(10, 25),
        closeTo(7.063584388207636, 1e-9),
      );
      expect(
        RainFadeScreen.rainAttenuationDb(10, 25, 10, Polarization.horizontal),
        closeTo(4.336286444055417, 1e-9),
      );
    });

    test('11 GHz (interpolated), 25 mm/hr, 10 km, H', () {
      expect(
        RainFadeScreen.rainAttenuationDb(11, 25, 10, Polarization.horizontal),
        closeTo(5.433266342756117, 1e-9),
      );
    });

    test('40 GHz, 50 mm/hr, 5 km, V', () {
      expect(
        RainFadeScreen.specificAttenuation(40, 50, Polarization.vertical),
        closeTo(11.740992965871886, 1e-9),
      );
      expect(
        RainFadeScreen.rainAttenuationDb(40, 50, 5, Polarization.vertical),
        closeTo(45.07346200029892, 1e-9),
      );
    });

    test('effective path length is always shorter than the geometric path',
        () {
      // P.530 reduction: L_eff < L for any positive rain rate and path.
      expect(RainFadeScreen.effectivePathKm(10, 25), lessThan(10));
      expect(RainFadeScreen.effectivePathKm(5, 50), lessThan(5));
    });
  });

  group('Path-length normalization — matches PWA toKm', () {
    test('miles convert to km at the PWA constant', () {
      expect(RainFadeScreen.pathToKm(1, PathUnit.mi), closeTo(1.60934, 1e-12));
      expect(RainFadeScreen.pathToKm(10, PathUnit.km), 10);
    });

    test('10 mi path matches 16.0934 km path at the same conditions', () {
      final double miFade = RainFadeScreen.rainAttenuationDb(
        11,
        25,
        RainFadeScreen.pathToKm(10, PathUnit.mi),
        Polarization.horizontal,
      );
      final double kmFade = RainFadeScreen.rainAttenuationDb(
        11,
        25,
        16.0934,
        Polarization.horizontal,
      );
      expect(miFade, closeTo(kmFade, 1e-9));
    });
  });

  group('RainFadeScreen widget', () {
    testWidgets('renders title, input labels, and result unit', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const RainFadeScreen(),
        ),
      );

      expect(find.text('Rain Fade'), findsWidgets);
      expect(find.text('Frequency'), findsOneWidget);
      expect(find.text('Rain rate'), findsOneWidget);
      expect(find.text('Path length'), findsOneWidget);
      expect(find.text('Polarization'), findsOneWidget);
      expect(find.text('Rain attenuation'), findsOneWidget);
      // Three text inputs: frequency, rain rate, path length.
      expect(find.byType(TextField), findsNWidgets(3));
    });

    testWidgets('typing valid inputs renders the PWA-rounded dB result',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const RainFadeScreen(),
        ),
      );

      final Finder fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '10'); // GHz
      await tester.enterText(fields.at(1), '25'); // mm/hr
      await tester.enterText(fields.at(2), '10'); // km default
      await tester.pump();

      // 10 GHz, 25 mm/hr, 10 km, H → 4.34 dB at 2-decimal PWA formatting.
      expect(find.text('4.34'), findsOneWidget);
    });

    testWidgets('clearing an input blanks the result to an em-free dash',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const RainFadeScreen(),
        ),
      );

      final Finder fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '10');
      await tester.enterText(fields.at(1), '25');
      await tester.enterText(fields.at(2), '10');
      await tester.pump();
      expect(find.text('4.34'), findsOneWidget);

      // Clear the path field → outputs blank (no crash, shows the dash).
      await tester.enterText(fields.at(2), '');
      await tester.pump();
      expect(find.text('4.34'), findsNothing);
      // Three outputs (attenuation, gamma, L_eff) all read as the dash.
      expect(find.text('—'), findsNWidgets(3));
    });
  });
}
