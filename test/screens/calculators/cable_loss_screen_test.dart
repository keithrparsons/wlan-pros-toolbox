// Tests for the Cable Loss calculator.
//
// SOURCE OF TRUTH: Times Microwave publishes an attenuation EQUATION on every
// LMR datasheet:
//
//     dB/100 ft = k1 · √(F_MHz) + k2 · F_MHz        (VSWR 1.0, +25 °C)
//
// The app implements that equation. It is exact at every frequency, it agrees
// with Times' own tabulated values everywhere they overlap, and — the reason it
// is here — it deletes the entire "read the wrong row of the table" failure
// class that produced the shipped defect (the app served Times' 900 MHz value,
// 3.9 dB/100 ft, at 2.4 GHz: a 41% under-report, in the dangerous direction).
//
// EVERY expected value below is a BLIND VECTOR taken from the verification
// brief (Deliverables/2026-07-11-calculator-verification/CABLE-AND-RAIN-DATA.md
// §2), which derived them from the manufacturer's datasheets. None was produced
// by running this code. Do not "fix" a failing expectation by pasting in what
// the app currently returns — that is how the original bug shipped.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/cable_loss_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_select.dart';

void main() {
  group('REGRESSION GUARD — the shipped column-shift defect', () {
    // This is the single assertion that fails loudly on the bug that shipped
    // (3.9 dB/100 ft) and survives either resolution of the 6.615-vs-6.8
    // question (equation at exactly 2400 MHz vs the datasheet's 2500 MHz row).
    // Brief §5: "Ship this one today."
    test('LMR-400 at 2400 MHz is strictly between 6.0 and 7.0 dB/100 ft', () {
      final double? v = CableLossScreen.cableLossPer100ft('LMR-400', 2400);
      expect(v, isNotNull);
      expect(
        v!,
        greaterThan(6.0),
        reason: 'A value at/below 6.0 means the table has been read off by a '
            'column again (Times 900 MHz = 3.9 served at 2.4 GHz).',
      );
      expect(v, lessThan(7.0));
    });
  });

  group('Times Microwave equation — blind vectors from the datasheets', () {
    // Brief §2. Tolerance ±0.05 dB/100 ft absolute (brief §5, "app output vs
    // Times equation"), far tighter than the 41% error we are fixing and tight
    // enough to catch any coefficient transcription slip.
    const double tol = 0.05;

    // cable → { freqMHz : expected dB/100 ft }
    const Map<String, Map<int, double>> vectors = <String, Map<int, double>>{
      'LMR-100A': <int, double>{
        100: 7.265,
        450: 15.83,
        900: 22.84,
        1500: 30.07,
        2400: 38.92,
        5800: 64.10,
      },
      'LMR-200': <int, double>{
        100: 3.242,
        450: 6.956,
        900: 9.924,
        1500: 12.92,
        2400: 16.51,
        5800: 26.35,
      },
      'LMR-400': <int, double>{
        100: 1.249,
        450: 2.711,
        900: 3.903,
        1500: 5.126,
        2400: 6.615,
        5800: 10.82,
      },
      'LMR-600': <int, double>{
        100: 0.7815,
        450: 1.720,
        900: 2.501,
        1500: 3.316,
        2400: 4.325,
        5800: 7.262,
      },
      'LMR-900': <int, double>{
        100: 0.5337,
        450: 1.170,
        900: 1.697,
        1500: 2.245,
        2400: 2.920,
        5800: 4.871,
      },
      // LMR-1200 REMOVED 2026-07-11 (Keith's call). It used to be pinned here,
      // including an equation-derived 3.774 dB/100 ft at 5800 MHz that this very
      // file flagged as "NOT tabulated by Times". The flag was right and the
      // number was wrong: the real figure is ~4.7-5.5, so the equation
      // under-predicts by 25-45% — and in the flattering direction, the same
      // failure mode as the column-shifted table this whole rewrite replaced.
      //
      // Times tabulates every other LMR to 5800 MHz and stops LMR-1200 at 2500.
      // That is not an oversight: the two-term model extrapolates badly for a
      // cable that large as the cross-section approaches mode cutoff. And nobody
      // runs LMR-1200 at 6 GHz anyway (outdoor 6 GHz standard-power needs AFC;
      // low-power is indoor-only), so the disputed value served no real use case.
      //
      // Shipping it would have introduced a brand-new wrong number on the same
      // day we fixed the old ones. The cable is gone; see audit_wave_2_test.dart
      // for the guards that keep it gone.
    };

    for (final MapEntry<String, Map<int, double>> cable in vectors.entries) {
      for (final MapEntry<int, double> point in cable.value.entries) {
        test('${cable.key} @ ${point.key} MHz = ${point.value} dB/100ft', () {
          expect(
            CableLossScreen.cableLossPer100ft(cable.key, point.key.toDouble()),
            closeTo(point.value, tol),
          );
        });
      }
    }
  });

  group('Equation agrees with the datasheet TABLE where Times tabulates', () {
    // Brief §1: "at every frequency the datasheet tabulates, the equation
    // reproduces the tabulated value to within the datasheet's own 0.1 dB
    // rounding." Tolerance ±0.1 (brief §5, "app output vs datasheet table").
    // This is the cross-check that the equation is not a private invention.
    const double tol = 0.1;

    test('LMR-400 reproduces its published 11-column table', () {
      // Times LMR-400 datasheet, p.23.
      const Map<int, double> table = <int, double>{
        30: 0.7,
        50: 0.9,
        150: 1.5,
        220: 1.9,
        450: 2.7,
        900: 3.9,
        1500: 5.1,
        1800: 5.7,
        2000: 6.0,
        2500: 6.8, // ← Keith's confirmed number, at the datasheet's own row.
        5800: 10.8,
      };
      table.forEach((int f, double expected) {
        expect(
          CableLossScreen.cableLossPer100ft('LMR-400', f.toDouble()),
          closeTo(expected, tol),
          reason: 'LMR-400 @ $f MHz',
        );
      });
    });

    test('the 900 MHz row really is 3.9 — the value the bug served at 2.4 GHz',
        () {
      // Pins the mechanism of the original defect so it can never be
      // reintroduced silently: 3.9 is a REAL Times number, just at 900 MHz.
      expect(
        CableLossScreen.cableLossPer100ft('LMR-400', 900),
        closeTo(3.9, 0.1),
      );
      // ...and it is emphatically NOT the 2.4 GHz value.
      expect(
        CableLossScreen.cableLossPer100ft('LMR-400', 2400),
        isNot(closeTo(3.9, 0.5)),
      );
    });
  });

  group('Equation properties (structural, not curve-fitted)', () {
    test('loss increases strictly with frequency for every cable', () {
      for (final String cable in CableLossScreen.cableTypes) {
        double prev = -1;
        for (final int f in <int>[100, 450, 900, 1500, 2400, 5800]) {
          final double v =
              CableLossScreen.cableLossPer100ft(cable, f.toDouble())!;
          expect(v, greaterThan(prev), reason: '$cable @ $f MHz');
          prev = v;
        }
      }
    });

    test('thicker cable loses less at 2.4 GHz (strict ordering)', () {
      // Brief §3. The LMR family is listed thinnest → thickest.
      double prev = double.infinity;
      for (final String cable in CableLossScreen.cableTypes) {
        final double v = CableLossScreen.cableLossPer100ft(cable, 2400)!;
        expect(v, lessThan(prev), reason: cable);
        prev = v;
      }
    });

    test('the equation is evaluated, not interpolated between knots', () {
      // A frequency nobody tabulates (3175 MHz) must still return the exact
      // equation value, not a linear blend of neighbouring table rows.
      const double k1 = 0.122290;
      const double k2 = 0.000260;
      const double f = 3175;
      expect(
        CableLossScreen.cableLossPer100ft('LMR-400', f),
        closeTo(k1 * math.sqrt(f) + k2 * f, 1e-9),
      );
    });

    test('coefficients match the Times datasheets exactly', () {
      const Map<String, (double, double)> expected = <String, (double, double)>{
        'LMR-100A': (0.709140, 0.001740),
        'LMR-200': (0.320900, 0.000330),
        'LMR-400': (0.122290, 0.000260),
        'LMR-600': (0.075550, 0.000260),
        'LMR-900': (0.051770, 0.000160),
        // No LMR-1200: the coefficients are removed along with the cable, so a
        // dead value cannot be resurrected by re-adding one line to the picker.
      };
      expect(CableLossScreen.cableCoefficients.length, expected.length);
      expected.forEach((String cable, (double, double) kv) {
        final (double k1, double k2) = CableLossScreen.cableCoefficients[cable]!;
        expect(k1, closeTo(kv.$1, 1e-12), reason: '$cable k1');
        expect(k2, closeTo(kv.$2, 1e-12), reason: '$cable k2');
      });
    });

    test('unknown cable type returns null (no crash, no guess)', () {
      expect(CableLossScreen.cableLossPer100ft('NOT-A-CABLE', 2400), isNull);
    });
  });

  group('RG types are GONE — "RG" is not one cable', () {
    // Keith's call. Belden 8259 and Belden 9201 are BOTH stamped RG-58 and
    // differ by 54% at 900 MHz, and no manufacturer publishes RG attenuation at
    // Wi-Fi frequencies (Belden's tables stop at 1000 MHz). Every number the app
    // previously showed for an RG type at 2.4 GHz was invented. Brief §6.
    test('no RG type is offered in the picker', () {
      for (final String rg in <String>['RG-58', 'RG-8/U', 'RG-213', 'RG-214']) {
        expect(
          CableLossScreen.cableTypes,
          isNot(contains(rg)),
          reason: '$rg must not be selectable — see brief §6.',
        );
      }
    });

    test('an RG type returns null rather than a fabricated number', () {
      for (final String rg in <String>['RG-58', 'RG-8/U', 'RG-213', 'RG-214']) {
        expect(CableLossScreen.cableLossPer100ft(rg, 2400), isNull, reason: rg);
      }
    });

    test('the picker holds exactly the five LMR cables, LMR-400 default', () {
      // FIVE, not six. Every one is tabulated by Times out to 5800 MHz, so the
      // equation is only ever evaluated inside its validated range. LMR-1200 was
      // the sole exception and is removed — see the vectors block above.
      expect(CableLossScreen.cableTypes, <String>[
        'LMR-100A',
        'LMR-200',
        'LMR-400',
        'LMR-600',
        'LMR-900',
      ]);
      expect(CableLossScreen.defaultCable, 'LMR-400');
    });
  });

  group('Total loss + unit normalization', () {
    test('GHz converts to MHz at 1000x', () {
      expect(
          CableLossScreen.freqToMHz(2.4, CableFreqUnit.ghz), closeTo(2400, 1e-9));
      expect(
          CableLossScreen.freqToMHz(900, CableFreqUnit.mhz), closeTo(900, 1e-9));
    });

    test('metres convert to feet at 3.28084 ft/m', () {
      expect(CableLossScreen.lengthToFeet(10, CableLengthUnit.m),
          closeTo(32.8084, 1e-9));
      expect(
          CableLossScreen.lengthToFeet(25, CableLengthUnit.ft), closeTo(25, 1e-9));
    });

    test('LMR-400 at 2.4 GHz over 25 ft is 1.654 dB (was 0.975 on the bug)', () {
      final double per100 = CableLossScreen.cableLossPer100ft('LMR-400', 2400)!;
      final double lenFt = CableLossScreen.lengthToFeet(25, CableLengthUnit.ft);
      // 6.615 × 25 / 100 = 1.654 dB. The bug reported 0.975 dB — a link budget
      // short by 0.68 dB on a 25 ft jumper, and by 2.7 dB on a 100 ft run.
      expect(CableLossScreen.totalLossDb(per100, lenFt), closeTo(1.654, 0.02));
    });

    test('a 100 ft LMR-400 run at 2.4 GHz loses the full per-100ft figure', () {
      final double per100 = CableLossScreen.cableLossPer100ft('LMR-400', 2400)!;
      expect(CableLossScreen.totalLossDb(per100, 100), closeTo(per100, 1e-12));
    });
  });

  group('CableLossScreen widget', () {
    testWidgets('renders title, input labels, and result unit', (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const CableLossScreen()),
        );

        expect(find.text('Cable Loss'), findsWidgets);
        expect(find.text('Cable type'), findsOneWidget);
        expect(find.text('Frequency'), findsOneWidget);
        expect(find.text('Cable length'), findsOneWidget);
        expect(find.text('Total cable loss'), findsOneWidget);
        expect(find.byType(TextField), findsNWidgets(2));
      });
    });

    testWidgets('cable-type selector is the shared AppSelect, default LMR-400',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const CableLossScreen()),
        );

        expect(find.byType(AppSelect<String>), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AppSelect<String>),
            matching: find.text('LMR-400'),
          ),
          findsOneWidget,
        );
      });
    });

    testWidgets('typing 2.4 GHz / 25 ft renders the corrected dB result',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const CableLossScreen()),
        );

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '2.4'); // GHz default
        await tester.enterText(fields.at(1), '25'); // ft default, LMR-400
        await tester.pump();

        // 6.6150 × 25 / 100 = 1.6537 → "1.65".
        expect(find.text('1.65'), findsOneWidget);
        // Per-100ft coefficient at 2.4 GHz for LMR-400 → "6.61".
        expect(find.text('6.61'), findsOneWidget);
        // The shipped bug's numbers must be nowhere on screen.
        expect(find.text('0.97'), findsNothing);
        expect(find.text('3.90'), findsNothing);
      });
    });

    testWidgets('clearing an input blanks the result to a dash', (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const CableLossScreen()),
        );

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '2.4');
        await tester.enterText(fields.at(1), '25');
        await tester.pump();
        expect(find.text('1.65'), findsOneWidget);

        await tester.enterText(fields.at(1), '');
        await tester.pump();
        expect(find.text('1.65'), findsNothing);
        expect(find.text('—'), findsNWidgets(2));
      });
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
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
