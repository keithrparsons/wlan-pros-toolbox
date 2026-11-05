// Tests for the Link Budget calculator.
//
// The math is verified against the RF Tools PWA reference (app.js
// calcLinkBudget):
//   rx_dbm = Tx + Gtx - Ltx - FSPL - Lrx + Grx - misc
//   margin = rx_dbm - sensitivity
// with TX-power normalization via wattsTodBm (W → 10·log10(txp·1000),
// mW → 10·log10(txp)). Expected values below were computed from that exact
// formula so the native app and PWA agree to the decimal.
//
// FSPL from frequency and distance is checked against the FSPL tool's own
// known values (fspl_screen_test.dart), and EIRP against the EIRP tool's
// (eirp_screen_test.dart), because the screen calls those tools' functions.
//
// Widget tests confirm the screen pumps, the manual FSPL override wins and is
// marked, and the distance follows the app-wide metric / imperial setting.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eirp_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/link_budget_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/units/length_format.dart';
import 'package:wlan_pros_toolbox/units/unit_system.dart';

// Text field order on the screen: 0 TX power, 1 TX gain, 2 TX loss,
// 3 frequency, 4 distance, 5 FSPL, 6 other losses, 7 RX loss, 8 RX gain,
// 9 RX sensitivity.
const int _fTxPower = 0, _fTxGain = 1, _fTxLoss = 2, _fFreq = 3, _fDist = 4;
const int _fFspl = 5, _fRxLoss = 7, _fRxGain = 8, _fRxSens = 9;

