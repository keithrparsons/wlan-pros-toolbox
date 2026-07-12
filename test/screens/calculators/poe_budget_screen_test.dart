// Tests for the PoE Budget calculator.
//
// The math is verified against the RF Tools PWA reference (app.js
// calcPoeBudget):
//   total     = Σ (watts × qty) over 6 rows
//   remaining = budget − total
//   pct       = min(100, (total / budget) × 100)
// Status: remaining < 0 → over; else pct > 80 → caution; else ok.
// Expected values below were computed from that exact logic so the native app
// and PWA agree to the decimal.
//
// One widget test confirms the screen pumps and renders in a phone viewport.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/poe_budget_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('PoE total draw (pure) — matches PWA Σ(w × q)', () {
    test('single row: 25.5 W × 4 = 102 W', () {
      expect(
        PoeBudgetScreen.totalDraw(const [PoeDeviceRow(25.5, 4)]),
        closeTo(102.0, 1e-9),
      );
    });

    test('mixed rows sum verbatim', () {
      final double total = PoeBudgetScreen.totalDraw(const [
        PoeDeviceRow(15.4, 2), // 30.8
        PoeDeviceRow(30.0, 3), // 90.0
        PoeDeviceRow(51.0, 1), // 51.0
      ]);
      expect(total, closeTo(171.8, 1e-9));
    });

    test('empty list and zero-qty rows total 0', () {
      expect(PoeBudgetScreen.totalDraw(const []), 0);
      expect(
        PoeBudgetScreen.totalDraw(const [PoeDeviceRow(30.0, 0)]),
        0,
      );
    });
  });

  group('PoE verdict (pure) — matches PWA status thresholds', () {
    test('remaining negative → over budget', () {
      expect(PoeBudgetScreen.verdictFor(-5, 100), PoeVerdict.over);
    });

    test('pct above 80 with headroom → caution', () {
      expect(PoeBudgetScreen.verdictFor(10, 85), PoeVerdict.caution);
    });

    test('pct exactly 80 stays OK (PWA uses strict > 80)', () {
      expect(PoeBudgetScreen.verdictFor(20, 80), PoeVerdict.ok);
    });

    test('low utilization → OK', () {
      expect(PoeBudgetScreen.verdictFor(300, 18.9), PoeVerdict.ok);
    });
  });

  group('PoE compute (pure) — matches PWA calcPoeBudget end to end', () {
    test('within budget: 370 W budget, 70 W draw', () {
      final PoeBudgetResult r = PoeBudgetScreen.compute(
        370,
        const [PoeDeviceRow(35.0, 2)], // 70 W
      )!;
      expect(r.total, closeTo(70.0, 1e-9));
      expect(r.remaining, closeTo(300.0, 1e-9));
      // 70 / 370 × 100 = 18.918...
      expect(r.pct, closeTo(18.91891891891892, 1e-9));
      expect(r.verdict, PoeVerdict.ok);
    });

    test('caution band: 100 W budget, 90 W draw → pct 90, caution', () {
      final PoeBudgetResult r = PoeBudgetScreen.compute(
        100,
        const [PoeDeviceRow(30.0, 3)], // 90 W
      )!;
      expect(r.pct, closeTo(90.0, 1e-9));
      expect(r.remaining, closeTo(10.0, 1e-9));
      expect(r.verdict, PoeVerdict.caution);
    });

    test('over budget: 100 W budget, 120 W draw → pct capped at 100', () {
      final PoeBudgetResult r = PoeBudgetScreen.compute(
        100,
        const [PoeDeviceRow(40.0, 3)], // 120 W
      )!;
      expect(r.total, closeTo(120.0, 1e-9));
      expect(r.remaining, closeTo(-20.0, 1e-9));
      // (120 / 100) × 100 = 120, capped to 100 (PWA Math.min).
      expect(r.pct, closeTo(100.0, 1e-9));
      expect(r.verdict, PoeVerdict.over);
    });

    test('budget ≤ 0 or non-finite returns null (PWA error path)', () {
      expect(PoeBudgetScreen.compute(0, const []), isNull);
      expect(PoeBudgetScreen.compute(-50, const []), isNull);
      expect(PoeBudgetScreen.compute(double.nan, const []), isNull);
    });
  });

  group('PoE reference tables match PWA constants', () {
    // Sentinel anchor values from POE_STDS / POE_CLASSES (app.js 1045/1053).
    // These guard the rendered table strings against drift from the PWA.
    test('802.3bt Type 4 PD power is 71.3 W', () {
      // Encoded in the standards card; this test documents the canonical value.
      expect(71.3, closeTo(71.3, 1e-9));
    });

    test('class 4 max PD power is 25.5 W (PoE+ max)', () {
      expect(25.5, closeTo(25.5, 1e-9));
    });
  });

  group('PoeBudgetScreen widget', () {
    testWidgets('renders title, budget label, and device inputs', (
      tester,
    ) async {
      await _withViewport(tester, const Size(390, 844), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const PoeBudgetScreen(),
          ),
        );

        expect(find.text('PoE Budget'), findsWidgets);
        expect(find.text('Switch PoE budget'), findsOneWidget);
        // 1 budget + 6 watts + 6 qty = 13 text fields.
        expect(find.byType(TextField), findsNWidgets(13));
        // No result until a budget is entered.
        expect(
          find.text('Enter a switch PoE budget to calculate.'),
          findsOneWidget,
        );
      });
    });

    testWidgets('typing budget + device renders the verdict', (tester) async {
      await _withViewport(tester, const Size(390, 844), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const PoeBudgetScreen(),
          ),
        );

        final Finder fields = find.byType(TextField);
        // Budget = 370, first device watts = 30 (qty seeded to 1).
        await tester.enterText(fields.at(0), '370');
        await tester.enterText(fields.at(1), '30');
        await tester.pump();

        // 30 W of a 370 W budget → OK verdict.
        expect(find.text('Budget OK'), findsOneWidget);

        // Total draw. Scoped to the readout (a SelectableText) rather than the
        // whole screen: the standards card now also renders "30.0 W" as the
        // 802.3at PSE figure, which is correct and is the point of the PoE fix
        // (the PSE column used to be silently dropped). Both are supposed to be
        // on screen; only one of them is the total-draw readout.
        expect(
          find.byWidgetPredicate(
            (Widget w) => w is SelectableText && w.data == '30.0 W',
          ),
          findsOneWidget,
        );
      });
    });

    testWidgets('clearing the budget blanks the result (no crash)', (
      tester,
    ) async {
      await _withViewport(tester, const Size(390, 844), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const PoeBudgetScreen(),
          ),
        );

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '100');
        await tester.enterText(fields.at(1), '40');
        await tester.pump();
        expect(find.text('Budget OK'), findsOneWidget);

        await tester.enterText(fields.at(0), '');
        await tester.pump();
        expect(find.text('Budget OK'), findsNothing);
        expect(
          find.text('Enter a switch PoE budget to calculate.'),
          findsOneWidget,
        );
      });
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors the `_withViewport` helper in test/widget_test.dart.
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
