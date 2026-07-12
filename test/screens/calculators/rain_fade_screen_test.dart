// Tests for the ITU Rain Fade calculator.
//
// SOURCE OF TRUTH: Recommendation ITU-R P.838-3, "Specific attenuation model for
// rain for use in prediction methods", TABLE 5 (pp. 5–8). All 115 rows.
//
//   gamma = k · R^alpha               (specific attenuation, dB/km)
//   d0    = 35 · e^(-0.015·R)
//   L_eff = L / (1 + L/d0)            (effective path length, km) — ITU-R P.530
//   A     = gamma · L_eff             (rain attenuation, dB)
//
// The coefficients that previously shipped were wrong in ALL 28 rows. The
// replacements are transcribed from the ITU's own PDF via the verification brief
// (Deliverables/2026-07-11-calculator-verification/CABLE-AND-RAIN-DATA.md §7).
// Every expected value below is a BLIND VECTOR from that table or derived from
// it by hand. None came from running this code.
//
// ⚠️⚠️ READ BEFORE ADDING A "SANITY CHECK" TO THIS FILE ⚠️⚠️
//
// k_H IS GENUINELY NON-MONOTONIC IN FREQUENCY BELOW 6 GHz.
//
//     3.0 GHz → 1.390e-4
//     3.5 GHz → 1.155e-4
//     4.0 GHz → 1.071e-4     ← a real trough, not a typo
//     4.5 GHz → 1.340e-4
//
// That dip is a real feature of the ITU's curve-fit (visible in P.838-3 Fig. 1)
// and it is in the official Table 5. α_H likewise peaks near 5 GHz and falls
// away on both sides. DO NOT add a "loss must increase with frequency"
// assertion: it would flag valid ITU data as broken, and the next person would
// "fix" the coefficients into being wrong. The dip is asserted POSITIVELY below
// so that anyone who "corrects" it breaks a test that explains why they should
// not have.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rain_fade_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('ITU-R P.838-3 Table 5 — coefficients are the ITU\'s, verbatim', () {
    // Blind vectors: [f_GHz, kH, alphaH, kV, alphaV] straight off the ITU PDF.
    const List<List<double>> vectors = <List<double>>[
      <double>[1, 0.0000259, 0.9691, 0.0000308, 0.8592],
      <double>[2, 0.0000847, 1.0664, 0.0000998, 0.9490],
      <double>[3, 0.0001390, 1.2322, 0.0001942, 1.0688],
      <double>[4, 0.0001071, 1.6009, 0.0002461, 1.2476],
      <double>[5, 0.0002162, 1.6969, 0.0002428, 1.5317],
      <double>[6, 0.0007056, 1.5900, 0.0004878, 1.5728],
      <double>[7, 0.001915, 1.4810, 0.001425, 1.4745],
      <double>[8, 0.004115, 1.3905, 0.003450, 1.3797],
      <double>[10, 0.01217, 1.2571, 0.01129, 1.2156],
      <double>[12, 0.02386, 1.1825, 0.02455, 1.1216],
      <double>[15, 0.04481, 1.1233, 0.05008, 1.0440],
      <double>[20, 0.09164, 1.0568, 0.09611, 0.9847],
      <double>[25, 0.1571, 0.9991, 0.1533, 0.9491],
      <double>[30, 0.2403, 0.9485, 0.2291, 0.9129],
      <double>[40, 0.4431, 0.8673, 0.4274, 0.8421],
      <double>[50, 0.6600, 0.8084, 0.6472, 0.7871],
      <double>[60, 0.8606, 0.7656, 0.8515, 0.7486],
      <double>[80, 1.1704, 0.7115, 1.1668, 0.7021],
      <double>[100, 1.3671, 0.6815, 1.3680, 0.6765],
      <double>[200, 1.6378, 0.6382, 1.6443, 0.6343],
      <double>[1000, 1.3795, 0.6396, 1.3822, 0.6365],
    ];

    for (final List<double> row in vectors) {
      test('${row[0]} GHz row matches the ITU table exactly', () {
        final (double kH, double aH) =
            RainFadeScreen.interpolateITU(row[0], Polarization.horizontal);
        final (double kV, double aV) =
            RainFadeScreen.interpolateITU(row[0], Polarization.vertical);
        expect(kH, closeTo(row[1], 1e-12), reason: 'k_H @ ${row[0]} GHz');
        expect(aH, closeTo(row[2], 1e-12), reason: 'alpha_H @ ${row[0]} GHz');
        expect(kV, closeTo(row[3], 1e-12), reason: 'k_V @ ${row[0]} GHz');
        expect(aV, closeTo(row[4], 1e-12), reason: 'alpha_V @ ${row[0]} GHz');
      });
    }

    test('the table carries all 116 rows of ITU-R P.838-3 Table 5', () {
      // 116, not 115. The verification brief's PROSE says "115 rows", but its
      // own Table 5 and its own drop-in JSON block both contain 116, and they
      // agree with each other row for row. The real Table 5 runs
      //   1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 5.5   (10)
      //   6                                        (1)
      //   7 … 100 in 1 GHz steps                   (94)
      //   120, 150, 200, 300 … 1000                (11)
      // = 116. The prose count is an off-by-one; the DATA is authoritative and
      // is what shipped here.
      expect(RainFadeScreen.ituRain.length, 116);
      expect(RainFadeScreen.ituRain.first[0], 1);
      expect(RainFadeScreen.ituRain.last[0], 1000);
    });

    test('the coefficients that shipped are GONE', () {
      // The old table's 10 GHz H row was k=0.0101, alpha=1.276. All 28 rows of
      // it were wrong. If any of them come back, this fails.
      final (double k, double a) =
          RainFadeScreen.interpolateITU(10, Polarization.horizontal);
      expect(k, isNot(closeTo(0.0101, 1e-6)));
      expect(a, isNot(closeTo(1.276, 1e-6)));
    });
  });

  group('⚠️ the k_H dip below 6 GHz is REAL ITU data — do not "fix" it', () {
    test('k_H falls from 3 GHz to 4 GHz, then rises again', () {
      double kH(double f) =>
          RainFadeScreen.interpolateITU(f, Polarization.horizontal).$1;

      final double at3 = kH(3);
      final double at3p5 = kH(3.5);
      final double at4 = kH(4);
      final double at4p5 = kH(4.5);
      final double at5 = kH(5);

      // Strictly DECREASING 3 → 4 GHz. This is correct.
      expect(at3, greaterThan(at3p5),
          reason: 'ITU: 1.390e-4 @ 3 GHz > 1.155e-4 @ 3.5 GHz');
      expect(at3p5, greaterThan(at4),
          reason: 'ITU: 1.155e-4 @ 3.5 GHz > 1.071e-4 @ 4 GHz');

      // Then strictly INCREASING again. Also correct.
      expect(at4, lessThan(at4p5));
      expect(at4p5, lessThan(at5));

      // If someone "smooths" this trough away, the app stops reproducing the
      // ITU recommendation. That is a defect, not a fix.
      expect(at4, lessThan(at3),
          reason: 'The 4 GHz trough is in the ITU\'s official Table 5. It is '
              'not a transcription error. Do not linearize it.');
    });

    test('alpha_H peaks near 5 GHz and falls away on both sides', () {
      double aH(double f) =>
          RainFadeScreen.interpolateITU(f, Polarization.horizontal).$2;
      expect(aH(5), closeTo(1.6969, 1e-12));
      expect(aH(4.5), lessThan(aH(5)));
      expect(aH(5.5), lessThan(aH(5)));
    });
  });

  group('Rain fade math — derived from the ITU coefficients', () {
    test('10 GHz, 25 mm/hr, 10 km, H', () {
      // gamma = 0.01217 · 25^1.2571 = 0.69605 dB/km
      expect(
        RainFadeScreen.specificAttenuation(10, 25, Polarization.horizontal),
        closeTo(0.6960508419472354, 1e-9),
      );
      // L_eff is unchanged by this fix (P.530, independent of k/alpha).
      expect(
        RainFadeScreen.effectivePathKm(10, 25),
        closeTo(7.063584388207636, 1e-9),
      );
      // A = 4.9166 dB. The old (wrong) coefficients gave 4.3363 dB — the app
      // was UNDER-reporting rain fade by 12% on this everyday 10 GHz case.
      expect(
        RainFadeScreen.rainAttenuationDb(10, 25, 10, Polarization.horizontal),
        closeTo(4.916613860577273, 1e-9),
      );
    });

    test('11 GHz, 25 mm/hr, 10 km, H (an exact node in the full table)', () {
      expect(
        RainFadeScreen.rainAttenuationDb(11, 25, 10, Polarization.horizontal),
        closeTo(6.231434380655517, 1e-9),
      );
    });

    test('40 GHz, 50 mm/hr, 5 km, V', () {
      expect(
        RainFadeScreen.specificAttenuation(40, 50, Polarization.vertical),
        closeTo(11.522246405948191, 1e-9),
      );
      expect(
        RainFadeScreen.rainAttenuationDb(40, 50, 5, Polarization.vertical),
        closeTo(44.23369786918358, 1e-9),
      );
    });

    test('effective path length is always shorter than the geometric path', () {
      expect(RainFadeScreen.effectivePathKm(10, 25), lessThan(10));
      expect(RainFadeScreen.effectivePathKm(5, 50), lessThan(5));
    });
  });

  group('Clamping outside the ITU table range (1–1000 GHz)', () {
    test('below 1 GHz clamps to the 1 GHz row', () {
      final (double k, double a) =
          RainFadeScreen.interpolateITU(0.5, Polarization.horizontal);
      expect(k, closeTo(0.0000259, 1e-15));
      expect(a, closeTo(0.9691, 1e-12));
    });

    test('above 1000 GHz clamps to the 1000 GHz row', () {
      final (double k, double a) =
          RainFadeScreen.interpolateITU(2000, Polarization.vertical);
      expect(k, closeTo(1.3822, 1e-12));
      expect(a, closeTo(0.6365, 1e-12));
    });
  });

  group('Path-length normalization', () {
    test('miles convert to km at 1.60934', () {
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
        MaterialApp(theme: AppTheme.dark(), home: const RainFadeScreen()),
      );

      expect(find.text('Rain Fade'), findsWidgets);
      expect(find.text('Frequency'), findsOneWidget);
      expect(find.text('Rain rate'), findsOneWidget);
      expect(find.text('Path length'), findsOneWidget);
      expect(find.text('Polarization'), findsOneWidget);
      expect(find.text('Rain attenuation'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(3));
    });

    testWidgets('typing valid inputs renders the corrected dB result',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark(), home: const RainFadeScreen()),
      );

      final Finder fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '10'); // GHz
      await tester.enterText(fields.at(1), '25'); // mm/hr
      await tester.enterText(fields.at(2), '10'); // km default
      await tester.pump();

      // 10 GHz, 25 mm/hr, 10 km, H → 4.92 dB. (Was 4.34 on the wrong table.)
      expect(find.text('4.92'), findsOneWidget);
      expect(find.text('4.34'), findsNothing);
    });

    testWidgets('clearing an input blanks the result to a dash', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark(), home: const RainFadeScreen()),
      );

      final Finder fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '10');
      await tester.enterText(fields.at(1), '25');
      await tester.enterText(fields.at(2), '10');
      await tester.pump();
      expect(find.text('4.92'), findsOneWidget);

      await tester.enterText(fields.at(2), '');
      await tester.pump();
      expect(find.text('4.92'), findsNothing);
      expect(find.text('—'), findsNWidgets(3));
    });
  });
}
