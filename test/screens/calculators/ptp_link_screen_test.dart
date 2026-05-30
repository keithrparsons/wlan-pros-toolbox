// Tests for the Point-to-Point (PtP) Link Check calculator.
//
// The math is verified against the RF Tools PWA reference (app.js calcPtP):
//   eirp     = txPow + txGain - txLoss
//   fspl     = 20·log10(d_km) + 20·log10(f_GHz) + 92.45
//   rainFade = γ · L_eff   (0 when rainRate == 0; ITU-R P.838-3 + P.530)
//   rxLevel  = eirp - fspl - rainFade + rxGain - rxLoss
//   margin   = rxLevel - rxSens
//   pass     = margin >= reqMargin
// Expected values below were computed from that exact formula so the native app
// and PWA agree to the decimal.
//
// One widget test (phone viewport) confirms the screen pumps, renders its
// required inputs, and produces a status verdict on valid input.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ptp_link_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('PtP unit normalization — matches PWA toKm', () {
    test('miles convert to km, km passes through', () {
      expect(PtpLinkScreen.distToKm(1, PtpDistUnit.mi), closeTo(1.60934, 1e-12));
      expect(PtpLinkScreen.distToKm(5, PtpDistUnit.km), 5);
    });
  });

  group('PtP FSPL leg — matches PWA calcFSPL form', () {
    test('1 GHz at 1 km equals the 92.45 anchor', () {
      expect(PtpLinkScreen.fsplDb(1, 1), closeTo(92.45, 1e-9));
    });

    test('5.8 GHz at 5 km', () {
      expect(PtpLinkScreen.fsplDb(5.8, 5), closeTo(121.69795995797912, 1e-9));
    });
  });

  group('PtP rain fade — matches PWA ITU-R P.838-3 + P.530 block', () {
    test('rain rate 0 yields exactly 0 fade (PWA rainRate > 0 guard)', () {
      expect(
        PtpLinkScreen.rainFadeDb(11, 0, 10, PtpPolarization.horizontal),
        0,
      );
    });

    test('11 GHz, 25 mm/hr horizontal, 10 km', () {
      expect(
        PtpLinkScreen.rainFadeDb(11, 25, 10, PtpPolarization.horizontal),
        closeTo(5.433266342756117, 1e-9),
      );
    });

    test('vertical polarization differs from horizontal', () {
      final double h =
          PtpLinkScreen.rainFadeDb(11, 25, 10, PtpPolarization.horizontal);
      final double v =
          PtpLinkScreen.rainFadeDb(11, 25, 10, PtpPolarization.vertical);
      expect(h, isNot(closeTo(v, 1e-6)));
    });
  });

  group('PtP link budget — matches PWA calcPtP end to end', () {
    test('clear-air 5.8 GHz / 5 km PASS link', () {
      final PtpResult r = PtpLinkScreen.linkBudget(
        freqGHz: 5.8,
        distKm: 5,
        txPow: 20,
        txGain: 23,
        rxGain: 23,
        txLoss: 1,
        rxLoss: 1,
        rainRateMmHr: 0,
        pol: PtpPolarization.horizontal,
        rxSens: -80,
        requiredMargin: 10,
      );
      expect(r.eirp, closeTo(42, 1e-9));
      expect(r.fspl, closeTo(121.69795995797912, 1e-9));
      expect(r.rainFade, 0);
      expect(r.rxLevel, closeTo(-57.69795995797912, 1e-9));
      expect(r.margin, closeTo(22.302040042020877, 1e-9));
      expect(r.pass, isTrue);
    });

    test('rain leg 11 GHz / 10 km still PASS at -75 dBm sensitivity', () {
      final PtpResult r = PtpLinkScreen.linkBudget(
        freqGHz: 11,
        distKm: 10,
        txPow: 20,
        txGain: 23,
        rxGain: 23,
        txLoss: 0,
        rxLoss: 0,
        rainRateMmHr: 25,
        pol: PtpPolarization.horizontal,
        rxSens: -75,
        requiredMargin: 10,
      );
      expect(r.rainFade, closeTo(5.433266342756117, 1e-9));
      // margin ~2.29 dB: link closes but below the 10 dB required → not pass.
      expect(r.margin, closeTo(2.288879954079377, 1e-9));
      expect(r.pass, isFalse);
    });

    test('long 24 GHz / 20 km link FAILS (negative margin)', () {
      final PtpResult r = PtpLinkScreen.linkBudget(
        freqGHz: 24,
        distKm: 20,
        txPow: 10,
        txGain: 15,
        rxGain: 15,
        txLoss: 0,
        rxLoss: 0,
        rainRateMmHr: 0,
        pol: PtpPolarization.horizontal,
        rxSens: -70,
        requiredMargin: 10,
      );
      expect(r.fspl, closeTo(146.07482474751174, 1e-9));
      expect(r.margin, closeTo(-36.07482474751174, 1e-9));
      expect(r.pass, isFalse);
    });
  });

  group('PtP verdict banding — thresholds owned by the calculator', () {
    test('margin >= required → pass', () {
      expect(PtpLinkScreen.verdictFor(12, 10), PtpVerdict.pass);
      expect(PtpLinkScreen.verdictFor(10, 10), PtpVerdict.pass);
    });

    test('0 <= margin < required → marginal', () {
      expect(PtpLinkScreen.verdictFor(5, 10), PtpVerdict.marginal);
      expect(PtpLinkScreen.verdictFor(0, 10), PtpVerdict.marginal);
    });

    test('margin < 0 → fail', () {
      expect(PtpLinkScreen.verdictFor(-0.1, 10), PtpVerdict.fail);
      expect(PtpLinkScreen.verdictFor(-30, 10), PtpVerdict.fail);
    });
  });

  group('PtpLinkScreen widget (phone viewport)', () {
    testWidgets('renders title, required labels, and a neutral placeholder',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const PtpLinkScreen(),
          ),
        );

        expect(find.text('PtP Link Check'), findsWidgets);
        expect(find.text('Frequency'), findsOneWidget);
        expect(find.text('Distance'), findsOneWidget);
        expect(find.text('Tx power'), findsOneWidget);
        expect(find.text('Receiver sensitivity'), findsOneWidget);
        expect(find.text('Required fade margin'), findsOneWidget);
        // Cold start: margin readout is the em-free dash, no verdict word yet.
        expect(find.text('—'), findsWidgets);
        expect(find.text('PASS'), findsNothing);
      });
    });

    testWidgets('typing a valid PASS link renders the verdict and margin',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const PtpLinkScreen(),
          ),
        );

        // Field order matches the build: freq, dist, txPow, txGain, rxGain,
        // txLoss, rxLoss, rain, sensitivity, reqMargin.
        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '5.8'); // freq GHz
        await tester.enterText(fields.at(1), '5'); // dist km
        await tester.enterText(fields.at(2), '20'); // tx power dBm
        await tester.enterText(fields.at(3), '23'); // tx gain dBi
        await tester.enterText(fields.at(4), '23'); // rx gain dBi
        await tester.enterText(fields.at(5), '1'); // tx loss dB
        await tester.enterText(fields.at(6), '1'); // rx loss dB
        await tester.enterText(fields.at(8), '-80'); // sensitivity dBm
        await tester.pump();

        // margin 22.3 dB ≥ 10 dB default required → PASS.
        expect(find.text('PASS'), findsOneWidget);
        expect(find.text('22.3'), findsOneWidget);
        // EIRP 42.0 dBm row renders.
        expect(find.text('42.0'), findsOneWidget);
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