void main() {
  group('Link budget math (pure) — matches PWA app.js calcLinkBudget', () {
    test('PWA placeholder example: +23 dBm link closes with 10 dB margin', () {
      // Tx 23, Gtx 14, Ltx 1.5, FSPL 120, Lrx 1.5, Grx 14, misc 0.
      final double rx = LinkBudgetScreen.receivedDbm(
        txPowerDbm: 23,
        txGain: 14,
        txLoss: 1.5,
        pathLoss: 120,
        rxLoss: 1.5,
        rxGain: 14,
        misc: 0,
      );
      expect(rx, closeTo(-72.0, 1e-9));
      // Sensitivity -82 → margin = -72 - (-82) = 10.
      expect(LinkBudgetScreen.linkMarginDb(rx, -82), closeTo(10.0, 1e-9));
    });

    test('other losses subtract directly from the received signal', () {
      final double rxNoMisc = LinkBudgetScreen.receivedDbm(
        txPowerDbm: 23,
        txGain: 14,
        txLoss: 1.5,
        pathLoss: 120,
        rxLoss: 1.5,
        rxGain: 14,
        misc: 0,
      );
      final double rxMisc = LinkBudgetScreen.receivedDbm(
        txPowerDbm: 23,
        txGain: 14,
        txLoss: 1.5,
        pathLoss: 120,
        rxLoss: 1.5,
        rxGain: 14,
        misc: 6,
      );
      expect(rxNoMisc - rxMisc, closeTo(6.0, 1e-9));
    });

    test('negative margin when path loss exceeds the budget', () {
      final double rx = LinkBudgetScreen.receivedDbm(
        txPowerDbm: 20,
        txGain: 3,
        txLoss: 0,
        pathLoss: 130,
        rxLoss: 0,
        rxGain: 3,
        misc: 0,
      );
      // rx = 20 + 3 - 130 + 3 = -104.
      expect(rx, closeTo(-104.0, 1e-9));
      // Sensitivity -90 → margin = -104 - (-90) = -14.
      expect(LinkBudgetScreen.linkMarginDb(rx, -90), closeTo(-14.0, 1e-9));
    });
  });

  group('TX power normalization — matches PWA wattsTodBm branch', () {
    test('dBm passes through unchanged', () {
      expect(LinkBudgetScreen.txPowerToDbm(23, TxPowerUnit.dbm), 23);
    });

    test('1 W equals 30 dBm', () {
      expect(
        LinkBudgetScreen.txPowerToDbm(1, TxPowerUnit.w),
        closeTo(30.0, 1e-9),
      );
    });

    test('0.1 W equals 20 dBm', () {
      expect(
        LinkBudgetScreen.txPowerToDbm(0.1, TxPowerUnit.w),
        closeTo(20.0, 1e-9),
      );
    });

    test('100 mW equals 20 dBm (PWA divides mW by 1000 first)', () {
      expect(
        LinkBudgetScreen.txPowerToDbm(100, TxPowerUnit.mw),
        closeTo(20.0, 1e-9),
      );
    });

    test('1000 mW equals 1 W equals 30 dBm', () {
      expect(
        LinkBudgetScreen.txPowerToDbm(1000, TxPowerUnit.mw),
        closeTo(LinkBudgetScreen.txPowerToDbm(1, TxPowerUnit.w), 1e-9),
      );
    });

    test('non-positive watts give a non-finite dBm (caught as invalid)', () {
      expect(LinkBudgetScreen.txPowerToDbm(0, TxPowerUnit.w).isFinite, isFalse);
    });
  });

  group('Margin health — matches PWA color thresholds', () {
    test('10 dB and above is healthy', () {
      expect(LinkBudgetScreen.marginHealth(10), MarginHealth.healthy);
      expect(LinkBudgetScreen.marginHealth(25), MarginHealth.healthy);
    });

    test('0 to just under 10 dB is marginal', () {
      expect(LinkBudgetScreen.marginHealth(0), MarginHealth.marginal);
      expect(LinkBudgetScreen.marginHealth(9.9), MarginHealth.marginal);
    });

    test('below 0 dB is negative', () {
      expect(LinkBudgetScreen.marginHealth(-0.1), MarginHealth.negative);
      expect(LinkBudgetScreen.marginHealth(-20), MarginHealth.negative);
    });
  });

  group('FSPL from frequency and distance — the FSPL tool\'s values', () {
    test('2400 MHz at 1000 m is the FSPL tool\'s 2.4 GHz / 1 km value', () {
      expect(
        LinkBudgetScreen.fsplFromInputs(freqMhz: 2400, distanceMetres: 1000),
        closeTo(100.05422483423212, 1e-9),
      );
    });

    test('5000 MHz at 1000 m is the FSPL tool\'s 5 GHz / 1 km value', () {
      expect(
        LinkBudgetScreen.fsplFromInputs(freqMhz: 5000, distanceMetres: 1000),
        closeTo(106.42940008672038, 1e-9),
      );
    });

    test('2400 MHz at 100 m is 20 dB less than at 1 km', () {
      expect(
        LinkBudgetScreen.fsplFromInputs(freqMhz: 2400, distanceMetres: 100),
        closeTo(80.05422483423212, 1e-9),
      );
    });

    test('same function as the FSPL tool, for an arbitrary case', () {
      expect(
        LinkBudgetScreen.fsplFromInputs(freqMhz: 5785, distanceMetres: 2300),
        closeTo(
          FsplScreen.fsplDb(
            FsplScreen.freqToGHz(5785, FreqUnit.mhz),
            FsplScreen.distToKm(2300, DistUnit.m),
          ),
          1e-12,
        ),
      );
    });

    test('feet go through the exact international foot', () {
      // 1000 ft = 304.8 m.
      const LengthFormat ft = LengthFormat(UnitSystem.imperial);
      expect(ft.distToMetres(1000), closeTo(304.8, 1e-9));
      expect(
        LinkBudgetScreen.fsplFromInputs(
          freqMhz: 2400,
          distanceMetres: ft.distToMetres(1000),
        ),
        closeTo(FsplScreen.fsplDb(2.4, 0.3048), 1e-9),
      );
    });

    test('zero or negative frequency or distance gives no FSPL', () {
      expect(
        LinkBudgetScreen.fsplFromInputs(freqMhz: 0, distanceMetres: 100),
        isNull,
      );
      expect(
        LinkBudgetScreen.fsplFromInputs(freqMhz: 2400, distanceMetres: 0),
        isNull,
      );
      expect(
        LinkBudgetScreen.fsplFromInputs(freqMhz: -5, distanceMetres: 100),
        isNull,
      );
    });
  });

  group('FSPL override (pure)', () {
    test('a manual value wins over the calculated one', () {
      expect(
        LinkBudgetScreen.effectivePathLoss(manual: 120, calculated: 100.05),
        120,
      );
    });

    test('with no manual value the calculated one is used', () {
      expect(
        LinkBudgetScreen.effectivePathLoss(manual: null, calculated: 100.05),
        100.05,
      );
    });

    test('neither gives none', () {
      expect(LinkBudgetScreen.effectivePathLoss(), isNull);
    });
  });

  group('EIRP — the EIRP tool\'s function', () {
    test('20 dBm + 14 dBi − 1.5 dB = 32.5 dBm (the EIRP tool\'s example)', () {
      expect(
        LinkBudgetScreen.eirpDbm(txPowerDbm: 20, txGain: 14, txLoss: 1.5),
        closeTo(32.5, 1e-9),
      );
    });

    test('negative power and gain: −10 dBm + 2 dBi − 0 dB = −8 dBm', () {
      expect(
        LinkBudgetScreen.eirpDbm(txPowerDbm: -10, txGain: 2, txLoss: 0),
        closeTo(-8.0, 1e-9),
      );
    });

    test('matches EirpScreen.eirpDbm for W input normalized to dBm', () {
      final double txDbm = LinkBudgetScreen.txPowerToDbm(1, TxPowerUnit.w);
      expect(
        LinkBudgetScreen.eirpDbm(txPowerDbm: txDbm, txGain: 6, txLoss: 1),
        closeTo(
          EirpScreen.eirpDbm(
            power: 1,
            unit: EirpPowerUnit.w,
            lossDb: 1,
            gainDbi: 6,
          )!,
          1e-9,
        ),
      );
    });
  });

  group('LinkBudgetScreen widget', () {
    testWidgets('renders title, section headers, and result labels', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark(), home: const LinkBudgetScreen()),
      );

      expect(find.text('Link Budget'), findsWidgets);
      expect(find.text('Transmitter'), findsOneWidget);
      expect(find.text('Path'), findsOneWidget);
      expect(find.text('Receiver'), findsOneWidget);
      expect(find.text('TX Power'), findsOneWidget);
      expect(find.text('RX Sensitivity'), findsOneWidget);
      expect(find.text('Received signal'), findsOneWidget);
      expect(find.text('Link margin'), findsOneWidget);
      // Ten numeric inputs across the three sections.
      expect(find.byType(TextField), findsNWidgets(10));
      expect(find.text('Frequency'), findsOneWidget);
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('EIRP'), findsOneWidget);
    });

    testWidgets('filling every required field renders both finite outputs', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark(), home: const LinkBudgetScreen()),
      );

      final Finder fields = find.byType(TextField);
      // FSPL typed directly: the manual path, as before frequency and distance.
      await tester.enterText(fields.at(_fTxPower), '23');
      await tester.enterText(fields.at(_fTxGain), '14');
      await tester.enterText(fields.at(_fTxLoss), '1.5');
      await tester.enterText(fields.at(_fFspl), '120');
      // skip misc (optional, defaults to 0)
      await tester.enterText(fields.at(_fRxLoss), '1.5');
      await tester.enterText(fields.at(_fRxGain), '14');
      await tester.enterText(fields.at(_fRxSens), '-82');
      await tester.pump();

      // RX = -72.0 dBm, margin = 10.0 dB at 1-decimal PWA formatting.
      expect(find.text('-72.0'), findsOneWidget);
      expect(find.text('10.0'), findsOneWidget);
    });

    testWidgets('a missing required field blanks both outputs to a dash', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark(), home: const LinkBudgetScreen()),
      );

      final Finder fields = find.byType(TextField);
      await tester.enterText(fields.at(_fTxPower), '23');
      await tester.enterText(fields.at(_fTxGain), '14');
      await tester.enterText(fields.at(_fTxLoss), '1.5');
      await tester.enterText(fields.at(_fFspl), '120');
      await tester.enterText(fields.at(_fRxLoss), '1.5');
      await tester.enterText(fields.at(_fRxGain), '14');
      await tester.enterText(fields.at(_fRxSens), '-82');
      await tester.pump();
      expect(find.text('10.0'), findsOneWidget);

      // Clear RX sensitivity → both outputs blank (no crash, both show a dash).
      await tester.enterText(fields.at(_fRxSens), '');
      await tester.pump();
      expect(find.text('-72.0'), findsNothing);
      expect(find.text('10.0'), findsNothing);
      expect(find.text('—'), findsNWidgets(2));
    });

    Future<void> fillTxRx(WidgetTester tester) async {
      final Finder fields = find.byType(TextField);
      await tester.enterText(fields.at(_fTxPower), '23');
      await tester.enterText(fields.at(_fTxGain), '14');
      await tester.enterText(fields.at(_fTxLoss), '1.5');
      await tester.enterText(fields.at(_fRxLoss), '1.5');
      await tester.enterText(fields.at(_fRxGain), '14');
      await tester.enterText(fields.at(_fRxSens), '-82');
    }

    testWidgets('frequency and distance calculate FSPL; a typed FSPL wins', (
      tester,
    ) async {
      await _withViewport(tester, const Size(414, 2600), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const LinkBudgetScreen()),
        );
        await fillTxRx(tester);
        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(_fFreq), '2400');
        await tester.enterText(fields.at(_fDist), '1000');
        await tester.pump();

        // FSPL 100.05 dB (calculated). RX = 23 + 14 − 1.5 − 100.054 − 1.5 + 14
        // = −52.05 dBm; margin 29.9 dB. EIRP = 23 + 14 − 1.5 = 35.5 dBm.
        expect(find.text('Free space path loss (calculated)'), findsOneWidget);
        // Once in the results; the FSPL field also shows it as its hint.
        expect(_readout('100.1'), findsOneWidget);
        expect(find.text('-52.1'), findsOneWidget);
        expect(find.text('29.9'), findsOneWidget);
        expect(find.text('35.5'), findsOneWidget);
        expect(find.textContaining('3.55 W'), findsOneWidget);

        // Override: the typed value wins, and is marked.
        await tester.enterText(fields.at(_fFspl), '120');
        await tester.pump();
        expect(find.text('Free space path loss (manual)'), findsOneWidget);
        expect(
          find.textContaining('Manual value: it overrides frequency'),
          findsOneWidget,
        );
        expect(find.text('-72.0'), findsOneWidget);
        expect(find.text('10.0'), findsOneWidget);

        // Clearing it goes back to the calculated value.
        await tester.enterText(fields.at(_fFspl), '');
        await tester.pump();
        expect(find.text('Free space path loss (calculated)'), findsOneWidget);
        expect(find.text('-52.1'), findsOneWidget);
      });
    });

    testWidgets('EIRP shows from the transmitter fields alone', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark(), home: const LinkBudgetScreen()),
      );
      final Finder fields = find.byType(TextField);
      await tester.enterText(fields.at(_fTxPower), '20');
      await tester.enterText(fields.at(_fTxGain), '14');
      await tester.enterText(fields.at(_fTxLoss), '1.5');
      await tester.pump();
      expect(find.text('32.5'), findsOneWidget);
      expect(find.textContaining('1.78 W'), findsOneWidget);
    });

    testWidgets('distance follows the app units, and a flip keeps the length', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final UnitSystemController units = UnitSystemController(
        initial: UnitSystem.imperial,
      );
      await _withViewport(tester, const Size(414, 2600), () async {
        await tester.pumpWidget(
          UnitSystemScope(
            controller: units,
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const LinkBudgetScreen(),
            ),
          ),
        );
        expect(find.text('(ft)'), findsOneWidget);
        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(_fFreq), '2400');
        await tester.enterText(fields.at(_fDist), '1000');
        await tester.pump();
        // 1000 ft = 304.8 m → FSPL 89.73 dB.
        final String expected = FsplScreen.fsplDb(
          2.4,
          0.3048,
        ).toStringAsFixed(1);
        expect(expected, '89.7');
        expect(_readout(expected), findsOneWidget);

        await units.setSystem(UnitSystem.metric);
        await tester.pump();
        expect(find.text('(m)'), findsOneWidget);
        final TextField dist = tester.widget<TextField>(fields.at(_fDist));
        expect(dist.controller!.text, '304.8');
        expect(_readout(expected), findsOneWidget, reason: 'same length');
      });
    });

    testWidgets('copy results carries frequency, distance, FSPL and EIRP', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _withViewport(tester, const Size(414, 2600), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const LinkBudgetScreen()),
        );
        await fillTxRx(tester);
        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(_fFreq), '2400');
        await tester.enterText(fields.at(_fDist), '1000');
        await tester.pump();

        await tester.tap(find.byTooltip('Copy results'));
        await tester.pump();
        expect(copied, contains('Frequency: 2400 MHz'));
        expect(copied, contains('Distance: 1000 m'));
        expect(copied, contains('Free space path loss: 100.1 dB (calculated)'));
        expect(copied, contains('EIRP: 35.5 dBm (3.55 W)'));
        expect(copied, contains('Received signal: -52.1 dBm'));
        expect(copied, contains('Link margin: 29.9 dB'));
        await tester.pump(const Duration(seconds: 2));
      });
    });
  });
}

/// A result readout (a SelectableText) showing exactly [value].
Finder _readout(String value) => find.byWidgetPredicate(
  (Widget w) => w is SelectableText && w.data == value,
);

/// Run [body] with the test view sized to [size], then restore.
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
