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
// One widget test confirms the screen pumps and renders its sections.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/link_budget_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

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
      expect(LinkBudgetScreen.txPowerToDbm(1, TxPowerUnit.w),
          closeTo(30.0, 1e-9));
    });

    test('0.1 W equals 20 dBm', () {
      expect(LinkBudgetScreen.txPowerToDbm(0.1, TxPowerUnit.w),
          closeTo(20.0, 1e-9));
    });

    test('100 mW equals 20 dBm (PWA divides mW by 1000 first)', () {
      expect(LinkBudgetScreen.txPowerToDbm(100, TxPowerUnit.mw),
          closeTo(20.0, 1e-9));
    });

    test('1000 mW equals 1 W equals 30 dBm', () {
      expect(LinkBudgetScreen.txPowerToDbm(1000, TxPowerUnit.mw),
          closeTo(LinkBudgetScreen.txPowerToDbm(1, TxPowerUnit.w), 1e-9));
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

  group('LinkBudgetScreen widget', () {
    testWidgets('renders title, section headers, and result labels',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const LinkBudgetScreen(),
        ),
      );

      expect(find.text('Link Budget'), findsWidgets);
      expect(find.text('Transmitter'), findsOneWidget);
      expect(find.text('Path'), findsOneWidget);
      expect(find.text('Receiver'), findsOneWidget);
      expect(find.text('TX Power'), findsOneWidget);
      expect(find.text('RX Sensitivity'), findsOneWidget);
      expect(find.text('Received signal'), findsOneWidget);
      expect(find.text('Link margin'), findsOneWidget);
      // Eight numeric inputs across the three sections.
      expect(find.byType(TextField), findsNWidgets(8));
    });

    testWidgets('filling every required field renders both finite outputs',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const LinkBudgetScreen(),
        ),
      );

      final Finder fields = find.byType(TextField);
      // Field order: TxPower, TxGain, TxLoss, FSPL, misc, RxLoss, RxGain, Sens.
      await tester.enterText(fields.at(0), '23');
      await tester.enterText(fields.at(1), '14');
      await tester.enterText(fields.at(2), '1.5');
      await tester.enterText(fields.at(3), '120');
      // skip misc (optional, defaults to 0)
      await tester.enterText(fields.at(5), '1.5');
      await tester.enterText(fields.at(6), '14');
      await tester.enterText(fields.at(7), '-82');
      await tester.pump();

      // RX = -72.0 dBm, margin = 10.0 dB at 1-decimal PWA formatting.
      expect(find.text('-72.0'), findsOneWidget);
      expect(find.text('10.0'), findsOneWidget);
    });

    testWidgets('a missing required field blanks both outputs to a dash',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const LinkBudgetScreen(),
        ),
      );

      final Finder fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '23');
      await tester.enterText(fields.at(1), '14');
      await tester.enterText(fields.at(2), '1.5');
      await tester.enterText(fields.at(3), '120');
      await tester.enterText(fields.at(5), '1.5');
      await tester.enterText(fields.at(6), '14');
      await tester.enterText(fields.at(7), '-82');
      await tester.pump();
      expect(find.text('10.0'), findsOneWidget);

      // Clear RX sensitivity → both outputs blank (no crash, both show a dash).
      await tester.enterText(fields.at(7), '');
      await tester.pump();
      expect(find.text('-72.0'), findsNothing);
      expect(find.text('10.0'), findsNothing);
      expect(find.text('—'), findsNWidgets(2));
    });
  });
}
